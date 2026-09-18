// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";

import {LibPointer, Pointer} from "rain-solmem-0.1.28/src/lib/LibPointer.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {SetAtFreePointer} from "test/lib/SetAtFreePointer.sol";
import {dirtyFreeMemory} from "test/lib/LibFreeMemory.sol";
import {collidingKey, keyForSlot, keysInSlot, slotOf} from "test/lib/LibMemoryKVKeys.sol";
import {headAddressOf, headOf, lengthOf, maskOf, metaOf, occupancyBitOf} from "test/lib/LibMemoryKVHandle.sol";

/// @title LibMemoryKVSetInsertTest
/// The insert half of `set`, asserted against the documented SHAPE of the store
/// rather than against a round trip through `get`.
///
/// The layout is the one the `MemoryKV` NatSpec documents and the `LibMemoryKV`
/// constants name. The first insert into the empty store allocates a
/// `LibMemoryKV.HEADER_BYTES` header at the free memory pointer, zeroed, and
/// the handle is its address. Every insert then places a
/// `LibMemoryKV.NODE_BYTES` key/value/next node at the free memory pointer,
/// prepends it to its list, adds two to the word count in the meta word and
/// sets the list's occupancy bit.
contract LibMemoryKVSetInsertTest is Test, SetAtFreePointer {
    using LibMemoryKV for MemoryKV;

    /// The words in a header.
    uint256 internal constant HEADER_WORDS = LibMemoryKV.HEADER_BYTES / 0x20;

    /// The words the first insert into the empty store writes: its header,
    /// then its node.
    uint256 internal constant FIRST_INSERT_WORDS = (LibMemoryKV.HEADER_BYTES + LibMemoryKV.NODE_BYTES) / 0x20;

    /// The three words of a list node as written by an insert.
    function readNode(uint256 pointer) internal pure returns (bytes32 nodeKey, bytes32 nodeValue, uint256 next) {
        assembly ("memory-safe") {
            nodeKey := mload(pointer)
            nodeValue := mload(add(pointer, 0x20))
            next := mload(add(pointer, 0x40))
        }
    }

    function wordAt(uint256 pointer) internal pure returns (bytes32) {
        return LibPointer.unsafeReadWord(Pointer.wrap(pointer));
    }

    /// An insert into the empty store allocates exactly a header then a node
    /// AT the free memory pointer, and returns the header's address. The
    /// header heads the key's list with the node and its meta word counts one
    /// pair and marks that list alone occupied. The node is key, then value,
    /// then the old head of the list.
    ///
    /// Stated as exact addresses and words rather than as "the value comes back
    /// out", so a header or node written next to the free memory pointer, a
    /// head holding an address the node is not at, or a next word that is not
    /// the old head is a different NUMBER here, not just a failed lookup.
    function testSetInsertIntoTheEmptyStoreAllocatesAHeaderThenANode(MemoryKVKey key, MemoryKVVal value) external pure {
        uint256 start = Pointer.unwrap(LibPointer.allocatedMemoryPointer());
        MemoryKV kv = MEMORY_KV_EMPTY.set(key, value);
        uint256 allocatedAfter = Pointer.unwrap(LibPointer.allocatedMemoryPointer());
        uint256 node = start + LibMemoryKV.HEADER_BYTES;
        uint256 bit = occupancyBitOf(slotOf(MemoryKVKey.unwrap(key)));

        assertEq(MemoryKV.unwrap(kv), start, "the handle is the header, at the free memory pointer");
        assertEq(allocatedAfter, node + LibMemoryKV.NODE_BYTES, "a header and one node allocated");
        assertEq(headOf(kv, key), node, "list head is the node after the header");
        assertEq(lengthOf(kv), 2, "one pair is two words");
        assertEq(maskOf(kv), bit, "the key's list alone is occupied");
        assertEq(metaOf(kv), LibMemoryKV.PAIR_COUNT_INCREMENT | bit, "meta is one pair and the mask alone");

        (bytes32 nodeKey, bytes32 nodeValue, uint256 next) = readNode(node);
        assertEq(nodeKey, MemoryKVKey.unwrap(key), "key at node+0x00");
        assertEq(nodeValue, MemoryKVVal.unwrap(value), "value at node+0x20");
        assertEq(next, 0, "next at node+0x40 is the old (empty) head");
    }

    /// An insert WRITES all three words of its node. A zero key, a zero value
    /// and the terminator of an empty list are what the node HOLDS, not what
    /// the memory under it happened to hold: the node lands on a sentinel here,
    /// so a word the insert leaves alone reads back as that sentinel instead.
    function testSetInsertWritesEveryWordOfTheNode(bytes32 seed) external pure {
        bytes32 sentinel = keccak256(abi.encode(seed));
        MemoryKVKey key = MemoryKVKey.wrap(bytes32(0));
        MemoryKVVal value = MemoryKVVal.wrap(bytes32(0));

        dirtyFreeMemory(sentinel, FIRST_INSERT_WORDS);

        uint256 node = Pointer.unwrap(LibPointer.allocatedMemoryPointer()) + LibMemoryKV.HEADER_BYTES;
        MemoryKV kv = MEMORY_KV_EMPTY.set(key, value);

        (bytes32 nodeKey, bytes32 nodeValue, uint256 next) = readNode(node);
        assertEq(nodeKey, bytes32(0), "zero key written at node+0x00");
        assertEq(nodeValue, bytes32(0), "zero value written at node+0x20");
        assertEq(next, 0, "terminator written at node+0x40");

        (uint256 exists, MemoryKVVal got) = kv.get(key);
        assertEq(exists, 1, "the zero key exists");
        assertEq(MemoryKVVal.unwrap(got), bytes32(0), "and reads back zero, not the sentinel");
    }

    /// Memory above the free memory pointer is not guaranteed zero, so the
    /// first insert zeroes the header it allocates. Over a sentinel, every
    /// word of the header is exactly what the insert means it to be: the key's
    /// head is the node, every other head is `0`, and the meta word is the
    /// count and the one occupancy bit. A word the insert leaves alone reads
    /// back as the sentinel, and a dirty head is a list that is not there.
    function testSetInsertZeroesTheHeaderOverDirtyMemory(bytes32 sentinel, MemoryKVKey key, MemoryKVVal value)
        external
        pure
    {
        vm.assume(sentinel != 0);
        uint256 start = Pointer.unwrap(LibPointer.allocatedMemoryPointer());
        dirtyFreeMemory(sentinel, FIRST_INSERT_WORDS);

        MemoryKV kv = MEMORY_KV_EMPTY.set(key, value);
        uint256 node = start + LibMemoryKV.HEADER_BYTES;
        uint256 slot = slotOf(MemoryKVKey.unwrap(key));

        uint256 meta = LibMemoryKV.PAIR_COUNT_INCREMENT | occupancyBitOf(slot);
        uint256 head = headAddressOf(kv, slot);
        uint256 metaAddress = MemoryKV.unwrap(kv) + LibMemoryKV.META_OFFSET;
        for (uint256 i = 0; i < HEADER_WORDS; i++) {
            uint256 at = MemoryKV.unwrap(kv) + i * 0x20;
            assertEq(
                uint256(wordAt(at)),
                at == metaAddress ? meta : at == head ? node : 0,
                string.concat("header word ", vm.toString(i))
            );
        }
    }

    /// Three keys that share one list: each insert PREPENDS, so the head is the
    /// newest node and every older node is still reachable behind it. Asserts
    /// the chain of addresses, which is the fact that "nothing inserted is
    /// lost" rests on. Only the first insert allocates a header: every later
    /// one allocates its node alone and returns the same handle.
    function testSetInsertPrependsWithinOneList() external pure {
        MemoryKVKey[] memory keys = keysInSlot(bytes32(uint256(1)), 0, 3);
        MemoryKV kv = MEMORY_KV_EMPTY;

        uint256 header = Pointer.unwrap(LibPointer.allocatedMemoryPointer());
        kv = kv.set(keys[0], MemoryKVVal.wrap(bytes32(uint256(0xA0))));
        uint256 node0 = header + LibMemoryKV.HEADER_BYTES;
        uint256 node1 = Pointer.unwrap(LibPointer.allocatedMemoryPointer());
        kv = kv.set(keys[1], MemoryKVVal.wrap(bytes32(uint256(0xA1))));
        uint256 node2 = Pointer.unwrap(LibPointer.allocatedMemoryPointer());
        kv = kv.set(keys[2], MemoryKVVal.wrap(bytes32(uint256(0xA2))));
        uint256 end = Pointer.unwrap(LibPointer.allocatedMemoryPointer());

        assertEq(MemoryKV.unwrap(kv), header, "every insert returns the one header");
        assertEq(node1, node0 + LibMemoryKV.NODE_BYTES, "second node follows the first");
        assertEq(node2, node1 + LibMemoryKV.NODE_BYTES, "third node follows the second");
        assertEq(end, node2 + LibMemoryKV.NODE_BYTES, "the third insert allocates its node alone");

        // The head is the newest node, and ONLY the newest: the head word is
        // overwritten with the new node rather than combined with the old one.
        assertEq(headOf(kv, keys[0]), node2, "head is the newest node");
        assertEq(lengthOf(kv), 6, "three pairs is six words");
        assertEq(maskOf(kv), occupancyBitOf(0), "one list, one occupancy bit");

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

    /// Each list's first insert sets that list's occupancy bit and no other,
    /// and a second pair in an occupied list sets nothing new. The lists are
    /// filled in an order the seed picks, so a bit that tracked the insert
    /// count rather than the list fails here.
    function testSetInsertSetsOneOccupancyBitPerList(bytes32 seed, uint256 offset) external pure {
        MemoryKV kv = MEMORY_KV_EMPTY;
        uint256 expected = 0;
        for (uint256 i = 0; i < LibMemoryKV.LIST_COUNT; i++) {
            // 7 is coprime to 15, so this visits every list once.
            uint256 slot = (offset % LibMemoryKV.LIST_COUNT + i * 7) % LibMemoryKV.LIST_COUNT;
            MemoryKVKey key = keyForSlot(keccak256(abi.encode(seed, i)), slot);

            kv = kv.set(key, MemoryKVVal.wrap(bytes32(i)));
            expected |= occupancyBitOf(slot);
            assertEq(maskOf(kv), expected, string.concat("the first pair in list ", vm.toString(slot)));

            kv = kv.set(collidingKey(key), MemoryKVVal.wrap(bytes32(i)));
            assertEq(maskOf(kv), expected, string.concat("a second pair in list ", vm.toString(slot)));
            assertEq(lengthOf(kv), (i + 1) * 4, "two pairs per list so far");
        }
        assertEq(maskOf(kv), LibMemoryKV.OCCUPANCY_MASK, "every list occupied");
    }

    /// The word count is every bit of the meta word above
    /// `LibMemoryKV.COUNT_BIT_OFFSET`, so it keeps counting past 0xFF. 200
    /// pairs is 400 words, which does not fit in a byte; a count that wrapped
    /// at 256 would both report the wrong number here and make
    /// `toBytes32Array` (which preallocates from it) return a short array.
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

    /// The handle and the head are whole addresses. From a free memory pointer
    /// with bits above the low sixteen, and not a multiple of 32, the handle
    /// is exactly that address and the head exactly the node after the
    /// header, not a truncation or a rounding of either.
    function testSetInsertRecordsTheWholeAddress(MemoryKVKey key, MemoryKVVal value) external pure {
        uint256 at = 0x12345;
        MemoryKV kv = setAtFreePointerInFrame(MEMORY_KV_EMPTY, key, value, at);
        assertEq(MemoryKV.unwrap(kv), at, "the whole address is the handle");
        assertEq(headOf(kv, key), at + LibMemoryKV.HEADER_BYTES, "the whole node address is the head");
        assertEq(lengthOf(kv), 2, "one pair is two words");

        (uint256 exists, MemoryKVVal got) = kv.get(key);
        assertEq(exists, 1, "the key exists");
        assertEq(MemoryKVVal.unwrap(got), MemoryKVVal.unwrap(value), "the value reads back");
    }

    /// Once the store has a header, the handle is its address and every insert
    /// writes into that header, so a caller that drops the return of a later
    /// insert still holds the whole store: the dropped handle is the returned
    /// one, and it counts, exports and finds the new pair.
    function testSetInsertIsReachableThroughADroppedLaterReturn(
        MemoryKVKey keyA,
        MemoryKVKey keyB,
        MemoryKVVal valueA,
        MemoryKVVal valueB
    ) external pure {
        vm.assume(MemoryKVKey.unwrap(keyA) != MemoryKVKey.unwrap(keyB));

        MemoryKV kv = MEMORY_KV_EMPTY.set(keyA, valueA);
        uint256 kept = MemoryKV.unwrap(kv);

        uint256 nodeB = Pointer.unwrap(LibPointer.allocatedMemoryPointer());
        MemoryKV returned = kv.set(keyB, valueB);

        assertEq(MemoryKV.unwrap(returned), kept, "the return is the handle passed in");
        assertEq(headOf(kv, keyB), nodeB, "the kept handle heads the new node");
        assertEq(lengthOf(kv), 4, "the kept handle counts two pairs");
        assertEq(kv.toBytes32Array().length, 4, "and exports two pairs");
        (uint256 exists, MemoryKVVal value) = kv.get(keyB);
        assertEq(exists, 1, "the kept handle has the new key");
        assertEq(MemoryKVVal.unwrap(value), MemoryKVVal.unwrap(valueB), "and its value");
    }

    /// The first insert allocates the header, and its address exists ONLY in
    /// the returned handle, which is why `set` documents that the return MUST
    /// be assigned back. A caller that drops it still holds the empty store:
    /// no revert, no header, just a store with nothing in it.
    function testSetFirstInsertIsLostWhenTheReturnIsDropped(MemoryKVKey key, MemoryKVVal value) external pure {
        MemoryKV kv = MEMORY_KV_EMPTY;
        MemoryKV returned = kv.set(key, value);

        assertEq(MemoryKV.unwrap(kv), 0, "the dropped handle is still the empty store");
        assertFalse(kv.has(key), "the insert is unreachable from the dropped handle");
        assertEq(kv.toBytes32Array().length, 0, "which exports nothing");
        assertTrue(MemoryKV.unwrap(returned) != 0, "the returned handle has a header");
        assertTrue(returned.has(key), "and the key");
    }
}
