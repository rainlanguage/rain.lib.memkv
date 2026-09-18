// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibPointer, Pointer} from "rain-solmem-0.1.28/src/lib/LibPointer.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {setFreePointer} from "test/lib/LibFreeMemory.sol";
import {keysInSlot} from "test/lib/LibMemoryKVKeys.sol";
import {headOf, lengthOf} from "test/lib/LibMemoryKVHandle.sol";

/// @title LibMemoryKVSetCapacityTest
/// `set` has no ceiling. The handle is the address of the header, and heads
/// and next pointers are whole words, so neither where the store lives in
/// memory nor how many pairs it holds is bounded by anything but the gas that
/// memory costs. Each case reads EVERY key back and exports the store, so an
/// address truncated anywhere on the way is a key that no longer reads back
/// rather than a store that merely looks full.
contract LibMemoryKVSetCapacityTest is Test {
    using LibMemoryKV for MemoryKV;

    /// The first address that does not fit in sixteen bits.
    uint256 internal constant ABOVE_SIXTEEN_BITS = 0x10000;

    /// Pairs the acceptance test sets, three times what a packed sixteen bit
    /// pointer could reach from the lowest free memory pointer.
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

    /// The #13 acceptance test. The free memory pointer is above sixteen bits
    /// before the first insert, so the header and every node are too, and the
    /// store then takes `ACCEPTANCE_PAIRS` distinct keys. Every key reads back
    /// with its value, the count is every pair, the export holds every pair
    /// once, and the allocation is exactly one header and one node per pair.
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
}
