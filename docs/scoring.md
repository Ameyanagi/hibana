# Scoring

Hibana assigns a deterministic integer score to the selected Unicode-scalar
subsequence. Higher scores rank first. The constants in this document are part
of the scoring contract and are pinned by `tests/test_score_conformance.mojo`.

## Base constants

| Component | Constant | Value |
| --- | --- | ---: |
| Each matched scalar | Base match | 100 |
| Each consecutive matched pair | Adjacency | +25 |
| Each scalar before the first match | Leading gap | -1 |
| Each unmatched scalar between selected positions | Internal gap | -1 |
| First pattern scalar's context bonus | First-character multiplier | ×2 total |
| Raw case equals the pattern at every selected position | Exact case | +45 once |

The first-character multiplier means the first selected position contributes
its context bonus twice: once as an ordinary matched position and once more as
the multiplier extra.

The exact-case bonus is ranking-only. It is added once after positions have
been selected, so it never changes the position vector within one candidate.
It is eligible only while ASCII folding is active: `CaseMode.IGNORE_ASCII`, or
`CaseMode.SMART_ASCII` with an all-lowercase query. Every selected raw candidate
scalar must equal the corresponding raw pattern scalar. It is never awarded
under `CaseMode.EXACT` or when smart-case degrades to exact matching. An empty
pattern scores zero and receives no bonuses.

## Multi-word queries

`Matcher` string queries split on ASCII space, tab, LF, and CR into
independently prepared atoms. Every atom must match. Each atom is scored from
the same table and the final score is their sum; in particular, the exact-case
ranking bonus is tested and applied independently per atom. Selected positions
are merged, sorted, and deduplicated after scoring.

## Character classes

Classes use an ASCII-only policy:

| Class | Scalars |
| --- | --- |
| `WHITESPACE` | space, `\t`, `\n`, `\r`, `\v`, `\f` |
| `DELIMITER`, `Scheme.DEFAULT` | `/`, `,`, `:`, `;`, `|` |
| `DELIMITER`, `Scheme.PATH` | `/`, `\` |
| `DIGIT` | `0`–`9` |
| `UPPER` | `A`–`Z` |
| `LOWER` | `a`–`z` |
| `WORD_OTHER` | every Unicode scalar greater than or equal to 128 |
| `NON_WORD` | every remaining ASCII scalar |

`WORD_OTHER` is word-like but never forms a camel-case or digit transition.
A character absent from the selected scheme's delimiter set is classified by
the remaining rules, normally as `NON_WORD`.

## Context-bonus matrix

The candidate start behaves as though the previous class were `WHITESPACE`.
For a matched word class, rules are checked from the top of this table and the
first match wins.

| Previous class | Matched `LOWER` | Matched `UPPER` | Matched `DIGIT` | Matched `WORD_OTHER` | Matched non-word class |
| --- | ---: | ---: | ---: | ---: | ---: |
| `WHITESPACE` | 60 | 60 | 60 | 60 | 50 |
| `DELIMITER`, `DEFAULT` | 55 | 55 | 55 | 55 | 50 |
| `DELIMITER`, `PATH` | 60 | 60 | 60 | 60 | 50 |
| `NON_WORD` | 50 | 50 | 50 | 50 | 50 |
| `LOWER` | 0 | 40 | 40 | 0 | 50 |
| `UPPER` | 0 | 0 | 40 | 0 | 50 |
| `DIGIT` | 0 | 0 | 0 | 0 | 50 |
| `WORD_OTHER` | 0 | 0 | 40 | 0 | 50 |

The named constants are:

| Bonus | Value |
| --- | ---: |
| `BONUS_BOUNDARY_WHITE` | 60 |
| `BONUS_BOUNDARY_DELIMITER`, `DEFAULT` | 55 |
| `BONUS_BOUNDARY_DELIMITER`, `PATH` | 60 |
| `BONUS_BOUNDARY` | 50 |
| `BONUS_CAMEL` | 40 |
| `BONUS_NON_WORD` | 50 |
| `BONUS_FIRST_CHAR_MULTIPLIER` | 2 |
| `BONUS_EXACT_CASE` | 45 |

When the matched scalar itself is `NON_WORD`, `DELIMITER`, or `WHITESPACE`, its
bonus is always `BONUS_NON_WORD` (50), regardless of the previous class or
scheme.

## Closed-form score

For a non-empty selected position vector `p`, let `bonus[j]` be the precomputed
context bonus at candidate scalar index `j`. Then:

```text
total = sum_i (100 + bonus[p_i])
      + bonus[p_0]
      + 25 * adjacent_pairs
      - p_0
      - internal_gap_scalars
      + (45 if the exact-case rule holds else 0)
```

Position selection maximizes every term except the final exact-case term, then
chooses the lexicographically earliest position vector on a tie. The exact-case
term is added only to the selected result.

A non-match has `matched == false`, score zero, and no positions. An empty
pattern is a successful match with the same score and empty positions; callers
must inspect `matched` to distinguish them. All returned positions are Unicode
scalar indices into the original candidate, never UTF-8 byte offsets.
