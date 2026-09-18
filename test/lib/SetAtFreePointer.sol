// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal} from "src/lib/LibMemoryKV.sol";
import {setFreePointer} from "test/lib/LibFreeMemory.sol";

/// @title SetAtFreePointer
/// Inherited by tests that need `set` to place its node at an exact address.
abstract contract SetAtFreePointer {
    /// `LibMemoryKV.set` with the free memory pointer first moved to
    /// `freePointer`, so an insert's node lands exactly there, in the caller's
    /// frame so the caller can read the node back.
    /// @param kv The store to set into.
    /// @param key The key to set.
    /// @param value The value to set.
    /// @param freePointer The address an insert allocates its node at. MUST be
    /// at least `0x80` and clear of every allocation the caller still reads, or
    /// the node overwrites it.
    /// @return The handle `set` returned.
    function setAtFreePointerInFrame(MemoryKV kv, MemoryKVKey key, MemoryKVVal value, uint256 freePointer)
        internal
        pure
        returns (MemoryKV)
    {
        setFreePointer(freePointer);
        return LibMemoryKV.set(kv, key, value);
    }

    /// `setAtFreePointerInFrame` in a frame of its own. External so a test
    /// calls it via `this.` and `vm.expectRevert` sees a real call.
    ///
    /// The handle crosses a call boundary both ways, which `MemoryKV` forbids
    /// in general, so `kv` MUST hold no head pointers: an empty store, with or
    /// without a forced count. The return is valid ONLY for bit inspection
    /// (`headOf`, `lengthOf`). It MUST NOT be passed to anything that walks its
    /// lists (`get`, `has`, `set`, `toBytes32Array`), because the walk would
    /// read the caller's memory at offsets that belong to this frame. A test
    /// that reads back does the set and the read in one external frame, with
    /// `setAtFreePointerInFrame`.
    /// @param kv The store to set into. MUST hold no head pointers.
    /// @param key The key to set.
    /// @param value The value to set.
    /// @param freePointer The address an insert allocates its node at. MUST be
    /// at least `0x80`, or the node lands on reserved memory in this frame.
    /// @return The handle `set` returned, for bit inspection only.
    function setAtFreePointer(MemoryKV kv, MemoryKVKey key, MemoryKVVal value, uint256 freePointer)
        external
        pure
        returns (MemoryKV)
    {
        return setAtFreePointerInFrame(kv, key, value, freePointer);
    }
}
