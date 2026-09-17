// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";

/// @title LibMemoryKVWordCountOverflowTest
/// The word count is SIXTEEN bits and an insert adds two to it, so there is a
/// count from which one more insert does not fit. The count is written by
/// shifting into the top of `MemoryKV`, which drops whatever does not fit, and
/// `toBytes32Array` sizes its allocation from the count and then copies every
/// pair it walks -- so a count that lost its high bit is a short allocation
/// written past, not a wrong number a caller might notice.
///
/// A store built only through `set` cannot get there, because a node address
/// must fit sixteen bits too and that runs out first. That is a bound on
/// addresses, not on the count, and it is the pointer width that sets it. These
/// assert the count is bounded by a bound on the count.
contract LibMemoryKVWordCountOverflowTest is Test {
    /// The bit offset of the word count in `MemoryKV`.
    uint256 internal constant COUNT_BIT_OFFSET = 0xf0;

    /// The widest count the field holds.
    uint256 internal constant COUNT_MAX = 0xFFFF;

    /// Somewhere low enough that the inserted node's address cannot be what
    /// overflows, and clear of the scratch space and the free memory pointer.
    uint256 internal constant LOW_FREE_POINTER = 0x200;

    function count(MemoryKV kv) internal pure returns (uint256) {
        return MemoryKV.unwrap(kv) >> COUNT_BIT_OFFSET;
    }

    function withCount(MemoryKV kv, uint256 newCount) internal pure returns (MemoryKV) {
        return MemoryKV.wrap((MemoryKV.unwrap(kv) & ~(COUNT_MAX << COUNT_BIT_OFFSET)) | (newCount << COUNT_BIT_OFFSET));
    }

    /// Insert against a chosen free memory pointer so the node's address is a
    /// known value rather than wherever this test frame happens to have reached.
    /// The node lives in memory this call frame owns, so only the returned `kv`
    /// and the (non)revert are observable to the caller.
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

    /// Insert `key` normally, force the count to `forced`, then set `key` again
    /// -- which is an update, because the key is already in its list. Both sets
    /// happen in this frame so the node the second one finds is the node the
    /// first one wrote.
    function updateAtForcedCount(
        uint256 forced,
        MemoryKVKey key,
        MemoryKVVal first,
        MemoryKVVal second,
        uint256 freePointer
    ) external pure returns (MemoryKV, uint256, bytes32) {
        assembly ("memory-safe") {
            mstore(0x40, freePointer)
        }
        MemoryKV kv = LibMemoryKV.set(MEMORY_KV_EMPTY, key, first);
        kv = LibMemoryKV.set(withCount(kv, forced), key, second);
        // The node lives in this frame, so the lookup has to happen here too.
        (uint256 exists, MemoryKVVal value) = LibMemoryKV.get(kv, key);
        return (kv, exists, MemoryKVVal.unwrap(value));
    }

    /// `0xFFFE + 2` is `0x10000`, which is one bit wider than the field. Shifted
    /// into place that bit is gone and the count reads back as `0`, so the
    /// insert that does not fit is the one that reports an empty store.
    function testSetRevertsRatherThanWrappingTheWordCountToZero() external {
        vm.expectRevert(abi.encodeWithSelector(LibMemoryKV.MemoryKVLengthOverflow.selector, 0x10000));
        this.setAtFreePointer(
            withCount(MEMORY_KV_EMPTY, 0xFFFE),
            MemoryKVKey.wrap(bytes32(uint256(1))),
            MemoryKVVal.wrap(bytes32(uint256(2))),
            LOW_FREE_POINTER
        );
    }

    /// The error carries the OFFENDING count, not the bound it crossed. From
    /// `0xFFFF` the sum is `0x10001`, which is neither `0xFFFF` nor the `0x10000`
    /// that the first overflowing count and one-past-the-bound share.
    function testSetWordCountOverflowPayloadIsTheOffendingCountNotTheBound() external {
        vm.expectRevert(abi.encodeWithSelector(LibMemoryKV.MemoryKVLengthOverflow.selector, 0x10001));
        this.setAtFreePointer(
            withCount(MEMORY_KV_EMPTY, 0xFFFF),
            MemoryKVKey.wrap(bytes32(uint256(1))),
            MemoryKVVal.wrap(bytes32(uint256(2))),
            LOW_FREE_POINTER
        );
    }

    /// The last insert that fits still happens. `0xFFFC + 2` is `0xFFFE`, the
    /// widest even count the field holds, and it must come back intact rather
    /// than be refused a step early.
    function testSetAcceptsTheWidestWordCountThatFits() external view {
        MemoryKVKey key = MemoryKVKey.wrap(bytes32(uint256(1)));
        MemoryKV kv = this.setAtFreePointer(
            withCount(MEMORY_KV_EMPTY, 0xFFFC), key, MemoryKVVal.wrap(bytes32(uint256(2))), LOW_FREE_POINTER
        );

        assertEq(count(kv), 0xFFFE, "the widest count that fits is written whole");

        uint256 bitOffset = (uint256(keccak256(abi.encodePacked(MemoryKVKey.unwrap(key)))) % 0x0f) * 0x10;
        assertEq((MemoryKV.unwrap(kv) >> bitOffset) & 0xFFFF, LOW_FREE_POINTER, "the node is still recorded");
    }

    /// An update does not add a pair, so there is no sum to overflow and a full
    /// count is not a reason to refuse one. The value must change and the count
    /// must not.
    function testSetUpdateAtAFullWordCountIsNotRefused() external view {
        MemoryKVKey key = MemoryKVKey.wrap(bytes32(uint256(1)));
        (MemoryKV kv, uint256 exists, bytes32 value) = this.updateAtForcedCount(
            COUNT_MAX,
            key,
            MemoryKVVal.wrap(bytes32(uint256(2))),
            MemoryKVVal.wrap(bytes32(uint256(3))),
            LOW_FREE_POINTER
        );

        assertEq(count(kv), COUNT_MAX, "an update leaves the count alone");
        assertEq(exists, 1, "the key is still there");
        assertEq(uint256(value), 3, "the update took effect");
    }

    /// When the node address and the count both overflow at once the address is
    /// what gets reported: it is the one that has already corrupted the list,
    /// and the count is only the size of the export that would have followed.
    function testSetReportsThePointerWhenBothOverflow() external {
        vm.expectRevert(abi.encodeWithSelector(LibMemoryKV.MemoryKVOverflow.selector, 0x12345));
        this.setAtFreePointer(
            withCount(MEMORY_KV_EMPTY, 0xFFFE),
            MemoryKVKey.wrap(bytes32(uint256(1))),
            MemoryKVVal.wrap(bytes32(uint256(2))),
            0x12345
        );
    }
}
