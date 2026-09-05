"""Linear-time production scalar fuzzy matching."""

from std.collections import List

from ..budget import WorkspaceBudget
from ..pattern import Pattern
from ..result import MatchResult, MatchScore
from ..scoring import (
    _BONUS_EXACT_CASE,
    Scheme,
    _BONUS_FIRST_CHAR_MULTIPLIER,
    _SCORE_ADJACENCY,
    _SCORE_MATCH,
    _candidate_bonuses,
    _candidate_match_scalar,
    _exact_case_score,
)


comptime _UNREACHABLE = Int.MIN // 4


struct _MatchStart(Copyable):
    """Optimal first position and score before the exact-case bonus."""

    var position: Int
    var score: Int

    def __init__(out self, position: Int, score: Int):
        self.position = position
        self.score = score


def _transition(previous: Int, current: Int, bonus: Int) -> Int:
    var gap = current - previous - 1
    if gap == 0:
        return _SCORE_MATCH + bonus + _SCORE_ADJACENCY
    return _SCORE_MATCH + bonus - gap


def _is_subsequence_match(
    pattern: Pattern,
    candidate: Span[UInt32, _],
) -> Bool:
    """Reject non-matches with one allocation-free candidate scan."""
    if pattern.is_empty():
        return True
    if len(pattern) > len(candidate):
        return False

    var pattern_index = 0
    for candidate_index in range(len(candidate)):
        if (
            _candidate_match_scalar(candidate[candidate_index], pattern._fold_ascii)
            == pattern._scalars[pattern_index]
        ):
            pattern_index += 1
            if pattern_index == len(pattern):
                return True
    return False


def _reset_scores(mut suffix_scores: List[Int], cell_count: Int, max_cells: Int):
    """Reset logical workspace length while retaining its allocation."""
    if cell_count > suffix_scores.capacity():
        var target_capacity = cell_count
        if suffix_scores.capacity() <= Int.MAX // 2:
            target_capacity = max(cell_count, max(1, suffix_scores.capacity() * 2))
        suffix_scores.reserve(min(target_capacity, max_cells))
    suffix_scores.clear()
    suffix_scores.resize(cell_count, _UNREACHABLE)


def _build_suffix_scores(
    pattern: Pattern,
    candidate: Span[UInt32, _],
    bonuses: Span[Int, _],
    mut suffix_scores: List[Int],
    budget: WorkspaceBudget,
) raises -> _MatchStart:
    """Build the shared DP and return its optimal first position and score."""
    var pattern_count = len(pattern)
    var candidate_count = len(candidate)
    var required = budget._required_cells(pattern_count, candidate_count)
    _reset_scores(suffix_scores, required, budget.max_cells())

    var last_row_offset = (pattern_count - 1) * candidate_count
    for candidate_index in range(candidate_count):
        if (
            _candidate_match_scalar(candidate[candidate_index], pattern._fold_ascii)
            == pattern._scalars[pattern_count - 1]
        ):
            suffix_scores[last_row_offset + candidate_index] = 0

    for reverse_row in range(1, pattern_count):
        var pattern_index = pattern_count - reverse_row - 1
        var current_row_offset = pattern_index * candidate_count
        var next_row_offset = current_row_offset + candidate_count
        var running_gapped_max = _UNREACHABLE
        for reverse_column in range(candidate_count):
            var candidate_index = candidate_count - reverse_column - 1
            var new_gapped_index = candidate_index + 2
            if new_gapped_index < candidate_count:
                var suffix = suffix_scores[next_row_offset + new_gapped_index]
                if suffix != _UNREACHABLE:
                    var adjusted_suffix = (
                        suffix + bonuses[new_gapped_index] - new_gapped_index
                    )
                    if (
                        running_gapped_max == _UNREACHABLE
                        or adjusted_suffix > running_gapped_max
                    ):
                        running_gapped_max = adjusted_suffix

            if (
                _candidate_match_scalar(candidate[candidate_index], pattern._fold_ascii)
                != pattern._scalars[pattern_index]
            ):
                continue

            var best_suffix = _UNREACHABLE
            var adjacent_index = candidate_index + 1
            if adjacent_index < candidate_count:
                var adjacent_suffix = suffix_scores[next_row_offset + adjacent_index]
                if adjacent_suffix != _UNREACHABLE:
                    best_suffix = (
                        _SCORE_MATCH
                        + bonuses[adjacent_index]
                        + _SCORE_ADJACENCY
                        + adjacent_suffix
                    )

            if running_gapped_max != _UNREACHABLE:
                var gapped_suffix = (
                    running_gapped_max + _SCORE_MATCH + 1 + candidate_index
                )
                if best_suffix == _UNREACHABLE or gapped_suffix > best_suffix:
                    best_suffix = gapped_suffix
            suffix_scores[current_row_offset + candidate_index] = best_suffix

    var best_start = -1
    var best_total = _UNREACHABLE
    for candidate_index in range(candidate_count):
        var suffix = suffix_scores[candidate_index]
        if suffix == _UNREACHABLE:
            continue
        var first_bonus = bonuses[candidate_index]
        var total = (
            _SCORE_MATCH
            + _BONUS_FIRST_CHAR_MULTIPLIER * first_bonus
            - candidate_index
            + suffix
        )
        if best_start < 0 or total > best_total:
            best_start = candidate_index
            best_total = total

    debug_assert(best_start >= 0, "subsequence prefilter guarantees a DP match")
    return _MatchStart(best_start, best_total)


def _next_position(
    pattern: Pattern,
    candidate: Span[UInt32, _],
    bonuses: Span[Int, _],
    suffix_scores: List[Int],
    pattern_index: Int,
    previous: Int,
) -> Int:
    """Return the lexicographically first next position preserving the optimum."""
    var candidate_count = len(candidate)
    var required_suffix = suffix_scores[
        (pattern_index - 1) * candidate_count + previous
    ]
    var row_offset = pattern_index * candidate_count
    for candidate_index in range(previous + 1, candidate_count):
        var suffix = suffix_scores[row_offset + candidate_index]
        if (
            suffix == _UNREACHABLE
            or _candidate_match_scalar(candidate[candidate_index], pattern._fold_ascii)
            != pattern._scalars[pattern_index]
        ):
            continue
        if (
            _transition(previous, candidate_index, bonuses[candidate_index]) + suffix
            == required_suffix
        ):
            return candidate_index
    debug_assert(False, "suffix DP must admit a reconstruction step")
    return -1


def _scalar_score_core(
    pattern: Pattern,
    candidate: Span[UInt32, _],
    bonuses: Span[Int, _],
    mut suffix_scores: List[Int],
    budget: WorkspaceBudget,
) raises -> MatchScore:
    """Return an exact score while retaining all scratch and allocating no list."""
    var best = _build_suffix_scores(pattern, candidate, bonuses, suffix_scores, budget)
    var previous = best.position
    var exact_case = (
        not pattern._fold_ascii or pattern._raw_scalars[0] == candidate[previous]
    )
    for pattern_index in range(1, len(pattern)):
        previous = _next_position(
            pattern,
            candidate,
            bonuses,
            suffix_scores,
            pattern_index,
            previous,
        )
        if pattern._raw_scalars[pattern_index] != candidate[previous]:
            exact_case = False
    var score = best.score
    if pattern._fold_ascii and exact_case:
        score += _BONUS_EXACT_CASE
    return MatchScore(True, score)


def _scalar_match_into_core(
    pattern: Pattern,
    candidate: Span[UInt32, _],
    bonuses: Span[Int, _],
    mut suffix_scores: List[Int],
    mut positions: List[Int],
    budget: WorkspaceBudget,
) raises -> MatchScore:
    """Return the exact score and reconstruct into caller-owned storage."""
    var best = _build_suffix_scores(pattern, candidate, bonuses, suffix_scores, budget)
    positions.clear()
    positions.resize(len(pattern), 0)
    positions[0] = best.position

    for pattern_index in range(1, len(pattern)):
        var previous = positions[pattern_index - 1]
        positions[pattern_index] = _next_position(
            pattern,
            candidate,
            bonuses,
            suffix_scores,
            pattern_index,
            previous,
        )

    return MatchScore(
        True,
        best.score + _exact_case_score(pattern, candidate, positions),
    )


def _scalar_match_core(
    pattern: Pattern,
    candidate: Span[UInt32, _],
    bonuses: Span[Int, _],
    mut suffix_scores: List[Int],
    budget: WorkspaceBudget,
) raises -> MatchResult:
    """Run the shared DP and return an owned position list."""
    var positions = List[Int]()
    var score = _scalar_match_into_core(
        pattern,
        candidate,
        bonuses,
        suffix_scores,
        positions,
        budget,
    )
    return MatchResult(score.matched, score.score, positions^)


def scalar_match(
    pattern: Pattern,
    candidate: Span[UInt32, _],
    scheme: Scheme = Scheme.DEFAULT,
    budget: WorkspaceBudget = WorkspaceBudget(),
) raises -> MatchResult:
    """Return the best prepared-scalar subsequence match in ``O(P*C)`` time.

    Backward dynamic-programming rows retain each optimal suffix score. A
    forward greedy walk then chooses the first position that preserves that
    optimum at every pattern index, yielding the lexicographically earliest
    optimal position vector. Positions index the original candidate scalars.
    """
    if pattern.is_empty():
        return MatchResult(True, 0, List[Int]())

    if not _is_subsequence_match(pattern, candidate):
        return MatchResult.no_match()
    var bonuses = _candidate_bonuses(candidate, scheme)
    var suffix_scores = List[Int]()
    return _scalar_match_core(
        pattern,
        candidate,
        bonuses,
        suffix_scores,
        budget,
    )
