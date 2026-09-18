// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";

import {LibPointer, Pointer} from "rain-solmem-0.1.28/src/lib/LibPointer.sol";
import {LibBytes32Array} from "rain-solmem-0.1.28/src/lib/LibBytes32Array.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {setFreePointer} from "test/lib/LibFreeMemory.sol";
import {keyForSlot, keysInSlot, slotOf, val} from "test/lib/LibMemoryKVKeys.sol";
import {assertValue} from "test/lib/LibMemoryKVAssert.sol";
import {
    COUNT_MAX,
    craftNode,
    handleWith,
    headOf,
    lengthOf,
    maskOf,
    metaOf,
    occupancyBitOf
} from "test/lib/LibMemoryKVHandle.sol";

/// @title LibMemoryKVSetCapacityTest
/// `set` has no ceiling. The handle is the address of the header, and heads
/// and next pointers are whole words, so neither where the store lives in
/// memory nor how many pairs it holds is bounded by anything but the gas that
/// memory costs. Each store built by `set` reads every key back and exports
/// whole.
///
/// The word count is every bit of the meta word from
/// `LibMemoryKV.COUNT_BIT_OFFSET` up. The cases that take a count wider than
/// sixteen bits, up to the widest the field holds, craft the header with it,
/// because no test can insert that many pairs: an insert adds exactly one pair
/// to it, an update leaves it alone, and the export sizes its array from all
/// of it.
contract LibMemoryKVSetCapacityTest is Test {
    using LibMemoryKV for MemoryKV;

    /// The first address, or word count, that does not fit in sixteen bits.
    uint256 internal constant ABOVE_SIXTEEN_BITS = 0x10000;

    /// Pairs the acceptance test sets.
    uint256 internal constant ACCEPTANCE_PAIRS = 2000;

    /// Nodes the straddling store chains into one list.
    uint256 internal constant CHAIN = 40;

    /// The bytes the straddling store occupies: its header and its chain.
    uint256 internal constant CHAIN_STORE_BYTES = LibMemoryKV.HEADER_BYTES + CHAIN * LibMemoryKV.NODE_BYTES;

    function freePointer() internal pure returns (uint256) {
        return Pointer.unwrap(LibPointer.allocatedMemoryPointer());
    }

    /// The value the acceptance test sets for pair `i`, distinct from every
    /// key it sets: `keccak256(i, 1)`, hashed in scratch space so that the
    /// free memory pointer does not move between the inserts.
    function valueFor(uint256 i) internal pure returns (bytes32 value) {
        assembly ("memory-safe") {
            mstore(0, i)
            mstore(0x20, 1)
            value := keccak256(0, 0x40)
        }
    }

    /// The free memory pointer is above sixteen bits before the first insert,
    /// so the header and every node are too, and the store then takes
    /// `ACCEPTANCE_PAIRS` distinct keys. Every key reads back with its value,
    /// the count is every pair, the export holds every pair once, and the
    /// allocation is exactly one header and one node per pair.
    function testTwoThousandPairsFromAboveSixteenBits() external pure {
        setFreePointer(ABOVE_SIXTEEN_BITS);
        MemoryKV kv = MEMORY_KV_EMPTY;
        for (uint256 i = 1; i <= ACCEPTANCE_PAIRS; i++) {
            kv = kv.set(MemoryKVKey.wrap(bytes32(i)), MemoryKVVal.wrap(valueFor(i)));
        }
        uint256 end = freePointer();

        assertEq(MemoryKV.unwrap(kv), ABOVE_SIXTEEN_BITS, "the header is where the free memory pointer was");
        assertEq(
            end,
            ABOVE_SIXTEEN_BITS + LibMemoryKV.HEADER_BYTES + ACCEPTANCE_PAIRS * LibMemoryKV.NODE_BYTES,
            "one header and one node per pair"
        );
        assertEq(lengthOf(kv), ACCEPTANCE_PAIRS * 2, "two words per pair");

        for (uint256 i = 1; i <= ACCEPTANCE_PAIRS; i++) {
            (uint256 exists, MemoryKVVal value) = kv.get(MemoryKVKey.wrap(bytes32(i)));
            assertEq(exists, 1, "every key exists");
            assertEq(MemoryKVVal.unwrap(value), valueFor(i), "every key reads back its value");
        }

        // Every exported pair is a key the store was given, with its value,
        // and none is exported twice. With the length that is every pair once.
        bytes32[] memory array = kv.toBytes32Array();
        assertEq(array.length, ACCEPTANCE_PAIRS * 2, "every pair exported");
        bool[] memory seen = new bool[](ACCEPTANCE_PAIRS + 1);
        for (uint256 cursor = 0; cursor < array.length; cursor += 2) {
            uint256 key = uint256(array[cursor]);
            assertTrue(key >= 1 && key <= ACCEPTANCE_PAIRS, "an exported key the store was given");
            assertFalse(seen[key], "no key exported twice");
            seen[key] = true;
            assertEq(array[cursor + 1], valueFor(key), "each exported key beside its own value");
        }
    }

    /// A store whose header and nodes straddle `0x10000`, at every alignment
    /// the fuzzer picks. It starts below sixteen bits and ends above them, so
    /// some of its words (a head, the meta word, a key, a value or a next
    /// pointer, depending on where it starts) sit on each side, and the walk
    /// down its one list follows next pointers across. Every key reads back
    /// and the export holds every pair once.
    function testAStoreStraddlingSixteenBitsReadsBackWhole(uint256 start, bytes32 seed) external pure {
        MemoryKVKey[] memory keys = keysInSlot(seed, uint256(seed) % LibMemoryKV.LIST_COUNT, CHAIN);
        start = bound(start, ABOVE_SIXTEEN_BITS - CHAIN_STORE_BYTES + 1, ABOVE_SIXTEEN_BITS - 1);
        assertGt(start, freePointer(), "the store starts above everything this test allocated");

        setFreePointer(start);
        MemoryKV kv = MEMORY_KV_EMPTY;
        for (uint256 i = 0; i < CHAIN; i++) {
            kv = kv.set(keys[i], MemoryKVVal.wrap(bytes32(i + 1)));
        }

        assertEq(MemoryKV.unwrap(kv), start, "the header is where the free memory pointer was");
        assertGt(start + CHAIN_STORE_BYTES, ABOVE_SIXTEEN_BITS, "the store ends above sixteen bits");
        assertEq(
            headOf(kv, keys[0]),
            start + LibMemoryKV.HEADER_BYTES + (CHAIN - 1) * LibMemoryKV.NODE_BYTES,
            "the newest node heads the one list"
        );
        assertEq(lengthOf(kv), CHAIN * 2, "two words per pair");

        for (uint256 i = 0; i < CHAIN; i++) {
            (uint256 exists, MemoryKVVal value) = kv.get(keys[i]);
            assertEq(exists, 1, "every key exists");
            assertEq(uint256(MemoryKVVal.unwrap(value)), i + 1, "every key reads back its value");
        }

        bytes32[] memory array = kv.toBytes32Array();
        assertEq(array.length, CHAIN * 2, "every pair exported");
        bool[] memory seen = new bool[](CHAIN);
        for (uint256 cursor = 0; cursor < array.length; cursor += 2) {
            uint256 value = uint256(array[cursor + 1]);
            assertTrue(value >= 1 && value <= CHAIN, "an exported value the store was given");
            uint256 index = value - 1;
            assertFalse(seen[index], "no pair exported twice");
            seen[index] = true;
            assertEq(array[cursor], MemoryKVKey.unwrap(keys[index]), "each exported value beside its own key");
        }
    }

    /// An insert into a store whose word count is wider than sixteen bits, up
    /// to the widest count one more pair still fits under `COUNT_MAX`, adds
    /// exactly the pair's two words to the whole count. The crafted list's
    /// occupancy bit stays set beside the new list's, bit 15 stays zero, and
    /// both keys read back.
    function testInsertAddsOnePairToAWordCountWiderThanSixteenBits(uint256 pairs, bytes32 seed) external pure {
        uint256 words = bound(pairs, ABOVE_SIXTEEN_BITS / 2, (COUNT_MAX - 3) / 2) * 2;
        uint256 craftedSlot = 0;
        uint256 insertedSlot = LibMemoryKV.LIST_COUNT - 1;
        MemoryKVKey crafted = keyForSlot(seed, craftedSlot);
        MemoryKVKey inserted = keyForSlot(seed, insertedSlot);
        MemoryKV kv = handleWith(craftedSlot, craftNode(crafted, val(1), 0), words);
        uint256 node = freePointer();

        MemoryKV afterInsert = kv.set(inserted, val(2));

        uint256 mask = occupancyBitOf(craftedSlot) | occupancyBitOf(insertedSlot);
        assertEq(MemoryKV.unwrap(afterInsert), MemoryKV.unwrap(kv), "the header stays where it is");
        assertEq(lengthOf(kv), words + 2, "the count grows by one pair's two words");
        assertEq(maskOf(kv), mask, "the crafted list's bit stays set beside the new list's");
        assertEq(
            metaOf(kv), ((words + 2) << LibMemoryKV.COUNT_BIT_OFFSET) | mask, "the meta word is the count and mask"
        );
        assertEq(headOf(kv, inserted), node, "the new node heads its list");
        assertValue(kv, crafted, 1, "crafted");
        assertValue(kv, inserted, 2, "inserted");
    }

    /// An update in a store whose word count is wider than sixteen bits, up to
    /// the widest even count the field holds, writes the value and leaves the
    /// meta word, the handle and the free memory pointer as they were.
    function testUpdateLeavesAWordCountWiderThanSixteenBitsAlone(uint256 pairs, bytes32 seed) external pure {
        uint256 words = bound(pairs, ABOVE_SIXTEEN_BITS / 2, COUNT_MAX / 2) * 2;
        MemoryKVKey key = MemoryKVKey.wrap(seed);
        MemoryKV kv = handleWith(slotOf(seed), craftNode(key, val(1), 0), words);
        uint256 meta = metaOf(kv);
        uint256 free = freePointer();

        MemoryKV afterUpdate = kv.set(key, val(2));
        uint256 freeAfter = freePointer();

        assertEq(MemoryKV.unwrap(afterUpdate), MemoryKV.unwrap(kv), "the handle is unchanged");
        assertEq(freeAfter, free, "nothing is allocated");
        assertEq(metaOf(kv), meta, "the meta word is unchanged");
        assertEq(lengthOf(kv), words, "the count is unchanged");
        assertValue(kv, key, 2, "updated");
    }

    /// The export sizes its array from the word count alone. The crafted store
    /// holds one node but carries a word count wider than sixteen bits, up to
    /// the widest even count the field holds: the array's length is that whole
    /// count, its allocation is the length word and that many words, and the
    /// node's pair is its first. The walk writes only that pair, so no memory
    /// past it is touched, and the free memory pointer is put back before the
    /// asserts allocate.
    function testExportSizesItsArrayFromAWordCountWiderThanSixteenBits(uint256 pairs, bytes32 seed) external pure {
        uint256 words = bound(pairs, ABOVE_SIXTEEN_BITS / 2, COUNT_MAX / 2) * 2;
        MemoryKVKey key = MemoryKVKey.wrap(seed);
        MemoryKV kv = handleWith(slotOf(seed), craftNode(key, val(1), 0), words);
        uint256 start = freePointer();

        bytes32[] memory array = kv.toBytes32Array();
        uint256 end = freePointer();
        uint256 arrayAt = Pointer.unwrap(LibBytes32Array.startPointer(array));
        uint256 length = array.length;
        bytes32 firstKey = array[0];
        bytes32 firstValue = array[1];
        setFreePointer(start);

        assertEq(arrayAt, start, "the array is at the free memory pointer");
        assertEq(length, words, "the length is the whole count");
        assertEq(end - start, 0x20 + words * 0x20, "the length word and every counted word are allocated");
        assertEq(firstKey, seed, "the node's key");
        assertEq(uint256(firstValue), 1, "the node's value");
    }
}
