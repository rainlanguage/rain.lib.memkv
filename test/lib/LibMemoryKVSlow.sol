// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibBytes32Array} from "rain.solmem/lib/LibBytes32Array.sol";
import {MemoryKV} from "src/lib/LibMemoryKV.sol";

library LibMemoryKVSlow {
    function exists(bytes32[] memory kvs, bytes32 k) internal pure returns (bool, uint256) {
        for (uint256 i = 0; i < kvs.length; i += 2) {
            if (kvs[i] == k) {
                return (true, i);
            }
        }
        return (false, 0);
    }

    function get(bytes32[] memory kvs, bytes32 k) internal pure returns (bool, bytes32) {
        (bool existsVal, uint256 index) = exists(kvs, k);
        return (existsVal, existsVal ? kvs[index] : bytes32(uint256(0)));
    }

    function set(bytes32[] memory kvs, bytes32 k, bytes32 v) internal pure returns (bytes32[] memory) {
        (bool existsVal, uint256 index) = exists(kvs, k);
        if (existsVal) {
            kvs[index + 1] = v;
            return kvs;
        } else {
            bytes32[] memory kv = new bytes32[](2);
            kv[0] = k;
            kv[1] = v;
            return LibBytes32Array.unsafeExtend(kvs, kv);
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
