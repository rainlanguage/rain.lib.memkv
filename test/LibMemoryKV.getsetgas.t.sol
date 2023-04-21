// SPDX-License-Identifier: CAL
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "sol.lib.memory/LibMemory.sol";

import "../src/LibMemoryKV.sol";

contract LibMemoryKVGetSetGasTest is Test {
    function testGetGas() public pure {
        MemoryKV kv = MemoryKV.wrap(0);
        LibMemoryKV.get(kv, MemoryKVKey.wrap(0));
    }
}