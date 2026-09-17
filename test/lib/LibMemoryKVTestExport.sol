// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

/// @title LibMemoryKVTestExport
/// Reading a pairwise `bytes32[]` as `toBytes32Array` lays it out: a key at
/// every even index and its value at the odd index after it.
library LibMemoryKVTestExport {
    /// How many times `array` holds `key` immediately followed by `value`.
    function countPair(bytes32[] memory array, bytes32 key, bytes32 value) internal pure returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < array.length; i += 2) {
            if (array[i] == key && array[i + 1] == value) {
                count++;
            }
        }
        return count;
    }
}
