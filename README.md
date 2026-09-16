# rain.lib.memkv

Docs at https://rainprotocol.github.io/rain.lib.memkv

## Key/Value store

Implements an in-memory key/value store that can be snapshotted/exported to an
`uint256[]` of pairwise keys/values as its items.

Internally represented as 15 linked lists and 1x 16bit overall word count that
facilitates O(1) allocation (excluding memory expansion costs) of an export
`uint256[]`.

Roughly O(1) for gets and sets for the amounts of data commonly handled in
Solidity. A key alone in its list costs ~240 gas to get and ~400 gas to insert.

Keys that hash into the same list are walked one at a time, so every key already
in a list adds ~65 gas to a get from it and ~75 gas to a set into it: the fourth
key to land in one list inserts for ~620 gas. With only 15 lists a store of five
distinct keys is already more likely than not to hold a collision.

The key/value store can differentiate between a key that is set to `0` and a key
that is unset for gets. However it is NOT possible to unset a key once it is
set.
