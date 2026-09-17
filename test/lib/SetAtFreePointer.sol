// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal} from "src/lib/LibMemoryKV.sol";

/// @title SetAtFreePointer
/// Inherited by tests that need `set` to place its node at an exact address.
abstract contract SetAtFreePointer {
    /// `LibMemoryKV.set` with the free memory pointer first moved to
    /// `freePointer`, so the node lands exactly there. External so a test calls
    /// it via `this.` and `vm.expectRevert` sees a real call.
    function setAtFreePointer(MemoryKV kv, MemoryKVKey key, MemoryKVVal value, uint256 freePointer)
        external
        pure
        returns (MemoryKV)
    {
        assembly ("memory-safe") {
            mstore(0x40, freePointer)
        }
        return LibMemoryKV.set(kv, key, value);
    }
}
