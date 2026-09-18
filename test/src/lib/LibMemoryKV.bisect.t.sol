// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";

import {LibPointer, Pointer} from "rain-solmem-0.1.28/src/lib/LibPointer.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {slotOf} from "test/lib/LibMemoryKVKeys.sol";
import {headOf, lengthOf} from "test/lib/LibMemoryKVHandle.sol";
import {countPair} from "test/lib/LibMemoryKVExport.sol";
import {setFreePointer, raiseFreePointerTo} from "test/lib/LibFreeMemory.sol";

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
/// That leaf reads slot 14 alone because the root split has already zeroed the
/// length.
///
/// The named tests each occupy one known slot, or one known pair, or one known
/// boundary, and the test name says which.
///
/// The enumerations run every combination of which slots are occupied. That is
/// the tree's whole input: each of its twenty eight guards tests a window of
/// `kv` against zero, and nothing it does branches on what a key or a value is.
/// Fifteen slots is 32768 combinations, so the enumerations cover the named
/// cases too, and nothing is sampled.
///
/// `slotKeys` is one constant key per slot, so every test here chooses its
/// occupancy and none takes a fuzz input.
///
/// Every node of every case an enumeration builds is allocated from a free
/// memory pointer that is rewound between cases.
contract LibMemoryKVBisectTest is Test {
    using LibMemoryKV for MemoryKV;

    /// Every combination of which slots are occupied.
    uint256 internal constant OCCUPANCY_COMBINATIONS = 2 ** LibMemoryKV.LIST_COUNT;

    /// Every slot occupied.
    uint256 internal constant OCCUPANCY_FULL = OCCUPANCY_COMBINATIONS - 1;

    /// Slots 0..7, the half the root split routes out of `and(mask128, kv)`.
    uint256 internal constant OCCUPANCY_LOW_HALF = 0x00FF;

    /// Slots 8..14, the half the root split shifts the length out of.
    uint256 internal constant OCCUPANCY_HIGH_HALF = 0x7F00;

    /// The top bit of a head pointer slot. A pointer is valid all the way to
    /// `LibMemoryKV.POINTER_MASK`, so every mask and shift on the way down the
    /// tree must carry this bit.
    uint256 internal constant POINTER_HIGH_BIT = 2 ** (LibMemoryKV.SLOT_BITS - 1);

    /// Stands for "no mask", which a 15 bit mask cannot collide with.
    uint256 internal constant NO_MASK = type(uint256).max;

    /// Values sit above every key, so no value word equals a key word. A value
    /// is this base plus the slot it belongs to, so no two slots share a value,
    /// which is how `exportMatches` reads a pair's slot back out of it.
    uint256 internal constant VALUE_BASE = 0x100;

    /// One key per slot: the smallest positive integer whose 32 byte big endian
    /// encoding hashes into that slot. Regenerating one is
    /// `cast keccak $(cast to-uint256 <n>)` reduced modulo
    /// `LibMemoryKV.LIST_COUNT`, and `testKeyConstantsLandWhereClaimed` is what
    /// holds them to it.
    function slotKeys() internal pure returns (bytes32[] memory keys) {
        keys = new bytes32[](LibMemoryKV.LIST_COUNT);
        keys[0] = bytes32(uint256(4));
        keys[1] = bytes32(uint256(31));
        keys[2] = bytes32(uint256(2));
        keys[3] = bytes32(uint256(1));
        keys[4] = bytes32(uint256(9));
        keys[5] = bytes32(uint256(49));
        keys[6] = bytes32(uint256(24));
        keys[7] = bytes32(uint256(42));
        keys[8] = bytes32(uint256(3));
        keys[9] = bytes32(uint256(21));
        keys[10] = bytes32(uint256(16));
        keys[11] = bytes32(uint256(7));
        keys[12] = bytes32(uint256(6));
        keys[13] = bytes32(uint256(14));
        keys[14] = bytes32(uint256(11));
    }

    /// The twelve smallest positive integers that all hash into slot 0, for the
    /// one test that needs one list many nodes long, so the length is far above
    /// what any single insert leaves it at while the high half stays empty.
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

    /// How many slots `mask` names.
    function occupiedCount(uint256 mask) internal pure returns (uint256) {
        uint256 count = 0;
        for (uint256 slot = 0; slot < LibMemoryKV.LIST_COUNT; slot++) {
            if (occupies(mask, slot)) {
                count++;
            }
        }
        return count;
    }

    /// Which slots of `kv` hold a pointer, in the same bit order as an occupancy
    /// mask.
    function occupancyOf(MemoryKV kv) internal pure returns (uint256) {
        uint256 occupancy = 0;
        for (uint256 i = 0; i < LibMemoryKV.LIST_COUNT; i++) {
            occupancy <<= 1;
            if (headOf(kv, LibMemoryKV.LIST_COUNT - 1 - i) != 0) {
                occupancy |= 1;
            }
        }
        return occupancy;
    }

    function freePointer() internal pure returns (uint256) {
        return Pointer.unwrap(LibPointer.allocatedMemoryPointer());
    }

    /// The store holding one key in each slot `mask` names.
    function storeForOccupancy(uint256 mask, bytes32[] memory keys) internal pure returns (MemoryKV) {
        MemoryKV kv = MEMORY_KV_EMPTY;
        for (uint256 slot = 0; slot < LibMemoryKV.LIST_COUNT; slot++) {
            if (occupies(mask, slot)) {
                kv = kv.set(MemoryKVKey.wrap(keys[slot]), MemoryKVVal.wrap(valueFor(slot)));
            }
        }
        return kv;
    }

    /// Exports the store and holds it to the pairs `mask` names, one pair per
    /// named slot and each exported exactly once. Order is not checked, per
    /// `exportMatches`.
    function checkExportedPairs(MemoryKV kv, uint256 mask, bytes32[] memory keys) internal pure {
        bytes32[] memory array = kv.toBytes32Array();
        assertEq(array.length, occupiedCount(mask) * 2, "one pair per occupied slot");
        for (uint256 slot = 0; slot < LibMemoryKV.LIST_COUNT; slot++) {
            if (occupies(mask, slot)) {
                assertEq(countPair(array, keys[slot], valueFor(slot)), 1, "occupied slot exported exactly once");
            }
        }
    }

    /// The store `mask` names, occupying exactly those slots and exporting
    /// exactly their pairs.
    function checkNamedOccupancy(uint256 mask) internal pure {
        bytes32[] memory keys = slotKeys();
        MemoryKV kv = storeForOccupancy(mask, keys);
        assertEq(occupancyOf(kv), mask, "exactly the named slots are populated");
        checkExportedPairs(kv, mask, keys);
    }

    /// The store `mask` names, with every pointer in it at or above
    /// `POINTER_HIGH_BIT`. A 16 bit pointer is valid all the way to
    /// `LibMemoryKV.POINTER_MASK`, so every mask and shift on the way down must
    /// carry bit 15.
    function checkNamedOccupancyFromHighPointers(uint256 mask) internal pure {
        raiseFreePointerTo(POINTER_HIGH_BIT);

        bytes32[] memory keys = slotKeys();
        MemoryKV kv = storeForOccupancy(mask, keys);
        assertEq(occupancyOf(kv), mask, "exactly the named slots are populated");
        for (uint256 slot = 0; slot < LibMemoryKV.LIST_COUNT; slot++) {
            if (occupies(mask, slot)) {
                assertGe(headOf(kv, slot), POINTER_HIGH_BIT, "pointer must have bit 15 set");
            }
        }
        checkExportedPairs(kv, mask, keys);
    }

    /// A single key in `slot` and nothing else. The exported array is exactly
    /// that one pair: the slot's key, then its value.
    function checkSoleSlot(uint256 slot) internal pure {
        bytes32[] memory keys = slotKeys();
        MemoryKV kv = storeForOccupancy(2 ** slot, keys);
        assertEq(occupancyOf(kv), 2 ** slot, "only the slot under test is populated");

        bytes32[] memory array = kv.toBytes32Array();
        assertEq(array.length, 2, "one pair");
        assertEq(array[0], keys[slot], "exported key");
        assertEq(array[1], valueFor(slot), "exported value");
    }

    function testLowSlot0SoleExport() public pure {
        checkSoleSlot(0);
    }

    function testLowSlot1SoleExport() public pure {
        checkSoleSlot(1);
    }

    function testLowSlot2SoleExport() public pure {
        checkSoleSlot(2);
    }

    function testLowSlot3SoleExport() public pure {
        checkSoleSlot(3);
    }

    function testLowSlot4SoleExport() public pure {
        checkSoleSlot(4);
    }

    function testLowSlot5SoleExport() public pure {
        checkSoleSlot(5);
    }

    function testLowSlot6SoleExport() public pure {
        checkSoleSlot(6);
    }

    function testLowSlot7SoleExport() public pure {
        checkSoleSlot(7);
    }

    function testHighSlot8SoleExport() public pure {
        checkSoleSlot(8);
    }

    function testHighSlot9SoleExport() public pure {
        checkSoleSlot(9);
    }

    function testHighSlot10SoleExport() public pure {
        checkSoleSlot(10);
    }

    function testHighSlot11SoleExport() public pure {
        checkSoleSlot(11);
    }

    function testHighSlot12SoleExport() public pure {
        checkSoleSlot(12);
    }

    function testHighSlot13SoleExport() public pure {
        checkSoleSlot(13);
    }

    /// Slot 14 is the leaf the collapsed path reaches. Alone in the store its
    /// 16 bits are the only nonzero bits of `p00`, and the export reaches its
    /// node through them.
    function testHighSlot14SoleExport() public pure {
        checkSoleSlot(14);
    }

    /// Two known slots and nothing else, each exported exactly once.
    function checkSlotPair(uint256 slotA, uint256 slotB) internal pure {
        checkNamedOccupancy(2 ** slotA | 2 ** slotB);
    }

    /// Both children of one interior node of the low subtree.
    function testLowSlots01Siblings() public pure {
        checkSlotPair(0, 1);
    }

    function testLowSlots23Siblings() public pure {
        checkSlotPair(2, 3);
    }

    function testLowSlots45Siblings() public pure {
        checkSlotPair(4, 5);
    }

    function testLowSlots67Siblings() public pure {
        checkSlotPair(6, 7);
    }

    /// Both children of one interior node of the high subtree.
    function testHighSlots89Siblings() public pure {
        checkSlotPair(8, 9);
    }

    function testHighSlots1011Siblings() public pure {
        checkSlotPair(10, 11);
    }

    /// Slots 12 and 13 are the ordinary leaves under the same node as slot 14,
    /// occupied while slot 14 is not. The collapsed path reads as empty here,
    /// and the export is exactly the two pairs.
    function testHighSlots1213Siblings() public pure {
        checkSlotPair(12, 13);
    }

    /// The two halves of the root split meet between slot 7 and slot 8. Slots 7
    /// and 8 are not siblings — they are the outermost leaves of different
    /// halves — so this is one key each side of the split, each exported
    /// exactly once.
    function testRootSplitBoundarySlots7And8() public pure {
        checkSlotPair(7, 8);
    }

    /// All three leaves below the node that holds slot 14, so the collapsed
    /// path and the ordinary path run in one export, and each of the three
    /// pairs is exported exactly once.
    function testHighSlot14WithBothOrdinaryLeaves() public pure {
        checkNamedOccupancy(2 ** 12 | 2 ** 13 | 2 ** 14);
    }

    /// Every slot of one half populated and no slot of the other, so every leaf
    /// of that half fires and each must fire exactly once.
    function testAllLowSlotsExport() public pure {
        checkNamedOccupancy(OCCUPANCY_LOW_HALF);
    }

    function testAllHighSlotsExport() public pure {
        checkNamedOccupancy(OCCUPANCY_HIGH_HALF);
    }

    /// Every slot of one half again, holding pointers with bit 15 set.
    function testAllLowSlotsHighPointerExport() public pure {
        checkNamedOccupancyFromHighPointers(OCCUPANCY_LOW_HALF);
    }

    function testAllHighSlotsHighPointerExport() public pure {
        checkNamedOccupancyFromHighPointers(OCCUPANCY_HIGH_HALF);
    }

    /// All fifteen slots at once. The two halves must be disjoint and must
    /// between them reach every slot, so every pair appears exactly once.
    function testEverySlotExportedExactlyOnce() public pure {
        checkNamedOccupancy(OCCUPANCY_FULL);
    }

    /// Whether `array` holds exactly the pairs `mask` must export, as a
    /// multiset. `toBytes32Array` documents its pair order as unspecified, so
    /// position is not checked.
    ///
    /// Each value is `VALUE_BASE + slot`, so the slot a pair claims is read out
    /// of its own value, and the pair is then held to the key that slot must
    /// carry. Collecting those slots into a bitset and comparing it to `mask` is
    /// multiset equality without a scan per pair: a slot exported twice is
    /// caught by its bit already being set, and one dropped, duplicated or
    /// invented by the bitsets differing.
    function exportMatches(bytes32[] memory array, uint256 mask, bytes32[] memory keys) internal pure returns (bool) {
        if (array.length % 2 != 0) {
            return false;
        }

        uint256 found = 0;
        for (uint256 cursor = 0; cursor < array.length; cursor += 2) {
            uint256 value = uint256(array[cursor + 1]);
            if (value < VALUE_BASE || value >= VALUE_BASE + LibMemoryKV.LIST_COUNT) {
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
    ///
    /// Every case is built from one free memory pointer, `free`, taken after
    /// `slotKeys` has allocated, so every node of every case lies in
    /// `[free, free + (LibMemoryKV.LIST_COUNT - 1) * LibMemoryKV.NODE_BYTES]`.
    /// That range is what `floor` and `ceiling` are checked against.
    /// @param floor The lowest node pointer the caller requires.
    /// @param ceiling The highest node pointer the caller requires.
    function checkEveryOccupancy(uint256 floor, uint256 ceiling) internal pure {
        bytes32[] memory keys = slotKeys();

        uint256 free = freePointer();
        assertGe(free, floor, "lowest node pointer below the required floor");
        assertLe(
            free + (LibMemoryKV.LIST_COUNT - 1) * LibMemoryKV.NODE_BYTES,
            ceiling,
            "highest node pointer above the required ceiling"
        );

        uint256 failed = NO_MASK;
        for (uint256 mask = 0; mask < OCCUPANCY_COMBINATIONS; mask++) {
            setFreePointer(free);
            if (!exportMatches(storeForOccupancy(mask, keys).toBytes32Array(), mask, keys)) {
                failed = mask;
                break;
            }
        }

        assertEq(failed, NO_MASK, "occupancy mask whose export did not match");
    }

    /// Each key constant hashes into the slot it is claimed for, and every
    /// chain key into slot 0. Every test in this file reads its result through
    /// the slot each key claims.
    ///
    /// Occupying all fifteen at once populates fifteen distinct slots. `set`
    /// routes on the key alone, so that plus one key per slot is every
    /// occupancy.
    function testKeyConstantsLandWhereClaimed() public pure {
        bytes32[] memory keys = slotKeys();
        for (uint256 slot = 0; slot < LibMemoryKV.LIST_COUNT; slot++) {
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
        checkEveryOccupancy(0, POINTER_HIGH_BIT - 1);
    }

    /// Every occupancy combination again with every pointer at or above
    /// `POINTER_HIGH_BIT`, so both states of a pointer's top bit are
    /// enumerated.
    function testEveryOccupancyCombinationExportedFromHighPointers() public pure {
        raiseFreePointerTo(POINTER_HIGH_BIT);
        checkEveryOccupancy(POINTER_HIGH_BIT, LibMemoryKV.POINTER_MASK);
    }

    /// The length is not a slot. It sits directly above slot 14, which is the
    /// leaf the collapsed path reaches without scrubbing, and the export reads
    /// no pointer out of it. Every pair here is on one low list, which leaves the whole high half
    /// empty while the length is far larger than any single insert makes it.
    ///
    /// It is also the only list built longer than one node, so it is the only
    /// place the walk down a list is exercised at all. Which order it comes back
    /// in is not checked, for the same reason nothing else here checks theirs.
    function testLengthIsNotRoutedAsAPointer() public pure {
        bytes32[12] memory keys = slot0ChainKeys();

        MemoryKV kv = MEMORY_KV_EMPTY;
        for (uint256 i = 0; i < keys.length; i++) {
            kv = kv.set(MemoryKVKey.wrap(keys[i]), MemoryKVVal.wrap(valueFor(i)));
        }

        assertEq(occupancyOf(kv), 1, "every slot but slot 0 must be empty");
        assertEq(lengthOf(kv), keys.length * 2, "length far above a single insert");

        bytes32[] memory array = kv.toBytes32Array();
        assertEq(array.length, keys.length * 2, "twelve pairs");
        for (uint256 i = 0; i < keys.length; i++) {
            assertEq(countPair(array, keys[i], valueFor(i)), 1, "each pair exported exactly once");
        }
    }
}
