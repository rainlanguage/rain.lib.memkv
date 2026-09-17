// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {LibPointer, Pointer} from "rain-solmem-0.1.28/src/lib/LibPointer.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {LibMemoryKVSlow} from "test/lib/LibMemoryKVSlow.sol";

/// @title LibMemoryKVSlowTest
/// The model is what the round trip tests hold the library to, so what it
/// answers has to be established somewhere other than a comparison against the
/// library. `testRoundTrip` reads BOTH sides through `LibMemoryKVSlow.get` and
/// only ever asks it for keys it just set, so a `get` that reads the wrong word
/// of the pair, or that answers a key it was never given, agrees with itself
/// and the comparison holds for the wrong reason. The cases here are those: the
/// word a hit reads back, what a miss answers, and the memory the linear export
/// claims for the array it writes.
contract LibMemoryKVSlowTest is Test {
    /// A pair is a key followed by the value it is paired with, and a hit
    /// answers with the second of the two. The table is written out rather than
    /// built by `set` so the expected value is not the model's own answer, and
    /// no key equals any value, so reading the key word back is a different
    /// answer at every pair.
    function testSlowGetReadsTheValueOfThePair() external pure {
        bytes32[] memory kvs = new bytes32[](6);
        kvs[0] = bytes32(uint256(0x11));
        kvs[1] = bytes32(uint256(0x22));
        kvs[2] = bytes32(uint256(0x33));
        kvs[3] = bytes32(uint256(0x44));
        kvs[4] = bytes32(uint256(0x55));
        kvs[5] = bytes32(uint256(0x66));

        for (uint256 i = 0; i < kvs.length; i += 2) {
            (bool exists, bytes32 value) = LibMemoryKVSlow.get(kvs, kvs[i]);
            assertTrue(exists);
            assertEq(value, kvs[i + 1]);
        }
    }

    /// A key the model was never given is absent and answers zero, whether or
    /// not it appears as a value.
    function testSlowGetAKeyThatIsNotThere(bytes32 key, bytes32 value, bytes32 needle) external pure {
        vm.assume(needle != key);

        bytes32[] memory kvs = new bytes32[](2);
        kvs[0] = key;
        kvs[1] = value;

        (bool exists, bytes32 got) = LibMemoryKVSlow.get(kvs, needle);
        assertFalse(exists);
        assertEq(got, bytes32(0));

        (bool existsEmpty, bytes32 gotEmpty) = LibMemoryKVSlow.get(new bytes32[](0), needle);
        assertFalse(existsEmpty);
        assertEq(gotEmpty, bytes32(0));
    }

    /// A miss reports index zero. Both callers guard on the flag before they
    /// read the index, so this is the model's own contract rather than
    /// something a round trip could disagree with.
    function testSlowExistsAMissReportsIndexZero(bytes32 key, bytes32 value, bytes32 needle) external pure {
        vm.assume(needle != key);

        bytes32[] memory kvs = new bytes32[](2);
        kvs[0] = key;
        kvs[1] = value;

        (bool exists, uint256 index) = LibMemoryKVSlow.exists(kvs, needle);
        assertFalse(exists);
        assertEq(index, 0);
    }

    /// The linear export takes the array from the free pointer and leaves the
    /// free pointer past every word it writes into it. An allocation short of
    /// what the copy writes leaves exported pairs sitting in memory that the
    /// next allocation hands out, which nothing reading only the array can see.
    function testSlowLinearExportAllocatesWhatItWrites(bytes32[] memory kvs) external pure {
        vm.assume(kvs.length % 2 == 0);

        MemoryKV kv = MEMORY_KV_EMPTY;
        for (uint256 i = 0; i < kvs.length; i += 2) {
            kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(kvs[i]), MemoryKVVal.wrap(kvs[i + 1]));
        }

        Pointer pointerBefore = LibPointer.allocatedMemoryPointer();
        bytes32[] memory array = LibMemoryKVSlow.toBytes32ArrayLinear(kv);
        Pointer pointerAfter = LibPointer.allocatedMemoryPointer();

        uint256 pointerArray;
        assembly ("memory-safe") {
            pointerArray := array
        }

        assertEq(Pointer.unwrap(pointerBefore), pointerArray);
        assertEq(Pointer.unwrap(pointerAfter), Pointer.unwrap(pointerBefore) + 0x20 + (array.length * 0x20));
    }
}
