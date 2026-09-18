// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {LibPointer, Pointer} from "rain-solmem-0.1.28/src/lib/LibPointer.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {dirtyFreeMemory, setFreePointer} from "test/lib/LibFreeMemory.sol";
import {COUNT_MAX, withCount, lengthOf, headOf, craftNode, handleWith} from "test/lib/LibMemoryKVHandle.sol";
import {slotOf} from "test/lib/LibMemoryKVKeys.sol";

/// @title LibMemoryKVHandleTest
/// The promises `withCount`, `craftNode` and `handleWith` make and other tests
/// rest on. `craftNode` and `handleWith` build the node and handle an insert
/// builds, so a list crafted with them reads as one `set` built.
contract LibMemoryKVHandleTest is Test {
    using LibMemoryKV for MemoryKV;

    /// The words in one list node.
    uint256 internal constant NODE_WORDS = LibMemoryKV.NODE_BYTES / 0x20;

    /// `craftNode` with the free memory pointer first moved to `at`, in a frame
    /// of its own so a test can expect its revert.
    function craftNodeAtExternal(uint256 at) external pure returns (uint256) {
        setFreePointer(at);
        return craftNode(MemoryKVKey.wrap(bytes32(0)), MemoryKVVal.wrap(bytes32(0)), 0);
    }

    /// `handleWith` in a frame of its own so a test can expect its revert.
    function handleWithExternal(uint256 slot, uint256 head, uint256 words) external pure returns (MemoryKV) {
        return handleWith(slot, head, words);
    }

    /// A node crafted where an insert into an empty store would put its node,
    /// under a handle naming it with one pair's count, is exactly what that
    /// insert builds: the same handle, the same three words and the same
    /// allocation. The memory under each is dirtied first, so a word either
    /// one leaves unwritten reads as the sentinel.
    function testCraftNodeAndHandleWithBuildWhatAnInsertBuilds(MemoryKVKey key, MemoryKVVal value) external pure {
        bytes32 sentinel = keccak256(abi.encode(key, value));
        Pointer at = LibPointer.allocatedMemoryPointer();

        dirtyFreeMemory(sentinel, NODE_WORDS);
        MemoryKV crafted = handleWith(slotOf(MemoryKVKey.unwrap(key)), craftNode(key, value, 0), 2);
        Pointer craftedEnd = LibPointer.allocatedMemoryPointer();
        // Held on the stack: the insert below reuses the node's memory.
        bytes32 craftedKey = LibPointer.unsafeReadWord(at);
        bytes32 craftedValue = LibPointer.unsafeReadWord(LibPointer.unsafeAddWord(at));
        bytes32 craftedNext = LibPointer.unsafeReadWord(LibPointer.unsafeAddWords(at, 2));

        setFreePointer(Pointer.unwrap(at));
        dirtyFreeMemory(sentinel, NODE_WORDS);
        MemoryKV inserted = MEMORY_KV_EMPTY.set(key, value);
        Pointer insertedEnd = LibPointer.allocatedMemoryPointer();

        assertEq(MemoryKV.unwrap(crafted), MemoryKV.unwrap(inserted), "the handle an insert builds");
        assertEq(Pointer.unwrap(craftedEnd), Pointer.unwrap(insertedEnd), "the allocation an insert makes");
        assertEq(craftedKey, LibPointer.unsafeReadWord(at), "the key word an insert writes");
        assertEq(
            craftedValue, LibPointer.unsafeReadWord(LibPointer.unsafeAddWord(at)), "the value word an insert writes"
        );
        assertEq(
            craftedNext, LibPointer.unsafeReadWord(LibPointer.unsafeAddWords(at, 2)), "the next word an insert writes"
        );
    }

    /// The node's third word is the next pointer it was given, whatever it is,
    /// so a crafted list links where the test says.
    function testCraftNodeLinksToTheNextPointerItIsGiven(uint256 next) external pure {
        dirtyFreeMemory(bytes32(~next), NODE_WORDS);
        uint256 node = craftNode(MemoryKVKey.wrap(bytes32(0)), MemoryKVVal.wrap(bytes32(0)), next);
        uint256 end = Pointer.unwrap(LibPointer.allocatedMemoryPointer());
        assertEq(
            uint256(LibPointer.unsafeReadWord(LibPointer.unsafeAddWords(Pointer.wrap(node), 2))), next, "next word"
        );
        assertEq(end, node + LibMemoryKV.NODE_BYTES, "one node allocated");
    }

    /// A node at `LibMemoryKV.POINTER_MASK` still fits a head slot; one byte
    /// higher does not and reverts rather than handing back an address a handle
    /// would truncate.
    function testCraftNodeRevertsAboveTheWidestHeadPointer() external {
        assertEq(
            this.craftNodeAtExternal(LibMemoryKV.POINTER_MASK), LibMemoryKV.POINTER_MASK, "the widest head pointer"
        );
        vm.expectRevert("crafted node pointer must fit a head slot");
        this.craftNodeAtExternal(LibMemoryKV.POINTER_MASK + 1);
    }

    /// The handle heads the named list with the named pointer, every other list
    /// is empty, and the count is the one given.
    function testHandleWithHeadsOnlyTheNamedList(uint256 slot, uint16 head, uint16 words) external pure {
        slot = bound(slot, 0, LibMemoryKV.LIST_COUNT - 1);
        MemoryKV kv = handleWith(slot, head, words);

        for (uint256 other = 0; other < LibMemoryKV.LIST_COUNT; other++) {
            assertEq(headOf(kv, other), other == slot ? head : 0, string.concat("head of slot ", vm.toString(other)));
        }
        assertEq(lengthOf(kv), words, "count");
    }

    /// Each field one past what its place in the handle holds reverts, while
    /// the other two stay at their widest valid value.
    function testHandleWithRejectsAFieldThatDoesNotFit() external {
        uint256 lastSlot = LibMemoryKV.LIST_COUNT - 1;
        uint256 widestHead = LibMemoryKV.POINTER_MASK;
        MemoryKV kv = this.handleWithExternal(lastSlot, widestHead, COUNT_MAX);
        assertEq(headOf(kv, lastSlot), widestHead, "the widest head");
        assertEq(lengthOf(kv), COUNT_MAX, "the widest count");

        vm.expectRevert("handle field out of range");
        this.handleWithExternal(LibMemoryKV.LIST_COUNT, widestHead, COUNT_MAX);
        vm.expectRevert("handle field out of range");
        this.handleWithExternal(lastSlot, widestHead + 1, COUNT_MAX);
        vm.expectRevert("handle field out of range");
        this.handleWithExternal(lastSlot, widestHead, COUNT_MAX + 1);
    }

    /// `withCount` rewrites the count and nothing under it: from any word,
    /// every head pointer comes through unchanged, the count reads back as the
    /// one forced, and every bit below the count's slot is the bit it was.
    function testWithCountKeepsEveryBitUnderTheCount(uint256 word, uint256 forced) external pure {
        forced = bound(forced, 0, COUNT_MAX);
        MemoryKV kv = MemoryKV.wrap(word);
        MemoryKV changed = withCount(kv, forced);

        assertEq(lengthOf(changed), forced, "count forced");
        for (uint256 slot = 0; slot < LibMemoryKV.LIST_COUNT; slot++) {
            assertEq(headOf(changed, slot), headOf(kv, slot), string.concat("head of slot ", vm.toString(slot)));
        }
        uint256 underTheCount = (uint256(1) << LibMemoryKV.COUNT_BIT_OFFSET) - 1;
        assertEq(MemoryKV.unwrap(changed) & underTheCount, word & underTheCount, "every bit under the count kept");
    }
}
