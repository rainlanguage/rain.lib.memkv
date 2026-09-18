# rain.lib.memkv

## Key/Value store

Implements an in-memory key/value store that can be snapshotted/exported to a
`bytes32[]` of pairwise keys/values as its items.

Internally represented as 15 linked lists and 1x 16bit overall word count that
facilitates O(1) allocation (excluding memory expansion costs) of an export
`bytes32[]`.

Roughly O(1) for gets and sets for the amounts of data commonly handled in
Solidity. A get of a key alone in its list, or an insert into an empty list,
walks nothing.

Keys that hash into the same list are walked one at a time, so a get or a set
pays one more step for every key it walks past in that list. With only 15 lists
a store of five distinct keys is already more likely than not to hold a
collision.

The key/value store can differentiate between a key that is set to `0` and a key
that is unset for gets. However it is NOT possible to unset a key once it is
set.
