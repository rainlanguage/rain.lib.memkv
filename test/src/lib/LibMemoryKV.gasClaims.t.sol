// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";

import {LibPointer, Pointer} from "rain-solmem-0.1.28/src/lib/LibPointer.sol";

import {LibMemoryKV, MemoryKV, MemoryKVVal, MemoryKVKey, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {keyForSlot, keysInSlot} from "test/lib/LibMemoryKVKeys.sol";
import {LibMemoryKVSlow} from "test/lib/LibMemoryKVSlow.sol";
import {setFreePointer} from "test/lib/LibFreeMemory.sol";

/// Compares the gas of paths through the library against each other within one
/// build: the export of a pair from each list against the others, the export of
/// pairs spread over lists against the same number stacked in one list, the
/// mask walk export against a linear walk over every head, the first insert
/// against a later insert into an empty list, and an insert into a list, or a
/// get of the key furthest from its head, against the same with one key fewer
/// ahead of it.
contract LibMemoryKVGasClaimsTest is Test {
    /// How many keys the colliding measurements put into one list.
    uint256 internal constant COLLIDERS = 4;

    /// The list the colliding measurements build. An insert into an empty list
    /// and a get of a key alone in one cost the same in every list.
    uint256 internal constant COLLIDING_SLOT = 3;

    /// The list of the pair a measurement puts in a store first when it needs
    /// a store that already has its header, so that an insert into
    /// `COLLIDING_SLOT` is not the store's first and does not pay for the
    /// header.
    uint256 internal constant OTHER_SLOT = 9;

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

    function walkGas(MemoryKV kv) internal view returns (uint256) {
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

    /// A store of `pairs` pairs, one in each of lists `0` to `pairs - 1`.
    function spreadStore(uint256 pairs) internal pure returns (MemoryKV kv) {
        for (uint256 list = 0; list < pairs; list++) {
            kv = LibMemoryKV.set(kv, keyForSlot(bytes32(list + 1), list), MemoryKVVal.wrap(bytes32(uint256(1))));
        }
    }

    /// A store of `pairs` pairs, every one of them in list `0`.
    function stackedStore(uint256 pairs) internal pure returns (MemoryKV kv) {
        MemoryKVKey[] memory keys = keysInSlot(bytes32(uint256(1)), 0, pairs);
        for (uint256 i = 0; i < pairs; i++) {
            kv = LibMemoryKV.set(kv, keys[i], MemoryKVVal.wrap(bytes32(uint256(1))));
        }
    }

    /// Exporting one pair costs exactly the same whichever list it landed in.
    /// The walk reaches every list through one mask step and one table lookup,
    /// so no list is nearer or further than another.
    function testExportGasIsTheSameForEveryList() public view {
        MemoryKV[] memory kvs = new MemoryKV[](LibMemoryKV.LIST_COUNT);
        for (uint256 list = 0; list < LibMemoryKV.LIST_COUNT; list++) {
            kvs[list] = LibMemoryKV.set(
                MEMORY_KV_EMPTY, keyForSlot(bytes32(list + 1), list), MemoryKVVal.wrap(bytes32(uint256(1)))
            );
        }

        padMemory();
        uint256[] memory gas = new uint256[](LibMemoryKV.LIST_COUNT);
        for (uint256 list = 0; list < LibMemoryKV.LIST_COUNT; list++) {
            gas[list] = walkGas(kvs[list]);
        }

        for (uint256 list = 1; list < LibMemoryKV.LIST_COUNT; list++) {
            assertEq(gas[list], gas[0], "every list costs the same to export");
        }
    }

    /// The same number of pairs costs more to export spread one to a list than
    /// stacked in one list, and each list the stack leaves empty saves exactly
    /// the one visit an occupied list costs.
    function testAnEmptyListCostsTheExportNothing() public view {
        uint256 listVisit;
        for (uint256 pairs = 2; pairs <= LibMemoryKV.LIST_COUNT; pairs++) {
            MemoryKV spread = spreadStore(pairs);
            MemoryKV stacked = stackedStore(pairs);

            padMemory();
            uint256 spreadGas = walkGas(spread);
            uint256 stackedGas = walkGas(stacked);
            assertGt(spreadGas, stackedGas, "every occupied list costs a visit");

            if (pairs == 2) {
                listVisit = spreadGas - stackedGas;
            }
            assertEq(spreadGas - stackedGas, (pairs - 1) * listVisit, "each list left empty saves one visit");
        }
    }

    /// Exports the store through the mask walk and through
    /// `LibMemoryKVSlow.toBytes32ArrayLinear`, a loop over every head that
    /// produces the same pairs, at every occupancy from the empty store to
    /// every list occupied, filling lists from list `0` up with one key each.
    /// At every occupancy the walk costs less. From one occupied list on, the
    /// saving is no larger than at the occupancy before: each list that fills
    /// adds a mask step and a table lookup to the walk, and nothing to the
    /// loop's visit of every head.
    function testExportGasSavingFallsAsListsFill() public view {
        uint256 previous = type(uint256).max;
        MemoryKV kv = MEMORY_KV_EMPTY;
        for (uint256 occupied = 0; occupied <= LibMemoryKV.LIST_COUNT; occupied++) {
            if (occupied > 0) {
                uint256 list = occupied - 1;
                kv = LibMemoryKV.set(kv, keyForSlot(bytes32(list + 1), list), MemoryKVVal.wrap(bytes32(uint256(1))));
            }

            padMemory();
            uint256 linear = linearGas(kv);
            uint256 walk = walkGas(kv);
            assertGt(linear, walk, "the walk costs less than the linear loop");

            uint256 saving = linear - walk;
            if (occupied > 1) {
                assertLe(saving, previous, "the saving never grows as lists fill");
            }
            previous = saving;
        }
    }

    /// The first insert into an empty store allocates and zeroes the header on
    /// top of an insert into an empty list, so it costs more than the same
    /// insert into an empty list of a store that already has its header.
    function testTheFirstInsertCostsMoreThanALaterInsertIntoAnEmptyList() public view {
        MemoryKVVal value = MemoryKVVal.wrap(bytes32(uint256(2)));
        MemoryKVKey key = keyForSlot(bytes32(uint256(1)), COLLIDING_SLOT);
        MemoryKV headed = LibMemoryKV.set(MEMORY_KV_EMPTY, keyForSlot(bytes32(uint256(1)), OTHER_SLOT), value);

        padMemory();
        uint256 firstStart = gasleft();
        MemoryKV first = LibMemoryKV.set(MEMORY_KV_EMPTY, key, value);
        uint256 firstEnd = gasleft();

        padMemory();
        uint256 laterStart = gasleft();
        MemoryKV later = LibMemoryKV.set(headed, key, value);
        uint256 laterEnd = gasleft();
        (first, later);

        assertGt(firstStart - firstEnd, laterStart - laterEnd, "the first insert pays for the header");
    }

    /// Keys that share a list are walked one at a time, so every key already in
    /// the list makes an insert into it, and a get of the key furthest from its
    /// head, cost more than the one before. The store already holds a pair in
    /// another list, so no insert measured here is the store's first and pays
    /// for the header.
    function testEachKeyAheadInAListAddsGas() public view {
        MemoryKVVal value = MemoryKVVal.wrap(bytes32(uint256(2)));
        MemoryKVKey[] memory keys = keysInSlot(bytes32(uint256(1)), COLLIDING_SLOT, COLLIDERS);
        // The first key set is the one furthest from the head, so reading it
        // back walks the whole list. It is held in a local outside every
        // measurement window below, so each window holds the call alone.
        MemoryKVKey first = keys[0];

        MemoryKV kv = LibMemoryKV.set(MEMORY_KV_EMPTY, keyForSlot(bytes32(uint256(1)), OTHER_SLOT), value);
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
