// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {SetAtFreePointer} from "test/lib/SetAtFreePointer.sol";
import {COUNT_MAX, lengthOf, headOf, withCount} from "test/lib/LibMemoryKVHandle.sol";
import {setFreePointer} from "test/lib/LibFreeMemory.sol";
import {EMPTY_FRAME_PAIRS} from "test/lib/LibMemoryKVCapacity.sol";

/// @title LibMemoryKVWordCountOverflowTest
/// The word count is ONE SLOT, `LibMemoryKV.SLOT_BITS` wide, and an insert adds
/// two to it, so there is a count from which one more insert does not fit, and
/// `set` reverts `MemoryKVLengthOverflow` for that insert.
///
/// A store built only through `set` cannot get there, because a node address
/// must fit a slot too and that runs out first. That is a bound on addresses,
/// not on the count, and it is the pointer width that sets it. These assert the
/// count is bounded by a bound on the count.
///
/// Both bounds are read by one comparison over `pointer | length`, so where the
/// two values meet at `LibMemoryKV.POINTER_MASK` is here too: what that
/// comparison still accepts, and which of the two an overflow is reported as.
contract LibMemoryKVWordCountOverflowTest is Test, SetAtFreePointer {
    /// Somewhere low enough that the inserted node's address cannot be what
    /// overflows, and clear of the scratch space and the free memory pointer.
    uint256 internal constant LOW_FREE_POINTER = 0x200;

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
        MemoryKV kv = setAtFreePointerInFrame(MEMORY_KV_EMPTY, key, first, freePointer);
        kv = LibMemoryKV.set(withCount(kv, forced), key, second);
        // The node lives in this frame, so the lookup has to happen here too.
        (uint256 exists, MemoryKVVal value) = LibMemoryKV.get(kv, key);
        return (kv, exists, MemoryKVVal.unwrap(value));
    }

    /// `COUNT_MAX - 1 + 2` is `COUNT_MAX + 1`, which is one bit wider than the
    /// field, and the insert reverts carrying `COUNT_MAX + 1`.
    function testSetRevertsRatherThanWrappingTheWordCountToZero() external {
        vm.expectRevert(abi.encodeWithSelector(LibMemoryKV.MemoryKVLengthOverflow.selector, COUNT_MAX + 1));
        this.setAtFreePointer(
            withCount(MEMORY_KV_EMPTY, COUNT_MAX - 1),
            MemoryKVKey.wrap(bytes32(uint256(1))),
            MemoryKVVal.wrap(bytes32(uint256(2))),
            LOW_FREE_POINTER
        );
    }

    /// The error carries the OFFENDING count, not the bound it crossed. From
    /// `COUNT_MAX` the sum is `COUNT_MAX + 2`, which is neither the bound nor
    /// the `COUNT_MAX + 1` that the first overflowing count and
    /// one-past-the-bound share.
    function testSetWordCountOverflowPayloadIsTheOffendingCountNotTheBound() external {
        vm.expectRevert(abi.encodeWithSelector(LibMemoryKV.MemoryKVLengthOverflow.selector, COUNT_MAX + 2));
        this.setAtFreePointer(
            withCount(MEMORY_KV_EMPTY, COUNT_MAX),
            MemoryKVKey.wrap(bytes32(uint256(1))),
            MemoryKVVal.wrap(bytes32(uint256(2))),
            LOW_FREE_POINTER
        );
    }

    /// The last insert that fits still happens. `COUNT_MAX - 3 + 2` is
    /// `COUNT_MAX - 1`, the widest even count the field holds, and it is written
    /// whole.
    function testSetAcceptsTheWidestWordCountThatFits() external view {
        MemoryKVKey key = MemoryKVKey.wrap(bytes32(uint256(1)));
        MemoryKV kv = this.setAtFreePointer(
            withCount(MEMORY_KV_EMPTY, COUNT_MAX - 3), key, MemoryKVVal.wrap(bytes32(uint256(2))), LOW_FREE_POINTER
        );

        assertEq(lengthOf(kv), COUNT_MAX - 1, "the widest count that fits is written whole");
        assertEq(headOf(kv, key), LOW_FREE_POINTER, "the node is still recorded");
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

        assertEq(lengthOf(kv), COUNT_MAX, "an update leaves the count alone");
        assertEq(exists, 1, "the key is still there");
        assertEq(uint256(value), 3, "the update took effect");
    }

    /// When the node address and the count both overflow at once the address is
    /// what gets reported.
    function testSetReportsThePointerWhenBothOverflow() external {
        vm.expectRevert(abi.encodeWithSelector(LibMemoryKV.MemoryKVOverflow.selector, 0x12345));
        this.setAtFreePointer(
            withCount(MEMORY_KV_EMPTY, COUNT_MAX - 1),
            MemoryKVKey.wrap(bytes32(uint256(1))),
            MemoryKVVal.wrap(bytes32(uint256(2))),
            0x12345
        );
    }

    /// `MemoryKVLengthOverflow` is documented for a word count pushed "past
    /// `POINTER_MASK`", so a count of exactly `COUNT_MAX`, which is that bound,
    /// still fits and is written whole. It is also the widest value the shared
    /// comparison accepts, reached here with both of its inputs nonzero.
    function testSetAcceptsAWordCountOfExactlyTheBound() external view {
        MemoryKVKey key = MemoryKVKey.wrap(bytes32(uint256(1)));
        MemoryKV kv = this.setAtFreePointer(
            withCount(MEMORY_KV_EMPTY, COUNT_MAX - 2), key, MemoryKVVal.wrap(bytes32(uint256(2))), LOW_FREE_POINTER
        );

        assertEq(lengthOf(kv), COUNT_MAX, "a count of exactly the bound is written whole");
        assertEq(headOf(kv, key), LOW_FREE_POINTER, "the node is still recorded");
    }

    /// `MemoryKVOverflow` is documented for a node "at a pointer above
    /// `POINTER_MASK`", so a node landing exactly on `LibMemoryKV.POINTER_MASK`
    /// has not overflowed and an overflowing count alongside it is still
    /// reported as the count's error.
    function testSetReportsTheCountWhenTheAddressIsTheWidestValidOne() external {
        vm.expectRevert(abi.encodeWithSelector(LibMemoryKV.MemoryKVLengthOverflow.selector, COUNT_MAX + 1));
        this.setAtFreePointer(
            withCount(MEMORY_KV_EMPTY, COUNT_MAX - 1),
            MemoryKVKey.wrap(bytes32(uint256(1))),
            MemoryKVVal.wrap(bytes32(uint256(2))),
            LibMemoryKV.POINTER_MASK
        );
    }

    /// The bound is `LibMemoryKV.POINTER_MASK`, not the one past it that first
    /// crosses it. With the node address at `LibMemoryKV.POINTER_MASK + 1` and
    /// the count at `COUNT_MAX + 1`, the same value, their combined
    /// `pointer | length` is that value as well, and the insert reverts
    /// `MemoryKVOverflow` carrying the node address.
    function testSetOverflowsWhenBothValuesAreTheFirstInvalidOne() external {
        vm.expectRevert(abi.encodeWithSelector(LibMemoryKV.MemoryKVOverflow.selector, LibMemoryKV.POINTER_MASK + 1));
        this.setAtFreePointer(
            withCount(MEMORY_KV_EMPTY, COUNT_MAX - 1),
            MemoryKVKey.wrap(bytes32(uint256(1))),
            MemoryKVVal.wrap(bytes32(uint256(2))),
            LibMemoryKV.POINTER_MASK + 1
        );
    }

    /// Ask for the inserts a count wrap needs, against an empty store in a
    /// frame that allocates nothing else so the node addresses are exact. The
    /// fill is expected to stop short; the caller sees only which error.
    function fillFromEmptyExternal(uint256 pairs) external pure {
        setFreePointer(0x80);
        MemoryKV kv = MEMORY_KV_EMPTY;
        for (uint256 i = 1; i <= pairs; i++) {
            kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(i)), MemoryKVVal.wrap(bytes32(i)));
        }
    }

    /// Every other test here forces the count with `withCount`, which is a
    /// `kv` no `set` produced. This one fills an empty store through `set`
    /// alone: carrying the count past `COUNT_MAX` needs `(COUNT_MAX + 1) / 2`
    /// inserts, and the node address runs out first, one pair past
    /// `EMPTY_FRAME_PAIRS`, at `0x80 + EMPTY_FRAME_PAIRS * NODE_BYTES`, so the
    /// fill reverts `MemoryKVOverflow`, not `MemoryKVLengthOverflow`.
    function testWordCountBoundIsUnreachableFromAnEmptyStore() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                LibMemoryKV.MemoryKVOverflow.selector, 0x80 + EMPTY_FRAME_PAIRS * LibMemoryKV.NODE_BYTES
            )
        );
        this.fillFromEmptyExternal((COUNT_MAX + 1) / 2);
    }
}
