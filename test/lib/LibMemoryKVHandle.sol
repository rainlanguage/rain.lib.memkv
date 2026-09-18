// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {LibPointer, Pointer} from "rain-solmem-0.1.28/src/lib/LibPointer.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal} from "src/lib/LibMemoryKV.sol";
import {setFreePointer} from "test/lib/LibFreeMemory.sol";
import {slotOf} from "test/lib/LibMemoryKVKeys.sol";

/// @dev The widest word count the handle holds: every bit from
/// `LibMemoryKV.COUNT_BIT_OFFSET` up.
uint256 constant COUNT_MAX = type(uint256).max >> LibMemoryKV.COUNT_BIT_OFFSET;

/// `kv` with its word count replaced by `newCount`, every other bit kept;
/// `newCount` is not checked against `COUNT_MAX`.
function withCount(MemoryKV kv, uint256 newCount) pure returns (MemoryKV) {
    return MemoryKV.wrap(
        (MemoryKV.unwrap(kv) & ~(COUNT_MAX << LibMemoryKV.COUNT_BIT_OFFSET))
            | (newCount << LibMemoryKV.COUNT_BIT_OFFSET)
    );
}

/// The word count the store carries at `LibMemoryKV.COUNT_BIT_OFFSET`.
function lengthOf(MemoryKV kv) pure returns (uint256) {
    return MemoryKV.unwrap(kv) >> LibMemoryKV.COUNT_BIT_OFFSET;
}

/// The head pointer `kv` holds for internal list `slot`.
function headOf(MemoryKV kv, uint256 slot) pure returns (uint256) {
    return (MemoryKV.unwrap(kv) >> (slot * LibMemoryKV.SLOT_BITS)) & LibMemoryKV.POINTER_MASK;
}

/// The head pointer `kv` holds for the internal list `key` belongs to.
function headOf(MemoryKV kv, MemoryKVKey key) pure returns (uint256) {
    return headOf(kv, slotOf(MemoryKVKey.unwrap(key)));
}

/// How many of the `LibMemoryKV.LIST_COUNT` internal lists of `kv` hold a head
/// pointer.
function occupiedSlots(MemoryKV kv) pure returns (uint256) {
    uint256 count = 0;
    for (uint256 slot = 0; slot < LibMemoryKV.LIST_COUNT; slot++) {
        if (headOf(kv, slot) != 0) {
            count++;
        }
    }
    return count;
}

/// A list node allocated at the free memory pointer: `LibMemoryKV.NODE_BYTES`
/// holding the key, value and next pointer words in the order an insert writes
/// them. Lets a test build a list no sequence of `set` calls builds. Reverts
/// when the node's address is above `LibMemoryKV.POINTER_MASK`, which no head
/// slot holds.
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
    require(node <= LibMemoryKV.POINTER_MASK, "crafted node pointer must fit a head slot");
}

/// A handle whose only list is `slot`, headed by `head`, carrying word count
/// `words`. Reverts when a field does not fit its place in the handle.
/// @param slot The internal list to head. MUST be below
/// `LibMemoryKV.LIST_COUNT`.
/// @param head The head pointer of that list. MUST be at most
/// `LibMemoryKV.POINTER_MASK`.
/// @param words The word count. MUST be at most `COUNT_MAX`.
/// @return The handle.
function handleWith(uint256 slot, uint256 head, uint256 words) pure returns (MemoryKV) {
    require(
        slot < LibMemoryKV.LIST_COUNT && head <= LibMemoryKV.POINTER_MASK && words <= COUNT_MAX,
        "handle field out of range"
    );
    return MemoryKV.wrap((words << LibMemoryKV.COUNT_BIT_OFFSET) | (head << (slot * LibMemoryKV.SLOT_BITS)));
}
