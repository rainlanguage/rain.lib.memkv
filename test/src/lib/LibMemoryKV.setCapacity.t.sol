// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal} from "src/lib/LibMemoryKV.sol";

/// @title LibMemoryKVSetCapacityTest
/// `set` can revert, and the ceiling it reverts at is the frame's free memory
/// pointer rather than a pair count. These tests state that ceiling as the
/// exact pair that crosses it and the exact pointer the revert carries, and
/// state that an update is not subject to it at all, so a guard that moved
/// onto the update path or a node that changed size is a different number
/// here.
contract LibMemoryKVSetCapacityTest is Test {
    using LibMemoryKV for MemoryKV;

    /// Insert `pairs` distinct keys into an empty store in a frame that starts
    /// at the default free memory pointer and allocates nothing else, so the
    /// nodes are the only allocation and their addresses are exact. Returns the
    /// word count, so a fill that stopped early is a number rather than a
    /// silence.
    function fillEmptyFrameExternal(uint256 pairs) external pure returns (uint256) {
        assembly ("memory-safe") {
            mstore(0x40, 0x80)
        }
        MemoryKV kv = MemoryKV.wrap(0);
        for (uint256 i = 1; i <= pairs; i++) {
            kv = kv.set(MemoryKVKey.wrap(bytes32(i)), MemoryKVVal.wrap(bytes32(i)));
        }
        return MemoryKV.unwrap(kv) >> 0xf0;
    }

    /// Insert `key`, then move the free memory pointer far above the bound and
    /// update `key`, reading the value back in the same frame. The node stays
    /// where it was allocated; only the free memory pointer is above the bound.
    function updateAboveTheBoundExternal(MemoryKVKey key, MemoryKVVal first, MemoryKVVal second)
        external
        pure
        returns (uint256, bytes32)
    {
        MemoryKV kv = MemoryKV.wrap(0).set(key, first);
        assembly ("memory-safe") {
            mstore(0x40, 0x20000)
        }
        kv = kv.set(key, second);
        (uint256 exists, MemoryKVVal got) = kv.get(key);
        return (exists, MemoryKVVal.unwrap(got));
    }

    /// A frame that allocates nothing else fits exactly 682 pairs: the first
    /// node is at the default free memory pointer `0x80` and each takes three
    /// words, so the 682nd starts at `0xFFE0` and still fits a 16 bit slot.
    function testSet682PairsFitAnOtherwiseEmptyFrame() external view {
        assertEq(this.fillEmptyFrameExternal(682), 1364, "682 pairs is 1364 words");
    }

    /// The 683rd pair would start at `0x10040`, past the widest pointer a slot
    /// holds, so it reverts carrying that address. This is the ceiling as a
    /// pair count, which is the form a caller can measure itself against.
    function testSetOverflowsOnThe683rdPairOfAnOtherwiseEmptyFrame() external {
        vm.expectRevert(abi.encodeWithSelector(LibMemoryKV.MemoryKVOverflow.selector, 0x10040));
        this.fillEmptyFrameExternal(683);
    }

    /// An update never reverts `MemoryKVOverflow`, however far past the bound
    /// the frame has already allocated: the pointer the guard reads is the
    /// matched node's, and a matched node is below the bound by construction.
    function testSetUpdateDoesNotOverflowAboveTheBound(MemoryKVKey key, MemoryKVVal first, MemoryKVVal second)
        external
        view
    {
        vm.assume(MemoryKVVal.unwrap(first) != MemoryKVVal.unwrap(second));

        (uint256 exists, bytes32 got) = this.updateAboveTheBoundExternal(key, first, second);

        assertEq(exists, 1, "the key still exists after the update");
        assertEq(got, MemoryKVVal.unwrap(second), "the update wrote through");
    }
}
