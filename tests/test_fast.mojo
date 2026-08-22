"""Tests for the allocation-free approximate scoring stage."""

from hibana import CaseMode, Pattern, Scheme
from hibana.fast import FastScore, fast_score
from hibana.prepared import MatchWorkspace, PreparedCandidate
from std.collections import List
from std.testing import TestSuite, assert_equal, assert_false, assert_true


def _assert_same_membership(
    query: StringSlice,
    candidate_text: StringSlice,
    case_mode: CaseMode,
    scheme: Scheme,
) raises:
    var pattern = Pattern(query, case_mode=case_mode)
    var candidate = PreparedCandidate(candidate_text, scheme=scheme)
    var fast = fast_score(pattern, candidate)
    var workspace = MatchWorkspace()
    var exact = workspace.match(pattern, candidate)
    assert_equal(fast.matched, exact.matched)


def test_empty_pattern_and_non_match_are_distinct() raises:
    var candidate = PreparedCandidate("anything")
    assert_true(fast_score(Pattern(""), candidate).matched)
    assert_equal(fast_score(Pattern(""), candidate).score, 0)
    assert_false(fast_score(Pattern("xyz"), candidate).matched)
    assert_equal(fast_score(Pattern("xyz"), candidate).score, 0)


def test_compact_reverse_alignment_uses_public_score_table() raises:
    # The forward scan first completes at the final b; reverse tightening then
    # chooses the adjacent "ab" rather than retaining the first candidate a.
    var score = fast_score(Pattern("ab"), PreparedCandidate("a---ab"))
    assert_true(score.matched)
    assert_equal(score.score, 366)


def test_fast_score_is_deterministic() raises:
    var pattern = Pattern("sMc", case_mode=CaseMode.IGNORE_ASCII)
    var candidate = PreparedCandidate("src/MyComponent", scheme=Scheme.PATH)
    var expected = fast_score(pattern, candidate)
    for _ in range(32):
        assert_true(fast_score(pattern, candidate) == expected)


def test_case_modes_and_schemes_preserve_exact_membership() raises:
    var patterns: List[String] = ["", "abc", "aC", "KM", "京大", "🔥b", "é"]
    var candidates: List[String] = [
        "",
        "a_b_c",
        "ABC",
        "KaMera",
        "src/AlphaComponent",
        "北京大学",
        "a🔥B",
        "café",
        "CAFÉ",
    ]
    var modes: List[CaseMode] = [
        CaseMode.EXACT,
        CaseMode.IGNORE_ASCII,
        CaseMode.SMART_ASCII,
    ]
    var schemes: List[Scheme] = [Scheme.DEFAULT, Scheme.PATH]
    for pattern in patterns:
        for candidate in candidates:
            for mode in modes:
                for scheme in schemes:
                    _assert_same_membership(pattern, candidate, mode, scheme)


def test_exhaustive_small_ascii_membership_matches_exact() raises:
    # Enumerate every binary string through length five as a candidate and
    # every binary string through length three as a pattern.
    var modes: List[CaseMode] = [
        CaseMode.EXACT,
        CaseMode.IGNORE_ASCII,
        CaseMode.SMART_ASCII,
    ]
    var schemes: List[Scheme] = [Scheme.DEFAULT, Scheme.PATH]
    for candidate_length in range(6):
        for candidate_bits in range(1 << candidate_length):
            var candidate = String()
            for index in range(candidate_length):
                candidate += "b" if candidate_bits & (1 << index) else "a"
            for pattern_length in range(4):
                for pattern_bits in range(1 << pattern_length):
                    var pattern = String()
                    for index in range(pattern_length):
                        pattern += "b" if pattern_bits & (1 << index) else "a"
                    for mode in modes:
                        for scheme in schemes:
                            _assert_same_membership(pattern, candidate, mode, scheme)


def test_fast_score_carries_no_position_storage() raises:
    var result = fast_score(Pattern("smc"), PreparedCandidate("src/MyComponent"))
    assert_true(result.matched)
    # Constructibility and equality make the intentionally small result shape
    # part of the public contract without exposing finalist positions.
    assert_true(result == FastScore(True, result.score))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
