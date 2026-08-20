"""Correctness-first scalar fuzzy matching."""

from std.collections import List

from ..pattern import Pattern, _scalar_values
from ..result import MatchResult


comptime _MAX_REFERENCE_CELLS = 1_000_000
comptime _MAX_REFERENCE_TRANSITIONS = 25_000_000
comptime _MAX_REFERENCE_TIE_STEPS = 100_000_000
comptime _SCORE_MAGNITUDE_LIMIT = 1_000_000_000


def _checked_reference_cells(pattern_count: Int, candidate_count: Int) raises -> Int:
    """Validate every product used by the bounded reference implementation."""
    # The score is at most 125 per pattern scalar and its negative magnitude is
    # bounded by the candidate length. Prove those arithmetic operations remain
    # inside the deliberately conservative score interval before evaluating one.
    if pattern_count > _SCORE_MAGNITUDE_LIMIT // 125:
        raise Error("pattern exceeds the scalar reference score limit")
    if candidate_count > _SCORE_MAGNITUDE_LIMIT:
        raise Error("candidate exceeds the scalar reference score limit")

    # Check division before multiplication so allocation and flattened indices
    # cannot overflow. Every later flattened index is strictly less than cells.
    if candidate_count > _MAX_REFERENCE_CELLS // pattern_count:
        raise Error("match exceeds the scalar reference state-table limit")
    var cells = pattern_count * candidate_count

    # The DP examines at most pattern_count * candidate_count^2 predecessor
    # transitions. Lexicographic ties may walk at most pattern_count positions.
    # Check both products by division rather than constructing an overflowing
    # estimate.
    if pattern_count > 1:
        if candidate_count > _MAX_REFERENCE_TRANSITIONS // cells:
            raise Error("match exceeds the scalar reference transition limit")
        var transitions = cells * candidate_count
        if pattern_count > _MAX_REFERENCE_TIE_STEPS // transitions:
            raise Error("match exceeds the scalar reference tie-break limit")
    return cells


def _score_positions(positions: List[Int]) -> Int:
    """Score a complete subsequence; higher values rank first.

    Each matched scalar contributes 100 points. Adjacent matches receive 25
    points, while leading and internal gaps cost one point per scalar.
    """
    if len(positions) == 0:
        return 0

    var score = len(positions) * 100 - positions[0]
    for index in range(1, len(positions)):
        var gap = positions[index] - positions[index - 1] - 1
        if gap == 0:
            score += 25
        else:
            score -= gap
    return score


def _is_lexicographically_earlier(left: List[Int], right: List[Int]) -> Bool:
    for index in range(len(left)):
        if left[index] < right[index]:
            return True
        if left[index] > right[index]:
            return False
    return False


def _path_is_earlier(
    backpointers: List[Int],
    width: Int,
    level: Int,
    left_end: Int,
    right_end: Int,
) -> Bool:
    var left = List[Int](length=level + 1, fill=0)
    var right = List[Int](length=level + 1, fill=0)
    var left_cursor = left_end
    var right_cursor = right_end
    for reverse_index in range(level + 1):
        var index = level - reverse_index
        left[index] = left_cursor
        right[index] = right_cursor
        if index > 0:
            left_cursor = backpointers[index * width + left_cursor]
            right_cursor = backpointers[index * width + right_cursor]
    return _is_lexicographically_earlier(left, right)


def scalar_match(pattern: Pattern, candidate: StringSlice) raises -> MatchResult:
    """Return the best exact-scalar subsequence match.

    Dynamic programming considers every complete subsequence under the scoring
    contract. Equal scores choose lexicographically earlier positions. This is
    a reviewable reference algorithm, not the final performance path.
    """
    if pattern.is_empty():
        return MatchResult(True, 0, List[Int]())

    var candidate_scalars = _scalar_values(candidate)
    if len(candidate_scalars) < len(pattern):
        return MatchResult.no_match()

    var candidate_count = len(candidate_scalars)
    var pattern_count = len(pattern)
    var cell_count = _checked_reference_cells(pattern_count, candidate_count)
    var unreachable = -_SCORE_MAGNITUDE_LIMIT - 1
    var backpointers = List[Int](length=cell_count, fill=-1)
    var previous = List[Int](length=candidate_count, fill=unreachable)

    for candidate_index in range(candidate_count):
        if candidate_scalars[candidate_index] == pattern._scalars[0]:
            previous[candidate_index] = 100 - candidate_index

    for pattern_index in range(1, pattern_count):
        var current = List[Int](length=candidate_count, fill=unreachable)
        for candidate_index in range(candidate_count):
            if candidate_scalars[candidate_index] != pattern._scalars[pattern_index]:
                continue

            var best_predecessor = -1
            var best_score = unreachable
            for predecessor in range(candidate_index):
                if previous[predecessor] == unreachable:
                    continue
                var gap = candidate_index - predecessor - 1
                var transition = 100 - gap
                if gap == 0:
                    transition = 125
                var score = previous[predecessor] + transition
                if (
                    best_predecessor < 0
                    or score > best_score
                    or (
                        score == best_score
                        and _path_is_earlier(
                            backpointers,
                            candidate_count,
                            pattern_index - 1,
                            predecessor,
                            best_predecessor,
                        )
                    )
                ):
                    best_predecessor = predecessor
                    best_score = score

            if best_predecessor >= 0:
                current[candidate_index] = best_score
                backpointers[
                    pattern_index * candidate_count + candidate_index
                ] = best_predecessor
        previous = current^

    var best_end = -1
    var best_score = unreachable
    for candidate_index in range(candidate_count):
        if previous[candidate_index] == unreachable:
            continue
        if (
            best_end < 0
            or previous[candidate_index] > best_score
            or (
                previous[candidate_index] == best_score
                and _path_is_earlier(
                    backpointers,
                    candidate_count,
                    pattern_count - 1,
                    candidate_index,
                    best_end,
                )
            )
        ):
            best_end = candidate_index
            best_score = previous[candidate_index]

    if best_end < 0:
        return MatchResult.no_match()

    var positions = List[Int](length=pattern_count, fill=0)
    for reverse_index in range(pattern_count):
        var pattern_index = pattern_count - reverse_index - 1
        positions[pattern_index] = best_end
        if pattern_index > 0:
            best_end = backpointers[pattern_index * candidate_count + best_end]
    var score = _score_positions(positions)
    return MatchResult(True, score, positions^)
