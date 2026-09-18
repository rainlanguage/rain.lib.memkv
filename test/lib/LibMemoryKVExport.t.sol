// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {countPair} from "test/lib/LibMemoryKVExport.sol";

/// @title LibMemoryKVExportTest
/// The promises `countPair` makes and other tests rest on.
contract LibMemoryKVExportTest is Test {
    /// Only a key word at an even index followed by the value word counts: a
    /// key with another value does not, and neither does a key word in a value
    /// position followed by the value, nor a value word in a key position
    /// followed by the value.
    function testCountPairCountsOnlyKeyThenValueAtAPairBoundary(bytes32 key, bytes32 value, bytes32 other)
        external
        pure
    {
        vm.assume(key != value && key != other && value != other);
        bytes32[] memory array = new bytes32[](8);
        array[0] = key;
        array[1] = value;
        array[2] = key;
        array[3] = other;
        array[4] = other;
        array[5] = key;
        array[6] = value;
        array[7] = value;

        assertEq(countPair(array, key, value), 1, "key then value");
        assertEq(countPair(array, key, other), 1, "key then other");
        assertEq(countPair(array, value, value), 1, "value then value");
        assertEq(countPair(array, other, value), 0, "no other then value");
    }
}
