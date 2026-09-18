// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";

import {LibPointer, Pointer} from "rain-solmem-0.1.28/src/lib/LibPointer.sol";

import {LibMemoryKV, MemoryKVKey, MemoryKVVal, MemoryKV, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {SetAtFreePointer} from "test/lib/SetAtFreePointer.sol";
import {collidingKey} from "test/lib/LibMemoryKVKeys.sol";
import {headOf, lengthOf} from "test/lib/LibMemoryKVHandle.sol";

/// @title LibMemoryKVGetSetTest
/// `get` after `set` on the same handle reports what was set. An insert
/// allocates exactly one node and makes its key readable, and an update of a
/// present key allocates nothing and changes that key's value alone. A node's
/// head pointer must fit its `LibMemoryKV.SLOT_BITS` wide slot: `set` reverts
/// with `MemoryKVOverflow` for one that does not, and `get` reads the node
/// words that lie above the bound.
contract LibMemoryKVGetSetTest is Test, SetAtFreePointer {
    /// Insert at an exact free memory pointer and read the key back inside the
    /// SAME call frame, as the node only exists in that frame's memory.
    function setAtPointerThenGetExternal(MemoryKVKey key, MemoryKVVal value, uint256 freePointer)
        external
        pure
        returns (uint256, MemoryKVVal)
    {
        MemoryKV kv = setAtFreePointerInFrame(MEMORY_KV_EMPTY, key, value, freePointer);
        return LibMemoryKV.get(kv, key);
    }

    /// Insert `first` normally, then `second` at an exact free memory pointer
    /// so that one list holds both with `second` at its head, and read `first`
    /// back inside the SAME call frame.
    function insertPairThenGetFirstExternal(
        MemoryKVKey first,
        MemoryKVKey second,
        MemoryKVVal value,
        uint256 headPointer
    ) external pure returns (uint256, MemoryKVVal) {
        MemoryKV kv = LibMemoryKV.set(MEMORY_KV_EMPTY, first, value);
        kv = setAtFreePointerInFrame(kv, second, MemoryKVVal.wrap(0), headPointer);
        return LibMemoryKV.get(kv, first);
    }

    /// `LibMemoryKV.POINTER_MASK` is the widest head pointer a slot holds, so an
    /// insert whose node starts exactly there succeeds and the slot encodes
    /// `LibMemoryKV.POINTER_MASK`.
    function testSetPointerBoundaryMaxAccepted(MemoryKVKey key, MemoryKVVal value) external view {
        MemoryKV kv = this.setAtFreePointer(MEMORY_KV_EMPTY, key, value, LibMemoryKV.POINTER_MASK);

        assertEq(headOf(kv, key), LibMemoryKV.POINTER_MASK, "the max pointer must be encoded into this key's slot");
        assertEq(lengthOf(kv), 2, "length");
    }

    /// The first pointer past the bound, `LibMemoryKV.POINTER_MASK + 1`, reverts
    /// `MemoryKVOverflow` carrying that pointer, not the bound it crossed.
    function testSetPointerBoundaryOverflowReverts(MemoryKVKey key, MemoryKVVal value) external {
        vm.expectRevert(abi.encodeWithSelector(LibMemoryKV.MemoryKVOverflow.selector, LibMemoryKV.POINTER_MASK + 1));
        this.setAtFreePointer(MEMORY_KV_EMPTY, key, value, LibMemoryKV.POINTER_MASK + 1);
    }

    /// The bound is on the node's HEAD pointer alone. A node inserted at the
    /// maximum head pointer `LibMemoryKV.POINTER_MASK` holds its value word at
    /// `LibMemoryKV.POINTER_MASK + 0x20`, above the bound, and `get` reads it:
    /// node fields are reached by full width arithmetic from the head, not
    /// through `LibMemoryKV.SLOT_BITS` wide pointers. A `get` that truncated a
    /// field address to `LibMemoryKV.SLOT_BITS` bits is indistinguishable from
    /// a correct one for every node that fits entirely under the bound.
    function testGetReadsAValueWordAboveTheBound(MemoryKVKey key, MemoryKVVal value) external view {
        (uint256 exists, MemoryKVVal got) = this.setAtPointerThenGetExternal(key, value, LibMemoryKV.POINTER_MASK);

        assertEq(exists, 1, "a node at the maximum head pointer exists");
        assertEq(MemoryKVVal.unwrap(got), MemoryKVVal.unwrap(value), "the value word above the bound reads back");
    }

    /// The same for the next pointer word. The second node's head is
    /// `LibMemoryKV.POINTER_MASK + 1 - 0x40`, which fits the bound, so its next
    /// word lands at exactly `LibMemoryKV.POINTER_MASK + 1` and the walk from
    /// that node down to the first one has to read across the bound to find it.
    function testGetWalksThroughANextWordAboveTheBound(MemoryKVKey key, MemoryKVVal value) external view {
        (uint256 exists, MemoryKVVal got) =
            this.insertPairThenGetFirstExternal(key, collidingKey(key), value, LibMemoryKV.POINTER_MASK + 1 - 0x40);

        assertEq(exists, 1, "the walk reaches the first key through a next word above the bound");
        assertEq(MemoryKVVal.unwrap(got), MemoryKVVal.unwrap(value), "the first key's value survives the walk");
    }

    /// A key missing from the empty store reads `(0, 0)`. One insert allocates
    /// exactly one node, records one pair, and makes the key read back its
    /// value.
    function testInsertAllocatesOneNodeAndReadsBack(MemoryKVKey key, MemoryKVVal value) public pure {
        MemoryKV kv = MEMORY_KV_EMPTY;

        (uint256 exists0, MemoryKVVal value0) = LibMemoryKV.get(kv, key);
        assertEq(exists0, 0, "missing before insert");
        assertEq(MemoryKVVal.unwrap(value0), 0, "no value before insert");

        Pointer alloc0 = LibPointer.allocatedMemoryPointer();
        kv = LibMemoryKV.set(kv, key, value);
        Pointer alloc1 = LibPointer.allocatedMemoryPointer();
        assertEq(Pointer.unwrap(alloc1), Pointer.unwrap(alloc0) + LibMemoryKV.NODE_BYTES, "insert allocates one node");
        assertEq(lengthOf(kv), 2, "one pair");

        (uint256 exists1, MemoryKVVal value1) = LibMemoryKV.get(kv, key);
        assertEq(exists1, 1, "present after insert");
        assertEq(MemoryKVVal.unwrap(value1), MemoryKVVal.unwrap(value), "value after insert");
    }

    /// Two distinct keys: each insert allocates one node, each update of a
    /// present key allocates nothing, and every read after every step reports
    /// the latest value written to that key, and `(0, 0)` for a key not yet
    /// set.
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
                Pointer.unwrap(alloc0) + LibMemoryKV.NODE_BYTES,
                "insert key0 allocates one node"
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
