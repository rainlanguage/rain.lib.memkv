// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";

import {LibPointer, Pointer} from "rain-solmem-0.1.28/src/lib/LibPointer.sol";
import {LibBytes32Array} from "rain-solmem-0.1.28/src/lib/LibBytes32Array.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {LibMemoryKVPacked, PackedMemoryKV, PACKED_MEMORY_KV_EMPTY} from "test/lib/LibMemoryKVPacked.sol";
import {dirtyFreeMemory, setFreePointer} from "test/lib/LibFreeMemory.sol";
import {keyForSlot, slotOf} from "test/lib/LibMemoryKVKeys.sol";
import {headOf, metaOf, occupancyBitOf} from "test/lib/LibMemoryKVHandle.sol";

/// @title LibMemoryKVPackedParityTest
/// `LibMemoryKV` against `LibMemoryKVPacked`, the packed-handle layout. For
/// any sequence of `set` calls the two answer every `get` and `has` alike and
/// export the same words in the same order. The occupancy mask, the meta word,
/// `SLOT_TABLE` and the header the first insert allocates are checked against
/// the layout the `MemoryKV` NatSpec documents and the `LibMemoryKV` constants
/// name.
contract LibMemoryKVPackedParityTest is Test {
    /// A quarter of every occupancy mask, the share each mask test runs.
    uint256 internal constant MASK_QUARTER = (LibMemoryKV.OCCUPANCY_MASK + 1) / 4;

    /// The words the first insert into the empty store allocates: its header,
    /// then its node.
    uint256 internal constant FIRST_INSERT_WORDS = (LibMemoryKV.HEADER_BYTES + LibMemoryKV.NODE_BYTES) / 0x20;

    /// The word at `pointer`.
    function wordAt(uint256 pointer) internal pure returns (uint256) {
        return uint256(LibPointer.unsafeReadWord(Pointer.wrap(pointer)));
    }

    /// The free memory pointer.
    function freePointer() internal pure returns (uint256) {
        return Pointer.unwrap(LibPointer.allocatedMemoryPointer());
    }

    /// `keccak256(seed, stream << 128 | i)`, hashed in scratch space so that
    /// building a sequence allocates nothing.
    function tag(uint256 seed, uint256 stream, uint256 i) internal pure returns (bytes32 hashed) {
        assembly ("memory-safe") {
            mstore(0, seed)
            mstore(0x20, or(shl(128, stream), i))
            hashed := keccak256(0, 0x40)
        }
    }

    /// Sets `keys[i]` to `values[i]` in order in a packed store, then in a
    /// `LibMemoryKV` store, and asserts both export the same words in the same
    /// order and answer `get` and `has` alike for every probe. The packed
    /// store is built first, so its nodes sit below every `LibMemoryKV` node.
    function checkParity(bytes32[] memory keys, bytes32[] memory values, bytes32[] memory probes) internal pure {
        PackedMemoryKV packed = PACKED_MEMORY_KV_EMPTY;
        for (uint256 i = 0; i < keys.length; i++) {
            packed = LibMemoryKVPacked.set(packed, MemoryKVKey.wrap(keys[i]), MemoryKVVal.wrap(values[i]));
        }
        MemoryKV kv = MEMORY_KV_EMPTY;
        for (uint256 i = 0; i < keys.length; i++) {
            kv = LibMemoryKV.set(kv, MemoryKVKey.wrap(keys[i]), MemoryKVVal.wrap(values[i]));
        }

        assertEq(LibMemoryKV.toBytes32Array(kv), LibMemoryKVPacked.toBytes32Array(packed), "export");

        for (uint256 i = 0; i < probes.length; i++) {
            MemoryKVKey probe = MemoryKVKey.wrap(probes[i]);
            (uint256 exists, MemoryKVVal value) = LibMemoryKV.get(kv, probe);
            (uint256 packedExists, MemoryKVVal packedValue) = LibMemoryKVPacked.get(packed, probe);
            assertEq(exists, packedExists, "exists");
            assertEq(MemoryKVVal.unwrap(value), MemoryKVVal.unwrap(packedValue), "value");
            assertEq(LibMemoryKV.has(kv, probe), LibMemoryKVPacked.has(packed, probe), "has");
        }
    }

    /// Up to 250 sets drawn from a pool of up to 200 keys, so both updates and
    /// lists many nodes long occur. Probes every pool key and one key outside
    /// the pool.
    function testParityOverAKeyPool(uint256 seed, uint256 length, uint256 poolSize) external pure {
        length = bound(length, 0, 250);
        poolSize = bound(poolSize, 1, 200);
        bytes32[] memory pool = new bytes32[](poolSize);
        for (uint256 i = 0; i < poolSize; i++) {
            pool[i] = tag(seed, 1, i);
        }
        bytes32[] memory keys = new bytes32[](length);
        bytes32[] memory values = new bytes32[](length);
        for (uint256 i = 0; i < length; i++) {
            keys[i] = pool[uint256(tag(seed, 2, i)) % poolSize];
            values[i] = tag(seed, 3, i);
        }
        bytes32[] memory probes = new bytes32[](poolSize + 1);
        for (uint256 i = 0; i < poolSize; i++) {
            probes[i] = pool[i];
        }
        probes[poolSize] = tag(seed, 4, 0);
        checkParity(keys, values, probes);
    }

    /// Fuzzer-chosen keys and values, zero and repeats included, truncated to
    /// the shorter array and at most 250 sets. Probes every key set and
    /// `extraProbe`.
    function testParityOverRawKeys(bytes32[] memory keys, bytes32[] memory values, bytes32 extraProbe) external pure {
        uint256 length = keys.length < values.length ? keys.length : values.length;
        if (length > 250) {
            length = 250;
        }
        LibBytes32Array.truncate(keys, length);
        LibBytes32Array.truncate(values, length);
        bytes32[] memory probes = new bytes32[](length + 1);
        for (uint256 i = 0; i < length; i++) {
            probes[i] = keys[i];
        }
        probes[length] = extraProbe;
        checkParity(keys, values, probes);
    }

    /// For every occupancy mask in `[from, to)`, one key in each list the mask
    /// marks, list `s` marked by `occupancyBitOf(s)`, set in ascending list
    /// order so that the set order is not the export order. The meta word is
    /// exactly the word count above the mask, and both stores export lowest
    /// mask bit first: the last list down to list 0.
    function checkMasks(uint256 from, uint256 to) internal pure {
        bytes32[] memory listKey = new bytes32[](LibMemoryKV.LIST_COUNT);
        for (uint256 s = 0; s < LibMemoryKV.LIST_COUNT; s++) {
            listKey[s] = MemoryKVKey.unwrap(keyForSlot(bytes32(s), s));
        }
        uint256 start = freePointer();
        for (uint256 mask = from; mask < to; mask++) {
            PackedMemoryKV packed = PACKED_MEMORY_KV_EMPTY;
            MemoryKV kv = MEMORY_KV_EMPTY;
            uint256 pairs = 0;
            for (uint256 s = 0; s < LibMemoryKV.LIST_COUNT; s++) {
                if (mask & occupancyBitOf(s) != 0) {
                    MemoryKVKey key = MemoryKVKey.wrap(listKey[s]);
                    MemoryKVVal value = MemoryKVVal.wrap(bytes32(s + 1));
                    packed = LibMemoryKVPacked.set(packed, key, value);
                    kv = LibMemoryKV.set(kv, key, value);
                    pairs++;
                }
            }

            bytes32[] memory expected = new bytes32[](pairs * 2);
            uint256 cursor = 0;
            for (uint256 s = LibMemoryKV.LIST_COUNT; s > 0; s--) {
                if (mask & occupancyBitOf(s - 1) != 0) {
                    expected[cursor] = listKey[s - 1];
                    expected[cursor + 1] = bytes32(s);
                    cursor += 2;
                }
            }

            assertEq(metaOf(kv), ((pairs * 2) << LibMemoryKV.COUNT_BIT_OFFSET) | mask, "meta");
            assertEq(LibMemoryKV.toBytes32Array(kv), expected, "export");
            assertEq(LibMemoryKVPacked.toBytes32Array(packed), expected, "packed export");
            setFreePointer(start);
        }
    }

    /// The first quarter of the occupancy masks, from the empty store.
    function testMetaAndExportOrderForTheFirstQuarterOfMasks() external pure {
        checkMasks(0, MASK_QUARTER);
    }

    /// The second quarter of the occupancy masks.
    function testMetaAndExportOrderForTheSecondQuarterOfMasks() external pure {
        checkMasks(MASK_QUARTER, 2 * MASK_QUARTER);
    }

    /// The third quarter of the occupancy masks.
    function testMetaAndExportOrderForTheThirdQuarterOfMasks() external pure {
        checkMasks(2 * MASK_QUARTER, 3 * MASK_QUARTER);
    }

    /// The last quarter of the occupancy masks, up to `LibMemoryKV.OCCUPANCY_MASK`.
    function testMetaAndExportOrderForTheLastQuarterOfMasks() external pure {
        checkMasks(3 * MASK_QUARTER, LibMemoryKV.OCCUPANCY_MASK + 1);
    }

    /// `SLOT_TABLE` is the table its NatSpec defines: the byte at index
    /// `2^j mod SLOT_TABLE_MODULUS` holds `LIST_COUNT - 1 - j` and every other
    /// byte is zero. The `LIST_COUNT` indices are distinct, so every single
    /// occupancy bit reads a byte of its own.
    function testSlotTableIsItsDefinition() external pure {
        uint256 table = 0;
        uint256 seen = 0;
        for (uint256 j = 0; j < LibMemoryKV.LIST_COUNT; j++) {
            uint256 index = (uint256(1) << j) % LibMemoryKV.SLOT_TABLE_MODULUS;
            assertEq(seen & (uint256(1) << index), 0, "index collision");
            seen |= uint256(1) << index;
            table |= (LibMemoryKV.LIST_COUNT - 1 - j) << (8 * (31 - index));
        }
        assertEq(table, LibMemoryKV.SLOT_TABLE, "SLOT_TABLE");
    }

    /// The first insert into the empty store allocates its header at the free
    /// memory pointer and zeroes it over dirty memory, then allocates the node
    /// directly after it. The key's head points at the node, every other head
    /// is zero, and the meta word is a count of two above the key's occupancy
    /// bit.
    function testFirstInsertZeroesHeaderOverDirtyMemory(bytes32 sentinel, bytes32 key, bytes32 value) external pure {
        vm.assume(sentinel != 0);
        dirtyFreeMemory(sentinel, FIRST_INSERT_WORDS);
        uint256 before = freePointer();
        MemoryKV kv = LibMemoryKV.set(MEMORY_KV_EMPTY, MemoryKVKey.wrap(key), MemoryKVVal.wrap(value));
        // Read before any assert, as an assert message allocates.
        uint256 after_ = freePointer();

        uint256 header = MemoryKV.unwrap(kv);
        uint256 node = header + LibMemoryKV.HEADER_BYTES;
        assertEq(header, before, "header at the free memory pointer");
        assertEq(after_, node + LibMemoryKV.NODE_BYTES, "header and one node");

        uint256 slot = slotOf(key);
        for (uint256 s = 0; s < LibMemoryKV.LIST_COUNT; s++) {
            assertEq(headOf(kv, s), s == slot ? node : 0, "head");
        }
        assertEq(metaOf(kv), (uint256(2) << LibMemoryKV.COUNT_BIT_OFFSET) | occupancyBitOf(slot), "meta");
        assertEq(wordAt(node), uint256(key), "node key");
        assertEq(wordAt(node + 0x20), uint256(value), "node value");
        assertEq(wordAt(node + 0x40), 0, "node next");

        assertFalse(
            LibMemoryKV.has(kv, keyForSlot(keccak256(abi.encode(key)), (slot + 1) % LibMemoryKV.LIST_COUNT)),
            "other list empty"
        );
        bytes32[] memory array = LibMemoryKV.toBytes32Array(kv);
        assertEq(array.length, 2, "export length");
        assertEq(array[0], key, "export key");
        assertEq(array[1], value, "export value");
    }
}
