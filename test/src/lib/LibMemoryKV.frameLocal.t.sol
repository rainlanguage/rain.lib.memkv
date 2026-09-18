// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {setFreePointer} from "test/lib/LibFreeMemory.sol";
import {headAddressOf, headOf} from "test/lib/LibMemoryKVHandle.sol";
import {slotOf} from "test/lib/LibMemoryKVKeys.sol";

/// @title LibMemoryKVFrameLocalTest
/// A `MemoryKV` is a `uint256`, so the ABI carries it across an external call
/// without complaint, and the header and nodes it names stay behind in the
/// frame that built them. These tests state both halves as values: the
/// handle's bits arrive intact, and the same handle then reports the READING
/// frame's memory rather than the store, so the hazard is a wrong number
/// rather than a revert a caller could catch.
contract LibMemoryKVFrameLocalTest is Test {
    using LibMemoryKV for MemoryKV;

    /// Where the builder below puts the header.
    uint256 internal constant HEADER_AT = 0xA0;

    /// Where the builder's one node lands, directly after the header.
    uint256 internal constant NODE_AT = HEADER_AT + LibMemoryKV.HEADER_BYTES;

    /// The key the builder sets and the reader looks up.
    bytes32 internal constant KEY = bytes32(uint256(0xA11CE));

    /// Build a one pair store whose header is at exactly `HEADER_AT`, read it
    /// back in the SAME frame, and return the handle alongside what that read
    /// saw. The header and the node are gone when this returns; only the
    /// handle's bits cross.
    function buildAndGetExternal(MemoryKVVal value) external pure returns (MemoryKV, uint256, bytes32, uint256) {
        setFreePointer(HEADER_AT);
        MemoryKV kv = MEMORY_KV_EMPTY.set(MemoryKVKey.wrap(KEY), value);
        (uint256 exists, MemoryKVVal got) = kv.get(MemoryKVKey.wrap(KEY));
        return (kv, exists, MemoryKVVal.unwrap(got), headOf(kv, MemoryKVKey.wrap(KEY)));
    }

    /// Read `KEY` out of `kv` in a frame whose memory at the builder's
    /// addresses is exactly `filler`. A `bytes memory` argument decodes at
    /// `0x80`, its length word, so the words of `filler` start at `0xA0`,
    /// which is where the builder put its header. Both facts are required
    /// rather than assumed so a decode that moved fails loudly.
    function getWithFillerExternal(MemoryKV kv, bytes memory filler) external pure returns (uint256, bytes32) {
        uint256 lengthWord;
        assembly ("memory-safe") {
            lengthWord := filler
        }
        require(lengthWord == 0x80, "filler must decode at 0x80");
        require(
            filler.length == LibMemoryKV.HEADER_BYTES + LibMemoryKV.NODE_BYTES, "filler must be a header and a node"
        );

        (uint256 exists, MemoryKVVal got) = LibMemoryKV.get(kv, MemoryKVKey.wrap(KEY));
        return (exists, MemoryKVVal.unwrap(got));
    }

    /// A forged header and node, laid out from `HEADER_AT` the way the builder
    /// laid out its own: `KEY`'s head names a node at `NODE_AT` holding `KEY`
    /// and `value`, every other word of the header is zero.
    function forgedStore(bytes32 value) internal pure returns (bytes memory filler) {
        filler = new bytes(LibMemoryKV.HEADER_BYTES + LibMemoryKV.NODE_BYTES);
        uint256 headOffset = headAddressOf(MemoryKV.wrap(HEADER_AT), slotOf(KEY)) - HEADER_AT;
        uint256 nodeAt = NODE_AT;
        uint256 nodeOffset = NODE_AT - HEADER_AT;
        bytes32 key = KEY;
        assembly ("memory-safe") {
            let data := add(filler, 0x20)
            mstore(add(data, headOffset), nodeAt)
            let node := add(data, nodeOffset)
            mstore(node, key)
            mstore(add(node, 0x20), value)
        }
    }

    /// The handle crosses an external call with every bit intact, and every
    /// bit of it is the header's address. The word count and the head are in
    /// the building frame's memory, not in the handle, so nothing that crosses
    /// says whether the store it names holds anything at all.
    function testHandleCrossesTheCallBoundaryAsTheHeaderAddress() external view {
        MemoryKVVal value = MemoryKVVal.wrap(bytes32(uint256(0xBEEF)));

        (MemoryKV kv, uint256 exists, bytes32 got, uint256 head) = this.buildAndGetExternal(value);

        assertEq(exists, 1, "the building frame reads its own store");
        assertEq(got, MemoryKVVal.unwrap(value), "the building frame reads the value it set");
        assertEq(head, NODE_AT, "the building frame's node is directly after its header");
        assertEq(MemoryKV.unwrap(kv), HEADER_AT, "the handle that crosses is the header address alone");
    }

    /// The same handle in another frame reads THAT frame's memory. A forged
    /// header and node occupy the store's addresses here, so the store answers
    /// with the forged value and not the one it was built with.
    function testCrossFrameGetReadsTheReadingFramesMemory() external view {
        MemoryKVVal value = MemoryKVVal.wrap(bytes32(uint256(0xBEEF)));

        (MemoryKV kv,,,) = this.buildAndGetExternal(value);
        (uint256 exists, bytes32 got) = this.getWithFillerExternal(kv, forgedStore(bytes32(uint256(0xD00D))));

        assertEq(exists, 1, "the walk finds a node through the forged head");
        assertEq(uint256(got), 0xD00D, "the value comes from the reading frame, not the store");
    }
}
