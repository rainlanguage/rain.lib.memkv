// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibPointer, Pointer} from "rain-solmem-0.1.28/src/lib/LibPointer.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal} from "src/lib/LibMemoryKV.sol";

/// @title LibMemoryKVSetInsertTest
/// The insert half of `set`, asserted against the documented SHAPE of the store
/// rather than against a round trip through `get`.
///
/// "Internally represented as 15 linked lists and 1x 16bit overall word count
/// that facilitates O(1) allocation ... of an export `uint256[]`" (README), and
/// the count is "The total word count of all inserts ... encoded alongside the
/// pointer" (`MemoryKV`). So an insert must place a three word key/value/next
/// node, prepend it to its list, and add two to a SIXTEEN bit count.
contract LibMemoryKVSetInsertTest is Test {
    using LibMemoryKV for MemoryKV;

    /// How many candidate keys `keysInOneSlot` tries before giving up. One key
    /// in 15 lands in any given list, so this is far more than the counts
    /// asked for here need, and it bounds a search that otherwise cannot end.
    uint256 internal constant CANDIDATE_LIMIT = 10000;

    /// The bit offset of the list a key belongs to. Recomputed here from the
    /// documented hash ("Hash logic MUST match set") in Solidity, so the
    /// expectation is not the implementation's own expression read back.
    function slotBitOffset(MemoryKVKey key) internal pure returns (uint256) {
        return (uint256(keccak256(abi.encodePacked(MemoryKVKey.unwrap(key)))) % 0x0f) * 0x10;
    }

    /// The head pointer `kv` records for the list that `key` belongs to.
    function slotPointer(MemoryKV kv, MemoryKVKey key) internal pure returns (uint256) {
        return (MemoryKV.unwrap(kv) >> slotBitOffset(key)) & 0xFFFF;
    }

    /// The 16 bit word count in the top of `kv`.
    function wordCount(MemoryKV kv) internal pure returns (uint256) {
        return MemoryKV.unwrap(kv) >> 0xf0;
    }

    /// The three words of a list node as written by an insert.
    function readNode(uint256 pointer) internal pure returns (bytes32 nodeKey, bytes32 nodeValue, uint256 next) {
        assembly ("memory-safe") {
            nodeKey := mload(pointer)
            nodeValue := mload(add(pointer, 0x20))
            next := mload(add(pointer, 0x40))
        }
    }

    /// `count` distinct keys that all hash into ONE of the 15 lists, so a
    /// second and third insert into the SAME list are observable.
    function keysInOneSlot(uint256 count) internal pure returns (MemoryKVKey[] memory keys) {
        keys = new MemoryKVKey[](count);
        MemoryKVKey first = MemoryKVKey.wrap(bytes32(uint256(1)));
        uint256 bitOffset = slotBitOffset(first);
        keys[0] = first;
        uint256 found = 1;
        for (uint256 i = 2; found < count && i <= CANDIDATE_LIMIT; i++) {
            MemoryKVKey candidate = MemoryKVKey.wrap(bytes32(i));
            if (slotBitOffset(candidate) == bitOffset) {
                keys[found] = candidate;
                found++;
            }
        }
        require(found == count, "keysInOneSlot: candidate limit hit before enough colliding keys");
    }

    /// Insert against an arbitrary free memory pointer so the inserted node's
    /// address (which `set` takes from the free memory pointer) is an exact
    /// known value. The node is written into memory this call frame owns and is
    /// gone when the call returns, so only the returned `kv` and the
    /// (non)revert are observable to the caller.
    function setAtFreePointerExternal(MemoryKV kv, MemoryKVKey key, MemoryKVVal value, uint256 freePointer)
        external
        pure
        returns (MemoryKV)
    {
        assembly ("memory-safe") {
            mstore(0x40, freePointer)
        }
        return LibMemoryKV.set(kv, key, value);
    }

    /// An insert into an empty store writes exactly three words AT the free
    /// memory pointer -- key, then value, then the old head of the list -- and
    /// records that same address as the list head, with a count of two.
    ///
    /// Stated as exact addresses and words rather than as "the value comes back
    /// out", so a node written next to the free memory pointer, a slot holding
    /// an address the node is not at, or a next word that is not the old head
    /// is a different NUMBER here, not just a failed lookup.
    function testSetInsertWritesThreeWordsAtTheFreeMemoryPointer(MemoryKVKey key, MemoryKVVal value) external pure {
        MemoryKV kv = MemoryKV.wrap(0);

        uint256 nodePointer = Pointer.unwrap(LibPointer.allocatedMemoryPointer());
        kv = kv.set(key, value);
        uint256 allocatedAfter = Pointer.unwrap(LibPointer.allocatedMemoryPointer());

        assertEq(allocatedAfter, nodePointer + 0x60, "three words allocated");
        assertEq(slotPointer(kv, key), nodePointer, "list head is the node address");
        assertEq(wordCount(kv), 2, "one pair is two words");

        (bytes32 nodeKey, bytes32 nodeValue, uint256 next) = readNode(nodePointer);
        assertEq(nodeKey, MemoryKVKey.unwrap(key), "key at node+0x00");
        assertEq(nodeValue, MemoryKVVal.unwrap(value), "value at node+0x20");
        assertEq(next, 0, "next at node+0x40 is the old (empty) head");
    }

    /// Three keys that share one list: each insert PREPENDS, so the head is the
    /// newest node and every older node is still reachable behind it. Asserts
    /// the chain of addresses, which is the fact that "nothing inserted is
    /// lost" rests on.
    function testSetInsertPrependsWithinOneList() external pure {
        MemoryKVKey[] memory keys = keysInOneSlot(3);
        MemoryKV kv = MemoryKV.wrap(0);

        uint256 node0 = Pointer.unwrap(LibPointer.allocatedMemoryPointer());
        kv = kv.set(keys[0], MemoryKVVal.wrap(bytes32(uint256(0xA0))));
        uint256 node1 = Pointer.unwrap(LibPointer.allocatedMemoryPointer());
        kv = kv.set(keys[1], MemoryKVVal.wrap(bytes32(uint256(0xA1))));
        uint256 node2 = Pointer.unwrap(LibPointer.allocatedMemoryPointer());
        kv = kv.set(keys[2], MemoryKVVal.wrap(bytes32(uint256(0xA2))));

        assertEq(node1, node0 + 0x60, "second node follows the first");
        assertEq(node2, node1 + 0x60, "third node follows the second");

        // The head is the newest node, and ONLY the newest -- the old head is
        // masked out of the slot rather than ored together with the new one.
        assertEq(slotPointer(kv, keys[0]), node2, "head is the newest node");
        assertEq(wordCount(kv), 6, "three pairs is six words");

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

    /// The word count is SIXTEEN bits, so it keeps counting past 0xFF. 200
    /// pairs is 400 words, which does not fit in a byte; a count that wrapped
    /// at 256 would both report the wrong number here and make `toBytes32Array`
    /// (which preallocates from it) return a short array.
    function testSetInsertWordCountPastAByte() external pure {
        uint256 pairs = 200;
        MemoryKV kv = MemoryKV.wrap(0);
        for (uint256 i = 1; i <= pairs; i++) {
            kv = kv.set(MemoryKVKey.wrap(bytes32(i)), MemoryKVVal.wrap(bytes32(i * 7)));
        }

        assertEq(wordCount(kv), pairs * 2, "400 words, not a count truncated to a byte on each insert");

        bytes32[] memory array = kv.toBytes32Array();
        assertEq(array.length, pairs * 2, "export is preallocated from the full count");

        for (uint256 i = 1; i <= pairs; i++) {
            (uint256 exists, MemoryKVVal value) = kv.get(MemoryKVKey.wrap(bytes32(i)));
            assertEq(exists, 1, "every key survives past the byte boundary");
            assertEq(uint256(MemoryKVVal.unwrap(value)), i * 7, "every value survives past the byte boundary");
        }
    }

    /// The overflow error carries the OFFENDING pointer, not the bound it
    /// crossed. `0x10000` is both the first invalid pointer and the value one
    /// past the bound, so it cannot tell the two apart; `0x12345` can.
    function testSetOverflowPayloadIsTheOffendingPointerNotTheBound() external {
        MemoryKVKey key = MemoryKVKey.wrap(bytes32(uint256(1)));
        MemoryKVVal value = MemoryKVVal.wrap(bytes32(uint256(2)));

        vm.expectRevert(abi.encodeWithSelector(LibMemoryKV.MemoryKVOverflow.selector, 0x12345));
        this.setAtFreePointerExternal(MemoryKV.wrap(0), key, value, 0x12345);
    }

    /// A pointer with bits above the low twelve must reach the slot intact: the
    /// slot is sixteen bits wide and an insert at `0xF000` must record exactly
    /// `0xF000`, not a truncation of it.
    function testSetInsertRecordsTheFullSixteenBitPointer(MemoryKVKey key, MemoryKVVal value) external view {
        MemoryKV kv = this.setAtFreePointerExternal(MemoryKV.wrap(0), key, value, 0xF000);
        assertEq(slotPointer(kv, key), 0xF000, "the whole 16 bit pointer reaches the slot");
        assertEq(wordCount(kv), 2, "one pair is two words");
    }

    /// The head pointer an insert produces exists ONLY in the returned store,
    /// which is why `set` documents that the return MUST be assigned back. The
    /// node is allocated and written either way, so a caller that drops the
    /// return is left holding the word it already had and the pair is reachable
    /// from nothing -- no revert, no short array, just a missing key.
    function testSetInsertIsUnreachableWhenTheReturnIsDropped(
        MemoryKVKey keyA,
        MemoryKVKey keyB,
        MemoryKVVal valueA,
        MemoryKVVal valueB
    ) external pure {
        vm.assume(MemoryKVKey.unwrap(keyA) != MemoryKVKey.unwrap(keyB));

        MemoryKV kv = MemoryKV.wrap(0).set(keyA, valueA);
        uint256 dropped = MemoryKV.unwrap(kv);

        uint256 nodeB = Pointer.unwrap(LibPointer.allocatedMemoryPointer());
        MemoryKV returned = kv.set(keyB, valueB);

        (bytes32 nodeKey, bytes32 nodeValue,) = readNode(nodeB);
        assertEq(nodeKey, MemoryKVKey.unwrap(keyB), "the node was written");
        assertEq(nodeValue, MemoryKVVal.unwrap(valueB), "with the value");

        assertEq(MemoryKV.unwrap(kv), dropped, "the dropped store is the word it already had");
        assertEq(wordCount(kv), 2, "the dropped store still counts one pair");
        assertEq(kv.toBytes32Array().length, 2, "and exports one pair");
        assertFalse(kv.has(keyB), "the insert is unreachable from the dropped store");

        assertEq(slotPointer(returned, keyB), nodeB, "the returned store heads the new node");
        assertEq(wordCount(returned), 4, "the returned store counts two pairs");
        (uint256 exists, MemoryKVVal value) = returned.get(keyB);
        assertEq(exists, 1, "the returned store has the key");
        assertEq(MemoryKVVal.unwrap(value), MemoryKVVal.unwrap(valueB), "and the value");
    }
}
