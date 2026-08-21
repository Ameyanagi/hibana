# Hibana

High-performance fuzzy matching for Mojo.

> **Experimental — API not yet released.**

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
    var matcher = Matcher("hm", scheme=Scheme.PATH)
    var ranked = matcher.rank(paths, k=5)
    for item in ranked:
        print(item.score, item.positions, paths[item.index])
```

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
zero-based Unicode scalar `positions`. Matching defaults to ASCII smart-case:
queries containing an ASCII uppercase letter are exact, while other queries
ignore ASCII letter case. Non-ASCII scalars always compare exactly, and
`Matcher("kmr", case_mode=CaseMode.EXACT)` restores exact-case matching.
`Matcher.match` is total and deterministic; a non-match is reported with
`matched == false`. For pattern length `P` and candidate length `C`, the
production path uses `O(P*C)` time and memory with no artificial resource
limits. The bounded exhaustive dynamic program survives only as an internal
test oracle and is not used by the production path.

`Matcher.match_scalars` accepts caller-prepared Unicode scalars and returns
positions into that span without copying it. `Matcher.rank` uses bounded
`O(K)` storage and returns matches by score descending, then input index
ascending. `TopK` exposes the same streaming policy when candidates do not
already live in a single span.

`Scheme.DEFAULT` rewards whitespace, common delimiters, word starts,
camel-case, and number transitions. `Scheme.PATH` treats `/` and `\` as the
strongest delimiters. Scores retain the 100-point match, 25-point adjacency,
and one-point gap terms, and add fixed context and exact-case bonuses. See the
[published scoring table](docs/scoring.md) for every constant, the closed-form
formula, and the ranking-only exact-case rule.

The exported structs are mutable Mojo value types. Matcher construction
snapshots its canonical prepared pattern; caller mutation of a returned result
changes that result value and is not revalidated by Hibana.

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

## Repository map

- `src/hibana/`: library or application source
- `tests/`: TestSuite unit, reference-value, and invariant tests
- `examples/`: small compilable usage programs
- `benchmarks/`: reproducible methodology and later benchmark programs
- `docs/`: architecture, design, compatibility, roadmap, and release policy
- `conda.recipe/`: local Rattler build recipe

See [the architecture](docs/architecture.md), [design principles](docs/design.md),
[scoring contract](docs/scoring.md), and
[v0.1 execution plan](docs/v0.1-plan.md) before proposing a new dependency or
feature.

## License

Licensed under either Apache-2.0 or MIT, at your option.
