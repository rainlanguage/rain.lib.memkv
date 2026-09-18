// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {slotOf, keyForSlot} from "test/lib/LibMemoryKVKeys.sol";
import {occupiedSlots} from "test/lib/LibMemoryKVHandle.sol";

/// @title LibMemoryKVGetWalkTest
/// `get` walks one internal list and stops at the FIRST node whose key matches.
/// `set` walks the same list and also stops at the first match, so the node
/// `set` writes and the node `get` reads MUST be the same node. Nothing in the
/// public API can build a list holding one key twice, so the only way to state
/// that agreement as an observable value is to hand both functions a list that
/// does, which these tests build directly in memory.
///
/// The walk is also a read: crossing a list leaves every allocated byte and the
/// free memory pointer where they were.
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
        uint256 bitOffset = slotOf(MemoryKVKey.unwrap(key)) * 0x10;
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
        MemoryKVKey tailKey = keyForSlot(bytes32(uint256(1)), 5);
        MemoryKVKey headKey = keyForSlot(bytes32(uint256(2)), 5);
        assertTrue(MemoryKVKey.unwrap(headKey) != MemoryKVKey.unwrap(tailKey), "the two keys must be different keys");

        MemoryKV kv = MEMORY_KV_EMPTY;
        kv = kv.set(tailKey, MemoryKVVal.wrap(bytes32(uint256(222))));
        kv = kv.set(headKey, MemoryKVVal.wrap(bytes32(uint256(111))));

        // One list holds both, so exactly one of the 15 slots is occupied and
        // the tail is only reachable by walking past the head.
        assertEq(occupiedSlots(kv), 1, "both keys share one internal list");

        (uint256 tailExists, MemoryKVVal tailValue) = kv.get(tailKey);
        assertEq(tailExists, 1, "tail exists");
        assertEq(MemoryKVVal.unwrap(tailValue), bytes32(uint256(222)), "tail value");

        (uint256 headExists, MemoryKVVal headValue) = kv.get(headKey);
        assertEq(headExists, 1, "head exists");
        assertEq(MemoryKVVal.unwrap(headValue), bytes32(uint256(111)), "head value");
    }

    /// Three keys forced onto ONE internal list, the first one set ending up at
    /// the tail because `set` prepends, plus a fourth key on that same list
    /// that was never set. A lookup for either returned key crosses the whole
    /// list rather than answering from the head.
    function threeKeysInOneList() internal pure returns (MemoryKV, MemoryKVKey, MemoryKVKey) {
        MemoryKVKey deepest = keyForSlot(bytes32(uint256(1)), 9);
        MemoryKVKey middle = keyForSlot(bytes32(uint256(2)), 9);
        MemoryKVKey head = keyForSlot(bytes32(uint256(3)), 9);
        MemoryKVKey absent = keyForSlot(bytes32(uint256(4)), 9);

        MemoryKV kv = MEMORY_KV_EMPTY;
        kv = kv.set(deepest, MemoryKVVal.wrap(bytes32(uint256(111))));
        kv = kv.set(middle, MemoryKVVal.wrap(bytes32(uint256(222))));
        kv = kv.set(head, MemoryKVVal.wrap(bytes32(uint256(333))));

        // Six words is three inserts, so the three keys are distinct and the
        // list is three nodes deep rather than one node updated twice.
        require(MemoryKV.unwrap(kv) >> 0xf0 == 6, "three distinct keys on one list");

        return (kv, deepest, absent);
    }

    /// Hashes every allocated byte, and the free memory pointer that bounds
    /// them, without allocating: taking it either side of a call measures that
    /// call alone.
    function allocatedMemory() internal pure returns (bytes32, uint256) {
        bytes32 digest;
        uint256 freeMemoryPointer;
        assembly ("memory-safe") {
            freeMemoryPointer := mload(0x40)
            digest := keccak256(0x60, sub(freeMemoryPointer, 0x60))
        }
        return (digest, freeMemoryPointer);
    }

    /// A hit at the tail crosses every node in front of it and leaves memory
    /// exactly as it was. A walk that wrote through the pointers it follows, or
    /// that allocated as it went, would corrupt or leak once per lookup while
    /// still returning the right pair, so the returned pair cannot state this.
    function testGetHitLeavesMemoryUntouched() external pure {
        (MemoryKV kv, MemoryKVKey deepest,) = threeKeysInOneList();

        (bytes32 digestBefore, uint256 freeBefore) = allocatedMemory();
        (uint256 exists, MemoryKVVal value) = kv.get(deepest);
        (bytes32 digestAfter, uint256 freeAfter) = allocatedMemory();

        assertEq(exists, 1, "tail key exists");
        assertEq(MemoryKVVal.unwrap(value), bytes32(uint256(111)), "tail value");
        assertEq(freeAfter, freeBefore, "free memory pointer");
        assertEq(digestAfter, digestBefore, "allocated memory");
    }

    /// The same for a miss, which crosses every node and then the terminator.
    function testGetMissLeavesMemoryUntouched() external pure {
        (MemoryKV kv,, MemoryKVKey absent) = threeKeysInOneList();

        (bytes32 digestBefore, uint256 freeBefore) = allocatedMemory();
        (uint256 exists, MemoryKVVal value) = kv.get(absent);
        (bytes32 digestAfter, uint256 freeAfter) = allocatedMemory();

        assertEq(exists, 0, "absent key");
        assertEq(MemoryKVVal.unwrap(value), bytes32(0), "absent value");
        assertEq(freeAfter, freeBefore, "free memory pointer");
        assertEq(digestAfter, digestBefore, "allocated memory");
    }
}
