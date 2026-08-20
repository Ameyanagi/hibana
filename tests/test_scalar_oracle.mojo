"""Independent exhaustive oracle checks for the scalar matcher contract."""

from hibana import Matcher, MatchResult
from std.collections import List
from std.testing import TestSuite, assert_equal, assert_false, assert_true


struct _OracleResult(Copyable):
    var matched: Bool
    var score: Int
    var positions: List[Int]

    def __init__(
        out self,
        matched: Bool,
        score: Int,
        var positions: List[Int],
    ):
        self.matched = matched
        self.score = score
        self.positions = positions^


def _scalar_values(text: StringSlice) -> List[UInt32]:
    var values = List[UInt32]()
    for scalar in text.codepoints():
        values.append(scalar.to_u32())
    return values^


def _score(positions: List[Int]) -> Int:
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


def _is_earlier(left: List[Int], right: List[Int]) -> Bool:
    for index in range(len(left)):
        if left[index] < right[index]:
            return True
        if left[index] > right[index]:
            return False
    return False


def _brute_force_match(pattern: StringSlice, candidate: StringSlice) -> _OracleResult:
    """Enumerate candidate subsets without using Hibana implementation details."""
    var pattern_scalars = _scalar_values(pattern)
    var candidate_scalars = _scalar_values(candidate)
    if len(pattern_scalars) == 0:
        return _OracleResult(True, 0, List[Int]())
    if len(pattern_scalars) > len(candidate_scalars):
        return _OracleResult(False, 0, List[Int]())

    var found = False
    var best_score = 0
    var best_positions = List[Int]()
    for mask in range(1 << len(candidate_scalars)):
        var positions = List[Int]()
        for candidate_index in range(len(candidate_scalars)):
            if mask & (1 << candidate_index):
                positions.append(candidate_index)
        if len(positions) != len(pattern_scalars):
            continue

        var matches = True
        for pattern_index in range(len(pattern_scalars)):
            if (
                pattern_scalars[pattern_index]
                != candidate_scalars[positions[pattern_index]]
            ):
                matches = False
                break
        if not matches:
            continue

        var score = _score(positions)
        if (
            not found
            or score > best_score
            or (score == best_score and _is_earlier(positions, best_positions))
        ):
            found = True
            best_score = score
            best_positions = positions.copy()

    if not found:
        return _OracleResult(False, 0, List[Int]())
    return _OracleResult(True, best_score, best_positions^)


def _binary_text(code: Int, length: Int) -> String:
    var text = String()
    for index in range(length):
        if code & (1 << index):
            text += "b"
        else:
            text += "a"
    return text^


def _assert_oracle_equal(
    actual: MatchResult,
    expected: _OracleResult,
    pattern: StringSlice,
    candidate: StringSlice,
) raises:
    if actual.matched != expected.matched or actual.score != expected.score:
        raise Error(
            "oracle mismatch for pattern '",
            pattern,
            "' and candidate '",
            candidate,
            "'",
        )
    assert_equal(len(actual.positions), len(expected.positions))
    for index in range(len(actual.positions)):
        assert_equal(actual.positions[index], expected.positions[index])


def test_known_oracle_states_are_independent_and_canonical() raises:
    var no_match = _brute_force_match("ab", "aaa")
    assert_false(no_match.matched)
    assert_equal(no_match.score, 0)
    assert_equal(len(no_match.positions), 0)

    var empty = _brute_force_match("", "abba")
    assert_true(empty.matched)
    assert_equal(empty.score, 0)
    assert_equal(len(empty.positions), 0)

    var tied = _brute_force_match("abc", "abbc")
    assert_true(tied.matched)
    assert_equal(tied.positions[0], 0)
    assert_equal(tied.positions[1], 1)
    assert_equal(tied.positions[2], 3)


def test_exhaustive_small_alphabet_matches_brute_force_oracle() raises:
    # 15 patterns (lengths 0...3) × 63 candidates (lengths 0...5) = 945
    # deterministic comparisons. The oracle enumerates every candidate subset.
    for pattern_length in range(4):
        for pattern_code in range(1 << pattern_length):
            var pattern = _binary_text(pattern_code, pattern_length)
            var matcher = Matcher(pattern)
            for candidate_length in range(6):
                for candidate_code in range(1 << candidate_length):
                    var candidate = _binary_text(candidate_code, candidate_length)
                    var actual = matcher.match(candidate)
                    var expected = _brute_force_match(pattern, candidate)
                    _assert_oracle_equal(actual, expected, pattern, candidate)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
