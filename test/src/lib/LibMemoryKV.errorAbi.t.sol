// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {withCount, COUNT_MAX} from "test/lib/LibMemoryKVTestHelpers.sol";

/// @title LibMemoryKVErrorAbiTest
/// Every other test that expects one of these errors builds the expectation
/// from `LibMemoryKV.<error>.selector`, which is derived from the very
/// declaration under test, so adding, widening or narrowing an argument moves
/// the expectation along with it and nothing fails. A caller decoding the
/// revert off chain holds the signature as a string instead. These build the
/// expected returndata from that string, pinning each error to exactly one
/// `uint256` argument and to a selector the other error does not share.
contract LibMemoryKVErrorAbiTest is Test {
    /// A node address low enough that it cannot be what overflows, and clear of
    /// the scratch space and the free memory pointer.
    uint256 internal constant LOW_FREE_POINTER = 0x200;

    /// A node address above the widest head pointer a list slot holds, and
    /// distinct from both that bound and one past it.
    uint256 internal constant HIGH_FREE_POINTER = 0x12345;

    /// Insert against a chosen free memory pointer so the node's address is a
    /// known value rather than wherever this test frame happens to have
    /// reached. The node lives in memory this call frame owns, so only the
    /// returned `kv` and the (non)revert are observable to the caller.
    function setAtFreePointer(MemoryKV kv, MemoryKVKey key, MemoryKVVal value, uint256 freePointer)
        external
        pure
        returns (MemoryKV)
    {
        assembly ("memory-safe") {
            mstore(0x40, freePointer)
        }
        return LibMemoryKV.set(kv, key, value);
    }

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
    /// `MemoryKVLengthOverflow(uint256)`, then the offending count. `0xFFFF + 2`
    /// is `0x10001`, which is neither the bound nor one past it.
    function testLengthOverflowRevertDataIsTheCanonicalAbiEncoding() external {
        bytes4 selector = bytes4(keccak256(bytes("MemoryKVLengthOverflow(uint256)")));
        vm.expectRevert(abi.encodePacked(selector, uint256(0x10001)));
        this.setAtFreePointer(
            withCount(MEMORY_KV_EMPTY, COUNT_MAX),
            MemoryKVKey.wrap(bytes32(uint256(1))),
            MemoryKVVal.wrap(bytes32(uint256(2))),
            LOW_FREE_POINTER
        );
    }
}
