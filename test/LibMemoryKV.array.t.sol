// SPDX-License-Identifier: CAL
pragma solidity =0.8.18;

import "forge-std/Test.sol";
import "sol.lib.memory/LibMemory.sol";

import "../src/LibMemoryKV.sol";
import "./LibMemoryKVSlow.sol";

contract LibMemoryKVArrayTest is Test {
    using LibMemoryKV for MemoryKV;

    function testUint256ArrayGas0() public pure {
        MemoryKV kv = MemoryKV.wrap(0);
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(1), MemoryKVVal.wrap(2));
        uint256[] memory array = LibMemoryKV.toUint256Array(kv);
        (array);
    }

    function testUint256ArrayGas1() public pure {
        MemoryKV kv = MemoryKV.wrap(0);
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(1), MemoryKVVal.wrap(2));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(3), MemoryKVVal.wrap(4));
        uint256[] memory array = LibMemoryKV.toUint256Array(kv);
        (array);
    }

    function testUint256ArrayGas3() public pure {
        MemoryKV kv = MemoryKV.wrap(0);
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(1), MemoryKVVal.wrap(2));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(3), MemoryKVVal.wrap(4));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(5), MemoryKVVal.wrap(6));
        uint256[] memory array = LibMemoryKV.toUint256Array(kv);
        (array);
    }

    function testUint256ArrayGas4() public pure {
        MemoryKV kv = MemoryKV.wrap(0);
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(1), MemoryKVVal.wrap(2));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(3), MemoryKVVal.wrap(4));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(5), MemoryKVVal.wrap(6));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(7), MemoryKVVal.wrap(8));
        uint256[] memory array = LibMemoryKV.toUint256Array(kv);
        (array);
    }

    function testUint256ArrayGas5() public pure {
        MemoryKV kv = MemoryKV.wrap(0);
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(1), MemoryKVVal.wrap(2));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(3), MemoryKVVal.wrap(4));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(5), MemoryKVVal.wrap(6));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(7), MemoryKVVal.wrap(8));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(9), MemoryKVVal.wrap(10));
        uint256[] memory array = LibMemoryKV.toUint256Array(kv);
        (array);
    }

    function testUint256ArrayGas6() public pure {
        MemoryKV kv = MemoryKV.wrap(0);
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(1), MemoryKVVal.wrap(2));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(3), MemoryKVVal.wrap(4));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(5), MemoryKVVal.wrap(6));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(7), MemoryKVVal.wrap(8));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(9), MemoryKVVal.wrap(10));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(10), MemoryKVVal.wrap(2));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(30), MemoryKVVal.wrap(4));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(50), MemoryKVVal.wrap(6));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(70), MemoryKVVal.wrap(8));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(90), MemoryKVVal.wrap(10));
        uint256[] memory array = LibMemoryKV.toUint256Array(kv);
        (array);
    }

    function testArrayAllocatedMemory(uint256[] memory kvs) public {
        vm.assume(kvs.length % 2 == 0);

        MemoryKV kv = MemoryKV.wrap(0);

        for (uint256 i = 0; i < kvs.length; i += 2) {
            kv = kv.set(MemoryKVKey.wrap(kvs[i]), MemoryKVVal.wrap(kvs[i + 1]));
        }

        Pointer pointerBefore = LibPointer.allocatedMemoryPointer();
        uint256[] memory array = kv.toUint256Array();
        Pointer pointerAfter = LibPointer.allocatedMemoryPointer();

        uint256 pointerArray;
        assembly ("memory-safe") {
            pointerArray := array
        }

        assertTrue(array.length <= kvs.length);
        assertEq(Pointer.unwrap(pointerBefore), pointerArray);
        assertEq(Pointer.unwrap(pointerAfter), Pointer.unwrap(pointerBefore) + 0x20 + (array.length * 0x20));
    }

    function testRoundTrip(uint256[] memory kvs) public {
        // We hit gas limits pretty easily in this test for "large" sets.
        vm.assume(kvs.length < 50);
        vm.assume(kvs.length % 2 == 0);

        MemoryKV kv = MemoryKV.wrap(0);

        uint256[] memory slowKVs = new uint256[](0);
        for (uint256 i = 0; i < kvs.length; i += 2) {
            uint256 key = kvs[i];
            uint256 value = kvs[i + 1];

            kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(key), MemoryKVVal.wrap(value));
            slowKVs = LibMemoryKVSlow.set(slowKVs, key, value);
        }

        uint256[] memory roundKVs = LibMemoryKV.toUint256Array(kv);
        assertEq(slowKVs.length, roundKVs.length);

        for (uint256 i = 0; i < slowKVs.length; i += 2) {
            uint256 key = slowKVs[i];
            (bool slowExists, uint256 slowVal) = LibMemoryKVSlow.get(slowKVs, key);
            (bool roundExists, uint256 roundVal) = LibMemoryKVSlow.get(roundKVs, key);
            assertEq(slowExists, true);
            assertEq(roundExists, true);
            assertEq(slowVal, roundVal);
        }
    }

    function testRoundTripLinear(uint256[] memory kvs) public {
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
