// SPDX-License-Identifier: CAL
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "../src/LibMemoryKV.sol";

contract LibMemoryKVTest is Test {
    function testRoundTrip(uint256[] memory kvs_) public {
        vm.assume(kvs_.length % 2 == 0);
        MemoryKV kv_ = MemoryKV.wrap(0);
        for (uint256 i_ = 0; i_ < kvs_.length; i_ += 2) {
            kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(kvs_[i_]), MemoryKVVal.wrap(kvs_[i_ + 1]));
        }

        assertEq(kvs_, LibMemoryKV.toUint256Array(kv_));
    }
}
