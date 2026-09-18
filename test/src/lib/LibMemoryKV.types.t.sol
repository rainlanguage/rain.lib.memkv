// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {LibPointer, Pointer} from "rain-solmem-0.1.28/src/lib/LibPointer.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {
    LIST_COUNT,
    SLOT_BITS,
    POINTER_MAX,
    NODE_BYTES,
    COUNT_BIT_OFFSET,
    COUNT_MAX,
    collidingPairDifferingInBit,
    countPair,
    headOf,
    keyForSlot,
    lengthOf
} from "test/lib/LibMemoryKVTestHelpers.sol";

/// @title LibMemoryKVTypesTest
/// The declarations the rest of the suite is written on top of: the one word an
/// empty store is, the layout that packs the head pointers and the word count
/// into a word, and the full width of the key and value a store carries. Every
/// other test reads these downstream, where a wrong one arrives as a wrong
/// export or a wrong walk. Here they are checked on the word itself.
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

    /// The test tree states the layout independently of the library, and the
    /// two agree. The layout tiles the word: the head pointer slots fill the
    /// bits below the count, the count is the one slot above them, and the
    /// widest pointer and the widest count are each exactly one slot wide.
    function testLayoutConstantsAgreeWithTheLibraryAndTileTheWord() external pure {
        assertEq(LibMemoryKV.LIST_COUNT, LIST_COUNT, "list count");
        assertEq(LibMemoryKV.SLOT_BITS, SLOT_BITS, "slot bits");
        assertEq(LibMemoryKV.POINTER_MASK, POINTER_MAX, "pointer mask");
        assertEq(LibMemoryKV.COUNT_BIT_OFFSET, COUNT_BIT_OFFSET, "count bit offset");
        assertEq(LibMemoryKV.NODE_BYTES, NODE_BYTES, "node bytes");

        assertEq(COUNT_BIT_OFFSET, LIST_COUNT * SLOT_BITS, "the count sits directly above the last list");
        assertEq(COUNT_BIT_OFFSET + SLOT_BITS, 256, "the count is the top slot of the word");
        assertEq(POINTER_MAX, 2 ** SLOT_BITS - 1, "a pointer is one slot wide");
        assertEq(COUNT_MAX, POINTER_MAX, "the count is one slot wide");
    }

    /// With every internal list holding one pair, the count and the head
    /// pointers tile the word as the layout states: the slot at
    /// `COUNT_BIT_OFFSET` counts two words per pair, and the slot at
    /// `slot * SLOT_BITS` points at the node holding the key that belongs to
    /// list `slot`, with that key's value after it.
    function testCountAndHeadPointersTileTheWord() external pure {
        MemoryKV kv = MEMORY_KV_EMPTY;
        MemoryKVKey[] memory keys = new MemoryKVKey[](LIST_COUNT);
        for (uint256 slot = 0; slot < LIST_COUNT; slot++) {
            keys[slot] = keyForSlot(bytes32(slot), slot);
            kv = kv.set(keys[slot], MemoryKVVal.wrap(bytes32(slot + 1)));
        }

        assertEq(lengthOf(kv), LIST_COUNT * 2, "the count is two words per pair");

        for (uint256 slot = 0; slot < LIST_COUNT; slot++) {
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
