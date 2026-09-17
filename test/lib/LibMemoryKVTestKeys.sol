// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {MemoryKVKey, MemoryKVVal} from "src/lib/LibMemoryKV.sol";

/// @title LibMemoryKVTestKeys
/// Keys and values a test constructs, and the internal list a key belongs to.
/// The list is restated from the hash `get` and `set` document in Solidity
/// rather than read back out of the store, so a test's expectation is not the
/// implementation's own expression.
library LibMemoryKVTestKeys {
    /// `MemoryKV` carries one head pointer per internal linked list.
    uint256 internal constant SLOTS = 15;

    /// How many candidates a search tries before reverting. One key in 15
    /// lands in any given list, so this is far more than any search here
    /// needs, and it bounds a search that otherwise cannot end.
    uint256 internal constant CANDIDATE_LIMIT = 10000;

    /// The value whose word is `v`.
    function val(uint256 v) internal pure returns (MemoryKVVal) {
        return MemoryKVVal.wrap(bytes32(v));
    }

    /// The internal list `key` belongs to: `keccak256(key) % 15`.
    function slotOf(MemoryKVKey key) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(MemoryKVKey.unwrap(key)))) % SLOTS;
    }

    /// The first key of the chain `seed`, `keccak256(seed)`,
    /// `keccak256(keccak256(seed))`, ... that lands in `slot`. `seed` itself is
    /// the answer when it already lands there. Reverts if no key of the first
    /// `CANDIDATE_LIMIT` does.
    function keyForSlot(bytes32 seed, uint256 slot) internal pure returns (MemoryKVKey) {
        bytes32 key = seed;
        for (uint256 i = 0; i < CANDIDATE_LIMIT; i++) {
            if (slotOf(MemoryKVKey.wrap(key)) == slot) {
                return MemoryKVKey.wrap(key);
            }
            key = keccak256(abi.encodePacked(key));
        }
        revert("no key for slot");
    }

    /// `count` distinct keys that all land in `slot`, so setting them in order
    /// builds one list `count` long. Each is `keyForSlot` of the previous one
    /// rehashed once, the first of `seed` itself.
    function keysInSlot(bytes32 seed, uint256 slot, uint256 count) internal pure returns (MemoryKVKey[] memory) {
        MemoryKVKey[] memory keys = new MemoryKVKey[](count);
        for (uint256 i = 0; i < count; i++) {
            keys[i] = keyForSlot(seed, slot);
            seed = keccak256(abi.encodePacked(MemoryKVKey.unwrap(keys[i])));
        }
        return keys;
    }

    /// A key other than `key` that lands in the same list as `key`, so one
    /// list holds both and a walk has to follow a next pointer to cross
    /// between them. It is `keyForSlot` of `key` rehashed once.
    function collidingKey(MemoryKVKey key) internal pure returns (MemoryKVKey) {
        return keyForSlot(keccak256(abi.encodePacked(MemoryKVKey.unwrap(key))), slotOf(key));
    }

    /// Two keys that differ in bit `bit` alone and land in ONE list, so a walk
    /// reaches both nodes and only the node key compare tells them apart. The
    /// first has the bit clear and the second has it set. `seed` picks which
    /// such pair: the low key is `keccak256(seed, tries)` with the bit cleared
    /// for the first `tries` from zero whose pair shares a list. Reverts if
    /// none of the first `CANDIDATE_LIMIT` does.
    function collidingPairDifferingInBit(uint256 seed, uint256 bit)
        internal
        pure
        returns (MemoryKVKey, MemoryKVKey)
    {
        uint256 mask = uint256(1) << bit;
        for (uint256 tries = 0; tries < CANDIDATE_LIMIT; tries++) {
            bytes32 low = bytes32(uint256(keccak256(abi.encodePacked(seed, tries))) & ~mask);
            bytes32 high = bytes32(uint256(low) | mask);
            if (slotOf(MemoryKVKey.wrap(low)) == slotOf(MemoryKVKey.wrap(high))) {
                return (MemoryKVKey.wrap(low), MemoryKVKey.wrap(high));
            }
        }
        revert("no pair differing in the bit shares a list within the candidate limit");
    }
}
