// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";

import {LibPointer, Pointer} from "rain-solmem-0.1.28/src/lib/LibPointer.sol";

import {dirtyFreeMemory, raiseFreePointerTo} from "test/lib/LibFreeMemory.sol";

/// @title LibFreeMemoryTest
/// The promises `dirtyFreeMemory` and `raiseFreePointerTo` make and other tests
/// rest on.
contract LibFreeMemoryTest is Test {
    function freePointer() internal pure returns (uint256) {
        return Pointer.unwrap(LibPointer.allocatedMemoryPointer());
    }

    function wordAt(uint256 pointer) internal pure returns (bytes32) {
        return LibPointer.unsafeReadWord(Pointer.wrap(pointer));
    }

    /// Exactly `words` words from the free memory pointer up read as the
    /// sentinel afterwards, the word after them keeps what it held, and the
    /// pointer does not move.
    function testDirtyFreeMemoryFillsExactlyTheWordsAndLeavesThePointer(bytes32 sentinel, uint8 words) external pure {
        uint256 start = freePointer();
        uint256 past = start + uint256(words) * 0x20;
        LibPointer.unsafeWriteWord(Pointer.wrap(past), ~sentinel);

        dirtyFreeMemory(sentinel, words);

        // Read before asserting: an assert message allocates at the pointer.
        uint256 end = freePointer();
        uint256 sentinelWords = 0;
        while (sentinelWords < words && wordAt(start + sentinelWords * 0x20) == sentinel) {
            sentinelWords++;
        }
        bytes32 pastWord = wordAt(past);

        assertEq(end, start, "pointer not moved");
        assertEq(sentinelWords, words, "every word dirtied");
        assertEq(pastWord, ~sentinel, "the word after them");
    }

    /// A free memory pointer below the floor is raised to exactly the floor.
    function testRaiseFreePointerToLiftsAPointerBelowTheFloor(uint16 gap) external pure {
        uint256 floor = freePointer() + uint256(gap) + 1;
        raiseFreePointerTo(floor);
        assertEq(freePointer(), floor, "raised to the floor");
    }

    /// A free memory pointer at or above the floor stays where it is.
    function testRaiseFreePointerToLeavesAPointerAtOrAboveTheFloor(uint256 floor) external pure {
        uint256 before = freePointer();
        floor = bound(floor, 0, before);
        raiseFreePointerTo(floor);
        assertEq(freePointer(), before, "left where it was");
    }
}
