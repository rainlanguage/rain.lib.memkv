// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";

import {LibPointer, Pointer} from "rain-solmem-0.1.28/src/lib/LibPointer.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {SetAtFreePointer} from "test/lib/SetAtFreePointer.sol";
import {dirtyFreeMemory} from "test/lib/LibFreeMemory.sol";
import {keysInSlot} from "test/lib/LibMemoryKVKeys.sol";
import {headOf, lengthOf} from "test/lib/LibMemoryKVHandle.sol";

/// @title LibMemoryKVSetInsertTest
/// The insert half of `set`, asserted against the documented SHAPE of the
/// store.
///
/// The layout is the one the `MemoryKV` NatSpec documents and the `LibMemoryKV`
/// constants name. So an insert must place a `LibMemoryKV.NODE_BYTES`
/// key/value/next node, prepend it to its list, and add two to the word count
/// in the slot at `LibMemoryKV.COUNT_BIT_OFFSET`.
contract LibMemoryKVSetInsertTest is Test, SetAtFreePointer {
    using LibMemoryKV for MemoryKV;

    /// The three words of a list node as written by an insert.
    function readNode(uint256 pointer) internal pure returns (bytes32 nodeKey, bytes32 nodeValue, uint256 next) {
        assembly ("memory-safe") {
            nodeKey := mload(pointer)
            nodeValue := mload(add(pointer, 0x20))
            next := mload(add(pointer, 0x40))
        }
    }

    /// An insert into an empty store writes exactly three words AT the free
    /// memory pointer -- key, then value, then the old head of the list -- and
    /// records that same address as the list head, with a count of two.
    function testSetInsertWritesThreeWordsAtTheFreeMemoryPointer(MemoryKVKey key, MemoryKVVal value) external pure {
        MemoryKV kv = MEMORY_KV_EMPTY;

        uint256 nodePointer = Pointer.unwrap(LibPointer.allocatedMemoryPointer());
        kv = kv.set(key, value);
        uint256 allocatedAfter = Pointer.unwrap(LibPointer.allocatedMemoryPointer());

        assertEq(allocatedAfter, nodePointer + LibMemoryKV.NODE_BYTES, "three words allocated");
        assertEq(headOf(kv, key), nodePointer, "list head is the node address");
        assertEq(lengthOf(kv), 2, "one pair is two words");

        (bytes32 nodeKey, bytes32 nodeValue, uint256 next) = readNode(nodePointer);
        assertEq(nodeKey, MemoryKVKey.unwrap(key), "key at node+0x00");
        assertEq(nodeValue, MemoryKVVal.unwrap(value), "value at node+0x20");
        assertEq(next, 0, "next at node+0x40 is the old (empty) head");
    }

    /// An insert WRITES all three words of its node: the node lands on memory
    /// dirtied with a sentinel, and its words read back as the zero key, the
    /// zero value and the terminator of an empty list.
    function testSetInsertWritesEveryWordOfTheNode(bytes32 seed) external pure {
        bytes32 sentinel = keccak256(abi.encode(seed));
        MemoryKVKey key = MemoryKVKey.wrap(bytes32(0));
        MemoryKVVal value = MemoryKVVal.wrap(bytes32(0));

        dirtyFreeMemory(sentinel, 3);

        uint256 nodePointer = Pointer.unwrap(LibPointer.allocatedMemoryPointer());
        MemoryKV kv = MEMORY_KV_EMPTY.set(key, value);

        (bytes32 nodeKey, bytes32 nodeValue, uint256 next) = readNode(nodePointer);
        assertEq(nodeKey, bytes32(0), "zero key written at node+0x00");
        assertEq(nodeValue, bytes32(0), "zero value written at node+0x20");
        assertEq(next, 0, "terminator written at node+0x40");

        (uint256 exists, MemoryKVVal got) = kv.get(key);
        assertEq(exists, 1, "the zero key exists");
        assertEq(MemoryKVVal.unwrap(got), bytes32(0), "and reads back zero, not the sentinel");
    }

    /// Three keys that share one list: each insert PREPENDS, so the head is the
    /// newest node and every older node is still reachable behind it. Asserts
    /// the chain of addresses.
    function testSetInsertPrependsWithinOneList() external pure {
        MemoryKVKey[] memory keys = keysInSlot(bytes32(uint256(1)), 0, 3);
        MemoryKV kv = MEMORY_KV_EMPTY;

        uint256 node0 = Pointer.unwrap(LibPointer.allocatedMemoryPointer());
        kv = kv.set(keys[0], MemoryKVVal.wrap(bytes32(uint256(0xA0))));
        uint256 node1 = Pointer.unwrap(LibPointer.allocatedMemoryPointer());
        kv = kv.set(keys[1], MemoryKVVal.wrap(bytes32(uint256(0xA1))));
        uint256 node2 = Pointer.unwrap(LibPointer.allocatedMemoryPointer());
        kv = kv.set(keys[2], MemoryKVVal.wrap(bytes32(uint256(0xA2))));

        assertEq(node1, node0 + LibMemoryKV.NODE_BYTES, "second node follows the first");
        assertEq(node2, node1 + LibMemoryKV.NODE_BYTES, "third node follows the second");

        // The head is the newest node, and ONLY the newest: the old head is
        // masked out of the slot.
        assertEq(headOf(kv, keys[0]), node2, "head is the newest node");
        assertEq(lengthOf(kv), 6, "three pairs is six words");

        {
            (bytes32 nodeKey, bytes32 nodeValue, uint256 next) = readNode(node2);
            assertEq(nodeKey, MemoryKVKey.unwrap(keys[2]), "newest node key");
            assertEq(nodeValue, bytes32(uint256(0xA2)), "newest node value");
            assertEq(next, node1, "newest node points at the previous head");
        }
        {
            (bytes32 nodeKey, bytes32 nodeValue, uint256 next) = readNode(node1);
            assertEq(nodeKey, MemoryKVKey.unwrap(keys[1]), "middle node key");
            assertEq(nodeValue, bytes32(uint256(0xA1)), "middle node value");
            assertEq(next, node0, "middle node points at the first node");
        }
        {
            (bytes32 nodeKey, bytes32 nodeValue, uint256 next) = readNode(node0);
            assertEq(nodeKey, MemoryKVKey.unwrap(keys[0]), "first node key");
            assertEq(nodeValue, bytes32(uint256(0xA0)), "first node value");
            assertEq(next, 0, "the first node terminates the list");
        }

        for (uint256 i = 0; i < 3; i++) {
            (uint256 exists, MemoryKVVal value) = kv.get(keys[i]);
            assertEq(exists, 1, "every key of the list still exists");
            assertEq(uint256(MemoryKVVal.unwrap(value)), 0xA0 + i, "every value of the list survives");
        }
    }

    /// The word count's slot is `LibMemoryKV.SLOT_BITS` wide, so it keeps
    /// counting past 0xFF. 200 pairs is 400 words, which does not fit in a
    /// byte: the count reads 400, and `toBytes32Array`, which preallocates from
    /// it, exports 400 words.
    function testSetInsertWordCountPastAByte() external pure {
        uint256 pairs = 200;
        MemoryKV kv = MEMORY_KV_EMPTY;
        for (uint256 i = 1; i <= pairs; i++) {
            kv = kv.set(MemoryKVKey.wrap(bytes32(i)), MemoryKVVal.wrap(bytes32(i * 7)));
        }

        assertEq(lengthOf(kv), pairs * 2, "400 words, not a count truncated to a byte on each insert");

        bytes32[] memory array = kv.toBytes32Array();
        assertEq(array.length, pairs * 2, "export is preallocated from the full count");

        for (uint256 i = 1; i <= pairs; i++) {
            (uint256 exists, MemoryKVVal value) = kv.get(MemoryKVKey.wrap(bytes32(i)));
            assertEq(exists, 1, "every key survives past the byte boundary");
            assertEq(uint256(MemoryKVVal.unwrap(value)), i * 7, "every value survives past the byte boundary");
        }
    }

    /// The overflow error carries the OFFENDING pointer, not the bound it
    /// crossed. `0x12345` is neither the bound nor one past it.
    function testSetOverflowPayloadIsTheOffendingPointerNotTheBound() external {
        MemoryKVKey key = MemoryKVKey.wrap(bytes32(uint256(1)));
        MemoryKVVal value = MemoryKVVal.wrap(bytes32(uint256(2)));

        vm.expectRevert(abi.encodeWithSelector(LibMemoryKV.MemoryKVOverflow.selector, 0x12345));
        this.setAtFreePointer(MEMORY_KV_EMPTY, key, value, 0x12345);
    }

    /// A pointer with bits above the low twelve must reach the slot intact: the
    /// slot is `LibMemoryKV.SLOT_BITS` wide and an insert at `0xF000` must record
    /// exactly `0xF000`, not a truncation of it.
    function testSetInsertRecordsTheWholePointer(MemoryKVKey key, MemoryKVVal value) external view {
        MemoryKV kv = this.setAtFreePointer(MEMORY_KV_EMPTY, key, value, 0xF000);
        assertEq(headOf(kv, key), 0xF000, "the whole pointer reaches the slot");
        assertEq(lengthOf(kv), 2, "one pair is two words");
    }

    /// The head pointer an insert produces exists ONLY in the returned store.
    /// The node is allocated and written either way, so a caller that drops the
    /// return is left holding the word it already had and the pair is reachable
    /// from nothing -- no revert, no short array, just a missing key.
    function testSetInsertIsUnreachableWhenTheReturnIsDropped(
        MemoryKVKey keyA,
        MemoryKVKey keyB,
        MemoryKVVal valueA,
        MemoryKVVal valueB
    ) external pure {
        vm.assume(MemoryKVKey.unwrap(keyA) != MemoryKVKey.unwrap(keyB));

        MemoryKV kv = MEMORY_KV_EMPTY.set(keyA, valueA);
        uint256 dropped = MemoryKV.unwrap(kv);

        uint256 nodeB = Pointer.unwrap(LibPointer.allocatedMemoryPointer());
        MemoryKV returned = kv.set(keyB, valueB);

        (bytes32 nodeKey, bytes32 nodeValue,) = readNode(nodeB);
        assertEq(nodeKey, MemoryKVKey.unwrap(keyB), "the node was written");
        assertEq(nodeValue, MemoryKVVal.unwrap(valueB), "with the value");

        assertEq(MemoryKV.unwrap(kv), dropped, "the dropped store is the word it already had");
        assertEq(lengthOf(kv), 2, "the dropped store still counts one pair");
        assertEq(kv.toBytes32Array().length, 2, "and exports one pair");
        assertFalse(kv.has(keyB), "the insert is unreachable from the dropped store");

        assertEq(headOf(returned, keyB), nodeB, "the returned store heads the new node");
        assertEq(lengthOf(returned), 4, "the returned store counts two pairs");
        (uint256 exists, MemoryKVVal value) = returned.get(keyB);
        assertEq(exists, 1, "the returned store has the key");
        assertEq(MemoryKVVal.unwrap(value), MemoryKVVal.unwrap(valueB), "and the value");
    }
}
