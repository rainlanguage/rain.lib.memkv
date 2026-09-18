// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";

import {LibPointer, Pointer} from "rain-solmem-0.1.28/src/lib/LibPointer.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {dirtyFreeMemory} from "test/lib/LibDirtyMemory.sol";
import {
    LIST_COUNT,
    POINTER_MAX,
    NODE_BYTES,
    COUNT_MAX,
    collidingPairDifferingInBit,
    slotOf,
    withCount,
    lengthOf,
    headOf,
    setFreePointer,
    raiseFreePointerTo,
    craftNode,
    handleWith,
    assertTextStates,
    assertValue,
    countPair
} from "test/lib/LibMemoryKVTestHelpers.sol";

/// @title LibMemoryKVTestHelpersTest
/// The promises the test helpers make and other tests rest on.
contract LibMemoryKVTestHelpersTest is Test {
    using LibMemoryKV for MemoryKV;

    function freePointer() internal pure returns (uint256) {
        return Pointer.unwrap(LibPointer.allocatedMemoryPointer());
    }

    function wordAt(uint256 pointer) internal pure returns (bytes32) {
        return LibPointer.unsafeReadWord(Pointer.wrap(pointer));
    }

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

    /// `assertTextStates` in a frame of its own so a test can expect its
    /// failure.
    function assertTextStatesExternal(string memory text, string memory phrase, string memory source) external pure {
        assertTextStates(text, phrase, source);
    }

    /// `assertValue` on a store built in this frame, which holds `stored` under
    /// `key` when `insert` is true and is empty otherwise, so a test can expect
    /// its failure without passing a handle across a call.
    function assertValueExternal(MemoryKVKey key, bool insert, uint256 stored, uint256 expected) external pure {
        MemoryKV kv = MEMORY_KV_EMPTY;
        if (insert) {
            kv = kv.set(key, MemoryKVVal.wrap(bytes32(stored)));
        }
        assertValue(kv, key, expected, "err");
    }

    /// The pair the search returns differs in the named bit and nothing else,
    /// the low key holds it clear and the high key set, and both share one
    /// list: the premise the one-bit key compare tests rest on.
    function testCollidingPairDiffersInExactlyTheBit(uint256 seed, uint8 bit) external pure {
        (MemoryKVKey low, MemoryKVKey high) = collidingPairDifferingInBit(seed, bit);
        uint256 lowWord = uint256(MemoryKVKey.unwrap(low));
        uint256 highWord = uint256(MemoryKVKey.unwrap(high));
        uint256 mask = uint256(1) << bit;

        assertEq(lowWord ^ highWord, mask, "differ in exactly the bit");
        assertEq(lowWord & mask, 0, "low key has the bit clear");
        assertEq(highWord & mask, mask, "high key has the bit set");
        assertEq(slotOf(MemoryKVKey.unwrap(low)), slotOf(MemoryKVKey.unwrap(high)), "one list");
    }

    /// `withCount` rewrites the count and nothing under it: from any word,
    /// every head pointer comes through unchanged, the count reads back as the
    /// one forced, and every bit below the top sixteen is the bit it was.
    function testWithCountKeepsEveryBitUnderTheCount(uint256 word, uint16 forced) external pure {
        MemoryKV kv = MemoryKV.wrap(word);
        MemoryKV changed = withCount(kv, forced);

        assertEq(lengthOf(changed), forced, "count forced");
        for (uint256 slot = 0; slot < LIST_COUNT; slot++) {
            assertEq(headOf(changed, slot), headOf(kv, slot), string.concat("head of slot ", vm.toString(slot)));
        }
        assertEq(
            MemoryKV.unwrap(changed) & type(uint240).max, word & type(uint240).max, "every bit under the count kept"
        );
    }

    /// A node crafted where an insert into an empty store would put its node,
    /// under a handle naming it with one pair's count, is exactly what that
    /// insert builds: the same handle, the same three words and the same
    /// allocation. The memory under each is dirtied first, so a word either
    /// one leaves unwritten reads as the sentinel.
    function testCraftNodeAndHandleWithBuildWhatAnInsertBuilds(MemoryKVKey key, MemoryKVVal value) external pure {
        bytes32 sentinel = keccak256(abi.encode(key, value));
        uint256 at = freePointer();

        dirtyFreeMemory(sentinel, 3);
        MemoryKV crafted = handleWith(slotOf(MemoryKVKey.unwrap(key)), craftNode(key, value, 0), 2);
        uint256 craftedEnd = freePointer();
        // Held on the stack: the insert below reuses the memory past the node.
        bytes32 craftedKey = wordAt(at);
        bytes32 craftedValue = wordAt(at + 0x20);
        bytes32 craftedNext = wordAt(at + 0x40);

        setFreePointer(at);
        dirtyFreeMemory(sentinel, 3);
        MemoryKV inserted = MEMORY_KV_EMPTY.set(key, value);
        uint256 insertedEnd = freePointer();

        assertEq(MemoryKV.unwrap(crafted), MemoryKV.unwrap(inserted), "the handle an insert builds");
        assertEq(craftedEnd, insertedEnd, "the allocation an insert makes");
        assertEq(craftedKey, wordAt(at), "the key word an insert writes");
        assertEq(craftedValue, wordAt(at + 0x20), "the value word an insert writes");
        assertEq(craftedNext, wordAt(at + 0x40), "the next word an insert writes");
    }

    /// The node's third word is the next pointer it was given, whatever it is,
    /// so a crafted list links where the test says.
    function testCraftNodeLinksToTheNextPointerItIsGiven(uint256 next) external pure {
        dirtyFreeMemory(bytes32(~next), 3);
        uint256 node = craftNode(MemoryKVKey.wrap(bytes32(0)), MemoryKVVal.wrap(bytes32(0)), next);
        uint256 end = freePointer();
        assertEq(uint256(wordAt(node + 0x40)), next, "next word");
        assertEq(end, node + NODE_BYTES, "one node allocated");
    }

    /// A node at `POINTER_MAX` still fits a head slot; one byte higher does not
    /// and reverts rather than handing back an address a handle would truncate.
    function testCraftNodeRevertsAboveTheWidestHeadPointer() external {
        assertEq(this.craftNodeAtExternal(POINTER_MAX), POINTER_MAX, "the widest head pointer");
        vm.expectRevert("crafted node pointer must fit a head slot");
        this.craftNodeAtExternal(POINTER_MAX + 1);
    }

    /// The handle heads the named list with the named pointer, every other list
    /// is empty, and the count is the one given.
    function testHandleWithHeadsOnlyTheNamedList(uint256 slot, uint16 head, uint16 words) external pure {
        slot = bound(slot, 0, LIST_COUNT - 1);
        MemoryKV kv = handleWith(slot, head, words);

        for (uint256 other = 0; other < LIST_COUNT; other++) {
            assertEq(headOf(kv, other), other == slot ? head : 0, string.concat("head of slot ", vm.toString(other)));
        }
        assertEq(lengthOf(kv), words, "count");
    }

    /// Each field one past what its place in the handle holds reverts, while
    /// the other two stay at their widest valid value.
    function testHandleWithRejectsAFieldThatDoesNotFit() external {
        MemoryKV widest = this.handleWithExternal(LIST_COUNT - 1, POINTER_MAX, COUNT_MAX);
        assertEq(headOf(widest, LIST_COUNT - 1), POINTER_MAX, "the widest head");
        assertEq(lengthOf(widest), COUNT_MAX, "the widest count");

        vm.expectRevert("handle field out of range");
        this.handleWithExternal(LIST_COUNT, POINTER_MAX, COUNT_MAX);
        vm.expectRevert("handle field out of range");
        this.handleWithExternal(LIST_COUNT - 1, POINTER_MAX + 1, COUNT_MAX);
        vm.expectRevert("handle field out of range");
        this.handleWithExternal(LIST_COUNT - 1, POINTER_MAX, COUNT_MAX + 1);
    }

    /// A free memory pointer below the floor is raised to exactly the floor.
    function testRaiseFreePointerToLiftsAPointerBelowTheFloor(uint16 gap) external pure {
        uint256 floor = freePointer() + uint256(gap) + 1;
        raiseFreePointerTo(floor);
        assertEq(freePointer(), floor, "raised to the floor");
    }

    /// A free memory pointer at or above the floor stays where it is.
    function testRaiseFreePointerToLeavesAPointerAtOrAboveTheFloor(uint256 floor) external pure {
        uint256 before = freePointer();
        floor = bound(floor, 0, before);
        raiseFreePointerTo(floor);
        assertEq(freePointer(), before, "left where it was");
    }

    /// A phrase the text holds verbatim passes.
    function testAssertTextStatesPassesOnAPhraseTheTextHolds() external pure {
        assertTextStates("the fixture text states ~120 gas here", "~120 gas", "text");
    }

    /// A phrase the text does not hold verbatim fails, naming the source and
    /// the phrase, even when the text holds a longer or shorter figure around
    /// the same digits.
    function testAssertTextStatesFailsOnAPhraseTheTextDoesNotHold() external {
        vm.expectRevert(bytes("text does not state \"~12 gas\""));
        this.assertTextStatesExternal("the fixture text states ~120 gas here", "~12 gas", "text");
        vm.expectRevert(bytes("text does not state \"~1200 gas\""));
        this.assertTextStatesExternal("the fixture text states ~120 gas here", "~1200 gas", "text");
    }

    /// A key the store holds with exactly the expected value passes.
    function testAssertValuePassesOnTheValueTheStoreHolds(MemoryKVKey key, uint256 value) external view {
        this.assertValueExternal(key, true, value, value);
    }

    /// A key the store does not hold fails on existence, even when the
    /// expected value is the zero a miss reads as.
    function testAssertValueFailsOnAKeyTheStoreDoesNotHold(MemoryKVKey key) external {
        vm.expectRevert(bytes("err exists: 0 != 1"));
        this.assertValueExternal(key, false, 0, 0);
    }

    /// A key the store holds with another value fails on the value.
    function testAssertValueFailsOnAnotherValue(MemoryKVKey key) external {
        vm.expectRevert(bytes("err value: 1 != 2"));
        this.assertValueExternal(key, true, 1, 2);
    }

    /// Only a key word at an even index followed by the value word counts: a
    /// key with another value does not, and neither does a key word in a value
    /// position followed by the value, nor a value word in a key position
    /// followed by the value.
    function testCountPairCountsOnlyKeyThenValueAtAPairBoundary(bytes32 key, bytes32 value, bytes32 other)
        external
        pure
    {
        vm.assume(key != value && key != other && value != other);
        bytes32[] memory array = new bytes32[](8);
        array[0] = key;
        array[1] = value;
        array[2] = key;
        array[3] = other;
        array[4] = other;
        array[5] = key;
        array[6] = value;
        array[7] = value;

        assertEq(countPair(array, key, value), 1, "key then value");
        assertEq(countPair(array, key, other), 1, "key then other");
        assertEq(countPair(array, value, value), 1, "value then value");
        assertEq(countPair(array, other, value), 0, "no other then value");
    }

    /// Exactly `words` words from the free memory pointer up read as the
    /// sentinel afterwards, the word after them keeps what it held, and the
    /// pointer does not move.
    function testDirtyFreeMemoryFillsExactlyTheWordsAndLeavesThePointer(bytes32 sentinel, uint8 words) external pure {
        uint256 start = freePointer();
        uint256 past = start + uint256(words) * 0x20;
        LibPointer.unsafeWriteWord(Pointer.wrap(past), ~sentinel);

        dirtyFreeMemory(sentinel, words);

        // Read before asserting: an assert message allocates at the pointer.
        uint256 end = freePointer();
        uint256 sentinelWords = 0;
        while (sentinelWords < words && wordAt(start + sentinelWords * 0x20) == sentinel) {
            sentinelWords++;
        }
        bytes32 pastWord = wordAt(past);

        assertEq(end, start, "pointer not moved");
        assertEq(sentinelWords, words, "every word dirtied");
        assertEq(pastWord, ~sentinel, "the word after them");
    }
}
