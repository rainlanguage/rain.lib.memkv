// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @dev The pairs `set` inserts into an empty store in a frame whose free
/// memory pointer starts at `0x80` and that allocates nothing else, before the
/// next insert reverts `MemoryKVOverflow`.
uint256 constant EMPTY_FRAME_PAIRS = 682;
