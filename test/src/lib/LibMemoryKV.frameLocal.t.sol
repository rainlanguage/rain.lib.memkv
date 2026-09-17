// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {LibMemoryKVTestHandle} from "test/lib/LibMemoryKVTestHandle.sol";

/// @title LibMemoryKVFrameLocalTest
/// A `MemoryKV` is a `uint256`, so the ABI carries it across an external call
/// without complaint, and the list items it names stay behind in the frame
/// that built them. These tests state both halves as values: the handle's bits
/// arrive intact, and the same handle then reports the READING frame's memory
/// rather than the store, so the hazard is a wrong number rather than a revert
/// a caller could catch.
contract LibMemoryKVFrameLocalTest is Test {
    using LibMemoryKV for MemoryKV;
    using LibMemoryKVTestHandle for MemoryKV;

    /// Build a one pair store whose node is at exactly `0xA0`, read it back in
    /// the SAME frame, and return the handle alongside what that read saw. The
    /// node is gone when this returns; only the handle's bits cross.
    function buildAndGetExternal(MemoryKVKey key, MemoryKVVal value)
        external
        pure
        returns (MemoryKV, uint256, bytes32)
    {
        assembly ("memory-safe") {
            mstore(0x40, 0xA0)
        }
        MemoryKV kv = MEMORY_KV_EMPTY.set(key, value);
        (uint256 exists, MemoryKVVal got) = kv.get(key);
        return (kv, exists, MemoryKVVal.unwrap(got));
    }

    /// Read `key` out of `kv` in a frame whose memory at the node's addresses
    /// is exactly `filler`. A `bytes memory` argument decodes at `0x80`, its
    /// length word, so the three words of `filler` land at `0xA0`, `0xC0` and
    /// `0xE0`, which is where the builder above put its node. Both facts are
    /// required rather than assumed so a decode that moved fails loudly.
    function getWithFillerExternal(MemoryKV kv, MemoryKVKey key, bytes memory filler)
        external
        pure
        returns (uint256, bytes32)
    {
        uint256 lengthWord;
        assembly ("memory-safe") {
            lengthWord := filler
        }
        require(lengthWord == 0x80, "filler must decode at 0x80");
        require(filler.length == 0x60, "filler must be three words");

        (uint256 exists, MemoryKVVal got) = LibMemoryKV.get(kv, key);
        return (exists, MemoryKVVal.unwrap(got));
    }

    /// The handle crosses an external call with every bit intact: the word
    /// count and the head pointer, which are all a consumer can inspect, are
    /// exactly what the building frame recorded. Nothing in the value says the
    /// store it names is gone.
    function testHandleCrossesTheCallBoundaryIntact() external view {
        MemoryKVKey key = MemoryKVKey.wrap(bytes32(uint256(0xA11CE)));
        MemoryKVVal value = MemoryKVVal.wrap(bytes32(uint256(0xBEEF)));

        (MemoryKV kv, uint256 exists, bytes32 got) = this.buildAndGetExternal(key, value);

        assertEq(exists, 1, "the building frame reads its own store");
        assertEq(got, MemoryKVVal.unwrap(value), "the building frame reads the value it set");
        assertEq(kv.lengthOf(), 2, "the word count crosses the boundary");
        assertEq(kv.headOf(key), 0xA0, "the head pointer crosses the boundary");
    }

    /// The same handle in another frame reads THAT frame's memory. The filler
    /// occupies the node's addresses here, so the store answers with the
    /// filler's value and not the one it was built with.
    function testCrossFrameGetReadsTheReadingFramesMemory() external view {
        MemoryKVKey key = MemoryKVKey.wrap(bytes32(uint256(0xA11CE)));
        MemoryKVVal value = MemoryKVVal.wrap(bytes32(uint256(0xBEEF)));

        (MemoryKV kv,,) = this.buildAndGetExternal(key, value);

        bytes memory filler = abi.encodePacked(MemoryKVKey.unwrap(key), bytes32(uint256(0xD00D)), bytes32(0));
        (uint256 exists, bytes32 got) = this.getWithFillerExternal(kv, key, filler);

        assertEq(exists, 1, "the walk finds a node at the head pointer");
        assertEq(uint256(got), 0xD00D, "the value comes from the reading frame, not the store");
    }
}
