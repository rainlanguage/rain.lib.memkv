// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {MemoryKV, MemoryKVKey} from "src/lib/LibMemoryKV.sol";
import {LibMemoryKVTestKeys} from "test/lib/LibMemoryKVTestKeys.sol";

/// @title LibMemoryKVTestHandle
/// The fields packed into a `MemoryKV` handle: fifteen 16 bit head pointers,
/// one per internal list, under a 16 bit word count.
library LibMemoryKVTestHandle {
    /// The widest head pointer a list slot can hold.
    uint256 internal constant POINTER_MAX = 0xFFFF;

    /// The word count the store carries in its top 16 bits.
    function lengthOf(MemoryKV kv) internal pure returns (uint256) {
        return MemoryKV.unwrap(kv) >> 0xf0;
    }

    /// The 16 bit head pointer `kv` holds for internal list `slot`.
    function headOf(MemoryKV kv, uint256 slot) internal pure returns (uint256) {
        return (MemoryKV.unwrap(kv) >> (slot * 0x10)) & POINTER_MAX;
    }

    /// The 16 bit head pointer `kv` holds for the internal list `key` belongs
    /// to.
    function headOf(MemoryKV kv, MemoryKVKey key) internal pure returns (uint256) {
        return headOf(kv, LibMemoryKVTestKeys.slotOf(key));
    }
}
