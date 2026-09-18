# rain.lib.memkv

## Key/Value store

Implements an in-memory key/value store that can be snapshotted/exported to a
`bytes32[]` of pairwise keys/values as its items.

Internally a store is a header in memory holding the heads of 15 linked lists
and a meta word. The meta word carries the overall word count, which facilitates
O(1) allocation (excluding memory expansion costs) of an export `bytes32[]`, and
a mask of the occupied lists, which lets an export skip the empty ones. A
`MemoryKV` is the address of the header, so there is no ceiling on where in
memory a store lives or on how many pairs it holds.

Roughly O(1) for gets and sets for the amounts of data commonly handled in
Solidity. A get of a key alone in its list, or an insert into an empty list,
walks nothing. The first insert into an empty store also allocates and zeroes
the header, so it costs more than a later insert into an empty list.

Keys that hash into the same list are walked one at a time, so a get or a set
pays one more step for every key it walks past in that list. With only 15 lists
a store of five distinct keys is already more likely than not to hold a
collision.

The key/value store can differentiate between a key that is set to `0` and a key
that is unset for gets. However it is NOT possible to unset a key once it is
set.
