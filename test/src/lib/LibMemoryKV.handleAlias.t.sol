// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {val, keyFor} from "test/lib/LibMemoryKVKeys.sol";
import {lengthOf} from "test/lib/LibMemoryKVHandle.sol";
import {assertValue} from "test/lib/LibMemoryKVAssert.sol";

/// @title LibMemoryKVHandleAliasTest
/// A `MemoryKV` is a value type, so every assignment of one copies it and
/// Solidity says nothing about the list items the copies go on sharing. These
/// tests pin what those copies report: an update reaches every handle holding
/// the key, an insert reaches only the handle `set` returned, and
/// `toBytes32Array` is the only way to hold values that a later update cannot
/// move. Each case states the VALUE a handle must report, so a store that
/// started copying on write, or one that stopped sharing items, is a different
/// number rather than a revert.
contract LibMemoryKVHandleAliasTest is Test {
    using LibMemoryKV for MemoryKV;

    /// An update through a handle is visible through a handle copied BEFORE the
    /// update, whose own bits never changed. The older handle reads 999 even
    /// though 111 is the only value it ever saw written.
    function testUpdateIsVisibleThroughAnOlderHandle() external pure {
        MemoryKV a = MEMORY_KV_EMPTY.set(keyFor(1), val(111));
        uint256 aBits = MemoryKV.unwrap(a);
        assertValue(a, keyFor(1), 111, "a before");

        MemoryKV b = a.set(keyFor(2), val(222));
        MemoryKV c = b.set(keyFor(1), val(999));

        // The update allocated nothing and moved no bits, in b or in a.
        assertEq(MemoryKV.unwrap(c), MemoryKV.unwrap(b), "c bits");
        assertEq(MemoryKV.unwrap(a), aBits, "a bits");

        assertValue(a, keyFor(1), 999, "a after");
        assertValue(b, keyFor(1), 999, "b after");
        assertEq(lengthOf(a), 2, "a length");
        assertEq(lengthOf(b), 4, "b length");
    }

    /// An insert is visible only through the handle `set` returned. The older
    /// handle keeps the value and the word count it had, and does not see the
    /// new key at all.
    function testInsertIsVisibleOnlyThroughTheReturnedHandle() external pure {
        MemoryKV a = MEMORY_KV_EMPTY.set(keyFor(1), val(10));
        MemoryKV b = a.set(keyFor(2), val(20));

        assertValue(b, keyFor(1), 10, "b old key");
        assertValue(b, keyFor(2), 20, "b new key");
        assertEq(lengthOf(b), 4, "b length");

        assertFalse(a.has(keyFor(2)), "a new key");
        assertValue(a, keyFor(1), 10, "a old key");
        assertEq(lengthOf(a), 2, "a length");
    }

    /// Two handles branched off one store are not two stores. An update made
    /// down one branch is read by the other, which is the cross-talk a caller
    /// exploring two paths would be exposed to. The keys each branch inserted
    /// stay private to it.
    function testUpdateCrossesBetweenBranchedHandles() external pure {
        MemoryKV a = MEMORY_KV_EMPTY.set(keyFor(1), val(1));
        MemoryKV left = a.set(keyFor(2), val(2));
        MemoryKV right = a.set(keyFor(3), val(3));

        left = left.set(keyFor(1), val(0xFEED));

        assertValue(right, keyFor(1), 0xFEED, "right shared key");
        assertValue(a, keyFor(1), 0xFEED, "a shared key");
        assertFalse(right.has(keyFor(2)), "right sees left insert");
        assertFalse(left.has(keyFor(3)), "left sees right insert");
    }

    /// `toBytes32Array` copies the values out, so an update afterwards cannot
    /// move what the array holds. This is the difference between an export and
    /// a retained handle: the handle below moves to 999, the array does not.
    function testExportedArrayDoesNotMoveUnderALaterUpdate() external pure {
        MemoryKV a = MEMORY_KV_EMPTY.set(keyFor(1), val(111));
        bytes32[] memory snapshot = a.toBytes32Array();
        assertEq(snapshot.length, 2, "snapshot length");
        assertEq(uint256(snapshot[0]), 1, "snapshot key");
        assertEq(uint256(snapshot[1]), 111, "snapshot value");

        MemoryKV b = a.set(keyFor(2), val(222)).set(keyFor(1), val(999));

        assertEq(uint256(snapshot[1]), 111, "snapshot after update");
        assertValue(a, keyFor(1), 999, "handle after update");
        assertValue(b, keyFor(1), 999, "b after update");
    }

    /// The same asymmetry over arbitrary keys and values: whatever the hash
    /// does with them, the update reaches the older handle and the insert does
    /// not. `second` is constrained away from `first` so the second `set` is an
    /// insert rather than a second update.
    function testAsymmetryHoldsForAnyKeys(
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
        assertEq(lengthOf(a), 2, "a length");
        assertEq(lengthOf(b), 4, "b length");

        // Update: visible through the older handle.
        (uint256 exists, MemoryKVVal got) = a.get(first);
        assertEq(exists, 1, "a first exists");
        assertEq(MemoryKVVal.unwrap(got), MemoryKVVal.unwrap(updated), "a first value");

        // Insert: invisible through the older handle.
        assertFalse(a.has(second), "a second");
        assertTrue(b.has(second), "b second");
    }
}
