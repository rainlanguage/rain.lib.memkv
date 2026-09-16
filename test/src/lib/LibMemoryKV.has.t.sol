// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal, MEMORY_KV_EMPTY} from "../../../src/lib/LibMemoryKV.sol";

/// @title LibMemoryKVHasTest
/// `has` answers the existence half of `get`, so every case here states what
/// `get` reports and what `has` must therefore say, rather than repeating how
/// the walk finds it.
contract LibMemoryKVHasTest is Test {
    using LibMemoryKV for MemoryKV;

    /// An empty store has nothing, whatever it is asked.
    function testHasEmpty(MemoryKVKey key) external pure {
        assertFalse(MEMORY_KV_EMPTY.has(key));
    }

    /// A key that was set is there, and a key that was not is not.
    function testHasWhatWasSet(MemoryKVKey key, MemoryKVKey other, MemoryKVVal value) external pure {
        vm.assume(MemoryKVKey.unwrap(key) != MemoryKVKey.unwrap(other));
        MemoryKV kv = MEMORY_KV_EMPTY.set(key, value);
        assertTrue(kv.has(key));
        assertFalse(kv.has(other));
    }

    /// A key SET TO ZERO exists. This is the case a caller gets wrong by
    /// reading the value instead of the existence flag, and the reason the two
    /// are reported separately.
    function testHasAKeyWhoseValueIsZero(MemoryKVKey key) external pure {
        MemoryKV kv = MEMORY_KV_EMPTY.set(key, MemoryKVVal.wrap(0));
        assertTrue(kv.has(key));
        (uint256 exists, MemoryKVVal value) = kv.get(key);
        assertEq(exists, 1);
        assertEq(MemoryKVVal.unwrap(value), 0);
    }

    /// `has` agrees with `get` on every key, set or unset.
    function testHasAgreesWithGet(MemoryKVKey[] memory keys, MemoryKVKey needle, MemoryKVVal value) external pure {
        MemoryKV kv = MEMORY_KV_EMPTY;
        for (uint256 i = 0; i < keys.length; i++) {
            kv = kv.set(keys[i], value);
        }
        (uint256 exists,) = kv.get(needle);
        assertEq(kv.has(needle), exists != 0);
        for (uint256 i = 0; i < keys.length; i++) {
            assertTrue(kv.has(keys[i]));
        }
    }

    /// Overwriting a key leaves it there, whatever it is overwritten with.
    function testHasSurvivesAnUpsert(MemoryKVKey key, MemoryKVVal first, MemoryKVVal second) external pure {
        MemoryKV kv = MEMORY_KV_EMPTY.set(key, first);
        assertTrue(kv.has(key));
        kv = kv.set(key, second);
        assertTrue(kv.has(key));
    }

    /// Several keys coexist: adding one does not remove another.
    function testHasEveryKeyOfMany() external pure {
        MemoryKV kv = MEMORY_KV_EMPTY;
        for (uint256 i = 1; i <= 8; i++) {
            kv = kv.set(MemoryKVKey.wrap(bytes32(i)), MemoryKVVal.wrap(bytes32(i)));
        }
        for (uint256 i = 1; i <= 8; i++) {
            assertTrue(kv.has(MemoryKVKey.wrap(bytes32(i))));
        }
        assertFalse(kv.has(MemoryKVKey.wrap(bytes32(uint256(9)))));
    }
}
