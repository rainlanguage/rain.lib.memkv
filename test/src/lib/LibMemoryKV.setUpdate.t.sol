// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {LibPointer, Pointer} from "rain-solmem-0.1.28/src/lib/LibPointer.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal} from "src/lib/LibMemoryKV.sol";

/// @title LibMemoryKVSetUpdateTest
/// `set` hashes the key to one of 15 internal lists, walks that list for a
/// match, and on a match mutates the value in place. Every case here states the
/// VALUE the store must report afterwards, so a walk that finds the wrong node,
/// a hash that disagrees with `get`, or an "update" that allocates shows up as a
/// different number rather than as a revert.
contract LibMemoryKVSetUpdateTest is Test {
    using LibMemoryKV for MemoryKV;

    /// The internal list a key belongs to. This is the store's own hash, which
    /// `get` and `set` MUST both use, restated here so the tests can aim keys at
    /// a chosen list rather than hoping a fuzzer collides two.
    function slotOf(MemoryKVKey key) internal pure returns (uint256 slot) {
        assembly ("memory-safe") {
            mstore(0, key)
            slot := mod(keccak256(0, 0x20), 15)
        }
    }

    /// Rehash `seed` until the key lands in `slot`.
    function keyForSlot(bytes32 seed, uint256 slot) internal pure returns (MemoryKVKey) {
        bytes32 key = seed;
        for (uint256 i = 0; i < 10000; i++) {
            if (slotOf(MemoryKVKey.wrap(key)) == slot) {
                return MemoryKVKey.wrap(key);
            }
            key = keccak256(abi.encodePacked(key));
        }
        revert("no key for slot");
    }

    /// The word count the store carries in its top 16 bits.
    function lengthOf(MemoryKV kv) internal pure returns (uint256) {
        return MemoryKV.unwrap(kv) >> 0xf0;
    }

    /// The 16 bit head pointer the store holds for `slot`.
    function headOf(MemoryKV kv, uint256 slot) internal pure returns (uint256) {
        return (MemoryKV.unwrap(kv) >> (slot * 0x10)) & 0xFFFF;
    }

    /// Assert the store reports exactly `value` for `key`.
    function assertValue(MemoryKV kv, MemoryKVKey key, uint256 value, string memory err) internal pure {
        (uint256 exists, MemoryKVVal got) = kv.get(key);
        assertEq(exists, 1, string.concat(err, " exists"));
        assertEq(uint256(MemoryKVVal.unwrap(got)), value, string.concat(err, " value"));
    }

    function val(uint256 v) internal pure returns (MemoryKVVal) {
        return MemoryKVVal.wrap(bytes32(v));
    }

    /// `set` must hash into the same list `get` reads from, for EVERY one of the
    /// 15 lists. The head pointer the store ends up holding names the list, so a
    /// set that hashed differently (different preimage, different modulus,
    /// different bit stride) parks the pointer in the wrong slot and the value
    /// is no longer readable.
    function testSetHashesIntoTheSameListGetReads() external pure {
        for (uint256 slot = 0; slot < 15; slot++) {
            MemoryKVKey key = keyForSlot(bytes32(slot + 1), slot);
            MemoryKV kv = MemoryKV.wrap(0).set(key, val(0xBEEF00 + slot));

            // The pointer went into the slot the key hashes to and nowhere else.
            assertTrue(headOf(kv, slot) > 0, "head");
            for (uint256 other = 0; other < 15; other++) {
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
        MemoryKV kv = MemoryKV.wrap(0).set(key, val(11));
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
    /// node. The three keys below share one internal list, so a walk that never
    /// runs, or that compares the wrong word, writes the value onto whichever
    /// node it stopped at instead.
    function testUpdateFindsTheRightNodeAmongColliders() external pure {
        MemoryKVKey a = keyForSlot(bytes32(uint256(0xA)), 7);
        MemoryKVKey b = keyForSlot(bytes32(uint256(0xB)), 7);
        MemoryKVKey c = keyForSlot(bytes32(uint256(0xC)), 7);

        MemoryKV kv = MemoryKV.wrap(0).set(a, val(1)).set(b, val(2)).set(c, val(3));
        assertEq(lengthOf(kv), 6, "length before");

        // `c` was inserted last so it is the head. Update the MIDDLE node.
        uint256 before = MemoryKV.unwrap(kv);
        kv = kv.set(b, val(200));
        assertEq(MemoryKV.unwrap(kv), before, "kv word");
        assertEq(lengthOf(kv), 6, "length after");

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
        MemoryKV kv = MemoryKV.wrap(0);
        for (uint256 i = 0; i < count; i++) {
            keys[i] = keyForSlot(bytes32(0xD0 + i), 3);
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
        MemoryKV kv = MemoryKV.wrap(0);
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

        // One insert of 3 words, then 63 updates of nothing.
        assertEq(Pointer.unwrap(alloc1), Pointer.unwrap(alloc0) + 0x60, "allocated");
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
        MemoryKV kv = MemoryKV.wrap(0).set(key, value);
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
        MemoryKV kv = MemoryKV.wrap(0).set(key, val(0));
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

    /// Updating a key in one internal list leaves the other 14 lists alone: same
    /// head pointers, same values.
    function testUpdateIsIsolatedBetweenLists() external pure {
        MemoryKVKey[] memory keys = new MemoryKVKey[](15);
        MemoryKV kv = MemoryKV.wrap(0);
        for (uint256 slot = 0; slot < 15; slot++) {
            keys[slot] = keyForSlot(bytes32(0x1000 + slot), slot);
            kv = kv.set(keys[slot], val(slot + 1));
        }
        assertEq(lengthOf(kv), 30, "length before");
        uint256 before = MemoryKV.unwrap(kv);

        // Update each list in turn, including list 14 whose pointer sits
        // directly under the word count in the top 16 bits.
        for (uint256 target = 0; target < 15; target++) {
            kv = kv.set(keys[target], val(0xABC00 + target));
            assertEq(MemoryKV.unwrap(kv), before, "kv word");
            assertEq(lengthOf(kv), 30, "length after");
            for (uint256 slot = 0; slot < 15; slot++) {
                assertValue(kv, keys[slot], slot <= target ? 0xABC00 + slot : slot + 1, "value");
            }
            assertEq(kv.toBytes32Array().length, 30, "array length");
        }
    }

    /// The word count the store carries must stay equal to twice the number of
    /// distinct keys, however many times those keys are rewritten. A count that
    /// drifted up on updates would make the export allocate and report slots the
    /// linked lists never fill.
    function testWordCountCountsDistinctKeysOnly(MemoryKVKey[] memory keys, MemoryKVVal value) external pure {
        vm.assume(keys.length <= 20);
        MemoryKV kv = MemoryKV.wrap(0);
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
}
