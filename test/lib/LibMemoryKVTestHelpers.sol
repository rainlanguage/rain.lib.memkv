// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {StdConstants} from "forge-std-1.16.1/src/StdConstants.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal} from "src/lib/LibMemoryKV.sol";

/// @dev How many candidates a key or key-pair search tries before reverting. One
/// key in `LibMemoryKV.LIST_COUNT` lands in any given list, and one candidate
/// pair in `LibMemoryKV.LIST_COUNT` shares a list, so this is far more than any
/// search here needs.
uint256 constant CANDIDATE_LIMIT = 10000;

/// The value whose word is `word`.
function val(uint256 word) pure returns (MemoryKVVal) {
    return MemoryKVVal.wrap(bytes32(word));
}

/// The key whose word is `word`.
function keyFor(uint256 word) pure returns (MemoryKVKey) {
    return MemoryKVKey.wrap(bytes32(word));
}

/// `keccak256` of the one word `word`, hashed from scratch space so the free
/// memory pointer does not move; callers rely on that when they need node
/// addresses to stay at or under `LibMemoryKV.POINTER_MASK`.
function hashWord(bytes32 word) pure returns (bytes32 hashed) {
    assembly ("memory-safe") {
        mstore(0, word)
        hashed := keccak256(0, 0x20)
    }
}

/// The internal list `key` belongs to: `keccak256(key) % LibMemoryKV.LIST_COUNT`,
/// restated from the layout `MemoryKV` documents rather than read back out of
/// the store.
function slotOf(bytes32 key) pure returns (uint256) {
    return uint256(hashWord(key)) % LibMemoryKV.LIST_COUNT;
}

/// The first key of the chain `seed`, `keccak256(seed)`, ... that lands in
/// `slot`; `seed` itself when it already does. Reverts if none of the first
/// `CANDIDATE_LIMIT` does.
function keyForSlot(bytes32 seed, uint256 slot) pure returns (MemoryKVKey) {
    bytes32 key = seed;
    for (uint256 i = 0; i < CANDIDATE_LIMIT; i++) {
        if (slotOf(key) == slot) {
            return MemoryKVKey.wrap(key);
        }
        key = hashWord(key);
    }
    revert("no key for slot");
}

/// `count` distinct keys that all land in `slot`, so setting them in order
/// builds one list `count` long. The first is `keyForSlot` of `seed`, each
/// after it `keyForSlot` of the previous one rehashed once.
function keysInSlot(bytes32 seed, uint256 slot, uint256 count) pure returns (MemoryKVKey[] memory) {
    MemoryKVKey[] memory keys = new MemoryKVKey[](count);
    for (uint256 i = 0; i < count; i++) {
        keys[i] = keyForSlot(seed, slot);
        seed = hashWord(MemoryKVKey.unwrap(keys[i]));
    }
    return keys;
}

/// A key other than `key` in the same list as `key`, so a walk has to follow a
/// next pointer to cross between them: `keyForSlot` of `key` rehashed once.
function collidingKey(MemoryKVKey key) pure returns (MemoryKVKey) {
    bytes32 raw = MemoryKVKey.unwrap(key);
    return keyForSlot(hashWord(raw), slotOf(raw));
}

/// Two keys that differ in bit `bit` alone and land in ONE list, the first
/// with the bit clear. The low key is `keccak256(seed, tries)` with the bit
/// cleared, for the first `tries` from zero whose pair shares a list.
function collidingPairDifferingInBit(uint256 seed, uint256 bit) pure returns (MemoryKVKey, MemoryKVKey) {
    require(bit < 256, "bit must be below 256");
    uint256 mask = uint256(1) << bit;
    for (uint256 tries = 0; tries < CANDIDATE_LIMIT; tries++) {
        bytes32 candidate;
        assembly ("memory-safe") {
            mstore(0, seed)
            mstore(0x20, tries)
            candidate := keccak256(0, 0x40)
        }
        bytes32 low = bytes32(uint256(candidate) & ~mask);
        bytes32 high = bytes32(uint256(low) | mask);
        if (slotOf(low) == slotOf(high)) {
            return (MemoryKVKey.wrap(low), MemoryKVKey.wrap(high));
        }
    }
    revert("no pair differing in the bit shares a list within the candidate limit");
}

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

/// How many times the pairwise `array`, a key at every even index and its
/// value after it as `toBytes32Array` lays it out, holds `key` then `value`.
function countPair(bytes32[] memory array, bytes32 key, bytes32 value) pure returns (uint256) {
    uint256 count = 0;
    for (uint256 i = 0; i < array.length; i += 2) {
        if (array[i] == key && array[i + 1] == value) {
            count++;
        }
    }
    return count;
}

/// Assert the store reports exactly `value` for `key`: the key exists and its
/// value word is `value`. `StdConstants.VM.assertEq` is what forge-std's
/// `assertEq(uint256,uint256,string)` calls, so the failure is the same one.
function assertValue(MemoryKV kv, MemoryKVKey key, uint256 value, string memory err) pure {
    (uint256 exists, MemoryKVVal got) = LibMemoryKV.get(kv, key);
    StdConstants.VM.assertEq(exists, 1, string.concat(err, " exists"));
    StdConstants.VM.assertEq(uint256(MemoryKVVal.unwrap(got)), value, string.concat(err, " value"));
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

/// Move the free memory pointer to `pointer`, so the next allocation, and so
/// the next node an insert writes, starts there. Memory at and above `pointer`
/// is free to the next allocation from then on, whatever it held.
/// @param pointer The new free memory pointer.
function setFreePointer(uint256 pointer) pure {
    assembly ("memory-safe") {
        mstore(0x40, pointer)
    }
}
