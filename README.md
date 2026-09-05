# Hibana

High-performance fuzzy matching for Mojo.

> **Experimental — API may change before v1.0.**

## Install

In a Pixi project, add the Hibana channel to the `channels` list in `pixi.toml`:

```toml
[workspace]
channels = [
    "https://ameyanagi.github.io/mojo-channel",
    "https://conda.modular.com/max",
    "conda-forge",
]
```

Keep this order: the ecosystem package channel has highest priority, Modular's
`max` channel supplies the Mojo compiler, and conda-forge supplies shared tools.

Then add Hibana:

```sh
pixi add mojo-hibana
```

`mojo-hibana` is the consumer package spelling on the hosted channel. Hibana is
still experimental; a source checkout is the fallback that always works today:

```sh
git clone https://github.com/Ameyanagi/hibana.git
cd hibana
pixi install --locked
pixi run mojo run -I src your_file.mojo
```

From another checkout, point Mojo at Hibana's source directory with
`mojo run -I /path/to/hibana/src your_file.mojo` (or the equivalent `mojo`
subcommand for your program).

## Quickstart

String queries use whitespace-AND matching by default: Hibana splits a query on
ASCII space, tab, LF, and CR, fuzzily matches every word somewhere in the same
candidate, sums the word scores, and merges their positions. Construct a
single prepared pattern, such as `Matcher(Pattern("a b"))`, when whitespace
must be matched literally.

```mojo
from hibana import Matcher, Scheme
from std.collections import List


def main() raises:
    var paths: List[String] = [
        "src/hibana/matcher.mojo",
        "src/hibana/scoring.mojo",
        "tests/test_basic.mojo",
        "README.md",
    ]
    var matcher = Matcher("hibana mojo", scheme=Scheme.PATH)
    var ranked = matcher.rank(paths)
    for item in ranked:
        print(item.score, item.positions, paths[item.index])
```

`rank(paths)` returns every match in score order and does not raise. Pass
`k=5`, for example, to use bounded top-K storage and retain only the best five.

## Rank and highlight file paths

Use `Scheme.PATH` to rank file paths and mark the matched Unicode scalar
positions:

```mojo
from hibana import Matcher, Scheme
from std.collections import List


def _position_markers(text: StringSlice, positions: List[Int]) -> String:
    var markers = String()
    var position_cursor = 0
    var scalar_index = 0
    for _ in text.codepoints():
        if (
            position_cursor < len(positions)
            and positions[position_cursor] == scalar_index
        ):
            markers += "^"
            position_cursor += 1
        else:
            markers += " "
        scalar_index += 1
    return markers^


def main() raises:
    var paths: List[String] = [
        "src/hibana/matcher.mojo",
        "src/hibana/pattern.mojo",
        "tests/test_basic.mojo",
        "README.md",
        "examples/rank_paths.mojo",
    ]
    var ranked = Matcher("mojo", scheme=Scheme.PATH).rank(paths, k=5)
    for item in ranked:
        print(paths[item.index], " score=", item.score)
        print(_position_markers(paths[item.index], item.positions))
```

## API contract

The Mojo import is `hibana`. Source lives under `src/hibana/`, whose
`__init__.mojo` defines the package boundary.

`MatchResult` reports `matched`, a deterministic integer `score`, and
zero-based Unicode scalar `positions`. A string query is split into fuzzy words
on ASCII space, tab, LF, and CR; every word must match, each word's score is
added, and all selected positions are merged in ascending order without
duplicates. Smart
case is decided independently for each word: a word containing an ASCII
uppercase letter is exact, while other words ignore ASCII letter case.
Non-ASCII scalars always compare exactly, and
`Matcher("kmr", case_mode=CaseMode.EXACT)` restores exact-case matching. Use
`Matcher(Pattern("a b"))` as the single-atom escape hatch for a literal space.
`Matcher.match` is exact and deterministic; a non-match is reported with
`matched == false`. Exact computation raises for unrepresentable DP sizes or a
configured workspace budget that is too small. For total atom length `P` and
candidate length `C`, the production path uses `O(P*C)` time, with one atom's dynamic-programming storage
live at a time. The default budget permits addressable DP storage; callers can
choose a smaller explicit `WorkspaceBudget(max_cells=...)` for external input.
The bounded exhaustive dynamic program survives only as an internal test oracle
and is not used by the production path.

`Matcher.match_scalars` accepts caller-prepared Unicode scalars and returns
positions into that span without copying it. `Matcher.rank(candidates)` is an
all-matches operation; `Matcher.rank(candidates, k=K)` uses bounded
`O(min(K, candidate_count))` ranking storage in addition to exact DP scratch.
Both return matches by score descending, then input index ascending, and accept `List[String]` directly. `TopK` exposes the bounded
streaming policy when candidates do not already live in a single span.
See [workspace budgets](docs/workspace-budget.md) for configuration, errors,
parallel peak-memory accounting, and the migration to raising exact methods.

`Scheme.DEFAULT` rewards whitespace, common delimiters, word starts,
camel-case, and number transitions. `Scheme.PATH` treats `/` and `\` as the
strongest delimiters. Scores retain the 100-point match, 25-point adjacency,
and one-point gap terms, and add fixed context and exact-case bonuses. See the
[published scoring table](docs/scoring.md) for every constant, the closed-form
formula, and the ranking-only exact-case rule.

The exported structs are mutable Mojo value types. Matcher construction
snapshots its prepared atoms; caller mutation of a returned result changes that
result value and is not revalidated by Hibana.

## Scope

Hibana owns reusable deterministic fuzzy matching and ranking, with no
language, filesystem, or user-interface policy.

The first implementation milestone is intentionally narrow: implement a
correctness-first scalar matcher with stable scores, matched positions, case
policy, path-aware scoring, and bounded top-K selection. The project is
independently installable and does not require any application from the wider
ecosystem.

## Development

Install [Pixi](https://pixi.sh/), then run:

```sh
pixi install --locked
pixi run check
pixi run example
pixi run example-rank
```

The exact stable Mojo compiler and all development dependencies are captured in
`pixi.lock`. Runtime and library code is Mojo-first and pure Mojo wherever
practical. Build-time data generation may use another language when justified,
but generated outputs must be deterministic, checksum-pinned, licensed, and
documented.

## Package

The Mojo import is `hibana`. The Conda distribution is
`mojo-hibana`. Source lives under `src/hibana/`, whose
`__init__.mojo` defines the package boundary.

The public API ranks caller-owned candidates without buffering every match:

```mojo
from hibana import CaseMode, Matcher, Scheme
from std.collections import List


def main() raises:
    var paths: List[String] = [
        "src/hibana/matcher.mojo", "src/hibana/scoring.mojo",
        "tests/test_basic.mojo", "README.md",
    ]
    var matcher = Matcher("hm", scheme=Scheme.PATH)  # Smart case is the default.
    var ranked = matcher.rank(paths, k=5)
    for item in ranked:
        print(item.score, item.positions, paths[item.index])
    _ = Matcher("HM", case_mode=CaseMode.EXACT, scheme=Scheme.PATH)  # Escape hatch.
```

`MatchResult` reports `matched`, a deterministic integer `score`, and
zero-based Unicode scalar `positions`. Matching defaults to ASCII smart-case:
queries containing an ASCII uppercase letter are exact, while other queries
ignore ASCII letter case. Non-ASCII scalars always compare exactly, and
`Matcher("kmr", case_mode=CaseMode.EXACT)` restores exact-case matching.
`Matcher.match` is exact and deterministic; a non-match is reported with
`matched == false`. Exact computation raises for unrepresentable DP sizes or a
configured workspace budget that is too small. For pattern length `P` and
candidate length `C`, the production path uses `O(P*C)` time and memory.
The default budget permits addressable DP storage; set an explicit
`WorkspaceBudget(max_cells=...)` for a smaller application limit. The bounded
exhaustive dynamic program survives only as an internal test oracle and is not
used by the production path.

`Matcher.match_scalars` accepts caller-prepared Unicode scalars and returns
positions into that span without copying it. `Matcher.rank` uses bounded
`O(K)` storage and returns matches by score descending, then input index
ascending. `TopK` exposes the same streaming policy when candidates do not
already live in a single span.

Interactive search loops that reuse the same candidates across changing
queries can opt into the advanced API without enlarging the package root:

```mojo
from hibana import Pattern, Scheme
from hibana.prepared import MatchWorkspace, PreparedCandidate


def main() raises:
    var candidate = PreparedCandidate(
        "src/hibana/matcher.mojo", scheme=Scheme.PATH
    )
    var workspace = MatchWorkspace()
    var pattern = Pattern("hm")
    var score = workspace.score(pattern, candidate)
    if score.matched:
        var positions = List[Int]()
        _ = workspace.match_into(pattern, candidate, positions)
        print(score.score, positions)
```

`PreparedCandidate` owns decoded Unicode scalars and boundary bonuses for one
scheme. `MatchWorkspace` reuses its largest dynamic-programming allocation.
`score` returns only exact match state and score, without allocating a position
list. `match_into` reconstructs the same winning positions into caller-owned
reusable storage. The convenience `match` retains the original owned-result
behavior. A workspace is mutable and not thread-safe, so use one per matching
loop or thread. Run `pixi run bench` for the scalar/prepared comparison matrix.

Indexes large enough for per-candidate allocation overhead to matter can use
`PreparedCorpus`, which stores decoded scalars and bonuses in contiguous arenas.
It supports indexed exact scoring plus `hybrid_rank_corpus` and
`rank_corpus_exact` without retaining source strings. See the
[prepared-corpus API and profile evidence](docs/prepared-corpus.md).

Large prepared indexes can additionally use the opt-in `hibana.fast` and
`hibana.hybrid` modules. Hybrid ranking fast-scores the full corpus, exactly
reranks a bounded shortlist, and reconstructs positions only for final rows.
Its total match count and finalist scores/positions are exact, while shortlist
selection is approximate. See [fast shortlist scoring](docs/fast-scoring.md)
and the [hybrid ranking contract](docs/hybrid-ranking.md).

Callers that require exact corpus ranking can opt into
`hibana.parallel.rank_prepared_exact`. It splits independent candidates into
coarse deterministic shards, score-only ranks in each worker, and reconstructs
positions only for the final rows. The API remains synchronous and has a
serial fallback; see the [parallel ranking contract](docs/parallel-ranking.md)
for Mojo 1.0 task-runtime constraints.

`Scheme.DEFAULT` rewards whitespace, common delimiters, word starts,
camel-case, and number transitions. `Scheme.PATH` treats `/` and `\` as the
strongest delimiters. Scores retain the 100-point match, 25-point adjacency,
and one-point gap terms, and add fixed context and exact-case bonuses. See the
[published scoring table](docs/scoring.md) for every constant, the closed-form
formula, and the ranking-only exact-case rule.

The exported structs are mutable Mojo value types. Matcher construction
snapshots its canonical prepared pattern; caller mutation of a returned result
changes that result value and is not revalidated by Hibana.

## Repository map

- `src/hibana/`: library or application source
- `tests/`: TestSuite unit, reference-value, and invariant tests
- `examples/`: small compilable usage programs
- `benchmarks/`: reproducible methodology and executable benchmark programs
- `docs/`: architecture, design, compatibility, roadmap, and release policy
- `conda.recipe/`: local Rattler build recipe

See [the architecture](docs/architecture.md), [design principles](docs/design.md),
[scoring contract](docs/scoring.md), and
[v0.1 execution plan](docs/v0.1-plan.md) before proposing a new dependency or
feature.

## License

Licensed under either Apache-2.0 or MIT, at your option.
