# Benchmarks

The current dynamic-programming scalar matcher is a correctness oracle, not a
performance claim. HIB-014 through HIB-018 in the v0.1 plan establish the
benchmark and optimization sequence.

The first benchmark matrix will cover:

| Dimension | Cases |
| --- | --- |
| Candidate kind | ASCII words, paths, Unicode scalar strings |
| Candidate count | 100, 10,000, 1,000,000 |
| Query | empty, short, long, match, non-match, incremental extension |
| Operation | pattern preparation, single match, batch match, bounded top-K |
| Distribution | dense matches, sparse matches, repeated scalars, long gaps |

Every run must record CPU, OS, Mojo version, compiler options, dataset
provenance and checksum, warmup, measured iterations, summary statistic, and
exact command. A checksum of scores and positions must prevent dead-code
elimination and detect semantic drift.

Benchmark programs belong in `bench_*.mojo`. Results are development evidence,
not permanent marketing claims.
