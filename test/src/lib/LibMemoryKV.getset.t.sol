// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibPointer, Pointer} from "rain-solmem-0.1.3/src/lib/LibPointer.sol";

import {LibMemoryKV, MemoryKVKey, MemoryKVVal, MemoryKV} from "src/lib/LibMemoryKV.sol";

contract LibMemoryKVGetSetTest is Test {
    function setOverflowExternal(MemoryKV kv, MemoryKVKey key, MemoryKVVal value) external pure returns (MemoryKV) {
        assembly ("memory-safe") {
            // Set the pointer past 0xFFFF to cause an overflow on the next
            // insert.
            mstore(0x40, 0x10000)
        }

        return LibMemoryKV.set(kv, key, value);
    }

    function testSetOverflow(MemoryKVKey key, MemoryKVVal value) external {
        MemoryKV kv = MemoryKV.wrap(0);
        // The next set should revert with a MemoryKVOverflow error.
        vm.expectRevert(abi.encodeWithSelector(LibMemoryKV.MemoryKVOverflow.selector, 0x10000));
        this.setOverflowExternal(kv, key, value);
    }

    /// Insert against an arbitrary free memory pointer so we can drive the
    /// inserted list item's pointer (which `set` takes from the free memory
    /// pointer) to an exact value and probe the overflow boundary precisely.
    /// The returned `kv` encodes the pointer for the inserted slot, so the
    /// caller can assert the exact pointer landed where expected. Note the node
    /// is written into low memory and may subsequently be clobbered, so the
    /// caller MUST NOT read the value back via `get`; the `kv` encoding and the
    /// (non)revert are the observable facts here.
    function setAtPointerExternal(MemoryKV kv, MemoryKVKey key, MemoryKVVal value, uint256 freePtr)
        external
        pure
        returns (MemoryKV)
    {
        assembly ("memory-safe") {
            mstore(0x40, freePtr)
        }
        return LibMemoryKV.set(kv, key, value);
    }

    /// The pointer `0xFFFF` is the MAXIMUM valid 16 bit pointer and an insert
    /// landing exactly on it MUST succeed (NOT revert). This is the lower edge
    /// of the overflow boundary: `pointer > 0xFFFF` reverts, so `0xFFFF` itself
    /// must be accepted. Discriminates against off-by-one mutations of the
    /// boundary (`>` -> `>=`, or `0xFFFF` -> `0xFFFE`), which would wrongly
    /// revert on this exact-max insert.
    function testSetPointerBoundaryMaxAccepted(MemoryKVKey key, MemoryKVVal value) external view {
        MemoryKV kv = MemoryKV.wrap(0);
        // Insert with the free memory pointer at exactly the max valid pointer.
        // This MUST NOT revert and MUST encode the pointer 0xFFFF.
        kv = this.setAtPointerExternal(kv, key, value, 0xFFFF);

        // The inserted list item must live at exactly 0xFFFF, so the slot for
        // this key must encode the pointer 0xFFFF.
        uint256 raw = MemoryKV.unwrap(kv);
        bool found = false;
        for (uint256 bitOffset = 0; bitOffset < 0xf0; bitOffset += 0x10) {
            if (((raw >> bitOffset) & 0xFFFF) == 0xFFFF) {
                found = true;
            }
        }
        assertTrue(found, "max pointer 0xFFFF must be encoded into kv");

        // The length must be exactly 2 words (one key/value pair).
        assertEq(raw >> 0xf0, 2, "length");
    }

    /// One below the max pointer (`0xFFFE`) must also be accepted and encode
    /// the exact pointer. Guards the boundary from the other side so a
    /// `0xFFFF` -> `0xFFFE` mutation (which would wrongly revert here) is killed.
    function testSetPointerBoundaryBelowMaxAccepted(MemoryKVKey key, MemoryKVVal value) external view {
        MemoryKV kv = MemoryKV.wrap(0);
        kv = this.setAtPointerExternal(kv, key, value, 0xFFFE);

        uint256 raw = MemoryKV.unwrap(kv);
        bool found = false;
        for (uint256 bitOffset = 0; bitOffset < 0xf0; bitOffset += 0x10) {
            if (((raw >> bitOffset) & 0xFFFF) == 0xFFFE) {
                found = true;
            }
        }
        assertTrue(found, "pointer 0xFFFE must be encoded into kv");
        assertEq(raw >> 0xf0, 2, "length");
    }

    /// The first pointer past the max (`0x10000`) MUST revert with the exact
    /// overflowing pointer value. This is the upper edge of the boundary and
    /// pins the exact revert payload so the boundary cannot silently move up.
    function testSetPointerBoundaryOverflowReverts(MemoryKVKey key, MemoryKVVal value) external {
        MemoryKV kv = MemoryKV.wrap(0);
        vm.expectRevert(abi.encodeWithSelector(LibMemoryKV.MemoryKVOverflow.selector, 0x10000));
        this.setAtPointerExternal(kv, key, value, 0x10000);
    }

    function testSetGet0(MemoryKVKey key, MemoryKVVal value) public pure {
        MemoryKV kv = MemoryKV.wrap(0);

        // Initially the key will not be set.
        (uint256 exists0, MemoryKVVal value0) = LibMemoryKV.get(kv, key);

        assertEq(0, exists0);
        assertEq(0, MemoryKVVal.unwrap(value0));

        Pointer alloc0 = LibPointer.allocatedMemoryPointer();
        kv = LibMemoryKV.set(kv, key, value);
        Pointer alloc1 = LibPointer.allocatedMemoryPointer();
        assertTrue(Pointer.unwrap(alloc1) == Pointer.unwrap(alloc0) + 0x60);

        // Now the key is set.
        assertTrue(MemoryKV.unwrap(kv) > 0);
        (uint256 exists1, MemoryKVVal value1) = LibMemoryKV.get(kv, key);

        assertEq(1, exists1);
        assertEq(MemoryKVVal.unwrap(value1), MemoryKVVal.unwrap(value));
    }

    function testSetGetSimple0() public pure {
        MemoryKV kv = MemoryKV.wrap(0);
        MemoryKVKey key0 = MemoryKVKey.wrap(bytes32(uint256(1)));
        MemoryKVVal value0 = MemoryKVVal.wrap(bytes32(uint256(2)));
        kv = LibMemoryKV.set(kv, key0, value0);
        (uint256 exists0, MemoryKVVal get0) = LibMemoryKV.get(kv, key0);

        assertEq(1, exists0);
        assertEq(MemoryKVVal.unwrap(get0), MemoryKVVal.unwrap(value0));

        MemoryKVKey key1 = MemoryKVKey.wrap(bytes32(uint256(3)));
        MemoryKVVal value1 = MemoryKVVal.wrap(bytes32(uint256(4)));
        kv = LibMemoryKV.set(kv, key1, value1);
        (uint256 exists1, MemoryKVVal get1) = LibMemoryKV.get(kv, key1);

        assertEq(1, exists1);
        assertEq(MemoryKVVal.unwrap(get1), MemoryKVVal.unwrap(value1));

        MemoryKVVal value2 = MemoryKVVal.wrap(bytes32(uint256(5)));
        kv = LibMemoryKV.set(kv, key0, value2);
        (uint256 exists2, MemoryKVVal get2) = LibMemoryKV.get(kv, key0);

        assertEq(1, exists2);
        assertEq(MemoryKVVal.unwrap(get2), MemoryKVVal.unwrap(value2));

        (uint256 exists3, MemoryKVVal get3) = LibMemoryKV.get(kv, key1);

        assertEq(1, exists3);
        assertEq(MemoryKVVal.unwrap(get3), MemoryKVVal.unwrap(value1));
    }

    function testSetGetSimple1() public pure {
        MemoryKV kv = MemoryKV.wrap(0);
        MemoryKVKey key0 = MemoryKVKey.wrap(bytes32(uint256(5808)));
        MemoryKVVal value00 = MemoryKVVal.wrap(bytes32(uint256(720)));
        kv = LibMemoryKV.set(kv, key0, value00);
        (uint256 exists0, MemoryKVVal get0) = LibMemoryKV.get(kv, key0);
        assertEq(1, exists0);
        assertEq(MemoryKVVal.unwrap(get0), MemoryKVVal.unwrap(value00));

        MemoryKVKey key1 = MemoryKVKey.wrap(bytes32(uint256(4571)));
        MemoryKVVal value10 = MemoryKVVal.wrap(bytes32(uint256(4142)));
        kv = LibMemoryKV.set(kv, key1, value10);
        (uint256 exists1, MemoryKVVal get1) = LibMemoryKV.get(kv, key0);
        assertEq(1, exists1);
        assertEq(MemoryKVVal.unwrap(get1), MemoryKVVal.unwrap(value00));

        (uint256 exists2, MemoryKVVal get2) = LibMemoryKV.get(kv, key1);
        assertEq(1, exists2);
        assertEq(MemoryKVVal.unwrap(get2), MemoryKVVal.unwrap(value10));
    }

    function testSetGetVal1(
        MemoryKVKey key0,
        MemoryKVVal value00,
        MemoryKVVal value01,
        MemoryKVKey key1,
        MemoryKVVal value10,
        MemoryKVVal value11
    ) public pure {
        vm.assume(MemoryKVKey.unwrap(key0) != MemoryKVKey.unwrap(key1));

        MemoryKV kv = MemoryKV.wrap(0);

        {
            Pointer alloc0 = LibPointer.allocatedMemoryPointer();
            kv = LibMemoryKV.set(kv, key0, value00);
            Pointer alloc1 = LibPointer.allocatedMemoryPointer();
            assertTrue(Pointer.unwrap(alloc1) == Pointer.unwrap(alloc0) + 0x60);

            (uint256 expect0, MemoryKVVal get0) = LibMemoryKV.get(kv, key0);
            assertEq(1, expect0);
            assertEq(MemoryKVVal.unwrap(get0), MemoryKVVal.unwrap(value00));

            (uint256 expect1, MemoryKVVal get1) = LibMemoryKV.get(kv, key1);
            assertEq(0, expect1);
            assertEq(MemoryKVVal.unwrap(get1), 0);
        }

        {
            Pointer alloc2 = LibPointer.allocatedMemoryPointer();
            kv = LibMemoryKV.set(kv, key1, value10);
            Pointer alloc3 = LibPointer.allocatedMemoryPointer();
            assertTrue(Pointer.unwrap(alloc3) == Pointer.unwrap(alloc2) + 0x60);

            (uint256 expect2, MemoryKVVal get2) = LibMemoryKV.get(kv, key0);
            assertEq(1, expect2);
            assertEq(MemoryKVVal.unwrap(get2), MemoryKVVal.unwrap(value00));

            (uint256 expect3, MemoryKVVal get3) = LibMemoryKV.get(kv, key1);
            assertEq(1, expect3);
            assertEq(MemoryKVVal.unwrap(get3), MemoryKVVal.unwrap(value10));
        }

        {
            Pointer alloc4 = LibPointer.allocatedMemoryPointer();
            kv = LibMemoryKV.set(kv, key1, value11);
            Pointer alloc5 = LibPointer.allocatedMemoryPointer();

            // No alloc on update.
            assertTrue(Pointer.unwrap(alloc4) == Pointer.unwrap(alloc5));
            (uint256 expect4, MemoryKVVal get4) = LibMemoryKV.get(kv, key0);
            assertEq(1, expect4);
            assertEq(MemoryKVVal.unwrap(get4), MemoryKVVal.unwrap(value00));

            (uint256 expect5, MemoryKVVal get5) = LibMemoryKV.get(kv, key1);
            assertEq(1, expect5);
            assertEq(MemoryKVVal.unwrap(get5), MemoryKVVal.unwrap(value11));
        }

        {
            Pointer alloc6 = LibPointer.allocatedMemoryPointer();

            kv = LibMemoryKV.set(kv, key0, value01);
            Pointer alloc7 = LibPointer.allocatedMemoryPointer();

            // No alloc on update.
            assertTrue(Pointer.unwrap(alloc6) == Pointer.unwrap(alloc7));

            (uint256 expect6, MemoryKVVal get6) = LibMemoryKV.get(kv, key0);
            assertEq(1, expect6);
            assertEq(MemoryKVVal.unwrap(get6), MemoryKVVal.unwrap(value01));

            (uint256 expect7, MemoryKVVal get7) = LibMemoryKV.get(kv, key1);
            assertEq(1, expect7);
            assertEq(MemoryKVVal.unwrap(get7), MemoryKVVal.unwrap(value11));
        }
    }
}
