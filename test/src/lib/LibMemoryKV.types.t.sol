// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {collidingPairDifferingInBit, countPair} from "test/lib/LibMemoryKVTestHelpers.sol";

/// @title LibMemoryKVTypesTest
/// The declarations the rest of the suite is written on top of: the one word an
/// empty store is, and the full width of the key and value it carries. Every
/// other test reads these three calls downstream, where a wrong empty store
/// arrives as a wrong export or a wrong walk. Here they are the word itself.
contract LibMemoryKVTypesTest is Test {
    using LibMemoryKV for MemoryKV;

    /// One head pointer per internal linked list.
    uint256 internal constant SLOTS = 15;

    /// The bit a key keeps that no random fuzz pair differs in alone.
    uint256 internal constant TOP_BIT = 0xff;

    /// `low` and `high` are two keys, each answering with its own value and
    /// each counted.
    function assertTwoKeys(MemoryKVKey low, MemoryKVKey high) internal pure {
        MemoryKV kv = MEMORY_KV_EMPTY.set(low, MemoryKVVal.wrap(bytes32(uint256(0xA))));
        kv = kv.set(high, MemoryKVVal.wrap(bytes32(uint256(0xB))));

        assertEq(MemoryKV.unwrap(kv) >> 0xf0, 4, "two pairs counted");

        (uint256 lowExists, MemoryKVVal lowValue) = kv.get(low);
        assertEq(lowExists, 1, "low key exists");
        assertEq(uint256(MemoryKVVal.unwrap(lowValue)), 0xA, "low key value");

        (uint256 highExists, MemoryKVVal highValue) = kv.get(high);
        assertEq(highExists, 1, "high key exists");
        assertEq(uint256(MemoryKVVal.unwrap(highValue)), 0xB, "high key value");

        bytes32[] memory array = kv.toBytes32Array();
        assertEq(array.length, 4, "array length");
        assertTrue(countPair(array, MemoryKVKey.unwrap(low), bytes32(uint256(0xA))) != 0, "low key pair exported");
        assertTrue(countPair(array, MemoryKVKey.unwrap(high), bytes32(uint256(0xB))) != 0, "high key pair exported");
    }

    /// The empty store is the zero word.
    function testEmptyStoreIsTheZeroWord() external pure {
        assertEq(MemoryKV.unwrap(MEMORY_KV_EMPTY), 0);
    }

    /// The word count is the top 16 bits of the store, and an empty store has
    /// counted nothing.
    function testEmptyStoreHasNoWordCount() external pure {
        assertEq(MemoryKV.unwrap(MEMORY_KV_EMPTY) >> 0xf0, 0);
    }

    /// The 15 head pointers are the 240 bits below the count, 16 bits each, and
    /// every one of them is empty. Slot 14 is the one that abuts the count, so
    /// a count wider than 16 bits would read here as a pointer that is not
    /// there.
    function testEmptyStoreHasNoHeadPointerInAnySlot() external pure {
        for (uint256 slot = 0; slot < SLOTS; slot++) {
            assertEq(
                (MemoryKV.unwrap(MEMORY_KV_EMPTY) >> (slot * 0x10)) & 0xFFFF,
                0,
                string.concat("slot ", vm.toString(slot))
            );
        }
    }

    /// Two keys differing in the top bit alone, sharing one internal list. A
    /// compare narrower than a word merges them: one pair counted instead of
    /// two, and one value answering for both. No fuzzed pair of keys differs in
    /// that bit alone, so the pair is searched for rather than drawn.
    function testTopBitCollidersAreTwoKeys() external pure {
        (MemoryKVKey low, MemoryKVKey high) = collidingPairDifferingInBit(0, TOP_BIT);
        assertTwoKeys(low, high);
    }

    /// The same, over whichever colliding pair the seed reaches.
    function testTopBitCollidersAreTwoKeysFuzz(uint256 seed) external pure {
        (MemoryKVKey low, MemoryKVKey high) = collidingPairDifferingInBit(seed, TOP_BIT);
        assertTwoKeys(low, high);
    }

    /// Both edges of a word are ordinary keys and ordinary values: a key of
    /// zero and a key of every bit set are two keys, and the value each carries
    /// leaves the export as the word that went in.
    function testKeyAndValueEdgesSurviveTheExport() external pure {
        MemoryKVKey zeroKey = MemoryKVKey.wrap(bytes32(0));
        MemoryKVKey maxKey = MemoryKVKey.wrap(bytes32(type(uint256).max));

        MemoryKV kv = MEMORY_KV_EMPTY.set(zeroKey, MemoryKVVal.wrap(bytes32(type(uint256).max)));
        kv = kv.set(maxKey, MemoryKVVal.wrap(bytes32(0)));

        (uint256 zeroExists, MemoryKVVal zeroValue) = kv.get(zeroKey);
        assertEq(zeroExists, 1, "zero key exists");
        assertEq(MemoryKVVal.unwrap(zeroValue), bytes32(type(uint256).max), "zero key value");

        (uint256 maxExists, MemoryKVVal maxValue) = kv.get(maxKey);
        assertEq(maxExists, 1, "max key exists");
        assertEq(MemoryKVVal.unwrap(maxValue), bytes32(0), "max key value");

        bytes32[] memory array = kv.toBytes32Array();
        assertEq(array.length, 4, "array length");
        assertTrue(countPair(array, bytes32(0), bytes32(type(uint256).max)) != 0, "zero key pair exported");
        assertTrue(countPair(array, bytes32(type(uint256).max), bytes32(0)) != 0, "max key pair exported");
    }
}
