// SPDX-License-Identifier: CAL
pragma solidity =0.8.18;

import "forge-std/Test.sol";
import "rain.lib.hash/LibHashNoAlloc.sol";
import "sol.lib.memory/LibMemory.sol";

import "../src/LibMemoryKV.sol";

contract LibMemoryKVSaturateTest is Test {
    using LibMemoryKV for MemoryKV;

    function testSaturate(bytes32 seed) public {
        MemoryKV kv = MemoryKV.wrap(0);

        bytes32[60] memory kvs = [
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(0))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(1))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(2))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(3))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(4))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(5))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(6))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(7))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(8))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(9))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(10))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(11))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(12))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(13))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(14))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(15))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(16))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(17))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(18))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(19))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(20))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(21))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(22))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(23))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(24))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(25))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(26))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(27))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(28))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(29))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(30))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(31))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(32))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(33))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(34))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(35))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(36))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(37))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(38))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(39))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(40))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(41))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(42))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(43))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(44))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(45))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(46))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(47))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(48))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(49))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(50))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(51))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(52))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(53))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(54))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(55))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(56))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(57))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(58))),
            LibHashNoAlloc.combineHashes(seed, bytes32(uint256(59)))
        ];

        // Rehash each key until we get an even spread across all internal list
        // slots.
        for (uint256 i = 0; i < kvs.length; i += 2) {
            bytes32 key = kvs[i];

            assembly ("memory-safe") {
                function calculateSlot(k) -> slot {
                    mstore(0, k)
                    slot := mod(keccak256(0, 0x20), 15)
                }
                for {} 1 {} {
                    let slot := calculateSlot(key)

                    switch eq(slot, mod(div(i, 2), 15))
                    case 1 { break }
                    default {
                        mstore(0, key)
                        key := keccak256(0, 0x20)
                    }
                }
            }
            kvs[i] = key;

            kv = kv.set(MemoryKVKey.wrap(uint256(key)), MemoryKVVal.wrap(uint256(kvs[i + 1])));
            assertTrue(LibMemory.memoryIsAligned());
        }

        // Every kv slot should be nonzero at this point.
        for (uint256 i = 0; i < 0xff; i += 0x10) {
            assertTrue(((MemoryKV.unwrap(kv) >> i) & 0xFFFF) > 0);
        }

        // Top slot must be the length.
        assertEq(60, MemoryKV.unwrap(kv) >> 0xf0);

        // Every value must be gettable.
        for (uint256 i = 0; i < kvs.length; i += 2) {
            (uint256 exists, MemoryKVVal value) = kv.get(MemoryKVKey.wrap(uint256(kvs[i])));
            assertEq(1, exists);
            assertEq(MemoryKVVal.unwrap(value), uint256(kvs[i + 1]));
        }

        // Exported array must include every key/value pair.
        uint256[] memory export = LibMemoryKV.toUint256Array(kv);
        assertTrue(LibMemory.memoryIsAligned());

        assertEq(kvs.length, export.length);
        uint256 matches = 0;
        for (uint256 i = 0; i < kvs.length; i += 2) {
            for (uint256 j = 0; j < export.length; j += 2) {
                if (uint256(kvs[i]) == export[j] && uint256(kvs[i + 1]) == export[j + 1]) {
                    matches += 1;
                }
            }
        }
        assertEq(matches, 30);
    }
}
