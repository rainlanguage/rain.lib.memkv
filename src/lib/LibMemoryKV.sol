// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// Entrypoint into the key/value store: a `uint256` packing the head pointers
/// of `LibMemoryKV.LIST_COUNT` internal linked lists and one word count, each
/// in its own `LibMemoryKV.SLOT_BITS` wide slot. A key belongs to list
/// `i = keccak256(key) % LIST_COUNT`, whose head pointer is the slot at bit
/// `i * SLOT_BITS` and is `0` while that list is empty, so `0` is the empty
/// store. The word count is the slot at `COUNT_BIT_OFFSET`, above the last
/// list, and counts two words per inserted pair, so `toBytes32Array` allocates
/// its `bytes32[]` in O(1). A list item is `NODE_BYTES` of memory: the key,
/// the value, then the pointer to the next item in the list, `0` after the
/// last.
///
/// A `MemoryKV` is a handle into shared memory, not a snapshot, although
/// Solidity silently copies it as a value type. Handles derived from the same
/// store share its list items, so an update is visible through every handle
/// that holds the key, including handles copied before the update, while an
/// insert is visible only through the handle `set` returned. Keep exactly one
/// live handle per store, or snapshot with `toBytes32Array`.
///
/// A handle is valid ONLY inside the call frame that created it. The pointers
/// it packs are offsets into that frame's memory. Being a `uint256` it crosses
/// an external call unchanged while the list items it names do not, so a
/// `MemoryKV` MUST NOT be returned from or passed into an external call. In
/// another frame those same offsets name whatever that frame holds at them, so
/// a read answers with unrelated memory, or follows a junk word as a pointer
/// and expands memory until the gas is gone. Cross a call boundary with
/// `toBytes32Array` instead.
type MemoryKV is uint256;

/// @dev The only valid starting value for a `MemoryKV`. A store MUST begin here
/// and MUST only ever be advanced by `set`; any other value is undefined
/// behaviour.
MemoryKV constant MEMORY_KV_EMPTY = MemoryKV.wrap(0);

/// The key associated with the value for each item in the store.
type MemoryKVKey is bytes32;

/// The value associated with the key for each item in the store.
type MemoryKVVal is bytes32;

/// @title LibMemoryKV
library LibMemoryKV {
    /// The number of internal linked lists a `MemoryKV` holds a head pointer
    /// for.
    uint256 internal constant LIST_COUNT = 15;

    /// The width in bits of one slot of a `MemoryKV`, whether it holds a head
    /// pointer or the word count.
    uint256 internal constant SLOT_BITS = 0x10;

    /// The mask of one slot, so both the widest head pointer and the widest
    /// word count a `MemoryKV` holds.
    uint256 internal constant POINTER_MASK = 0xFFFF;

    /// The bit offset of the word count's slot in a `MemoryKV`.
    uint256 internal constant COUNT_BIT_OFFSET = 0xf0;

    /// The bytes of memory `set` allocates for one list item.
    uint256 internal constant NODE_BYTES = 0x60;

    /// Thrown when an insert would allocate its node at a pointer above
    /// `POINTER_MASK`, the widest head pointer a list slot can hold.
    ///
    /// Only the head is bounded: the rest of the node MAY extend above
    /// `POINTER_MASK`, as every field is reached by full width arithmetic from
    /// the head. An update allocates nothing, so it never throws this.
    /// @param pointer The offending pointer, not the bound it crossed.
    error MemoryKVOverflow(uint256 pointer);

    /// Thrown when an insert would push the word count past `POINTER_MASK`,
    /// the widest word count its slot can hold.
    /// @param length The word count the insert would have produced, not the
    /// stored count before it and not the `POINTER_MASK` bound it crossed.
    error MemoryKVLengthOverflow(uint256 length);

    /// Gets the value associated with a given key.
    /// The value returned will be `0` if the key exists and was set to zero OR
    /// the key DOES NOT exist, i.e. was never set.
    ///
    /// The caller MUST check the `exists` flag to disambiguate between zero
    /// values and unset keys.
    ///
    /// @param kv The entrypoint to the key/value store.
    /// @param key The key to lookup a `value` for.
    /// @return exists `0` if the key was not found. The `value` MUST NOT be
    /// used if the `key` does not exist.
    /// @return value The value for the `key`, if it exists, else `0`. MAY BE `0`
    /// even if the `key` exists. It is possible to set any key to a `0` value.
    function get(MemoryKV kv, MemoryKVKey key) internal pure returns (uint256 exists, MemoryKVVal value) {
        assembly ("memory-safe") {
            // Hash to find the internal linked list to walk.
            // Hash logic MUST match set.
            mstore(0, key)
            let bitOffset := mul(mod(keccak256(0, 0x20), LIST_COUNT), SLOT_BITS)

            // Loop until key found or give up if pointer is zero.
            for { let pointer := and(shr(bitOffset, kv), POINTER_MASK) } iszero(iszero(pointer)) {
                pointer := mload(add(pointer, 0x40))
            } {
                if eq(key, mload(pointer)) {
                    exists := 1
                    value := mload(add(pointer, 0x20))
                    break
                }
            }
        }
    }

    /// Whether a key exists in the store. Equivalent to the `exists` half of
    /// `get` as a `bool`, so usable inside an expression.
    ///
    /// A key SET TO ZERO exists; existence is independent of the value.
    /// @param kv The entrypoint to the key/value store.
    /// @param key The key to look for.
    /// @return Whether the key is in the store.
    function has(MemoryKV kv, MemoryKVKey key) internal pure returns (bool) {
        (uint256 exists,) = get(kv, key);
        return exists != 0;
    }

    /// Upserts a value in the set by its key. I.e. if the key exists then the
    /// associated value will be mutated in place, else a new key/value pair will
    /// be inserted. The key/value store pointer is returned rather than mutated
    /// in place, as it MAY point to a new list item in memory.
    ///
    /// `kv` is a value, so an insert's new head pointer exists only in the
    /// return. The caller MUST assign the return back over the `kv` it passed
    /// in, or the inserted pair is discarded with no revert. A dropped return
    /// on an update path appears to work only because that pair is already
    /// reachable from the unchanged pointer, which is not a guarantee.
    ///
    /// An update writes through a shared list item, so it is visible to every
    /// handle that holds the key, including handles copied before this call. An
    /// insert is visible only through the returned handle.
    ///
    /// Reverts `MemoryKVOverflow` when an INSERT would allocate its node above
    /// `POINTER_MASK`, the widest head pointer a list slot can hold. An update
    /// allocates nothing and so never reverts. The ceiling is on the frame's
    /// free memory pointer rather than on a pair count: the node takes its
    /// address from there, so every unrelated allocation in the frame lowers
    /// how many pairs still fit, which is 682 for a frame that allocates
    /// nothing else.
    /// @param kv The key/value store pointer to modify.
    /// @param key The key to upsert against.
    /// @param value The value to associate with the upserted key.
    /// @return The final value of `kv` as it MAY be modified if the upsert
    /// resulted in an insert operation.
    function set(MemoryKV kv, MemoryKVKey key, MemoryKVVal value) internal pure returns (MemoryKV) {
        uint256 pointer;
        uint256 length;
        assembly ("memory-safe") {
            // Hash to spread inserts across internal lists.
            // This MUST remain in sync with `get` logic.
            mstore(0, key)
            let bitOffset := mul(mod(keccak256(0, 0x20), LIST_COUNT), SLOT_BITS)

            // Set aside the starting pointer as we'll need to include it in any
            // newly inserted linked list items.
            let startPointer := and(shr(bitOffset, kv), POINTER_MASK)

            // Find a key match then break so that we populate a nonzero pointer.
            pointer := startPointer
            for {} iszero(iszero(pointer)) { pointer := mload(add(pointer, 0x40)) } {
                if eq(key, mload(pointer)) { break }
            }

            // If the pointer is nonzero we have to update the associated value
            // directly, otherwise this is an insert operation.
            switch iszero(pointer)
            // Update.
            case 0 { mstore(add(pointer, 0x20), value) }
            // Insert.
            default {
                // Allocate the list item.
                pointer := mload(0x40)
                mstore(0x40, add(pointer, NODE_BYTES))

                // Write key/value/pointer.
                mstore(pointer, key)
                mstore(add(pointer, 0x20), value)
                mstore(add(pointer, 0x40), startPointer)

                // Update total stored word count.
                length := add(shr(COUNT_BIT_OFFSET, kv), 2)

                //slither-disable-next-line incorrect-shift
                kv := add(kv, shl(COUNT_BIT_OFFSET, 2))

                // kv must point to new insertion.
                //slither-disable-next-line incorrect-shift
                kv := or(
                    shl(bitOffset, pointer),
                    // Mask out the old pointer
                    and(kv, not(shl(bitOffset, POINTER_MASK)))
                )
            }
        }
        // Neither bound can be crossed without setting a bit above
        // `POINTER_MASK`, so one comparison covers both and the nested test
        // only runs once something has already overflowed.
        if ((pointer | length) > POINTER_MASK) {
            if (pointer > POINTER_MASK) {
                revert MemoryKVOverflow(pointer);
            }
            revert MemoryKVLengthOverflow(length);
        }
        return kv;
    }

    /// Export/snapshot the key/value store into a standard `bytes32[]`. Reads
    /// the word count to preallocate the `bytes32[]`, then bisects the head
    /// pointers in `kv` to find the non-zero ones, walking each found list to
    /// its end to copy out every pair.
    ///
    /// The bisect tests an empty subtree once where a linear loop visits every
    /// list in it, so its saving over a loop over every list depends on which
    /// lists are occupied, not on how many pairs they hold, and falls as they
    /// fill: ~1900 gas for an empty store, ~1100 gas with lists 0 to 5 occupied
    /// and ~60 gas with every list occupied.
    ///
    /// Note this is a one time export, if the key/value store is subsequently
    /// mutated the built array will not reflect these mutations.
    ///
    /// The allocation is sized from the word count in `kv` and filled by
    /// walking the lists, so the two must agree.
    ///
    /// @param kv The entrypoint into the key/value store.
    /// @return array All the keys and values copied pairwise into a `bytes32[]`.
    /// The pair order is unspecified and MUST NOT be relied upon; a caller that
    /// needs a canonical form MUST sort.
    // The cyclomatic complexity slither counts is the bisect's branches, one
    // per node of the tree over the head pointers.
    //slither-disable-next-line cyclomatic-complexity
    function toBytes32Array(MemoryKV kv) internal pure returns (bytes32[] memory array) {
        uint256 mask16 = type(uint16).max;
        uint256 mask32 = type(uint32).max;
        uint256 mask64 = type(uint64).max;
        uint256 mask128 = type(uint128).max;
        assembly ("memory-safe") {
            // Manually create a `bytes32[]`.
            // No need to zero out memory as we're about to write to it.
            array := mload(0x40)
            let length := shr(COUNT_BIT_OFFSET, kv)
            mstore(0x40, add(array, add(0x20, mul(length, 0x20))))
            mstore(array, length)

            // Known false positives in slither
            // https://github.com/crytic/slither/issues/1815
            //slither-disable-next-line naming-convention
            function copyFromPtr(cursor, pointer) -> end {
                for {} iszero(iszero(pointer)) {
                    pointer := mload(add(pointer, 0x40))
                    cursor := add(cursor, 0x40)
                } {
                    mstore(cursor, mload(pointer))
                    mstore(add(cursor, 0x20), mload(add(pointer, 0x20)))
                }
                end := cursor
            }

            // Bisect. The gas this tree saves over a linear loop is documented
            // in the NatSpec above.
            // Each symbol is declared in the smallest block that holds every
            // use of it, so a use outside that block does not compile.
            let cursor := add(array, 0x20)
            {
                // Remove the length from kv before iffing, so p0 is zero
                // exactly when lists 8 to 14 are empty and the bisect skips
                // them.
                let p0 := shr(0x90, shl(0x10, kv))
                if iszero(iszero(p0)) {
                    {
                        let p00 := shr(0x40, p0)
                        if iszero(iszero(p00)) {
                            {
                                // This branch is a special case because we
                                // already zeroed out the high bits which are
                                // used by the length and are NOT a pointer.
                                // We can skip processing where the pointer would
                                // have been if it were not the length, and do
                                // not need to scrub the high bits to move from
                                // `p00` to `p0001`.
                                let p0001 := shr(0x20, p00)
                                if iszero(iszero(p0001)) { cursor := copyFromPtr(cursor, p0001) }
                            }
                            let p001 := and(mask32, p00)
                            if iszero(iszero(p001)) {
                                {
                                    let p0010 := shr(0x10, p001)
                                    if iszero(iszero(p0010)) { cursor := copyFromPtr(cursor, p0010) }
                                }
                                let p0011 := and(mask16, p001)
                                if iszero(iszero(p0011)) { cursor := copyFromPtr(cursor, p0011) }
                            }
                        }
                    }
                    let p01 := and(mask64, p0)
                    if iszero(iszero(p01)) {
                        {
                            let p010 := shr(0x20, p01)
                            if iszero(iszero(p010)) {
                                {
                                    let p0100 := shr(0x10, p010)
                                    if iszero(iszero(p0100)) { cursor := copyFromPtr(cursor, p0100) }
                                }
                                let p0101 := and(mask16, p010)
                                if iszero(iszero(p0101)) { cursor := copyFromPtr(cursor, p0101) }
                            }
                        }

                        let p011 := and(mask32, p01)
                        if iszero(iszero(p011)) {
                            {
                                let p0110 := shr(0x10, p011)
                                if iszero(iszero(p0110)) { cursor := copyFromPtr(cursor, p0110) }
                            }

                            let p0111 := and(mask16, p011)
                            if iszero(iszero(p0111)) { cursor := copyFromPtr(cursor, p0111) }
                        }
                    }
                }
            }

            {
                let p1 := and(mask128, kv)
                if iszero(iszero(p1)) {
                    {
                        let p10 := shr(0x40, p1)
                        if iszero(iszero(p10)) {
                            {
                                let p100 := shr(0x20, p10)
                                if iszero(iszero(p100)) {
                                    {
                                        let p1000 := shr(0x10, p100)
                                        if iszero(iszero(p1000)) { cursor := copyFromPtr(cursor, p1000) }
                                    }
                                    let p1001 := and(mask16, p100)
                                    if iszero(iszero(p1001)) { cursor := copyFromPtr(cursor, p1001) }
                                }
                            }
                            let p101 := and(mask32, p10)
                            if iszero(iszero(p101)) {
                                {
                                    let p1010 := shr(0x10, p101)
                                    if iszero(iszero(p1010)) { cursor := copyFromPtr(cursor, p1010) }
                                }
                                let p1011 := and(mask16, p101)
                                if iszero(iszero(p1011)) { cursor := copyFromPtr(cursor, p1011) }
                            }
                        }
                    }
                    let p11 := and(mask64, p1)
                    if iszero(iszero(p11)) {
                        {
                            let p110 := shr(0x20, p11)
                            if iszero(iszero(p110)) {
                                {
                                    let p1100 := shr(0x10, p110)
                                    if iszero(iszero(p1100)) { cursor := copyFromPtr(cursor, p1100) }
                                }
                                let p1101 := and(mask16, p110)
                                if iszero(iszero(p1101)) { cursor := copyFromPtr(cursor, p1101) }
                            }
                        }

                        let p111 := and(mask32, p11)
                        if iszero(iszero(p111)) {
                            {
                                let p1110 := shr(0x10, p111)
                                if iszero(iszero(p1110)) { cursor := copyFromPtr(cursor, p1110) }
                            }

                            let p1111 := and(mask16, p111)
                            if iszero(iszero(p1111)) { cursor := copyFromPtr(cursor, p1111) }
                        }
                    }
                }
            }
        }
    }
}
