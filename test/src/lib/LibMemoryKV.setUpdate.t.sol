// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {LibPointer, Pointer} from "rain-solmem-0.1.28/src/lib/LibPointer.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {keyForSlot, slotOf, collidingPairDifferingInBit, val} from "test/lib/LibMemoryKVKeys.sol";
import {lengthOf, headOf, maskOf, occupancyBitOf} from "test/lib/LibMemoryKVHandle.sol";
import {assertValue} from "test/lib/LibMemoryKVAssert.sol";

/// @title LibMemoryKVSetUpdateTest
/// `set` hashes the key to one of `LibMemoryKV.LIST_COUNT` internal lists,
/// walks that list for a match, and on a match mutates the value in place.
/// Every case here states the VALUE the store must report afterwards, so a walk
/// that finds the wrong node, a hash that disagrees with `get`, or an "update"
/// that allocates or writes the header shows up as a different number rather
/// than as a revert.
contract LibMemoryKVSetUpdateTest is Test {
    using LibMemoryKV for MemoryKV;

    /// The words in a header.
    uint256 internal constant HEADER_WORDS = LibMemoryKV.HEADER_BYTES / 0x20;

    /// A copy of every word of the header at `kv`, so an update can be checked
    /// against the header it started from.
    function headerWords(MemoryKV kv) internal pure returns (bytes32[] memory words) {
        words = new bytes32[](HEADER_WORDS);
        for (uint256 i = 0; i < HEADER_WORDS; i++) {
            words[i] = LibPointer.unsafeReadWord(Pointer.wrap(MemoryKV.unwrap(kv) + i * 0x20));
        }
    }

    /// Every word of the header at `kv` is the word `before` holds for it.
    function assertHeaderIs(MemoryKV kv, bytes32[] memory before, string memory err) internal pure {
        for (uint256 i = 0; i < HEADER_WORDS; i++) {
            assertEq(
                LibPointer.unsafeReadWord(Pointer.wrap(MemoryKV.unwrap(kv) + i * 0x20)),
                before[i],
                string.concat(err, " header word ", vm.toString(i))
            );
        }
    }

    /// `set` must hash into the same list `get` reads from, for EVERY one of the
    /// `LibMemoryKV.LIST_COUNT` lists. The head the store ends up holding names
    /// the list, so a set that hashed differently (different preimage, different
    /// modulus, different head stride) parks the head in the wrong word and the
    /// value is no longer readable.
    function testSetHashesIntoTheSameListGetReads() external pure {
        for (uint256 slot = 0; slot < LibMemoryKV.LIST_COUNT; slot++) {
            MemoryKVKey key = keyForSlot(bytes32(slot + 1), slot);
            MemoryKV kv = MEMORY_KV_EMPTY.set(key, val(0xBEEF00 + slot));

            // The head went into the list the key hashes to and nowhere else.
            assertTrue(headOf(kv, slot) > 0, "head");
            for (uint256 other = 0; other < LibMemoryKV.LIST_COUNT; other++) {
                if (other != slot) {
                    assertEq(headOf(kv, other), 0, "other list");
                }
            }
            assertValue(kv, key, 0xBEEF00 + slot, "roundtrip");
            assertEq(lengthOf(kv), 2, "length");
        }
    }

    /// An update mutates the value word and NOTHING else: the returned handle is
    /// the handle that went in, every header word is unchanged, and no memory
    /// was allocated.
    function testUpdateChangesOnlyTheValue() external pure {
        MemoryKVKey key = MemoryKVKey.wrap(bytes32(uint256(1)));
        MemoryKV kv = MEMORY_KV_EMPTY.set(key, val(11));
        uint256 before = MemoryKV.unwrap(kv);
        bytes32[] memory header = headerWords(kv);

        Pointer alloc0 = LibPointer.allocatedMemoryPointer();
        kv = kv.set(key, val(22));
        Pointer alloc1 = LibPointer.allocatedMemoryPointer();

        assertEq(Pointer.unwrap(alloc1), Pointer.unwrap(alloc0), "allocated");
        assertEq(MemoryKV.unwrap(kv), before, "handle");
        assertHeaderIs(kv, header, "update");
        assertValue(kv, key, 22, "updated");

        bytes32[] memory array = kv.toBytes32Array();
        assertEq(array.length, 2, "array length");
        assertEq(uint256(array[0]), 1, "array key");
        assertEq(uint256(array[1]), 22, "array value");
    }

    /// Updating one key of a list of colliding keys must land on that key's own
    /// node. The three keys below share one internal list, so a walk that never
    /// runs, or that compares the wrong word, writes the value onto whichever
    /// node it stopped at instead.
    function testUpdateFindsTheRightNodeAmongColliders() external pure {
        MemoryKVKey a = keyForSlot(bytes32(uint256(0xA)), 0x07);
        MemoryKVKey b = keyForSlot(bytes32(uint256(0xB)), 0x07);
        MemoryKVKey c = keyForSlot(bytes32(uint256(0xC)), 0x07);

        MemoryKV kv = MEMORY_KV_EMPTY.set(a, val(1)).set(b, val(2)).set(c, val(3));
        assertEq(lengthOf(kv), 6, "length before");

        // `c` was inserted last so it is the head. Update the MIDDLE node.
        uint256 before = MemoryKV.unwrap(kv);
        bytes32[] memory header = headerWords(kv);
        kv = kv.set(b, val(200));
        assertEq(MemoryKV.unwrap(kv), before, "handle");
        assertHeaderIs(kv, header, "update");

        assertValue(kv, a, 1, "a");
        assertValue(kv, b, 200, "b");
        assertValue(kv, c, 3, "c");
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
        bytes32[] memory header = headerWords(kv);
        kv = kv.set(keys[0], val(0xF00D));
        assertEq(MemoryKV.unwrap(kv), before, "handle");
        assertHeaderIs(kv, header, "update");

        assertValue(kv, keys[0], 0xF00D, "tail");
        for (uint256 i = 1; i < count; i++) {
            assertValue(kv, keys[i], i + 1, "untouched");
        }
    }

    /// Repeatedly upserting the same key allocates memory exactly once, for the
    /// single insert's header and node, and never grows the word count or moves
    /// the head.
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

        // One insert of a header and a node, then 63 updates of nothing.
        assertEq(
            Pointer.unwrap(alloc1),
            Pointer.unwrap(alloc0) + LibMemoryKV.HEADER_BYTES + LibMemoryKV.NODE_BYTES,
            "allocated"
        );
        assertEq(MemoryKV.unwrap(kv), word, "handle");
        assertEq(headOf(kv, key), Pointer.unwrap(alloc0) + LibMemoryKV.HEADER_BYTES, "head");
        assertEq(lengthOf(kv), 2, "length");
        assertEq(maskOf(kv), occupancyBitOf(slotOf(MemoryKVKey.unwrap(key))), "mask");
        assertValue(kv, key, 64, "latest");

        bytes32[] memory array = kv.toBytes32Array();
        assertEq(array.length, 2, "array length");
        assertEq(uint256(array[0]), 0x5EED, "array key");
        assertEq(uint256(array[1]), 64, "array value");
    }

    /// Writing the value a key already holds is a no-op on every observable: the
    /// handle, the header, the allocation, and the export.
    function testUpdateToTheSameValueIsIdempotent(MemoryKVKey key, MemoryKVVal value) external pure {
        MemoryKV kv = MEMORY_KV_EMPTY.set(key, value);
        uint256 before = MemoryKV.unwrap(kv);
        bytes32[] memory header = headerWords(kv);
        bytes32[] memory arrayBefore = kv.toBytes32Array();

        Pointer alloc0 = LibPointer.allocatedMemoryPointer();
        kv = kv.set(key, value);
        Pointer alloc1 = LibPointer.allocatedMemoryPointer();

        assertEq(Pointer.unwrap(alloc1), Pointer.unwrap(alloc0), "allocated");
        assertEq(MemoryKV.unwrap(kv), before, "handle");
        assertHeaderIs(kv, header, "update");

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
        bytes32[] memory header = headerWords(kv);
        assertValue(kv, key, 0, "zero");

        kv = kv.set(key, MemoryKVVal.wrap(bytes32(type(uint256).max)));
        assertEq(MemoryKV.unwrap(kv), before, "handle max");
        assertHeaderIs(kv, header, "max");
        assertValue(kv, key, type(uint256).max, "max");

        kv = kv.set(key, val(0));
        assertEq(MemoryKV.unwrap(kv), before, "handle back");
        assertHeaderIs(kv, header, "back");
        assertValue(kv, key, 0, "back to zero");
    }

    /// Updating a key in one internal list leaves every other list alone: same
    /// heads, same values.
    function testUpdateIsIsolatedBetweenLists() external pure {
        MemoryKVKey[] memory keys = new MemoryKVKey[](LibMemoryKV.LIST_COUNT);
        MemoryKV kv = MEMORY_KV_EMPTY;
        for (uint256 slot = 0; slot < LibMemoryKV.LIST_COUNT; slot++) {
            keys[slot] = keyForSlot(bytes32(0x1000 + slot), slot);
            kv = kv.set(keys[slot], val(slot + 1));
        }
        uint256 words = 2 * LibMemoryKV.LIST_COUNT;
        assertEq(lengthOf(kv), words, "length before");
        uint256 before = MemoryKV.unwrap(kv);
        bytes32[] memory header = headerWords(kv);

        // Update each list in turn, including the last, whose head word sits
        // directly under the meta word.
        for (uint256 target = 0; target < LibMemoryKV.LIST_COUNT; target++) {
            kv = kv.set(keys[target], val(0xABC00 + target));
            assertEq(MemoryKV.unwrap(kv), before, "handle");
            assertHeaderIs(kv, header, "update");
            for (uint256 slot = 0; slot < LibMemoryKV.LIST_COUNT; slot++) {
                assertValue(kv, keys[slot], slot <= target ? 0xABC00 + slot : slot + 1, "value");
            }
            assertEq(kv.toBytes32Array().length, words, "array length");
        }
    }

    /// The word count the store carries must stay equal to twice the number of
    /// distinct keys, however many times those keys are rewritten. A count that
    /// drifted up on updates would make the export allocate and report slots the
    /// linked lists never fill.
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

        // Rewriting every key changes neither the handle nor the header. The
        // empty store has no header to compare.
        uint256 before = MemoryKV.unwrap(kv);
        bytes32[] memory header = before == 0 ? new bytes32[](0) : headerWords(kv);
        for (uint256 i = 0; i < keys.length; i++) {
            kv = kv.set(keys[i], value);
        }
        assertEq(MemoryKV.unwrap(kv), before, "handle");
        if (before != 0) {
            assertHeaderIs(kv, header, "rewrite");
        }
        assertEq(kv.toBytes32Array().length, distinct * 2, "array length");
    }

    /// The match compares the whole 256 bit key word. Each pair below shares
    /// one internal list and differs in a single bit, at the top and at the
    /// bottom of the word, so a comparison narrowed at either end would stop at
    /// the first key's node and overwrite its value instead of inserting the
    /// second key, leaving one pair where there must be two.
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
}
