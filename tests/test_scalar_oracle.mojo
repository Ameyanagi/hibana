"""Independent exhaustive oracle checks for the scalar matcher contract."""

from hibana import CaseMode, Matcher, MatchResult, Pattern
from hibana.algorithms.reference import reference_match
from std.collections import List
from std.testing import TestSuite, assert_equal, assert_false, assert_true


comptime _RANDOM_SEED = UInt64(0x6A09E667F3BCC909)
comptime _RANDOM_CASE_COUNT = 2_000


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


def _fold_ascii_scalar(scalar: UInt32) -> UInt32:
    if scalar >= UInt32(65) and scalar <= UInt32(90):
        return scalar + UInt32(32)
    return scalar


def _contains_ascii_uppercase(scalars: List[UInt32]) -> Bool:
    for scalar in scalars:
        if scalar >= UInt32(65) and scalar <= UInt32(90):
            return True
    return False


def _oracle_folds_ascii(pattern_scalars: List[UInt32], case_mode: CaseMode) -> Bool:
    return case_mode == CaseMode.IGNORE_ASCII or (
        case_mode == CaseMode.SMART_ASCII
        and not _contains_ascii_uppercase(pattern_scalars)
    )


def _closed_form_score(positions: List[Int]) -> Int:
    """Derive score from span, omitted slots, and adjacent pairs.

    This intentionally differs from the production transition/recomputation
    loops: every slot inside the first-to-last span is either matched or one
    internal gap, and each consecutive selected pair earns one adjacency bonus.
    """
    if len(positions) == 0:
        return 0

    var adjacent_pairs = 0
    for index in range(1, len(positions)):
        if positions[index] == positions[index - 1] + 1:
            adjacent_pairs += 1
    var occupied_span = positions[len(positions) - 1] - positions[0] + 1
    var internal_gaps = occupied_span - len(positions)
    return len(positions) * 100 - positions[0] - internal_gaps + adjacent_pairs * 25


def _advance_lexicographic_combination(
    mut positions: List[Int], candidate_count: Int
) -> Bool:
    """Advance a fixed-size combination in position-vector lexical order."""
    var position_count = len(positions)
    for reverse_index in range(position_count):
        var index = position_count - reverse_index - 1
        var limit = candidate_count - position_count + index
        if positions[index] < limit:
            positions[index] += 1
            for suffix in range(index + 1, position_count):
                positions[suffix] = positions[suffix - 1] + 1
            return True
    return False


def _brute_force_match(
    pattern: StringSlice,
    candidate: StringSlice,
    case_mode: CaseMode = CaseMode.SMART_ASCII,
) -> _OracleResult:
    """Enumerate candidate subsets without using Hibana implementation details."""
    var pattern_scalars = _scalar_values(pattern)
    var candidate_scalars = _scalar_values(candidate)
    if _oracle_folds_ascii(pattern_scalars, case_mode):
        for index in range(len(pattern_scalars)):
            pattern_scalars[index] = _fold_ascii_scalar(pattern_scalars[index])
        for index in range(len(candidate_scalars)):
            candidate_scalars[index] = _fold_ascii_scalar(candidate_scalars[index])
    if len(pattern_scalars) == 0:
        return _OracleResult(True, 0, List[Int]())
    if len(pattern_scalars) > len(candidate_scalars):
        return _OracleResult(False, 0, List[Int]())

    var found = False
    var best_score = 0
    var best_positions = List[Int]()
    var positions = List[Int](length=len(pattern_scalars), fill=0)
    for index in range(len(positions)):
        positions[index] = index
    var has_combination = True
    while has_combination:
        var matches = True
        for pattern_index in range(len(pattern_scalars)):
            if (
                pattern_scalars[pattern_index]
                != candidate_scalars[positions[pattern_index]]
            ):
                matches = False
                break
        if matches:
            var score = _closed_form_score(positions)
            # Combinations arrive lexicographically. Retaining the first equal
            # score implements the tie contract without a second comparator.
            if not found or score > best_score:
                found = True
                best_score = score
                best_positions = positions.copy()
        has_combination = _advance_lexicographic_combination(
            positions, len(candidate_scalars)
        )

    if not found:
        return _OracleResult(False, 0, List[Int]())
    return _OracleResult(True, best_score, best_positions^)


def _mixed_case_ternary_text(code: Int, length: Int) -> String:
    var text = String()
    var remaining = code
    for _ in range(length):
        var scalar = remaining % 3
        remaining = remaining // 3
        if scalar == 0:
            text += "a"
        elif scalar == 1:
            text += "b"
        else:
            text += "A"
    return text^


def _ternary_code_count(length: Int) -> Int:
    var count = 1
    for _ in range(length):
        count *= 3
    return count


def _next_xorshift64(mut state: UInt64) -> UInt64:
    # Reproducible xorshift64 recurrence: x ^= x << 13; x ^= x >> 7;
    # x ^= x << 17, starting from _RANDOM_SEED.
    state ^= state << 13
    state ^= state >> 7
    state ^= state << 17
    return state


def _random_mixed_case_text(mut state: UInt64, length: Int) -> String:
    var text = String()
    for _ in range(length):
        var scalar = _next_xorshift64(state) % 4
        if scalar == 0:
            text += "a"
        elif scalar == 1:
            text += "b"
        elif scalar == 2:
            text += "A"
        else:
            text += "B"
    return text^


def _assert_oracle_equal(
    actual: MatchResult,
    expected: _OracleResult,
    pattern: StringSlice,
    candidate: StringSlice,
) raises:
    if (
        actual.matched != expected.matched
        or actual.score != expected.score
        or len(actual.positions) != len(expected.positions)
    ):
        raise Error(
            "oracle mismatch for pattern '",
            pattern,
            "' and candidate '",
            candidate,
            "'",
        )
    for index in range(len(actual.positions)):
        if actual.positions[index] != expected.positions[index]:
            raise Error(
                "oracle mismatch for pattern '",
                pattern,
                "' and candidate '",
                candidate,
                "'",
            )


def _assert_three_way_case_mode(
    pattern: StringSlice,
    candidate: StringSlice,
    case_mode: CaseMode,
) raises:
    var prepared_pattern = Pattern(pattern, case_mode=case_mode)
    var actual = Matcher(prepared_pattern).match(candidate)
    var reference_result = reference_match(prepared_pattern, candidate)
    var expected = _brute_force_match(pattern, candidate, case_mode)
    _assert_oracle_equal(actual, expected, pattern, candidate)
    _assert_oracle_equal(reference_result, expected, pattern, candidate)


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


def test_exhaustive_small_alphabet_matches_both_oracles() raises:
    # 40 patterns (lengths 0...3) × 364 candidates (lengths 0...5) = 14,560
    # three-way comparisons. The brute-force oracle enumerates every valid
    # mixed-case combination independently of both DP implementations.
    var pair_count = 0
    for pattern_length in range(4):
        for pattern_code in range(_ternary_code_count(pattern_length)):
            var pattern = _mixed_case_ternary_text(pattern_code, pattern_length)
            var prepared_pattern = Pattern(pattern)
            var matcher = Matcher(prepared_pattern)
            for candidate_length in range(6):
                for candidate_code in range(_ternary_code_count(candidate_length)):
                    pair_count += 1
                    var candidate = _mixed_case_ternary_text(
                        candidate_code, candidate_length
                    )
                    var actual = matcher.match(candidate)
                    var reference_result = reference_match(prepared_pattern, candidate)
                    var expected = _brute_force_match(pattern, candidate)
                    _assert_oracle_equal(actual, expected, pattern, candidate)
                    _assert_oracle_equal(reference_result, expected, pattern, candidate)
    assert_equal(pair_count, 14_560)


def test_fixed_seed_random_cases_match_both_oracles() raises:
    var random_state = _RANDOM_SEED
    for case_index in range(_RANDOM_CASE_COUNT):
        var pattern_length = 0
        var candidate_length = 0
        if case_index < 50:
            # Enumerate all 5 × 10 length pairs before drawing random lengths.
            pattern_length = case_index % 5
            candidate_length = case_index // 5
        else:
            pattern_length = Int(_next_xorshift64(random_state) % 5)
            candidate_length = Int(_next_xorshift64(random_state) % 10)

        var pattern = _random_mixed_case_text(random_state, pattern_length)
        var candidate = _random_mixed_case_text(random_state, candidate_length)
        var prepared_pattern = Pattern(pattern)
        var actual = Matcher(prepared_pattern).match(candidate)
        var reference_result = reference_match(prepared_pattern, candidate)
        var expected = _brute_force_match(pattern, candidate)
        _assert_oracle_equal(actual, expected, pattern, candidate)
        _assert_oracle_equal(reference_result, expected, pattern, candidate)


def test_explicit_case_modes_match_both_oracles() raises:
    _assert_three_way_case_mode("a", "A", CaseMode.EXACT)
    _assert_three_way_case_mode("A", "a", CaseMode.EXACT)
    _assert_three_way_case_mode("Ab", "aB", CaseMode.EXACT)
    _assert_three_way_case_mode("aB", "xaBy", CaseMode.EXACT)

    _assert_three_way_case_mode("a", "A", CaseMode.IGNORE_ASCII)
    _assert_three_way_case_mode("A", "a", CaseMode.IGNORE_ASCII)
    _assert_three_way_case_mode("Ab", "xxaB", CaseMode.IGNORE_ASCII)
    _assert_three_way_case_mode("éA", "Éa", CaseMode.IGNORE_ASCII)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
