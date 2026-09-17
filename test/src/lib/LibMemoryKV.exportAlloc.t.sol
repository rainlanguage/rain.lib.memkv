// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibPointer, Pointer} from "rain-solmem-0.1.28/src/lib/LibPointer.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";

/// @title LibMemoryKVExportAllocTest
/// The export's ARRAY: where it is allocated, how big it is, and that every
/// word of it is a key or a value that was actually inserted.
///
/// The expectations here are derived from the documented contract rather than
/// from the header the implementation writes: the README says the store
/// exports "pairwise keys/values", and `MemoryKV` is documented as carrying
/// "the total word count of all inserts", so an export of N DISTINCT keys is
/// 2N words long and occupies exactly 0x20 + 2N * 0x20 bytes of fresh memory.
/// Counting N independently of the store is the point - reading it back out of
/// `array.length` would only restate whatever the implementation wrote.
contract LibMemoryKVExportAllocTest is Test {
    using LibMemoryKV for MemoryKV;

    /// Fill `words` words of memory from the free memory pointer up with a
    /// sentinel, WITHOUT allocating them. Anything an export subsequently
    /// hands back that still reads as the sentinel is memory the export
    /// claimed but never wrote.
    function dirtyFreeMemory(bytes32 sentinel, uint256 words) internal pure {
        assembly ("memory-safe") {
            let cursor := mload(0x40)
            for { let i := 0 } lt(i, words) { i := add(i, 1) } {
                mstore(cursor, sentinel)
                cursor := add(cursor, 0x20)
            }
        }
    }

    /// Rehash `key` until it lands in internal list `slot`. Mirrors the hash
    /// `get`/`set` use so a test can put several keys into ONE linked list and
    /// force the walk to take more than one step.
    function keyForSlot(bytes32 key, uint256 slot) internal pure returns (bytes32) {
        assembly ("memory-safe") {
            for {} 1 {} {
                mstore(0, key)
                if eq(mod(keccak256(0, 0x20), 0x0f), slot) { break }
                mstore(0, key)
                key := keccak256(0, 0x20)
            }
        }
        return key;
    }

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

    /// An empty store exports an empty array and allocates the length header
    /// and nothing else: exactly 0x20 bytes. The zero length is WRITTEN, not
    /// inherited from memory that happened to be zero, so the header word is
    /// dirtied first: an export that wrote no header would hand back the
    /// sentinel as the length.
    function testExportEmptyAllocatesOnlyTheHeader() external pure {
        dirtyFreeMemory(bytes32(type(uint256).max), 1);

        Pointer before = LibPointer.allocatedMemoryPointer();
        bytes32[] memory array = LibMemoryKV.toBytes32Array(MEMORY_KV_EMPTY);
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
        assertEq(MemoryKV.unwrap(kv) >> 0xf0, expectedWords, "kv word count");
        assertEq(LibMemoryKV.toBytes32Array(kv).length, expectedWords, "array length");
    }

    /// The array is allocated AT the free memory pointer and the allocation is
    /// exactly the header plus two words per distinct key. Both edges matter:
    /// one word short leaves the last value in unallocated memory, one word
    /// long wastes a word forever.
    function testExportAllocatesExactlyHeaderPlusTwoWordsPerPair(bytes32[] memory kvs) external pure {
        vm.assume(kvs.length < 40);
        vm.assume(kvs.length % 2 == 0);

        MemoryKV kv = MEMORY_KV_EMPTY;
        for (uint256 i = 0; i < kvs.length; i += 2) {
            kv = kv.set(MemoryKVKey.wrap(kvs[i]), MemoryKVVal.wrap(kvs[i + 1]));
        }

        uint256 expectedWords = distinctKeys(kvs) * 2;

        Pointer before = LibPointer.allocatedMemoryPointer();
        bytes32[] memory array = LibMemoryKV.toBytes32Array(kv);
        Pointer afterPointer = LibPointer.allocatedMemoryPointer();

        uint256 arrayPointer;
        assembly ("memory-safe") {
            arrayPointer := array
        }

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

    /// `toBytes32Array` justifies skipping a zero-fill with "we're about to
    /// write to it". Every word it allocates must therefore be written: dirty
    /// the free memory first and assert the sentinel never reappears inside
    /// the exported array.
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

    /// A single internal list holding several nodes is walked to its end and
    /// every pair on it lands in the array, adjacent and in one piece. This is
    /// the multi-step walk: the chain, not the bisect.
    function testExportWalksOneListToTheEnd(bytes32 seed, uint256 slot) external pure {
        slot = bound(slot, 0, 14);

        bytes32[] memory keys = new bytes32[](5);
        MemoryKV kv = MEMORY_KV_EMPTY;
        for (uint256 i = 0; i < keys.length; i++) {
            keys[i] = keyForSlot(keccak256(abi.encode(seed, i)), slot);
            kv = kv.set(MemoryKVKey.wrap(keys[i]), MemoryKVVal.wrap(bytes32(i + 1)));
        }

        // Exactly one slot of the kv is populated: everything is on one list.
        uint256 populated = 0;
        for (uint256 bitOffset = 0; bitOffset < 0xf0; bitOffset += 0x10) {
            if (((MemoryKV.unwrap(kv) >> bitOffset) & 0xFFFF) != 0) {
                populated += 1;
            }
        }
        assertEq(populated, 1, "one list");

        bytes32[] memory array = kv.toBytes32Array();
        assertEq(array.length, 10);

        for (uint256 i = 0; i < keys.length; i++) {
            bool found = false;
            for (uint256 j = 0; j < array.length; j += 2) {
                if (array[j] == keys[i]) {
                    assertEq(array[j + 1], bytes32(i + 1), "value beside its key");
                    found = true;
                }
            }
            assertTrue(found, "every node on the list was copied");
        }
    }

    /// Two populated lists both land in the array: the second walk appends
    /// after the first rather than writing over it. The two lists are the same
    /// length so a cursor that failed to carry over would drop or duplicate a
    /// pair rather than merely reorder them.
    function testExportAppendsAcrossLists(bytes32 seed) external pure {
        bytes32[] memory keys = new bytes32[](4);
        MemoryKV kv = MEMORY_KV_EMPTY;
        for (uint256 i = 0; i < keys.length; i++) {
            keys[i] = keyForSlot(keccak256(abi.encode(seed, i)), i < 2 ? 0 : 14);
            kv = kv.set(MemoryKVKey.wrap(keys[i]), MemoryKVVal.wrap(bytes32(i + 1)));
        }

        bytes32[] memory array = kv.toBytes32Array();
        assertEq(array.length, 8);

        uint256 matched = 0;
        for (uint256 i = 0; i < keys.length; i++) {
            for (uint256 j = 0; j < array.length; j += 2) {
                if (array[j] == keys[i] && array[j + 1] == bytes32(i + 1)) {
                    matched += 1;
                }
            }
        }
        assertEq(matched, keys.length, "every pair from both lists, exactly once");
    }

    /// Every one of the 15 internal lists is reachable by the export. One key
    /// per slot, each with a value that identifies its slot, so a mask or a
    /// branch that reads the wrong slot produces a WRONG VALUE rather than
    /// merely a short array.
    function testExportReachesEverySlot(bytes32 seed) external pure {
        bytes32[] memory keys = new bytes32[](15);
        MemoryKV kv = MEMORY_KV_EMPTY;
        for (uint256 slot = 0; slot < 15; slot++) {
            keys[slot] = keyForSlot(keccak256(abi.encode(seed, slot)), slot);
            kv = kv.set(MemoryKVKey.wrap(keys[slot]), MemoryKVVal.wrap(bytes32(slot + 1)));
        }

        bytes32[] memory array = kv.toBytes32Array();
        assertEq(array.length, 30, "two words per slot");

        for (uint256 slot = 0; slot < 15; slot++) {
            bool found = false;
            for (uint256 j = 0; j < array.length; j += 2) {
                if (array[j] == keys[slot]) {
                    assertEq(array[j + 1], bytes32(slot + 1), "slot's value");
                    found = true;
                }
            }
            assertTrue(found, "slot was exported");
        }
    }

    /// The export is a READ of the store. The NatSpec calls it a "one time
    /// export" whose array will not reflect later mutations, which only means
    /// anything if the store itself is still there afterwards: every key is
    /// still gettable with its value, and a second export is identical to the
    /// first. Only one pre-existing test notices an export that scribbles on
    /// the nodes it walks, and only as a side effect of exporting twice.
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
    /// allocated NEXT sits past the end of the array and the array keeps every
    /// word it was given.
    function testExportedArraySurvivesLaterAllocation(bytes32 fill) external pure {
        MemoryKV kv = MEMORY_KV_EMPTY;
        for (uint256 i = 1; i <= 5; i++) {
            kv = kv.set(MemoryKVKey.wrap(bytes32(i)), MemoryKVVal.wrap(bytes32(i * 7)));
        }

        bytes32[] memory array = kv.toBytes32Array();
        assertEq(array.length, 10);

        bytes32[] memory snapshot = new bytes32[](array.length);
        for (uint256 i = 0; i < array.length; i++) {
            snapshot[i] = array[i];
        }

        bytes32[] memory later = new bytes32[](32);
        for (uint256 i = 0; i < later.length; i++) {
            later[i] = fill;
        }

        assertEq(array.length, 10, "array length survived");
        for (uint256 i = 0; i < array.length; i++) {
            assertEq(array[i], snapshot[i], "array contents survived a later allocation");
        }
    }
}
