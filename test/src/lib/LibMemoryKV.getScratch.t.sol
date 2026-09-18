// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {LibPointer, Pointer} from "rain-solmem-0.1.28/src/lib/LibPointer.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";

/// @title LibMemoryKVGetScratchTest
/// `get` builds its hash preimage in scratch space at `0x00`-`0x3f`. Its
/// assembly is declared `memory-safe`, which forbids two writes just above
/// scratch: the free memory pointer at `0x40` may only move to a valid
/// allocation, and the zero slot at `0x60`, the data every empty dynamic array
/// points at, may never change. A lookup that built the same hash in either
/// word instead still answers with the right value, so only the words
/// themselves say it. That `get` leaves every allocated byte above them
/// unchanged is pinned by `LibMemoryKVGetWalkTest`.
contract LibMemoryKVGetScratchTest is Test {
    using LibMemoryKV for MemoryKV;

    /// The zero slot, which `memory-safe` assembly never writes.
    Pointer internal constant ZERO_SLOT = Pointer.wrap(0x60);

    /// A lookup leaves `0x40` holding the address it held and `0x60` holding
    /// zero, whether it hits or misses.
    function testGetLeavesFreePointerAndZeroSlotAlone(MemoryKVKey key, MemoryKVKey absent, MemoryKVVal value)
        external
        pure
    {
        vm.assume(MemoryKVKey.unwrap(key) != MemoryKVKey.unwrap(absent));
        MemoryKV kv = MEMORY_KV_EMPTY.set(key, value);

        uint256 freeBefore = Pointer.unwrap(LibPointer.allocatedMemoryPointer());
        uint256 zeroBefore = uint256(LibPointer.unsafeReadWord(ZERO_SLOT));

        (uint256 hit, MemoryKVVal got) = kv.get(key);
        (uint256 miss,) = kv.get(absent);

        uint256 freeAfter = Pointer.unwrap(LibPointer.allocatedMemoryPointer());
        uint256 zeroAfter = uint256(LibPointer.unsafeReadWord(ZERO_SLOT));

        assertEq(hit, 1, "the hit that must not move memory has to have happened");
        assertEq(MemoryKVVal.unwrap(got), MemoryKVVal.unwrap(value), "value");
        assertEq(miss, 0, "the miss that must not move memory has to have happened");

        assertEq(zeroBefore, 0, "zero slot before");
        assertEq(freeAfter, freeBefore, "free memory pointer");
        assertEq(zeroAfter, 0, "zero slot");
    }
}
