// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {README_PATH, LIB_MEMORY_KV_PATH, assertTextStates, assertDocumentStates} from "test/lib/LibDocumentAssert.sol";

/// @title LibDocumentAssertTest
/// The promises `assertTextStates` and `assertDocumentStates` make and other
/// tests rest on.
contract LibDocumentAssertTest is Test {
    /// `assertTextStates` in a frame of its own so a test can expect its
    /// failure.
    function assertTextStatesExternal(string memory text, string memory phrase, string memory source) external pure {
        assertTextStates(text, phrase, source);
    }

    /// `assertDocumentStates` in a frame of its own so a test can expect its
    /// failure.
    function assertDocumentStatesExternal(string memory path, string memory phrase) external view {
        assertDocumentStates(path, phrase);
    }

    /// A phrase the text holds verbatim passes.
    function testAssertTextStatesPassesOnAPhraseTheTextHolds() external pure {
        assertTextStates("the fixture text states ~120 gas here", "~120 gas", "text");
    }

    /// A phrase the text does not hold verbatim fails, naming the source and
    /// the phrase, even when the text holds a longer or shorter figure around
    /// the same digits.
    function testAssertTextStatesFailsOnAPhraseTheTextDoesNotHold() external {
        vm.expectRevert(bytes("text does not state \"~12 gas\""));
        this.assertTextStatesExternal("the fixture text states ~120 gas here", "~12 gas", "text");
        vm.expectRevert(bytes("text does not state \"~1200 gas\""));
        this.assertTextStatesExternal("the fixture text states ~120 gas here", "~1200 gas", "text");
    }

    /// Each readable document states its own whole contents, which only holds
    /// when the file read is the one at `path`.
    function testAssertDocumentStatesReadsTheFileAtPath() external view {
        assertDocumentStates(README_PATH, vm.readFile(README_PATH));
        assertDocumentStates(LIB_MEMORY_KV_PATH, vm.readFile(LIB_MEMORY_KV_PATH));
    }

    /// A phrase longer than the whole file is one the file cannot hold, so it
    /// fails, naming the path and the phrase.
    function testAssertDocumentStatesFailsOnAPhraseTheFileDoesNotHold() external {
        string memory phrase = string.concat(vm.readFile(README_PATH), "~120 gas");
        vm.expectRevert(bytes(string.concat(README_PATH, " does not state \"", phrase, "\"")));
        this.assertDocumentStatesExternal(README_PATH, phrase);
    }
}
