// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Vm} from "forge-std-1.16.1/src/Vm.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal} from "src/lib/LibMemoryKV.sol";

/// @title LibMemoryKVTestAssert
/// Assertions over what a store reports, through the cheatcode assertions that
/// forge-std's `assertEq` is built on.
library LibMemoryKVTestAssert {
    Vm internal constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// Assert the store reports exactly `value` for `key`: the key exists and
    /// its value word is `value`.
    function assertValue(MemoryKV kv, MemoryKVKey key, uint256 value, string memory err) internal pure {
        (uint256 exists, MemoryKVVal got) = LibMemoryKV.get(kv, key);
        VM.assertEq(exists, 1, string.concat(err, " exists"));
        VM.assertEq(uint256(MemoryKVVal.unwrap(got)), value, string.concat(err, " value"));
    }
}
