// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {LibPointer, Pointer} from "rain-solmem-0.1.28/src/lib/LibPointer.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {dirtyFreeMemory, setFreePointer} from "test/lib/LibFreeMemory.sol";
import {keysInSlot, slotOf} from "test/lib/LibMemoryKVKeys.sol";
import {headOf, lengthOf, maskOf, occupancyBitOf} from "test/lib/LibMemoryKVHandle.sol";
import {countPair} from "test/lib/LibMemoryKVExport.sol";

/// @title LibMemoryKVExportOccupancyTest
/// Pins the occupancy mask walk of `toBytes32Array`, the only path by which
/// internal lists 0..14 reach the exported array. Each step isolates the
/// lowest set bit of the mask, clears it, and copies the list that
/// `SLOT_TABLE` names for it, so which lists are exported is decided by the
/// mask alone and never by reading a head.
///
/// Two layers, and both are wanted.
///
/// The named tests each occupy one known list, or one known set of lists. A
/// store that populates many lists at once fails as "some pair is missing"
/// with no indication of which; a store built from named lists fails as that
/// list's key and value, and the test name says which list.
///
/// The enumerations then run every combination of which lists are occupied.
/// That is the walk's whole input: nothing it does branches on what a key or a
/// value is. Fifteen lists is 32768 combinations, so the enumerations cover
/// the named cases too, and nothing is sampled. The named cases are kept
/// anyway, for the name on the failure.
///
/// `listKeys` is what makes either affordable: one constant key per list, so
/// an occupancy is chosen rather than searched for.
///
/// Every header and node of every case an enumeration builds is allocated from
/// a free memory pointer that is rewound between cases, so each case builds at
/// the same addresses. The pair order is unspecified, so nothing here checks
/// it; `LibMemoryKV.packedParity.t.sol` pins the order the walk produces.
contract LibMemoryKVExportOccupancyTest is Test {
    using LibMemoryKV for MemoryKV;

    /// Every combination of which lists are occupied: every occupancy mask.
    uint256 constant OCCUPANCY_COMBINATIONS = LibMemoryKV.OCCUPANCY_MASK + 1;

    /// Every other list, starting at list 0: the even lists, whose occupancy
    /// bits are the even bits of the mask.
    uint256 constant OCCUPANCY_EVEN_LISTS = 0x5555;

    /// Every other list, starting at list 1: the odd lists.
    uint256 constant OCCUPANCY_ODD_LISTS = 0x2AAA;

    /// The first address that does not fit in sixteen bits. A store built from
    /// here has a header address, and heads and next pointers, that do not.
    uint256 constant ABOVE_SIXTEEN_BITS = 0x10000;

    /// Stands for "no mask", which a 15 bit mask cannot collide with.
    uint256 constant NO_MASK = type(uint256).max;

    /// Values sit above every constant key, so a copy that reads the key where
    /// the value belongs, or that reads another list's value, is a different
    /// word. The value of the key at index `i` is this base plus `i`, which is
    /// how `exportMatches` reads a pair's index back out of it.
    uint256 constant VALUE_BASE = 0x100;

    /// Pairs `testCountBitsAreNeverReadAsMaskBits` adds to list 0 behind the
    /// fifteen `listKeys`, taking the count from 30 words to 128.
    uint256 constant EXTRA_PAIRS = 49;

    /// What the words past the end of an export hold before it runs.
    bytes32 constant PAST_THE_END = keccak256("past the end of the export");

    /// One key per list: the smallest positive integer whose 32 byte big endian
    /// encoding hashes into that list. Regenerating one is
    /// `cast keccak $(cast to-uint256 <n>)` reduced modulo 15, and
    /// `testKeyConstantsLandWhereClaimed` is what holds them to it.
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
    /// its mask, and exports exactly their pairs, each once. A walk step that
    /// looks up the wrong list, or clears the wrong bit, or stops early, drops
    /// a pair or exports one twice: a count other than one.
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
    /// list `SLOT_TABLE` names for it. A table byte that names any other list
    /// copies that list's empty head instead, and the one pair is missing.
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

    /// List 14 is the lowest bit of the mask, so the walk reaches it first.
    function testList14AloneExports() public pure {
        checkSoleList(14);
    }

    /// The lowest and the highest bit of the mask, the walk's first and last
    /// possible steps, with every bit between them clear. A walk that stops
    /// before the top of the mask drops list 0.
    function testListsAtBothEndsOfTheMaskExport() public pure {
        checkNamedOccupancy(occupancyBitOf(0) | occupancyBitOf(14), "lists 0 and 14");
    }

    /// Every two lists whose occupancy bits are neighbours. A step that clears
    /// a neighbour of the bit it isolated skips a list, and one that clears
    /// nothing copies the same list again.
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
        checkNamedOccupancy(OCCUPANCY_EVEN_LISTS, "even lists");
        checkNamedOccupancy(OCCUPANCY_ODD_LISTS, "odd lists");
    }

    /// All fifteen lists at once. Every step must copy a list no other step
    /// copies, and between them reach every list.
    function testEveryListExportedExactlyOnce() public pure {
        checkNamedOccupancy(LibMemoryKV.OCCUPANCY_MASK, "every list");
    }

    function testEvenListsExportAboveSixteenBits() public pure {
        checkNamedOccupancyAboveSixteenBits(OCCUPANCY_EVEN_LISTS, "even lists");
    }

    function testOddListsExportAboveSixteenBits() public pure {
        checkNamedOccupancyAboveSixteenBits(OCCUPANCY_ODD_LISTS, "odd lists");
    }

    function testEveryListExportedExactlyOnceAboveSixteenBits() public pure {
        checkNamedOccupancyAboveSixteenBits(LibMemoryKV.OCCUPANCY_MASK, "every list");
    }

    /// Whether `array` holds exactly the pairs `expected` names and nothing
    /// else, as a multiset: bit `i` of `expected` names the pair `keys[i]`,
    /// `valueFor(i)`. `toBytes32Array` documents its pair order as
    /// unspecified, so position is deliberately not checked.
    ///
    /// Each value is `VALUE_BASE + i`, so the index a pair claims is read out
    /// of its own value, and the pair is then held to the key that index must
    /// carry. Collecting those indices into a bitset and comparing it to
    /// `expected` is multiset equality without a scan per pair: a pair exported
    /// twice is caught by its bit already being set, and one dropped,
    /// duplicated or invented by the bitsets differing.
    ///
    /// The named tests check the same thing through `countPair`, which costs a
    /// scan per pair but names the list it checked. Here the whole point is
    /// 32768 cases, so the check is the cheap one.
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

    /// Builds and exports all 32768 occupancy combinations and checks each
    /// against the mask, count and pairs that combination must produce. The
    /// check is plain arithmetic and the first mask that fails it is carried
    /// out of the loop, so the assertion machinery runs once rather than 32768
    /// times and the mask that failed is what the assertion reports.
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

    /// The fifteen key constants are the whole reason a combination can be
    /// chosen rather than searched for, and every test here reads its result
    /// through the list each key claims. Should the hash that `get` and `set`
    /// share ever move, the keys stop naming the lists they claim and the
    /// tests silently cover something other than what they report.
    ///
    /// Occupying all fifteen at once is what makes them fifteen distinct lists
    /// rather than fifteen keys that each hash somewhere. `set` routes on the
    /// key alone, so that plus one key per list is every occupancy.
    function testKeyConstantsLandWhereClaimed() public pure {
        bytes32[] memory keys = listKeys();
        for (uint256 list = 0; list < LibMemoryKV.LIST_COUNT; list++) {
            assertEq(slotOf(keys[list]), list, "list key hashes into its list");
        }
        assertEq(
            occupancyOf(storeForOccupancy(LibMemoryKV.OCCUPANCY_MASK, keys)),
            LibMemoryKV.OCCUPANCY_MASK,
            "fifteen keys, fifteen lists"
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

    /// The word count sits in the meta word directly above the occupancy mask,
    /// with only the zero bit 15 between them. A mask read wider than
    /// `LibMemoryKV.OCCUPANCY_MASK` takes count bits for occupancy bits, and
    /// `SLOT_TABLE` maps every bit to some list, so the walk then copies a
    /// list a second time, after every true mask bit, past the end of the
    /// array the count sized. Every list is occupied here so that any such bit
    /// lands on a list with pairs in it, and the count then runs from 30 words
    /// to 128, setting each count bit from the second to the eighth.
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

            uint256 arrayAt;
            assembly ("memory-safe") {
                arrayAt := array
            }
            assertEq(end, arrayAt + 0x20 + pairs * 0x40, "the export ends after its pairs");
            assertTrue(exportMatches(array, keys, (uint256(1) << pairs) - 1), "every pair exported exactly once");
            assertEq(firstPastTheEnd, PAST_THE_END, "the first word past the end is untouched");
            assertEq(secondPastTheEnd, PAST_THE_END, "the second word past the end is untouched");
        }
    }
}
