// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal} from "src/lib/LibMemoryKV.sol";

/// @title LibMemoryKVStorageParityTest
/// The memory KV should behave the same as contract storage.
contract LibMemoryKVStorageParityTest is Test {
    //forge-lint: disable-next-line(mixed-case-variable)
    mapping(bytes32 => bytes32) public sStorageKV;

    /// A single get/set should behave the same as storage.
    function testSingleGetSet(bytes32 key, bytes32 value) external {
        MemoryKV kv = MemoryKV.wrap(0);
        sStorageKV[key] = value;
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(key), MemoryKVVal.wrap(value));
        (uint256 exists, MemoryKVVal get) = LibMemoryKV.get(kv, MemoryKVKey.wrap(key));

        assertEq(1, exists, "exists");
        assertEq(MemoryKVVal.unwrap(get), MemoryKVVal.unwrap(MemoryKVVal.wrap(value)), "value");
        assertEq(sStorageKV[key], MemoryKVVal.unwrap(get), "storage");
    }

    /// A single get/set pair that we can fuzz.
    /// @param key The key to set.
    /// @param value The value to set.
    //forge-lint: disable-next-line(pascal-case-struct)
    struct KV {
        bytes32 key;
        bytes32 value;
    }

    /// A list of get/sets should behave the same as storage.
    function testMultiGetSetSingle(KV[] memory kvs) external {
        MemoryKV kv = MemoryKV.wrap(0);
        for (uint256 i = 0; i < kvs.length; i++) {
            sStorageKV[kvs[i].key] = kvs[i].value;
            kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(kvs[i].key), MemoryKVVal.wrap(kvs[i].value));
        }
        bytes32[] memory finalKVs = LibMemoryKV.toBytes32Array(kv);
        for (uint256 i = 0; i < finalKVs.length; i += 2) {
            assertEq(sStorageKV[finalKVs[i]], finalKVs[i + 1], "storage");
        }
    }

    /// Many KVs should all behave the same as storage in aggregate.
    function testMultiGetSetDouble(KV[] memory kvsOne, KV[] memory kvsTwo) external {
        uint256 endOne = kvsOne.length >= 10 ? 10 : kvsOne.length;
        MemoryKV kv = MemoryKV.wrap(0);
        for (uint256 i = 0; i < endOne; i++) {
            sStorageKV[kvsOne[i].key] = kvsOne[i].value;
            kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(kvsOne[i].key), MemoryKVVal.wrap(kvsOne[i].value));
        }
        bytes32[] memory finalKVs = LibMemoryKV.toBytes32Array(kv);
        for (uint256 i = 0; i < finalKVs.length; i += 2) {
            assertEq(sStorageKV[finalKVs[i]], finalKVs[i + 1], "storage");
        }

        uint256 endTwo = kvsTwo.length >= 10 ? 10 : kvsTwo.length;
        MemoryKV kvTwo = MemoryKV.wrap(0);
        for (uint256 i = 0; i < endTwo; i++) {
            sStorageKV[kvsTwo[i].key] = kvsTwo[i].value;
            kvTwo = LibMemoryKV.set(kvTwo, MemoryKVKey.wrap(kvsTwo[i].key), MemoryKVVal.wrap(kvsTwo[i].value));
        }
        bytes32[] memory finalKVsTwo = LibMemoryKV.toBytes32Array(kvTwo);
        for (uint256 i = 0; i < finalKVsTwo.length; i += 2) {
            assertEq(sStorageKV[finalKVsTwo[i]], finalKVsTwo[i + 1], "storage");
        }
    }
}
