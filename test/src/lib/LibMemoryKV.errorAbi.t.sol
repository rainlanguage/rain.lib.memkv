// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {SetAtFreePointer} from "test/lib/SetAtFreePointer.sol";
import {COUNT_MAX, withCount} from "test/lib/LibMemoryKVHandle.sol";

/// @title LibMemoryKVErrorAbiTest
/// Each error's revert data, expected as built from the error's signature
/// written out as a string: the first four bytes of the hash of that
/// signature, then exactly one `uint256` argument word.
contract LibMemoryKVErrorAbiTest is Test, SetAtFreePointer {
    /// A node address low enough that it cannot be what overflows, and clear of
    /// the scratch space and the free memory pointer.
    uint256 internal constant LOW_FREE_POINTER = 0x200;

    /// A node address above the widest head pointer a list slot holds, and
    /// distinct from both that bound and one past it.
    uint256 internal constant HIGH_FREE_POINTER = 0x12345;

    /// An insert above the head pointer bound reverts with the first four bytes
    /// of the hash of `MemoryKVOverflow(uint256)`, then the offending pointer
    /// in one word, and nothing after it.
    function testOverflowRevertDataIsTheCanonicalAbiEncoding() external {
        bytes4 selector = bytes4(keccak256(bytes("MemoryKVOverflow(uint256)")));
        vm.expectRevert(abi.encodePacked(selector, uint256(HIGH_FREE_POINTER)));
        this.setAtFreePointer(
            MEMORY_KV_EMPTY,
            MemoryKVKey.wrap(bytes32(uint256(1))),
            MemoryKVVal.wrap(bytes32(uint256(2))),
            HIGH_FREE_POINTER
        );
    }

    /// The same for the count bound: the first four bytes of the hash of
    /// `MemoryKVLengthOverflow(uint256)`, then the offending count.
    /// `COUNT_MAX + 2` is neither the bound nor one past it.
    function testLengthOverflowRevertDataIsTheCanonicalAbiEncoding() external {
        bytes4 selector = bytes4(keccak256(bytes("MemoryKVLengthOverflow(uint256)")));
        vm.expectRevert(abi.encodePacked(selector, COUNT_MAX + 2));
        this.setAtFreePointer(
            withCount(MEMORY_KV_EMPTY, COUNT_MAX),
            MemoryKVKey.wrap(bytes32(uint256(1))),
            MemoryKVVal.wrap(bytes32(uint256(2))),
            LOW_FREE_POINTER
        );
    }
}
