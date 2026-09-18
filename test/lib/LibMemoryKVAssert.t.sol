// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {assertValue} from "test/lib/LibMemoryKVAssert.sol";

/// @title LibMemoryKVAssertTest
/// The promises `assertValue` makes and other tests rest on.
contract LibMemoryKVAssertTest is Test {
    using LibMemoryKV for MemoryKV;

    /// `assertValue` on a store built in this frame, which holds `stored` under
    /// `key` when `insert` is true and is empty otherwise, so a test can expect
    /// its failure without passing a handle across a call.
    function assertValueExternal(MemoryKVKey key, bool insert, uint256 stored, uint256 expected) external pure {
        MemoryKV kv = MEMORY_KV_EMPTY;
        if (insert) {
            kv = kv.set(key, MemoryKVVal.wrap(bytes32(stored)));
        }
        assertValue(kv, key, expected, "err");
    }

    /// A key the store holds with exactly the expected value passes.
    function testAssertValuePassesOnTheValueTheStoreHolds(MemoryKVKey key, uint256 value) external view {
        this.assertValueExternal(key, true, value, value);
    }

    /// A key the store does not hold fails on existence, even when the
    /// expected value is the zero a miss reads as.
    function testAssertValueFailsOnAKeyTheStoreDoesNotHold(MemoryKVKey key) external {
        vm.expectRevert(bytes("err exists: 0 != 1"));
        this.assertValueExternal(key, false, 0, 0);
    }

    /// A key the store holds with another value fails on the value.
    function testAssertValueFailsOnAnotherValue(MemoryKVKey key) external {
        vm.expectRevert(bytes("err value: 1 != 2"));
        this.assertValueExternal(key, true, 1, 2);
    }
}
