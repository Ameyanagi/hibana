# Architecture

Hibana owns Fuzzy pattern preparation, scoring, match positions, ranking schemes, and top-K selection.

## Dependency boundary

Allowed ecosystem dependencies: Moji for shared text views and mappings once required; no CJK-specific dependency.
Expected downstream consumers: Yuragi and other search, command-palette, launcher, and filtering applications.

Dependencies point from applications and higher-level packages toward smaller
foundations. This repository must never import a downstream consumer. New
dependencies require a documented need and must not force unrelated users to
install an application, renderer, language layer, or scientific stack.

## Layers

Planned implementation areas: matcher, pattern, candidate, score, result, positions, case policy, schemes, scalar algorithms, later SIMD kernels, and top-K.

The package root exports only the small documented public surface. Algorithms,
generated tables, platform details, and backend implementations remain in
their owning modules. Generic Mojo-native buffers, spans, strings, and
collections are preferred over an ecosystem-specific universal container.

`Pattern` has one canonical prepared scalar sequence; no cached source string
can diverge from it. `Matcher` snapshots that value at construction. Mojo 1.0
struct fields are externally mutable even when underscore-prefixed, so public
documentation treats these types as mutable value snapshots and does not claim
post-mutation invariants. Underscore storage remains outside the stable API.

## Data flow

Input validation occurs at the public boundary. Internal layers operate on
explicit typed values, produce deterministic outputs for deterministic inputs,
and report invalid state rather than silently replacing it with a default.
I/O, clocks, randomness, terminal queries, filesystem access, and accelerator
selection stay at explicit effect or backend boundaries.

The correctness-first scalar algorithm is a bounded, fallible reference oracle.
It checks state-table, transition, tie-break, flattened-index, and score bounds
before allocating or evaluating. A future production scalar implementation must
preserve its match, score, and tie semantics without inheriting its polynomial
complexity.
