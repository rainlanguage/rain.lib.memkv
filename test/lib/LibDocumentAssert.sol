// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {StdConstants} from "forge-std-1.16.1/src/StdConstants.sol";

/// @dev The README, relative to the project root. `foundry.toml` grants
/// tests read access to it.
string constant README_PATH = "README.md";

/// @dev The library source, relative to the project root. `foundry.toml`
/// grants tests read access to it.
string constant LIB_MEMORY_KV_PATH = "src/lib/LibMemoryKV.sol";

/// Assert `text` contains `phrase` verbatim, naming `source` in the failure.
/// @param text The text to search.
/// @param phrase The exact phrase `text` must contain.
/// @param source What `text` is, for the failure message.
function assertTextStates(string memory text, string memory phrase, string memory source) pure {
    StdConstants.VM
        .assertTrue(StdConstants.VM.contains(text, phrase), string.concat(source, " does not state \"", phrase, "\""));
}

/// Assert the file at `path` contains `phrase` verbatim. A test renders
/// `phrase` from the constant it checks the code against, so the file and the
/// constant cannot drift apart without a failure. Reading `path` needs a read
/// `fs_permissions` entry for it in `foundry.toml`.
/// @param path The file, relative to the project root.
/// @param phrase The exact phrase the file must contain.
function assertDocumentStates(string memory path, string memory phrase) view {
    assertTextStates(StdConstants.VM.readFile(path), phrase, path);
}
