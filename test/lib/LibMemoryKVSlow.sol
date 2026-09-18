// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {LibBytes32Array} from "rain-solmem-0.1.28/src/lib/LibBytes32Array.sol";

import {LibMemoryKV, MemoryKV} from "src/lib/LibMemoryKV.sol";
import {headAddressOf, lengthOf} from "test/lib/LibMemoryKVHandle.sol";

/// @title LibMemoryKVSlow
/// Independent reference implementations that `LibMemoryKV` is tested against.
/// `exists`, `get` and `set` keep the store as a flat `bytes32[]` of pairs, each
/// key at an even index and its value in the word after it, linear in the
/// number of pairs and in no canonical order. `toBytes32ArrayLinear` exports a
/// `MemoryKV` without the occupancy mask.
library LibMemoryKVSlow {
    /// Finds `key` in `pairs`.
    /// @param pairs Pairwise key/value array.
    /// @param key The key to look for.
    /// @return found Whether `key` is present.
    /// @return index Index of the KEY word when found; the value is at
    /// `index + 1`. `0` when not found, which is also the index of a key found
    /// at the start of `pairs`, so read `found` first.
    function exists(bytes32[] memory pairs, bytes32 key) internal pure returns (bool found, uint256 index) {
        for (uint256 i = 0; i < pairs.length; i += 2) {
            if (pairs[i] == key) {
                //forge-lint: disable-next-line(boolean-cst)
                return (true, i);
            }
        }
        //forge-lint: disable-next-line(boolean-cst)
        return (false, 0);
    }

    /// Reads the value paired with `key`.
    /// @param pairs Pairwise key/value array.
    /// @param key The key to look up.
    /// @return found Whether `key` is present.
    /// @return value The value paired with `key`, or `0` when not found.
    function get(bytes32[] memory pairs, bytes32 key) internal pure returns (bool found, bytes32 value) {
        uint256 index;
        (found, index) = exists(pairs, key);
        value = found ? pairs[index + 1] : bytes32(0);
    }

    /// Upserts `key` to `value`. An update overwrites the value in `pairs` in
    /// place. An insert appends the pair with `LibBytes32Array.unsafeExtend`,
    /// which extends `pairs` in place or copies it, so the caller MUST use the
    /// returned array only and MUST NOT use `pairs` afterwards.
    /// @param pairs Pairwise key/value array.
    /// @param key The key to set.
    /// @param value The value to pair with `key`.
    /// @return The array holding every pair, including `key` and `value`.
    function set(bytes32[] memory pairs, bytes32 key, bytes32 value) internal pure returns (bytes32[] memory) {
        (bool found, uint256 index) = exists(pairs, key);
        if (found) {
            pairs[index + 1] = value;
            return pairs;
        } else {
            bytes32[] memory pair = new bytes32[](2);
            pair[0] = key;
            pair[1] = value;
            return LibBytes32Array.unsafeExtend(pairs, pair);
        }
    }

    /// `LibMemoryKV.toBytes32Array` with the occupancy mask walk replaced by a
    /// walk over every head in the header, list 0 first. This is the linear
    /// loop the mask walk is measured against, so it MUST stay a plain walk
    /// over every head. Like the fast path, it sizes the array from the word
    /// count in the meta word, fills it by walking every list, and leaves the
    /// free memory pointer past every word written. It exports the same pairs
    /// as `toBytes32Array`; the pair order is not guaranteed to match.
    /// @param kv The entrypoint into the key/value store.
    /// @return array Every key and value in `kv`, copied pairwise.
    function toBytes32ArrayLinear(MemoryKV kv) internal pure returns (bytes32[] memory array) {
        uint256 length = lengthOf(kv);
        // The heads are consecutive words from the first head to the address
        // one past the last. The empty store has no header, so no heads.
        uint256 head = headAddressOf(kv, 0);
        uint256 headsEnd = MemoryKV.unwrap(kv) == 0 ? head : headAddressOf(kv, LibMemoryKV.LIST_COUNT);
        assembly ("memory-safe") {
            array := mload(0x40)
            mstore(0x40, add(array, add(0x20, mul(length, 0x20))))
            mstore(array, length)

            function copyFromPtr(cursor, pointer) -> end {
                for {} iszero(iszero(pointer)) {
                    pointer := mload(add(pointer, 0x40))
                    cursor := add(cursor, 0x40)
                } {
                    mstore(cursor, mload(pointer))
                    mstore(add(cursor, 0x20), mload(add(pointer, 0x20)))
                }
                end := cursor
            }

            let cursor := add(array, 0x20)
            for {} lt(head, headsEnd) { head := add(head, 0x20) } { cursor := copyFromPtr(cursor, mload(head)) }
        }
    }
}
