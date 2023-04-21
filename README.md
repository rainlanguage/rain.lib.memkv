# raim.lib.memkv

Docs at https://rainprotocol.github.io/rain.lib.memkv

## Key/Value store

Implements an in-memory key/value store that can be snapshotted/exported to an
`uint256[]` of pairwise keys/values as its items.

Roughly O(1) for gets and sets for the amounts of data commonly handled in
Solidity. Gets cost ~350 gas and sets are ~400 gas.

Internally represented as 15 linked lists and 1x 16bit overall word count that
facilitates O(1) allocation (excluding memory expansion costs) of an export
`uint256[]`.

The key/value store can differentiate between a key that is set to `0` and a key
that is unset for gets. However it is NOT possible to unset a key once it is set.