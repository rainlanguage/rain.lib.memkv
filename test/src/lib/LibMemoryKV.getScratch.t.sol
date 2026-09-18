// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";

/// @title LibMemoryKVGetScratchTest
/// `get` builds its hash preimage in memory, and its assembly is declared
/// `memory-safe`, so the only memory it may write is Solidity's scratch space
/// at `0x00`-`0x3f`. The words either side of it belong to the compiler: the
/// free memory pointer at `0x40` names the next allocation, and the zero slot
/// at `0x60` is the data every empty dynamic array points at. A lookup that
/// built the same hash in one of those instead still answers with the right
/// value, so only the words themselves say it.
contract LibMemoryKVGetScratchTest is Test {
    using LibMemoryKV for MemoryKV;

    /// A lookup leaves `0x40` holding the address it held and `0x60` holding
    /// zero, whether it hits or misses.
    function testGetWritesNothingOutsideScratch(MemoryKVKey key, MemoryKVKey absent, MemoryKVVal value) external pure {
        vm.assume(MemoryKVKey.unwrap(key) != MemoryKVKey.unwrap(absent));
        MemoryKV kv = MEMORY_KV_EMPTY.set(key, value);

        uint256 freeBefore;
        uint256 zeroBefore;
        assembly ("memory-safe") {
            freeBefore := mload(0x40)
            zeroBefore := mload(0x60)
        }

        (uint256 hit, MemoryKVVal got) = kv.get(key);
        (uint256 miss,) = kv.get(absent);

        uint256 freeAfter;
        uint256 zeroAfter;
        assembly ("memory-safe") {
            freeAfter := mload(0x40)
            zeroAfter := mload(0x60)
        }

        assertEq(hit, 1, "the hit that must not move memory has to have happened");
        assertEq(MemoryKVVal.unwrap(got), MemoryKVVal.unwrap(value), "value");
        assertEq(miss, 0, "the miss that must not move memory has to have happened");

        assertEq(zeroBefore, 0, "zero slot before");
        assertEq(freeAfter, freeBefore, "free memory pointer");
        assertEq(zeroAfter, 0, "zero slot");
    }
}
