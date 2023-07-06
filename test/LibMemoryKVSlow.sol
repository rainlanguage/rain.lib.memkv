// SPDX-License-Identifier: CAL
pragma solidity =0.8.18;

import "sol.lib.memory/LibUint256Array.sol";
import "../src/LibMemoryKV.sol";

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

    function toUint256ArrayLinear(MemoryKV kv_) internal pure returns (uint256[] memory arr_) {
        assembly ("memory-safe") {
            arr_ := mload(0x40)
            let len_ := shr(0xf0, kv_)
            mstore(0x40, add(arr_, add(0x20, mul(len_, 0x20))))
            mstore(arr_, len_)

            function copyFromPtr(cursor_, ptr_) -> end_ {
                for {} iszero(iszero(ptr_)) {
                    ptr_ := mload(add(ptr_, 0x40))
                    cursor_ := add(cursor_, 0x40)
                } {
                    mstore(cursor_, mload(ptr_))
                    mstore(add(cursor_, 0x20), mload(add(ptr_, 0x20)))
                }
                end_ := cursor_
            }

            let cursor_ := add(arr_, 0x20)
            for {
                let ptrCursor_ := 0
                let ptr_ := and(kv_, 0xFFFF)
            } lt(ptrCursor_, 0xf0) {
                ptrCursor_ := add(ptrCursor_, 0x10)
                ptr_ := and(shr(ptrCursor_, kv_), 0xFFFF)
            } { cursor_ := copyFromPtr(cursor_, ptr_) }
        }
    }
}
