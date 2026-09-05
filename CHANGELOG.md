# Changelog

This project follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and uses semantic versioning after the first public release.

## [Unreleased]

### Fixed

- Clamp both `Matcher.rank(..., k)` heap capacities to available candidates;
  empty inputs validate `k` and return without allocating a heap.

### Added

- `hibana.budget.WorkspaceBudget(max_cells=...)` checks DP dimension and byte
  overflow before allocation and bounds retained scratch growth. Matcher,
  prepared workspace, hybrid, and parallel entry points accept this budget.
- Deterministic propagation of parallel workspace errors after joining tasks,
  with worker score buffers freed before final-position reconstruction.

### Changed

- Exact `Matcher.match`, `match_scalars`, `rank`, and prepared `match`, `score`,
  `match_into` now raise for checked resource failures. Forwarding call sites
  must propagate or handle errors; ordinary default-budget results are unchanged.
  See `docs/workspace-budget.md` for limits and per-shard peak memory.

## [0.1.0] - 2026-08-22

### Added

- Initial experimental repository scaffold.
- Prepared `Pattern` and reusable `Matcher` values.
- Explicit `CaseMode.EXACT`, `CaseMode.IGNORE_ASCII`, and
  `CaseMode.SMART_ASCII` matching policies.
- Deterministic scalar matching with scores and candidate positions.
- Reference tests, a basic public-API example, and an issue-sized v0.1 plan.
- Checked reference-algorithm resource limits and explicit mutable-value
  semantics for prepared patterns, matchers, and results.
- An independent lexicographic-combination oracle with a closed-form score that
  asserts all 14,560 exhaustive mixed-case pattern/candidate pairs execute.
- Fixed `Scheme.DEFAULT` and `Scheme.PATH` boundary-bonus policies, including
  word, camel-case, number, delimiter, first-character, and exact-case bonuses.
- Literal score-conformance fixtures that pin every scoring constant and both
  delimiter schemes.
- Caller-prepared scalar matching through `Matcher.match_scalars`, sharing the
  same no-copy scalar core as `Matcher.match` after its single decode pass.
- Bounded `TopK` streaming selection, inspectable `Ranked` values, and
  `Matcher.rank` convenience over caller-owned candidate spans.
- Non-raising no-`k` `Matcher.rank` overloads that return every match, plus
  direct `List[String]` and bare-list-literal ranking ergonomics.
- A deterministic path-ranking example that marks matched scalar positions.
- A README honesty check that extracts and compiles every fenced Mojo program.
- An opt-in `hibana.prepared` path that reuses decoded candidates, boundary
  bonuses, and dynamic-programming workspace storage across incremental queries.
- An allocation-free subsequence prefilter and reproducible `pixi run bench`
  scalar/prepared comparison matrix.
- Exact prepared scoring without owned position-result allocation through
  `MatchWorkspace.score`; retained workspace scratch becomes allocation-free
  after it has grown to the required dynamic-programming size.
- Fixed-seed differential coverage for score-only and output-buffer matching,
  plus benchmark variants isolating owned-result allocation and reconstruction.
- Opt-in linear `fast_score` shortlist scoring with exact membership and no
  position allocation.
- Allocation-bounded hybrid corpus ranking with exact total counts, exact
  finalist scores and positions, deterministic heaps, quality fixtures, and
  10,000/100,000-candidate benchmarks.
- Opt-in synchronous parallel exact ranking with coarse worker-local scoring,
  deterministic source-index merging, serial fallback, and bounded heaps.
- Arena-backed `PreparedCorpus` storage, indexed exact and fast scoring,
  hybrid and parallel exact ranking, differential tests, memory profiling, and
  31-sample p50/p95 benchmarks at 10,000 and 100,000 candidates.

### Changed

- **Breaking:** string-query matching now uses fzf-register whitespace-AND
  semantics. Previously, `Matcher("foo bar")` searched for one fuzzy pattern
  containing a literal space; it now requires both independently prepared
  words to match, sums their scores, and merges their positions. Use
  `Matcher(Pattern("foo bar"))` for the old literal-space meaning.
- **Breaking:** `Matcher.rank(candidates, k)` is now the explicitly bounded,
  raising form, while `Matcher.rank(candidates)` ranks all matches without
  raising. Invalid `k` errors now name `rank` and recommend omitting `k`.
- Matching now defaults to ASCII smart-case instead of exact-case. Pass
  `case_mode=CaseMode.EXACT` to preserve the previous behavior.
- Match scores now include the documented boundary-bonus scheme. Exact-case
  ranking bonuses are applied after position selection and never alter a
  candidate's chosen position vector.
- `MatchResult` and `Ranked` now support field-wise equality and readable
  `Writable` output.
- Validation errors now report the offending arguments and limits with clearer
  recovery guidance.
- The README now follows the consumer-first front-door structure with install,
  copy-compilable quickstart, and real-task path-ranking guidance.

[Unreleased]: https://github.com/Ameyanagi/hibana/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Ameyanagi/hibana/releases/tag/v0.1.0
