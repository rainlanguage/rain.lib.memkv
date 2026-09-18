// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// Entrypoint into the key/value store.
///
/// `0` is the empty store, which owns no memory. Any other value is the memory
/// address of the store's header, which the first insert allocates at the free
/// memory pointer. Nothing is packed into the handle itself, so there is no
/// ceiling on where in memory the store lives or on how many pairs it holds.
///
/// ```
/// header, LibMemoryKV.HEADER_BYTES at kv
///   kv + 0x20 * s   head of list s, for s in 0..14: the address of the list's
///                   newest node, 0 while the list is empty
///   kv + 0x1e0      meta: bits 16..255 the word count, two per pair
///                         bit 15 zero
///                         bits 0..14 the occupancy mask: list s is non-empty
///                         exactly when bit 14 - s is set
///
/// node, LibMemoryKV.NODE_BYTES at p
///   p + 0x00        key
///   p + 0x20        value
///   p + 0x40        next: the node that headed the list before this one, 0
///                   at the end of the list
/// ```
///
/// A key belongs to list `keccak256(key) % LibMemoryKV.LIST_COUNT`. An insert
/// prepends its node to that list and adds one pair to the word count, which
/// lets `toBytes32Array` allocate its `bytes32[]` in O(1), and sets the list's
/// occupancy bit, which lets it skip the empty lists without reading their
/// heads.
///
/// A `MemoryKV` is a handle to memory, not a snapshot, although Solidity
/// silently copies it as a value type. Once a store is non-empty every copy of
/// its handle is the same store: an insert or an update through any copy is
/// visible through every copy, and they share one word count. Only the empty
/// handle branches, because every `set` on `0` allocates a header of its own.
/// Snapshot with `toBytes32Array`.
///
/// A handle is valid ONLY inside the call frame that created it. The header
/// and the nodes are addresses in that frame's memory. Being a `uint256` a
/// handle crosses an external call unchanged while the memory it names does
/// not, so a `MemoryKV` MUST NOT be returned from or passed into an external
/// call. In another frame the same address names whatever that frame holds
/// there, so a read answers with unrelated memory, or follows a junk word as a
/// pointer and expands memory until the gas is gone. Cross a call boundary
/// with `toBytes32Array` instead.
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
    /// The number of internal linked lists a store keeps a head for.
    uint256 internal constant LIST_COUNT = 15;

    /// The bytes of memory `set` allocates for one node: the key, the value
    /// and the next pointer.
    uint256 internal constant NODE_BYTES = 0x60;

    /// The bytes of memory the first insert into an empty store allocates for
    /// its header: one head per list, then the meta word.
    uint256 internal constant HEADER_BYTES = 0x200;

    /// The offset of the meta word from the start of the header, directly
    /// after the last head.
    uint256 internal constant META_OFFSET = 0x1e0;

    /// The bit offset of the word count in the meta word, above the occupancy
    /// mask and the zero bit 15.
    uint256 internal constant COUNT_BIT_OFFSET = 0x10;

    /// What one insert adds to the meta word: the pair's two words in the
    /// count, `2 << COUNT_BIT_OFFSET`. A literal, because inline assembly
    /// accepts only literal constants and does not fold a `shl` of two.
    uint256 internal constant PAIR_COUNT_INCREMENT = 0x20000;

    /// The occupancy mask's bits in the meta word, one per list.
    uint256 internal constant OCCUPANCY_MASK = 0x7fff;

    /// The occupancy bit of list 0. List `s` has the bit `s` places below it,
    /// so the lowest set bit of the mask is the highest occupied list.
    uint256 internal constant LIST_0_OCCUPANCY_BIT = 0x4000;

    /// Maps a single occupancy bit, reduced modulo `SLOT_TABLE_MODULUS`, to the
    /// list it marks: the byte at index `2^j mod 19` holds `14 - j`, the list
    /// whose occupancy bit is `j`. 2 is a primitive root modulo 19, so the 15
    /// indices `2^0 .. 2^14 mod 19` are distinct and every bit has a byte of
    /// its own.
    //slither-disable-next-line too-many-digits
    uint256 internal constant SLOT_TABLE = 0x000e0d010c0000080b060002000907030a040500000000000000000000000000;

    /// The modulus that turns a single occupancy bit into its `SLOT_TABLE`
    /// index.
    uint256 internal constant SLOT_TABLE_MODULUS = 19;

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
            // The empty store has no header. Reading one at `0` would take the
            // scratch space and the free memory pointer for heads.
            if kv {
                // Hash to find the internal linked list to walk.
                // Hash logic MUST match set.
                mstore(0, key)

                // Loop until key found or give up if pointer is zero.
                for { let pointer := mload(add(kv, shl(5, mod(keccak256(0, 0x20), LIST_COUNT)))) } pointer {
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
    /// be inserted.
    ///
    /// An insert into the empty store first allocates the header at the free
    /// memory pointer and zeroes it, because memory above the free memory
    /// pointer is not guaranteed to be zero. Every insert then allocates one
    /// node. An update allocates nothing. `set` never reverts.
    ///
    /// The caller MUST assign the return back over the `kv` it passed in. The
    /// first insert into the empty store returns the address of the header it
    /// allocated, and the return is the only thing that holds it, so a dropped
    /// return there loses the whole store with no revert. For any other `kv`
    /// the return is the `kv` passed in.
    ///
    /// Every write lands in memory shared by every copy of a non-empty handle,
    /// so an insert or an update is visible through all of them, including
    /// copies taken before this call.
    /// @param kv The key/value store to modify.
    /// @param key The key to upsert against.
    /// @param value The value to associate with the upserted key.
    /// @return The store, which differs from `kv` only when `kv` is the empty
    /// store.
    function set(MemoryKV kv, MemoryKVKey key, MemoryKVVal value) internal pure returns (MemoryKV) {
        assembly ("memory-safe") {
            if iszero(kv) {
                kv := mload(0x40)
                mstore(0x40, add(kv, HEADER_BYTES))
                // Copying from past the end of calldata writes zeros.
                calldatacopy(kv, calldatasize(), HEADER_BYTES)
            }

            // Hash to spread inserts across internal lists.
            // This MUST remain in sync with `get` logic.
            mstore(0, key)
            let list := mod(keccak256(0, 0x20), LIST_COUNT)
            let head := add(kv, shl(5, list))

            // Set aside the starting pointer as an insert links its node to
            // it.
            let startPointer := mload(head)

            // Find a key match then break so that we populate a nonzero pointer.
            let pointer := startPointer
            for {} pointer { pointer := mload(add(pointer, 0x40)) } {
                if eq(key, mload(pointer)) { break }
            }

            // If the pointer is nonzero we have to update the associated value
            // directly, otherwise this is an insert operation.
            switch iszero(pointer)
            // Update.
            case 0 { mstore(add(pointer, 0x20), value) }
            // Insert.
            default {
                // Allocate the node.
                pointer := mload(0x40)
                mstore(0x40, add(pointer, NODE_BYTES))

                // Write key/value/pointer.
                mstore(pointer, key)
                mstore(add(pointer, 0x20), value)
                mstore(add(pointer, 0x40), startPointer)

                // The node heads its list.
                mstore(head, pointer)

                // One more pair in the count, and the list is occupied.
                let meta := add(kv, META_OFFSET)
                //slither-disable-next-line incorrect-shift
                mstore(meta, or(add(mload(meta), PAIR_COUNT_INCREMENT), shr(list, LIST_0_OCCUPANCY_BIT)))
            }
        }
        return kv;
    }

    /// Export/snapshot the key/value store into a standard `bytes32[]`. Reads
    /// the word count to preallocate the `bytes32[]`, then walks the
    /// occupancy mask from its lowest set bit up, copying out every pair of
    /// each occupied list from its head to its end. Empty lists cost nothing
    /// beyond the mask test that skips them.
    ///
    /// Note this is a one time export, if the key/value store is subsequently
    /// mutated the built array will not reflect these mutations.
    ///
    /// The allocation is sized from the word count and filled by walking the
    /// lists, so the two must agree.
    ///
    /// @param kv The entrypoint into the key/value store.
    /// @return array All the keys and values copied pairwise into a `bytes32[]`.
    /// The pair order is unspecified and MUST NOT be relied upon; a caller that
    /// needs a canonical form MUST sort.
    function toBytes32Array(MemoryKV kv) internal pure returns (bytes32[] memory array) {
        assembly ("memory-safe") {
            // Manually create a `bytes32[]`.
            // No need to zero out memory as we're about to write to it.
            array := mload(0x40)

            // The empty store has no header, so no meta word to read.
            let meta := 0
            if kv { meta := mload(add(kv, META_OFFSET)) }

            let length := shr(COUNT_BIT_OFFSET, meta)
            mstore(0x40, add(array, add(0x20, shl(5, length))))
            mstore(array, length)

            let cursor := add(array, 0x20)
            for { let mask := and(meta, OCCUPANCY_MASK) } mask {} {
                // Isolate the lowest set bit and clear it from the mask.
                let bit := and(mask, sub(0, mask))
                mask := xor(mask, bit)

                // Copy the list that bit marks, newest node first.
                for { let pointer := mload(add(kv, shl(5, byte(mod(bit, SLOT_TABLE_MODULUS), SLOT_TABLE)))) } pointer {
                    pointer := mload(add(pointer, 0x40))
                } {
                    mstore(cursor, mload(pointer))
                    mstore(add(cursor, 0x20), mload(add(pointer, 0x20)))
                    cursor := add(cursor, 0x40)
                }
            }
        }
    }
}
