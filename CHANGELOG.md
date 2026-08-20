# Changelog

This project follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and uses semantic versioning after the first public release.

## [Unreleased]

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

### Changed

- Matching now defaults to ASCII smart-case instead of exact-case. Pass
  `case_mode=CaseMode.EXACT` to preserve the previous behavior.
- Match scores now include the documented boundary-bonus scheme. Exact-case
  ranking bonuses are applied after position selection and never alter a
  candidate's chosen position vector.
