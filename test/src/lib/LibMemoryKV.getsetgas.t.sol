// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";

import {LibMemoryKV, MemoryKV, MemoryKVVal, MemoryKVKey} from "src/lib/LibMemoryKV.sol";

contract LibMemoryKVGetSetGasTest is Test {
    function testGetGas() public pure {
        MemoryKV kv = MemoryKV.wrap(0);
        LibMemoryKV.get(kv, MemoryKVKey.wrap(0));
    }

    function testSetGas0() public pure {
        MemoryKV kv = MemoryKV.wrap(0);
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(1), MemoryKVVal.wrap(2));
    }

    function testSetGas1() public pure {
        MemoryKV kv = MemoryKV.wrap(0);
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(1), MemoryKVVal.wrap(2));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(3), MemoryKVVal.wrap(4));
    }

    function testSetGas3() public pure {
        MemoryKV kv = MemoryKV.wrap(0);
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(1), MemoryKVVal.wrap(2));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(3), MemoryKVVal.wrap(4));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(5), MemoryKVVal.wrap(6));
    }

    function testSetGas4() public pure {
        MemoryKV kv = MemoryKV.wrap(0);
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(1), MemoryKVVal.wrap(2));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(3), MemoryKVVal.wrap(4));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(5), MemoryKVVal.wrap(6));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(7), MemoryKVVal.wrap(8));
    }

    function testSetGas5() public pure {
        MemoryKV kv = MemoryKV.wrap(0);
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(1), MemoryKVVal.wrap(2));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(3), MemoryKVVal.wrap(4));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(5), MemoryKVVal.wrap(6));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(7), MemoryKVVal.wrap(8));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(9), MemoryKVVal.wrap(10));
    }

    function testSetGas6() public pure {
        MemoryKV kv = MemoryKV.wrap(0);
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(1), MemoryKVVal.wrap(2));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(3), MemoryKVVal.wrap(4));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(5), MemoryKVVal.wrap(6));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(7), MemoryKVVal.wrap(8));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(9), MemoryKVVal.wrap(10));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(10), MemoryKVVal.wrap(2));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(30), MemoryKVVal.wrap(4));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(50), MemoryKVVal.wrap(6));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(70), MemoryKVVal.wrap(8));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(90), MemoryKVVal.wrap(10));
    }
}
