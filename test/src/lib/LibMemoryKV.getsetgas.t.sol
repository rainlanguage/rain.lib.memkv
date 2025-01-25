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
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(1))), MemoryKVVal.wrap(bytes32(uint256(2))));
    }

    function testSetGas1() public pure {
        MemoryKV kv = MemoryKV.wrap(0);
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(1))), MemoryKVVal.wrap(bytes32(uint256(2))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(3))), MemoryKVVal.wrap(bytes32(uint256(4))));
    }

    function testSetGas3() public pure {
        MemoryKV kv = MemoryKV.wrap(0);
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(1))), MemoryKVVal.wrap(bytes32(uint256(2))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(3))), MemoryKVVal.wrap(bytes32(uint256(4))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(5))), MemoryKVVal.wrap(bytes32(uint256(6))));
    }

    function testSetGas4() public pure {
        MemoryKV kv = MemoryKV.wrap(0);
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(1))), MemoryKVVal.wrap(bytes32(uint256(2))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(3))), MemoryKVVal.wrap(bytes32(uint256(4))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(5))), MemoryKVVal.wrap(bytes32(uint256(6))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(7))), MemoryKVVal.wrap(bytes32(uint256(8))));
    }

    function testSetGas5() public pure {
        MemoryKV kv = MemoryKV.wrap(0);
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(1))), MemoryKVVal.wrap(bytes32(uint256(2))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(3))), MemoryKVVal.wrap(bytes32(uint256(4))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(5))), MemoryKVVal.wrap(bytes32(uint256(6))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(7))), MemoryKVVal.wrap(bytes32(uint256(8))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(9))), MemoryKVVal.wrap(bytes32(uint256(10))));
    }

    function testSetGas6() public pure {
        MemoryKV kv = MemoryKV.wrap(0);
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(1))), MemoryKVVal.wrap(bytes32(uint256(2))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(3))), MemoryKVVal.wrap(bytes32(uint256(4))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(5))), MemoryKVVal.wrap(bytes32(uint256(6))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(7))), MemoryKVVal.wrap(bytes32(uint256(8))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(9))), MemoryKVVal.wrap(bytes32(uint256(10))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(10))), MemoryKVVal.wrap(bytes32(uint256(2))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(30))), MemoryKVVal.wrap(bytes32(uint256(4))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(50))), MemoryKVVal.wrap(bytes32(uint256(6))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(70))), MemoryKVVal.wrap(bytes32(uint256(8))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(90))), MemoryKVVal.wrap(bytes32(uint256(10))));
    }
}
