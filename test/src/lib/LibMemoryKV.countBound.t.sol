// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal} from "src/lib/LibMemoryKV.sol";

/// @title LibMemoryKVCountBoundTest
/// The word count `toBytes32Array` sizes its allocation from is a 16 bit field
/// that `set` advances by 2 per insert and truncates, with no bound of its own.
/// What keeps it from wrapping is the item pointer bound: an item is 0x60 bytes
/// and `set` reverts once one would begin past `0xFFFF`. These tests hold the
/// two bounds against each other, because the `MemoryKV` precondition is only
/// worth stating if a store built the documented way cannot break it.
///
/// The numbers are derived from those two constants rather than read back out
/// of a `kv`. Solidity hands every call a free memory pointer of `0x80` and
/// `set` allocates items from it unbroken, so item 681 begins at
/// `0x80 + 681 * 0x60 == 0xFFE0` and is accepted, item 682 begins at `0x10040`
/// and is not. A count wrap needs 65536 words, which is 32768 inserts.
contract LibMemoryKVCountBoundTest is Test {
    /// The largest number of inserts that fit under the item pointer bound, and
    /// the count that many inserts leave behind.
    uint256 constant MAX_INSERTS = 682;
    uint256 constant MAX_COUNT = MAX_INSERTS * 2;

    /// The pointer of the first item that does not fit.
    uint256 constant OVERFLOW_POINTER = 0x80 + MAX_INSERTS * 0x60;

    /// Inserts needed to advance the 16 bit count field through a full wrap.
    uint256 constant INSERTS_TO_WRAP_COUNT = 0x10000 / 2;

    /// Insert `inserts` distinct keys into a fresh store, inside one call frame
    /// so every item stays live for the whole fill, and hand back the raw `kv`.
    /// Keys are hashed out of scratch memory so that filling the store
    /// allocates nothing but the items themselves.
    function insertDistinctExternal(uint256 inserts) external pure returns (uint256) {
        MemoryKV kv = MemoryKV.wrap(0);
        for (uint256 i = 0; i < inserts; ++i) {
            bytes32 key;
            assembly ("memory-safe") {
                mstore(0, i)
                key := keccak256(0, 0x20)
            }
            kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(key), MemoryKVVal.wrap(key));
        }
        return MemoryKV.unwrap(kv);
    }

    /// The free memory pointer a call starts from, read through the same
    /// calldata shape as `insertDistinctExternal` so the item addresses this
    /// test computes are the ones `set` will actually see.
    function entryFreePointerExternal(uint256) external pure returns (uint256) {
        uint256 pointer;
        assembly ("memory-safe") {
            pointer := mload(0x40)
        }
        return pointer;
    }

    /// Every item address here is `0x80 + n * 0x60`, which only holds if a call
    /// really does start allocating at `0x80`. Pinned on its own so that a
    /// change in that assumption is attributable rather than showing up as an
    /// unexplained off by one in the tests below.
    function testEntryFreeMemoryPointer() external view {
        assertEq(this.entryFreePointerExternal(0), 0x80, "entry free memory pointer");
    }

    /// A store filled to the item pointer bound carries 1364 words. That is the
    /// most any `kv` reached through `set` can report, and it is where the
    /// `MemoryKV` count field's headroom is actually spent.
    function testSaturatedStoreCount() external view {
        uint256 kv = this.insertDistinctExternal(MAX_INSERTS);
        assertEq(kv >> 0xf0, MAX_COUNT, "saturated word count");
    }

    /// One insert past saturation reverts with the exact pointer that did not
    /// fit, so the bound cannot move without this test naming the new address.
    function testOneInsertPastSaturationReverts() external {
        vm.expectRevert(abi.encodeWithSelector(LibMemoryKV.MemoryKVOverflow.selector, OVERFLOW_POINTER));
        this.insertDistinctExternal(MAX_INSERTS + 1);
    }

    /// The 16 bit count cannot wrap for a store that started at
    /// `MemoryKV.wrap(0)`. Wrapping it needs 32768 inserts and the pointer
    /// bound stops the fill at the same item it always does, 48 times earlier.
    function testCountCannotWrapThroughSet() external {
        vm.expectRevert(abi.encodeWithSelector(LibMemoryKV.MemoryKVOverflow.selector, OVERFLOW_POINTER));
        this.insertDistinctExternal(INSERTS_TO_WRAP_COUNT);
    }
}
