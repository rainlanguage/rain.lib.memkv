// SPDX-License-Identifier: CAL
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "../src/LibMemoryKV.sol";
import "./LibMemoryKVSlow.sol";

contract LibMemoryKVTest is Test {
    function testRoundTrip(uint256[] memory kvs_) public {
        // We hit gas limits pretty easily in this test for "large" sets.
        vm.assume(kvs_.length < 50);
        vm.assume(kvs_.length % 2 == 0);

        MemoryKV kv_ = MemoryKV.wrap(0);

        uint256[] memory slowKVs_ = new uint256[](0);
        for (uint256 i_ = 0; i_ < kvs_.length; i_ += 2) {
            uint256 k_ = kvs_[i_];
            uint256 v_ = kvs_[i_ + 1];

            kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(k_), MemoryKVVal.wrap(v_));
            slowKVs_ = LibMemoryKVSlow.set(slowKVs_, k_, v_);
        }

        uint256[] memory roundKVs_ = LibMemoryKV.toUint256Array(kv_);
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