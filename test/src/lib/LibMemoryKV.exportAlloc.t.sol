// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";

import {LibPointer, Pointer} from "rain-solmem-0.1.28/src/lib/LibPointer.sol";
import {LibBytes32Array} from "rain-solmem-0.1.28/src/lib/LibBytes32Array.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {dirtyFreeMemory, setFreePointer} from "test/lib/LibFreeMemory.sol";
import {slotOf, keyForSlot} from "test/lib/LibMemoryKVKeys.sol";
import {occupiedSlots, lengthOf} from "test/lib/LibMemoryKVHandle.sol";
import {countPair} from "test/lib/LibMemoryKVExport.sol";

/// @title LibMemoryKVExportAllocTest
/// The export's ARRAY: where it is allocated, how big it is, and that every
/// word of it is a key or a value that was actually inserted.
///
/// An export of N DISTINCT keys is 2N words long and occupies exactly
/// 0x20 + 2N * 0x20 bytes of fresh memory, with N counted by the test from the
/// keys it inserts rather than read back out of the store.
contract LibMemoryKVExportAllocTest is Test {
    using LibMemoryKV for MemoryKV;

    /// Number of distinct keys in a pairwise `kvs`, counted by the test rather
    /// than by the thing under test.
    function distinctKeys(bytes32[] memory kvs) internal pure returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < kvs.length; i += 2) {
            bool seen = false;
            for (uint256 j = 0; j < i; j += 2) {
                if (kvs[j] == kvs[i]) {
                    seen = true;
                }
            }
            if (!seen) {
                count += 1;
            }
        }
        return count;
    }

    /// An empty store exports an empty array and allocates the length word and
    /// nothing else: exactly 0x20 bytes. The zero length is WRITTEN: the length
    /// word is dirtied first and the length reads back as zero.
    function testExportEmptyAllocatesOnlyTheLengthWord() external pure {
        dirtyFreeMemory(bytes32(type(uint256).max), 1);

        Pointer before = LibPointer.allocatedMemoryPointer();
        bytes32[] memory array = MEMORY_KV_EMPTY.toBytes32Array();
        Pointer afterPointer = LibPointer.allocatedMemoryPointer();

        assertEq(array.length, 0);
        assertEq(Pointer.unwrap(afterPointer) - Pointer.unwrap(before), 0x20);
    }

    /// The array is 2 words per DISTINCT key, counted by the test. Repeat
    /// upserts of a key are updates, not inserts, so they add nothing.
    function testExportLengthIsTwoWordsPerDistinctKey(bytes32[] memory kvs) external pure {
        vm.assume(kvs.length < 40);
        vm.assume(kvs.length % 2 == 0);

        MemoryKV kv = MEMORY_KV_EMPTY;
        for (uint256 i = 0; i < kvs.length; i += 2) {
            kv = kv.set(MemoryKVKey.wrap(kvs[i]), MemoryKVVal.wrap(kvs[i + 1]));
        }

        uint256 expectedWords = distinctKeys(kvs) * 2;

        // The word count the store carries, and the array it exports, are both
        // exactly that.
        assertEq(lengthOf(kv), expectedWords, "kv word count");
        assertEq(kv.toBytes32Array().length, expectedWords, "array length");
    }

    /// The array is allocated AT the free memory pointer and the allocation is
    /// exactly the length word plus two words per distinct key.
    function testExportAllocatesExactlyLengthWordPlusTwoWordsPerPair(bytes32[] memory kvs) external pure {
        vm.assume(kvs.length < 40);
        vm.assume(kvs.length % 2 == 0);

        MemoryKV kv = MEMORY_KV_EMPTY;
        for (uint256 i = 0; i < kvs.length; i += 2) {
            kv = kv.set(MemoryKVKey.wrap(kvs[i]), MemoryKVVal.wrap(kvs[i + 1]));
        }

        uint256 expectedWords = distinctKeys(kvs) * 2;

        Pointer before = LibPointer.allocatedMemoryPointer();
        bytes32[] memory array = kv.toBytes32Array();
        Pointer afterPointer = LibPointer.allocatedMemoryPointer();

        uint256 arrayPointer = Pointer.unwrap(LibBytes32Array.startPointer(array));

        assertEq(arrayPointer, Pointer.unwrap(before), "array is at the free memory pointer");
        assertEq(Pointer.unwrap(afterPointer) - Pointer.unwrap(before), 0x20 + expectedWords * 0x20, "allocation size");
    }

    /// Exporting must not touch anything already allocated. A live array sat
    /// immediately below the export keeps every word it had.
    function testExportDoesNotClobberLiveMemory(bytes32 fill) external pure {
        MemoryKV kv = MEMORY_KV_EMPTY;
        for (uint256 i = 1; i <= 6; i++) {
            kv = kv.set(MemoryKVKey.wrap(bytes32(i)), MemoryKVVal.wrap(bytes32(i * 1000)));
        }

        bytes32[] memory live = new bytes32[](8);
        for (uint256 i = 0; i < live.length; i++) {
            live[i] = fill;
        }

        bytes32[] memory array = kv.toBytes32Array();
        assertEq(array.length, 12);

        for (uint256 i = 0; i < live.length; i++) {
            assertEq(live[i], fill, "live memory survived the export");
        }
    }

    /// The array is allocated AT the free memory pointer wherever it points,
    /// including 1 to 31 bytes past a word boundary, and the live bytes below
    /// it keep what they held. The live allocation is one word and `tail`
    /// bytes, all copied from `live`, so the free memory pointer ends inside
    /// the word after it.
    function testExportAllocatesAtAnUnalignedFreePointer(bytes32 key, bytes32 value, bytes32 live, uint256 tail)
        external
        pure
    {
        tail = bound(tail, 1, 31);
        MemoryKV kv = MEMORY_KV_EMPTY.set(MemoryKVKey.wrap(key), MemoryKVVal.wrap(value));

        Pointer start = LibPointer.allocatedMemoryPointer();
        Pointer tailWord = LibPointer.unsafeAddWord(start);
        LibPointer.unsafeWriteWord(start, live);
        LibPointer.unsafeWriteWord(tailWord, live);
        Pointer free = LibPointer.unsafeAddBytes(tailWord, tail);
        setFreePointer(Pointer.unwrap(free));

        bytes32[] memory array = kv.toBytes32Array();

        // The first `tail` bytes of the tail word are live; the rest of it is
        // the array's.
        bytes32 liveTailMask = ~(bytes32(type(uint256).max) >> (tail * 8));
        assertEq(
            Pointer.unwrap(LibBytes32Array.startPointer(array)),
            Pointer.unwrap(free),
            "the export is at the unaligned free memory pointer"
        );
        assertEq(LibPointer.unsafeReadWord(start), live, "the live word is untouched");
        assertEq(
            LibPointer.unsafeReadWord(tailWord) & liveTailMask, live & liveTailMask, "the live tail bytes are untouched"
        );
        assertEq(array.length, 2, "one pair");
        assertEq(array[0], key, "key");
        assertEq(array[1], value, "value");
    }

    /// `abi.encodePacked` need not leave the free memory pointer at a word
    /// boundary. An export allocated after a packed `bytes` leaves every one
    /// of its bytes and its length alone.
    function testExportAfterEncodePackedLeavesTheBytesAlone(bytes32 key, bytes32 value) external pure {
        MemoryKV kv = MEMORY_KV_EMPTY.set(MemoryKVKey.wrap(key), MemoryKVVal.wrap(value));
        bytes memory packed = abi.encodePacked(uint8(0xAA), uint8(0xBB), uint8(0xCC));
        bytes32 before = keccak256(packed);

        bytes32[] memory array = kv.toBytes32Array();

        assertEq(keccak256(packed), before, "the packed bytes survive the export");
        assertEq(packed.length, 3, "the packed length survives the export");
        assertEq(array.length, 2, "one pair");
        assertEq(array[0], key, "key");
        assertEq(array[1], value, "value");
    }

    /// Every word `toBytes32Array` allocates is written: with the free memory
    /// dirtied first, the sentinel appears nowhere in the exported array.
    function testExportWritesEveryAllocatedWord(bytes32 seed) external pure {
        bytes32 sentinel = keccak256(abi.encode(seed, "sentinel"));

        MemoryKV kv = MEMORY_KV_EMPTY;
        for (uint256 i = 1; i <= 10; i++) {
            kv = kv.set(MemoryKVKey.wrap(keccak256(abi.encode(seed, i))), MemoryKVVal.wrap(bytes32(i)));
        }

        dirtyFreeMemory(sentinel, 64);

        bytes32[] memory array = kv.toBytes32Array();
        assertEq(array.length, 20);
        for (uint256 i = 0; i < array.length; i++) {
            assertTrue(array[i] != sentinel, "exported a word that was never written");
        }
    }

    /// Each node contributes exactly two words, key first then value, and the
    /// pair is adjacent. One key/value pair pins the order without any
    /// ambiguity about which pair is which.
    function testExportIsKeyThenValue() external pure {
        bytes32 key = bytes32(uint256(0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA));
        bytes32 value = bytes32(uint256(0xBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB));

        MemoryKV kv = MEMORY_KV_EMPTY.set(MemoryKVKey.wrap(key), MemoryKVVal.wrap(value));
        bytes32[] memory array = kv.toBytes32Array();

        assertEq(array.length, 2);
        assertEq(array[0], key, "key first");
        assertEq(array[1], value, "value second");
    }

    /// A value of `0` is a value: `get` documents that any key MAY be set to
    /// zero and reports existence separately from it. The export writes that
    /// zero into the pair's second word: the free memory is dirtied first, and
    /// the assertion is on the zero itself.
    function testExportCopiesZeroValue(bytes32 seed) external pure {
        bytes32 sentinel = keccak256(abi.encode(seed, "sentinel"));
        bytes32 zeroValued = keccak256(abi.encode(seed, "zero valued"));

        MemoryKV kv = MEMORY_KV_EMPTY.set(MemoryKVKey.wrap(zeroValued), MemoryKVVal.wrap(bytes32(0)));
        for (uint256 i = 1; i <= 4; i++) {
            kv = kv.set(MemoryKVKey.wrap(keccak256(abi.encode(seed, i))), MemoryKVVal.wrap(bytes32(i)));
        }

        dirtyFreeMemory(sentinel, 64);

        bytes32[] memory array = kv.toBytes32Array();
        assertEq(array.length, 10);

        assertEq(countPair(array, zeroValued, bytes32(0)), 1, "the zero value copied, exactly once");
    }

    /// A key of `0` is a key: nothing marks it as absent and `get` finds it by
    /// equality like any other. The export must copy it into the pair's first
    /// word and keep walking past it. The zero key is inserted LAST onto a list
    /// four other keys already occupy, so `set`'s prepend puts it at the head
    /// and the walk reaches the four behind it through its next pointer.
    function testExportCopiesZeroKey(bytes32 seed) external pure {
        bytes32 sentinel = keccak256(abi.encode(seed, "sentinel"));
        bytes32 zeroKeyValue = keccak256(abi.encode(seed, "zero key value"));
        uint256 slot = slotOf(bytes32(0));

        MemoryKV kv = MEMORY_KV_EMPTY;
        bytes32[] memory behind = new bytes32[](4);
        for (uint256 i = 0; i < behind.length; i++) {
            behind[i] = MemoryKVKey.unwrap(keyForSlot(keccak256(abi.encode(seed, i)), slot));
            kv = kv.set(MemoryKVKey.wrap(behind[i]), MemoryKVVal.wrap(bytes32(i + 1)));
        }
        kv = kv.set(MemoryKVKey.wrap(bytes32(0)), MemoryKVVal.wrap(zeroKeyValue));

        dirtyFreeMemory(sentinel, 64);

        bytes32[] memory array = kv.toBytes32Array();
        assertEq(array.length, 10);

        assertEq(countPair(array, bytes32(0), zeroKeyValue), 1, "the zero key exported exactly once");

        for (uint256 i = 0; i < behind.length; i++) {
            assertEq(countPair(array, behind[i], bytes32(i + 1)), 1, "the walk did not stop at the zero key");
        }
    }

    /// The pair writes stay inside the array. The word at
    /// `array + 0x20 + length * 0x20` is the first word of the next
    /// allocation, which the `memory-safe` annotation promises is untouched,
    /// so it must still read as the sentinel the test put there.
    function testExportWritesNothingPastTheArray(bytes32 seed) external pure {
        bytes32 sentinel = keccak256(abi.encode(seed, "sentinel"));

        MemoryKV kv = MEMORY_KV_EMPTY;
        for (uint256 i = 1; i <= 6; i++) {
            kv = kv.set(MemoryKVKey.wrap(keccak256(abi.encode(seed, i))), MemoryKVVal.wrap(bytes32(i)));
        }

        dirtyFreeMemory(sentinel, 64);

        bytes32[] memory array = kv.toBytes32Array();
        bytes32 past = LibPointer.unsafeReadWord(LibBytes32Array.endPointer(array));

        assertEq(array.length, 12);
        assertEq(past, sentinel, "the word past the array end was written");
    }

    /// A single internal list holding several nodes is walked to its end and
    /// every pair on it lands in the array, adjacent and in one piece. This is
    /// the multi-step walk: the chain, not the occupancy mask.
    function testExportWalksOneListToTheEnd(bytes32 seed, uint256 slot) external pure {
        slot = bound(slot, 0, LibMemoryKV.LIST_COUNT - 1);

        bytes32[] memory keys = new bytes32[](5);
        MemoryKV kv = MEMORY_KV_EMPTY;
        for (uint256 i = 0; i < keys.length; i++) {
            keys[i] = MemoryKVKey.unwrap(keyForSlot(keccak256(abi.encode(seed, i)), slot));
            kv = kv.set(MemoryKVKey.wrap(keys[i]), MemoryKVVal.wrap(bytes32(i + 1)));
        }

        // Exactly one list of the store is headed: everything is on one list.
        assertEq(occupiedSlots(kv), 1, "one list");

        bytes32[] memory array = kv.toBytes32Array();
        assertEq(array.length, 10);

        for (uint256 i = 0; i < keys.length; i++) {
            assertEq(countPair(array, keys[i], bytes32(i + 1)), 1, "every node on the list copied exactly once");
        }
    }

    /// Two populated lists of the same length both land in the array: the
    /// second walk appends after the first rather than writing over it, and
    /// every pair is exported exactly once.
    function testExportAppendsAcrossLists(bytes32 seed) external pure {
        bytes32[] memory keys = new bytes32[](4);
        MemoryKV kv = MEMORY_KV_EMPTY;
        for (uint256 i = 0; i < keys.length; i++) {
            keys[i] =
                MemoryKVKey.unwrap(keyForSlot(keccak256(abi.encode(seed, i)), i < 2 ? 0 : LibMemoryKV.LIST_COUNT - 1));
            kv = kv.set(MemoryKVKey.wrap(keys[i]), MemoryKVVal.wrap(bytes32(i + 1)));
        }

        bytes32[] memory array = kv.toBytes32Array();
        assertEq(array.length, 8);

        for (uint256 i = 0; i < keys.length; i++) {
            assertEq(countPair(array, keys[i], bytes32(i + 1)), 1, "every pair from both lists, exactly once");
        }
    }

    /// Every one of the `LibMemoryKV.LIST_COUNT` internal lists is reachable by
    /// the export. With one key in each list, the array holds each list's pair
    /// exactly once, key and value together, and nothing else.
    function testExportReachesEverySlot(bytes32 seed) external pure {
        bytes32[] memory keys = new bytes32[](LibMemoryKV.LIST_COUNT);
        MemoryKV kv = MEMORY_KV_EMPTY;
        for (uint256 slot = 0; slot < LibMemoryKV.LIST_COUNT; slot++) {
            keys[slot] = MemoryKVKey.unwrap(keyForSlot(keccak256(abi.encode(seed, slot)), slot));
            kv = kv.set(MemoryKVKey.wrap(keys[slot]), MemoryKVVal.wrap(bytes32(slot + 1)));
        }

        bytes32[] memory array = kv.toBytes32Array();
        assertEq(array.length, LibMemoryKV.LIST_COUNT * 2, "two words per slot");

        for (uint256 slot = 0; slot < LibMemoryKV.LIST_COUNT; slot++) {
            assertEq(countPair(array, keys[slot], bytes32(slot + 1)), 1, "slot exported exactly once");
        }
    }

    /// The export is a READ of the store: afterwards every key is still
    /// gettable with its value, and a second export is identical to the first.
    function testExportLeavesTheStoreIntact(bytes32 seed) external pure {
        bytes32[] memory keys = new bytes32[](7);
        MemoryKV kv = MEMORY_KV_EMPTY;
        for (uint256 i = 0; i < keys.length; i++) {
            keys[i] = keccak256(abi.encode(seed, i));
            kv = kv.set(MemoryKVKey.wrap(keys[i]), MemoryKVVal.wrap(bytes32(i + 1)));
        }

        bytes32[] memory first = kv.toBytes32Array();

        for (uint256 i = 0; i < keys.length; i++) {
            (uint256 exists, MemoryKVVal value) = kv.get(MemoryKVKey.wrap(keys[i]));
            assertEq(exists, 1, "key survived the export");
            assertEq(MemoryKVVal.unwrap(value), bytes32(i + 1), "value survived the export");
        }

        bytes32[] memory second = kv.toBytes32Array();
        assertEq(first.length, second.length);
        for (uint256 i = 0; i < first.length; i++) {
            assertEq(first[i], second[i], "a second export is word for word the first");
        }
    }

    /// The array region is really allocated, not merely written: whatever is
    /// allocated NEXT sits past the end of the array, so once that allocation
    /// is written the array keeps its length and holds every inserted pair
    /// exactly once. The expected pairs come from the inserts, not from the
    /// array.
    function testExportedArraySurvivesLaterAllocation(bytes32 fill) external pure {
        MemoryKV kv = MEMORY_KV_EMPTY;
        for (uint256 i = 1; i <= 5; i++) {
            kv = kv.set(MemoryKVKey.wrap(bytes32(i)), MemoryKVVal.wrap(bytes32(i * 7)));
        }

        bytes32[] memory array = kv.toBytes32Array();
        assertEq(array.length, 10);

        bytes32[] memory later = new bytes32[](32);
        for (uint256 i = 0; i < later.length; i++) {
            later[i] = fill;
        }

        assertEq(array.length, 10, "array length survived");
        for (uint256 i = 1; i <= 5; i++) {
            assertEq(countPair(array, bytes32(i), bytes32(i * 7)), 1, "pair survived a later allocation");
        }
    }
}
