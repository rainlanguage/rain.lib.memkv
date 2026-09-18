// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";

import {LibMemoryKV, MemoryKV, MemoryKVVal, MemoryKVKey, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {keyForSlot, keysInSlot} from "test/lib/LibMemoryKVKeys.sol";
import {LibMemoryKVSlow} from "test/lib/LibMemoryKVSlow.sol";

/// Compares the gas of paths through the library against each other within one
/// build: the export of a pair from each list against the others, the bisect
/// export against a linear walk over every list, and an insert into a list, or
/// a get of the key furthest from its head, against the same with one key fewer
/// ahead of it.
contract LibMemoryKVGasClaimsTest is Test {
    /// `kv` carries one pointer per internal linked list.
    uint256 internal constant SLOTS = 0x0f;

    /// The one slot the bisect reaches a level early. The length occupies the
    /// high bits of `kv`, so stripping it leaves the last slot's pointer already
    /// isolated and the tree tests it directly instead of descending to it.
    uint256 internal constant SHALLOW_SLOT = 0x0e;

    /// How far two equal-depth export paths may differ in gas. The optimizer
    /// picks which arm of each conditional falls through, and a taken jump lands
    /// on a `JUMPDEST` that costs 1 gas, so a path pays up to one gas per
    /// conditional it passes: the four bisect levels and the leaf guard.
    uint256 internal constant BRANCH_LAYOUT_GAS = 5;

    /// `toBytes32Array` NatSpec: "the bisect approach can save ~1-1.5k gas vs. a
    /// naive linear loop over all 15 slots for every export".
    uint256 internal constant BISECT_SAVING = 1000;

    /// The largest store the saving is claimed for. Beyond it the per-pair
    /// copying, which both implementations do identically, dominates.
    uint256 internal constant BISECT_SAVING_MAX_PAIRS = 5;

    /// How many keys the colliding measurements put into one list.
    uint256 internal constant COLLIDERS = 4;

    /// The list the colliding measurements build. Any of the 15 would do: an
    /// insert into an empty list and a get of a key alone in one cost the same
    /// in every slot.
    uint256 internal constant COLLIDING_SLOT = 3;

    /// Expands memory past anything the measurements below allocate, then
    /// rewinds the free pointer over it. Every measurement after it allocates
    /// inside memory that is already expanded, so none of them pays expansion
    /// and the order two measurements are taken in does not change either one.
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

    /// Exporting one pair costs the same whichever slot it landed in, to within
    /// `BRANCH_LAYOUT_GAS`: the bisect is the same depth to every slot but the
    /// shallow one, and every branch it does not take costs the one test that
    /// skips it. Delete any of those tests and the stores that skip that branch
    /// pay a whole `copyFromPtr` call on an empty list, far more than
    /// `BRANCH_LAYOUT_GAS`, which shows up here as a slot that no longer matches
    /// its peers.
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
                assertApproxEqAbs(gas[slot], gas[0], BRANCH_LAYOUT_GAS, "slot must cost the same as its peers");
            }
        }
    }

    /// The naive linear loop the NatSpec measures the saving against is
    /// `toBytes32ArrayLinear`, which visits all 15 slots and produces the same
    /// pairs.
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

    /// Keys that share a list are walked one at a time, so every key already in
    /// the list makes an insert into it, and a get of the key furthest from its
    /// head, cost more than the one before.
    function testEachKeyAheadInAListAddsGas() public view {
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
            assertGt(setGas[i], setGas[i - 1], "one more key in front of an insert");
            assertGt(getGas[i], getGas[i - 1], "one more key in front of a get");
        }
    }
}
