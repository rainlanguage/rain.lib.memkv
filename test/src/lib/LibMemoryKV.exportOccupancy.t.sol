// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";

import {LibPointer, Pointer} from "rain-solmem-0.1.28/src/lib/LibPointer.sol";
import {LibBytes32Array} from "rain-solmem-0.1.28/src/lib/LibBytes32Array.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {dirtyFreeMemory, setFreePointer} from "test/lib/LibFreeMemory.sol";
import {keysInSlot, slotOf} from "test/lib/LibMemoryKVKeys.sol";
import {headOf, lengthOf, maskOf, occupancyBitOf} from "test/lib/LibMemoryKVHandle.sol";
import {countPair} from "test/lib/LibMemoryKVExport.sol";

/// @title LibMemoryKVExportOccupancyTest
/// The occupancy mask walk of `toBytes32Array`, the only path by which the
/// internal lists reach the exported array. Each step isolates the lowest set
/// bit of the mask, clears it, and copies the list that `SLOT_TABLE` names for
/// it, so which lists are exported is decided by the mask alone.
///
/// The named tests each occupy one known list, or one known set of lists, and
/// name it on failure. The enumerations run every occupancy mask, which is the
/// walk's whole input: nothing it does branches on a key or a value.
///
/// `listKeys` holds one constant key per list, so every test here chooses its
/// occupancy and none takes a fuzz input.
///
/// Every header and node of every case an enumeration builds is allocated from
/// a free memory pointer that is rewound between cases, so each case builds at
/// the same addresses. The pair order is unspecified and nothing here checks
/// it; `LibMemoryKV.packedParity.t.sol` pins the order the walk produces.
contract LibMemoryKVExportOccupancyTest is Test {
    using LibMemoryKV for MemoryKV;

    /// Every combination of which lists are occupied: every occupancy mask.
    uint256 constant OCCUPANCY_COMBINATIONS = LibMemoryKV.OCCUPANCY_MASK + 1;

    /// The first address that does not fit in sixteen bits. A store built from
    /// here has a header address, and heads and next pointers, that do not.
    uint256 constant ABOVE_SIXTEEN_BITS = 0x10000;

    /// Stands for "no mask": it has bits outside `LibMemoryKV.OCCUPANCY_MASK`.
    uint256 constant NO_MASK = type(uint256).max;

    /// Values sit above every constant key. The value of the key at index `i`
    /// is this base plus `i`, which is how `exportMatches` reads a pair's index
    /// back out of it.
    uint256 constant VALUE_BASE = 0x100;

    /// Pairs `testCountBitsAreNeverReadAsMaskBits` adds to list 0 behind the
    /// `listKeys`, taking the store to 64 pairs: a count of 128 words.
    uint256 constant EXTRA_PAIRS = 64 - LibMemoryKV.LIST_COUNT;

    /// What the words past the end of an export hold before it runs.
    bytes32 constant PAST_THE_END = keccak256("past the end of the export");

    /// One key per list: the smallest positive integer whose 32 byte big endian
    /// encoding hashes into that list. Regenerating one is
    /// `cast keccak $(cast to-uint256 <n>)` reduced modulo
    /// `LibMemoryKV.LIST_COUNT`, and `testKeyConstantsLandWhereClaimed` checks
    /// each.
    function listKeys() internal pure returns (bytes32[] memory keys) {
        uint256[15] memory words = [uint256(4), 31, 2, 1, 9, 49, 24, 42, 3, 21, 16, 7, 6, 14, 11];
        keys = new bytes32[](LibMemoryKV.LIST_COUNT);
        for (uint256 list = 0; list < LibMemoryKV.LIST_COUNT; list++) {
            keys[list] = bytes32(words[list]);
        }
    }

    function valueFor(uint256 index) internal pure returns (bytes32) {
        return bytes32(VALUE_BASE + index);
    }

    function freePointer() internal pure returns (uint256) {
        return Pointer.unwrap(LibPointer.allocatedMemoryPointer());
    }

    /// Every other list, starting at list `first`, as an occupancy mask.
    function alternateLists(uint256 first) internal pure returns (uint256 mask) {
        for (uint256 list = first; list < LibMemoryKV.LIST_COUNT; list += 2) {
            mask |= occupancyBitOf(list);
        }
    }

    /// Whether `mask` names `list` as occupied.
    function occupies(uint256 mask, uint256 list) internal pure returns (bool) {
        return mask & occupancyBitOf(list) != 0;
    }

    /// The lists `mask` names, as a bitset with bit `list` set for each, which
    /// is the index of that list's key in `listKeys`; and how many there are.
    function listsOf(uint256 mask) internal pure returns (uint256 lists, uint256 count) {
        for (uint256 list = 0; list < LibMemoryKV.LIST_COUNT; list++) {
            if (occupies(mask, list)) {
                lists |= uint256(1) << list;
                count++;
            }
        }
    }

    /// Which lists of `kv` have a non-zero head, as an occupancy mask, read
    /// from the heads rather than the mask the store keeps.
    function occupancyOf(MemoryKV kv) internal pure returns (uint256 occupancy) {
        for (uint256 list = 0; list < LibMemoryKV.LIST_COUNT; list++) {
            if (headOf(kv, list) != 0) {
                occupancy |= occupancyBitOf(list);
            }
        }
    }

    /// The store holding one key in each list `mask` names.
    function storeForOccupancy(uint256 mask, bytes32[] memory keys) internal pure returns (MemoryKV kv) {
        kv = MEMORY_KV_EMPTY;
        for (uint256 list = 0; list < LibMemoryKV.LIST_COUNT; list++) {
            if (occupies(mask, list)) {
                kv = kv.set(MemoryKVKey.wrap(keys[list]), MemoryKVVal.wrap(valueFor(list)));
            }
        }
    }

    /// The store `mask` names occupies exactly those lists, by its heads and by
    /// its mask, and exports exactly their pairs, each once.
    function checkNamedOccupancy(uint256 mask, string memory name) internal pure {
        bytes32[] memory keys = listKeys();
        checkStore(storeForOccupancy(mask, keys), mask, keys, name);
    }

    /// `kv`, built by `storeForOccupancy(mask, keys)`, occupies exactly the
    /// lists `mask` names and exports exactly their pairs, each once.
    function checkStore(MemoryKV kv, uint256 mask, bytes32[] memory keys, string memory name) internal pure {
        assertEq(occupancyOf(kv), mask, string.concat(name, ": exactly the named lists have heads"));
        assertEq(maskOf(kv), mask, string.concat(name, ": the mask is exactly the named lists"));

        bytes32[] memory array = kv.toBytes32Array();
        (, uint256 count) = listsOf(mask);
        assertEq(array.length, count * 2, string.concat(name, ": one pair per occupied list"));
        for (uint256 list = 0; list < LibMemoryKV.LIST_COUNT; list++) {
            if (occupies(mask, list)) {
                assertEq(
                    countPair(array, keys[list], valueFor(list)),
                    1,
                    string.concat(name, ": list ", vm.toString(list), " exported exactly once")
                );
            }
        }
    }

    /// `checkNamedOccupancy` for a store built from above sixteen bits, so the
    /// header address and every head the walk follows are wider than sixteen
    /// bits.
    function checkNamedOccupancyAboveSixteenBits(uint256 mask, string memory name) internal pure {
        bytes32[] memory keys = listKeys();
        setFreePointer(ABOVE_SIXTEEN_BITS);
        MemoryKV kv = storeForOccupancy(mask, keys);
        assertEq(MemoryKV.unwrap(kv), ABOVE_SIXTEEN_BITS, string.concat(name, ": the header is above sixteen bits"));
        for (uint256 list = 0; list < LibMemoryKV.LIST_COUNT; list++) {
            if (occupies(mask, list)) {
                assertGt(headOf(kv, list), ABOVE_SIXTEEN_BITS, string.concat(name, ": the head is above sixteen bits"));
            }
        }
        checkStore(kv, mask, keys, name);
    }

    /// A single key in `list` and nothing else. Its occupancy bit is the whole
    /// mask, so the walk takes one step: it isolates that bit and copies the
    /// list `SLOT_TABLE` names for it.
    function checkSoleList(uint256 list) internal pure {
        bytes32[] memory keys = listKeys();
        MemoryKV kv = storeForOccupancy(occupancyBitOf(list), keys);
        assertEq(occupancyOf(kv), occupancyBitOf(list), "only the list under test has a head");
        assertEq(maskOf(kv), occupancyBitOf(list), "only the list under test is in the mask");

        bytes32[] memory array = kv.toBytes32Array();
        assertEq(array.length, 2, "one pair");
        assertEq(array[0], keys[list], "exported key");
        assertEq(array[1], valueFor(list), "exported value");
    }

    /// List 0 is the highest bit of the mask, so the walk reaches it last.
    function testList0AloneExports() public pure {
        checkSoleList(0);
    }

    function testList1AloneExports() public pure {
        checkSoleList(1);
    }

    function testList2AloneExports() public pure {
        checkSoleList(2);
    }

    function testList3AloneExports() public pure {
        checkSoleList(3);
    }

    function testList4AloneExports() public pure {
        checkSoleList(4);
    }

    function testList5AloneExports() public pure {
        checkSoleList(5);
    }

    function testList6AloneExports() public pure {
        checkSoleList(6);
    }

    function testList7AloneExports() public pure {
        checkSoleList(7);
    }

    function testList8AloneExports() public pure {
        checkSoleList(8);
    }

    function testList9AloneExports() public pure {
        checkSoleList(9);
    }

    function testList10AloneExports() public pure {
        checkSoleList(10);
    }

    function testList11AloneExports() public pure {
        checkSoleList(11);
    }

    function testList12AloneExports() public pure {
        checkSoleList(12);
    }

    function testList13AloneExports() public pure {
        checkSoleList(13);
    }

    /// The last list is the lowest bit of the mask, so the walk reaches it
    /// first.
    function testLastListAloneExports() public pure {
        checkSoleList(LibMemoryKV.LIST_COUNT - 1);
    }

    /// The lowest and the highest bit of the mask, the walk's first and last
    /// possible steps, with every bit between them clear.
    function testListsAtBothEndsOfTheMaskExport() public pure {
        uint256 last = LibMemoryKV.LIST_COUNT - 1;
        checkNamedOccupancy(occupancyBitOf(0) | occupancyBitOf(last), string.concat("lists 0 and ", vm.toString(last)));
    }

    /// Every two lists whose occupancy bits are neighbours.
    function testEveryAdjacentPairOfListsExports() public pure {
        for (uint256 list = 0; list + 1 < LibMemoryKV.LIST_COUNT; list++) {
            checkNamedOccupancy(
                occupancyBitOf(list) | occupancyBitOf(list + 1),
                string.concat("lists ", vm.toString(list), " and ", vm.toString(list + 1))
            );
        }
    }

    /// Every other list, so every step of the walk skips a clear bit.
    function testAlternateListsExport() public pure {
        checkNamedOccupancy(alternateLists(0), "even lists");
        checkNamedOccupancy(alternateLists(1), "odd lists");
    }

    /// Every list at once. Every step copies a list no other step copies, and
    /// between them they reach every list.
    function testEveryListExportedExactlyOnce() public pure {
        checkNamedOccupancy(LibMemoryKV.OCCUPANCY_MASK, "every list");
    }

    function testEvenListsExportAboveSixteenBits() public pure {
        checkNamedOccupancyAboveSixteenBits(alternateLists(0), "even lists");
    }

    function testOddListsExportAboveSixteenBits() public pure {
        checkNamedOccupancyAboveSixteenBits(alternateLists(1), "odd lists");
    }

    function testEveryListExportedExactlyOnceAboveSixteenBits() public pure {
        checkNamedOccupancyAboveSixteenBits(LibMemoryKV.OCCUPANCY_MASK, "every list");
    }

    /// Whether `array` holds exactly the pairs `expected` names and nothing
    /// else, as a multiset: bit `i` of `expected` names the pair `keys[i]`,
    /// `valueFor(i)`. The pair order is unspecified, so position is not
    /// checked.
    ///
    /// Each value is `VALUE_BASE + i`, so the index a pair claims is read out
    /// of its own value, and the pair is then held to the key that index must
    /// carry. Collecting those indices into a bitset and comparing it to
    /// `expected` is multiset equality without a scan per pair: a pair exported
    /// twice is caught by its bit already being set, and one dropped,
    /// duplicated or invented by the bitsets differing.
    function exportMatches(bytes32[] memory array, bytes32[] memory keys, uint256 expected)
        internal
        pure
        returns (bool)
    {
        if (array.length % 2 != 0) {
            return false;
        }

        uint256 found = 0;
        for (uint256 cursor = 0; cursor < array.length; cursor += 2) {
            uint256 value = uint256(array[cursor + 1]);
            if (value < VALUE_BASE || value >= VALUE_BASE + keys.length) {
                return false;
            }

            uint256 index = value - VALUE_BASE;
            if (array[cursor] != keys[index]) {
                return false;
            }
            if (found & (uint256(1) << index) != 0) {
                return false;
            }
            found |= uint256(1) << index;
        }
        return found == expected;
    }

    /// Builds and exports every occupancy combination and checks each against
    /// the mask, count and pairs that combination must produce. The check is
    /// plain arithmetic and the first mask that fails it is carried out of the
    /// loop, so the assertion machinery runs once and the mask that failed is
    /// what the assertion reports.
    function checkEveryOccupancy() internal pure {
        bytes32[] memory keys = listKeys();

        uint256 free = freePointer();
        uint256 failed = NO_MASK;
        for (uint256 mask = 0; mask < OCCUPANCY_COMBINATIONS; mask++) {
            MemoryKV kv = storeForOccupancy(mask, keys);
            (uint256 lists, uint256 count) = listsOf(mask);
            if (maskOf(kv) != mask || lengthOf(kv) != count * 2 || !exportMatches(kv.toBytes32Array(), keys, lists)) {
                failed = mask;
                break;
            }

            setFreePointer(free);
        }

        assertEq(failed, NO_MASK, "occupancy mask whose store or export did not match");
    }

    /// Each key constant hashes into the list it claims, and together they
    /// occupy every list.
    function testKeyConstantsLandWhereClaimed() public pure {
        bytes32[] memory keys = listKeys();
        for (uint256 list = 0; list < LibMemoryKV.LIST_COUNT; list++) {
            assertEq(slotOf(keys[list]), list, "list key hashes into its list");
        }
        assertEq(
            occupancyOf(storeForOccupancy(LibMemoryKV.OCCUPANCY_MASK, keys)),
            LibMemoryKV.OCCUPANCY_MASK,
            "one key per list, every list occupied"
        );
    }

    /// Every occupancy combination, built at the free memory pointer the test
    /// starts with.
    function testEveryOccupancyCombinationExported() public pure {
        checkEveryOccupancy();
    }

    /// Every occupancy combination again, built from above sixteen bits, so
    /// the header address and every head and next pointer the walk follows
    /// are wider than sixteen bits.
    function testEveryOccupancyCombinationExportedAboveSixteenBits() public pure {
        setFreePointer(ABOVE_SIXTEEN_BITS);
        checkEveryOccupancy();
    }

    /// The word count sits in the meta word directly above the occupancy mask.
    /// Every list is occupied, and the count then grows one pair at a time to
    /// 128 words, setting each count bit from the second to the eighth; at
    /// every step the export holds exactly the store's pairs and writes
    /// nothing past its end.
    ///
    /// The extra pairs make list 0 a list many nodes long, so the walk down a
    /// list is exercised here too.
    function testCountBitsAreNeverReadAsMaskBits() public pure {
        bytes32[] memory keys = new bytes32[](LibMemoryKV.LIST_COUNT + EXTRA_PAIRS);
        {
            bytes32[] memory perList = listKeys();
            MemoryKVKey[] memory chain = keysInSlot(bytes32(uint256(1)), 0, EXTRA_PAIRS);
            for (uint256 i = 0; i < keys.length; i++) {
                keys[i] = i < perList.length ? perList[i] : MemoryKVKey.unwrap(chain[i - perList.length]);
            }
        }

        MemoryKV kv = storeForOccupancy(LibMemoryKV.OCCUPANCY_MASK, keys);
        for (uint256 pairs = LibMemoryKV.LIST_COUNT; pairs <= keys.length; pairs++) {
            if (pairs > LibMemoryKV.LIST_COUNT) {
                kv = kv.set(MemoryKVKey.wrap(keys[pairs - 1]), MemoryKVVal.wrap(valueFor(pairs - 1)));
            }
            assertEq(maskOf(kv), LibMemoryKV.OCCUPANCY_MASK, "every list stays occupied");
            assertEq(lengthOf(kv), pairs * 2, "two words per pair");

            // The array's length word, its pairs, then two words past its end.
            dirtyFreeMemory(PAST_THE_END, pairs * 2 + 3);
            bytes32[] memory array = kv.toBytes32Array();
            // Read before any assert, as an assert message allocates over them.
            uint256 end = freePointer();
            bytes32 firstPastTheEnd = LibPointer.unsafeReadWord(Pointer.wrap(end));
            bytes32 secondPastTheEnd = LibPointer.unsafeReadWord(Pointer.wrap(end + 0x20));

            uint256 arrayAt = Pointer.unwrap(LibBytes32Array.startPointer(array));
            assertEq(end, arrayAt + 0x20 + pairs * 0x40, "the export ends after its pairs");
            assertTrue(exportMatches(array, keys, (uint256(1) << pairs) - 1), "every pair exported exactly once");
            assertEq(firstPastTheEnd, PAST_THE_END, "the first word past the end is untouched");
            assertEq(secondPastTheEnd, PAST_THE_END, "the second word past the end is untouched");
        }
    }
}
