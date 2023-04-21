// SPDX-License-Identifier: CAL
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "sol.lib.memory/LibMemory.sol";

import "../src/LibMemoryKV.sol";
import "./LibMemoryKVSlow.sol";

contract LibMemoryKVTest is Test {



    function testSetGas0() public pure {
        MemoryKV kv = MemoryKV.wrap(0);
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(1), MemoryKVVal.wrap(2));
    }

    function testSetGas1() public pure {
        MemoryKV kv = MemoryKV.wrap(0);
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(1), MemoryKVVal.wrap(2));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(3), MemoryKVVal.wrap(4));
    }

    function testSetGas3() public pure {
        MemoryKV kv = MemoryKV.wrap(0);
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(1), MemoryKVVal.wrap(2));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(3), MemoryKVVal.wrap(4));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(5), MemoryKVVal.wrap(6));
    }

    function testSetGas4() public pure {
        MemoryKV kv = MemoryKV.wrap(0);
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(1), MemoryKVVal.wrap(2));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(3), MemoryKVVal.wrap(4));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(5), MemoryKVVal.wrap(6));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(7), MemoryKVVal.wrap(8));
    }

    function testSetGas5() public pure {
        MemoryKV kv = MemoryKV.wrap(0);
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(1), MemoryKVVal.wrap(2));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(3), MemoryKVVal.wrap(4));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(5), MemoryKVVal.wrap(6));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(7), MemoryKVVal.wrap(8));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(9), MemoryKVVal.wrap(10));
    }

    function testSetGas6() public pure {
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
    }

    function testUint256ArrayGas0() public pure {
        MemoryKV kv = MemoryKV.wrap(0);
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(1), MemoryKVVal.wrap(2));
        uint256[] memory arr_ = LibMemoryKV.toUint256Array(kv);
        (arr_);
    }

    function testUint256ArrayGas1() public pure {
        MemoryKV kv = MemoryKV.wrap(0);
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(1), MemoryKVVal.wrap(2));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(3), MemoryKVVal.wrap(4));
        uint256[] memory arr_ = LibMemoryKV.toUint256Array(kv);
        (arr_);
    }

    function testUint256ArrayGas3() public pure {
        MemoryKV kv = MemoryKV.wrap(0);
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(1), MemoryKVVal.wrap(2));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(3), MemoryKVVal.wrap(4));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(5), MemoryKVVal.wrap(6));
        uint256[] memory arr_ = LibMemoryKV.toUint256Array(kv);
        (arr_);
    }

    function testUint256ArrayGas4() public pure {
        MemoryKV kv = MemoryKV.wrap(0);
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(1), MemoryKVVal.wrap(2));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(3), MemoryKVVal.wrap(4));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(5), MemoryKVVal.wrap(6));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(7), MemoryKVVal.wrap(8));
        uint256[] memory arr_ = LibMemoryKV.toUint256Array(kv);
        (arr_);
    }

    function testUint256ArrayGas5() public pure {
        MemoryKV kv = MemoryKV.wrap(0);
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(1), MemoryKVVal.wrap(2));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(3), MemoryKVVal.wrap(4));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(5), MemoryKVVal.wrap(6));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(7), MemoryKVVal.wrap(8));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(9), MemoryKVVal.wrap(10));
        uint256[] memory arr_ = LibMemoryKV.toUint256Array(kv);
        (arr_);
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
        uint256[] memory arr_ = LibMemoryKV.toUint256Array(kv);
        (arr_);
    }

    function testRoundTrip(uint256[] memory kvs_) public {
        // We hit gas limits pretty easily in this test for "large" sets.
        vm.assume(kvs_.length < 50);
        vm.assume(kvs_.length % 2 == 0);

        MemoryKV kv = MemoryKV.wrap(0);

        uint256[] memory slowKVs_ = new uint256[](0);
        for (uint256 i_ = 0; i_ < kvs_.length; i_ += 2) {
            uint256 k_ = kvs_[i_];
            uint256 v_ = kvs_[i_ + 1];

            kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(k_), MemoryKVVal.wrap(v_));
            slowKVs_ = LibMemoryKVSlow.set(slowKVs_, k_, v_);
        }

        uint256[] memory roundKVs_ = LibMemoryKV.toUint256Array(kv);
        assertEq(slowKVs_.length, roundKVs_.length);

        for (uint256 i_ = 0; i_ < slowKVs_.length; i_ += 2) {
            uint256 k_ = slowKVs_[i_];
            (bool slowExists_, uint256 slowVal_) = LibMemoryKVSlow.get(slowKVs_, k_);
            (bool roundExists_, uint256 roundVal_) = LibMemoryKVSlow.get(roundKVs_, k_);
            assertEq(slowExists_, true);
            assertEq(roundExists_, true);
            assertEq(slowVal_, roundVal_);
        }
    }
}
