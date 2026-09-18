// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";

import {LibPointer, Pointer} from "rain-solmem-0.1.28/src/lib/LibPointer.sol";
import {LibBytes32Array} from "rain-solmem-0.1.28/src/lib/LibBytes32Array.sol";

import {LibMemoryKV, MemoryKV, MemoryKVVal, MemoryKVKey, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {countPair} from "test/lib/LibMemoryKVExport.sol";
import {LibMemoryKVSlow} from "test/lib/LibMemoryKVSlow.sol";

contract LibMemoryKVArrayTest is Test {
    using LibMemoryKV for MemoryKV;

    // The `Gas` tests assert nothing on purpose. Each sets as many fresh keys as
    // there are pairs in its name, then exports the store, so the gas report
    // carries the cost of that build and export and nothing else. No test
    // asserts a row's figure: `LibMemoryKV.gasClaims.t.sol` measures the export
    // on its own and asserts its gas only relative to other measurements,
    // against a linear walk and between lists.
    function testBytes32ArrayGas0Pairs() public pure {
        bytes32[] memory array = MEMORY_KV_EMPTY.toBytes32Array();
        (array);
    }

    function testBytes32ArrayGas1Pair() public pure {
        MemoryKV kv = MEMORY_KV_EMPTY;
        kv = kv.set(MemoryKVKey.wrap(bytes32(uint256(1))), MemoryKVVal.wrap(bytes32(uint256(2))));
        bytes32[] memory array = kv.toBytes32Array();
        (array);
    }

    function testBytes32ArrayGas2Pairs() public pure {
        MemoryKV kv = MEMORY_KV_EMPTY;
        kv = kv.set(MemoryKVKey.wrap(bytes32(uint256(1))), MemoryKVVal.wrap(bytes32(uint256(2))));
        kv = kv.set(MemoryKVKey.wrap(bytes32(uint256(3))), MemoryKVVal.wrap(bytes32(uint256(4))));
        bytes32[] memory array = kv.toBytes32Array();
        (array);
    }

    function testBytes32ArrayGas3Pairs() public pure {
        MemoryKV kv = MEMORY_KV_EMPTY;
        kv = kv.set(MemoryKVKey.wrap(bytes32(uint256(1))), MemoryKVVal.wrap(bytes32(uint256(2))));
        kv = kv.set(MemoryKVKey.wrap(bytes32(uint256(3))), MemoryKVVal.wrap(bytes32(uint256(4))));
        kv = kv.set(MemoryKVKey.wrap(bytes32(uint256(5))), MemoryKVVal.wrap(bytes32(uint256(6))));
        bytes32[] memory array = kv.toBytes32Array();
        (array);
    }

    function testBytes32ArrayGas4Pairs() public pure {
        MemoryKV kv = MEMORY_KV_EMPTY;
        kv = kv.set(MemoryKVKey.wrap(bytes32(uint256(1))), MemoryKVVal.wrap(bytes32(uint256(2))));
        kv = kv.set(MemoryKVKey.wrap(bytes32(uint256(3))), MemoryKVVal.wrap(bytes32(uint256(4))));
        kv = kv.set(MemoryKVKey.wrap(bytes32(uint256(5))), MemoryKVVal.wrap(bytes32(uint256(6))));
        kv = kv.set(MemoryKVKey.wrap(bytes32(uint256(7))), MemoryKVVal.wrap(bytes32(uint256(8))));
        bytes32[] memory array = kv.toBytes32Array();
        (array);
    }

    function testBytes32ArrayGas5Pairs() public pure {
        MemoryKV kv = MEMORY_KV_EMPTY;
        kv = kv.set(MemoryKVKey.wrap(bytes32(uint256(1))), MemoryKVVal.wrap(bytes32(uint256(2))));
        kv = kv.set(MemoryKVKey.wrap(bytes32(uint256(3))), MemoryKVVal.wrap(bytes32(uint256(4))));
        kv = kv.set(MemoryKVKey.wrap(bytes32(uint256(5))), MemoryKVVal.wrap(bytes32(uint256(6))));
        kv = kv.set(MemoryKVKey.wrap(bytes32(uint256(7))), MemoryKVVal.wrap(bytes32(uint256(8))));
        kv = kv.set(MemoryKVKey.wrap(bytes32(uint256(9))), MemoryKVVal.wrap(bytes32(uint256(10))));
        bytes32[] memory array = kv.toBytes32Array();
        (array);
    }

    function testBytes32ArrayGas10Pairs() public pure {
        MemoryKV kv = MEMORY_KV_EMPTY;
        kv = kv.set(MemoryKVKey.wrap(bytes32(uint256(1))), MemoryKVVal.wrap(bytes32(uint256(2))));
        kv = kv.set(MemoryKVKey.wrap(bytes32(uint256(3))), MemoryKVVal.wrap(bytes32(uint256(4))));
        kv = kv.set(MemoryKVKey.wrap(bytes32(uint256(5))), MemoryKVVal.wrap(bytes32(uint256(6))));
        kv = kv.set(MemoryKVKey.wrap(bytes32(uint256(7))), MemoryKVVal.wrap(bytes32(uint256(8))));
        kv = kv.set(MemoryKVKey.wrap(bytes32(uint256(9))), MemoryKVVal.wrap(bytes32(uint256(10))));
        kv = kv.set(MemoryKVKey.wrap(bytes32(uint256(10))), MemoryKVVal.wrap(bytes32(uint256(2))));
        kv = kv.set(MemoryKVKey.wrap(bytes32(uint256(30))), MemoryKVVal.wrap(bytes32(uint256(4))));
        kv = kv.set(MemoryKVKey.wrap(bytes32(uint256(50))), MemoryKVVal.wrap(bytes32(uint256(6))));
        kv = kv.set(MemoryKVKey.wrap(bytes32(uint256(70))), MemoryKVVal.wrap(bytes32(uint256(8))));
        kv = kv.set(MemoryKVKey.wrap(bytes32(uint256(90))), MemoryKVVal.wrap(bytes32(uint256(10))));
        bytes32[] memory array = kv.toBytes32Array();
        (array);
    }

    function testArrayAllocatedMemory(bytes32[] memory kvs) public pure {
        vm.assume(kvs.length % 2 == 0);

        MemoryKV kv = MEMORY_KV_EMPTY;

        for (uint256 i = 0; i < kvs.length; i += 2) {
            kv = kv.set(MemoryKVKey.wrap(kvs[i]), MemoryKVVal.wrap(kvs[i + 1]));
        }

        Pointer pointerBefore = LibPointer.allocatedMemoryPointer();
        bytes32[] memory array = kv.toBytes32Array();
        Pointer pointerAfter = LibPointer.allocatedMemoryPointer();

        uint256 pointerArray = Pointer.unwrap(LibBytes32Array.startPointer(array));

        assertTrue(array.length <= kvs.length);
        assertEq(Pointer.unwrap(pointerBefore), pointerArray);
        assertEq(Pointer.unwrap(pointerAfter), Pointer.unwrap(pointerBefore) + 0x20 + (array.length * 0x20));
    }

    function testRoundTrip(bytes32[] memory kvs) public pure {
        // We hit gas limits pretty easily in this test for "large" sets.
        vm.assume(kvs.length < 50);
        vm.assume(kvs.length % 2 == 0);

        MemoryKV kv = MEMORY_KV_EMPTY;

        bytes32[] memory slowKVs = new bytes32[](0);
        for (uint256 i = 0; i < kvs.length; i += 2) {
            bytes32 key = kvs[i];
            bytes32 value = kvs[i + 1];

            kv = kv.set(MemoryKVKey.wrap(key), MemoryKVVal.wrap(value));
            slowKVs = LibMemoryKVSlow.set(slowKVs, key, value);
        }

        bytes32[] memory roundKVs = kv.toBytes32Array();
        assertEq(slowKVs.length, roundKVs.length);

        for (uint256 i = 0; i < slowKVs.length; i += 2) {
            bytes32 key = slowKVs[i];
            (bool slowExists, bytes32 slowVal) = LibMemoryKVSlow.get(slowKVs, key);
            (bool roundExists, bytes32 roundVal) = LibMemoryKVSlow.get(roundKVs, key);
            assertEq(slowExists, true);
            assertEq(roundExists, true);
            assertEq(slowVal, roundVal);
            // The exported value is also the word the model holds after the
            // key, read out of its array by index.
            assertEq(roundVal, slowKVs[i + 1]);
        }
    }

    function testRoundTripLinear(bytes32[] memory kvs) public pure {
        vm.assume(kvs.length % 2 == 0);

        MemoryKV kv = MEMORY_KV_EMPTY;

        for (uint256 i = 0; i < kvs.length; i += 2) {
            kv = kv.set(MemoryKVKey.wrap(kvs[i]), MemoryKVVal.wrap(kvs[i + 1]));
        }

        bytes32[] memory array = kv.toBytes32Array();
        bytes32[] memory arrayLinear = LibMemoryKVSlow.toBytes32ArrayLinear(kv);

        assertEq(array.length, arrayLinear.length);

        // The linear walk visits each list exactly once, and every pair it
        // exports is counted on its own in the bisect's export: exactly once.
        for (uint256 i = 0; i < arrayLinear.length; i += 2) {
            assertEq(countPair(array, arrayLinear[i], arrayLinear[i + 1]), 1, "each pair exported exactly once");
        }
    }
}
