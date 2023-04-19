// SPDX-License-Identifier: CAL
pragma solidity ^0.8.18;

library LibMemoryKVSlow {
    function get(uint256[] memory kvs_, k_) internal pure returns (bool, uint256) {
        for (uint256 i_ = 0; i_ < kvs_.length; i_ += 2) {
            if (kvs_[i_] == k_) {
                return (true, kvs_[i_]);
            }
        }
        return (false, 0);
    }

    function set(uint256[] memory kvs_, k_, v_) internal pure returns (uint256[] memory) {

    }
}