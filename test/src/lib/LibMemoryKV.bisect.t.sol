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
/// The pre-existing suite only ever exports stores that populate many slots at
/// once, so a slot the bisect drops or misroutes shows up as "some pair is
/// missing" with no indication of which. Each test here occupies one known
/// slot, or one known pair, so the observable failure is the exported key and
/// value of a named slot.
contract LibMemoryKVBisectTest is Test {
    using LibMemoryKV for MemoryKV;

    /// The internal list slot a key hashes into. MUST match `get`/`set`.
    function slotOf(bytes32 key) internal pure returns (uint256) {
        uint256 slot;
        assembly ("memory-safe") {
            mstore(0, key)
            slot := mod(keccak256(0, 0x20), 0x0f)
        }
        return slot;
    }

    /// Rehash `seed` until it lands in `slot`. The search length is unbounded,
    /// so it rehashes in scratch space rather than through `abi.encodePacked`,
    /// which would allocate per attempt. `testAllLowSlotsHighPointerExport` and
    /// `testAllHighSlotsHighPointerExport` pad memory to within 16 bits of the
    /// pointer ceiling `set` enforces, so a per-attempt allocation makes a long
    /// search overflow that ceiling and revert on a seed the fuzzer reaches
    /// roughly once in 300k runs.
    function keyForSlot(bytes32 seed, uint256 slot) internal pure returns (bytes32) {
        bytes32 key = seed;
        while (slotOf(key) != slot) {
            assembly ("memory-safe") {
                mstore(0, key)
                key := keccak256(0, 0x20)
            }
        }
        return key;
    }

    function pointerAt(MemoryKV kv, uint256 slot) internal pure returns (uint256) {
        return (MemoryKV.unwrap(kv) >> (slot * 0x10)) & 0xFFFF;
    }

    function lengthOf(MemoryKV kv) internal pure returns (uint256) {
        return MemoryKV.unwrap(kv) >> 0xf0;
    }

    /// How many times `key` is exported paired with `value`.
    function countPair(bytes32[] memory array, bytes32 key, bytes32 value) internal pure returns (uint256) {
        uint256 found = 0;
        for (uint256 i = 0; i < array.length; i += 2) {
            if (array[i] == key && array[i + 1] == value) {
                found++;
            }
        }
        return found;
    }

    /// A single key in `slot` and nothing else. The exported array must be
    /// exactly that one pair, so a bisect that never visits `slot`, or that
    /// reaches it with a mangled pointer, exports something other than the key
    /// where the key belongs.
    function checkSoleSlot(uint256 slot, bytes32 seed, bytes32 value) internal pure {
        bytes32 key = keyForSlot(seed, slot);
        MemoryKV kv = MemoryKV.wrap(0);
        kv = kv.set(MemoryKVKey.wrap(key), MemoryKVVal.wrap(value));

        assertTrue(pointerAt(kv, slot) > 0, "slot under test must be populated");
        for (uint256 i = 0; i < 15; i++) {
            if (i != slot) {
                assertEq(pointerAt(kv, i), 0, "no other slot may be populated");
            }
        }

        bytes32[] memory array = LibMemoryKV.toBytes32Array(kv);
        assertEq(array.length, 2, "one pair");
        assertEq(array[0], key, "exported key");
        assertEq(array[1], value, "exported value");
    }

    function testLowSlot0SoleExport(bytes32 seed, bytes32 value) public pure {
        checkSoleSlot(0, seed, value);
    }

    function testLowSlot1SoleExport(bytes32 seed, bytes32 value) public pure {
        checkSoleSlot(1, seed, value);
    }

    function testLowSlot2SoleExport(bytes32 seed, bytes32 value) public pure {
        checkSoleSlot(2, seed, value);
    }

    function testLowSlot3SoleExport(bytes32 seed, bytes32 value) public pure {
        checkSoleSlot(3, seed, value);
    }

    function testLowSlot4SoleExport(bytes32 seed, bytes32 value) public pure {
        checkSoleSlot(4, seed, value);
    }

    function testLowSlot5SoleExport(bytes32 seed, bytes32 value) public pure {
        checkSoleSlot(5, seed, value);
    }

    function testLowSlot6SoleExport(bytes32 seed, bytes32 value) public pure {
        checkSoleSlot(6, seed, value);
    }

    function testLowSlot7SoleExport(bytes32 seed, bytes32 value) public pure {
        checkSoleSlot(7, seed, value);
    }

    function testHighSlot8SoleExport(bytes32 seed, bytes32 value) public pure {
        checkSoleSlot(8, seed, value);
    }

    function testHighSlot9SoleExport(bytes32 seed, bytes32 value) public pure {
        checkSoleSlot(9, seed, value);
    }

    function testHighSlot10SoleExport(bytes32 seed, bytes32 value) public pure {
        checkSoleSlot(10, seed, value);
    }

    function testHighSlot11SoleExport(bytes32 seed, bytes32 value) public pure {
        checkSoleSlot(11, seed, value);
    }

    function testHighSlot12SoleExport(bytes32 seed, bytes32 value) public pure {
        checkSoleSlot(12, seed, value);
    }

    function testHighSlot13SoleExport(bytes32 seed, bytes32 value) public pure {
        checkSoleSlot(13, seed, value);
    }

    /// Slot 14 is the leaf the collapsed path reaches. Alone in the store its
    /// 16 bits are the only nonzero bits of `p00`, so a shift of the wrong
    /// distance yields a pointer into unwritten memory rather than the node.
    function testHighSlot14SoleExport(bytes32 seed, bytes32 value) public pure {
        checkSoleSlot(14, seed, value);
    }

    /// Two known slots and nothing else. A mask or shift that folds one onto
    /// the other, or a window that covers one twice, changes how often a pair
    /// appears rather than merely dropping it — which neither slot alone would
    /// reveal.
    function checkSlotPair(uint256 slotA, uint256 slotB, bytes32 seed) internal pure {
        bytes32 keyA = keyForSlot(keccak256(abi.encodePacked(seed, uint256(0))), slotA);
        bytes32 keyB = keyForSlot(keccak256(abi.encodePacked(seed, uint256(1))), slotB);
        bytes32 valA = keccak256(abi.encodePacked(seed, uint256(2)));
        bytes32 valB = keccak256(abi.encodePacked(seed, uint256(3)));

        MemoryKV kv = MemoryKV.wrap(0);
        kv = kv.set(MemoryKVKey.wrap(keyA), MemoryKVVal.wrap(valA));
        kv = kv.set(MemoryKVKey.wrap(keyB), MemoryKVVal.wrap(valB));

        bytes32[] memory array = LibMemoryKV.toBytes32Array(kv);
        assertEq(array.length, 4, "two pairs");
        assertEq(countPair(array, keyA, valA), 1, "first slot of the pair exported exactly once");
        assertEq(countPair(array, keyB, valB), 1, "second slot of the pair exported exactly once");
    }

    /// Both children of one interior node of the low subtree.
    function testLowSlots01Siblings(bytes32 seed) public pure {
        checkSlotPair(0, 1, seed);
    }

    function testLowSlots23Siblings(bytes32 seed) public pure {
        checkSlotPair(2, 3, seed);
    }

    function testLowSlots45Siblings(bytes32 seed) public pure {
        checkSlotPair(4, 5, seed);
    }

    function testLowSlots67Siblings(bytes32 seed) public pure {
        checkSlotPair(6, 7, seed);
    }

    /// Both children of one interior node of the high subtree.
    function testHighSlots89Siblings(bytes32 seed) public pure {
        checkSlotPair(8, 9, seed);
    }

    function testHighSlots1011Siblings(bytes32 seed) public pure {
        checkSlotPair(10, 11, seed);
    }

    /// Slots 12 and 13 are the ordinary leaves under the same node as slot 14,
    /// occupied while slot 14 is not. The collapsed path must read as empty
    /// here: anything left in the bits above slot 14 turns into a pointer and
    /// costs the store a pair.
    function testHighSlots1213Siblings(bytes32 seed) public pure {
        checkSlotPair(12, 13, seed);
    }

    /// The two halves of the root split meet between slot 7 and slot 8. Slots 7
    /// and 8 are not siblings — they are the outermost leaves of different
    /// halves — so one key each side of that boundary is the discriminator for
    /// the split itself: a window that overlaps exports one of them twice, and
    /// a window that leaves a gap drops one.
    function testRootSplitBoundarySlots7And8(bytes32 seed) public pure {
        checkSlotPair(7, 8, seed);
    }

    /// All three leaves below the node that holds slot 14, so the collapsed
    /// path and the ordinary path run against each other. A mask that lets the
    /// collapsed leaf through to the ordinary subtree, or the reverse, changes
    /// how often a pair appears rather than merely dropping it.
    function testHighSlot14WithBothOrdinaryLeaves(bytes32 seed) public pure {
        uint256[3] memory slots = [uint256(12), 13, 14];
        bytes32[3] memory keys;
        bytes32[3] memory values;

        MemoryKV kv = MemoryKV.wrap(0);
        for (uint256 i = 0; i < slots.length; i++) {
            keys[i] = keyForSlot(keccak256(abi.encodePacked(seed, i)), slots[i]);
            values[i] = keccak256(abi.encodePacked(seed, i, uint256(1)));
            kv = kv.set(MemoryKVKey.wrap(keys[i]), MemoryKVVal.wrap(values[i]));
        }

        for (uint256 i = 0; i < 12; i++) {
            assertEq(pointerAt(kv, i), 0, "only slots 12..14 may be populated");
        }

        bytes32[] memory array = LibMemoryKV.toBytes32Array(kv);
        assertEq(array.length, 6, "three pairs");
        for (uint256 i = 0; i < slots.length; i++) {
            assertEq(countPair(array, keys[i], values[i]), 1, "each leaf exported exactly once");
        }
    }

    /// Every slot of one half populated and no slot of the other, so every leaf
    /// of that half fires and each must fire exactly once. A leaf that copies
    /// without carrying the cursor forward is overwritten by the next one.
    function checkHalfExport(uint256 firstSlot, uint256 slotCount, bytes32 seed) internal pure {
        bytes32[] memory keys = new bytes32[](slotCount);
        bytes32[] memory values = new bytes32[](slotCount);
        MemoryKV kv = MemoryKV.wrap(0);
        for (uint256 i = 0; i < slotCount; i++) {
            keys[i] = keyForSlot(keccak256(abi.encodePacked(seed, i)), firstSlot + i);
            values[i] = keccak256(abi.encodePacked(seed, i, uint256(1)));
            kv = kv.set(MemoryKVKey.wrap(keys[i]), MemoryKVVal.wrap(values[i]));
        }

        for (uint256 slot = 0; slot < 15; slot++) {
            if (slot >= firstSlot && slot < firstSlot + slotCount) {
                assertTrue(pointerAt(kv, slot) > 0, "slot of the half under test populated");
            } else {
                assertEq(pointerAt(kv, slot), 0, "slot of the other half empty");
            }
        }

        bytes32[] memory array = LibMemoryKV.toBytes32Array(kv);
        assertEq(array.length, slotCount * 2, "one pair per slot of the half");
        for (uint256 i = 0; i < slotCount; i++) {
            assertEq(countPair(array, keys[i], values[i]), 1, "each slot of the half exported exactly once");
        }
    }

    /// Every slot of one half holding a pointer with its top bit set. A 16 bit
    /// pointer is valid all the way to `0xFFFF`, so every mask and shift on the
    /// way down must carry bit 15. Padding memory first pushes the free memory
    /// pointer, and therefore every inserted node, above `0x8000`.
    function checkHalfHighPointerExport(uint256 firstSlot, uint256 slotCount, bytes32 seed) internal pure {
        bytes memory pad = new bytes(0x9000);
        (pad);

        bytes32[] memory keys = new bytes32[](slotCount);
        bytes32[] memory values = new bytes32[](slotCount);
        MemoryKV kv = MemoryKV.wrap(0);
        for (uint256 i = 0; i < slotCount; i++) {
            keys[i] = keyForSlot(keccak256(abi.encodePacked(seed, i)), firstSlot + i);
            values[i] = keccak256(abi.encodePacked(seed, i, uint256(1)));
            kv = kv.set(MemoryKVKey.wrap(keys[i]), MemoryKVVal.wrap(values[i]));
        }

        for (uint256 slot = firstSlot; slot < firstSlot + slotCount; slot++) {
            assertTrue(pointerAt(kv, slot) >= 0x8000, "pointer must have bit 15 set");
            assertTrue(pointerAt(kv, slot) <= 0xFFFF, "pointer must stay 16 bit");
        }

        bytes32[] memory array = LibMemoryKV.toBytes32Array(kv);
        assertEq(array.length, slotCount * 2, "one pair per slot of the half");
        for (uint256 i = 0; i < slotCount; i++) {
            assertEq(countPair(array, keys[i], values[i]), 1, "each high pointer slot exported exactly once");
        }
    }

    function testAllLowSlotsExport(bytes32 seed) public pure {
        checkHalfExport(0, 8, seed);
    }

    function testAllHighSlotsExport(bytes32 seed) public pure {
        checkHalfExport(8, 7, seed);
    }

    function testAllLowSlotsHighPointerExport(bytes32 seed) public pure {
        checkHalfHighPointerExport(0, 8, seed);
    }

    function testAllHighSlotsHighPointerExport(bytes32 seed) public pure {
        checkHalfHighPointerExport(8, 7, seed);
    }

    /// All fifteen slots at once. The two halves must be disjoint and must
    /// between them reach every slot, so every pair appears exactly once: a
    /// window that is too wide duplicates, one that is too narrow drops, and a
    /// leaf that does not carry the cursor forward is overwritten.
    function testEverySlotExportedExactlyOnce(bytes32 seed) public pure {
        bytes32[15] memory keys;
        bytes32[15] memory values;
        MemoryKV kv = MemoryKV.wrap(0);
        for (uint256 slot = 0; slot < 15; slot++) {
            keys[slot] = keyForSlot(keccak256(abi.encodePacked(seed, slot)), slot);
            values[slot] = keccak256(abi.encodePacked(seed, slot, uint256(1)));
            kv = kv.set(MemoryKVKey.wrap(keys[slot]), MemoryKVVal.wrap(values[slot]));
        }

        bytes32[] memory array = LibMemoryKV.toBytes32Array(kv);
        assertEq(array.length, 30, "fifteen pairs");
        for (uint256 slot = 0; slot < 15; slot++) {
            assertEq(countPair(array, keys[slot], values[slot]), 1, "each slot exported exactly once");
        }
    }

    /// The length is not a slot. It sits directly above slot 14, which is the
    /// leaf the collapsed path reaches without scrubbing, so a root split that
    /// carried the length into the tree would read it as that leaf's pointer.
    /// Every pair here is on one low list, which leaves the whole high half
    /// empty while the length is far larger than any single insert makes it.
    function testLengthIsNotRoutedAsAPointer(bytes32 seed) public pure {
        bytes32[12] memory keys;
        bytes32[12] memory values;
        MemoryKV kv = MemoryKV.wrap(0);
        for (uint256 i = 0; i < 12; i++) {
            keys[i] = keyForSlot(keccak256(abi.encodePacked(seed, i)), 0);
            values[i] = keccak256(abi.encodePacked(seed, i, uint256(1)));
            kv = kv.set(MemoryKVKey.wrap(keys[i]), MemoryKVVal.wrap(values[i]));
        }

        for (uint256 i = 8; i < 15; i++) {
            assertEq(pointerAt(kv, i), 0, "high half must be empty");
        }
        assertEq(lengthOf(kv), 24, "length far above a single insert");

        bytes32[] memory array = LibMemoryKV.toBytes32Array(kv);
        assertEq(array.length, 24, "twelve pairs");
        for (uint256 i = 0; i < 12; i++) {
            assertEq(countPair(array, keys[i], values[i]), 1, "each pair exported exactly once");
        }
    }
}
