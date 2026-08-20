"""Linear-time production scalar fuzzy matching."""

from std.collections import List

from ..pattern import Pattern, _matching_scalar_values
from ..result import MatchResult


comptime _UNREACHABLE = Int.MIN // 4


def _transition(previous: Int, current: Int) -> Int:
    var gap = current - previous - 1
    if gap == 0:
        return 125
    return 100 - gap


def scalar_match(pattern: Pattern, candidate: StringSlice) -> MatchResult:
    """Return the best prepared-scalar subsequence match in ``O(P*C)`` time.

    Backward dynamic-programming rows retain each optimal suffix score. A
    forward greedy walk then chooses the first position that preserves that
    optimum at every pattern index, yielding the lexicographically earliest
    optimal position vector. Positions index the original candidate scalars.
    """
    if pattern.is_empty():
        return MatchResult(True, 0, List[Int]())

    var candidate_scalars = _matching_scalar_values(candidate, pattern._fold_ascii)
    var pattern_count = len(pattern)
    var candidate_count = len(candidate_scalars)
    if pattern_count > candidate_count:
        return MatchResult.no_match()

    var suffix_scores = List[Int](
        length=pattern_count * candidate_count, fill=_UNREACHABLE
    )
    var last_row_offset = (pattern_count - 1) * candidate_count
    for candidate_index in range(candidate_count):
        if candidate_scalars[candidate_index] == pattern._scalars[pattern_count - 1]:
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
                    var adjusted_suffix = suffix - new_gapped_index
                    if (
                        running_gapped_max == _UNREACHABLE
                        or adjusted_suffix > running_gapped_max
                    ):
                        running_gapped_max = adjusted_suffix

            if candidate_scalars[candidate_index] != pattern._scalars[pattern_index]:
                continue

            var best_suffix = _UNREACHABLE
            var adjacent_index = candidate_index + 1
            if adjacent_index < candidate_count:
                var adjacent_suffix = suffix_scores[next_row_offset + adjacent_index]
                if adjacent_suffix != _UNREACHABLE:
                    best_suffix = 125 + adjacent_suffix

            if running_gapped_max != _UNREACHABLE:
                var gapped_suffix = running_gapped_max + 101 + candidate_index
                if best_suffix == _UNREACHABLE or gapped_suffix > best_suffix:
                    best_suffix = gapped_suffix
            suffix_scores[current_row_offset + candidate_index] = best_suffix

    var best_start = -1
    var best_total = _UNREACHABLE
    for candidate_index in range(candidate_count):
        var suffix = suffix_scores[candidate_index]
        if suffix == _UNREACHABLE:
            continue
        var total = 100 - candidate_index + suffix
        if best_start < 0 or total > best_total:
            best_start = candidate_index
            best_total = total

    if best_start < 0:
        return MatchResult.no_match()

    var positions = List[Int](length=pattern_count, fill=0)
    positions[0] = best_start
    for pattern_index in range(1, pattern_count):
        var previous = positions[pattern_index - 1]
        var required_suffix = suffix_scores[
            (pattern_index - 1) * candidate_count + previous
        ]
        var found = False
        var row_offset = pattern_index * candidate_count
        for candidate_index in range(previous + 1, candidate_count):
            var suffix = suffix_scores[row_offset + candidate_index]
            if (
                suffix == _UNREACHABLE
                or candidate_scalars[candidate_index] != pattern._scalars[pattern_index]
            ):
                continue
            if _transition(previous, candidate_index) + suffix == required_suffix:
                positions[pattern_index] = candidate_index
                found = True
                break
        debug_assert(found, "suffix DP must admit a reconstruction step")

    return MatchResult(True, best_total, positions^)
