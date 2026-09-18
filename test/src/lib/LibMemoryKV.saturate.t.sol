// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {keyForSlot, countPair} from "test/lib/LibMemoryKVTestHelpers.sol";

contract LibMemoryKVSaturateTest is Test {
    using LibMemoryKV for MemoryKV;

    uint256 internal constant LIST_COUNT = 15;
    uint256 internal constant LIST_POINTER_BITS = 0x10;
    uint256 internal constant LENGTH_BIT_OFFSET = LIST_COUNT * LIST_POINTER_BITS;
    /// Two keys per internal list.
    uint256 internal constant PAIR_COUNT = 2 * LIST_COUNT;

    function testSaturate(bytes32 seed) public pure {
        MemoryKV kv = MEMORY_KV_EMPTY;

        // Interleaved key/value words; the key slots are rehashed in place below.
        bytes32[] memory kvs = new bytes32[](PAIR_COUNT * 2);
        for (uint256 i = 0; i < kvs.length; i++) {
            kvs[i] = keccak256(abi.encode(seed, i));
        }

        // Rehash each key until we get an even spread across all internal list
        // slots.
        for (uint256 i = 0; i < kvs.length; i += 2) {
            MemoryKVKey key = keyForSlot(kvs[i], (i / 2) % LIST_COUNT);
            kvs[i] = MemoryKVKey.unwrap(key);

            kv = kv.set(key, MemoryKVVal.wrap(kvs[i + 1]));
        }

        // Every kv slot should be nonzero at this point.
        for (uint256 i = 0; i < LENGTH_BIT_OFFSET; i += LIST_POINTER_BITS) {
            assertTrue(((MemoryKV.unwrap(kv) >> i) & 0xFFFF) > 0);
        }

        // Top slot must be the length.
        assertEq(60, MemoryKV.unwrap(kv) >> LENGTH_BIT_OFFSET);

        // Every value must be gettable.
        for (uint256 i = 0; i < kvs.length; i += 2) {
            (uint256 exists, MemoryKVVal value) = kv.get(MemoryKVKey.wrap(kvs[i]));
            assertEq(1, exists);
            assertEq(MemoryKVVal.unwrap(value), kvs[i + 1]);
        }

        // Exported array must include every key/value pair.
        bytes32[] memory export = LibMemoryKV.toBytes32Array(kv);

        assertEq(kvs.length, export.length);
        // Counted over every pair at once, a pair exported twice pays for a
        // pair not exported at all, so each pair is counted on its own.
        for (uint256 i = 0; i < kvs.length; i += 2) {
            assertEq(countPair(export, kvs[i], kvs[i + 1]), 1, "each pair exported exactly once");
        }
    }
}
