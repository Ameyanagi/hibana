# Hibana

> **Experimental — API not yet released.**

High-performance fuzzy matching for Mojo.

## Scope

Hibana owns reusable deterministic fuzzy matching and ranking, with no language, filesystem, or user-interface policy.

The first implementation milestone is intentionally narrow: implement a correctness-first scalar matcher with stable scores, matched positions, case policy, path-aware scoring, and bounded top-K selection.
The project is independently installable and does not require any application
from the wider ecosystem.

## Development

Install [Pixi](https://pixi.sh/), then run:

```sh
pixi install --locked
pixi run check
pixi run example
```

The exact stable Mojo compiler and all development dependencies are captured in
`pixi.lock`. Runtime and library code is Mojo-first and pure Mojo wherever
practical. Build-time data generation may use another language when justified,
but generated outputs must be deterministic, checksum-pinned, licensed, and
documented.

## Package

The Mojo import is `hibana`. The eventual Conda distribution is
`mojo-hibana`. Source lives under `src/hibana/`, whose
`__init__.mojo` defines the package boundary.

The first correctness-first scalar slice is available for development:

```mojo
from hibana import Matcher

var result = Matcher("kmr").match("kamera")
```

`MatchResult` reports `matched`, a deterministic integer `score`, and
zero-based Unicode scalar `positions`. The current slice is exact and
case-sensitive; it is experimental and not yet a stable release. Matching is
fallible because the polynomial reference oracle rejects workloads beyond its
documented state, transition, tie-break, and score bounds rather than risking
overflow or unbounded allocation. See the v0.1 plan for exact limits.

The exported structs are mutable Mojo value types. Matcher construction
snapshots its canonical prepared pattern; caller mutation of a returned result
changes that result value and is not revalidated by Hibana.

## Repository map

- `src/hibana/`: library or application source
- `tests/`: TestSuite unit, reference-value, and invariant tests
- `examples/`: small compilable usage programs
- `benchmarks/`: reproducible methodology and later benchmark programs
- `docs/`: architecture, design, compatibility, roadmap, and release policy
- `conda.recipe/`: local Rattler build recipe

See [the architecture](docs/architecture.md), [design principles](docs/design.md),
and [v0.1 execution plan](docs/v0.1-plan.md) before proposing a new dependency
or feature.

## License

Licensed under either Apache-2.0 or MIT, at your option.
