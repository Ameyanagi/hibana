"""Allocation-free approximate scoring for broad fuzzy-search scans."""

from .pattern import Pattern
from .prepared import PreparedCandidate, PreparedCorpus
from .scoring import (
    _BONUS_EXACT_CASE,
    _BONUS_FIRST_CHAR_MULTIPLIER,
    _SCORE_ADJACENCY,
    _SCORE_MATCH,
    _candidate_match_scalar,
)


struct FastScore(Copyable, Equatable, ImplicitlyCopyable):
    """The match state and approximate score from ``fast_score``.

    This deliberately omits positions so broad scans cannot accidentally
    allocate one result list per candidate. Run Hibana's exact matcher only
    for the bounded finalist set when positions or optimal ranking are needed.
    A non-match and an empty-pattern match both score zero; inspect ``matched``
    to distinguish them.
    """

    var matched: Bool
    var score: Int

    def __init__(out self, matched: Bool, score: Int):
        self.matched = matched
        self.score = score

    @staticmethod
    def no_match() -> Self:
        """Return the canonical fast non-match."""
        return Self(False, 0)

    def __eq__(self, other: Self) -> Bool:
        return self.matched == other.matched and self.score == other.score


def _fast_score_spans(
    pattern: Pattern,
    scalars: Span[UInt32, _],
    bonuses: Span[Int, _],
) -> FastScore:
    """Shared fast scan over parallel scalar and bonus spans."""
    if pattern.is_empty():
        return FastScore(True, 0)
    if len(pattern) > len(scalars):
        return FastScore.no_match()

    var pattern_index = 0
    var end_position = -1
    for candidate_index in range(len(scalars)):
        if (
            _candidate_match_scalar(scalars[candidate_index], pattern._fold_ascii)
            != pattern._scalars[pattern_index]
        ):
            continue
        pattern_index += 1
        if pattern_index == len(pattern):
            end_position = candidate_index
            break

    if end_position < 0:
        return FastScore.no_match()

    pattern_index = len(pattern) - 1
    var next_position = -1
    var score = 0
    var exact_case = pattern._fold_ascii
    for reverse_offset in range(end_position + 1):
        var candidate_index = end_position - reverse_offset
        if (
            _candidate_match_scalar(scalars[candidate_index], pattern._fold_ascii)
            != pattern._scalars[pattern_index]
        ):
            continue

        if pattern._fold_ascii and (
            scalars[candidate_index] != pattern._raw_scalars[pattern_index]
        ):
            exact_case = False

        if next_position >= 0:
            var gap = next_position - candidate_index - 1
            score += _SCORE_MATCH + bonuses[next_position]
            score += _SCORE_ADJACENCY if gap == 0 else -gap

        next_position = candidate_index
        if pattern_index == 0:
            score += (
                _SCORE_MATCH
                + _BONUS_FIRST_CHAR_MULTIPLIER * bonuses[candidate_index]
                - candidate_index
            )
            if exact_case:
                score += _BONUS_EXACT_CASE
            return FastScore(True, score)
        pattern_index -= 1

    debug_assert(False, "forward subsequence match must admit reverse tightening")
    return FastScore.no_match()


def fast_score(pattern: Pattern, candidate: PreparedCandidate) -> FastScore:
    """Return a deterministic linear-time fuzzy score without allocations.

    The first pass finds the earliest end of any matching subsequence. The
    reverse pass tightens that window and applies the public scoring table to
    the resulting compact alignment. This is ``O(C)`` time and ``O(1)`` extra
    storage, compared with the exact matcher's ``O(P*C)`` dynamic program.

    Match membership is exact: this reports a match if and only if the exact
    matcher does for the same prepared pattern and candidate. Scores are an
    approximation because the compact greedy alignment need not be the
    maximum-scoring alignment. Use them for a broad top-B shortlist, then run
    the exact matcher on that shortlist for final scores and positions.

    The pattern owns ASCII case policy and the candidate owns the boundary
    scheme used by its precomputed bonuses. Positions are intentionally not
    returned. Direct mutation of underscore-prefixed prepared storage is
    outside the stable API; call ``candidate.validate()`` after such mutation.
    """
    return _fast_score_spans(pattern, candidate._raw_scalars, candidate._bonuses)


def fast_score_at(
    pattern: Pattern,
    corpus: PreparedCorpus,
    index: Int,
) raises -> FastScore:
    """Return the fast score for one arena-backed corpus candidate."""
    corpus._check_index(index)
    return _fast_score_at_unchecked(pattern, corpus, index)


def _fast_score_at_unchecked(
    pattern: Pattern,
    corpus: PreparedCorpus,
    index: Int,
) -> FastScore:
    """Score one corpus slot after bounds have been established."""
    var start = corpus._offsets[index]
    var end = corpus._offsets[index + 1]
    return _fast_score_spans(
        pattern,
        Span(corpus._raw_scalars)[start:end],
        Span(corpus._bonuses)[start:end],
    )
