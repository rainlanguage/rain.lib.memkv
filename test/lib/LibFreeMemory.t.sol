// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {LibPointer, Pointer} from "rain-solmem-0.1.28/src/lib/LibPointer.sol";

import {dirtyFreeMemory} from "test/lib/LibFreeMemory.sol";

/// @title LibFreeMemoryTest
/// The promises `dirtyFreeMemory` makes and other tests rest on.
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
}
