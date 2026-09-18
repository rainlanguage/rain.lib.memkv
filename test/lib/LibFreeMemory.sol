// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {LibPointer, Pointer} from "rain-solmem-0.1.28/src/lib/LibPointer.sol";

/// Fill `words` words from the free memory pointer up with `sentinel`,
/// WITHOUT moving the pointer, so the next allocation lands on memory that
/// does not read as zero. A word the allocator subsequently claims but never
/// writes still reads as `sentinel`.
function dirtyFreeMemory(bytes32 sentinel, uint256 words) pure {
    Pointer cursor = LibPointer.allocatedMemoryPointer();
    for (uint256 i = 0; i < words; i++) {
        LibPointer.unsafeWriteWord(cursor, sentinel);
        cursor = LibPointer.unsafeAddWord(cursor);
    }
}

/// Move the free memory pointer to `pointer`, so the next allocation, and so
/// the next node an insert writes, starts there. Memory at and above `pointer`
/// is free to the next allocation from then on, whatever it held.
/// @param pointer The new free memory pointer.
function setFreePointer(uint256 pointer) pure {
    assembly ("memory-safe") {
        mstore(0x40, pointer)
    }
}

/// Advance the free memory pointer to `floor` if it is below it, so every later
/// allocation, and so every node an insert writes, sits at or above `floor`. A
/// pointer already at or above `floor` is left where it is.
/// @param floor The lowest address the next allocation may start at.
function raiseFreePointerTo(uint256 floor) pure {
    if (Pointer.unwrap(LibPointer.allocatedMemoryPointer()) < floor) {
        setFreePointer(floor);
    }
}
