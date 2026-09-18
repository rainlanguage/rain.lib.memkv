// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";

import {LibPointer, Pointer} from "rain-solmem-0.1.28/src/lib/LibPointer.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {keyForSlot} from "test/lib/LibMemoryKVKeys.sol";
import {lengthOf} from "test/lib/LibMemoryKVHandle.sol";
import {assertValue} from "test/lib/LibMemoryKVAssert.sol";
import {setFreePointer} from "test/lib/LibFreeMemory.sol";

/// @title LibMemoryKVCrossFunctionTest
/// Two properties of `MemoryKV` handles that take more than one call frame or
/// more than one live handle to observe. The packed word `set` builds, its
/// count at `COUNT_BIT_OFFSET` and list `i`'s head at `i * SLOT_BITS` over
/// nodes `NODE_BYTES` apart, survives an external call bit for bit. An update
/// reaches every live handle holding the key, while an insert changes only the
/// handle `set` returns.
contract LibMemoryKVCrossFunctionTest is Test {
    using LibMemoryKV for MemoryKV;

    /// Where `buildSaturatedExternal` builds its store. It must sit at or above
    /// the free memory pointer after `keys` is decoded, which that function
    /// checks on entry, so no node lands on `keys`. It is low enough that
    /// `LibMemoryKV.LIST_COUNT` nodes all sit at or under
    /// `LibMemoryKV.POINTER_MASK`.
    uint256 internal constant SATURATED_BASE = 0x300;

    /// The free memory pointer on entry to a function in this contract, before
    /// its memory arguments are decoded.
    uint256 internal constant ENTRY_FREE_POINTER = 0x80;

    /// Build a store holding `keys`, `keys[i]` set to `i + 1`, with its nodes
    /// allocated upwards from `SATURATED_BASE`, and hand back only the handle.
    /// The nodes are gone when this returns. Reverts when the decoded `keys`
    /// end above `SATURATED_BASE`, where the nodes would overwrite keys the
    /// loop has yet to read.
    function buildSaturatedExternal(bytes32[] memory keys) external pure returns (MemoryKV) {
        require(Pointer.unwrap(LibPointer.allocatedMemoryPointer()) <= SATURATED_BASE, "keys overlap SATURATED_BASE");
        setFreePointer(SATURATED_BASE);
        MemoryKV kv = MEMORY_KV_EMPTY;
        for (uint256 i = 0; i < keys.length; i++) {
            kv = kv.set(MemoryKVKey.wrap(keys[i]), MemoryKVVal.wrap(bytes32(i + 1)));
        }
        return kv;
    }

    /// `buildSaturatedExternal` builds from the most keys whose decoded array
    /// ends at `SATURATED_BASE`, and reverts on one key more, before any node
    /// is written over them.
    function testSaturatedBuilderRefusesKeysReachingPastItsBase() external {
        // A decoded `bytes32[]` is its length word, then one word per key.
        uint256 fit = (SATURATED_BASE - ENTRY_FREE_POINTER - 0x20) / 0x20;
        bytes32[] memory keys = new bytes32[](fit);
        for (uint256 i = 0; i < fit; i++) {
            keys[i] = keccak256(abi.encode(i));
        }
        assertEq(lengthOf(this.buildSaturatedExternal(keys)), fit * 2, "every key that fits is inserted");

        bytes32[] memory tooMany = new bytes32[](fit + 1);
        vm.expectRevert(bytes("keys overlap SATURATED_BASE"));
        this.buildSaturatedExternal(tooMany);
    }

    /// A handle with every head pointer slot and the word count in use arrives
    /// on the other side of an external call bit for bit. It equals the word
    /// computed here from the word count and the addresses the building frame
    /// allocates its nodes at.
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
