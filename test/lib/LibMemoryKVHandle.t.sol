// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";

import {LibPointer, Pointer} from "rain-solmem-0.1.28/src/lib/LibPointer.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {dirtyFreeMemory, setFreePointer} from "test/lib/LibFreeMemory.sol";
import {
    COUNT_MAX,
    occupancyBitOf,
    metaOf,
    lengthOf,
    maskOf,
    headOf,
    occupiedSlots,
    craftHeader,
    writeList,
    craftNode,
    handleWith
} from "test/lib/LibMemoryKVHandle.sol";
import {keyForSlot, collidingKey, slotOf} from "test/lib/LibMemoryKVKeys.sol";

/// @title LibMemoryKVHandleTest
/// The layout readers read what `set` writes, and the crafting functions write
/// what `set` writes.
contract LibMemoryKVHandleTest is Test {
    using LibMemoryKV for MemoryKV;

    /// The words in a header.
    uint256 internal constant HEADER_WORDS = LibMemoryKV.HEADER_BYTES / 0x20;

    /// The words in a header and one node, what the first insert allocates.
    uint256 internal constant FIRST_INSERT_WORDS = (LibMemoryKV.HEADER_BYTES + LibMemoryKV.NODE_BYTES) / 0x20;

    function freePointer() internal pure returns (uint256) {
        return Pointer.unwrap(LibPointer.allocatedMemoryPointer());
    }

    function wordAt(uint256 pointer) internal pure returns (bytes32) {
        return LibPointer.unsafeReadWord(Pointer.wrap(pointer));
    }

    /// `handleWith` in a frame of its own so a test can expect its revert. It
    /// returns what the store reads, not the handle, which MUST NOT leave the
    /// frame.
    function handleWithExternal(uint256 slot, uint256 head, uint256 words)
        external
        pure
        returns (uint256 readHead, uint256 readLength)
    {
        MemoryKV kv = handleWith(slot, head, words);
        return (headOf(kv, slot), lengthOf(kv));
    }

    /// The empty store has no header, so every reader answers `0`, even though
    /// the memory a header at address `0` would span holds non-zero words.
    function testReadersReadNothingFromTheEmptyStore(bytes32 sentinel) external pure {
        vm.assume(sentinel != 0);
        assembly ("memory-safe") {
            mstore(0, sentinel)
            mstore(0x20, sentinel)
        }
        uint256 start = freePointer();
        dirtyFreeMemory(sentinel, HEADER_WORDS);
        setFreePointer(start + LibMemoryKV.HEADER_BYTES);

        // Read before asserting: an assert message can use scratch space.
        uint256 meta = metaOf(MEMORY_KV_EMPTY);
        uint256 length = lengthOf(MEMORY_KV_EMPTY);
        uint256 mask = maskOf(MEMORY_KV_EMPTY);
        uint256 occupied = occupiedSlots(MEMORY_KV_EMPTY);
        bytes32 wordAtHead0 = wordAt(0);
        bytes32 wordAtMeta = wordAt(LibMemoryKV.META_OFFSET);

        assertEq(wordAtHead0, sentinel, "the word a head 0 read at address 0 would see");
        assertEq(wordAtMeta, sentinel, "the word a meta read at address 0 would see");
        assertEq(meta, 0, "meta");
        assertEq(length, 0, "length");
        assertEq(mask, 0, "mask");
        assertEq(occupied, 0, "occupied lists");
    }

    /// After three inserts, two into one list and one into another, each
    /// reader reports what the inserts wrote: each list's newest node as its
    /// head, no head for any other list, three pairs in the count, and the two
    /// lists' occupancy bits in the mask.
    function testReadersReadWhatInsertsWrite(bytes32 seed, uint256 slotA, uint256 slotB) external pure {
        slotA = bound(slotA, 0, LibMemoryKV.LIST_COUNT - 1);
        slotB = bound(slotB, 0, LibMemoryKV.LIST_COUNT - 2);
        if (slotB >= slotA) {
            slotB++;
        }
        MemoryKVKey keyA = keyForSlot(seed, slotA);
        MemoryKVKey keyB = keyForSlot(seed, slotB);
        MemoryKVKey keyA2 = collidingKey(keyA);

        MemoryKV kv = MEMORY_KV_EMPTY.set(keyA, MemoryKVVal.wrap(0));
        kv = kv.set(keyB, MemoryKVVal.wrap(0));
        uint256 nodeB = freePointer() - LibMemoryKV.NODE_BYTES;
        kv = kv.set(keyA2, MemoryKVVal.wrap(0));
        uint256 nodeA2 = freePointer() - LibMemoryKV.NODE_BYTES;

        uint256 words = 6;
        uint256 mask = occupancyBitOf(slotA) | occupancyBitOf(slotB);
        assertEq(headOf(kv, slotA), nodeA2, "list A's head is its newest node");
        assertEq(headOf(kv, keyA), nodeA2, "the head of key A's list");
        assertEq(headOf(kv, slotB), nodeB, "list B's head is its node");
        for (uint256 slot = 0; slot < LibMemoryKV.LIST_COUNT; slot++) {
            if (slot != slotA && slot != slotB) {
                assertEq(headOf(kv, slot), 0, string.concat("head of empty list ", vm.toString(slot)));
            }
        }
        assertEq(occupiedSlots(kv), 2, "occupied lists");
        assertEq(lengthOf(kv), words, "two words per pair");
        assertEq(maskOf(kv), mask, "one occupancy bit per occupied list");
        assertEq(metaOf(kv), (words << LibMemoryKV.COUNT_BIT_OFFSET) | mask, "meta");
    }

    /// Every list has an occupancy bit of its own inside the mask.
    function testOccupancyBitsAreDistinctAndInsideTheMask() external pure {
        uint256 seen = 0;
        for (uint256 slot = 0; slot < LibMemoryKV.LIST_COUNT; slot++) {
            uint256 bit = occupancyBitOf(slot);
            assertEq(bit & (bit - 1), 0, "one bit");
            assertEq(bit & LibMemoryKV.OCCUPANCY_MASK, bit, "inside the mask");
            assertEq(seen & bit, 0, "a bit of its own");
            seen |= bit;
        }
        assertEq(seen, LibMemoryKV.OCCUPANCY_MASK, "the lists' bits make up the mask");
    }

    /// Over dirty memory, the crafted header sits at the free memory pointer,
    /// allocates exactly one header, reads as zero in every word, and leaves
    /// the word after it as it was.
    function testCraftHeaderAllocatesAZeroedHeaderOverDirtyMemory(bytes32 sentinel) external pure {
        vm.assume(sentinel != 0);
        uint256 at = freePointer();
        dirtyFreeMemory(sentinel, HEADER_WORDS + 1);

        MemoryKV kv = craftHeader();

        // Read before asserting: an assert message allocates at the pointer.
        uint256 end = freePointer();
        uint256 zeroWords = 0;
        while (zeroWords < HEADER_WORDS && wordAt(at + zeroWords * 0x20) == 0) {
            zeroWords++;
        }
        bytes32 pastWord = wordAt(at + LibMemoryKV.HEADER_BYTES);

        assertEq(MemoryKV.unwrap(kv), at, "at the free memory pointer");
        assertEq(end, at + LibMemoryKV.HEADER_BYTES, "one header allocated");
        assertEq(zeroWords, HEADER_WORDS, "every word zero");
        assertEq(pastWord, sentinel, "the word after the header");
    }

    /// A header crafted where an insert into the empty store puts its header,
    /// then a node crafted after it and written as the key's list with one
    /// pair's count, is exactly what that insert builds: the same handle, the
    /// same allocation, and the same header and node words. The memory under
    /// each is dirtied with the same sentinel first.
    function testCraftingBuildsWhatAnInsertBuilds(MemoryKVKey key, MemoryKVVal value) external pure {
        bytes32 sentinel = keccak256(abi.encode(key, value));
        // Allocated below `at`, so the insert does not reuse it.
        bytes32[] memory crafted = new bytes32[](FIRST_INSERT_WORDS);
        uint256 at = freePointer();

        dirtyFreeMemory(sentinel, FIRST_INSERT_WORDS);
        MemoryKV craftedKv = craftHeader();
        uint256 node = craftNode(key, value, 0);
        writeList(craftedKv, slotOf(MemoryKVKey.unwrap(key)), node, 2);
        uint256 craftedEnd = freePointer();
        for (uint256 i = 0; i < FIRST_INSERT_WORDS; i++) {
            crafted[i] = wordAt(at + i * 0x20);
        }

        setFreePointer(at);
        dirtyFreeMemory(sentinel, FIRST_INSERT_WORDS);
        MemoryKV inserted = MEMORY_KV_EMPTY.set(key, value);
        uint256 insertedEnd = freePointer();

        assertEq(MemoryKV.unwrap(craftedKv), MemoryKV.unwrap(inserted), "the handle an insert returns");
        assertEq(craftedEnd, insertedEnd, "the allocation an insert makes");
        for (uint256 i = 0; i < FIRST_INSERT_WORDS; i++) {
            assertEq(crafted[i], wordAt(at + i * 0x20), string.concat("word ", vm.toString(i), " an insert writes"));
        }
    }

    /// The node's third word is the next pointer it was given, whatever it is,
    /// so a crafted list links where the test says.
    function testCraftNodeLinksToTheNextPointerItIsGiven(uint256 next) external pure {
        dirtyFreeMemory(bytes32(~next), 3);
        uint256 node = craftNode(MemoryKVKey.wrap(bytes32(0)), MemoryKVVal.wrap(bytes32(0)), next);
        uint256 end = freePointer();
        assertEq(uint256(wordAt(node + 0x40)), next, "next word");
        assertEq(end, node + LibMemoryKV.NODE_BYTES, "one node allocated");
    }

    /// The store heads the named list with the named head, every other list
    /// is empty, the count is the one given, and only the named list's
    /// occupancy bit is set.
    function testHandleWithHeadsOnlyTheNamedList(uint256 slot, uint256 head, uint256 words) external pure {
        slot = bound(slot, 0, LibMemoryKV.LIST_COUNT - 1);
        words = bound(words, 0, COUNT_MAX);
        MemoryKV kv = handleWith(slot, head, words);

        for (uint256 other = 0; other < LibMemoryKV.LIST_COUNT; other++) {
            assertEq(headOf(kv, other), other == slot ? head : 0, string.concat("head of list ", vm.toString(other)));
        }
        assertEq(lengthOf(kv), words, "count");
        assertEq(maskOf(kv), occupancyBitOf(slot), "occupancy");
    }

    /// Writing a second list keeps the first list's head and occupancy bit and
    /// replaces the count.
    function testWriteListKeepsEveryOtherList(
        uint256 slotA,
        uint256 slotB,
        uint256 headA,
        uint256 headB,
        uint256 wordsA,
        uint256 wordsB
    ) external pure {
        slotA = bound(slotA, 0, LibMemoryKV.LIST_COUNT - 1);
        slotB = bound(slotB, 0, LibMemoryKV.LIST_COUNT - 2);
        if (slotB >= slotA) {
            slotB++;
        }
        wordsA = bound(wordsA, 0, COUNT_MAX);
        wordsB = bound(wordsB, 0, COUNT_MAX);
        MemoryKV kv = handleWith(slotA, headA, wordsA);

        writeList(kv, slotB, headB, wordsB);

        for (uint256 other = 0; other < LibMemoryKV.LIST_COUNT; other++) {
            uint256 expected = other == slotA ? headA : other == slotB ? headB : 0;
            assertEq(headOf(kv, other), expected, string.concat("head of list ", vm.toString(other)));
        }
        assertEq(lengthOf(kv), wordsB, "count replaced");
        assertEq(maskOf(kv), occupancyBitOf(slotA) | occupancyBitOf(slotB), "occupancy");
    }

    /// A list past the last one, or a count above `COUNT_MAX`, reverts, while
    /// the widest valid values pass through unchanged.
    function testWriteListRejectsAFieldThatDoesNotFit() external {
        uint256 widestSlot = LibMemoryKV.LIST_COUNT - 1;
        (uint256 readHead, uint256 readLength) = this.handleWithExternal(widestSlot, type(uint256).max, COUNT_MAX);
        assertEq(readHead, type(uint256).max, "the widest head");
        assertEq(readLength, COUNT_MAX, "the widest count");

        vm.expectRevert("list field out of range");
        this.handleWithExternal(LibMemoryKV.LIST_COUNT, 0, 0);
        vm.expectRevert("list field out of range");
        this.handleWithExternal(widestSlot, 0, COUNT_MAX + 1);
    }
}
