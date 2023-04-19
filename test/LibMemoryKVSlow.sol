// SPDX-License-Identifier: CAL
pragma solidity ^0.8.18;

import "sol.lib.memory/LibUint256Array.sol";

library LibMemoryKVSlow {
    function exists(uint256[] memory kvs_, uint256 k_) internal pure returns (bool, uint256) {
        for (uint256 i_ = 0; i_ < kvs_.length; i_ += 2) {
            if (kvs_[i_] == k_) {
                return (true, i_);
            }
        }
        return (false, 0);
    }

    function get(uint256[] memory kvs_, uint256 k_) internal pure returns (bool, uint256) {
        (bool exists_, uint256 index_) = exists(kvs_, k_);
        return (exists_, exists_ ? kvs_[index_] : 0);
    }

    function set(uint256[] memory kvs_, uint256 k_, uint256 v_) internal pure returns (uint256[] memory) {
        (bool exists_, uint256 index_) = exists(kvs_, k_);
        if (exists_) {
            kvs_[index_ + 1] = v_;
            return kvs_;
        } else {
            uint256[] memory kv_ = new uint256[](2);
            kv_[0] = k_;
            kv_[1] = v_;
            return LibUint256Array.unsafeExtend(kvs_, kv_);
        }
    }
}
