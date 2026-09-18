// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {slotOf} from "test/lib/LibMemoryKVKeys.sol";
import {headOf} from "test/lib/LibMemoryKVHandle.sol";
import {countPair} from "test/lib/LibMemoryKVExport.sol";
import {setFreePointer} from "test/lib/LibFreeMemory.sol";

/// @title LibMemoryKVExportWalkTest
/// The export's WALK: following one internal list from its head to the
/// terminator. `MemoryKVOverflow` bounds the HEAD pointer of a list at
/// `0xFFFF` and nothing else, because "the node's three words MAY extend above
/// `0xFFFF`, as every field is reached by full width arithmetic from the head".
/// A head near the bound therefore keeps its next word above it, and the
/// export reads that word there at full width, exactly as `get` does, to reach
/// the pairs behind that node.
contract LibMemoryKVExportWalkTest is Test {
    using LibMemoryKV for MemoryKV;

    /// The free memory pointer the chain below is built from. The first node
    /// lands here and the second, which is the one the list's slot points at,
    /// `LibMemoryKV.NODE_BYTES` above it.
    uint256 internal constant CHAIN_POINTER = 0xFF60;

    /// Where the head node lands: the lowest head whose next word, at
    /// `HEAD_POINTER + 0x40`, sits wholly above the bound. Every head above it
    /// that `set` accepts, up to `LibMemoryKV.POINTER_MASK`, keeps its next
    /// word higher still.
    uint256 internal constant HEAD_POINTER = CHAIN_POINTER + LibMemoryKV.NODE_BYTES;

    /// Two keys that hash into one internal list.
    bytes32 internal constant KEY_TAIL = bytes32(uint256(4));
    bytes32 internal constant KEY_HEAD = bytes32(uint256(5));

    /// Values that share no bits with either key, so a pair assembled from the
    /// wrong words is a different value rather than a coincidence.
    bytes32 internal constant VALUE_TAIL = bytes32(uint256(0xDEC0DE));
    bytes32 internal constant VALUE_HEAD = bytes32(uint256(0xC0FFEE));

    /// Build the two key list at `pointer` and export it in the SAME frame, so
    /// the nodes the export walks are the ones this built. `KEY_TAIL` is
    /// inserted first, so `KEY_HEAD` is the list's head and `KEY_TAIL` is
    /// reachable only through the head node's next word.
    function exportChainAtExternal(uint256 pointer) external pure returns (MemoryKV, bytes32[] memory) {
        setFreePointer(pointer);
        MemoryKV kv = MEMORY_KV_EMPTY;
        kv = kv.set(MemoryKVKey.wrap(KEY_TAIL), MemoryKVVal.wrap(VALUE_TAIL));
        kv = kv.set(MemoryKVKey.wrap(KEY_HEAD), MemoryKVVal.wrap(VALUE_HEAD));
        return (kv, kv.toBytes32Array());
    }

    /// The head node's next word is the first word above the bound. The export
    /// reads it at full width and walks on to the tail node behind it, so both
    /// pairs are exported, each exactly once. Pair order is not checked, as
    /// `toBytes32Array` leaves it unspecified.
    function testExportWalksThroughANextWordAboveTheBound() external view {
        assertEq(slotOf(KEY_HEAD), slotOf(KEY_TAIL), "the two keys share one list");
        assertEq(
            HEAD_POINTER + 0x40,
            LibMemoryKV.POINTER_MASK + 1,
            "the head node's next word is the first word above the bound"
        );

        (MemoryKV kv, bytes32[] memory array) = this.exportChainAtExternal(CHAIN_POINTER);

        assertEq(headOf(kv, MemoryKVKey.wrap(KEY_HEAD)), HEAD_POINTER, "the list's head is the node at the bound");
        assertEq(array.length, 4, "both pairs");
        assertEq(countPair(array, KEY_HEAD, VALUE_HEAD), 1, "the head node's pair, exactly once");
        assertEq(
            countPair(array, KEY_TAIL, VALUE_TAIL), 1, "the pair behind the next word above the bound, exactly once"
        );
    }
}
