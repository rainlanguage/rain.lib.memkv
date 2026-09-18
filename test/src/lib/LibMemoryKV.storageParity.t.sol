// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {countPair} from "test/lib/LibMemoryKVExport.sol";

/// @title LibMemoryKVStorageParityTest
/// The memory KV should behave the same as contract storage.
contract LibMemoryKVStorageParityTest is Test {
    using LibMemoryKV for MemoryKV;

    /// Contract storage standing in for one store.
    /// @param values The value each key was last set to.
    /// @param seen Whether each key has been set.
    /// @param distinct How many distinct keys have been set.
    struct StorageStore {
        mapping(bytes32 => bytes32) values;
        mapping(bytes32 => bool) seen;
        uint256 distinct;
    }

    /// How many pairs each store in `testTwoLiveStoresEachMatchTheirOwnStorage`
    /// takes from its fuzzed array. Both decoded arrays sit in memory below the
    /// first node, a pointer word and two struct words per pair, so uncapped
    /// arrays can push the nodes past `POINTER_MASK` and `set` reverts
    /// `MemoryKVOverflow` instead of the test checking parity. Ten per store
    /// keeps every node below it.
    uint256 internal constant PAIRS_PER_STORE = 10;

    //forge-lint: disable-next-line(mixed-case-variable)
    mapping(bytes32 => bytes32) public sStorageKV;

    StorageStore internal sStoreOne;
    StorageStore internal sStoreTwo;

    /// Set `pair` in both `kv` and `store`, returning the new `kv`.
    function setBoth(MemoryKV kv, StorageStore storage store, KV memory pair) internal returns (MemoryKV) {
        if (!store.seen[pair.key]) {
            store.seen[pair.key] = true;
            store.distinct++;
        }
        store.values[pair.key] = pair.value;
        return kv.set(MemoryKVKey.wrap(pair.key), MemoryKVVal.wrap(pair.value));
    }

    /// `kv` holds what `store` holds, `pairs[0:end]` having been set in both:
    /// every key set reads back through `get` with the value storage holds for
    /// it, is exported exactly once with that value, and the export holds two
    /// words per distinct key, so nothing else.
    function assertMatchesStorage(MemoryKV kv, StorageStore storage store, KV[] memory pairs, uint256 end)
        internal
        view
    {
        bytes32[] memory exported = kv.toBytes32Array();
        assertEq(exported.length, store.distinct * 2, "export holds every distinct key once");
        for (uint256 i = 0; i < end; i++) {
            bytes32 key = pairs[i].key;
            bytes32 value = store.values[key];
            (uint256 exists, MemoryKVVal got) = kv.get(MemoryKVKey.wrap(key));
            assertEq(exists, 1, "exists");
            assertEq(MemoryKVVal.unwrap(got), value, "get");
            assertEq(countPair(exported, key, value), 1, "exported exactly once");
        }
    }

    /// A single get/set should behave the same as storage.
    function testSingleGetSet(bytes32 key, bytes32 value) external {
        MemoryKV kv = MEMORY_KV_EMPTY;
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

    /// Any sequence of sets leaves the store holding what storage holds after
    /// the same sets.
    function testSetSequenceMatchesStorage(KV[] memory kvs) external {
        MemoryKV kv = MEMORY_KV_EMPTY;
        for (uint256 i = 0; i < kvs.length; i++) {
            kv = setBoth(kv, sStoreOne, kvs[i]);
        }
        assertMatchesStorage(kv, sStoreOne, kvs, kvs.length);
    }

    /// Two stores built in one frame behave as two storage mappings: each holds
    /// what its own storage holds, the first checked only once the second is
    /// built, so building one disturbs nothing the other answers or exports.
    function testTwoLiveStoresEachMatchTheirOwnStorage(KV[] memory kvsOne, KV[] memory kvsTwo) external {
        uint256 endOne = kvsOne.length > PAIRS_PER_STORE ? PAIRS_PER_STORE : kvsOne.length;
        uint256 endTwo = kvsTwo.length > PAIRS_PER_STORE ? PAIRS_PER_STORE : kvsTwo.length;

        MemoryKV kvOne = MEMORY_KV_EMPTY;
        for (uint256 i = 0; i < endOne; i++) {
            kvOne = setBoth(kvOne, sStoreOne, kvsOne[i]);
        }

        MemoryKV kvTwo = MEMORY_KV_EMPTY;
        for (uint256 i = 0; i < endTwo; i++) {
            kvTwo = setBoth(kvTwo, sStoreTwo, kvsTwo[i]);
        }

        assertMatchesStorage(kvOne, sStoreOne, kvsOne, endOne);
        assertMatchesStorage(kvTwo, sStoreTwo, kvsTwo, endTwo);
    }
}
