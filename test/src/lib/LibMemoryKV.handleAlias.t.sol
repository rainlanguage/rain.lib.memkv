// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {val, keyFor} from "test/lib/LibMemoryKVKeys.sol";
import {lengthOf} from "test/lib/LibMemoryKVHandle.sol";
import {assertValue} from "test/lib/LibMemoryKVAssert.sol";

/// @title LibMemoryKVHandleAliasTest
/// A `MemoryKV` is a value type, so every assignment of one copies it, and
/// Solidity says nothing about the store the copies go on sharing. These tests
/// pin what the copies report: once a store is non-empty every copy of its
/// handle is that one store, so an update AND an insert through any copy
/// reach every copy, and there is one word count. Only the empty handle
/// branches, because every `set` on it allocates a header of its own.
/// `toBytes32Array` is the only way to hold pairs that a later `set` cannot
/// move. Each case states the VALUE a handle must report.
contract LibMemoryKVHandleAliasTest is Test {
    using LibMemoryKV for MemoryKV;

    /// An update through a handle is visible through a handle copied BEFORE
    /// the update. The older copy reads 999 even though 111 is the only value
    /// it ever saw written, and no copy's word moves.
    function testUpdateIsVisibleThroughAnOlderHandle() external pure {
        MemoryKV a = MEMORY_KV_EMPTY.set(keyFor(1), val(111));
        uint256 aBits = MemoryKV.unwrap(a);
        assertValue(a, keyFor(1), 111, "a before");

        MemoryKV b = a.set(keyFor(2), val(222));
        MemoryKV c = b.set(keyFor(1), val(999));

        assertEq(MemoryKV.unwrap(b), aBits, "b bits");
        assertEq(MemoryKV.unwrap(c), aBits, "c bits");

        assertValue(a, keyFor(1), 999, "a after");
        assertValue(b, keyFor(1), 999, "b after");
        assertEq(lengthOf(a), 4, "a length");
        assertEq(lengthOf(b), 4, "b length");
    }

    /// An insert is visible through a handle copied BEFORE the insert, and the
    /// older copy reports the count the insert raised.
    function testInsertIsVisibleThroughAnOlderHandle() external pure {
        MemoryKV a = MEMORY_KV_EMPTY.set(keyFor(1), val(10));
        MemoryKV b = a.set(keyFor(2), val(20));

        assertEq(MemoryKV.unwrap(b), MemoryKV.unwrap(a), "one word");
        assertValue(a, keyFor(1), 10, "a old key");
        assertValue(a, keyFor(2), 20, "a new key");
        assertValue(b, keyFor(1), 10, "b old key");
        assertValue(b, keyFor(2), 20, "b new key");
        assertEq(lengthOf(a), 4, "a length");
        assertEq(lengthOf(b), 4, "b length");
    }

    /// Two handles branched off one non-empty store are not two stores. Each
    /// branch reads the other's inserts and updates, which is the cross-talk a
    /// caller exploring two paths is exposed to.
    function testBranchesOfANonEmptyStoreAreOneStore() external pure {
        MemoryKV a = MEMORY_KV_EMPTY.set(keyFor(1), val(1));
        MemoryKV left = a.set(keyFor(2), val(2));
        MemoryKV right = a.set(keyFor(3), val(3));

        left = left.set(keyFor(1), val(0xFEED));

        assertValue(right, keyFor(1), 0xFEED, "right sees left's update");
        assertValue(a, keyFor(1), 0xFEED, "a sees left's update");
        assertValue(right, keyFor(2), 2, "right sees left's insert");
        assertValue(left, keyFor(3), 3, "left sees right's insert");
        assertEq(lengthOf(left), 6, "left length");
        assertEq(lengthOf(right), 6, "right length");
    }

    /// The empty handle is the one copy that branches: two inserts through it
    /// allocate two headers, and each store holds only its own key.
    function testTheEmptyHandleBranches() external pure {
        MemoryKV empty = MEMORY_KV_EMPTY;
        MemoryKV left = empty.set(keyFor(1), val(1));
        MemoryKV right = empty.set(keyFor(2), val(2));

        assertTrue(MemoryKV.unwrap(left) != MemoryKV.unwrap(right), "two headers");
        assertEq(MemoryKV.unwrap(empty), 0, "the empty handle stays empty");
        assertFalse(left.has(keyFor(2)), "left does not see right's key");
        assertFalse(right.has(keyFor(1)), "right does not see left's key");
        assertEq(lengthOf(left), 2, "left length");
        assertEq(lengthOf(right), 2, "right length");
    }

    /// `toBytes32Array` copies the pairs out, so a later update or insert
    /// cannot move what the array holds. This is the difference between an
    /// export and a retained handle: the handle below moves to 999 and gains a
    /// key, the array does neither.
    function testExportedArrayDoesNotMoveUnderALaterSet() external pure {
        MemoryKV a = MEMORY_KV_EMPTY.set(keyFor(1), val(111));
        bytes32[] memory snapshot = a.toBytes32Array();
        assertEq(snapshot.length, 2, "snapshot length");
        assertEq(uint256(snapshot[0]), 1, "snapshot key");
        assertEq(uint256(snapshot[1]), 111, "snapshot value");

        MemoryKV b = a.set(keyFor(2), val(222)).set(keyFor(1), val(999));

        assertEq(snapshot.length, 2, "snapshot length after the insert");
        assertEq(uint256(snapshot[0]), 1, "snapshot key after the update");
        assertEq(uint256(snapshot[1]), 111, "snapshot value after the update");
        assertValue(a, keyFor(1), 999, "handle after update");
        assertValue(b, keyFor(1), 999, "b after update");
        assertEq(a.toBytes32Array().length, 4, "a fresh export sees the insert");
    }

    /// The same over arbitrary keys and values: whatever the hash does with
    /// them, the insert and the update both reach the older handle, and every
    /// copy is one word. `second` is constrained away from `first` so the
    /// second `set` is an insert rather than a second update.
    function testEveryCopyIsOneStoreForAnyKeys(
        MemoryKVKey first,
        MemoryKVKey second,
        MemoryKVVal initial,
        MemoryKVVal updated
    ) external pure {
        vm.assume(MemoryKVKey.unwrap(first) != MemoryKVKey.unwrap(second));
        vm.assume(MemoryKVVal.unwrap(initial) != MemoryKVVal.unwrap(updated));

        MemoryKV a = MEMORY_KV_EMPTY.set(first, initial);
        uint256 aBits = MemoryKV.unwrap(a);

        MemoryKV b = a.set(second, updated).set(first, updated);

        assertEq(MemoryKV.unwrap(a), aBits, "a bits");
        assertEq(MemoryKV.unwrap(b), aBits, "b bits");
        assertEq(lengthOf(a), 4, "a length");
        assertEq(lengthOf(b), 4, "b length");

        // Update: visible through the older handle.
        (uint256 exists, MemoryKVVal got) = a.get(first);
        assertEq(exists, 1, "a first exists");
        assertEq(MemoryKVVal.unwrap(got), MemoryKVVal.unwrap(updated), "a first value");

        // Insert: visible through the older handle too.
        (exists, got) = a.get(second);
        assertEq(exists, 1, "a second exists");
        assertEq(MemoryKVVal.unwrap(got), MemoryKVVal.unwrap(updated), "a second value");
    }
}
