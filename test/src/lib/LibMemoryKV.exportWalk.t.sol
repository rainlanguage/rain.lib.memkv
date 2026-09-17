// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {LibMemoryKVTestKeys} from "test/lib/LibMemoryKVTestKeys.sol";
import {LibMemoryKVTestHandle} from "test/lib/LibMemoryKVTestHandle.sol";

/// @title LibMemoryKVExportWalkTest
/// The export's WALK: following one internal list from its head to the
/// terminator. `MemoryKVOverflow` bounds the HEAD pointer of a list at
/// `0xFFFF` and nothing else, because "the node's three words MAY extend above
/// `0xFFFF`, as every field is reached by full width arithmetic from the head".
/// The widest head `set` accepts therefore keeps its next word above that
/// bound, and the export has to read it there, exactly as `get` does, or the
/// pairs behind that node are lost.
contract LibMemoryKVExportWalkTest is Test {
    using LibMemoryKV for MemoryKV;
    using LibMemoryKVTestKeys for MemoryKVKey;
    using LibMemoryKVTestHandle for MemoryKV;

    /// The widest head pointer a list slot can hold.
    uint256 constant POINTER_MAX = 0xFFFF;

    /// Bytes `set` allocates per inserted key/value pair.
    uint256 constant NODE_BYTES = 0x60;

    /// The free memory pointer the chain below is built from. The first node
    /// lands here and the second, which is the one the list's slot points at,
    /// `NODE_BYTES` above it.
    uint256 constant CHAIN_POINTER = 0xFF60;

    /// Where the head node lands, which is the widest head the chain can have
    /// while its next word is still a whole word above the bound.
    uint256 constant HEAD_POINTER = CHAIN_POINTER + NODE_BYTES;

    /// Two keys that hash into one internal list, small enough that a walk
    /// which mistook memory below the store for a pointer would read low
    /// memory rather than run out of gas.
    bytes32 constant KEY_TAIL = bytes32(uint256(4));
    bytes32 constant KEY_HEAD = bytes32(uint256(5));

    /// Values that share no bits with either key, so a pair assembled from the
    /// wrong words is a different value rather than a coincidence.
    bytes32 constant VALUE_TAIL = bytes32(uint256(0xDEC0DE));
    bytes32 constant VALUE_HEAD = bytes32(uint256(0xC0FFEE));

    /// Build the two key list at `pointer` and export it in the SAME frame, so
    /// the nodes the export walks are the ones this built. `KEY_TAIL` is
    /// inserted first, so `KEY_HEAD` is the list's head and `KEY_TAIL` is
    /// reachable only through the head node's next word.
    function exportChainAtExternal(uint256 pointer) external pure returns (MemoryKV, bytes32[] memory) {
        assembly ("memory-safe") {
            mstore(0x40, pointer)
        }
        MemoryKV kv = MEMORY_KV_EMPTY;
        kv = kv.set(MemoryKVKey.wrap(KEY_TAIL), MemoryKVVal.wrap(VALUE_TAIL));
        kv = kv.set(MemoryKVKey.wrap(KEY_HEAD), MemoryKVVal.wrap(VALUE_HEAD));
        return (kv, kv.toBytes32Array());
    }

    /// A head node at `0xFFC0` holds its next word at exactly `0x10000`. The
    /// export must read that word at full width to find the node behind it: a
    /// read truncated to 16 bits lands in the scratch space instead, where the
    /// last hashed key is, and the tail pair never reaches the array.
    function testExportWalksThroughANextWordAboveTheBound() external view {
        assertEq(
            MemoryKVKey.wrap(KEY_HEAD).slotOf(), MemoryKVKey.wrap(KEY_TAIL).slotOf(), "the two keys share one list"
        );
        assertGt(HEAD_POINTER + 0x40, POINTER_MAX, "the head node's next word is above the bound");

        (MemoryKV kv, bytes32[] memory array) = this.exportChainAtExternal(CHAIN_POINTER);

        assertEq(kv.headOf(MemoryKVKey.wrap(KEY_HEAD)), HEAD_POINTER, "the list's head is the node at the bound");
        assertEq(array.length, 4, "both pairs");
        assertEq(array[0], KEY_HEAD, "the head node's key");
        assertEq(array[1], VALUE_HEAD, "the head node's value");
        assertEq(array[2], KEY_TAIL, "the key behind the next word above the bound");
        assertEq(array[3], VALUE_TAIL, "the value behind the next word above the bound");
    }
}
