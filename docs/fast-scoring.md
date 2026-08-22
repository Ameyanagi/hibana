# Fast shortlist scoring

`hibana.fast` provides an opt-in first stage for large interactive search
indexes. It preserves exact fuzzy-match membership but approximates ranking:

```mojo
from hibana import Pattern, Scheme
from hibana.fast import fast_score
from hibana.prepared import PreparedCandidate

var pattern = Pattern("smc")
var candidate = PreparedCandidate("src/MyComponent", scheme=Scheme.PATH)
var score = fast_score(pattern, candidate)
```

`fast_score` finds the earliest complete subsequence, tightens that window from
right to left, and applies Hibana's normal scoring constants to the compact
alignment. It takes linear time in candidate length and constant extra storage.
The result contains only `matched` and `score`; it never allocates positions.
ASCII case behavior comes from `Pattern`, and boundary behavior comes from the
scheme used to construct `PreparedCandidate`.

The compact alignment is not guaranteed to maximize the exact score. A search
application should use fast scores to retain a generously sized top-B shortlist
and then call `MatchWorkspace.score` and `match_into` on those finalists. The
exact matcher remains Hibana's default public behavior and the correctness
oracle for match membership.

Run the 10,000-candidate all-hit/no-hit development benchmark with:

```sh
pixi run bench-fast
```

Benchmark results are evidence for the machine and revision reported by the
run, not a portable latency guarantee.

## SIMD decision

The greedy kernel intentionally remains scalar. Its pattern index changes when
each match is encountered, so every next comparison depends on the preceding
comparison; candidate lengths, Unicode scalars, early exits, and reverse
tightening add further lane divergence. `PreparedCandidate` stores independent
variable-length scalar lists, so cross-candidate SIMD would require a different
structure-of-arrays index rather than a safe local vector load.

On Apple M4 with Mojo 1.0.0 (`ed45d567`), the checked-in benchmark measured the
scalar fast scan at 92.4 ns/candidate for the all-hit case and 56.5 ns/candidate
for the no-hit case. The allocation-free exact baseline measured 1,106.0 and
108.7 ns/candidate respectively. An earlier cached folded-scalar preparation
experiment, which would create the contiguous preprocessing seam needed by a
SIMD fold, made dense long matches 15–27% slower from additional memory traffic
and remains removed. No unmeasured vector path or unsafe list reinterpretation
is included. SIMD should be revisited only with a benchmarked structure-of-
arrays `SearchIndex` that processes several similarly sized candidates across
lanes; the exact finalist DP and position tracing should remain scalar.
