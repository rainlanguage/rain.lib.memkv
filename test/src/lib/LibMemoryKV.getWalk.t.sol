// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {LibMemoryKVTestKeys} from "test/lib/LibMemoryKVTestKeys.sol";

/// @title LibMemoryKVGetWalkTest
/// `get` walks one internal list and stops at the FIRST node whose key matches.
/// `set` walks the same list and also stops at the first match, so the node
/// `set` writes and the node `get` reads MUST be the same node. Nothing in the
/// public API can build a list holding one key twice, so the only way to state
/// that agreement as an observable value is to hand both functions a list that
/// does, which these tests build directly in memory.
contract LibMemoryKVGetWalkTest is Test {
    using LibMemoryKV for MemoryKV;

    /// Builds one internal list holding `key` twice: a head node carrying
    /// `first` and a tail node carrying `second`. The list is hung off the slot
    /// `key` hashes to, so `get` and `set` both walk it for that key.
    function craftDuplicateKeyList(MemoryKVKey key, MemoryKVVal first, MemoryKVVal second)
        internal
        pure
        returns (MemoryKV kv, uint256 head, uint256 tail)
    {
        uint256 bitOffset = LibMemoryKVTestKeys.slotOf(key) * 0x10;
        assembly ("memory-safe") {
            tail := mload(0x40)
            mstore(0x40, add(tail, 0x60))
            mstore(tail, key)
            mstore(add(tail, 0x20), second)
            mstore(add(tail, 0x40), 0)

            head := mload(0x40)
            mstore(0x40, add(head, 0x60))
            mstore(head, key)
            mstore(add(head, 0x20), first)
            mstore(add(head, 0x40), tail)

            // Two pairs, and the head of the list in the slot for this key.
            kv := or(shl(0xf0, 0x04), shl(bitOffset, head))
        }
        require(head <= 0xFFFF, "crafted head pointer must fit 16 bits");
        require(tail <= 0xFFFF, "crafted tail pointer must fit 16 bits");
    }

    /// The walk stops at the first match, so the head node's value is what
    /// comes back, NOT the tail node's.
    function testGetReturnsTheFirstMatchingNode() external pure {
        MemoryKVKey key = MemoryKVKey.wrap(bytes32(uint256(0xBEEF)));
        (MemoryKV kv,,) =
            craftDuplicateKeyList(key, MemoryKVVal.wrap(bytes32(uint256(11))), MemoryKVVal.wrap(bytes32(uint256(22))));

        (uint256 exists, MemoryKVVal value) = kv.get(key);
        assertEq(exists, 1, "exists");
        assertEq(MemoryKVVal.unwrap(value), bytes32(uint256(11)), "first match wins");
    }

    /// Same statement, fuzzed over the key and both values.
    function testGetReturnsTheFirstMatchingNodeFuzz(MemoryKVKey key, MemoryKVVal first, MemoryKVVal second)
        external
        pure
    {
        vm.assume(MemoryKVVal.unwrap(first) != MemoryKVVal.unwrap(second));
        (MemoryKV kv,,) = craftDuplicateKeyList(key, first, second);

        (uint256 exists, MemoryKVVal value) = kv.get(key);
        assertEq(exists, 1, "exists");
        assertEq(MemoryKVVal.unwrap(value), MemoryKVVal.unwrap(first), "first match wins");
    }

    /// `set` updates the first matching node in place. `get` MUST read that
    /// same node, so the value `set` just wrote is the value `get` reports.
    /// If `get` kept walking it would report the stale tail node instead.
    function testGetAgreesWithSetOnWhichNodeIsTheKey() external pure {
        MemoryKVKey key = MemoryKVKey.wrap(bytes32(uint256(0xBEEF)));
        (MemoryKV kv, uint256 head, uint256 tail) =
            craftDuplicateKeyList(key, MemoryKVVal.wrap(bytes32(uint256(11))), MemoryKVVal.wrap(bytes32(uint256(22))));

        kv = kv.set(key, MemoryKVVal.wrap(bytes32(uint256(33))));

        // `set` wrote the head node and left the tail node alone.
        uint256 headValue;
        uint256 tailValue;
        assembly ("memory-safe") {
            headValue := mload(add(head, 0x20))
            tailValue := mload(add(tail, 0x20))
        }
        assertEq(headValue, 33, "set wrote the head node");
        assertEq(tailValue, 22, "set left the tail node alone");

        (uint256 exists, MemoryKVVal value) = kv.get(key);
        assertEq(exists, 1, "exists");
        assertEq(MemoryKVVal.unwrap(value), bytes32(uint256(33)), "get reads the node set wrote");
    }

    /// A node deeper in the list that is NOT the head still answers, and it
    /// answers with its own value rather than the head's. Both keys are forced
    /// onto ONE internal list, because two keys in different slots are two
    /// one-node lists and never exercise the walk at all.
    function testGetReadsATailNodeWhenOnlyItMatches() external pure {
        MemoryKVKey tailKey = LibMemoryKVTestKeys.keyForSlot(bytes32(uint256(1)), 5);
        MemoryKVKey headKey = LibMemoryKVTestKeys.keyForSlot(bytes32(uint256(2)), 5);
        assertTrue(MemoryKVKey.unwrap(headKey) != MemoryKVKey.unwrap(tailKey), "the two keys must be different keys");

        MemoryKV kv = MEMORY_KV_EMPTY;
        kv = kv.set(tailKey, MemoryKVVal.wrap(bytes32(uint256(222))));
        kv = kv.set(headKey, MemoryKVVal.wrap(bytes32(uint256(111))));

        // One list holds both, so exactly one of the 15 slots is occupied and
        // the tail is only reachable by walking past the head.
        uint256 occupied = 0;
        for (uint256 bitOffset = 0; bitOffset < 0xf0; bitOffset += 0x10) {
            if (((MemoryKV.unwrap(kv) >> bitOffset) & 0xFFFF) != 0) {
                occupied++;
            }
        }
        assertEq(occupied, 1, "both keys share one internal list");

        (uint256 tailExists, MemoryKVVal tailValue) = kv.get(tailKey);
        assertEq(tailExists, 1, "tail exists");
        assertEq(MemoryKVVal.unwrap(tailValue), bytes32(uint256(222)), "tail value");

        (uint256 headExists, MemoryKVVal headValue) = kv.get(headKey);
        assertEq(headExists, 1, "head exists");
        assertEq(MemoryKVVal.unwrap(headValue), bytes32(uint256(111)), "head value");
    }
}
