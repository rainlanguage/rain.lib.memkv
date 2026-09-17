// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {LibMemoryKV, MemoryKV, MemoryKVVal, MemoryKVKey, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {keyForSlot, keysInSlot} from "test/lib/LibMemoryKVTestHelpers.sol";
import {LibMemoryKVSlow} from "test/lib/LibMemoryKVSlow.sol";

/// Pins the gas figures the library documents for itself. Those figures are the
/// reason the export is a bisect rather than a loop and the reason any of this
/// is assembly, and the rest of the suite cannot tell whether they still hold:
/// the skip guards that produce the saving are invisible to a test that only
/// reads the exported pairs.
contract LibMemoryKVGasClaimsTest is Test {
    /// `kv` carries one pointer per internal linked list.
    uint256 constant SLOTS = 0x0f;

    /// The one slot the bisect reaches a level early. The length occupies the
    /// high bits of `kv`, so stripping it leaves the last slot's pointer already
    /// isolated and the tree tests it directly instead of descending to it.
    uint256 constant SHALLOW_SLOT = 0x0e;

    /// `toBytes32Array` NatSpec: "the bisect approach can save ~1-1.5k gas vs. a
    /// naive linear loop over all 15 slots for every export".
    uint256 constant BISECT_SAVING = 1000;

    /// The largest store the saving is claimed for. Beyond it the per-pair
    /// copying, which both implementations do identically, dominates.
    uint256 constant BISECT_SAVING_MAX_PAIRS = 5;

    /// README: "A key alone in its list costs ~240 gas to get and ~390 gas to
    /// insert."
    uint256 constant README_SOLO_GET_GAS = 240;
    uint256 constant README_SOLO_SET_GAS = 390;

    /// README: "every key already in a list adds ~65 gas to a get from it and
    /// ~75 gas to a set into it: the fourth key to land in one list inserts for
    /// ~610 gas."
    uint256 constant README_WALKED_GET_GAS = 65;
    uint256 constant README_WALKED_SET_GAS = 75;
    uint256 constant README_FOURTH_IN_LIST_SET_GAS = 610;

    /// How many keys the colliding measurements put into one list. The README
    /// names the fourth.
    uint256 constant COLLIDERS = 4;

    /// The list the colliding measurements build. Any of the 15 would do: an
    /// insert into an empty list and a get of a key alone in one cost the same
    /// in every slot.
    uint256 constant COLLIDING_SLOT = 3;

    /// What the README's `~` is read as here.
    uint256 constant ROUNDING_PERCENT = 10;

    /// The README's figures are prefixed `~`, read here as `ROUNDING_PERCENT` in
    /// BOTH directions. A one sided bound is how the figure this replaced
    /// survived: the published get was an over-estimate, so an upper bound on
    /// the measurement held while the sentence was wrong.
    function assertNear(uint256 measured, uint256 published, string memory reason) internal pure {
        uint256 tolerance = (published * ROUNDING_PERCENT) / 100;
        assertLe(measured, published + tolerance, reason);
        assertGe(measured + tolerance, published, reason);
    }

    /// Expands memory past anything the measurements below allocate, then rewinds
    /// the free pointer over it. Without this each measurement is taken at a
    /// higher point in memory than the last and carries a different expansion
    /// cost, which is a difference between allocations rather than between the
    /// things being compared.
    function padMemory() internal pure {
        uint256 pointer;
        assembly ("memory-safe") {
            pointer := mload(0x40)
        }
        bytes memory pad = new bytes(0x1000);
        (pad);
        assembly {
            mstore(0x40, pointer)
        }
    }

    function bisectGas(MemoryKV kv) internal view returns (uint256) {
        uint256 start = gasleft();
        bytes32[] memory array = LibMemoryKV.toBytes32Array(kv);
        uint256 end = gasleft();
        (array);
        return start - end;
    }

    function linearGas(MemoryKV kv) internal view returns (uint256) {
        uint256 start = gasleft();
        bytes32[] memory array = LibMemoryKVSlow.toBytes32ArrayLinear(kv);
        uint256 end = gasleft();
        (array);
        return start - end;
    }

    /// Exporting one pair costs the same whichever slot it landed in: the bisect
    /// is the same depth to every slot but the shallow one, and every branch it
    /// does not take costs exactly the one test that skips it. Delete any of
    /// those tests and the stores that skip that branch start paying for it,
    /// which shows up here as a slot that no longer matches its peers.
    function testExportGasIsUniformAcrossSlots() public view {
        MemoryKV[] memory kvs = new MemoryKV[](SLOTS);
        for (uint256 slot = 0; slot < SLOTS; slot++) {
            bytes32 key = MemoryKVKey.unwrap(keyForSlot(bytes32(slot + 1), slot));
            kvs[slot] = LibMemoryKV.set(MEMORY_KV_EMPTY, MemoryKVKey.wrap(key), MemoryKVVal.wrap(bytes32(uint256(1))));
        }

        padMemory();
        uint256[] memory gas = new uint256[](SLOTS);
        for (uint256 slot = 0; slot < SLOTS; slot++) {
            gas[slot] = bisectGas(kvs[slot]);
        }

        for (uint256 slot = 1; slot < SLOTS; slot++) {
            if (slot == SHALLOW_SLOT) {
                assertLt(gas[slot], gas[0], "shallow slot must cost less");
            } else {
                assertEq(gas[slot], gas[0], "slot must cost the same as its peers");
            }
        }
    }

    /// The naive linear loop the NatSpec measures the saving against is
    /// `toBytes32ArrayLinear`, which visits all 15 slots and produces the same
    /// pairs. Measuring the linear walk first leaves the bisect allocating higher
    /// in memory, so the saving asserted here is the pessimistic one.
    function testExportGasBeatsLinearWalk() public view {
        for (uint256 pairs = 0; pairs <= BISECT_SAVING_MAX_PAIRS; pairs++) {
            MemoryKV kv = MEMORY_KV_EMPTY;
            for (uint256 i = 1; i <= pairs; i++) {
                kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(i)), MemoryKVVal.wrap(bytes32(i)));
            }

            padMemory();
            uint256 linear = linearGas(kv);
            uint256 bisect = bisectGas(kv);
            assertGe(linear, bisect + BISECT_SAVING, "bisect must save the documented gas");
        }
    }

    /// The README's headline figures, on the key alone in its list that they
    /// name.
    function testGetSetGasMatchesReadme() public view {
        MemoryKV kv = MEMORY_KV_EMPTY;
        MemoryKVKey key = MemoryKVKey.wrap(bytes32(uint256(1)));
        MemoryKVVal value = MemoryKVVal.wrap(bytes32(uint256(2)));

        padMemory();

        uint256 setStart = gasleft();
        kv = LibMemoryKV.set(kv, key, value);
        uint256 setEnd = gasleft();

        uint256 getStart = gasleft();
        (uint256 exists, MemoryKVVal got) = LibMemoryKV.get(kv, key);
        uint256 getEnd = gasleft();
        (exists, got);

        assertNear(setStart - setEnd, README_SOLO_SET_GAS, "set");
        assertNear(getStart - getEnd, README_SOLO_GET_GAS, "get");
    }

    /// The README's collision figures. The per-key costs are differences between
    /// measurements taken here, so each says what one more key in front of the
    /// target costs and carries none of the constant every measurement shares.
    function testCollidingGasMatchesReadme() public view {
        MemoryKVVal value = MemoryKVVal.wrap(bytes32(uint256(2)));
        MemoryKVKey[] memory keys = keysInSlot(bytes32(uint256(1)), COLLIDING_SLOT, COLLIDERS);
        // The first key set is the one furthest from the head, so reading it
        // back walks the whole list. Hoisted out of every measurement below
        // because an array read inside the window is measured with the call.
        MemoryKVKey first = keys[0];

        MemoryKV kv = MEMORY_KV_EMPTY;
        uint256[] memory setGas = new uint256[](COLLIDERS);
        uint256[] memory getGas = new uint256[](COLLIDERS);

        for (uint256 i = 0; i < COLLIDERS; i++) {
            MemoryKVKey key = keys[i];

            padMemory();
            uint256 setStart = gasleft();
            MemoryKV next = LibMemoryKV.set(kv, key, value);
            uint256 setEnd = gasleft();
            setGas[i] = setStart - setEnd;
            kv = next;

            padMemory();
            uint256 getStart = gasleft();
            (uint256 exists, MemoryKVVal got) = LibMemoryKV.get(kv, first);
            uint256 getEnd = gasleft();
            (exists, got);
            getGas[i] = getStart - getEnd;
        }

        for (uint256 i = 1; i < COLLIDERS; i++) {
            assertNear(setGas[i] - setGas[i - 1], README_WALKED_SET_GAS, "one more key in front of a set");
            assertNear(getGas[i] - getGas[i - 1], README_WALKED_GET_GAS, "one more key in front of a get");
        }
        assertNear(setGas[COLLIDERS - 1], README_FOURTH_IN_LIST_SET_GAS, "fourth key into one list");
    }
}
