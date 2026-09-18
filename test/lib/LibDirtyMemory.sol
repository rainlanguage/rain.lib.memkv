// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// Fill `words` words from the free memory pointer up with `sentinel`,
/// WITHOUT moving the pointer, so the next allocation lands on memory that
/// does not read as zero. A word the allocator subsequently claims but never
/// writes still reads as `sentinel`.
function dirtyFreeMemory(bytes32 sentinel, uint256 words) pure {
    assembly ("memory-safe") {
        let cursor := mload(0x40)
        for { let i := 0 } lt(i, words) { i := add(i, 1) } {
            mstore(cursor, sentinel)
            cursor := add(cursor, 0x20)
        }
    }
}
