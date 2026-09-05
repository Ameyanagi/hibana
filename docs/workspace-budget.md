# Exact matching workspace budgets

`hibana.budget.WorkspaceBudget` bounds the retained dynamic-programming (DP)
score table in one workspace. Each successful non-empty atom with `P` Unicode
scalars against a candidate with `C` scalars requires `P * C` cells. A cell is
one native `Int` (eight bytes on every supported package platform).

```mojo
from hibana import Matcher, Pattern
from hibana.budget import WorkspaceBudget
from hibana.parallel import rank_prepared_exact
from hibana.prepared import MatchWorkspace, PreparedCandidate


def main() raises:
    var budget = WorkspaceBudget(max_cells=1_000_000)
    var matcher = Matcher("sm", budget=budget)
    print(matcher.match("src/main.mojo"))

    var candidate = PreparedCandidate("src/main.mojo")
    var workspace = MatchWorkspace(budget=budget)
    print(workspace.score(Pattern("sm"), candidate).score)
    print(workspace.retained_cells(), budget.max_bytes())

    var candidates = [PreparedCandidate("src/main.mojo")]
    var page = rank_prepared_exact(candidates, Pattern("sm"), budget=budget)
    print(page.total_matches)
```

Pass the same keyword to `rank_corpus_exact`, `hybrid_rank`, or
`hybrid_rank_corpus`. Those calls configure every workspace they create.
`Matcher` keeps only one atom's score table live at a time, so its limit applies
to the largest matching atom rather than the sum of atom lengths.

The default `WorkspaceBudget()` has no application-specific limit. It permits
up to `Int.MAX // size_of[Int]()` cells, so cell indexing and payload byte sizes
remain representable. Explicit `max_cells` must be within that same inclusive
range. A byte-based application limit can be converted with
`WorkspaceBudget(max_cells=byte_limit // 8)` on supported 64-bit platforms.
`max_cells()` and `max_bytes()` are non-raising accessors; `validate()` is the
explicit checkpoint after unusual direct mutation of underscore storage.

Before allocating or growing DP scratch, every exact path checks dimension
multiplication, byte-size multiplication, and the configured limit. For example,
a two-scalar pattern and a three-scalar candidate exceed a five-cell budget:

```text
exact DP requires 6 cells (48 bytes); allowed 5 cells (40 bytes); shorten the query or candidate, or increase max_cells
```

`required_cells(pattern_count, candidate_count)` performs the same checks
without allocating input or DP storage. Overflow errors report the dimensions
or cell count and the allowed limit without evaluating an overflowing product.
The allocation-free empty-query and subsequence-rejection paths still run before
these checks. Therefore a zero-cell budget accepts empty matches and returns
ordinary non-matches; it raises for every successful non-empty exact match.

An error returns no partial result and never selects approximate matching.
Callers may explicitly choose `fast_score` or hybrid ranking, whose approximation
contract remains separate. Even an explicitly selected hybrid call raises if a
shortlisted candidate's exact DP exceeds its budget.

A rejected workspace operation preserves retained DP capacity and permits later
smaller matches. `match_into` clears caller positions before processing a valid
candidate, including on a budget error; `match_into_at` still preserves positions
when the corpus index itself is invalid.

## Peak memory and concurrency

A workspace grows geometrically but caps retained capacity at `max_cells`, even
when a doubling step would overshoot. Repeated calls within retained capacity
allocate no new DP storage. A limit is not a process-wide memory guarantee:
prepared input, boundary bonuses, union-position masks, result positions, heaps,
list headers, and allocator bookkeeping are outside this DP budget. Validate or
bound input separately before preparing externally supplied records.

For parallel exact ranking, let `W = min(parallelism_level(), ceil(N / grain_size))`
for a non-empty corpus, with a minimum worker limit of one. Each of the `W`
shards receives the whole per-workspace budget, so retained score payload can
reach `W * budget.max_bytes()`. For example, eight shards with one million cells
each retain up to 64 MB of score payload on 64-bit targets. During buffer growth,
old and new allocations can coexist temporarily; conservatively allow up to
`2 * W * budget.max_bytes()` for those score allocations, plus the other storage
listed above. These are mathematical planning formulas: check multiplication
when computing a total in application code.

Workers are joined before any error is raised to the caller. If several shards
fail, the first failing shard in source order supplies the error, independently
of scheduling. Successful shards may complete their scans; no cancellation is
implied. Worker buffers are freed after merging and before the final-position
workspace allocates, so reconstruction does not retain an extra shard's score
table at the same time.

## Source migration

Exact computation now has an explicit failure contract. `Matcher.match`,
`match_scalars`, both `rank` overload families, and `MatchWorkspace.match`,
`score`, and `match_into` are `raises`. Mark forwarding functions `raises` or
handle the error at an application boundary. The indexed, hybrid, and parallel
entry points already raised and retain that calling convention. Constructors
for matchers and workspaces remain non-raising when given a validated budget.

Default-budget scores, positions, deterministic ties, and accepted ordinary
inputs are unchanged. These checks do not introduce an approximate fallback.
