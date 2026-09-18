// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {keyForSlot} from "test/lib/LibMemoryKVKeys.sol";
import {lengthOf} from "test/lib/LibMemoryKVHandle.sol";
import {assertValue} from "test/lib/LibMemoryKVAssert.sol";

/// @title LibMemoryKVCrossFunctionTest
/// Two claims about a `MemoryKV` handle that no mutation of the library can
/// falsify, because they are about the handle as a `uint256` rather than about
/// anything the library computes: every bit of it survives an external call,
/// and the update/insert asymmetry holds however many handles are live at once.
contract LibMemoryKVCrossFunctionTest is Test {
    using LibMemoryKV for MemoryKV;

    /// Where the saturated store below is built. Above the decoded `keys`
    /// argument so the nodes cannot land on it, and low enough that
    /// `LibMemoryKV.LIST_COUNT` nodes all fit under the
    /// `LibMemoryKV.POINTER_MASK` head pointer bound.
    uint256 internal constant SATURATED_BASE = 0x300;

    /// Build a store holding one key in each of the `LibMemoryKV.LIST_COUNT`
    /// internal lists, from a free memory pointer this frame fixes, and hand
    /// back only the handle. The nodes are gone when this returns.
    function buildSaturatedExternal(bytes32[] memory keys) external pure returns (MemoryKV) {
        assembly ("memory-safe") {
            mstore(0x40, SATURATED_BASE)
        }
        MemoryKV kv = MEMORY_KV_EMPTY;
        for (uint256 i = 0; i < keys.length; i++) {
            kv = kv.set(MemoryKVKey.wrap(keys[i]), MemoryKVVal.wrap(bytes32(i + 1)));
        }
        return kv;
    }

    /// A handle with every head pointer slot and the word count in use arrives
    /// on the other side of an external call bit for bit. The word it must equal is
    /// computed here from the addresses the building frame was forced to
    /// allocate at, so a handle that lost the word count, or a slot, or the top
    /// bit of one pointer, is a different number rather than a store that
    /// merely reads oddly.
    function testSaturatedHandleCrossesTheCallBoundaryBitForBit(bytes32 seed) external view {
        bytes32[] memory keys = new bytes32[](LibMemoryKV.LIST_COUNT);
        uint256 expected = (LibMemoryKV.LIST_COUNT * 2) << LibMemoryKV.COUNT_BIT_OFFSET;
        for (uint256 slot = 0; slot < LibMemoryKV.LIST_COUNT; slot++) {
            keys[slot] = MemoryKVKey.unwrap(keyForSlot(keccak256(abi.encode(seed, slot)), slot));
            expected |= (SATURATED_BASE + slot * LibMemoryKV.NODE_BYTES) << (slot * LibMemoryKV.SLOT_BITS);
        }

        MemoryKV kv = this.buildSaturatedExternal(keys);

        assertEq(MemoryKV.unwrap(kv), expected, "handle word");
    }

    /// The asymmetry holds with a whole chain of handles live at once: the
    /// update reaches all five, while each insert reaches only the handles from
    /// the one `set` returned onwards. Each handle also keeps its own word
    /// count, which is the only part of a handle an insert changes.
    function testAsymmetryHoldsAcrossManyLiveHandles(bytes32 seed) external pure {
        MemoryKVKey[] memory keys = new MemoryKVKey[](5);
        MemoryKV[] memory handles = new MemoryKV[](5);
        MemoryKV kv = MEMORY_KV_EMPTY;
        for (uint256 i = 0; i < keys.length; i++) {
            keys[i] = MemoryKVKey.wrap(keccak256(abi.encode(seed, i)));
            kv = kv.set(keys[i], MemoryKVVal.wrap(bytes32(i + 1)));
            handles[i] = kv;
        }

        // Every handle carries the count of the inserts it was branched after,
        // and sees exactly those keys.
        for (uint256 i = 0; i < handles.length; i++) {
            assertEq(lengthOf(handles[i]), (i + 1) * 2, "count");
            for (uint256 j = 0; j < keys.length; j++) {
                if (j <= i) {
                    assertValue(handles[i], keys[j], j + 1, "before branch");
                } else {
                    assertFalse(handles[i].has(keys[j]), "after branch");
                }
            }
        }

        // One update through the newest handle moves the value every handle
        // holding that key reports, oldest included.
        handles[handles.length - 1] = handles[handles.length - 1].set(keys[0], MemoryKVVal.wrap(bytes32(uint256(999))));
        for (uint256 i = 0; i < handles.length; i++) {
            assertValue(handles[i], keys[0], 999, "after update");
            assertEq(lengthOf(handles[i]), (i + 1) * 2, "count after update");
        }
    }
}
