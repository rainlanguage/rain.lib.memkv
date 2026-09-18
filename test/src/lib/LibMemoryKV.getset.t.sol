// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {LibPointer, Pointer} from "rain-solmem-0.1.28/src/lib/LibPointer.sol";

import {LibMemoryKV, MemoryKVKey, MemoryKVVal, MemoryKV, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {lengthOf} from "test/lib/LibMemoryKVHandle.sol";

/// @title LibMemoryKVGetSetTest
/// `get` after `set` on the same handle reports what was set. The first insert
/// allocates the header and one node, a later insert allocates one node, and
/// each makes its key readable; an update of a present key allocates nothing
/// and changes that key's value alone.
contract LibMemoryKVGetSetTest is Test {
    /// What the first insert into the empty store allocates: its header, then
    /// its node.
    uint256 internal constant FIRST_INSERT_BYTES = LibMemoryKV.HEADER_BYTES + LibMemoryKV.NODE_BYTES;

    /// A key missing from the empty store reads `(0, 0)`. The first insert
    /// allocates the header and one node, records one pair, and makes the key
    /// read back its value.
    function testFirstInsertAllocatesTheHeaderAndOneNodeAndReadsBack(MemoryKVKey key, MemoryKVVal value) public pure {
        MemoryKV kv = MEMORY_KV_EMPTY;

        (uint256 exists0, MemoryKVVal value0) = LibMemoryKV.get(kv, key);
        assertEq(exists0, 0, "missing before insert");
        assertEq(MemoryKVVal.unwrap(value0), 0, "no value before insert");

        Pointer alloc0 = LibPointer.allocatedMemoryPointer();
        kv = LibMemoryKV.set(kv, key, value);
        Pointer alloc1 = LibPointer.allocatedMemoryPointer();
        assertEq(
            Pointer.unwrap(alloc1),
            Pointer.unwrap(alloc0) + FIRST_INSERT_BYTES,
            "first insert allocates the header and one node"
        );
        assertEq(lengthOf(kv), 2, "one pair");

        (uint256 exists1, MemoryKVVal value1) = LibMemoryKV.get(kv, key);
        assertEq(exists1, 1, "present after insert");
        assertEq(MemoryKVVal.unwrap(value1), MemoryKVVal.unwrap(value), "value after insert");
    }

    /// Two distinct keys: the first insert allocates the header and one node,
    /// the second one node, each update of a present key allocates nothing,
    /// and every read after every step reports the latest value written to
    /// that key, and `(0, 0)` for a key not yet set.
    function testUpdateAllocatesNothingAndLeavesTheOtherKeyAlone(
        MemoryKVKey key0,
        MemoryKVVal value00,
        MemoryKVVal value01,
        MemoryKVKey key1,
        MemoryKVVal value10,
        MemoryKVVal value11
    ) public pure {
        vm.assume(MemoryKVKey.unwrap(key0) != MemoryKVKey.unwrap(key1));

        MemoryKV kv = MEMORY_KV_EMPTY;

        {
            Pointer alloc0 = LibPointer.allocatedMemoryPointer();
            kv = LibMemoryKV.set(kv, key0, value00);
            Pointer alloc1 = LibPointer.allocatedMemoryPointer();
            assertEq(
                Pointer.unwrap(alloc1),
                Pointer.unwrap(alloc0) + FIRST_INSERT_BYTES,
                "insert key0 allocates the header and one node"
            );

            (uint256 exists0, MemoryKVVal get0) = LibMemoryKV.get(kv, key0);
            assertEq(exists0, 1, "key0 present after insert");
            assertEq(MemoryKVVal.unwrap(get0), MemoryKVVal.unwrap(value00), "key0 value after insert");

            (uint256 exists1, MemoryKVVal get1) = LibMemoryKV.get(kv, key1);
            assertEq(exists1, 0, "key1 missing before insert");
            assertEq(MemoryKVVal.unwrap(get1), 0, "key1 no value before insert");
        }

        {
            Pointer alloc2 = LibPointer.allocatedMemoryPointer();
            kv = LibMemoryKV.set(kv, key1, value10);
            Pointer alloc3 = LibPointer.allocatedMemoryPointer();
            assertEq(
                Pointer.unwrap(alloc3),
                Pointer.unwrap(alloc2) + LibMemoryKV.NODE_BYTES,
                "insert key1 allocates one node"
            );

            (uint256 exists2, MemoryKVVal get2) = LibMemoryKV.get(kv, key0);
            assertEq(exists2, 1, "key0 present after key1 insert");
            assertEq(MemoryKVVal.unwrap(get2), MemoryKVVal.unwrap(value00), "key0 unchanged by key1 insert");

            (uint256 exists3, MemoryKVVal get3) = LibMemoryKV.get(kv, key1);
            assertEq(exists3, 1, "key1 present after insert");
            assertEq(MemoryKVVal.unwrap(get3), MemoryKVVal.unwrap(value10), "key1 value after insert");
        }

        {
            Pointer alloc4 = LibPointer.allocatedMemoryPointer();
            kv = LibMemoryKV.set(kv, key1, value11);
            Pointer alloc5 = LibPointer.allocatedMemoryPointer();
            assertEq(Pointer.unwrap(alloc5), Pointer.unwrap(alloc4), "update key1 allocates nothing");

            (uint256 exists4, MemoryKVVal get4) = LibMemoryKV.get(kv, key0);
            assertEq(exists4, 1, "key0 present after key1 update");
            assertEq(MemoryKVVal.unwrap(get4), MemoryKVVal.unwrap(value00), "key0 unchanged by key1 update");

            (uint256 exists5, MemoryKVVal get5) = LibMemoryKV.get(kv, key1);
            assertEq(exists5, 1, "key1 present after update");
            assertEq(MemoryKVVal.unwrap(get5), MemoryKVVal.unwrap(value11), "key1 value after update");
        }

        {
            Pointer alloc6 = LibPointer.allocatedMemoryPointer();
            kv = LibMemoryKV.set(kv, key0, value01);
            Pointer alloc7 = LibPointer.allocatedMemoryPointer();
            assertEq(Pointer.unwrap(alloc7), Pointer.unwrap(alloc6), "update key0 allocates nothing");

            (uint256 exists6, MemoryKVVal get6) = LibMemoryKV.get(kv, key0);
            assertEq(exists6, 1, "key0 present after update");
            assertEq(MemoryKVVal.unwrap(get6), MemoryKVVal.unwrap(value01), "key0 value after update");

            (uint256 exists7, MemoryKVVal get7) = LibMemoryKV.get(kv, key1);
            assertEq(exists7, 1, "key1 present after key0 update");
            assertEq(MemoryKVVal.unwrap(get7), MemoryKVVal.unwrap(value11), "key1 unchanged by key0 update");
        }
    }
}
