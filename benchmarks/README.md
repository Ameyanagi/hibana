# Benchmarks

`pixi run bench` executes the optimized scalar/prepared comparison matrix. The
script records CPU, OS, architecture, Mojo version, compiler options, Git
state, warmup count, measured iterations, minimum of five samples, and a
checksum of match state, scores, and positions. The focused corpus benchmarks
below instead use 31 samples and nearest-rank p50/p95 so tail latency is not
hidden by a best-case minimum.

The current executable matrix covers:

| Dimension | Cases |
| --- | --- |
| Candidate kind | ASCII words, paths, Unicode scalar strings |
| Candidate size | 23, 624, 1,248, and 2,496 Unicode scalars |
| Query | short, long, match, non-match, incremental extension |
| Operation | scalar match, prepared owned result, score-only, and caller-owned positions |
| Distribution | short paths, repeated long path segments, sparse non-match |

Three focused index-style benchmarks complement that exact matcher matrix:

- `pixi run bench-fast` compares linear approximate and exact allocation-free
  score scans over 10,000 prepared candidates in all-hit and no-hit cases.
- `pixi run bench-hybrid` measures B=1,000/K=20 hybrid ranking over 10,000 and
  100,000 candidates in owned and arena-backed storage, including finalist
  position reconstruction, and reports p50/p95 over 31 samples after three
  warmups.
- `pixi run bench-parallel` compares serial and runtime-default parallel exact
  ranking over 10,000 and 100,000 candidates in both storage layouts. It
  reports p50/p95 and the corresponding speedups over 31 samples after three
  warmups per mode.
- `bash scripts/profile-corpus.sh MODE` builds a long-running 100,000-candidate
  binary and records a macOS Time Profiler trace plus `/usr/bin/time -l` memory
  counters. Modes are `hybrid`, `arena-hybrid`, `exact`, and `arena-exact`.
  The script also verifies complete result equivalence between the selected
  storage layout and its owned or arena-backed counterpart.

The repository wrappers record CPU, OS, architecture, Mojo version, compiler
options, Git revision and dirty state, deterministic fixture provenance and
source checksum, a current tracked/untracked source-manifest checksum, warmup,
measured iterations, summary statistic, and exact command. Capture stdout (for
example with `tee`) when retaining a result. Clean-revision runs are directly
reproducible; archive the diff beside any dirty-run output because a checksum
can verify but cannot reconstruct local changes. A checksum of scores and
positions must prevent dead-code elimination and detect semantic drift.
Historical numbers without captured metadata are context only, not reproducible
current baselines.

The matrix deliberately compares identical score and tie semantics. The scalar
variant decodes and classifies its candidate and allocates DP storage on every
call. `prepared_owned` performs candidate work once and retains scratch but
allocates the result's owned positions. `prepared_score` traces the exact winner
without storing positions. `prepared_into` reconstructs positions into one
reused caller-owned list. Their checksums verify match state and score; variants
that return positions additionally checksum every position.

A cached folded-scalar candidate array was measured and removed: on the initial
Apple Silicon run it made long dense matches 15–27% slower. The retained design
folds ASCII on demand and uses less candidate memory. SIMD is deferred because
the only contiguous fold-preprocessing seam is amortized and was not a measured
bottleneck; the branch-heavy `O(P*C)` DP remains dominant.

The corpus profiler confirmed this on the broad scan: query-dependent fast
scoring dominates, followed by exact shortlist DP and bounded heap work. An
exact compact-`UInt8` bonus experiment regressed latency because every hot load
needed widening, so the arena retains native `Int` bonuses. Contiguous arenas
still remove two owned list allocations per candidate and reduced measured
100,000-candidate RSS by about 15%. See `docs/prepared-corpus.md` for commands,
measurements, and SIMD reasoning.

Future matrix extensions still include fixed-seed datasets at 100 and
1,000,000 candidates, pattern preparation, Unicode-heavy text,
dense repeated scalars, and long gaps. Benchmark programs belong in
`bench_*.mojo`. Results are development evidence, not permanent marketing
claims.
