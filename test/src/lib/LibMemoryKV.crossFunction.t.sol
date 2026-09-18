// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";

import {LibPointer, Pointer} from "rain-solmem-0.1.28/src/lib/LibPointer.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {setFreePointer} from "test/lib/LibFreeMemory.sol";
import {keyForSlot} from "test/lib/LibMemoryKVKeys.sol";
import {lengthOf} from "test/lib/LibMemoryKVHandle.sol";
import {assertValue} from "test/lib/LibMemoryKVAssert.sol";

/// @title LibMemoryKVCrossFunctionTest
/// Two claims about a `MemoryKV` handle that only hold across call frames or
/// across several live copies, which no single-handle test reaches: the word
/// that crosses an external call is the header's address and carries nothing
/// of the store's contents, and every live copy of a non-empty handle is the
/// one store, however many copies there are. Both rest on what `set` computes:
/// where it puts the header, and that it writes inserts and updates in place.
contract LibMemoryKVCrossFunctionTest is Test {
    using LibMemoryKV for MemoryKV;

    /// Where the stores below are built. At or above the free memory pointer
    /// after the `keys` argument is decoded, which `buildExternal` checks on
    /// entry so the store cannot land on the keys it is still reading.
    uint256 internal constant STORE_BASE = 0x300;

    /// Build a store holding `keys`, from a free memory pointer this frame
    /// fixes, and hand back only the handle. The header and the nodes are gone
    /// when this returns.
    function buildExternal(bytes32[] memory keys) external pure returns (MemoryKV) {
        require(
            Pointer.unwrap(LibPointer.allocatedMemoryPointer()) <= STORE_BASE, "the keys must end at or below the store"
        );
        setFreePointer(STORE_BASE);
        MemoryKV kv = MEMORY_KV_EMPTY;
        for (uint256 i = 0; i < keys.length; i++) {
            kv = kv.set(MemoryKVKey.wrap(keys[i]), MemoryKVVal.wrap(bytes32(i + 1)));
        }
        return kv;
    }

    /// A store with a key in every one of the fifteen lists and a store with
    /// one key, built at the same address, cross an external call as the same
    /// word: the header's address. The count, the heads and the occupancy
    /// mask are in the building frame's memory, so nothing about what the
    /// store held crosses with it.
    function testTheWordThatCrossesIsTheHeaderAddressAlone(bytes32 seed) external view {
        bytes32[] memory keys = new bytes32[](LibMemoryKV.LIST_COUNT);
        for (uint256 list = 0; list < LibMemoryKV.LIST_COUNT; list++) {
            keys[list] = MemoryKVKey.unwrap(keyForSlot(keccak256(abi.encode(seed, list)), list));
        }
        bytes32[] memory oneKey = new bytes32[](1);
        oneKey[0] = keys[0];

        assertEq(MemoryKV.unwrap(this.buildExternal(keys)), STORE_BASE, "every list occupied");
        assertEq(MemoryKV.unwrap(this.buildExternal(oneKey)), STORE_BASE, "one key");
    }

    /// Every copy of a non-empty handle is the one store, with a whole chain
    /// of copies live at once. After the first insert every copy is the same
    /// word, and neither an insert nor an update changes it; every copy
    /// sees every key, whichever copy it was set through, and every copy
    /// reports the one word count.
    function testEveryLiveCopyIsTheOneStore(bytes32 seed) external pure {
        MemoryKVKey[] memory keys = new MemoryKVKey[](5);
        MemoryKV[] memory handles = new MemoryKV[](5);
        MemoryKV kv = MEMORY_KV_EMPTY;
        for (uint256 i = 0; i < keys.length; i++) {
            keys[i] = MemoryKVKey.wrap(keccak256(abi.encode(seed, i)));
            kv = kv.set(keys[i], MemoryKVVal.wrap(bytes32(i + 1)));
            handles[i] = kv;
        }

        // Every copy is the first insert's header, and sees every key,
        // including the ones set after it was copied.
        for (uint256 i = 0; i < handles.length; i++) {
            assertEq(MemoryKV.unwrap(handles[i]), MemoryKV.unwrap(handles[0]), "one word");
            assertEq(lengthOf(handles[i]), keys.length * 2, "one count");
            for (uint256 j = 0; j < keys.length; j++) {
                assertValue(handles[i], keys[j], j + 1, "every key");
            }
        }

        // One update through the newest copy and one insert through the oldest
        // reach every copy, oldest and newest included, and move no copy's
        // word.
        MemoryKV updated = handles[handles.length - 1].set(keys[0], MemoryKVVal.wrap(bytes32(uint256(999))));
        MemoryKVKey late = MemoryKVKey.wrap(keccak256(abi.encode(seed, keys.length)));
        MemoryKV inserted = handles[0].set(late, MemoryKVVal.wrap(bytes32(uint256(777))));
        assertEq(MemoryKV.unwrap(updated), MemoryKV.unwrap(handles[0]), "an update returns the one word");
        assertEq(MemoryKV.unwrap(inserted), MemoryKV.unwrap(handles[0]), "an insert returns the one word");
        for (uint256 i = 0; i < handles.length; i++) {
            assertValue(handles[i], keys[0], 999, "after the update");
            assertValue(handles[i], late, 777, "after the insert");
            assertEq(lengthOf(handles[i]), (keys.length + 1) * 2, "one count after the insert");
        }
    }
}
