// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {LibMemoryKV, MemoryKV, MemoryKVKey} from "src/lib/LibMemoryKV.sol";
import {slotOf} from "test/lib/LibMemoryKVKeys.sol";

/// `kv` with its word count replaced by `newCount`, every other bit kept;
/// `newCount` is not checked against `LibMemoryKV.POINTER_MASK`, the widest
/// count the slot holds.
function withCount(MemoryKV kv, uint256 newCount) pure returns (MemoryKV) {
    return MemoryKV.wrap(
        (MemoryKV.unwrap(kv) & ~(LibMemoryKV.POINTER_MASK << LibMemoryKV.COUNT_BIT_OFFSET))
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
