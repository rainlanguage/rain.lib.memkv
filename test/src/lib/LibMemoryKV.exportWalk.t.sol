// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {setFreePointer} from "test/lib/LibFreeMemory.sol";
import {slotOf} from "test/lib/LibMemoryKVKeys.sol";
import {headOf} from "test/lib/LibMemoryKVHandle.sol";
import {countPair} from "test/lib/LibMemoryKVExport.sol";

/// @title LibMemoryKVExportWalkTest
/// The export's WALK: following one internal list from its head to the
/// terminator. Heads and next pointers are whole words, so the export has to
/// read them at full width, exactly as `get` does, wherever in memory the
/// store lives, or the pairs behind them are lost. Each case builds a two
/// node list at an address that puts one of those words on the far side of
/// `0x10000` and exports it in the same frame.
contract LibMemoryKVExportWalkTest is Test {
    using LibMemoryKV for MemoryKV;

    /// The first address that does not fit in sixteen bits.
    uint256 internal constant ABOVE_SIXTEEN_BITS = 0x10000;

    /// Where a header puts its list's head node's next word at exactly
    /// `ABOVE_SIXTEEN_BITS`: the header, then the tail node, then the head
    /// node, whose next word is `0x40` into it.
    uint256 internal constant NEXT_WORD_AT_SIXTEEN_BITS =
        ABOVE_SIXTEEN_BITS - LibMemoryKV.HEADER_BYTES - LibMemoryKV.NODE_BYTES - 0x40;

    /// Where a header ends at exactly `ABOVE_SIXTEEN_BITS`, so both nodes, and
    /// therefore the head and the next pointer the walk follows, are above it.
    uint256 internal constant NODES_ABOVE_SIXTEEN_BITS = ABOVE_SIXTEEN_BITS - LibMemoryKV.HEADER_BYTES;

    /// Two keys that hash into one internal list.
    bytes32 internal constant KEY_TAIL = bytes32(uint256(4));
    bytes32 internal constant KEY_HEAD = bytes32(uint256(5));

    /// Values that share no bits with either key, so a pair assembled from the
    /// wrong words is a different value rather than a coincidence.
    bytes32 internal constant VALUE_TAIL = bytes32(uint256(0xDEC0DE));
    bytes32 internal constant VALUE_HEAD = bytes32(uint256(0xC0FFEE));

    /// Build the two key list with its header at `headerAt` and export it.
    /// `KEY_TAIL` is inserted first, so `KEY_HEAD` is the list's head and
    /// `KEY_TAIL` is reachable only through the head node's next word.
    function exportChainAt(uint256 headerAt) internal pure returns (MemoryKV kv, bytes32[] memory array) {
        setFreePointer(headerAt);
        kv = MEMORY_KV_EMPTY.set(MemoryKVKey.wrap(KEY_TAIL), MemoryKVVal.wrap(VALUE_TAIL))
            .set(MemoryKVKey.wrap(KEY_HEAD), MemoryKVVal.wrap(VALUE_HEAD));
        array = kv.toBytes32Array();
    }

    /// The export holds both pairs, each exactly once. The pair order is
    /// unspecified, so it is not checked.
    function assertBothPairs(bytes32[] memory array) internal pure {
        assertEq(array.length, 4, "both pairs");
        assertEq(countPair(array, KEY_HEAD, VALUE_HEAD), 1, "the head node's pair, once");
        assertEq(countPair(array, KEY_TAIL, VALUE_TAIL), 1, "the pair behind the next word, once");
    }

    function testTheTwoKeysShareOneList() external pure {
        assertEq(slotOf(KEY_HEAD), slotOf(KEY_TAIL), "the two keys share one list");
    }

    /// A head node at `0xFFC0` holds its next word at exactly `0x10000`. The
    /// export must read that word at full width to find the node behind it: a
    /// read truncated to 16 bits lands in the scratch space instead, and the
    /// tail pair never reaches the array.
    function testExportWalksThroughANextWordAtSixteenBits() external pure {
        (MemoryKV kv, bytes32[] memory array) = exportChainAt(NEXT_WORD_AT_SIXTEEN_BITS);

        assertEq(
            headOf(kv, MemoryKVKey.wrap(KEY_HEAD)) + 0x40, ABOVE_SIXTEEN_BITS, "the head node's next word is at 0x10000"
        );
        assertBothPairs(array);
    }

    /// A header that ends at exactly `0x10000` puts both nodes above it, so
    /// the head the export reads out of the header and the next pointer it
    /// reads out of the head node are both wider than sixteen bits.
    function testExportFollowsAHeadAndANextPointerAboveSixteenBits() external pure {
        (MemoryKV kv, bytes32[] memory array) = exportChainAt(NODES_ABOVE_SIXTEEN_BITS);

        assertEq(MemoryKV.unwrap(kv) + LibMemoryKV.HEADER_BYTES, ABOVE_SIXTEEN_BITS, "the header ends at 0x10000");
        assertEq(
            headOf(kv, MemoryKVKey.wrap(KEY_HEAD)),
            ABOVE_SIXTEEN_BITS + LibMemoryKV.NODE_BYTES,
            "the head is the second node above 0x10000"
        );
        assertBothPairs(array);
    }
}
