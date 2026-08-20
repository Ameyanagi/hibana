# Changelog

This project follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and uses semantic versioning after the first public release.

## [Unreleased]

### Added

- Initial experimental repository scaffold.
- Prepared `Pattern` and reusable `Matcher` values.
- Deterministic exact-scalar matching with scores and candidate positions.
- Reference tests, a basic public-API example, and an issue-sized v0.1 plan.
- Checked reference-algorithm resource limits and explicit mutable-value
  semantics for prepared patterns, matchers, and results.
- An independent brute-force subset oracle covering 945 exhaustive
  small-alphabet pattern/candidate pairs.
