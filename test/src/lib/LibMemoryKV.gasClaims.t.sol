// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {LibPointer, Pointer} from "rain-solmem-0.1.28/src/lib/LibPointer.sol";

import {LibMemoryKV, MemoryKV, MemoryKVVal, MemoryKVKey, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {README_PATH, LIB_MEMORY_KV_PATH, assertDocumentStates} from "test/lib/LibDocumentAssert.sol";
import {setFreePointer} from "test/lib/LibFreeMemory.sol";
import {keyForSlot, keysInSlot} from "test/lib/LibMemoryKVKeys.sol";
import {LibMemoryKVSlow} from "test/lib/LibMemoryKVSlow.sol";

/// Pins the gas figures the library documents for itself. Those figures are the
/// reason the export is a bisect rather than a loop and the reason any of this
/// is assembly, and the rest of the suite cannot tell whether they still hold:
/// the skip guards that produce the saving are invisible to a test that only
/// reads the exported pairs. Each figure is a constant here. The test that
/// measures the code against a figure also checks that the README or the
/// NatSpec states that constant, so neither the code nor the text can drift
/// from it without a failure.
contract LibMemoryKVGasClaimsTest is Test {
    /// The one slot the bisect reaches a level early. The length occupies the
    /// high bits of `kv`, so stripping it leaves the last slot's pointer already
    /// isolated and the tree tests it directly instead of descending to it.
    uint256 internal constant SHALLOW_SLOT = LibMemoryKV.LIST_COUNT - 1;

    /// The export's saving over the linear walk for an empty store.
    uint256 internal constant BISECT_SAVING_EMPTY = 1900;

    /// How many lists, counting up from list `0`, are occupied where the saving
    /// is pinned between the empty and the full store.
    uint256 internal constant BISECT_SAVING_PARTIAL_LISTS = 6;

    /// The export's saving over the linear walk with lists `0` to
    /// `BISECT_SAVING_PARTIAL_LISTS - 1` occupied.
    uint256 internal constant BISECT_SAVING_PARTIAL = 1100;

    /// The export's saving over the linear walk with every list occupied.
    uint256 internal constant BISECT_SAVING_FULL = 60;

    /// A get of a key alone in its list.
    uint256 internal constant README_SOLO_GET_GAS = 240;

    /// An insert of a key alone in its list.
    uint256 internal constant README_SOLO_SET_GAS = 390;

    /// What each key already in a list adds to a get from that list.
    uint256 internal constant README_WALKED_GET_GAS = 65;

    /// What each key already in a list adds to a set into that list.
    uint256 internal constant README_WALKED_SET_GAS = 75;

    /// An insert of the `COLLIDERS`th key to land in one list.
    uint256 internal constant README_LAST_COLLIDER_SET_GAS = 610;

    /// How many keys the colliding measurements put into one list.
    uint256 internal constant COLLIDERS = 4;

    /// The list the colliding measurements build. Any list would do: an insert
    /// into an empty list and a get of a key alone in one cost the same in
    /// every slot.
    uint256 internal constant COLLIDING_SLOT = 3;

    /// What a documented `~` figure is read as here: the largest difference
    /// between the measurement and the figure, relative to the figure, in
    /// forge-std's units where `1e18` is 100%. `assertApproxEqRel` bounds both
    /// directions, so an over-estimate fails as an under-estimate does.
    uint256 internal constant ROUNDING = 0.1e18;

    /// `figure` as the documents state a gas figure: `~` and the figure, then
    /// ` gas`.
    function approxGas(uint256 figure) internal pure returns (string memory) {
        return string.concat("~", vm.toString(figure), " gas");
    }

    /// `COLLIDERS` as the ordinal the README names the last colliding key by.
    function collidersOrdinal() internal pure returns (string memory) {
        string[4] memory ordinals = ["first", "second", "third", "fourth"];
        require(COLLIDERS <= ordinals.length, "COLLIDERS has no ordinal here");
        return ordinals[COLLIDERS - 1];
    }

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

    /// Exporting one pair costs the same whichever slot it landed in: the bisect
    /// is the same depth to every slot but the shallow one, and every branch it
    /// does not take costs exactly the one test that skips it. Delete any of
    /// those tests and the stores that skip that branch start paying for it,
    /// which shows up here as a slot that no longer matches its peers.
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
                assertEq(gas[slot], gas[0], "slot must cost the same as its peers");
            }
        }
    }

    /// The naive linear loop the NatSpec measures the saving against is
    /// `toBytes32ArrayLinear`, which visits every list and produces the same
    /// pairs. The saving comes from the empty lists the bisect skips a subtree
    /// at a time, so it falls as lists fill. Lists are filled from list `0` up,
    /// one key each, and the saving is measured at every occupancy from the
    /// empty store to every list occupied: it never grows, and it is within
    /// `ROUNDING` of each documented figure at the occupancy that figure names.
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

            if (occupied == 0) {
                assertApproxEqRel(saving, BISECT_SAVING_EMPTY, ROUNDING, "saving for an empty store");
            } else if (occupied == BISECT_SAVING_PARTIAL_LISTS) {
                assertApproxEqRel(saving, BISECT_SAVING_PARTIAL, ROUNDING, "saving with the low lists occupied");
            } else if (occupied == LibMemoryKV.LIST_COUNT) {
                assertApproxEqRel(saving, BISECT_SAVING_FULL, ROUNDING, "saving with every list occupied");
            }
        }

        assertDocumentStates(LIB_MEMORY_KV_PATH, string.concat(approxGas(BISECT_SAVING_EMPTY), " for an empty store"));
        assertDocumentStates(
            LIB_MEMORY_KV_PATH,
            string.concat(
                approxGas(BISECT_SAVING_PARTIAL),
                " with lists 0 to ",
                vm.toString(BISECT_SAVING_PARTIAL_LISTS - 1),
                " occupied"
            )
        );
        assertDocumentStates(
            LIB_MEMORY_KV_PATH, string.concat(approxGas(BISECT_SAVING_FULL), " with every list occupied")
        );
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

        assertApproxEqRel(setStart - setEnd, README_SOLO_SET_GAS, ROUNDING, "set");
        assertApproxEqRel(getStart - getEnd, README_SOLO_GET_GAS, ROUNDING, "get");

        assertDocumentStates(README_PATH, string.concat(approxGas(README_SOLO_GET_GAS), " to get"));
        assertDocumentStates(README_PATH, string.concat(approxGas(README_SOLO_SET_GAS), " to insert"));
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
            assertApproxEqRel(
                setGas[i] - setGas[i - 1], README_WALKED_SET_GAS, ROUNDING, "one more key in front of a set"
            );
            assertApproxEqRel(
                getGas[i] - getGas[i - 1], README_WALKED_GET_GAS, ROUNDING, "one more key in front of a get"
            );
        }
        assertApproxEqRel(
            setGas[COLLIDERS - 1], README_LAST_COLLIDER_SET_GAS, ROUNDING, "the last colliding key into one list"
        );

        assertDocumentStates(README_PATH, string.concat(approxGas(README_WALKED_GET_GAS), " to a get from it"));
        assertDocumentStates(
            README_PATH, string.concat(approxGas(README_WALKED_SET_GAS), " to a set into it: the ", collidersOrdinal())
        );
        assertDocumentStates(README_PATH, string.concat("inserts for ", approxGas(README_LAST_COLLIDER_SET_GAS)));
    }
}
