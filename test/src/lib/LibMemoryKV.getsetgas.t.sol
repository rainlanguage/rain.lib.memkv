// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {LibMemoryKV, MemoryKV, MemoryKVVal, MemoryKVKey, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";

/// These tests assert nothing on purpose: each exists so that the gas report
/// carries the cost of the gets or sets it performs and nothing else. A set row
/// is named by the sets it performs: an insert sets a key not yet in the store
/// and an update sets a key already in it. A row's figure is a whole-test total
/// and no test asserts one. `LibMemoryKV.gasClaims.t.sol` measures on their own
/// the operations the README gives figures for: the first insert into an empty
/// store, which is the insert in `testSetGas1Insert`; a get of a key alone in
/// its list, which is the get in `testGetHitGas`; a later insert into an empty
/// list; and each key a get or a set walks past. It measures neither the miss
/// nor the update.
contract LibMemoryKVGetSetGasTest is Test {
    /// A get against an empty store. There is no list to walk, so this is a
    /// miss, and its figure is not the cost of a get that finds its key.
    function testGetMissGas() public pure {
        MemoryKV kv = MEMORY_KV_EMPTY;
        LibMemoryKV.get(kv, MemoryKVKey.wrap(0));
    }

    /// A get of a key alone in its list, from the store `testSetGas1Insert`
    /// builds. This entry exceeds that one by the get plus whatever the two
    /// entries' selector dispatch costs differ by.
    function testGetHitGas() public pure {
        MemoryKV kv = MEMORY_KV_EMPTY;
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(1))), MemoryKVVal.wrap(bytes32(uint256(2))));
        LibMemoryKV.get(kv, MemoryKVKey.wrap(bytes32(uint256(1))));
    }

    function testSetGas1Insert() public pure {
        MemoryKV kv = MEMORY_KV_EMPTY;
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(1))), MemoryKVVal.wrap(bytes32(uint256(2))));
    }

    function testSetGas2Inserts() public pure {
        MemoryKV kv = MEMORY_KV_EMPTY;
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(1))), MemoryKVVal.wrap(bytes32(uint256(2))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(3))), MemoryKVVal.wrap(bytes32(uint256(4))));
    }

    function testSetGas3Inserts() public pure {
        MemoryKV kv = MEMORY_KV_EMPTY;
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(1))), MemoryKVVal.wrap(bytes32(uint256(2))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(3))), MemoryKVVal.wrap(bytes32(uint256(4))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(5))), MemoryKVVal.wrap(bytes32(uint256(6))));
    }

    function testSetGas4Inserts() public pure {
        MemoryKV kv = MEMORY_KV_EMPTY;
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(1))), MemoryKVVal.wrap(bytes32(uint256(2))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(3))), MemoryKVVal.wrap(bytes32(uint256(4))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(5))), MemoryKVVal.wrap(bytes32(uint256(6))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(7))), MemoryKVVal.wrap(bytes32(uint256(8))));
    }

    function testSetGas5Inserts() public pure {
        MemoryKV kv = MEMORY_KV_EMPTY;
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(1))), MemoryKVVal.wrap(bytes32(uint256(2))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(3))), MemoryKVVal.wrap(bytes32(uint256(4))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(5))), MemoryKVVal.wrap(bytes32(uint256(6))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(7))), MemoryKVVal.wrap(bytes32(uint256(8))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(9))), MemoryKVVal.wrap(bytes32(uint256(10))));
    }

    function testSetGas10Inserts() public pure {
        MemoryKV kv = MEMORY_KV_EMPTY;
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

    /// An insert, then an update of the key it inserted. The insert builds the
    /// store `testSetGas1Insert` builds, so this entry exceeds that one by the
    /// update plus whatever the two entries' selector dispatch costs differ by.
    function testSetGas1Insert1Update() public pure {
        MemoryKV kv = MEMORY_KV_EMPTY;
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(1))), MemoryKVVal.wrap(bytes32(uint256(2))));
        kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(uint256(1))), MemoryKVVal.wrap(bytes32(uint256(3))));
    }
}
