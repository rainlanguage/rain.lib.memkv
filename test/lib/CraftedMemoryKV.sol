// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {LibPointer, Pointer} from "rain-solmem-0.1.28/src/lib/LibPointer.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal} from "src/lib/LibMemoryKV.sol";
import {setFreePointer} from "test/lib/LibMemoryKVTestHelpers.sol";

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
/// @param words The word count. MUST be at most `LibMemoryKV.POINTER_MASK`.
/// @return The handle.
function handleWith(uint256 slot, uint256 head, uint256 words) pure returns (MemoryKV) {
    require(
        slot < LibMemoryKV.LIST_COUNT && head <= LibMemoryKV.POINTER_MASK && words <= LibMemoryKV.POINTER_MASK,
        "handle field out of range"
    );
    return MemoryKV.wrap((words << LibMemoryKV.COUNT_BIT_OFFSET) | (head << (slot * LibMemoryKV.SLOT_BITS)));
}
