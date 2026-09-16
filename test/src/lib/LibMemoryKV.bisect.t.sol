// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal} from "src/lib/LibMemoryKV.sol";

/// Pins the whole `toBytes32Array` bisect tree: the root split of `kv` and both
/// halves below it, which are together the only path by which internal list
/// slots 0..14 reach the exported array.
///
/// The two halves are not mirror images, and the root split is the reason. The
/// low half is eight leaves under four interior nodes, routing slots 0..7 out
/// of `and(mask128, kv)`. The high half is seven, because the 16 bit length
/// field occupies the lane an eighth leaf would need: `shr(0x90, shl(0x10, kv))`
/// shifts the length out first, so `p0` lane j is slot 8+j for j in 0..6 and
/// lane 7 is structurally zero. The tree then collapses the node that would
/// have covered that zero lane — slot 14 is reached by `shr(0x20, p00)` with no
/// `and(mask16, ...)` scrub, where the mirroring leaf of the low half has one.
/// That omission is sound only while the root split has already zeroed the
/// length, a coupling between two lines twelve apart, so the split and both
/// halves are pinned in one file rather than split across files that cannot see
/// each other's assumptions.
///
/// Which slots a store occupies is the tree's whole input. Every one of its
/// twenty eight guards tests a window of `kv` against zero, and nothing it does
/// branches on what a key or a value is. Fifteen slots is 32768 occupancy
/// combinations, and these tests run all of them rather than sampling:
/// `slotKeys` is one constant per slot, so a combination is reached by choosing
/// keys rather than by searching for them, and the space is small enough to
/// enumerate whole.
///
/// Every node of every case is allocated from a free memory pointer that is
/// rewound between cases. Unrewound, the 32768 cases walk that pointer past the
/// `0xFFFF` ceiling `set` enforces after 115 of them.
contract LibMemoryKVBisectTest is Test {
    using LibMemoryKV for MemoryKV;

    /// `kv` carries one pointer per internal linked list.
    uint256 constant SLOTS = 15;

    /// Every combination of which slots are occupied.
    uint256 constant OCCUPANCY_COMBINATIONS = 2 ** SLOTS;

    /// Every slot occupied.
    uint256 constant OCCUPANCY_FULL = OCCUPANCY_COMBINATIONS - 1;

    /// Bytes `set` allocates per inserted key/value pair.
    uint256 constant NODE_BYTES = 0x60;

    /// The widest pointer a slot can hold.
    uint256 constant POINTER_MAX = 0xFFFF;

    /// A 16 bit pointer is valid all the way to `POINTER_MAX`, so every mask and
    /// shift on the way down the tree must carry this bit.
    uint256 constant POINTER_HIGH_BIT = 0x8000;

    /// Enough padding to push the free memory pointer, and therefore every node
    /// an enumeration inserts, above `POINTER_HIGH_BIT`.
    uint256 constant HIGH_POINTER_PAD = 0x9000;

    /// Stands for "no mask", which a 15 bit mask cannot collide with.
    uint256 constant NO_MASK = type(uint256).max;

    /// Values sit above every key, so a copy that reads the key where the value
    /// belongs, or that reads another slot's value, is a different word. In an
    /// enumeration a value is this base plus the slot it belongs to, which is
    /// how `exportMatches` reads a pair's slot back out of it.
    uint256 constant VALUE_BASE = 0x100;

    /// The internal list slot a key hashes into. MUST match `get`/`set`.
    function slotOf(bytes32 key) internal pure returns (uint256) {
        uint256 slot;
        assembly ("memory-safe") {
            mstore(0, key)
            slot := mod(keccak256(0, 0x20), 0x0f)
        }
        return slot;
    }

    /// One key per slot: the smallest positive integer whose 32 byte big endian
    /// encoding hashes into that slot. Regenerating one is
    /// `cast keccak $(cast to-uint256 <n>)` reduced modulo 15, and
    /// `testKeyConstantsLandWhereClaimed` is what holds them to it.
    function slotKeys() internal pure returns (bytes32[SLOTS] memory) {
        return [
            bytes32(uint256(4)),
            bytes32(uint256(31)),
            bytes32(uint256(2)),
            bytes32(uint256(1)),
            bytes32(uint256(9)),
            bytes32(uint256(49)),
            bytes32(uint256(24)),
            bytes32(uint256(42)),
            bytes32(uint256(3)),
            bytes32(uint256(21)),
            bytes32(uint256(16)),
            bytes32(uint256(7)),
            bytes32(uint256(6)),
            bytes32(uint256(14)),
            bytes32(uint256(11))
        ];
    }

    /// The twelve smallest positive integers that all hash into slot 0, for the
    /// one test that needs a list longer than the store has slots.
    function slot0ChainKeys() internal pure returns (bytes32[12] memory) {
        return [
            bytes32(uint256(4)),
            bytes32(uint256(5)),
            bytes32(uint256(12)),
            bytes32(uint256(20)),
            bytes32(uint256(27)),
            bytes32(uint256(30)),
            bytes32(uint256(40)),
            bytes32(uint256(50)),
            bytes32(uint256(62)),
            bytes32(uint256(64)),
            bytes32(uint256(108)),
            bytes32(uint256(138))
        ];
    }

    function valueFor(uint256 index) internal pure returns (bytes32) {
        return bytes32(VALUE_BASE + index);
    }

    /// Whether `mask` names `slot` as occupied.
    function occupies(uint256 mask, uint256 slot) internal pure returns (bool) {
        return (mask >> slot) & 1 != 0;
    }

    function pointerAt(MemoryKV kv, uint256 slot) internal pure returns (uint256) {
        return (MemoryKV.unwrap(kv) >> (slot * 0x10)) & POINTER_MAX;
    }

    function lengthOf(MemoryKV kv) internal pure returns (uint256) {
        return MemoryKV.unwrap(kv) >> 0xf0;
    }

    /// Which slots of `kv` hold a pointer, in the same bit order as an occupancy
    /// mask.
    function occupancyOf(MemoryKV kv) internal pure returns (uint256) {
        uint256 occupancy = 0;
        for (uint256 i = 0; i < SLOTS; i++) {
            occupancy <<= 1;
            if (pointerAt(kv, SLOTS - 1 - i) != 0) {
                occupancy |= 1;
            }
        }
        return occupancy;
    }

    function freePointer() internal pure returns (uint256) {
        uint256 pointer;
        assembly ("memory-safe") {
            pointer := mload(0x40)
        }
        return pointer;
    }

    /// How many times `array` holds the pair `(key, value)`. For the one test
    /// whose pairs all share a slot, so none of them names one and
    /// `exportMatches` has nothing to read.
    function countPair(bytes32[] memory array, bytes32 key, bytes32 value) internal pure returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < array.length; i += 2) {
            if (array[i] == key && array[i + 1] == value) {
                count++;
            }
        }
        return count;
    }

    /// The store holding one key in each slot `mask` names.
    function storeForOccupancy(uint256 mask, bytes32[SLOTS] memory keys) internal pure returns (MemoryKV) {
        MemoryKV kv = MemoryKV.wrap(0);
        for (uint256 slot = 0; slot < SLOTS; slot++) {
            if (occupies(mask, slot)) {
                kv = kv.set(MemoryKVKey.wrap(keys[slot]), MemoryKVVal.wrap(valueFor(slot)));
            }
        }
        return kv;
    }

    /// Whether `array` holds exactly the pairs `mask` must export, as a
    /// multiset. `toBytes32Array` documents its pair order as unspecified, so
    /// position is deliberately not checked: two blocks of the tree swapped
    /// emit the same pairs in a different order and are not a defect.
    ///
    /// Each value is `VALUE_BASE + slot`, so the slot a pair claims is read out
    /// of its own value, and the pair is then held to the key that slot must
    /// carry. Collecting those slots into a bitset and comparing it to `mask` is
    /// multiset equality without a scan per pair: a slot exported twice is
    /// caught by its bit already being set, and one dropped, duplicated or
    /// invented by the bitsets differing.
    function exportMatches(bytes32[] memory array, uint256 mask, bytes32[SLOTS] memory keys)
        internal
        pure
        returns (bool)
    {
        if (array.length % 2 != 0) {
            return false;
        }

        uint256 found = 0;
        for (uint256 cursor = 0; cursor < array.length; cursor += 2) {
            uint256 value = uint256(array[cursor + 1]);
            if (value < VALUE_BASE || value >= VALUE_BASE + SLOTS) {
                return false;
            }

            uint256 slot = value - VALUE_BASE;
            if (array[cursor] != keys[slot]) {
                return false;
            }
            if (occupies(found, slot)) {
                return false;
            }
            found |= 2 ** slot;
        }
        return found == mask;
    }

    /// Exports all 32768 occupancy combinations and checks each against the
    /// pairs that combination must produce. The check is plain arithmetic and
    /// the first mask that fails it is carried out of the loop, so the assertion
    /// machinery runs once rather than 32768 times and the mask that failed is
    /// what the assertion reports.
    function checkEveryOccupancy() internal pure {
        bytes32[SLOTS] memory keys = slotKeys();

        uint256 free = freePointer();
        assertLe(free + (SLOTS - 1) * NODE_BYTES, POINTER_MAX, "every case must fit under the pointer ceiling");

        uint256 failed = NO_MASK;
        for (uint256 mask = 0; mask < OCCUPANCY_COMBINATIONS; mask++) {
            if (!exportMatches(LibMemoryKV.toBytes32Array(storeForOccupancy(mask, keys)), mask, keys)) {
                failed = mask;
                break;
            }

            assembly ("memory-safe") {
                mstore(0x40, free)
            }
        }

        assertEq(failed, NO_MASK, "occupancy mask whose export did not match");
    }

    /// The fifteen key constants are the whole reason a combination can be
    /// chosen rather than searched for, and every enumeration below reads its
    /// result through the slot each key claims. Should the hash that `get` and
    /// `set` share ever move, the keys stop naming the slots they claim and the
    /// enumerations silently cover something other than what they report.
    ///
    /// Occupying all fifteen at once is what makes them fifteen distinct slots
    /// rather than fifteen keys that each hash somewhere. `set` routes on the
    /// key alone, so that plus one key per slot is every occupancy.
    function testKeyConstantsLandWhereClaimed() public pure {
        bytes32[SLOTS] memory keys = slotKeys();
        for (uint256 slot = 0; slot < SLOTS; slot++) {
            assertEq(slotOf(keys[slot]), slot, "slot key hashes into its slot");
        }
        assertEq(occupancyOf(storeForOccupancy(OCCUPANCY_FULL, keys)), OCCUPANCY_FULL, "fifteen keys, fifteen slots");

        bytes32[12] memory chainKeys = slot0ChainKeys();
        for (uint256 i = 0; i < chainKeys.length; i++) {
            assertEq(slotOf(chainKeys[i]), 0, "chain key hashes into slot 0");
        }
    }

    /// Every occupancy combination with every pointer below `POINTER_HIGH_BIT`.
    function testEveryOccupancyCombinationExported() public pure {
        assertLt(
            freePointer() + (SLOTS - 1) * NODE_BYTES, POINTER_HIGH_BIT, "every node pointer must leave bit 15 clear"
        );
        checkEveryOccupancy();
    }

    /// Every occupancy combination again with every pointer above
    /// `POINTER_HIGH_BIT`, so both states of a pointer's top bit are enumerated
    /// rather than left to wherever the allocator happened to be.
    function testEveryOccupancyCombinationExportedFromHighPointers() public pure {
        bytes memory pad = new bytes(HIGH_POINTER_PAD);
        (pad);
        assertGe(freePointer(), POINTER_HIGH_BIT, "every node pointer must have bit 15 set");
        checkEveryOccupancy();
    }

    /// The length is not a slot. It sits directly above slot 14, which is the
    /// leaf the collapsed path reaches without scrubbing, so a root split that
    /// carried the length into the tree would read it as that leaf's pointer.
    /// Every pair here is on one low list, which leaves the whole high half
    /// empty while the length is far larger than any single insert makes it.
    ///
    /// It is also the only list built longer than one node, so it is the only
    /// place the walk down a list is exercised at all. Which order it comes back
    /// in is not checked, for the same reason the enumerations do not check
    /// theirs.
    function testLengthIsNotRoutedAsAPointer() public pure {
        bytes32[12] memory keys = slot0ChainKeys();

        MemoryKV kv = MemoryKV.wrap(0);
        for (uint256 i = 0; i < keys.length; i++) {
            kv = kv.set(MemoryKVKey.wrap(keys[i]), MemoryKVVal.wrap(valueFor(i)));
        }

        assertEq(occupancyOf(kv), 1, "every slot but slot 0 must be empty");
        assertEq(lengthOf(kv), keys.length * 2, "length far above a single insert");

        bytes32[] memory array = LibMemoryKV.toBytes32Array(kv);
        assertEq(array.length, keys.length * 2, "twelve pairs");
        for (uint256 i = 0; i < keys.length; i++) {
            assertEq(countPair(array, keys[i], valueFor(i)), 1, "each pair exported exactly once");
        }
    }
}
