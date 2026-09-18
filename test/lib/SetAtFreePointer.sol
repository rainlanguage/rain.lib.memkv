// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal} from "src/lib/LibMemoryKV.sol";
import {setFreePointer} from "test/lib/LibFreeMemory.sol";

/// @title SetAtFreePointer
/// Inherited by tests that need `set` to allocate at an exact address.
abstract contract SetAtFreePointer {
    /// `LibMemoryKV.set` with the free memory pointer first moved to
    /// `freePointer`, so an insert's allocations start exactly there, in the
    /// caller's frame so the caller can read them back. An insert into the
    /// empty store allocates its header there and its node after the header;
    /// an insert into any other store allocates its node there.
    /// @param kv The store to set into.
    /// @param key The key to set.
    /// @param value The value to set.
    /// @param freePointer The address an insert starts allocating at. MUST be
    /// at least `0x80` and clear of every allocation the caller still reads, or
    /// the insert overwrites it.
    /// @return The handle `set` returned.
    function setAtFreePointerInFrame(MemoryKV kv, MemoryKVKey key, MemoryKVVal value, uint256 freePointer)
        internal
        pure
        returns (MemoryKV)
    {
        setFreePointer(freePointer);
        return LibMemoryKV.set(kv, key, value);
    }
}
