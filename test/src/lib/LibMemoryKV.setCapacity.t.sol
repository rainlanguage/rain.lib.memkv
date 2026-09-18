// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {LibPointer, Pointer} from "rain-solmem-0.1.28/src/lib/LibPointer.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {EMPTY_FRAME_PAIRS} from "test/lib/LibMemoryKVCapacity.sol";

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
        MemoryKV kv = MEMORY_KV_EMPTY;
        for (uint256 i = 1; i <= pairs; i++) {
            kv = kv.set(MemoryKVKey.wrap(bytes32(i)), MemoryKVVal.wrap(bytes32(i)));
        }
        return MemoryKV.unwrap(kv) >> 0xf0;
    }

    /// Allocate an unrelated `bytes32[]` of `elements` elements in a frame that
    /// starts at the default free memory pointer, then insert `pairs` distinct
    /// keys behind it. The array costs a length word plus its elements, and
    /// that cost is required rather than assumed so a frame that started
    /// somewhere else is a failure here rather than a different capacity.
    /// Returns the word count.
    function fillAfterUnrelatedAllocationExternal(uint256 elements, uint256 pairs) external pure returns (uint256) {
        assembly ("memory-safe") {
            mstore(0x40, 0x80)
        }
        bytes32[] memory unrelated = new bytes32[](elements);
        require(unrelated.length == elements, "the unrelated array is live");
        require(
            Pointer.unwrap(LibPointer.allocatedMemoryPointer()) == 0xA0 + elements * 0x20,
            "the unrelated array is a length word and its elements"
        );

        MemoryKV kv = MEMORY_KV_EMPTY;
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
        MemoryKV kv = MEMORY_KV_EMPTY.set(key, first);
        assembly ("memory-safe") {
            mstore(0x40, 0x20000)
        }
        kv = kv.set(key, second);
        (uint256 exists, MemoryKVVal got) = kv.get(key);
        return (exists, MemoryKVVal.unwrap(got));
    }

    /// A frame that allocates nothing else fits `EMPTY_FRAME_PAIRS` pairs: the
    /// first node is at the default free memory pointer `0x80` and each is
    /// `NODE_BYTES`, so the last of them still starts at or below the widest
    /// pointer a head slot holds.
    function testSetFillsAnOtherwiseEmptyFrameToItsCapacity() external view {
        assertEq(this.fillEmptyFrameExternal(EMPTY_FRAME_PAIRS), EMPTY_FRAME_PAIRS * 2, "each pair is two words");
    }

    /// One pair past `EMPTY_FRAME_PAIRS` would start at
    /// `0x80 + EMPTY_FRAME_PAIRS * NODE_BYTES`, past the widest pointer a slot
    /// holds, so it reverts carrying that address. This is the ceiling as a
    /// pair count, which is the form a caller can measure itself against.
    function testSetOverflowsOnePairPastAnOtherwiseEmptyFramesCapacity() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                LibMemoryKV.MemoryKVOverflow.selector, 0x80 + EMPTY_FRAME_PAIRS * LibMemoryKV.NODE_BYTES
            )
        );
        this.fillEmptyFrameExternal(EMPTY_FRAME_PAIRS + 1);
    }

    /// An empty `bytes32[]` is one word, and that one word costs a whole pair:
    /// the nodes start at `0xA0` instead of `0x80`, so the last one that fits
    /// is the 681st, at `0xFFA0`.
    function testOneUnrelatedWordLeavesRoomFor681Pairs() external view {
        assertEq(this.fillAfterUnrelatedAllocationExternal(0, 681), 1362, "681 pairs is 1362 words");
    }

    /// The `EMPTY_FRAME_PAIRS` pairs that fit an otherwise empty frame revert
    /// once one unrelated word is in that frame: the last of them would start
    /// at `0x10000`. A pair count is therefore not a capacity: what the caller
    /// has already allocated decides whether the same count succeeds or
    /// reverts.
    function testOneUnrelatedWordMakesAnEmptyFramesCapacityOverflow() external {
        vm.expectRevert(abi.encodeWithSelector(LibMemoryKV.MemoryKVOverflow.selector, 0x10000));
        this.fillAfterUnrelatedAllocationExternal(0, EMPTY_FRAME_PAIRS);
    }

    /// A bigger allocation costs more pairs, and not one per word: eight
    /// unrelated words start the nodes at `0x180` and cost three pairs, leaving
    /// 679 with the 680th at `0x10020`.
    function testEightUnrelatedWordsCostThreePairs() external {
        assertEq(this.fillAfterUnrelatedAllocationExternal(7, 679), 1358, "679 pairs is 1358 words");
        vm.expectRevert(abi.encodeWithSelector(LibMemoryKV.MemoryKVOverflow.selector, 0x10020));
        this.fillAfterUnrelatedAllocationExternal(7, 680);
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
