# Arena-backed prepared corpora

`hibana.prepared.PreparedCorpus` is the advanced storage path for applications
that retain many candidates across queries. It keeps all decoded Unicode
scalars and boundary bonuses in two contiguous arenas plus one offset table.
Source strings remain caller-owned and results refer to them by source index.

```mojo
from hibana import Pattern, Scheme
from hibana.hybrid import hybrid_rank_corpus
from hibana.parallel import rank_corpus_exact
from hibana.prepared import PreparedCorpus

var corpus = PreparedCorpus(scheme=Scheme.PATH)
corpus.reserve(candidate_capacity=100_000, scalar_capacity=5_000_000)
corpus.append("src/alpha/render.mojo")
corpus.append("src/beta/search.mojo")

var approximate = hybrid_rank_corpus(
    Pattern("srm"), corpus, k=20, shortlist_size=1_000
)
var exact = rank_corpus_exact(corpus, Pattern("srm"), k=20)
```

`hybrid_rank_corpus` has exactly the same HYBRID contract as `hybrid_rank`:
membership count, finalist scores, finalist positions, and ties are exact, but
fast-shortlist selection is approximate. `rank_corpus_exact` has the same
fully exact deterministic contract and synchronous task-runtime boundary as
`rank_prepared_exact`. `MatchWorkspace.score_at`, `match_into_at`, and
`fast_score_at` provide indexed building blocks when an application owns its
ranking loop.

The corpus uses one scoring scheme. Empty candidates are valid. Append order is
the stable source-index order. `reserve` is optional but avoids arena growth
during bulk construction. `estimated_payload_bytes` reports scalar, bonus, and
offset payload on Hibana's supported 64-bit targets; allocator metadata and
three list headers are excluded.

`PreparedCorpus` has ordinary Mojo value semantics: explicit copy construction
deep-copies the scalar arena, bonus arena, and offset table. That independence
is useful for snapshots but expensive for a large index. Pass a corpus as a
borrowed argument or move it when another independent arena set is unnecessary.
For indexed reconstruction, a valid `match_into_at` call clears the supplied
position list for every outcome, including a workspace-budget error; an invalid
index raises before changing it. `MatchWorkspace(budget=WorkspaceBudget(...))`
bounds retained exact DP scratch; see [workspace budgets](workspace-budget.md).

## Profile evidence

The implementation was selected using a compiled 100,000-candidate workload on
an Apple M4 running macOS 26.5.1 with Mojo 1.0.0. `xctrace` Time Profiler and
`/usr/bin/sample` show that the all-hit hybrid scan spends about 82% of sampled
main-thread CPU in linear fast scoring, about 7% in exact shortlist DP, and
about 3% in top-B heap maintenance. The exact path is dominated by DP table
construction across workers, followed by reconstruction and the subsequence
prefilter. Each ranking call creates bounded shortlist/top-k heaps, exact
workspace, final rows, and—for parallel exact ranking—worker states. Arena
storage reduces retained candidate ownership; it does not make ranking calls
allocation-free. The profiling script records CPU samples and peak resident
memory, not an allocation trace.

Arena storage reduced maximum resident set size from 85,540,864 to 72,777,728
bytes for the hybrid profiler and from 85,737,472 to 73,039,872 bytes for the
parallel exact profiler, approximately 15% in both cases. It replaces two
retained list allocations per candidate—200,000 allocations at this size—with
three corpus arenas.

The following numbers are historical local observations whose original raw
outputs and source revision were not retained; treat them as context, not as an
independently reproducible current baseline. New focused benchmark and profiler
wrappers print revision, dirty state, machine, compiler, fixture-source checksum,
workspace-source manifest checksum, and command metadata. Clean runs are
reproducible from that record; dirty runs must archive their diff as well.

In the paired 31-sample benchmark, arena hybrid all-hit latency improved from
12.479/12.652 ms p50/p95 to 10.629/11.632 ms. Arena serial exact improved from
288.399/373.586 ms to 264.940/294.554 ms. Parallel exact p50 was effectively
unchanged at 79.103 vs 79.384 ms while p95 improved from 102.913 to 88.458 ms.
These are development measurements, not portable guarantees; rerun on the
target corpus and hardware.

A one-byte bonus arena was also implemented and differentially verified, then
removed because required widening in the hottest loops caused a repeatable
latency regression. SIMD was not retained: fast subsequence scoring has
query-dependent branches and loop-carried match state, while exact DP has
running maxima and reconstruction dependencies. The profiler identifies no
material contiguous preprocessing kernel that would amortize SIMD setup.

Reproduce the CPU and memory profile with:

```sh
bash scripts/profile-corpus.sh hybrid
bash scripts/profile-corpus.sh arena-hybrid
bash scripts/profile-corpus.sh exact
bash scripts/profile-corpus.sh arena-exact
pixi run bench-hybrid
pixi run bench-parallel
```

Each profiler invocation also runs the corresponding owned or arena-backed
mode and requires their complete result checksums—total count plus every row
index, score, and position—to agree before it succeeds.
