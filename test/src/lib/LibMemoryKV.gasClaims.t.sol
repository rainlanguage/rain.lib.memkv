// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {LibMemoryKV, MemoryKV, MemoryKVVal, MemoryKVKey} from "src/lib/LibMemoryKV.sol";
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

    /// README: "Gets cost ~350 gas and sets are ~400 gas."
    uint256 constant README_GET_GAS = 350;
    uint256 constant README_SET_GAS = 400;

    /// What the README's `~` is read as here.
    uint256 constant ROUNDING_PERCENT = 10;

    /// The internal list slot a key hashes into. MUST match `get`/`set`.
    function slotOf(bytes32 key) internal pure returns (uint256) {
        uint256 slot;
        assembly ("memory-safe") {
            mstore(0, key)
            slot := mod(keccak256(0, 0x20), 0x0f)
        }
        return slot;
    }

    /// Rehash `seed` until it lands in `slot`.
    function keyForSlot(bytes32 seed, uint256 slot) internal pure returns (bytes32) {
        bytes32 key = seed;
        while (slotOf(key) != slot) {
            key = keccak256(abi.encodePacked(key));
        }
        return key;
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
            bytes32 key = keyForSlot(bytes32(slot + 1), slot);
            kvs[slot] = LibMemoryKV.set(MemoryKV.wrap(0), MemoryKVKey.wrap(key), MemoryKVVal.wrap(bytes32(uint256(1))));
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
            MemoryKV kv = MemoryKV.wrap(0);
            for (uint256 i = 1; i <= pairs; i++) {
                kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(bytes32(i)), MemoryKVVal.wrap(bytes32(i)));
            }

            padMemory();
            uint256 linear = linearGas(kv);
            uint256 bisect = bisectGas(kv);
            assertGe(linear, bisect + BISECT_SAVING, "bisect must save the documented gas");
        }
    }

    /// The README's headline figures, on the uncontended insert and lookup that
    /// its "roughly O(1)" describes.
    function testGetSetGasMatchesReadme() public view {
        MemoryKV kv = MemoryKV.wrap(0);
        MemoryKVKey key = MemoryKVKey.wrap(bytes32(uint256(1)));

        padMemory();

        uint256 setStart = gasleft();
        kv = LibMemoryKV.set(kv, key, MemoryKVVal.wrap(bytes32(uint256(2))));
        uint256 setEnd = gasleft();

        uint256 getStart = gasleft();
        (uint256 exists, MemoryKVVal value) = LibMemoryKV.get(kv, key);
        uint256 getEnd = gasleft();
        (exists, value);

        assertLe(setStart - setEnd, README_SET_GAS + (README_SET_GAS * ROUNDING_PERCENT) / 100, "set");
        assertLe(getStart - getEnd, README_GET_GAS + (README_GET_GAS * ROUNDING_PERCENT) / 100, "get");
    }
}
