// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";

import {LibPointer, Pointer} from "rain-solmem-0.1.28/src/lib/LibPointer.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {keyForSlot, slotOf, collidingPairDifferingInBit, val} from "test/lib/LibMemoryKVKeys.sol";
import {lengthOf, headOf, craftNode, handleWith} from "test/lib/LibMemoryKVHandle.sol";
import {assertValue} from "test/lib/LibMemoryKVAssert.sol";
import {setFreePointer} from "test/lib/LibFreeMemory.sol";

/// @title LibMemoryKVSetUpdateTest
/// `set` hashes the key to one of `LibMemoryKV.LIST_COUNT` internal lists,
/// walks that list for a match, and on a match mutates the value in place.
/// Every case here states the VALUE the store must report afterwards.
contract LibMemoryKVSetUpdateTest is Test {
    using LibMemoryKV for MemoryKV;

    /// `set` must hash into the same list `get` reads from, for EVERY one of the
    /// `LibMemoryKV.LIST_COUNT` lists. The head pointer the store ends up
    /// holding names the list: it is in the slot the key hashes to and no
    /// other, and `get` reads the value back.
    function testSetHashesIntoTheSameListGetReads() external pure {
        for (uint256 slot = 0; slot < LibMemoryKV.LIST_COUNT; slot++) {
            MemoryKVKey key = keyForSlot(bytes32(slot + 1), slot);
            MemoryKV kv = MEMORY_KV_EMPTY.set(key, val(0xBEEF00 + slot));

            // The pointer went into the slot the key hashes to and nowhere else.
            assertTrue(headOf(kv, slot) > 0, "head");
            for (uint256 other = 0; other < LibMemoryKV.LIST_COUNT; other++) {
                if (other != slot) {
                    assertEq(headOf(kv, other), 0, "other slot");
                }
            }
            assertValue(kv, key, 0xBEEF00 + slot, "roundtrip");
            assertEq(lengthOf(kv), 2, "length");
        }
    }

    /// An update mutates the value word and NOTHING else: the returned store is
    /// bit for bit the store that went in, the word count is unchanged, and no
    /// memory was allocated.
    function testUpdateChangesOnlyTheValue() external pure {
        MemoryKVKey key = MemoryKVKey.wrap(bytes32(uint256(1)));
        MemoryKV kv = MEMORY_KV_EMPTY.set(key, val(11));
        uint256 before = MemoryKV.unwrap(kv);

        Pointer alloc0 = LibPointer.allocatedMemoryPointer();
        kv = kv.set(key, val(22));
        Pointer alloc1 = LibPointer.allocatedMemoryPointer();

        assertEq(Pointer.unwrap(alloc1), Pointer.unwrap(alloc0), "allocated");
        assertEq(MemoryKV.unwrap(kv), before, "kv word");
        assertEq(lengthOf(kv), 2, "length");
        assertValue(kv, key, 22, "updated");

        bytes32[] memory array = kv.toBytes32Array();
        assertEq(array.length, 2, "array length");
        assertEq(uint256(array[0]), 1, "array key");
        assertEq(uint256(array[1]), 22, "array value");
    }

    /// Updating one key of a list of colliding keys must land on that key's own
    /// node. The three keys below share one internal list, and the update
    /// through the middle key changes the middle value alone.
    function testUpdateFindsTheRightNodeAmongColliders() external pure {
        MemoryKVKey tail = keyForSlot(bytes32(uint256(0xA)), 0x07);
        MemoryKVKey middle = keyForSlot(bytes32(uint256(0xB)), 0x07);
        MemoryKVKey head = keyForSlot(bytes32(uint256(0xC)), 0x07);

        // Inserts prepend, so the last key set is the head and the first the tail.
        MemoryKV kv = MEMORY_KV_EMPTY.set(tail, val(1)).set(middle, val(2)).set(head, val(3));
        assertEq(lengthOf(kv), 6, "length before");

        uint256 before = MemoryKV.unwrap(kv);
        kv = kv.set(middle, val(200));
        assertEq(MemoryKV.unwrap(kv), before, "kv word");
        assertEq(lengthOf(kv), 6, "length after");

        assertValue(kv, tail, 1, "tail");
        assertValue(kv, middle, 200, "middle");
        assertValue(kv, head, 3, "head");
    }

    /// The walk must reach the far end of a list, which means following the next
    /// pointer at node+0x40 all the way down. The first key inserted is the last
    /// node of the list, so updating it is the longest walk there is.
    function testUpdateReachesTheTailOfALongList() external pure {
        uint256 count = 6;
        MemoryKVKey[] memory keys = new MemoryKVKey[](count);
        MemoryKV kv = MEMORY_KV_EMPTY;
        for (uint256 i = 0; i < count; i++) {
            keys[i] = keyForSlot(bytes32(0xD0 + i), 0x03);
            kv = kv.set(keys[i], val(i + 1));
        }
        assertEq(lengthOf(kv), count * 2, "length before");

        // keys[0] is the tail.
        uint256 before = MemoryKV.unwrap(kv);
        kv = kv.set(keys[0], val(0xF00D));
        assertEq(MemoryKV.unwrap(kv), before, "kv word");
        assertEq(lengthOf(kv), count * 2, "length after");

        assertValue(kv, keys[0], 0xF00D, "tail");
        for (uint256 i = 1; i < count; i++) {
            assertValue(kv, keys[i], i + 1, "untouched");
        }
    }

    /// Repeatedly upserting the same key allocates memory exactly once, for the
    /// single insert, and never grows the word count.
    function testRepeatedUpsertAllocatesOnce() external pure {
        MemoryKVKey key = MemoryKVKey.wrap(bytes32(uint256(0x5EED)));
        MemoryKV kv = MEMORY_KV_EMPTY;
        uint256 word;

        // Nothing but `set` runs between the two readings, so the whole delta
        // belongs to `set`.
        Pointer alloc0 = LibPointer.allocatedMemoryPointer();
        for (uint256 i = 1; i <= 64; i++) {
            kv = kv.set(key, val(i));
            if (i == 1) {
                word = MemoryKV.unwrap(kv);
            }
        }
        Pointer alloc1 = LibPointer.allocatedMemoryPointer();

        // One insert of one node, then 63 updates of nothing.
        assertEq(Pointer.unwrap(alloc1), Pointer.unwrap(alloc0) + LibMemoryKV.NODE_BYTES, "allocated");
        assertEq(MemoryKV.unwrap(kv), word, "kv word");
        assertEq(lengthOf(kv), 2, "length");
        assertValue(kv, key, 64, "latest");

        bytes32[] memory array = kv.toBytes32Array();
        assertEq(array.length, 2, "array length");
        assertEq(uint256(array[0]), 0x5EED, "array key");
        assertEq(uint256(array[1]), 64, "array value");
    }

    /// Writing the value a key already holds is a no-op on every observable: the
    /// store word, the word count, the allocation, and the export.
    function testUpdateToTheSameValueIsIdempotent(MemoryKVKey key, MemoryKVVal value) external pure {
        MemoryKV kv = MEMORY_KV_EMPTY.set(key, value);
        uint256 before = MemoryKV.unwrap(kv);
        bytes32[] memory arrayBefore = kv.toBytes32Array();

        Pointer alloc0 = LibPointer.allocatedMemoryPointer();
        kv = kv.set(key, value);
        Pointer alloc1 = LibPointer.allocatedMemoryPointer();

        assertEq(Pointer.unwrap(alloc1), Pointer.unwrap(alloc0), "allocated");
        assertEq(MemoryKV.unwrap(kv), before, "kv word");

        bytes32[] memory arrayAfter = kv.toBytes32Array();
        assertEq(arrayAfter.length, 2, "array length");
        assertEq(arrayBefore[0], arrayAfter[0], "array key");
        assertEq(arrayBefore[1], arrayAfter[1], "array value");
    }

    /// A key set to zero, then to the maximum, then back to zero. Existence never
    /// wavers and the value is whatever was last written, including zero.
    function testUpdateAcrossTheZeroAndMaxEdges() external pure {
        MemoryKVKey key = MemoryKVKey.wrap(bytes32(uint256(0)));
        MemoryKV kv = MEMORY_KV_EMPTY.set(key, val(0));
        uint256 before = MemoryKV.unwrap(kv);
        assertValue(kv, key, 0, "zero");

        kv = kv.set(key, MemoryKVVal.wrap(bytes32(type(uint256).max)));
        assertEq(MemoryKV.unwrap(kv), before, "kv word max");
        assertValue(kv, key, type(uint256).max, "max");

        kv = kv.set(key, val(0));
        assertEq(MemoryKV.unwrap(kv), before, "kv word back");
        assertValue(kv, key, 0, "back to zero");
        assertEq(lengthOf(kv), 2, "length");
    }

    /// Updating a key in one internal list leaves every other list alone: same
    /// head pointers, same values.
    function testUpdateIsIsolatedBetweenLists() external pure {
        MemoryKVKey[] memory keys = new MemoryKVKey[](LibMemoryKV.LIST_COUNT);
        MemoryKV kv = MEMORY_KV_EMPTY;
        for (uint256 slot = 0; slot < LibMemoryKV.LIST_COUNT; slot++) {
            keys[slot] = keyForSlot(bytes32(0x1000 + slot), slot);
            kv = kv.set(keys[slot], val(slot + 1));
        }
        assertEq(lengthOf(kv), LibMemoryKV.LIST_COUNT * 2, "length before");
        uint256 before = MemoryKV.unwrap(kv);

        // Update each list in turn, including the last, whose pointer sits
        // directly under the word count.
        for (uint256 target = 0; target < LibMemoryKV.LIST_COUNT; target++) {
            kv = kv.set(keys[target], val(0xABC00 + target));
            assertEq(MemoryKV.unwrap(kv), before, "kv word");
            assertEq(lengthOf(kv), LibMemoryKV.LIST_COUNT * 2, "length after");
            for (uint256 slot = 0; slot < LibMemoryKV.LIST_COUNT; slot++) {
                assertValue(kv, keys[slot], slot <= target ? 0xABC00 + slot : slot + 1, "value");
            }
            assertEq(kv.toBytes32Array().length, LibMemoryKV.LIST_COUNT * 2, "array length");
        }
    }

    /// The word count the store carries must stay equal to twice the number of
    /// distinct keys, however many times those keys are rewritten, and the
    /// export is that many words long.
    function testWordCountCountsDistinctKeysOnly(MemoryKVKey[] memory keys, MemoryKVVal value) external pure {
        vm.assume(keys.length <= 20);
        MemoryKV kv = MEMORY_KV_EMPTY;
        uint256 distinct = 0;
        for (uint256 i = 0; i < keys.length; i++) {
            if (!kv.has(keys[i])) {
                distinct++;
            }
            kv = kv.set(keys[i], value);
            // Every key seen so far is still readable.
            assertValue(kv, keys[i], uint256(MemoryKVVal.unwrap(value)), "readable");
        }
        assertEq(lengthOf(kv), distinct * 2, "length");

        // Rewriting every key changes neither the count nor the store word.
        uint256 before = MemoryKV.unwrap(kv);
        for (uint256 i = 0; i < keys.length; i++) {
            kv = kv.set(keys[i], value);
        }
        assertEq(MemoryKV.unwrap(kv), before, "kv word");
        assertEq(lengthOf(kv), distinct * 2, "length after");
        assertEq(kv.toBytes32Array().length, distinct * 2, "array length");
    }

    /// The match compares the whole 256 bit key word. Each pair below shares
    /// one internal list and differs in a single bit, at the top and at the
    /// bottom of the word, and setting the second key inserts it: two pairs,
    /// each key with its own value.
    function testSetDistinguishesKeysDifferingInOneBit() external pure {
        uint256[2] memory bits = [uint256(0), 0xff];
        for (uint256 i = 0; i < bits.length; i++) {
            (MemoryKVKey first, MemoryKVKey second) = collidingPairDifferingInBit(0, bits[i]);
            assertEq(slotOf(MemoryKVKey.unwrap(first)), slotOf(MemoryKVKey.unwrap(second)), "one list");

            MemoryKV kv = MEMORY_KV_EMPTY.set(first, val(11)).set(second, val(22));

            assertEq(lengthOf(kv), 4, "both keys stored");
            assertValue(kv, first, 11, "first");
            assertValue(kv, second, 22, "second");
            assertEq(kv.toBytes32Array().length, 4, "array length");
        }
    }

    /// The match compares every bit of the key. A crafted node on the key's
    /// list holding the key itself is updated in place. Holding the key with
    /// any one of its 256 bits flipped, it holds a different key: setting the
    /// key inserts a node that heads the list, grows the count, and leaves the
    /// crafted node's value as it was.
    function testSetRequiresEveryBitOfTheKey() external pure {
        MemoryKVKey key = MemoryKVKey.wrap(bytes32(type(uint256).max / 3));
        uint256 node = craftNode(key, val(0xDEC0DE), 0);
        MemoryKV kv = handleWith(slotOf(MemoryKVKey.unwrap(key)), node, 2);
        Pointer nodeKey = Pointer.wrap(node);
        Pointer nodeValue = LibPointer.unsafeAddWord(nodeKey);

        MemoryKV same = kv.set(key, val(1));
        assertEq(MemoryKV.unwrap(same), MemoryKV.unwrap(kv), "the key itself updates in place");
        assertEq(uint256(LibPointer.unsafeReadWord(nodeValue)), 1, "the update wrote the crafted node");

        // Every insert below starts its node here, so each is read against the
        // same head.
        uint256 free = Pointer.unwrap(LibPointer.allocatedMemoryPointer());
        // Every bit in turn, ending when the walking bit falls off the top.
        for (uint256 bit = 1; bit != 0; bit <<= 1) {
            LibPointer.unsafeWriteWord(nodeKey, bytes32(uint256(MemoryKVKey.unwrap(key)) ^ bit));
            setFreePointer(free);
            MemoryKV inserted = kv.set(key, val(2));
            assertEq(lengthOf(inserted), 4, "one bit apart is a different key, so this is an insert");
            assertEq(headOf(inserted, key), free, "the insert heads the list at the new node");
            assertEq(
                uint256(LibPointer.unsafeReadWord(nodeValue)), 1, "one bit apart leaves the crafted node's value alone"
            );
        }
    }
}
