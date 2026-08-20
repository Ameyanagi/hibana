# Reference architecture

This document records the primary-source research behind Hibana's production
architecture. It is a design input, not a compatibility claim: Hibana keeps its
own scoring and tie contracts, and no reference source is copied.

## Reviewed primary sources

The shallow clones live outside the Hibana repository under
`/Users/ryuichi/dev/reference-libraries/hibana/`. The recorded commit, rather
than a moving branch name, defines the reviewed source.

| Project | Reviewed commit | License | Relevant public surface |
| --- | --- | --- | --- |
| [nucleo](https://github.com/helix-editor/nucleo/tree/8c16d47cdfa9607d3e44df5f81c635c6f43c65ee) | `8c16d47cdfa9607d3e44df5f81c635c6f43c65ee` | MPL-2.0 (`LICENSE`, `matcher/LICENSE`, and `matcher/Cargo.toml`) | `nucleo_matcher::Matcher`, `Config`, `Utf32Str`, `pattern::Atom`, and `pattern::Pattern` |
| [fzf](https://github.com/junegunn/fzf/tree/15f64c492a08f0840b81540c7d1de35737448086) | `15f64c492a08f0840b81540c7d1de35737448086` | MIT (`LICENSE` and `src/LICENSE`) | `algo.Algo`, `FuzzyMatchV1`, `FuzzyMatchV2`, `algo.Result`, `Pattern`, and reusable `util.Slab` |
| [fzy](https://github.com/jhawthorn/fzy/tree/34b88869d022e861da4846c4463aea3ddfb3ff30) | `34b88869d022e861da4846c4463aea3ddfb3ff30` | MIT (`LICENSE`) | `has_match`, `match`, `match_positions`, `score_t`, and `MATCH_MAX_LEN` |

The clones are research evidence only. They are not build inputs, vendored
dependencies, benchmark datasets, or permission to reproduce implementation
text. In particular, nucleo's MPL-2.0 source is used only to understand public
architecture and algorithmic ideas.

## What the references actually do

### API and lifetime comparison

| Concern | nucleo | fzf | fzy | Hibana decision |
| --- | --- | --- | --- | --- |
| Query preparation | `Atom`/`Pattern` own a prepared `Utf32String`; parsing and policy are applied once. | `BuildPattern` lowercases/normalizes runes, parses application query syntax, and caches patterns. The low-level algorithm assumes an already prepared rune slice. | Takes a NUL-terminated needle on every call and lowercases into fixed scratch. | `Pattern` owns one canonical Unicode-scalar sequence plus explicit policy. No application query grammar. |
| Matcher lifetime | `Matcher` owns configuration and roughly 135 KiB of reusable scratch, so callers are told to reuse it. | Each low-level call accepts an optional reusable `Slab`; the application matcher owns one slab per worker. | No reusable matcher object; score-only uses stack arrays and positions allocate matrices per call. | A pattern-bound `Matcher` remains the ergonomic façade and owns private reusable workspace when production code needs it. One matcher is used by one task at a time. |
| Score and positions | Separate `fuzzy_match` and `fuzzy_indices`; indices are normally computed only for rendered finalists. | `withPos` controls optional backtracking; `Result` always contains range and score. | Separate `match` and `match_positions`. | Keep public `match` correct and simple. Add an internal score-only lane before top-K; expose it only if downstream use proves value. |
| Result meaning | `Option<u16>`/`Option<u32>` distinguishes no match; index vectors are caller-owned and not cleared. | Negative start/end denotes no match; positions are optional and returned in a separate pointer. | `-INFINITY` represents no score and also oversized input; exact match is `INFINITY`. | Keep explicit `matched`, checked integer score, and owned scalar positions. Resource rejection raises and is never a non-match. |
| Text unit | ASCII bytes or a UTF-32-like grapheme representation. | ASCII bytes or Unicode code points/runes. | Bytes with C-library case conversion. | Unicode scalar values in v0.1. Positions are relative to exactly the candidate view supplied to Hibana; coordinate conversion and source projection remain downstream. |

Primary evidence:

- nucleo documents matcher scratch, reuse, score-only versus indices, caller
  preparation, and its `2^32-1` limit in
  [`matcher/src/lib.rs`](https://github.com/helix-editor/nucleo/blob/8c16d47cdfa9607d3e44df5f81c635c6f43c65ee/matcher/src/lib.rs#L107-L225).
  `Atom` owns its prepared needle and dispatches score/indices through a mutable
  matcher in
  [`matcher/src/pattern.rs`](https://github.com/helix-editor/nucleo/blob/8c16d47cdfa9607d3e44df5f81c635c6f43c65ee/matcher/src/pattern.rs#L80-L105)
  and
  [`matcher/src/pattern.rs`](https://github.com/helix-editor/nucleo/blob/8c16d47cdfa9607d3e44df5f81c635c6f43c65ee/matcher/src/pattern.rs#L298-L399).
- fzf states the low-level prepared-pattern preconditions in
  [`src/algo/algo.go`](https://github.com/junegunn/fzf/blob/15f64c492a08f0840b81540c7d1de35737448086/src/algo/algo.go#L319-L322),
  constructs and caches its higher-level pattern in
  [`src/pattern.go`](https://github.com/junegunn/fzf/blob/15f64c492a08f0840b81540c7d1de35737448086/src/pattern.go#L47-L165),
  and exposes reusable integer slabs in
  [`src/util/slab.go`](https://github.com/junegunn/fzf/blob/15f64c492a08f0840b81540c7d1de35737448086/src/util/slab.go#L1-L12).
- fzy's entire library-level matcher surface and fixed length bound are visible
  in
  [`src/match.h`](https://github.com/jhawthorn/fzy/blob/34b88869d022e861da4846c4463aea3ddfb3ff30/src/match.h#L10-L18).

### Algorithms, scoring, and ties

nucleo and fzf use related modified Smith-Waterman scoring: a match is worth
16, gaps have start and extension penalties, boundaries and camel-case
transitions receive bonuses, and the first query character's boundary bonus is
multiplied. fzf documents both the rationale and `O(N*P)` optimal path in
[`src/algo/algo.go`](https://github.com/junegunn/fzf/blob/15f64c492a08f0840b81540c7d1de35737448086/src/algo/algo.go#L8-L77).
Nucleo keeps separate match and gap state and narrows the matrix; its constants
and boundary classes are in
[`matcher/src/score.rs`](https://github.com/helix-editor/nucleo/blob/8c16d47cdfa9607d3e44df5f81c635c6f43c65ee/matcher/src/score.rs#L6-L48).

fzf uses an optimal DP when within its slab/pattern bounds, but falls back to a
greedy V1 matcher when `N*P` exceeds slab capacity or the pattern exceeds 1,000
runes. It also has allocation-free and reduced-allocation paths for one- and
two-byte patterns. See
[`src/algo/algo.go`](https://github.com/junegunn/fzf/blob/15f64c492a08f0840b81540c7d1de35737448086/src/algo/algo.go#L510-L574)
and
[`src/algo/algo.go`](https://github.com/junegunn/fzf/blob/15f64c492a08f0840b81540c7d1de35737448086/src/algo/algo.go#L722-L776).
Nucleo likewise bounds its optimal traceback matrix to 100 KiB and falls back
to greedy matching when the slab cannot represent the problem; the bound and
fallback are in
[`matcher/src/matrix.rs`](https://github.com/helix-editor/nucleo/blob/8c16d47cdfa9607d3e44df5f81c635c6f43c65ee/matcher/src/matrix.rs#L9-L13)
and
[`matcher/src/fuzzy_optimal.rs`](https://github.com/helix-editor/nucleo/blob/8c16d47cdfa9607d3e44df5f81c635c6f43c65ee/matcher/src/fuzzy_optimal.rs#L11-L28).

fzy is an independent two-matrix dynamic program with floating-point gap and
boundary scores. Score-only keeps rolling `D` and `M` rows; positions allocate
the full matrices and backtrack. Equal traceback choices deliberately select
the latest candidate position. See
[`src/match.c`](https://github.com/jhawthorn/fzy/blob/34b88869d022e861da4846c4463aea3ddfb3ff30/src/match.c#L70-L145)
and
[`src/match.c`](https://github.com/jhawthorn/fzy/blob/34b88869d022e861da4846c4463aea3ddfb3ff30/src/match.c#L148-L223).

The references do not share one alignment tie rule. fzy's backtrace selects the
latest eligible candidate position. fzf's forward scan preserves the first
equal-scoring endpoint while reverse mode replaces it, and its traceback has a
separate consecutive-match preference; examples are visible in
[`src/algo/algo.go`](https://github.com/junegunn/fzf/blob/15f64c492a08f0840b81540c7d1de35737448086/src/algo/algo.go#L909-L958).
Nucleo's high-level candidate order is score descending, total matcher-column
length ascending, then insertion index in
[`src/worker.rs`](https://github.com/helix-editor/nucleo/blob/8c16d47cdfa9607d3e44df5f81c635c6f43c65ee/src/worker.rs#L232-L270).

Hibana does not adopt any of those exact scoring or tie rules. Its default v0.1
contract remains:

```text
score = 100 * matched_scalars
      + 25 * adjacent_transitions
      - leading_gap
      - internal_gap_scalars
```

Higher scores win. Equal-scoring alignments choose lexicographically earlier
Unicode-scalar positions. A production kernel, short-pattern specialization,
or SIMD-assisted path must return exactly the reference oracle's match state,
score, and positions. It must not silently change to a greedy alignment at a
resource threshold.

### Ranking and top-K

The reviewed applications sort every match. fzy uses score descending and
original storage order for ties in
[`src/choices.c`](https://github.com/jhawthorn/fzy/blob/34b88869d022e861da4846c4463aea3ddfb3ff30/src/choices.c#L18-L37),
while fzf combines score with configurable length, path, begin, and end keys,
then uses a stable radix sort for larger result sets in
[`src/result.go`](https://github.com/junegunn/fzf/blob/15f64c492a08f0840b81540c7d1de35737448086/src/result.go#L54-L117)
and
[`src/result.go`](https://github.com/junegunn/fzf/blob/15f64c492a08f0840b81540c7d1de35737448086/src/result.go#L350-L435).
Nucleo's low-level `match_list` also collects and sorts all matches in
[`matcher/src/pattern.rs`](https://github.com/helix-editor/nucleo/blob/8c16d47cdfa9607d3e44df5f81c635c6f43c65ee/matcher/src/pattern.rs#L373-L399).
Its high-level worker also retains and sorts the full match vector; none of the
reviewed libraries provides Hibana's required bounded top-K operation.

Hibana's v0.1 top-K is deliberately different. Candidate identity is only the
zero-based ordinal in the supplied collection:

1. Visit candidates in ascending ordinal order and compute score without
   positions.
2. Keep at most `K` records in a worst-first heap. Lower score is worse; for an
   equal score, the larger ordinal is worse.
3. Recompute full positions only for the retained ordinals.
4. Return retained results ordered by score descending, then input order
   ascending.

This uses `O(K)` ranking state rather than collecting every match. The v0.1 API
borrows an immutable indexable in-memory candidate collection for the duration
of the call. Each ordinal must yield the same scalar sequence in the scoring and
position passes; Hibana invokes no caller callback between them. Results own
their ordinal, score, and positions, so no candidate borrow escapes. A future
streaming API may retain at most K candidate values, and a future application
adapter may carry an opaque caller ID separately from the ordinal, but neither
changes the ordinal tie rule. Both require a downstream ownership study.

## Adopted and rejected ideas

| Idea | Decision | Reason |
| --- | --- | --- |
| Prepare a query once and reuse matcher workspace | Adopt | Nucleo owns prepared needles and reusable matcher scratch; fzf prepares/caches patterns and accepts a reusable slab. Fzy is the useful counterexample that prepares per call. Hibana's match-many API benefits from the nucleo/fzf split. |
| Separate broad score calculation from finalist positions | Adopt internally | nucleo, fzf, and fzy all make positions optional or separate. This is essential for bounded top-K. |
| Cheap ordered-subsequence prefilter and narrowed DP range | Adopt after baseline | The pass can reject a non-match without DP and can find a safe smaller interval for a match. It remains scalar reference-tested and preserves scalar indices; HIB-016 measures rejection and narrowing yield before default dispatch changes. |
| Rolling rows for score-only DP and compact traceback decisions | Adopt | It bounds score-only memory and keeps position cost explicit. Every size calculation remains checked. |
| ASCII short-pattern fast paths | Adopt after baselines | fzf's one/two-character paths demonstrate the opportunity, but conformance and measurement come first. |
| SIMD-assisted dual-byte search | Investigate late | fzf limits SIMD to a narrow prefilter primitive with scalar fallback and exhaustive/fuzz equivalence tests; that is the acceptable boundary. |
| Differential, exhaustive, property, and fuzz-style testing | Adopt | fzf compares fast paths to its general algorithm; fzy runs 100,000-trial position properties; nucleo checks greedy/optimal invariants. Hibana's bounded exhaustive oracle remains authoritative. |
| Silently fall back from optimal to greedy scoring | Reject | It changes scores and positions based on resource size. Hibana raises a resource error instead. Approximate matching would require a separately named future API. |
| Global mutable scoring initialization | Reject | fzf's process-global scheme setup does not fit independently configured Mojo matchers or deterministic parallel callers. |
| Application query grammar, caches, workers, cancellation, or filesystem path handling | Reject | These belong to Yuragi or another application. Hibana accepts text and explicit policy only. |
| Floating scores, infinities, or overloading a resource error as non-match | Reject | Checked integer scores and explicit fallibility keep ordering portable and failures observable. |
| Fixed byte limits and C-library case conversion | Reject | Hibana's unit is a Unicode scalar and its resource contract is checked rather than platform-locale dependent. |
| Keep only the first code point of each grapheme | Reject | Nucleo deliberately uses this compact text model, but Hibana's v0.1 exact-scalar contract must not discard input. Grapheme/source mapping belongs in Moji. |
| Full-sort fallback for top-K | Reject | It violates the bounded-memory contract. |
| Public scalar/SIMD/backend selector | Reject | Backend choice is private and must not fragment semantics. |
| Copying reference source | Reject | Architecture and test ideas are reimplemented independently from public behavior and papers where needed. |

## Target Hibana layers

```text
public root
  Pattern, Matcher, MatchResult
  later: CasePolicy, ScoringScheme, RankedMatch/top_k
                |
                v
facade and ownership
  pattern preparation -> matcher lifetime -> result construction
                |
       +--------+---------+
       |                  |
       v                  v
semantic policy       bounded ranking
  case                 top-K heap
  score transitions    stable final order
  tie comparison       finalist reconstruction
       |
       v
algorithm dispatch (private)
  reference oracle -> production scalar -> optional ASCII/SIMD fast path
       |                       |
       +-----------+-----------+
                   v
text primitives and checked workspace
  Unicode scalar views, subsequence prefilter, checked sizes, reusable buffers
```

Dependency direction is downward only:

- `topk` may call the matcher score and position lanes; matching never imports
  ranking.
- production scalar and SIMD paths depend on one semantic scoring/tie module;
  they do not define their own policies.
- SIMD may accelerate prefilter/equality/classification primitives, but the
  scalar implementation remains available on every target.
- Hibana owns no transformed-to-source mapping. A later Moji dependency may
  supply only a generic scalar text view after HIB-013 evidence. Hibana never
  depends on Yomi, Yuragi, a terminal, or filesystem traversal.
- benchmark and oracle helpers remain outside the package root.

### Downstream coordinate gate

Hibana's coordinate boundary ends at zero-based Unicode-scalar positions in
exactly the candidate view it matched. Hibana does not return byte offsets,
display columns, grapheme indices, or transformed-to-source mappings.

Before HIB-020 can claim Yuragi integration, the packaged ecosystem must prove
this pipeline without a Yuragi-specific scoring adapter:

1. Yuragi supplies direct or Yomi-produced search text as a StringSlice or an
   approved Moji scalar view.
2. Hibana returns scalar positions relative to that exact view.
3. Moji converts each scalar position to its non-empty half-open UTF-8 byte
   range in the same view. Separate positions remain separate ranges.
4. For phonetic text, Yomi batch-projects those output-byte ranges to ordered
   exact original-source ranges without bridging a gap.
5. Yuragi merges direct and phonetic ranked results and owns highlight policy.

The gate requires ASCII, multibyte pass-through, expansion, contraction, and
discontiguous-highlight fixtures. It does not permit Hibana to import Yomi or
to understand a language.

A likely source layout is:

```text
src/hibana/
  pattern.mojo              canonical prepared query
  matcher.mojo              pattern-bound façade and workspace owner
  result.mojo               match result values
  case.mojo                 exact/ASCII-insensitive nominal policy
  score.mojo                checked score and tie semantics
  topk.mojo                 bounded ranking
  schemes/
    default.mojo
    path.mojo               text-boundary policy only
  algorithms/
    reference.mojo          current bounded oracle
    prefilter.mojo          ordered-subsequence bounds
    scalar.mojo             production scalar lane
    simd.mojo               optional private kernels and scalar fallback
```

File names are targets, not permission to expose internal modules from
`__init__.mojo`.

## Pattern preparation and matcher lifetime

`Pattern` remains an owned mutable Mojo value whose single canonical state is
the prepared scalar sequence and explicit preparation policy. Exact mode stores
the input scalar unchanged. ASCII-insensitive mode maps only `A` through `Z`
and preserves a one-to-one scalar index relation. Full Unicode folding and
normalization are excluded from Hibana. A downstream layer may supply an
already transformed scalar view while retaining its mapping outside Hibana.

Do not add both a source string and prepared scalars to `Pattern`: reachable
Mojo fields could diverge. An ASCII acceleration must either be derivable from
the canonical sequence at use time or use a total single-representation value,
not two independently mutable caches.

`Matcher(pattern)` snapshots the pattern, preserving the current mutation
semantics. The production matcher may additionally own reusable score rows,
prefilter buffers, and traceback storage. Workspace grows only after checked
limits and may retain a documented high-water capacity. A matcher is not
implicitly synchronized; callers use one matcher per concurrent task. Hibana
does not spawn workers.

The current workspace-free experimental `Matcher` is `Copyable`; that is not
the production lifetime contract. Before reusable workspace lands, `Matcher`
becomes a move-only mutable owner. Moving transfers its pattern, policy, and
workspace; copying or aliasing scratch is unsupported. Constructing another
matcher from the same copyable `Pattern` creates fresh empty workspace. Matching
methods may mutate private workspace without changing semantic configuration,
and destruction releases the retained high-water allocation. A future named
clone operation would also start with empty workspace and requires measured user
need; ordinary copy syntax must not duplicate a warmed matcher.

Candidate preparation stays measurement-gated. Repeatedly converting a large
candidate corpus may justify a `PreparedCandidate` or Moji text view, as nucleo
presegments inputs, but HIB-013 must first quantify its memory and ownership
cost. No candidate type enters the root API before that evidence.

## Minimal Mojo API sketch

The existing source-compatible path remains primary:

```mojo
from hibana import Matcher, Pattern

var prepared = Pattern("kmr")
var matcher = Matcher(prepared)
var result = matcher.match("kamera")
```

The intended v0.1 additions are conceptually:

```mojo
var pattern = Pattern("kmr", CasePolicy.ascii_insensitive())
var matcher = Matcher(pattern, ScoringScheme.default())

# Public correctness path: always returns owned positions on a match.
var result = matcher.match("Kamera")

# Bounded collection path: identity is the zero-based candidate ordinal.
var ranked = matcher.top_k(candidates, limit=50)
```

`top_k`'s exact collection signature waits for a compiled Mojo ownership
prototype. Its semantics do not: it borrows an immutable indexed Mojo-native
collection/view and returns owned `RankedMatch` values containing
`candidate_index`, `score`, and positions. `candidate_index` is the collection
ordinal, not an opaque caller ID. The operation rejects a non-positive or
unrepresentable bound and never introduces a universal Hibana candidate
container. A private score-only operation feeds top-K; making it public requires
an independent user need and an explicit no-position result type rather than
weakening `MatchResult` invariants.

## Resource and error contract

The current reference oracle limits state cells to 1,000,000, predecessor
transitions to 25,000,000, tie steps to 100,000,000, and conservative score
magnitude to 1,000,000,000. Those limits remain stable oracle behavior until a
documented compatibility change.

The production lane must follow these rules:

1. Check pattern/candidate dimensions, every product, flattened index, score
   bound, and requested top-K capacity before allocation or arithmetic.
2. Treat resource rejection as a raised error, never as `matched == false` and
   never as an approximate result.
3. Use `Int` scores until a narrower representation is proven for every scheme;
   do not inherit fzf/nucleo's 16-bit assumptions silently.
4. Score-only production matching targets `O(P*C)` time and `O(C)` workspace.
   Position reconstruction may use checked compact `O(P*C)` decisions initially
   and must publish its separate bound.
5. A subsequence prefilter targets `O(C)` no-match time and returns scalar
   bounds without changing positions.
6. Top-K is all-or-error. A scoring or finalist-reconstruction resource failure
   discards local ranking/output state and raises; it never returns a partial
   list. Each reconstruction size is checked before allocating, and both passes
   observe the same immutable candidate data.
7. Excluding the caller-owned collection and returned value, top-K peak and
   retained auxiliary space is `O(C_scan + P*C_final + K)` for the initial
   production design: `C_scan` is the longest candidate scored during the
   matcher's lifetime and `C_final` is the longest finalist reconstructed.
   These terms are checked matcher high-water buffers plus the `O(K)` heap.
   Returned owned position lists occupy at most `O(K*P)` additional space.
8. Allocation failure from the runtime may still raise, but sizes must not wrap
   or trigger a knowingly unbounded request first.

## Scalar and SIMD separation

The current exhaustive implementation is renamed conceptually as the reference
oracle; it is not incrementally mutated into the optimized kernel. The
production scalar lane is implemented beside it and compared on every bounded
fixture.

Optimization order is:

1. ordered-subsequence prefilter and narrowed candidate interval;
2. score-only `O(P*C)` scalar recurrence with checked rows;
3. position reconstruction preserving lexicographically earliest ties;
4. allocation reuse inside `Matcher`;
5. measured one- and two-scalar ASCII specializations;
6. only then, a private SIMD prefilter primitive with scalar fallback.

fzf's current SIMD boundary is instructive: assembly accelerates finding either
of two bytes while the matching algorithm and fallback stay separate, as
documented in
[`src/algo/SIMD.md`](https://github.com/junegunn/fzf/blob/15f64c492a08f0840b81540c7d1de35737448086/src/algo/SIMD.md#L1-L59).
Nucleo has no explicit public scalar/SIMD backend seam at the reviewed commit;
it specializes ASCII versus Unicode and delegates ASCII search primitives to
`memchr`. Hibana should initially prefer Mojo SIMD rather than assembly or FFI.
Every optimized path requires table, exhaustive, and randomized equivalence
against the production scalar path, which itself remains checked against the
reference oracle. Runtime dispatch and backend names stay private.

## Benchmark and conformance corpus

Generated data must use fixed seeds, documented generation code, checksums, and
licenses that permit redistribution. Do not use the cloned reference trees as
committed datasets.

| Dimension | Required cases |
| --- | --- |
| Candidate family | ASCII identifiers, mixed-case words, slash/backslash paths as text, repeated scalars, combining-scalar strings, emoji, and mixed Unicode scalars |
| Candidate count | 100, 10,000, and 1,000,000 |
| Candidate length | 0, 1, 2, 8, 32, 128, long-but-accepted, and first-rejected boundary |
| Query length | 0, 1, 2, 4, 8, 32, candidate-longer, and resource-boundary cases |
| Selectivity | no match, approximately 1%, 25%, and all match |
| Alignment | contiguous, leading gap, internal gaps, long gaps, repeated equal-score choices, boundary starts, and late high-score match |
| Policy | exact, ASCII-insensitive, default score, and path-boundary score |
| Operation | preparation, reused single match, score-only, positions, top-K for K=1/10/50/K>N, and incremental query extension |
| Backend | oracle, production scalar, each short-pattern specialization, and SIMD-enabled/disabled |

Every performance run records CPU, OS, Mojo/compiler versions and flags,
dataset checksum, warmup, measured iterations, allocation/high-water metrics,
match count, and a score/position checksum. Report median and a dispersion
measure; retain raw machine-readable output. Compare score-only separately from
positions and cold construction separately from matcher reuse.

External tools are useful only as separately identified context because their
semantics differ. If measured, pin the exact commits above, run their library
APIs rather than terminal applications, record their toolchains and policies,
and do not publish an apples-to-apples speed claim. Nucleo's benchmark currently
uses Linux-tree paths with four queries in
[`bench/src/main.rs`](https://github.com/helix-editor/nucleo/blob/8c16d47cdfa9607d3e44df5f81c635c6f43c65ee/bench/src/main.rs#L35-L75).
Fzf's fast paths use exhaustive character-class coverage plus fuzz comparison
against the general algorithm in
[`src/algo/fastpath_equiv_test.go`](https://github.com/junegunn/fzf/blob/15f64c492a08f0840b81540c7d1de35737448086/src/algo/fastpath_equiv_test.go#L3-L11).
Fzy checks 100,000 generated trials for match/score consistency and increasing,
matching positions in
[`test/test_properties.c`](https://github.com/jhawthorn/fzy/blob/34b88869d022e861da4846c4463aea3ddfb3ff30/test/test_properties.c#L84-L159).

## Dependency-ordered issues

Keep the existing HIB identifiers; use this order and gates to avoid coupling
semantic work to optimization:

1. **HIB-007 — case policy.** Add exact and one-to-one ASCII-insensitive
   preparation. Gate on original-scalar position fixtures.
2. **HIB-008 — scoring scheme.** Centralize checked match, adjacency, gap, and
   tie transitions in a nominal value. The oracle consumes this contract first.
3. **HIB-009 — path scheme.** Add text-only boundary classes and bonuses. No
   path objects, filesystem calls, or platform lookup.
4. **HIB-010 — conformance corpus.** Freeze score, position, case, boundary,
   repeated-scalar, and tie tables before another matcher is introduced.
5. **HIB-011/HIB-012 — ranked ordinal and bounded top-K.** Compile the immutable
   indexed-collection ownership prototype, define score descending/ordinal
   ascending, implement a worst-first K heap, and prove stable two-pass data,
   owned results, all-or-error reconstruction, and its separate space bound.
6. **HIB-014 — benchmark harness.** It is already dependency-ready, but land it
   after the policy surface is fixed so the matrix does not immediately churn.
7. **HIB-015 — generated datasets.** Add deterministic 100/10,000/1,000,000
   corpora and checksums; keep large generation optional if repository size
   requires it.
8. **HIB-016 — baseline.** Measure preparation, reuse, score-only prototype,
   positions, top-K, selectivity, prefilter rejection/narrowing yield, and
   allocation high water before production optimization.
9. **HIB-017a — prefilter and bounds.** Add an independently tested scalar
   subsequence prefilter returning the smallest safe DP interval.
10. **HIB-017b — production score lane.** Implement checked `O(P*C)` score-only
    rows and compare every bounded case with the oracle.
11. **HIB-017c — production positions.** Add compact checked traceback and prove
    lexicographically earliest ties against the oracle. Switch private dispatch
    only after benchmarks show the required improvement.
12. **HIB-018a — short ASCII paths.** Add one/two-scalar specializations only
    where baselines show value, with exhaustive equivalence.
13. **HIB-018b — SIMD investigation.** Prototype one private prefilter kernel,
    scalar fallback, architecture matrix, and raw measurements. It may be
    deferred from v0.1.
14. **HIB-013 — candidate preparation decision.** Run only after HIB-016 and a
    Yuragi ownership study. Consider only preparation or a generic Moji scalar
    view, never source mapping; accept an explicit no-change decision.
15. **HIB-019 through HIB-022 — release gates.** Document both score-only and
    positions complexity, prove the packaged Moji scalar-to-byte/Yomi
    projection/Yuragi orchestration pipeline, validate artifacts, then perform
    the release audit.

`HIB-017a/b/c` and `HIB-018a/b` are review-sized subdivisions of the existing
plan items, not new public milestones. No production path is default until the
oracle equivalence, resource, benchmark, package, and downstream gates pass.

## Explicit non-goals

- CJK readings, romanization, phonetic generation, or language detection.
- Terminal UI, filesystem traversal, ignore files, shell history, processes,
  clocks, network access, or internal worker pools.
- Fzf-compatible query syntax or exact ranking compatibility with any reviewed
  project.
- Unicode normalization, full case folding, or ownership of source mappings;
  callers may supply an externally mapped scalar view.
- A universal candidate/array/executor type, persistent index, or database.
- Silent approximate matching, mandatory SIMD, GPU matching, assembly, or FFI
  in v0.1.
- Benchmark superiority claims derived from different scoring semantics or
  application-level timing.
