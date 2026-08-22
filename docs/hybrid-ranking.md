# Hybrid corpus ranking

`hibana.hybrid` composes fast membership scanning with exact finalist scoring
without changing Hibana's default exact API:

```mojo
from hibana import Pattern, Scheme
from hibana.hybrid import hybrid_rank
from hibana.prepared import PreparedCandidate
from std.collections import List

var candidates: List[PreparedCandidate] = [
    PreparedCandidate("src/MyComponent.mojo", scheme=Scheme.PATH),
    PreparedCandidate("src/search/matcher.mojo", scheme=Scheme.PATH),
]
var result = hybrid_rank(
    Pattern("smc"), candidates, k=20, shortlist_size=1_000
)
```

The stages are fixed and deterministic:

1. `fast_score` scans every candidate in linear time and retains a top-B heap
   containing only `(index, score)` values.
2. `MatchWorkspace.score` exactly scores those B candidates without allocating
   positions.
3. A second bounded heap retains the exact top K.
4. `MatchWorkspace.match_into` reconstructs positions only for those finalists.

## Contract

HYBRID ranking is approximate. `total_matches` is exact because fast and exact
matching have identical subsequence membership. Every returned row has the
exact Hibana score and exact scalar positions. The selected row set can differ
from a complete exact corpus rank because a candidate outside the fast top-B
shortlist is never exact-reranked. Ties at both stages prefer the lower original
candidate index.

Increasing `shortlist_size` trades exact dynamic-programming work for ranking
recall. If it covers every matching candidate, output equals full exact ranking.
Both `k` and the shortlist are corpus-bounded before heap allocation, so callers
may pass an effectively unbounded `k` without reserving unbounded memory when
the corpus itself is small. Both arguments must be positive. For a non-empty
corpus, the effective shortlist must cover the effective requested row count:
`min(shortlist_size, N) >= min(k, N)`.

Three fixed 256-item path-like quality corpora currently measure aggregate
recall@10 of 19/30 with B=64 and 27/30 with B=192; these are deterministic
regression gates, not general quality guarantees.

Beyond caller-owned prepared candidates, storage is bounded by the two heaps,
one reusable exact workspace, and K finalist position lists. There is no
per-candidate position list in either broad scan. `hybrid_rank` and its result
live in an opt-in advanced module and are intentionally not package-root
exports.

Applications retaining large indexes can use `PreparedCorpus` and
`hybrid_rank_corpus` with the same contract. Its contiguous arenas remove
per-candidate list ownership while source indices and scalar positions retain
the same meaning. See [arena-backed prepared corpora](prepared-corpus.md).

Run the development benchmark with:

```sh
pixi run bench-hybrid
```

The benchmark performs three warmups followed by 31 measured samples and
reports nearest-rank p50 and p95. Its checksum includes the exact total plus
every finalist index, score, and Unicode scalar position.
