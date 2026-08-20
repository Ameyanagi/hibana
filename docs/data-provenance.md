# Data provenance

No generated lookup data is currently committed.

`tests/test_scalar_oracle.mojo` deterministically enumerates its complete
mixed-case corpus at test runtime: every `{a,b,A}` pattern through length 3 and
candidate through length 5. The test asserts all 14,560 pairs execute. A second
2,000-case fixed-seed corpus draws from `{a,b,A,B,_,/,space}` and runs under
both `Scheme.DEFAULT` and `Scheme.PATH`. Its oracle generates fixed-size
candidate combinations in position-vector lexicographic order, retains the
first equal-scoring path, and derives bonuses and the closed-form score
independently of both dynamic programs. The exact-case bonus is applied only
after selection. It uses no external dataset, nondeterministic random source,
or generated committed artifact.

Every future generated artifact must record:

- upstream project and canonical URL;
- upstream version and retrieval date;
- exact file checksums and licenses;
- generator source and command;
- deterministic output checks;
- review notes for semantic or licensing changes.

Generation tools are development dependencies. Consumers install the generated
Mojo data and do not require Python, Rust, C, or another runtime.
