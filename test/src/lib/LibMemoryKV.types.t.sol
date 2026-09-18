// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";

import {LibPointer, Pointer} from "rain-solmem-0.1.28/src/lib/LibPointer.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {collidingPairDifferingInBit, keyForSlot} from "test/lib/LibMemoryKVKeys.sol";
import {countPair} from "test/lib/LibMemoryKVExport.sol";
import {headOf, lengthOf} from "test/lib/LibMemoryKVHandle.sol";

/// @title LibMemoryKVTypesTest
/// The store's declarations: the one word an empty store is, the layout that
/// packs the head pointers and the word count into a word, and the full width
/// of the key and value a store carries.
contract LibMemoryKVTypesTest is Test {
    using LibMemoryKV for MemoryKV;

    /// The bit a key keeps that no random fuzz pair differs in alone.
    uint256 internal constant TOP_BIT = 0xff;

    /// `low` and `high` are two keys, each answering with its own value and
    /// each counted.
    function assertTwoKeys(MemoryKVKey low, MemoryKVKey high) internal pure {
        MemoryKV kv = MEMORY_KV_EMPTY.set(low, MemoryKVVal.wrap(bytes32(uint256(0xA))));
        kv = kv.set(high, MemoryKVVal.wrap(bytes32(uint256(0xB))));

        assertEq(lengthOf(kv), 4, "two pairs counted");

        (uint256 lowExists, MemoryKVVal lowValue) = kv.get(low);
        assertEq(lowExists, 1, "low key exists");
        assertEq(uint256(MemoryKVVal.unwrap(lowValue)), 0xA, "low key value");

        (uint256 highExists, MemoryKVVal highValue) = kv.get(high);
        assertEq(highExists, 1, "high key exists");
        assertEq(uint256(MemoryKVVal.unwrap(highValue)), 0xB, "high key value");

        bytes32[] memory array = kv.toBytes32Array();
        assertEq(array.length, 4, "array length");
        assertEq(countPair(array, MemoryKVKey.unwrap(low), bytes32(uint256(0xA))), 1, "low key pair exported once");
        assertEq(countPair(array, MemoryKVKey.unwrap(high), bytes32(uint256(0xB))), 1, "high key pair exported once");
    }

    /// The empty store is the zero word.
    function testEmptyStoreIsTheZeroWord() external pure {
        assertEq(MemoryKV.unwrap(MEMORY_KV_EMPTY), 0);
    }

    /// With every internal list holding one pair, the count and the head
    /// pointers tile the word as the layout states: the slot at
    /// `COUNT_BIT_OFFSET` counts two words per pair, and the slot at
    /// `slot * SLOT_BITS` points at the node holding the key that belongs to
    /// list `slot`, with that key's value after it.
    function testCountAndHeadPointersTileTheWord() external pure {
        MemoryKV kv = MEMORY_KV_EMPTY;
        MemoryKVKey[] memory keys = new MemoryKVKey[](LibMemoryKV.LIST_COUNT);
        for (uint256 slot = 0; slot < LibMemoryKV.LIST_COUNT; slot++) {
            keys[slot] = keyForSlot(bytes32(slot), slot);
            kv = kv.set(keys[slot], MemoryKVVal.wrap(bytes32(slot + 1)));
        }

        assertEq(lengthOf(kv), LibMemoryKV.LIST_COUNT * 2, "the count is two words per pair");

        for (uint256 slot = 0; slot < LibMemoryKV.LIST_COUNT; slot++) {
            string memory name = string.concat("slot ", vm.toString(slot));
            Pointer head = Pointer.wrap(headOf(kv, slot));
            assertTrue(Pointer.unwrap(head) != 0, string.concat(name, " occupied"));
            assertEq(LibPointer.unsafeReadWord(head), MemoryKVKey.unwrap(keys[slot]), string.concat(name, " key"));
            assertEq(
                LibPointer.unsafeReadWord(LibPointer.unsafeAddWord(head)),
                bytes32(slot + 1),
                string.concat(name, " value")
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
        assertEq(countPair(array, bytes32(0), bytes32(type(uint256).max)), 1, "zero key pair exported once");
        assertEq(countPair(array, bytes32(type(uint256).max), bytes32(0)), 1, "max key pair exported once");
    }
}
