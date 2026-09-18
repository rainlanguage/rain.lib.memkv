// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {LibPointer, Pointer} from "rain-solmem-0.1.28/src/lib/LibPointer.sol";

import {LibMemoryKV, MemoryKV, MemoryKVVal, MemoryKVKey, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {setFreePointer} from "test/lib/LibFreeMemory.sol";
import {keyForSlot, keysInSlot} from "test/lib/LibMemoryKVKeys.sol";
import {LibMemoryKVSlow} from "test/lib/LibMemoryKVSlow.sol";

/// Compares gas between paths through the library in one build, never against
/// a fixed figure: a consumer compiles the library with its own optimizer
/// settings, so an absolute cost holds only for this repository's build, while
/// which of two paths costs more follows from what each path does. The
/// comparisons here are the reason the export is a bisect rather than a loop,
/// and the rest of the suite cannot see them: the skip guards that produce the
/// saving are invisible to a test that only reads the exported pairs.
contract LibMemoryKVGasClaimsTest is Test {
    /// The one slot the bisect reaches a level early. The length occupies the
    /// high bits of `kv`, so stripping it leaves the last slot's pointer already
    /// isolated and the tree tests it directly instead of descending to it.
    uint256 internal constant SHALLOW_SLOT = LibMemoryKV.LIST_COUNT - 1;

    /// How far two equal-depth export paths may differ in gas. The optimizer
    /// picks which arm of each conditional falls through, and a taken jump lands
    /// on a `JUMPDEST` that costs 1 gas, so a path pays up to one gas per
    /// conditional it passes: the four bisect levels and the leaf guard.
    uint256 internal constant BRANCH_LAYOUT_GAS = 5;

    /// How many keys the colliding measurements put into one list.
    uint256 internal constant COLLIDERS = 4;

    /// The list the colliding measurements build. Any list would do: an insert
    /// into an empty list and a get of a key alone in one cost the same in
    /// every slot.
    uint256 internal constant COLLIDING_SLOT = 3;

    /// Expands memory past anything the measurements below allocate, then
    /// rewinds the free pointer over it. Every measurement after it allocates
    /// inside memory that is already expanded, so none of them pays expansion
    /// and the order two measurements are taken in does not change either one.
    function padMemory() internal pure {
        uint256 pointer = Pointer.unwrap(LibPointer.allocatedMemoryPointer());
        bytes memory pad = new bytes(0x1000);
        (pad);
        setFreePointer(pointer);
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
        MemoryKV[] memory kvs = new MemoryKV[](LibMemoryKV.LIST_COUNT);
        for (uint256 slot = 0; slot < LibMemoryKV.LIST_COUNT; slot++) {
            bytes32 key = MemoryKVKey.unwrap(keyForSlot(bytes32(slot + 1), slot));
            kvs[slot] = LibMemoryKV.set(MEMORY_KV_EMPTY, MemoryKVKey.wrap(key), MemoryKVVal.wrap(bytes32(uint256(1))));
        }

        padMemory();
        uint256[] memory gas = new uint256[](LibMemoryKV.LIST_COUNT);
        for (uint256 slot = 0; slot < LibMemoryKV.LIST_COUNT; slot++) {
            gas[slot] = bisectGas(kvs[slot]);
        }

        for (uint256 slot = 1; slot < LibMemoryKV.LIST_COUNT; slot++) {
            if (slot == SHALLOW_SLOT) {
                assertLt(gas[slot], gas[0], "shallow slot must cost less");
            } else {
                assertApproxEqAbs(gas[slot], gas[0], BRANCH_LAYOUT_GAS, "slot must cost the same as its peers");
            }
        }
    }

    /// The naive linear loop the saving is measured against is
    /// `toBytes32ArrayLinear`, which visits every list and produces the same
    /// pairs. The saving comes from the empty lists the bisect skips a subtree
    /// at a time, so it falls as lists fill. Lists are filled from list `0` up,
    /// one key each, and at every occupancy from the empty store to every list
    /// occupied the bisect costs less and the saving is no larger than at the
    /// occupancy before.
    function testExportGasSavingFallsAsListsFill() public view {
        uint256 previous = type(uint256).max;
        MemoryKV kv = MEMORY_KV_EMPTY;
        for (uint256 occupied = 0; occupied <= LibMemoryKV.LIST_COUNT; occupied++) {
            if (occupied > 0) {
                uint256 slot = occupied - 1;
                kv = LibMemoryKV.set(kv, keyForSlot(bytes32(slot + 1), slot), MemoryKVVal.wrap(bytes32(uint256(1))));
            }

            padMemory();
            uint256 linear = linearGas(kv);
            uint256 bisect = bisectGas(kv);
            assertGt(linear, bisect, "the bisect costs less than the linear walk");

            uint256 saving = linear - bisect;
            assertLe(saving, previous, "the saving never grows as lists fill");
            previous = saving;
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
