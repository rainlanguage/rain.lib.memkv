// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {LibMemoryKV, MemoryKV, MemoryKVVal, MemoryKVKey, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {keyForSlot, keysInSlot} from "test/lib/LibMemoryKVKeys.sol";
import {LibMemoryKVSlow} from "test/lib/LibMemoryKVSlow.sol";

/// Pins the gas figures the library documents for itself: the README's get and
/// insert figures, and the `toBytes32Array` claim that the occupancy mask walk
/// visits only the occupied lists. The rest of the suite cannot tell whether
/// they still hold: an export that visited every list, or a get that took a
/// longer path, produces the same pairs.
contract LibMemoryKVGasClaimsTest is Test {
    /// The stores the mask walk is claimed to beat the linear loop for, by
    /// pair count. Each occupied list costs the walk a mask step and a table
    /// lookup that the linear loop does not pay, so the walk's lead narrows as
    /// the lists fill.
    uint256 constant SMALL_STORE_PAIRS = 5;

    /// README: "A key alone in its list costs ~250 gas to get and ~345 gas to
    /// insert."
    uint256 constant README_SOLO_GET_GAS = 250;
    uint256 constant README_SOLO_SET_GAS = 345;

    /// README: "The first insert into an empty store costs ~430 gas, because it
    /// also allocates and zeroes the header."
    uint256 constant README_FIRST_SET_GAS = 430;

    /// README: "every key already in a list adds ~65 gas to a get from it or a
    /// set into it: the fourth key to land in one list inserts for ~540 gas."
    uint256 constant README_WALKED_GET_GAS = 65;
    uint256 constant README_WALKED_SET_GAS = 65;
    uint256 constant README_FOURTH_IN_LIST_SET_GAS = 540;

    /// How many keys the colliding measurements put into one list. The README
    /// names the fourth.
    uint256 constant COLLIDERS = 4;

    /// The list the colliding measurements build. Any of the 15 would do: an
    /// insert into an empty list and a get of a key alone in one cost the same
    /// in every list.
    uint256 constant COLLIDING_SLOT = 3;

    /// The list holding the pair the colliding measurements start from, so that
    /// the first key into `COLLIDING_SLOT` is not the store's first insert and
    /// does not pay for the header.
    uint256 constant OTHER_SLOT = 9;

    /// What the README's `~` is read as here.
    uint256 constant ROUNDING_PERCENT = 10;

    /// The README's figures are prefixed `~`, read here as `ROUNDING_PERCENT` in
    /// BOTH directions. A one sided bound is how an over-estimate survives: the
    /// measurement stays under it while the sentence is wrong.
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

    /// `toBytes32Array`: "Empty lists cost nothing beyond the mask test that
    /// skips them." The same number of pairs costs more to export spread one to
    /// a list than stacked in one list, and each list the stack leaves empty
    /// saves exactly the one visit an occupied list costs. A walk that visited
    /// every list would cost the same for both stores.
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

    /// The mask walk against `LibMemoryKVSlow.toBytes32ArrayLinear`, which
    /// visits all 15 heads and copies the same pairs with the same inner loop.
    /// On a small store most lists are empty, and the walk skips them where the
    /// linear loop reads each head. Measuring the linear loop first leaves the
    /// walk allocating higher in memory, so the win asserted here is the
    /// pessimistic one.
    function testExportWalkBeatsTheLinearLoopForSmallStores() public view {
        MemoryKV kv = MEMORY_KV_EMPTY;
        for (uint256 pairs = 1; pairs <= SMALL_STORE_PAIRS; pairs++) {
            kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(pairs)), MemoryKVVal.wrap(bytes32(pairs)));

            padMemory();
            uint256 linear = linearGas(kv);
            uint256 walk = walkGas(kv);
            assertLt(walk, linear, "the walk beats the linear loop");
        }
    }

    /// The README's first insert: the header's allocation and zeroing on top of
    /// an insert into an empty list.
    function testFirstInsertGasMatchesReadme() public view {
        MemoryKV kv = MEMORY_KV_EMPTY;
        MemoryKVKey key = MemoryKVKey.wrap(bytes32(uint256(1)));
        MemoryKVVal value = MemoryKVVal.wrap(bytes32(uint256(2)));

        padMemory();
        uint256 setStart = gasleft();
        kv = LibMemoryKV.set(kv, key, value);
        uint256 setEnd = gasleft();

        assertNear(setStart - setEnd, README_FIRST_SET_GAS, "first insert");
    }

    /// The README's get and set figures, in a store that already holds a pair
    /// in another list so that no measurement pays for the header. The first
    /// key into the list is the key alone in its list. The per-key costs are
    /// differences between measurements taken here, so each says what one more
    /// key in front of the target costs and carries none of the constant every
    /// measurement shares.
    function testGetSetGasMatchesReadme() public view {
        MemoryKVVal value = MemoryKVVal.wrap(bytes32(uint256(2)));
        MemoryKVKey[] memory keys = keysInSlot(bytes32(uint256(1)), COLLIDING_SLOT, COLLIDERS);
        // The first key set is the one furthest from the head, so reading it
        // back walks the whole list. Hoisted out of every measurement below
        // because an array read inside the window is measured with the call.
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

        assertNear(setGas[0], README_SOLO_SET_GAS, "insert of a key alone in its list");
        assertNear(getGas[0], README_SOLO_GET_GAS, "get of a key alone in its list");
        for (uint256 i = 1; i < COLLIDERS; i++) {
            assertNear(setGas[i] - setGas[i - 1], README_WALKED_SET_GAS, "one more key in front of a set");
            assertNear(getGas[i] - getGas[i - 1], README_WALKED_GET_GAS, "one more key in front of a get");
        }
        assertNear(setGas[COLLIDERS - 1], README_FOURTH_IN_LIST_SET_GAS, "fourth key into one list");
    }
}
