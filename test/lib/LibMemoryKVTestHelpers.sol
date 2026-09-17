// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Vm} from "forge-std-1.16.1/src/Vm.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal} from "src/lib/LibMemoryKV.sol";

// `MemoryKV` carries one 16 bit head pointer per internal linked list, under
// a 16 bit word count.
uint256 constant SLOTS = 15;

// The widest head pointer a list slot can hold.
uint256 constant POINTER_MAX = 0xFFFF;

// How many candidates a key search tries before reverting. One key in 15
// lands in any given list, so this is far more than any search here needs,
// and it bounds a search that otherwise cannot end.
uint256 constant CANDIDATE_LIMIT = 10000;

Vm constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

/// The value whose word is `v`.
function val(uint256 v) pure returns (MemoryKVVal) {
    return MemoryKVVal.wrap(bytes32(v));
}

/// `keccak256` of the one word `word`, hashed from scratch space so the free
/// memory pointer does not move. Nothing in this file allocates: a search that
/// allocated on every candidate would push the nodes of a test that fills all
/// 15 lists past what a 16 bit pointer can address.
function hashWord(bytes32 word) pure returns (bytes32 hashed) {
    assembly ("memory-safe") {
        mstore(0, word)
        hashed := keccak256(0, 0x20)
    }
}

/// The internal list `key` belongs to: `keccak256(key) % 15`, restated from
/// the hash `get` and `set` document rather than read back out of the store.
function slotOf(bytes32 key) pure returns (uint256) {
    return uint256(hashWord(key)) % SLOTS;
}

/// The first key of the chain `seed`, `keccak256(seed)`,
/// `keccak256(keccak256(seed))`, ... that lands in `slot`. `seed` itself is the
/// answer when it already lands there. Reverts if no key of the first
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
/// builds one list `count` long. Each is `keyForSlot` of the previous one
/// rehashed once, the first of `seed` itself.
function keysInSlot(bytes32 seed, uint256 slot, uint256 count) pure returns (MemoryKVKey[] memory) {
    MemoryKVKey[] memory keys = new MemoryKVKey[](count);
    for (uint256 i = 0; i < count; i++) {
        keys[i] = keyForSlot(seed, slot);
        seed = hashWord(MemoryKVKey.unwrap(keys[i]));
    }
    return keys;
}

/// A key other than `key` that lands in the same list as `key`, so one list
/// holds both and a walk has to follow a next pointer to cross between them.
/// It is `keyForSlot` of `key` rehashed once.
function collidingKey(MemoryKVKey key) pure returns (MemoryKVKey) {
    bytes32 raw = MemoryKVKey.unwrap(key);
    return keyForSlot(hashWord(raw), slotOf(raw));
}

/// Two keys that differ in bit `bit` alone and land in ONE list, so a walk
/// reaches both nodes and only the node key compare tells them apart. The
/// first has the bit clear and the second has it set. `seed` picks which such
/// pair: the low key is `keccak256(seed, tries)` with the bit cleared for the
/// first `tries` from zero whose pair shares a list. Reverts if none of the
/// first `CANDIDATE_LIMIT` does, and if `bit` is not a bit of a 256 bit key.
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

/// The word count the store carries in its top 16 bits.
function lengthOf(MemoryKV kv) pure returns (uint256) {
    return MemoryKV.unwrap(kv) >> 0xf0;
}

/// `lengthOf`.
function wordCount(MemoryKV kv) pure returns (uint256) {
    return lengthOf(kv);
}

/// The 16 bit head pointer `kv` holds for internal list `slot`.
function headOf(MemoryKV kv, uint256 slot) pure returns (uint256) {
    return (MemoryKV.unwrap(kv) >> (slot * 0x10)) & POINTER_MAX;
}

/// The 16 bit head pointer `kv` holds for the internal list `key` belongs to.
function headOf(MemoryKV kv, MemoryKVKey key) pure returns (uint256) {
    return headOf(kv, slotOf(MemoryKVKey.unwrap(key)));
}

/// How many times the pairwise `array`, laid out as `toBytes32Array` lays it
/// out with a key at every even index and its value after it, holds `key`
/// immediately followed by `value`.
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
/// value word is `value`. `Vm.assertEq` is what forge-std's
/// `assertEq(uint256,uint256,string)` calls, so a failure here is the same
/// failure that assertion raises.
function assertValue(MemoryKV kv, MemoryKVKey key, uint256 value, string memory err) pure {
    (uint256 exists, MemoryKVVal got) = LibMemoryKV.get(kv, key);
    VM.assertEq(exists, 1, string.concat(err, " exists"));
    VM.assertEq(uint256(MemoryKVVal.unwrap(got)), value, string.concat(err, " value"));
}
