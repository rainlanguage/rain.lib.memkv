// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";

import {MemoryKVKey} from "src/lib/LibMemoryKV.sol";
import {collidingPairDifferingInBit, slotOf} from "test/lib/LibMemoryKVKeys.sol";

/// @title LibMemoryKVKeysTest
/// The promises `collidingPairDifferingInBit` makes and other tests rest on.
contract LibMemoryKVKeysTest is Test {
    /// The pair the search returns differs in the named bit and nothing else,
    /// the low key holds it clear and the high key set, and both share one
    /// list: the premise the one-bit key compare tests rest on.
    function testCollidingPairDiffersInExactlyTheBit(uint256 seed, uint8 bit) external pure {
        (MemoryKVKey low, MemoryKVKey high) = collidingPairDifferingInBit(seed, bit);
        uint256 lowWord = uint256(MemoryKVKey.unwrap(low));
        uint256 highWord = uint256(MemoryKVKey.unwrap(high));
        uint256 mask = uint256(1) << bit;

        assertEq(lowWord ^ highWord, mask, "differ in exactly the bit");
        assertEq(lowWord & mask, 0, "low key has the bit clear");
        assertEq(highWord & mask, mask, "high key has the bit set");
        assertEq(slotOf(MemoryKVKey.unwrap(low)), slotOf(MemoryKVKey.unwrap(high)), "one list");
    }
}
