// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

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

    uint256 internal constant LIST_COUNT = 15;
    uint256 internal constant SLOT_BITS = 0x10;
    uint256 internal constant NODE_SIZE = 0x60;

    /// Where the saturated store below is built. Above the decoded `keys`
    /// argument so the nodes cannot land on it, and low enough that fifteen
    /// nodes all fit under the `0xFFFF` head pointer bound.
    uint256 internal constant SATURATED_BASE = 0x300;

    /// Build a store holding one key in each of the fifteen internal lists,
    /// from a free memory pointer this frame fixes, and hand back only the
    /// handle. The nodes are gone when this returns.
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

    /// A handle with every one of its sixteen fields in use arrives on the
    /// other side of an external call bit for bit. The word it must equal is
    /// computed here from the addresses the building frame was forced to
    /// allocate at, so a handle that lost the word count, or a slot, or the top
    /// bit of one pointer, is a different number rather than a store that
    /// merely reads oddly.
    function testSaturatedHandleCrossesTheCallBoundaryBitForBit(bytes32 seed) external view {
        bytes32[] memory keys = new bytes32[](LIST_COUNT);
        uint256 expected = (LIST_COUNT * 2) << 0xf0;
        for (uint256 slot = 0; slot < LIST_COUNT; slot++) {
            keys[slot] = MemoryKVKey.unwrap(keyForSlot(keccak256(abi.encode(seed, slot)), slot));
            expected |= (SATURATED_BASE + slot * NODE_SIZE) << (slot * SLOT_BITS);
        }

        MemoryKV kv = this.buildSaturatedExternal(keys);

        assertEq(MemoryKV.unwrap(kv), expected, "handle word");
    }

    /// The asymmetry holds with a whole chain of handles live at once: the
    /// update reaches all five, while each insert reaches only the handles from
    /// the one `set` returned onwards. An insert writes the word count and the
    /// head pointer of the inserted key's list into the handle it returns. An
    /// update writes no bit of any handle, so every handle word, the one `set`
    /// returns included, is the same before and after it.
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
        // holding that key reports, oldest included, and leaves every handle
        // word as it was.
        uint256[] memory before = new uint256[](handles.length);
        for (uint256 i = 0; i < handles.length; i++) {
            before[i] = MemoryKV.unwrap(handles[i]);
        }
        handles[handles.length - 1] = handles[handles.length - 1].set(keys[0], MemoryKVVal.wrap(bytes32(uint256(999))));
        for (uint256 i = 0; i < handles.length; i++) {
            assertValue(handles[i], keys[0], 999, "after update");
            assertEq(MemoryKV.unwrap(handles[i]), before[i], "handle word after update");
        }
    }
}
