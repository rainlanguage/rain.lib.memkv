// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal} from "src/lib/LibMemoryKV.sol";

/// Pins the low half of the `toBytes32Array` bisect tree, which is the only
/// path by which internal list slots 0..7 reach the exported array.
///
/// The pre-existing suite only ever exports stores that populate many slots at
/// once, so a slot that the bisect drops or misroutes shows up as "some pair is
/// missing" with no indication of which slot. These tests occupy one known slot
/// (or one known sibling pair) at a time, so the observable failure is the
/// exported key/value of that specific slot.
contract LibMemoryKVBisectLowTest is Test {
    using LibMemoryKV for MemoryKV;

    /// The internal list slot a key hashes into. MUST match `get`/`set`.
    function slotOf(bytes32 key) internal pure returns (uint256 slot) {
        assembly ("memory-safe") {
            mstore(0, key)
            slot := mod(keccak256(0, 0x20), 15)
        }
    }

    /// Rehash `seed` until it lands in `slot`.
    function keyForSlot(bytes32 seed, uint256 slot) internal pure returns (bytes32 key) {
        key = seed;
        while (slotOf(key) != slot) {
            key = keccak256(abi.encodePacked(key));
        }
    }

    function pointerAt(MemoryKV kv, uint256 slot) internal pure returns (uint256) {
        return (MemoryKV.unwrap(kv) >> (slot * 0x10)) & 0xFFFF;
    }

    /// A single key in `slot` and nothing else. The exported array must be
    /// exactly that one pair, so a bisect that never visits `slot` exports a
    /// zero word where the key belongs.
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

    /// Both children of one interior node of the low subtree, and nothing else.
    /// A mask or shift that folds one sibling onto the other loses a pair here
    /// even though each sibling alone would still be found.
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

        uint256 foundA = 0;
        uint256 foundB = 0;
        for (uint256 j = 0; j < array.length; j += 2) {
            if (array[j] == keyA && array[j + 1] == valA) {
                foundA++;
            }
            if (array[j] == keyB && array[j + 1] == valB) {
                foundB++;
            }
        }
        assertEq(foundA, 1, "first sibling exported exactly once");
        assertEq(foundB, 1, "second sibling exported exactly once");
    }

    function testLowSlots67Siblings(bytes32 seed) public pure {
        checkSiblingSlots(6, 7, seed);
    }

    function testLowSlots45Siblings(bytes32 seed) public pure {
        checkSiblingSlots(4, 5, seed);
    }

    function testLowSlots23Siblings(bytes32 seed) public pure {
        checkSiblingSlots(2, 3, seed);
    }

    function testLowSlots01Siblings(bytes32 seed) public pure {
        checkSiblingSlots(0, 1, seed);
    }

    /// All eight low slots populated and no high slot, so every exported pair
    /// came through the low subtree and each of its eight leaves must fire
    /// exactly once.
    function testAllLowSlotsExport(bytes32 seed) public pure {
        bytes32[8] memory keys;
        bytes32[8] memory values;
        MemoryKV kv = MemoryKV.wrap(0);
        for (uint256 i = 0; i < 8; i++) {
            keys[i] = keyForSlot(keccak256(abi.encodePacked(seed, i)), i);
            values[i] = keccak256(abi.encodePacked(seed, i, uint256(1)));
            kv = kv.set(MemoryKVKey.wrap(keys[i]), MemoryKVVal.wrap(values[i]));
        }

        for (uint256 i = 0; i < 8; i++) {
            assertTrue(pointerAt(kv, i) > 0, "low slot populated");
        }
        for (uint256 i = 8; i < 15; i++) {
            assertEq(pointerAt(kv, i), 0, "high slot empty");
        }

        bytes32[] memory array = LibMemoryKV.toBytes32Array(kv);
        assertEq(array.length, 16, "eight pairs");

        for (uint256 i = 0; i < 8; i++) {
            uint256 found = 0;
            for (uint256 j = 0; j < array.length; j += 2) {
                if (array[j] == keys[i] && array[j + 1] == values[i]) {
                    found++;
                }
            }
            assertEq(found, 1, "each low slot exported exactly once");
        }
    }

    /// Every low slot holding a pointer with its top bit set. A 16 bit pointer
    /// is valid all the way to `0xFFFF`, so the bisect must carry bit 15 of
    /// every slot through. Padding memory first pushes the free memory pointer,
    /// and therefore every inserted node, above `0x8000`.
    function testAllLowSlotsHighPointerExport(bytes32 seed) public pure {
        bytes memory pad = new bytes(0x9000);
        (pad);

        bytes32[8] memory keys;
        bytes32[8] memory values;
        MemoryKV kv = MemoryKV.wrap(0);
        for (uint256 i = 0; i < 8; i++) {
            keys[i] = keyForSlot(keccak256(abi.encodePacked(seed, i)), i);
            values[i] = keccak256(abi.encodePacked(seed, i, uint256(1)));
            kv = kv.set(MemoryKVKey.wrap(keys[i]), MemoryKVVal.wrap(values[i]));
        }

        for (uint256 i = 0; i < 8; i++) {
            assertTrue(pointerAt(kv, i) >= 0x8000, "pointer must have bit 15 set");
            assertTrue(pointerAt(kv, i) <= 0xFFFF, "pointer must stay 16 bit");
        }

        bytes32[] memory array = LibMemoryKV.toBytes32Array(kv);
        assertEq(array.length, 16, "eight pairs");

        for (uint256 i = 0; i < 8; i++) {
            uint256 found = 0;
            for (uint256 j = 0; j < array.length; j += 2) {
                if (array[j] == keys[i] && array[j + 1] == values[i]) {
                    found++;
                }
            }
            assertEq(found, 1, "each high pointer slot exported exactly once");
        }
    }
}
