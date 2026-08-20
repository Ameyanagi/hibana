# Data provenance

No generated lookup data is currently committed.

`tests/test_scalar_oracle.mojo` deterministically enumerates its complete
two-symbol corpus at test runtime: every `{a,b}` pattern through length 3 and
candidate through length 5. It uses no external dataset, random source, or
generated committed artifact.

Every future generated artifact must record:

- upstream project and canonical URL;
- upstream version and retrieval date;
- exact file checksums and licenses;
- generator source and command;
- deterministic output checks;
- review notes for semantic or licensing changes.

Generation tools are development dependencies. Consumers install the generated
Mojo data and do not require Python, Rust, C, or another runtime.
