// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";

/// @title LibMemoryKVSetSlotMaskTest
/// An insert clears its list's head slot and writes the new head into it, and
/// the region it clears must be EXACTLY the sixteen bits of that slot. A clear
/// one bit short leaves the old head's low bit ored under the new one; a clear
/// one bit long takes the low bit of the slot above.
///
/// Both edges are invisible while every node address is a multiple of 32,
/// because the bit at stake is then zero either way. So these tests place nodes
/// at addresses the library allows but a Solidity allocator would not choose:
/// one odd, one even, in the same list and in neighbouring lists. A node
/// address is a caller's free memory pointer, and `set` bounds it by magnitude
/// alone.
contract LibMemoryKVSetSlotMaskTest is Test {
    using LibMemoryKV for MemoryKV;

    /// An odd node address, low enough that a walk off the end of it expands
    /// memory by kilobytes rather than megabytes.
    uint256 internal constant ODD_POINTER = 0x101;

    /// An even node address clear of the three words at `ODD_POINTER`.
    uint256 internal constant EVEN_POINTER = 0x180;

    /// The list a key belongs to, restated from the store's own documented hash
    /// so the expectation is not the implementation's expression read back.
    function slotOf(MemoryKVKey key) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(MemoryKVKey.unwrap(key)))) % 0x0f;
    }

    /// Rehash `seed` until the key lands in `slot`.
    function keyForSlot(bytes32 seed, uint256 slot) internal pure returns (MemoryKVKey) {
        bytes32 key = seed;
        for (uint256 i = 0; i < 10000; i++) {
            if (slotOf(MemoryKVKey.wrap(key)) == slot) {
                return MemoryKVKey.wrap(key);
            }
            key = keccak256(abi.encodePacked(key));
        }
        revert("no key for slot");
    }

    /// The 16 bit head pointer the store holds for `slot`.
    function headOf(MemoryKV kv, uint256 slot) internal pure returns (uint256) {
        return (MemoryKV.unwrap(kv) >> (slot * 0x10)) & 0xFFFF;
    }

    /// The word count the store carries in its top 16 bits.
    function lengthOf(MemoryKV kv) internal pure returns (uint256) {
        return MemoryKV.unwrap(kv) >> 0xf0;
    }

    /// Insert `first` at `firstPointer`, then `second` at `secondPointer`, and
    /// read `first` back in the frame that owns both nodes. The nodes die with
    /// this frame, so the store word and that read are all the caller gets.
    function insertAtTwoPointersExternal(
        MemoryKVKey first,
        MemoryKVVal firstValue,
        uint256 firstPointer,
        MemoryKVKey second,
        MemoryKVVal secondValue,
        uint256 secondPointer
    ) external pure returns (MemoryKV, uint256, bytes32) {
        MemoryKV kv = MEMORY_KV_EMPTY;
        assembly ("memory-safe") {
            mstore(0x40, firstPointer)
        }
        kv = kv.set(first, firstValue);
        assembly ("memory-safe") {
            mstore(0x40, secondPointer)
        }
        kv = kv.set(second, secondValue);
        (uint256 exists, MemoryKVVal got) = kv.get(first);
        return (kv, exists, MemoryKVVal.unwrap(got));
    }

    /// Two keys in ONE list, the older node at an odd address and the newer at
    /// an even one. The slot must hold the newer address exactly: a clear that
    /// stopped at fifteen bits would leave the odd address's low bit set and
    /// head the list at `EVEN_POINTER + 1`, where no node begins.
    ///
    /// Slot 0 also puts the rewrite at a bit offset of zero, so the shift that
    /// places the new head is the identity.
    function testInsertClearsTheSlotsLowBit() external view {
        MemoryKVKey older = keyForSlot(bytes32(uint256(1)), 0);
        MemoryKVKey newer = keyForSlot(bytes32(uint256(2)), 0);
        assertTrue(MemoryKVKey.unwrap(older) != MemoryKVKey.unwrap(newer), "two distinct keys");

        (MemoryKV kv, uint256 exists, bytes32 value) = this.insertAtTwoPointersExternal(
            older,
            MemoryKVVal.wrap(bytes32(uint256(0xA100))),
            ODD_POINTER,
            newer,
            MemoryKVVal.wrap(bytes32(uint256(0xB200))),
            EVEN_POINTER
        );

        assertEq(headOf(kv, 0), EVEN_POINTER, "slot 0 heads the newer node and nothing of the older address");
        assertEq(lengthOf(kv), 4, "two pairs is four words");
        assertEq(exists, 1, "the older key is still reachable behind the new head");
        assertEq(uint256(value), 0xA100, "and still carries its value");
    }

    /// One key in list 14 at an odd address, then a key in list 13. Writing
    /// list 13's head must not reach bit 224, the low bit of list 14's head: a
    /// clear of seventeen bits would move list 14 to `ODD_POINTER - 1`.
    ///
    /// List 14 is the highest there is, so its head sits directly under the
    /// word count and is the slot a rewrite is likeliest to reach past.
    function testInsertLeavesTheNeighbouringSlotsLowBit() external view {
        MemoryKVKey high = keyForSlot(bytes32(uint256(1)), 14);
        MemoryKVKey low = keyForSlot(bytes32(uint256(1)), 13);

        (MemoryKV kv, uint256 exists, bytes32 value) = this.insertAtTwoPointersExternal(
            high,
            MemoryKVVal.wrap(bytes32(uint256(0xA100))),
            ODD_POINTER,
            low,
            MemoryKVVal.wrap(bytes32(uint256(0xB200))),
            EVEN_POINTER
        );

        assertEq(headOf(kv, 14), ODD_POINTER, "list 14 keeps the whole address it was given");
        assertEq(headOf(kv, 13), EVEN_POINTER, "list 13 heads its own node");
        assertEq(lengthOf(kv), 4, "two pairs is four words");
        assertEq(exists, 1, "the key in list 14 is still reachable");
        assertEq(uint256(value), 0xA100, "and still carries its value");
    }
}
