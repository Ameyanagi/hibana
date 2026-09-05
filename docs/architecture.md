# Architecture

Hibana owns Fuzzy pattern preparation, scoring, match positions, ranking schemes, and top-K selection.

## Dependency boundary

Allowed ecosystem dependencies: Moji for shared text views and mappings once required; no CJK-specific dependency.
Expected downstream consumers: Yuragi and other search, command-palette, launcher, and filtering applications.

Dependencies point from applications and higher-level packages toward smaller
foundations. This repository must never import a downstream consumer. New
dependencies require a documented need and must not force unrelated users to
install an application, renderer, language layer, or scientific stack.

## Layers

Planned implementation areas: matcher, pattern, candidate, score, result, positions, case policy, schemes, scalar algorithms, later SIMD kernels, and top-K.

The package root exports only the small documented public surface. Algorithms,
generated tables, platform details, and backend implementations remain in
their owning modules. Generic Mojo-native buffers, spans, strings, and
collections are preferred over an ecosystem-specific universal container.

`Pattern` has one canonical prepared scalar sequence; no cached source string
can diverge from it. `Matcher` snapshots that value at construction. Mojo 1.0
struct fields are externally mutable even when underscore-prefixed, so public
documentation treats these types as mutable value snapshots and does not claim
post-mutation invariants. Underscore storage remains outside the stable API.

The optional `hibana.prepared` module is the interactive-query seam. Its
`PreparedCandidate` owns decoded Unicode scalars and one scheme's boundary
bonuses, while `MatchWorkspace` owns reusable dynamic-programming scratch.
Neither type is re-exported from the package root: one-shot and ordinary
match-many callers keep the `Matcher` API, while applications that can justify
candidate-side memory opt in explicitly.

The prepared API separates ranking from visible-result materialization.
`MatchWorkspace.score` returns an allocation-free `MatchScore`; it still traces
the winning path because Hibana's exact-case bonus is defined after position
selection. `MatchWorkspace.match_into` reruns the exact dynamic program and
writes the winning path into a caller-owned `List[Int]`. Search applications
can therefore score every candidate and reconstruct positions only for their
retained top-K rows. The ordinary `match` method remains the convenience path
whose result owns its position list.

For large retained indexes, `PreparedCorpus` moves candidate scalars and
bonuses into contiguous arenas with one offset table. `score_at` and
`match_into_at` preserve exact `PreparedCandidate` semantics by slicing those
arenas without materializing candidate objects. `hybrid_rank_corpus` and
`rank_corpus_exact` provide approximate-shortlist and fully exact corpus
workflows respectively. This path remains in advanced modules rather than the
small package root; see `docs/prepared-corpus.md` for profiling and memory data.

## Data flow

Input validation occurs at the public boundary. Internal layers operate on
explicit typed values, produce deterministic outputs for deterministic inputs,
and report invalid state rather than silently replacing it with a default.
I/O, clocks, randomness, terminal queries, filesystem access, and accelerator
selection stay at explicit effect or backend boundaries.

The correctness-first scalar algorithm is a bounded, fallible reference oracle.
It checks state-table, transition, tie-break, flattened-index, and score bounds
before allocating or evaluating. A future production scalar implementation must
preserve its match, score, and tie semantics without inheriting its polynomial
complexity.

The production matcher first runs an allocation-free linear subsequence scan.
Non-matches return before boundary preparation or `O(P*C)` scratch allocation.
Successful prepared matches retain that scratch allocation in the caller's
workspace and reset its logical contents on reuse. Checked cell and byte counts
reject overflow or the configured per-workspace budget before any DP allocation;
geometric capacity growth stays within that budget. Exact resource failures
propagate to the caller, including from parallel shards after all tasks join.
See [workspace budgets](workspace-budget.md) for API migration and peak-memory
accounting. Score-only matching adds no
dynamic allocation after that workspace has grown. Caller-owned position
storage similarly retains its capacity. The current DP still writes and scans
`O(P*C)` score cells and traces positions with up to another `O(P*C)` scan;
this algorithmic work is the remaining dominant optimization target.

ASCII folding stays scalar and on demand. Caching a second folded candidate
array increased memory traffic and regressed measured long dense matches, while
candidate preparation is amortized outside repeated matching. SIMD remains a
backend experiment until a benchmark identifies contiguous preprocessing as a
material bottleneck.
