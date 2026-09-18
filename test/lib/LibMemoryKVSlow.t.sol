// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {LibPointer, Pointer} from "rain-solmem-0.1.28/src/lib/LibPointer.sol";
import {LibBytes32Array} from "rain-solmem-0.1.28/src/lib/LibBytes32Array.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {LibMemoryKVSlow} from "test/lib/LibMemoryKVSlow.sol";

contract LibMemoryKVSlowTest is Test {
    /// The linear export takes the array from the free pointer and leaves the
    /// free pointer past every word it writes into it. An allocation short of
    /// what the copy writes leaves exported pairs sitting in memory that the
    /// next allocation hands out, which nothing reading only the array can see.
    function testSlowLinearExportAllocatesWhatItWrites(bytes32[] memory kvs) external pure {
        vm.assume(kvs.length % 2 == 0);

        MemoryKV kv = MEMORY_KV_EMPTY;
        for (uint256 i = 0; i < kvs.length; i += 2) {
            kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(kvs[i]), MemoryKVVal.wrap(kvs[i + 1]));
        }

        Pointer pointerBefore = LibPointer.allocatedMemoryPointer();
        bytes32[] memory array = LibMemoryKVSlow.toBytes32ArrayLinear(kv);
        Pointer pointerAfter = LibPointer.allocatedMemoryPointer();

        uint256 pointerArray = Pointer.unwrap(LibBytes32Array.startPointer(array));

        assertEq(Pointer.unwrap(pointerBefore), pointerArray);
        assertEq(Pointer.unwrap(pointerAfter), Pointer.unwrap(pointerBefore) + 0x20 + (array.length * 0x20));
    }
}
