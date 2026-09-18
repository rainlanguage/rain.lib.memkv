// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {LibMemoryKV, MemoryKV} from "src/lib/LibMemoryKV.sol";
import {withCount, lengthOf, headOf} from "test/lib/LibMemoryKVHandle.sol";

/// @title LibMemoryKVHandleTest
/// The promises `withCount` makes and other tests rest on.
contract LibMemoryKVHandleTest is Test {
    /// `withCount` rewrites the count and nothing under it: from any word,
    /// every head pointer comes through unchanged, the count reads back as the
    /// one forced, and every bit below the count's slot is the bit it was.
    function testWithCountKeepsEveryBitUnderTheCount(uint256 word, uint256 forced) external pure {
        forced = bound(forced, 0, LibMemoryKV.POINTER_MASK);
        MemoryKV kv = MemoryKV.wrap(word);
        MemoryKV changed = withCount(kv, forced);

        assertEq(lengthOf(changed), forced, "count forced");
        for (uint256 slot = 0; slot < LibMemoryKV.LIST_COUNT; slot++) {
            assertEq(headOf(changed, slot), headOf(kv, slot), string.concat("head of slot ", vm.toString(slot)));
        }
        uint256 underTheCount = (uint256(1) << LibMemoryKV.COUNT_BIT_OFFSET) - 1;
        assertEq(MemoryKV.unwrap(changed) & underTheCount, word & underTheCount, "every bit under the count kept");
    }
}
