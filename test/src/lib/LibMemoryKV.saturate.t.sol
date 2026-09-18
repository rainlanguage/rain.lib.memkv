// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {keyForSlot} from "test/lib/LibMemoryKVKeys.sol";
import {lengthOf, maskOf, occupiedSlots} from "test/lib/LibMemoryKVHandle.sol";
import {countPair} from "test/lib/LibMemoryKVExport.sol";

/// @title LibMemoryKVSaturateTest
/// All `LibMemoryKV.LIST_COUNT` internal lists are non-empty at the same time,
/// and the word count, every `get` and the export all still match what was
/// set.
contract LibMemoryKVSaturateTest is Test {
    using LibMemoryKV for MemoryKV;

    /// Two pairs per internal list, so every list has a node behind its head.
    uint256 internal constant PAIR_COUNT = 2 * LibMemoryKV.LIST_COUNT;

    /// `PAIR_COUNT` pairs are set, spread evenly over the lists. After that,
    /// every list holds a head pointer and its occupancy bit, the word count is
    /// two per pair, every key reads back its value, and the export holds two
    /// words per pair with each pair exactly once.
    function testSaturate(bytes32 seed) public pure {
        MemoryKV kv = MEMORY_KV_EMPTY;

        // Interleaved key/value words; each key is rehashed in place below.
        bytes32[] memory kvs = new bytes32[](PAIR_COUNT * 2);
        for (uint256 i = 0; i < kvs.length; i++) {
            kvs[i] = keccak256(abi.encode(seed, i));
        }

        // Rehash each key until it lands in its list, so the pairs spread
        // evenly across every list.
        for (uint256 i = 0; i < kvs.length; i += 2) {
            MemoryKVKey key = keyForSlot(kvs[i], (i / 2) % LibMemoryKV.LIST_COUNT);
            kvs[i] = MemoryKVKey.unwrap(key);

            kv = kv.set(key, MemoryKVVal.wrap(kvs[i + 1]));
        }

        assertEq(occupiedSlots(kv), LibMemoryKV.LIST_COUNT, "every list holds a head pointer");
        assertEq(maskOf(kv), LibMemoryKV.OCCUPANCY_MASK, "every list marked occupied");
        assertEq(lengthOf(kv), kvs.length, "word count");

        for (uint256 i = 0; i < kvs.length; i += 2) {
            (uint256 exists, MemoryKVVal value) = kv.get(MemoryKVKey.wrap(kvs[i]));
            assertEq(exists, 1, "exists");
            assertEq(MemoryKVVal.unwrap(value), kvs[i + 1], "value");
        }

        bytes32[] memory export = kv.toBytes32Array();

        assertEq(export.length, kvs.length, "export length");
        // Counted over every pair at once, a pair exported twice pays for a
        // pair not exported at all, so each pair is counted on its own.
        for (uint256 i = 0; i < kvs.length; i += 2) {
            assertEq(countPair(export, kvs[i], kvs[i + 1]), 1, "each pair exported exactly once");
        }
    }
}
