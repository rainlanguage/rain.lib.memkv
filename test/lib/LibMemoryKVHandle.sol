// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {LibPointer, Pointer} from "rain-solmem-0.1.28/src/lib/LibPointer.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal} from "src/lib/LibMemoryKV.sol";
import {setFreePointer} from "test/lib/LibFreeMemory.sol";
import {slotOf} from "test/lib/LibMemoryKVKeys.sol";

/// @dev The widest word count the meta word holds: every bit from
/// `LibMemoryKV.COUNT_BIT_OFFSET` up.
uint256 constant COUNT_MAX = type(uint256).max >> LibMemoryKV.COUNT_BIT_OFFSET;

/// The occupancy bit of list `slot` in the meta word.
function occupancyBitOf(uint256 slot) pure returns (uint256) {
    return LibMemoryKV.LIST_0_OCCUPANCY_BIT >> slot;
}

/// The meta word of the store's header; `0` for the empty store, which has no
/// header.
function metaOf(MemoryKV kv) pure returns (uint256 meta) {
    if (MemoryKV.unwrap(kv) != 0) {
        uint256 metaOffset = LibMemoryKV.META_OFFSET;
        assembly ("memory-safe") {
            meta := mload(add(kv, metaOffset))
        }
    }
}

/// The word count the meta word carries above
/// `LibMemoryKV.COUNT_BIT_OFFSET`; `0` for the empty store.
function lengthOf(MemoryKV kv) pure returns (uint256) {
    return metaOf(kv) >> LibMemoryKV.COUNT_BIT_OFFSET;
}

/// The occupancy mask the meta word carries; `0` for the empty store.
function maskOf(MemoryKV kv) pure returns (uint256) {
    return metaOf(kv) & LibMemoryKV.OCCUPANCY_MASK;
}

/// The address of the header word that holds the head of internal list `slot`
/// of the header at `kv`.
function headAddressOf(MemoryKV kv, uint256 slot) pure returns (uint256) {
    return MemoryKV.unwrap(kv) + slot * 0x20;
}

/// The head the header holds for internal list `slot`; `0` for the empty
/// store.
function headOf(MemoryKV kv, uint256 slot) pure returns (uint256 head) {
    if (MemoryKV.unwrap(kv) != 0) {
        uint256 headAddress = headAddressOf(kv, slot);
        assembly ("memory-safe") {
            head := mload(headAddress)
        }
    }
}

/// The head the header holds for the internal list `key` belongs to.
function headOf(MemoryKV kv, MemoryKVKey key) pure returns (uint256) {
    return headOf(kv, slotOf(MemoryKVKey.unwrap(key)));
}

/// How many of the `LibMemoryKV.LIST_COUNT` internal lists of `kv` have a
/// non-zero head, read from the heads rather than the occupancy mask.
function occupiedSlots(MemoryKV kv) pure returns (uint256) {
    uint256 count = 0;
    for (uint256 slot = 0; slot < LibMemoryKV.LIST_COUNT; slot++) {
        if (headOf(kv, slot) != 0) {
            count++;
        }
    }
    return count;
}

/// An empty header allocated at the free memory pointer: every head, and the
/// meta word, zero, whatever the memory held before. Lets a test build a store
/// no sequence of `set` calls builds.
/// @return kv The header's address, which the free memory pointer is now
/// `LibMemoryKV.HEADER_BYTES` past.
function craftHeader() pure returns (MemoryKV kv) {
    uint256 headerBytes = LibMemoryKV.HEADER_BYTES;
    assembly ("memory-safe") {
        kv := mload(0x40)
        mstore(0x40, add(kv, headerBytes))
        for { let cursor := kv } lt(cursor, add(kv, headerBytes)) { cursor := add(cursor, 0x20) } {
            mstore(cursor, 0)
        }
    }
}

/// Point list `slot` of the header at `kv` at `head`, set the list's
/// occupancy bit, and set the store's word count to `words`. Every other head
/// and occupancy bit is kept. Reverts when a field does not fit its place in
/// the header.
/// @param kv The header to write. MUST NOT be the empty store.
/// @param slot The internal list to head. MUST be below
/// `LibMemoryKV.LIST_COUNT`.
/// @param head The list's head: a node address, or `0`.
/// @param words The word count. MUST be at most `COUNT_MAX`.
function writeList(MemoryKV kv, uint256 slot, uint256 head, uint256 words) pure {
    require(slot < LibMemoryKV.LIST_COUNT && words <= COUNT_MAX, "list field out of range");
    uint256 meta = (words << LibMemoryKV.COUNT_BIT_OFFSET) | maskOf(kv) | occupancyBitOf(slot);
    uint256 headAddress = headAddressOf(kv, slot);
    uint256 metaOffset = LibMemoryKV.META_OFFSET;
    assembly ("memory-safe") {
        mstore(headAddress, head)
        mstore(add(kv, metaOffset), meta)
    }
}

/// A list node allocated at the free memory pointer: `LibMemoryKV.NODE_BYTES`
/// holding the key, value and next pointer words in the order an insert writes
/// them. Lets a test build a list no sequence of `set` calls builds.
/// @param key The node's key word.
/// @param value The node's value word.
/// @param next The node's next pointer word; `0` ends the list.
/// @return node The node's address, which the free memory pointer is now
/// `LibMemoryKV.NODE_BYTES` past.
function craftNode(MemoryKVKey key, MemoryKVVal value, uint256 next) pure returns (uint256 node) {
    Pointer pointer = LibPointer.allocatedMemoryPointer();
    node = Pointer.unwrap(pointer);
    setFreePointer(node + LibMemoryKV.NODE_BYTES);
    LibPointer.unsafeWriteWord(pointer, MemoryKVKey.unwrap(key));
    LibPointer.unsafeWriteWord(LibPointer.unsafeAddWord(pointer), MemoryKVVal.unwrap(value));
    LibPointer.unsafeWriteWord(LibPointer.unsafeAddWords(pointer, 2), bytes32(next));
}

/// A store whose only list is `slot`, headed by `head`, carrying word count
/// `words`: `craftHeader` then `writeList`.
/// @param slot The internal list to head. MUST be below
/// `LibMemoryKV.LIST_COUNT`.
/// @param head The list's head: a node address, or `0`.
/// @param words The word count. MUST be at most `COUNT_MAX`.
/// @return kv The crafted header's address.
function handleWith(uint256 slot, uint256 head, uint256 words) pure returns (MemoryKV kv) {
    kv = craftHeader();
    writeList(kv, slot, head, words);
}
