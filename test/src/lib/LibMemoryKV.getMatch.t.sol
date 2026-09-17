// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal, MEMORY_KV_EMPTY} from "src/lib/LibMemoryKV.sol";
import {slotOf, keyForSlot} from "test/lib/LibMemoryKVTestHelpers.sol";

/// @title LibMemoryKVGetMatchTest
/// What `get` does with a node the walk has already reached: which bits of the
/// key decide the match, and what a walk that matches nothing reports. Both
/// cases put the node `get` must reject on the list the query key hashes to,
/// because a key whose list `get` never walks is rejected by the hash and says
/// nothing about the comparison.
contract LibMemoryKVGetMatchTest is Test {
    using LibMemoryKV for MemoryKV;

    /// A one node list holding `nodeKey`, hung off the internal list that
    /// `queryKey` hashes to, so a `get` for `queryKey` reaches that node
    /// whether or not the two keys are the same. The node's address comes back
    /// alongside the store so a case can rewrite the node in place.
    function craftNodeInSlotOf(MemoryKVKey queryKey, MemoryKVKey nodeKey, MemoryKVVal value)
        internal
        pure
        returns (MemoryKV, uint256)
    {
        MemoryKV kv;
        uint256 node;
        uint256 bitOffset = slotOf(MemoryKVKey.unwrap(queryKey)) * 0x10;
        assembly ("memory-safe") {
            node := mload(0x40)
            mstore(0x40, add(node, 0x60))
            mstore(node, nodeKey)
            mstore(add(node, 0x20), value)
            mstore(add(node, 0x40), 0)

            kv := or(shl(0xf0, 0x02), shl(bitOffset, node))
        }
        require(node <= 0xFFFF, "crafted node pointer must fit 16 bits");
        return (kv, node);
    }

    /// Overwrite the key word of a crafted node, leaving its value and next
    /// pointer alone.
    function writeNodeKey(uint256 node, MemoryKVKey key) internal pure {
        assembly ("memory-safe") {
            mstore(node, key)
        }
    }

    /// The match is equality across the whole 256 bit word: a node key one bit
    /// away from the query key is a different key, whichever of the 256 bits it
    /// is. A comparison narrower than the word would answer for a neighbouring
    /// key over the bits it dropped, and hand back that key's value.
    function testGetRequiresEveryBitOfTheKey() external pure {
        MemoryKVKey queryKey = MemoryKVKey.wrap(bytes32(type(uint256).max / 3));
        MemoryKVVal value = MemoryKVVal.wrap(bytes32(uint256(0xDEC0DE)));
        (MemoryKV kv, uint256 node) = craftNodeInSlotOf(queryKey, queryKey, value);

        (uint256 exists, MemoryKVVal got) = kv.get(queryKey);
        assertEq(exists, 1, "the key itself is a hit");
        assertEq(MemoryKVVal.unwrap(got), MemoryKVVal.unwrap(value), "the key itself reports its value");

        // Every bit in turn, ending when the walking bit falls off the top.
        for (uint256 bit = 1; bit != 0; bit <<= 1) {
            writeNodeKey(node, MemoryKVKey.wrap(bytes32(uint256(MemoryKVKey.unwrap(queryKey)) ^ bit)));
            (uint256 missExists, MemoryKVVal missValue) = kv.get(queryKey);
            assertEq(missExists, 0, "one bit apart is not the key");
            assertEq(MemoryKVVal.unwrap(missValue), 0, "one bit apart reports no value");
        }

        writeNodeKey(node, queryKey);
        (exists, got) = kv.get(queryKey);
        assertEq(exists, 1, "the key put back is a hit again");
        assertEq(MemoryKVVal.unwrap(got), MemoryKVVal.unwrap(value), "the key put back reports its value");
    }

    /// A key that hashes onto an OCCUPIED list but is not on it reports
    /// `(0, 0)`. Both returns keep their zero initialisation, so the value of a
    /// node the walk passed over cannot come back beside a zero `exists`. The
    /// three keys are driven onto one list rather than left to collide by
    /// chance, which two arbitrary keys do one time in fifteen.
    function testGetMissOverAnOccupiedListReportsNoValue() external pure {
        MemoryKVKey head = keyForSlot(bytes32(uint256(1)), 5);
        MemoryKVKey tail = keyForSlot(bytes32(uint256(2)), 5);
        MemoryKVKey absent = keyForSlot(bytes32(uint256(3)), 5);
        assertTrue(MemoryKVKey.unwrap(head) != MemoryKVKey.unwrap(tail), "head and tail are different keys");
        assertTrue(MemoryKVKey.unwrap(absent) != MemoryKVKey.unwrap(head), "absent is not the head key");
        assertTrue(MemoryKVKey.unwrap(absent) != MemoryKVKey.unwrap(tail), "absent is not the tail key");

        MemoryKV kv = MEMORY_KV_EMPTY;
        kv = kv.set(tail, MemoryKVVal.wrap(bytes32(uint256(0x222))));
        kv = kv.set(head, MemoryKVVal.wrap(bytes32(uint256(0x111))));
        assertTrue(((MemoryKV.unwrap(kv) >> 0x50) & 0xFFFF) != 0, "the absent key's list is occupied");
        assertEq(MemoryKV.unwrap(kv) >> 0xf0, 4, "both pairs are in the store");

        (uint256 exists, MemoryKVVal value) = kv.get(absent);
        assertEq(exists, 0, "the absent key is not in the store");
        assertEq(MemoryKVVal.unwrap(value), 0, "a walked past value does not come back");
    }
}
