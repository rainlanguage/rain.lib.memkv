// SPDX-License-Identifier: CAL
pragma solidity ^0.8.18;

/// Entrypoint into the key/value store. Is a mutable pointer to the head of the
/// linked list. Initially points to `0` for an empty list. The total length of
/// the linked list is also encoded alongside the pointer to allow efficient O(1)
/// memory allocation for a `uint256[]` in the case of a final snapshot/export.
type MemoryKV is uint256;
/// The key associated with the value for each item in the linked list.

type MemoryKVKey is uint256;
/// The pointer to the next item in the list. `0` signifies the end of the list.

type MemoryKVPtr is uint256;
/// The value associated with the key for each item in the linked list.

type MemoryKVVal is uint256;

/// @title LibMemoryKV
/// @notice Implements an in-memory key/value store in terms of a linked list
/// that can be snapshotted/exported to a `uint256[]` of pairwise keys/values as
/// its items. Ostensibly supports reading/writing to storage within a read only
/// context in an interpreter `eval` by tracking changes requested by an
/// expression in memory as a cache-like structure over the underlying storage.
///
/// A linked list is required because unlike stack movements we do NOT have any
/// way to precalculate how many items will be included in the final set at
/// deploy time. Any two writes may share the same key known only at runtime, so
/// any two writes may result in either 2 or 1 insertions (and 0 or 1 updates).
/// We could attempt to solve this by allowing duplicate keys and simply append
/// values for each write, so two writes will always insert 2 values, but then
/// looping constructs such as `OpDoWhile` and `OpFoldContext` with net 0 stack
/// movements (i.e. predictably deallocateable memory) can still cause
/// unbounded/unknown inserts for our state changes. The linked list allows us
/// to both dedupe same-key writes and also safely handle an unknown
/// (at deploy time) number of upserts. New items are inserted at the head of
/// the list and a pointer to `0` is the sentinel that defines the end of the
/// list. It is an error to dereference the `0` pointer.
///
/// Currently implemented as O(n) where n is likely relatively small, in future
/// could be reimplemented as 8 linked lists over a single `MemoryKV` by packing
/// many `MemoryKVPtr` and using `%` to distribute keys between lists. The
/// extremely high gas cost of writing to storage itself should be a natural
/// disincentive for n getting large enough to cause the linked list traversal
/// to be a significant gas cost itself.
///
/// Currently implemented in terms of raw `uint256` custom types that represent
/// keys, values and pointers. Could be reimplemented in terms of an equivalent
/// struct with key, value and pointer fields.
library LibMemoryKV {
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
            // Hash logic MUST match set.
            mstore(0, key)
            let bitOffset := mul(mod(keccak256(0, 0x20), 15), 0x10)

            // Loop until k found or give up if ptr is zero.
            for { let ptr := and(shr(bitOffset, kv), 0xFFFF) } iszero(iszero(ptr)) { ptr := mload(add(ptr, 0x40)) } {
                if eq(key, mload(ptr)) {
                    exists := 1
                    value := mload(add(ptr, 0x20))
                    break
                }
            }
        }
    }

    /// Upserts a value in the set by its key. I.e. if the key exists then the
    /// associated value will be mutated in place, else a new key/value pair will
    /// be inserted. The key/value store pointer will be mutated and returned as
    /// it MAY point to a new list item in memory.
    /// @param kv The key/value store pointer to modify.
    /// @param k_ The key to upsert against.
    /// @param v_ The value to associate with the upserted key.
    /// @return The final value of `kv` as it MAY be modified if the upsert
    /// resulted in an insert operation.
    function set(MemoryKV kv, MemoryKVKey k_, MemoryKVVal v_) internal pure returns (MemoryKV) {
        assembly ("memory-safe") {
            // Hash to spread inserts across internal lists.
            // This MUST remain in sync with `get` logic.
            mstore(0, k_)
            let bitOffset_ := mul(mod(keccak256(0, 0x20), 15), 0x10)

            let startPtr_ := and(shr(bitOffset_, kv), 0xFFFF)
            let ptr_ := startPtr_
            for {} iszero(iszero(ptr_)) { ptr_ := mload(add(ptr_, 0x40)) } { if eq(k_, mload(ptr_)) { break } }

            switch iszero(ptr_)
            // update
            case 0 { mstore(add(ptr_, 0x20), v_) }
            // insert
            default {
                // allocate new memory
                ptr_ := mload(0x40)
                mstore(0x40, add(ptr_, 0x60))
                // set k/v/ptr
                mstore(ptr_, k_)
                mstore(add(ptr_, 0x20), v_)
                mstore(add(ptr_, 0x40), startPtr_)

                // update array len
                let len_ := add(shr(0xf0, kv), 2)
                kv := or(shl(0xf0, len_), and(kv, not(shl(0xf0, 0xFFFF))))

                // kv must point to new insertion
                kv :=
                    or(
                        shl(bitOffset_, ptr_),
                        // Mask out the old pointer
                        and(kv, not(shl(bitOffset_, 0xFFFF)))
                    )
            }
        }
        return kv;
    }

    /// Export/snapshot the underlying linked list of the key/value store into
    /// a standard `uint256[]`. Reads the total length to preallocate the
    /// `uint256[]` then bisects the bits of the `kv` to find non-zero pointers
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
    /// @return array All the keys and values copied pairwise into a `uint256[]`.
    function toUint256Array(MemoryKV kv) internal pure returns (uint256[] memory array) {
        uint256 mask16 = type(uint16).max;
        uint256 mask32 = type(uint32).max;
        uint256 mask64 = type(uint64).max;
        uint256 mask128 = type(uint128).max;
        assembly ("memory-safe") {
            // Manually create an `uint256[]`.
            // No need to zero out memory as we're about to write to it.
            array := mload(0x40)
            let length := shr(0xf0, kv)
            mstore(0x40, add(array, add(0x20, mul(length, 0x20))))
            mstore(array, length)

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
                let p1_ := and(mask128, kv)
                if iszero(iszero(p1_)) {
                    {
                        let p10_ := shr(0x40, p1_)
                        if iszero(iszero(p10_)) {
                            {
                                let p100_ := shr(0x20, p10_)
                                if iszero(iszero(p100_)) {
                                    {
                                        let p1000_ := shr(0x10, p100_)
                                        if iszero(iszero(p1000_)) { cursor := copyFromPtr(cursor, p1000_) }
                                    }
                                    let p1001_ := and(mask16, p100_)
                                    if iszero(iszero(p1001_)) { cursor := copyFromPtr(cursor, p1001_) }
                                }
                            }
                            let p101_ := and(mask32, p10_)
                            if iszero(iszero(p101_)) {
                                {
                                    let p1010_ := shr(0x10, p101_)
                                    if iszero(iszero(p1010_)) { cursor := copyFromPtr(cursor, p1010_) }
                                }
                                let p1011_ := and(mask16, p101_)
                                if iszero(iszero(p1011_)) { cursor := copyFromPtr(cursor, p1011_) }
                            }
                        }
                    }
                    let p11_ := and(mask64, p1_)
                    if iszero(iszero(p11_)) {
                        {
                            let p110_ := shr(0x20, p11_)
                            if iszero(iszero(p110_)) {
                                {
                                    let p1100_ := shr(0x10, p110_)
                                    if iszero(iszero(p1100_)) { cursor := copyFromPtr(cursor, p1100_) }
                                }
                                let p1101_ := and(mask16, p110_)
                                if iszero(iszero(p1101_)) { cursor := copyFromPtr(cursor, p1101_) }
                            }
                        }

                        let p111_ := and(mask32, p11_)
                        if iszero(iszero(p111_)) {
                            {
                                let p1110_ := shr(0x10, p111_)
                                if iszero(iszero(p1110_)) { cursor := copyFromPtr(cursor, p1110_) }
                            }

                            let p1111_ := and(mask16, p111_)
                            if iszero(iszero(p1111_)) { cursor := copyFromPtr(cursor, p1111_) }
                        }
                    }
                }
            }
        }
    }
}
