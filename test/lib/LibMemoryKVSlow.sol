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

    function toBytes32ArrayLinear(MemoryKV kv) internal pure returns (bytes32[] memory arr) {
        assembly ("memory-safe") {
            arr := mload(0x40)
            let len := shr(0xf0, kv)
            mstore(0x40, add(arr, add(0x20, mul(len, 0x20))))
            mstore(arr, len)

            function copyFromPtr(cursor, ptr) -> end {
                for {} iszero(iszero(ptr)) {
                    ptr := mload(add(ptr, 0x40))
                    cursor := add(cursor, 0x40)
                } {
                    mstore(cursor, mload(ptr))
                    mstore(add(cursor, 0x20), mload(add(ptr, 0x20)))
                }
                end := cursor
            }

            let cursor := add(arr, 0x20)
            for {
                let ptrCursor := 0
                let ptr := and(kv, 0xFFFF)
            } lt(ptrCursor, 0xf0) {
                ptrCursor := add(ptrCursor, 0x10)
                ptr := and(shr(ptrCursor, kv), 0xFFFF)
            } { cursor := copyFromPtr(cursor, ptr) }
        }
    }
}
