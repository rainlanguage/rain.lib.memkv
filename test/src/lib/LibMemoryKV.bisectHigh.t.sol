// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal} from "src/lib/LibMemoryKV.sol";

/// Pins the high half of the `toBytes32Array` bisect tree and the root split
/// that carves it out of `kv`.
///
/// The high half routes internal list slots 8..14. It is seven leaves where
/// the low half is eight, because the 16 bit length field occupies the bits an
/// eighth leaf would need and `shr(0x90, shl(0x10, kv))` shifts it out before
/// the tree runs. Slot 14 is then reached by `shr(0x20, p00)`, which collapses
/// an interior node and omits the 16 bit scrub the mirroring leaf of the low
/// half performs. That omission is sound only while the length is zeroed, so
/// the two are pinned together here.
///
/// Each test occupies one known slot, or one known sibling pair, so a branch
/// that drops or misroutes a slot fails as that slot's key and value rather
/// than as a missing pair somewhere in a large store.
contract LibMemoryKVBisectHighTest is Test {
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
    /// which would allocate per attempt. `testAllHighSlotsHighPointerExport`
    /// pads memory to within 16 bits of the pointer ceiling `set` enforces, so
    /// a per-attempt allocation makes a long search overflow that ceiling and
    /// revert on a seed the fuzzer reaches roughly once in 300k runs.
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

    /// Both children of one interior node of the high subtree, and nothing
    /// else. A mask or shift that folds one sibling onto the other loses a
    /// pair here even though each sibling alone would still be found.
    function checkSiblingSlots(uint256 slotA, uint256 slotB, bytes32 seed) internal pure {
        bytes32 keyA = keyForSlot(keccak256(abi.encodePacked(seed, uint256(0))), slotA);
        bytes32 keyB = keyForSlot(keccak256(abi.encodePacked(seed, uint256(1))), slotB);
        bytes32 valA = keccak256(abi.encodePacked(seed, uint256(2)));
        bytes32 valB = keccak256(abi.encodePacked(seed, uint256(3)));

        MemoryKV kv = MemoryKV.wrap(0);
        kv = kv.set(MemoryKVKey.wrap(keyA), MemoryKVVal.wrap(valA));
        kv = kv.set(MemoryKVKey.wrap(keyB), MemoryKVVal.wrap(valB));

        bytes32[] memory array = LibMemoryKV.toBytes32Array(kv);
        assertEq(array.length, 4, "two pairs");
        assertEq(countPair(array, keyA, valA), 1, "first sibling exported exactly once");
        assertEq(countPair(array, keyB, valB), 1, "second sibling exported exactly once");
    }

    function testHighSlots89Siblings(bytes32 seed) public pure {
        checkSiblingSlots(8, 9, seed);
    }

    function testHighSlots1011Siblings(bytes32 seed) public pure {
        checkSiblingSlots(10, 11, seed);
    }

    /// Slots 12 and 13 are the ordinary leaves under the same node as slot 14,
    /// occupied while slot 14 is not. The collapsed path must read as empty
    /// here: anything left in the bits above slot 14 turns into a pointer and
    /// costs the store a pair.
    function testHighSlots1213Siblings(bytes32 seed) public pure {
        checkSiblingSlots(12, 13, seed);
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

    /// Every high slot populated and no low slot, so all seven leaves of the
    /// high subtree fire and each must fire exactly once. A leaf that copies
    /// without carrying the cursor forward is overwritten by the next one.
    function testAllHighSlotsExport(bytes32 seed) public pure {
        bytes32[7] memory keys;
        bytes32[7] memory values;
        MemoryKV kv = MemoryKV.wrap(0);
        for (uint256 i = 0; i < 7; i++) {
            keys[i] = keyForSlot(keccak256(abi.encodePacked(seed, i)), i + 8);
            values[i] = keccak256(abi.encodePacked(seed, i, uint256(1)));
            kv = kv.set(MemoryKVKey.wrap(keys[i]), MemoryKVVal.wrap(values[i]));
        }

        for (uint256 i = 0; i < 8; i++) {
            assertEq(pointerAt(kv, i), 0, "low slot empty");
        }
        for (uint256 i = 8; i < 15; i++) {
            assertTrue(pointerAt(kv, i) > 0, "high slot populated");
        }

        bytes32[] memory array = LibMemoryKV.toBytes32Array(kv);
        assertEq(array.length, 14, "seven pairs");
        for (uint256 i = 0; i < 7; i++) {
            assertEq(countPair(array, keys[i], values[i]), 1, "each high slot exported exactly once");
        }
    }

    /// Every high slot holding a pointer with its top bit set. A 16 bit
    /// pointer is valid all the way to `0xFFFF`, so every mask and shift on
    /// the way down the high subtree must carry bit 15. Padding memory first
    /// pushes the free memory pointer, and therefore every inserted node,
    /// above `0x8000`.
    function testAllHighSlotsHighPointerExport(bytes32 seed) public pure {
        bytes memory pad = new bytes(0x9000);
        (pad);

        bytes32[7] memory keys;
        bytes32[7] memory values;
        MemoryKV kv = MemoryKV.wrap(0);
        for (uint256 i = 0; i < 7; i++) {
            keys[i] = keyForSlot(keccak256(abi.encodePacked(seed, i)), i + 8);
            values[i] = keccak256(abi.encodePacked(seed, i, uint256(1)));
            kv = kv.set(MemoryKVKey.wrap(keys[i]), MemoryKVVal.wrap(values[i]));
        }

        for (uint256 i = 8; i < 15; i++) {
            assertTrue(pointerAt(kv, i) >= 0x8000, "pointer must have bit 15 set");
            assertTrue(pointerAt(kv, i) <= 0xFFFF, "pointer must stay 16 bit");
        }

        bytes32[] memory array = LibMemoryKV.toBytes32Array(kv);
        assertEq(array.length, 14, "seven pairs");
        for (uint256 i = 0; i < 7; i++) {
            assertEq(countPair(array, keys[i], values[i]), 1, "each high pointer slot exported exactly once");
        }
    }

    /// The two halves of the root split meet between slot 7 and slot 8. One
    /// key on each side of that boundary and nothing else: a window that
    /// overlaps exports one of them twice, and a window that leaves a gap
    /// drops one.
    function testRootSplitBoundarySlots7And8(bytes32 seed) public pure {
        bytes32 keyLow = keyForSlot(keccak256(abi.encodePacked(seed, uint256(0))), 7);
        bytes32 keyHigh = keyForSlot(keccak256(abi.encodePacked(seed, uint256(1))), 8);
        bytes32 valLow = keccak256(abi.encodePacked(seed, uint256(2)));
        bytes32 valHigh = keccak256(abi.encodePacked(seed, uint256(3)));

        MemoryKV kv = MemoryKV.wrap(0);
        kv = kv.set(MemoryKVKey.wrap(keyLow), MemoryKVVal.wrap(valLow));
        kv = kv.set(MemoryKVKey.wrap(keyHigh), MemoryKVVal.wrap(valHigh));

        bytes32[] memory array = LibMemoryKV.toBytes32Array(kv);
        assertEq(array.length, 4, "two pairs");
        assertEq(countPair(array, keyLow, valLow), 1, "slot 7 exported exactly once");
        assertEq(countPair(array, keyHigh, valHigh), 1, "slot 8 exported exactly once");
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
