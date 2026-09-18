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
/// more than one live handle to observe. The word that crosses an external
/// call is the header's address and carries nothing of the store's contents.
/// Every live copy of a non-empty handle is the one store, however many copies
/// there are.
contract LibMemoryKVCrossFunctionTest is Test {
    using LibMemoryKV for MemoryKV;

    /// Where `buildExternal` builds its store. It must sit at or above the free
    /// memory pointer after `keys` is decoded, which that function checks on
    /// entry, so neither the header nor a node lands on `keys`.
    uint256 internal constant STORE_BASE = 0x300;

    /// The free memory pointer on entry to a function in this contract, before
    /// its memory arguments are decoded.
    uint256 internal constant ENTRY_FREE_POINTER = 0x80;

    /// Build a store holding `keys`, `keys[i]` set to `i + 1`, with its header
    /// and then its nodes allocated upwards from `STORE_BASE`, and hand back
    /// only the handle. The header and the nodes are gone when this returns.
    /// Reverts when the decoded `keys` end above `STORE_BASE`, where the store
    /// would overwrite keys the loop has yet to read.
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

    /// `buildExternal` builds from the most keys whose decoded array ends at
    /// `STORE_BASE`, putting the header there, and reverts on one key more,
    /// before the header or any node is written over them.
    function testBuilderRefusesKeysReachingPastItsBase() external {
        // A decoded `bytes32[]` is its length word, then one word per key.
        uint256 fit = (STORE_BASE - ENTRY_FREE_POINTER - 0x20) / 0x20;
        bytes32[] memory keys = new bytes32[](fit);
        for (uint256 i = 0; i < fit; i++) {
            keys[i] = keccak256(abi.encode(i));
        }
        assertEq(MemoryKV.unwrap(this.buildExternal(keys)), STORE_BASE, "the keys that fit build at the base");

        bytes32[] memory tooMany = new bytes32[](fit + 1);
        vm.expectRevert(bytes("the keys must end at or below the store"));
        this.buildExternal(tooMany);
    }

    /// A store with a key in every one of the `LibMemoryKV.LIST_COUNT` lists
    /// and a store with one key, built at the same address, cross an external
    /// call as the same word: the header's address. The count, the heads and
    /// the occupancy mask are in the building frame's memory, so nothing about
    /// what the store held crosses with it.
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
