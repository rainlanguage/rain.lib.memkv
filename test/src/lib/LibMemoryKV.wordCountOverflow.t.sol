// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {lengthOf, withCount, COUNT_MAX} from "test/lib/LibMemoryKVTestHelpers.sol";

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
///
/// Both bounds are read by one comparison over `pointer | length`, so where the
/// two values meet at `0xFFFF` is here too: what that comparison still accepts,
/// and which of the two an overflow is reported as.
contract LibMemoryKVWordCountOverflowTest is Test {
    /// Somewhere low enough that the inserted node's address cannot be what
    /// overflows, and clear of the scratch space and the free memory pointer.
    uint256 internal constant LOW_FREE_POINTER = 0x200;

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

        assertEq(lengthOf(kv), 0xFFFE, "the widest count that fits is written whole");

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

        assertEq(lengthOf(kv), COUNT_MAX, "an update leaves the count alone");
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

    /// `MemoryKVLengthOverflow` is documented for a count pushed "past
    /// `0xFFFF`", so `0xFFFF` itself still fits and must be written whole. It is
    /// also the widest value the shared comparison accepts, reached here with
    /// both of its inputs nonzero, so a guard that added the node address and
    /// the count rather than ORing their bits would refuse this insert.
    function testSetAcceptsAWordCountOfExactlyTheBound() external view {
        MemoryKVKey key = MemoryKVKey.wrap(bytes32(uint256(1)));
        MemoryKV kv = this.setAtFreePointer(
            withCount(MEMORY_KV_EMPTY, 0xFFFD), key, MemoryKVVal.wrap(bytes32(uint256(2))), LOW_FREE_POINTER
        );

        assertEq(lengthOf(kv), 0xFFFF, "a count of exactly the bound is written whole");

        uint256 bitOffset = (uint256(keccak256(abi.encodePacked(MemoryKVKey.unwrap(key)))) % 0x0f) * 0x10;
        assertEq((MemoryKV.unwrap(kv) >> bitOffset) & 0xFFFF, LOW_FREE_POINTER, "the node is still recorded");
    }

    /// `MemoryKVOverflow` is documented for a node address "above `0xFFFF`", so
    /// a node landing exactly on `0xFFFF` has not overflowed and an overflowing
    /// count alongside it is still reported as the count's error. Every other
    /// input either leaves the guard alone or is already past the address bound,
    /// so this is what separates an address bound of `above` from one of `at`.
    function testSetReportsTheCountWhenTheAddressIsTheWidestValidOne() external {
        vm.expectRevert(abi.encodeWithSelector(LibMemoryKV.MemoryKVLengthOverflow.selector, 0x10000));
        this.setAtFreePointer(
            withCount(MEMORY_KV_EMPTY, 0xFFFE),
            MemoryKVKey.wrap(bytes32(uint256(1))),
            MemoryKVVal.wrap(bytes32(uint256(2))),
            0xFFFF
        );
    }

    /// The bound is `0xFFFF`, not the `0x10000` that first crosses it. With the
    /// node address and the count both at `0x10000` their combined
    /// `pointer | length` is `0x10000` as well, so a bound written one too high
    /// lets this insert through entirely rather than merely naming the wrong
    /// overflow: `0x12345` above carries bits a raised bound still catches, and
    /// this carries none.
    function testSetOverflowsWhenBothValuesAreTheFirstInvalidOne() external {
        vm.expectRevert(abi.encodeWithSelector(LibMemoryKV.MemoryKVOverflow.selector, 0x10000));
        this.setAtFreePointer(
            withCount(MEMORY_KV_EMPTY, 0xFFFE),
            MemoryKVKey.wrap(bytes32(uint256(1))),
            MemoryKVVal.wrap(bytes32(uint256(2))),
            0x10000
        );
    }

    /// Ask for the inserts a count wrap needs, against an empty store in a
    /// frame that allocates nothing else so the node addresses are exact. The
    /// fill is expected to stop short; the caller sees only which error.
    function fillFromEmptyExternal(uint256 pairs) external pure {
        assembly ("memory-safe") {
            mstore(0x40, 0x80)
        }
        MemoryKV kv = MemoryKV.wrap(0);
        for (uint256 i = 1; i <= pairs; i++) {
            kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(i)), MemoryKVVal.wrap(bytes32(i)));
        }
    }

    /// Every other test here forces the count with `withCount`, which is a
    /// `kv` no `set` produced. This is the one that asks what a caller who only
    /// ever calls `set` can reach, and the answer is that it is not this error:
    /// carrying the count to `0x10000` needs 32768 inserts, and the node
    /// address runs out 48 times earlier, at the 683rd, at `0x10040`. So
    /// `MemoryKVLengthOverflow` is not in a correct caller's reach and the
    /// header's claim above is a measurement rather than an assurance.
    function testWordCountBoundIsUnreachableFromAnEmptyStore() external {
        vm.expectRevert(abi.encodeWithSelector(LibMemoryKV.MemoryKVOverflow.selector, 0x10040));
        this.fillFromEmptyExternal((COUNT_MAX + 1) / 2);
    }
}
