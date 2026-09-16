// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.18;

/// Entrypoint into the key/value store. Is a mutable pointer to the head of the
/// linked list. Initially points to `0` for an empty list. The total word count
/// of all inserts is also encoded alongside the pointer to allow efficient O(1)
/// memory allocation for a `bytes32[]` in the case of a final snapshot/export.
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

/// The key associated with the value for each item in the store.
type MemoryKVKey is bytes32;

/// The value associated with the key for each item in the store.
type MemoryKVVal is bytes32;

/// @title LibMemoryKV
library LibMemoryKV {
    /// Thrown when an insert would allocate its node at a pointer above
    /// `0xFFFF`, which is the widest head pointer a list slot can hold, so the
    /// slot would truncate it and the bits above the slot would overwrite the
    /// neighbouring slots and the word count.
    ///
    /// Only the head is bounded: the node's three words MAY extend above
    /// `0xFFFF`, as every field is reached by full width arithmetic from the
    /// head. An update allocates nothing, so it never throws this.
    /// @param pointer The offending pointer, not the bound it crossed.
    error MemoryKVOverflow(uint256 pointer);

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
            let bitOffset := mul(mod(keccak256(0, 0x20), 15), 0x10)

            // Loop until k found or give up if pointer is zero.
            for { let pointer := and(shr(bitOffset, kv), 0xFFFF) } iszero(iszero(pointer)) {
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

    /// Whether a key exists in the store.
    ///
    /// The same walk as `get`, answering only the half of it that says whether
    /// the key is there. A caller asking membership wants a `bool` it can put
    /// inside an expression, and `get` returns a tuple, which Solidity cannot
    /// destructure inside one: every such caller otherwise writes a line to
    /// unpack the answer before it can use it.
    ///
    /// A key SET TO ZERO exists. Existence is not the value, which is why `get`
    /// reports them separately and why this reads the first of the two rather
    /// than comparing the second against zero.
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
    /// `0xFFFF`, the widest head pointer a list slot can hold. An update
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
        assembly ("memory-safe") {
            // Hash to spread inserts across internal lists.
            // This MUST remain in sync with `get` logic.
            mstore(0, key)
            let bitOffset := mul(mod(keccak256(0, 0x20), 15), 0x10)

            // Set aside the starting pointer as we'll need to include it in any
            // newly inserted linked list items.
            let startPointer := and(shr(bitOffset, kv), 0xFFFF)

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
                // Allocate 3 words of memory.
                pointer := mload(0x40)
                mstore(0x40, add(pointer, 0x60))

                // Write key/value/pointer.
                mstore(pointer, key)
                mstore(add(pointer, 0x20), value)
                mstore(add(pointer, 0x40), startPointer)

                // Update total stored word count.
                let length := add(shr(0xf0, kv), 2)

                //slither-disable-next-line incorrect-shift
                kv := or(shl(0xf0, length), and(kv, not(shl(0xf0, 0xFFFF))))

                // kv must point to new insertion.
                //slither-disable-next-line incorrect-shift
                kv := or(
                    shl(bitOffset, pointer),
                    // Mask out the old pointer
                    and(kv, not(shl(bitOffset, 0xFFFF)))
                )
            }
        }
        if (pointer > 0xFFFF) {
            revert MemoryKVOverflow(pointer);
        }
        return kv;
    }

    /// Export/snapshot the underlying linked list of the key/value store into
    /// a standard `bytes32[]`. Reads the total length to preallocate the
    /// `bytes32[]` then bisects the bits of the `kv` to find non-zero pointers
    /// to linked lists, walking each found list to the end to extract all
    /// values. As a single `kv` has 15 slots for pointers to linked lists it is
    /// likely for smallish structures that many slots can simply be skipped, so
    /// the bisect approach can save ~1-1.5k gas vs. a naive linear loop over
    /// all 15 slots for every export.
    ///
    /// Note this is a one time export, if the key/value store is subsequently
    /// mutated the built array will not reflect these mutations.
    ///
    /// @param kv The entrypoint into the key/value store.
    /// @return array All the keys and values copied pairwise into a `bytes32[]`.
    // Slither is not wrong about the cyclomatic complexity but I don't know
    // another way to implement the bisect and keep the gas savings.
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
            let length := shr(0xf0, kv)
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

            // Bisect.
            // This crazy tree saves ~1-1.5k gas vs. a simple loop with larger
            // relative savings for small-medium sized structures.
            // The internal scoping blocks are to provide some safety against
            // typos causing the incorrect symbol to be referenced by enforcing
            // each symbol is as tightly scoped as it can be.
            let cursor := add(array, 0x20)
            {
                // Remove the length from kv before iffing to save ~100 gas.
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
