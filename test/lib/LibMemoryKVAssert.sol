// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {StdConstants} from "forge-std-1.16.2/src/StdConstants.sol";

import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal} from "src/lib/LibMemoryKV.sol";

/// Assert the store reports exactly `value` for `key`: the key exists and its
/// value word is `value`. `StdConstants.VM.assertEq` is what forge-std's
/// `assertEq(uint256,uint256,string)` calls, so the failure is the same one.
function assertValue(MemoryKV kv, MemoryKVKey key, uint256 value, string memory err) pure {
    (uint256 exists, MemoryKVVal got) = LibMemoryKV.get(kv, key);
    StdConstants.VM.assertEq(exists, 1, string.concat(err, " exists"));
    StdConstants.VM.assertEq(uint256(MemoryKVVal.unwrap(got)), value, string.concat(err, " value"));
}
