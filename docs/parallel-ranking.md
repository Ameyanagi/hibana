# Parallel exact prepared ranking

`hibana.parallel` is an opt-in synchronous kernel for repeatedly searching a
prepared candidate collection:

```mojo
from hibana import Pattern
from hibana.parallel import rank_prepared_exact
from hibana.prepared import PreparedCandidate

var candidates = [
    PreparedCandidate("src/alpha.mojo"),
    PreparedCandidate("src/beta.mojo"),
]
var page = rank_prepared_exact(candidates, Pattern("sm"), k=20)
```

The kernel gives every coarse shard its own exact `MatchWorkspace`, score-only
top-k heap, and match counter. Workers never allocate match-position lists.
After a fixed-order merge, `match_into()` reconstructs positions for only the
final `k` candidates. `source_index` is the candidate's zero-based position in
the input span; `positions` are Unicode scalar offsets within that candidate.
Ranking is deterministic: score descending, then input index ascending.
`total_matches` is counted before truncation.

`rank_corpus_exact` applies the same algorithm and contract to a
`PreparedCorpus`. It shares immutable arenas across workers and gives every
worker disjoint mutable workspace and heap state. This removes per-candidate
retained list ownership without changing deterministic source-index ties or
Unicode scalar positions.

Scans below `grain_size` use the same exact kernel serially. The default grain
is 4,096 candidates; benchmark the application corpus before changing it.

## Mojo 1.0 runtime boundary

This API uses the shipped `std.runtime.asyncrt.TaskGroup`. In Mojo 1.0 that
surface is toolchain-unstable and its origin checking is incomplete. Hibana
therefore keeps the task group local and stationary, shares owned candidates
through an immutable `Span` and arena candidates through a borrowed immutable
`PreparedCorpus`, assigns every task a disjoint mutable state span, and waits
before any backing storage can move.

Use this function synchronously from a normal Mojo call stack. Do not invoke it
inside `create_task()`, do not nest another task group around it, and do not
move an active task group. Mojo 1.0 has no supported task cancellation API;
background and cancellable orchestration belongs above this kernel after the
runtime supports robust nested task groups. The implementation uses no FFI,
but every supported Linux and macOS package target must exercise the parallel
tests in CI.

Run the serial-versus-parallel benchmark with:

```sh
pixi run bench-parallel
```

It performs three warmups followed by 31 measured samples for each mode and
reports nearest-rank p50/p95 plus p50/p95 speedups. The checksum covers the
exact total and every returned input index, score, and Unicode scalar position.
