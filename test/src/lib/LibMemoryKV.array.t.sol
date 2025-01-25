// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";

import {LibPointer, Pointer} from "rain.solmem/lib/LibPointer.sol";

import {LibMemoryKV, MemoryKV, MemoryKVVal, MemoryKVKey} from "src/lib/LibMemoryKV.sol";
import {LibMemoryKVSlow} from "test/lib/LibMemoryKVSlow.sol";

contract LibMemoryKVArrayTest is Test {
    using LibMemoryKV for MemoryKV;

    function testBytes32ArrayGas0() public pure {
        MemoryKV kv = MemoryKV.wrap(0);
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(1))), MemoryKVVal.wrap(bytes32(uint256(2))));
        bytes32[] memory array = LibMemoryKV.toBytes32Array(kv);
        (array);
    }

    function testBytes32ArrayGas1() public pure {
        MemoryKV kv = MemoryKV.wrap(0);
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(1))), MemoryKVVal.wrap(bytes32(uint256(2))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(3))), MemoryKVVal.wrap(bytes32(uint256(4))));
        bytes32[] memory array = LibMemoryKV.toBytes32Array(kv);
        (array);
    }

    function testBytes32ArrayGas3() public pure {
        MemoryKV kv = MemoryKV.wrap(0);
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(1))), MemoryKVVal.wrap(bytes32(uint256(2))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(3))), MemoryKVVal.wrap(bytes32(uint256(4))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(5))), MemoryKVVal.wrap(bytes32(uint256(6))));
        bytes32[] memory array = LibMemoryKV.toBytes32Array(kv);
        (array);
    }

    function testBytes32ArrayGas4() public pure {
        MemoryKV kv = MemoryKV.wrap(0);
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(1))), MemoryKVVal.wrap(bytes32(uint256(2))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(3))), MemoryKVVal.wrap(bytes32(uint256(4))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(5))), MemoryKVVal.wrap(bytes32(uint256(6))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(7))), MemoryKVVal.wrap(bytes32(uint256(8))));
        bytes32[] memory array = LibMemoryKV.toBytes32Array(kv);
        (array);
    }

    function testBytes32ArrayGas5() public pure {
        MemoryKV kv = MemoryKV.wrap(0);
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(1))), MemoryKVVal.wrap(bytes32(uint256(2))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(3))), MemoryKVVal.wrap(bytes32(uint256(4))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(5))), MemoryKVVal.wrap(bytes32(uint256(6))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(7))), MemoryKVVal.wrap(bytes32(uint256(8))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(9))), MemoryKVVal.wrap(bytes32(uint256(10))));
        bytes32[] memory array = LibMemoryKV.toBytes32Array(kv);
        (array);
    }

    function testBytes32ArrayGas6() public pure {
        MemoryKV kv = MemoryKV.wrap(0);
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(1))), MemoryKVVal.wrap(bytes32(uint256(2))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(3))), MemoryKVVal.wrap(bytes32(uint256(4))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(5))), MemoryKVVal.wrap(bytes32(uint256(6))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(7))), MemoryKVVal.wrap(bytes32(uint256(8))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(9))), MemoryKVVal.wrap(bytes32(uint256(10))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(10))), MemoryKVVal.wrap(bytes32(uint256(2))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(30))), MemoryKVVal.wrap(bytes32(uint256(4))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(50))), MemoryKVVal.wrap(bytes32(uint256(6))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(70))), MemoryKVVal.wrap(bytes32(uint256(8))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(90))), MemoryKVVal.wrap(bytes32(uint256(10))));
        bytes32[] memory array = LibMemoryKV.toBytes32Array(kv);
        (array);
    }

    function testArrayAllocatedMemory(bytes32[] memory kvs) public pure {
        vm.assume(kvs.length % 2 == 0);

        MemoryKV kv = MemoryKV.wrap(0);

        for (uint256 i = 0; i < kvs.length; i += 2) {
            kv = kv.set(MemoryKVKey.wrap(kvs[i]), MemoryKVVal.wrap(kvs[i + 1]));
        }

        Pointer pointerBefore = LibPointer.allocatedMemoryPointer();
        bytes32[] memory array = kv.toBytes32Array();
        Pointer pointerAfter = LibPointer.allocatedMemoryPointer();

        uint256 pointerArray;
        assembly ("memory-safe") {
            pointerArray := array
        }

        assertTrue(array.length <= kvs.length);
        assertEq(Pointer.unwrap(pointerBefore), pointerArray);
        assertEq(Pointer.unwrap(pointerAfter), Pointer.unwrap(pointerBefore) + 0x20 + (array.length * 0x20));
    }

    function testRoundTrip(bytes32[] memory kvs) public pure {
        // We hit gas limits pretty easily in this test for "large" sets.
        vm.assume(kvs.length < 50);
        vm.assume(kvs.length % 2 == 0);

        MemoryKV kv = MemoryKV.wrap(0);

        bytes32[] memory slowKVs = new bytes32[](0);
        for (uint256 i = 0; i < kvs.length; i += 2) {
            bytes32 key = kvs[i];
            bytes32 value = kvs[i + 1];

            kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(key), MemoryKVVal.wrap(value));
            slowKVs = LibMemoryKVSlow.set(slowKVs, key, value);
        }

        bytes32[] memory roundKVs = LibMemoryKV.toBytes32Array(kv);
        assertEq(slowKVs.length, roundKVs.length);

        for (uint256 i = 0; i < slowKVs.length; i += 2) {
            bytes32 key = slowKVs[i];
            (bool slowExists, bytes32 slowVal) = LibMemoryKVSlow.get(slowKVs, key);
            (bool roundExists, bytes32 roundVal) = LibMemoryKVSlow.get(roundKVs, key);
            assertEq(slowExists, true);
            assertEq(roundExists, true);
            assertEq(slowVal, roundVal);
        }
    }

    function testRoundTripLinear(uint256[] memory kvs) public pure {
        vm.assume(kvs.length % 2 == 0);

        MemoryKV kv = MemoryKV.wrap(0);

        for (uint256 i = 0; i < kvs.length; i += 2) {
            kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(kvs[i]), MemoryKVVal.wrap(kvs[i + 1]));
        }

        uint256[] memory array = LibMemoryKV.toUint256Array(kv);
        uint256[] memory arrayLinear = LibMemoryKVSlow.toUint256ArrayLinear(kv);

        assertEq(array.length, arrayLinear.length);

        uint256 matches = 0;
        for (uint256 i = 0; i < array.length; i += 2) {
            for (uint256 j = 0; j < arrayLinear.length; j += 2) {
                if (array[i] == arrayLinear[j] && array[i + 1] == arrayLinear[j + 1]) {
                    matches += 1;
                }
            }
        }
        assertEq(matches, arrayLinear.length / 2);
    }
}
