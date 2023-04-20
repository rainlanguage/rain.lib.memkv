// SPDX-License-Identifier: CAL
pragma solidity ^0.8.18;

import "sol.lib.binmaskflag/Binary.sol";

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
    /// Reads the `MemoryKVVal` that some `MemoryKVPtr` is pointing to.
    /// The caller MUST NOT provide a 0 pointer, i.e. if `getPtr` would say
    /// the key DOES NOT exist then DO NOT use that pointer.
    /// @param ptr_ The pointer to read the value
    function readPtrVal(MemoryKVPtr ptr_) internal pure returns (MemoryKVVal v_) {
        assembly ("memory-safe") {
            v_ := mload(add(ptr_, 0x20))
        }
    }

    /// Finds the pointer to the item that holds the value associated with the
    /// given key. Walks the linked list from the entrypoint into the key/value
    /// store until it finds the specified key. As the last pointer in the list
    /// is always `0`, `0` is what will be returned if the key is not found. Any
    /// non-zero pointer implies the value it points to is for the provided key.
    /// @param kv_ The entrypoint to the key/value store.
    /// @param k_ The key to lookup a pointer for.
    /// @return ptr_ The _pointer_ to the value for the key, if it exists, else
    /// a pointer to `0`. If the pointer is non-zero the associated value can be
    /// read to a `MemoryKVVal` with `LibMemoryKV.readPtrVal`.
    function getPtr(MemoryKV kv_, MemoryKVKey k_) internal pure returns (MemoryKVPtr ptr_) {
        assembly ("memory-safe") {
            mstore(0, k_)
            let bitOffset_ := mul(mod(keccak256(0, 0x20), 14), 0x10)

            // loop until k found or give up if ptr is zero
            for { ptr_ := and(shr(bitOffset_, kv_), 0xFFFF) } iszero(iszero(ptr_)) { ptr_ := mload(add(ptr_, 0x40)) } {
                if eq(k_, mload(ptr_)) { break }
            }
        }
    }

    /// Upserts a value in the set by its key. I.e. if the key exists then the
    /// associated value will be mutated in place, else a new key/value pair will
    /// be inserted. The key/value store pointer will be mutated and returned as
    /// it MAY point to a new list item in memory.
    /// @param kv_ The key/value store pointer to modify.
    /// @param k_ The key to upsert against.
    /// @param v_ The value to associate with the upserted key.
    /// @return The final value of `kv_` as it MAY be modified if the upsert
    /// resulted in an insert operation.
    function setVal(MemoryKV kv_, MemoryKVKey k_, MemoryKVVal v_) internal pure returns (MemoryKV) {
        assembly ("memory-safe") {
            // Hash to spread inserts across internal lists.
            mstore(0, k_)
            let bitOffset_ := mul(mod(keccak256(0, 0x20), 14), 0x10)
            let startPtr_ := and(shr(bitOffset_, kv_), 0xFFFF)
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
                let len_ := add(shr(0xf0, kv_), 2)
                kv_ := or(shl(0xf0, len_), and(kv_, not(shl(0xf0, 0xFFFF))))

                // kv must point to new insertion
                kv_ :=
                    or(
                        shl(bitOffset_, ptr_),
                        // Mask out the old pointer
                        and(kv_, not(shl(bitOffset_, 0xFFFF)))
                    )
            }
        }
        return kv_;
    }

    function toUint256Array(MemoryKV kv_) internal pure returns (uint256[] memory arr_) {
        uint256 mask16_ = type(uint16).max;
        uint256 mask32_ = type(uint32).max;
        uint256 mask64_ = type(uint64).max;
        assembly ("memory-safe") {
            // Manually create an `uint256[]`.
            // No need to zero out memory as we're about to write to it.
            arr_ := mload(0x40)
            let len_ := shr(0xf0, kv_)
            mstore(0x40, add(arr_, add(0x20, mul(len_, 0x20))))
            mstore(arr_, len_)

            function copyFromPtr(start_, ptr_) -> end_ {
                end_ := start_
            }

            // Bisect.
            let cursor_ := add(arr_, 0x20)
            {
                let p0_ := shr(0x80, kv_)
                if iszero(iszero(p0_)) {
                    {
                        let p00_ := shr(0x40, p0_)
                        if iszero(iszero(p00_)) {
                            {
                                let p000_ := shr(0x20, p00_)
                                if iszero(iszero(p000_)) {
                                    {
                                        let p0000_ := shr(0x10, p000_)
                                        if iszero(iszero(p0000_)) { cursor_ := copyFromPtr(cursor_, p0000_) }
                                    }
                                    let p0001_ := and(mask16_, p000_)
                                    if iszero(iszero(p0001_)) { cursor_ := copyFromPtr(cursor_, p0001_) }
                                }
                            }
                            let p001_ := and(mask32_, p00_)
                            if iszero(iszero(p001_)) {
                                {
                                    let p0010_ := shr(0x10, p001_)
                                    if iszero(iszero(p0010_)) { cursor_ := copyFromPtr(cursor_, p0010_) }
                                }
                                let p0011_ := and(mask16_, p001_)
                                if iszero(iszero(p0011_)) { cursor_ := copyFromPtr(cursor_, p0011_) }
                            }
                        }
                    }
                    let p01_ := and(mask64_, p0_)
                    if iszero(iszero(p01_)) {
                        {
                            let p010_ := shr(0x20, p01_)
                            if iszero(iszero(p010_)) {
                                {
                                    let p0100_ := shr(0x10, p010_)
                                    if iszero(iszero(p0100_)) { cursor_ := copyFromPtr(cursor_, p0100_) }
                                }
                                let p0101_ := and(mask16_, p010_)
                                if iszero(iszero(p0101_)) { cursor_ := copyFromPtr(cursor_, p0101_) }
                            }
                        }

                        let p011_ := and(mask32_, p01_)
                        if iszero(iszero(p011_)) {
                            {
                                let p0110_ := shr(0x10, p011_)
                                if iszero(iszero(p0110_)) { cursor_ := copyFromPtr(cursor_, p0110_) }
                            }

                            let p0111_ := and(mask16_, p011_)
                            if iszero(iszero(p0111_)) { cursor_ := copyFromPtr(cursor_, p0111_) }
                        }
                    }
                }
            }
        }
    }

    // /// Export/snapshot the underlying linked list of the key/value store into
    // /// a standard `uint256[]`. Reads the total length to preallocate the
    // /// `uint256[]` then walks the entire linked list, copying every key and
    // /// value into the array, until it reaches a pointer to `0`. Note this is a
    // /// one time export, if the key/value store is subsequently mutated the built
    // /// array will not reflect these mutations.
    // /// @param kv_ The entrypoint into the key/value store.
    // /// @return arr_ All the keys and values copied pairwise into a `uint256[]`.
    // function toUint256Array(MemoryKV kv_) internal pure returns (uint256[] memory arr_) {
    //     unchecked {
    //         // uint256 ptr_ = MemoryKV.unwrap(kv_) & MASK_16BIT;
    //         // uint256 length_ = MemoryKV.unwrap(kv_) >> 16;
    //         // uint256[] memory arr_ = new uint256[](length_);
    //         assembly ("memory-safe") {
    //             let mask_ := 0xFFFF
    //             // No ifs, or, buts... plenty of ands tho.
    //             let len0_ := and(shr(0x10, kv_), mask_)
    //             let len1_ := and(shr(0x30, kv_), mask_)
    //             let len2_ := and(shr(0x50, kv_), mask_)
    //             let len3_ := and(shr(0x70, kv_), mask_)
    //             let len4_ := and(shr(0x90, kv_), mask_)
    //             let len5_ := and(shr(0xb0, kv_), mask_)
    //             let len6_ := and(shr(0xd0, kv_), mask_)
    //             let len7_ := shr(0xf0, kv_)

    //             {
    //                 let length_ := add(len0_, add(len1_, add(len2_, add(len3_, add(len4_, add(len5_, add(len6_, len7_)))))))

    //                 // Manually create an `uint256[]`.
    //                 // No need to zero out memory as we're about to write to it.
    //                 arr_ := mload(0x40)
    //                 mstore(0x40, add(arr_, add(0x20, mul(length_, 0x20))))
    //             }

    //             function copyFromPtr(start_, ptr_) -> end_ {}
    //             pop(copyFromPtr(
    //                 copyFromPtr(
    //                     copyFromPtr(
    //                         copyFromPtr(
    //                             copyFromPtr(
    //                                 copyFromPtr(
    //                                     copyFromPtr(
    //                                         copyFromPtr(add(arr_, 0x20), and(kv_, mask_)), and(shr(0x20, kv_), mask_)
    //                                     ),
    //                                     and(shr(0x40, kv_), mask_)
    //                                 ),
    //                                 and(shr(0x60, kv_), mask_)
    //                             ),
    //                             and(shr(0x80, kv_), mask_)
    //                         ),
    //                         and(shr(0xa0, kv_), mask_)
    //                     ),
    //                     and(shr(0xc0, kv_), mask_)
    //                 ),
    //                 and(shr(0xe0, kv_), mask_)
    //             ))

    //             // for {
    //             //     let cursor_ := add(arr_, 0x20)
    //             //     let end_ := add(cursor_, mul(mload(arr_), 0x20))
    //             // } lt(cursor_, end_) {
    //             //     cursor_ := add(cursor_, 0x20)
    //             //     ptr_ := mload(add(ptr_, 0x40))
    //             // } {
    //             //     // key
    //             //     mstore(cursor_, mload(ptr_))
    //             //     cursor_ := add(cursor_, 0x20)
    //             //     // value
    //             //     mstore(cursor_, mload(add(ptr_, 0x20)))
    //             // }
    //         }
    //     }
    // }
}
