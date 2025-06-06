// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {LibPointer, Pointer} from "rain.solmem/lib/LibPointer.sol";

import {LibMemoryKV, MemoryKVKey, MemoryKVVal, MemoryKV} from "src/lib/LibMemoryKV.sol";

contract LibMemoryKVGetSetTest is Test {
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
