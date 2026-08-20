from hibana import CaseMode, Matcher, MatchResult, Pattern, Scheme
from hibana.algorithms.reference import reference_match
from std.collections import List
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def _scalar_values(text: StringSlice) -> List[UInt32]:
    var values = List[UInt32]()
    for scalar in text.codepoints():
        values.append(scalar.to_u32())
    return values^


def _assert_match_invariants(
    pattern: StringSlice,
    candidate: StringSlice,
    result: MatchResult,
    expected_score: Int,
) raises:
    var pattern_scalars = _scalar_values(pattern)
    var candidate_scalars = _scalar_values(candidate)
    assert_true(result.matched)
    assert_equal(len(result.positions), len(pattern_scalars))
    for index in range(len(result.positions)):
        var position = result.positions[index]
        assert_true(position >= 0 and position < len(candidate_scalars))
        assert_equal(candidate_scalars[position], pattern_scalars[index])
        if index > 0:
            assert_true(result.positions[index - 1] < position)
    assert_equal(result.score, expected_score)


def _assert_same_result(left: MatchResult, right: MatchResult) raises:
    assert_equal(left.matched, right.matched)
    assert_equal(left.score, right.score)
    assert_equal(len(left.positions), len(right.positions))
    for index in range(len(left.positions)):
        assert_equal(left.positions[index], right.positions[index])


def test_pattern_is_prepared_by_unicode_scalar() raises:
    var pattern = Pattern("京大")
    assert_equal(len(pattern), 2)
    assert_false(pattern.is_empty())


def test_empty_pattern_matches_every_candidate() raises:
    var result = Matcher("").match("anything")
    assert_true(result.matched)
    assert_equal(result.score, 0)  # Empty patterns receive no score components.
    assert_equal(len(result.positions), 0)


def test_scalar_subsequence_reports_score_and_positions() raises:
    var result = Matcher("kmr").match("kamera")
    assert_true(result.matched)
    assert_equal(result.score, 463)  # 300 + 60 + 60 - 2 + 45
    assert_equal(len(result.positions), 3)
    assert_equal(result.positions[0], 0)
    assert_equal(result.positions[1], 2)
    assert_equal(result.positions[2], 4)


def test_contiguous_match_scores_higher_than_gapped_match() raises:
    var matcher = Matcher("kmr")
    var contiguous = matcher.match("kmr")
    var gapped = matcher.match("kamera")
    assert_true(contiguous.score > gapped.score)
    assert_equal(contiguous.score, 515)  # 300 + 60 + 60 + 50 + 45


def test_best_scoring_subsequence_is_selected() raises:
    var result = Matcher("ab").match("aab")
    assert_true(result.matched)
    assert_equal(result.positions[0], 0)
    assert_equal(result.positions[1], 2)
    assert_equal(result.score, 364)  # 200 + 60 + 60 - 1 + 45


def test_equal_scores_choose_lexicographically_earlier_positions() raises:
    var result = Matcher("abc").match("abbc")
    assert_true(result.matched)
    assert_equal(result.positions[0], 0)
    assert_equal(result.positions[1], 1)
    assert_equal(result.positions[2], 3)


def test_non_match_is_canonical() raises:
    var result = Matcher("xyz").match("xylophone")
    assert_false(result.matched)
    assert_equal(result.score, 0)  # Canonical non-matches have no score.
    assert_equal(len(result.positions), 0)


def test_smart_case_uppercase_query_remains_exact() raises:
    assert_false(Matcher("KM").match("kamera").matched)


def test_smart_case_lowercase_query_matches_mixed_case_candidate() raises:
    var result = Matcher("km").match("KaMera")
    assert_true(result.matched)
    assert_equal(result.positions[0], 0)
    assert_equal(result.positions[1], 2)
    assert_equal(result.score, 359)  # (100 + 60) + (100 + 40) + 60 - 1


def test_exact_case_mode_rejects_smart_case_match() raises:
    assert_false(Matcher("km", case_mode=CaseMode.EXACT).match("KaMera").matched)


def test_ignore_ascii_matches_uppercase_query_case_insensitively() raises:
    var result = Matcher("KM", case_mode=CaseMode.IGNORE_ASCII).match("kamera")
    assert_true(result.matched)
    assert_equal(result.positions[0], 0)
    assert_equal(result.positions[1], 2)


def test_non_ascii_scalars_never_fold() raises:
    assert_false(Matcher("é").match("É").matched)
    assert_true(Matcher("京").match("京").matched)


def test_pattern_retains_raw_scalars_when_ascii_folding_is_active() raises:
    var pattern = Pattern("Km", case_mode=CaseMode.IGNORE_ASCII)
    assert_equal(pattern._raw_scalars[0], UInt32(75))
    assert_equal(pattern._raw_scalars[1], UInt32(109))
    assert_equal(pattern._scalars[0], UInt32(107))
    assert_equal(pattern._scalars[1], UInt32(109))


def test_positions_are_unicode_scalar_indices() raises:
    var result = Matcher("京大").match("北京大学")
    assert_true(result.matched)
    assert_equal(result.positions[0], 1)
    assert_equal(result.positions[1], 2)
    assert_equal(result.score, 269)  # 200 + 25 - 1 + 45


def test_combining_scalar_positions_do_not_split_utf8_bytes() raises:
    var result = Matcher("́b").match("áb")
    assert_true(result.matched)
    assert_equal(result.positions[0], 1)
    assert_equal(result.positions[1], 2)


def test_emoji_counts_as_one_scalar_position() raises:
    var result = Matcher("🔥b").match("a🔥b")
    assert_true(result.matched)
    assert_equal(result.positions[0], 1)
    assert_equal(result.positions[1], 2)


def test_nonempty_pattern_does_not_match_empty_candidate() raises:
    assert_false(Matcher("a").match("").matched)


def test_a_match_may_have_a_negative_score() raises:
    var result = Matcher("z", case_mode=CaseMode.EXACT).match(
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaz"
    )
    assert_true(result.matched)
    assert_true(result.score < 0)


def test_prepared_pattern_can_be_reused() raises:
    var pattern = Pattern("fb")
    var matcher = Matcher(pattern)
    assert_true(matcher.match("foobar").matched)
    assert_true(matcher.match("feedback").matched)


def test_prepared_pattern_matcher_accepts_scheme() raises:
    var pattern = Pattern("ab", case_mode=CaseMode.EXACT)
    var default_result = Matcher(pattern).match("a/b")
    var path_result = Matcher(pattern, scheme=Scheme.PATH).match("a/b")
    assert_equal(default_result.score, 374)  # 200 + 60 + 55 + 60 - 1
    assert_equal(path_result.score, 379)  # 200 + 60 + 60 + 60 - 1


def test_matcher_outputs_satisfy_membership_order_and_score_invariants() raises:
    var pattern = "a🔥京"
    var candidate = "xxa--🔥z京-end"
    var result = Matcher(pattern).match(candidate)
    # 300 + 50 boundary + 0 first-extra - 2 leading - 3 internal + 45.
    _assert_match_invariants(pattern, candidate, result, 390)


def test_matching_is_deterministic_across_repeated_calls() raises:
    var matcher = Matcher("abc")
    var expected = matcher.match("a-bc-abc")
    for _ in range(16):
        var actual = matcher.match("a-bc-abc")
        _assert_same_result(actual, expected)


def test_matcher_snapshots_a_prepared_pattern() raises:
    var pattern = Pattern("ab")
    var matcher = Matcher(pattern)
    pattern._scalars = Pattern("zz")._scalars.copy()
    assert_true(matcher.match("ab").matched)
    assert_false(matcher.match("zz").matched)


def test_reference_state_table_limit_is_reported_before_allocation() raises:
    var pattern = String()
    var candidate = String()
    for _ in range(1_000):
        pattern += "a"
    for _ in range(1_001):
        candidate += "a"
    with assert_raises(contains="state-table limit"):
        _ = reference_match(Pattern(pattern), candidate)


def test_reference_transition_limit_is_reported() raises:
    var candidate = String()
    for _ in range(4_000):
        candidate += "a"
    with assert_raises(contains="transition limit"):
        _ = reference_match(Pattern("aa"), candidate)


def test_production_match_has_no_reference_transition_limit() raises:
    var candidate = String()
    for _ in range(4_000):
        candidate += "a"
    var result = Matcher("aa").match(candidate)
    assert_true(result.matched)
    assert_equal(result.score, 390)  # 200 + 60 + 60 + 25 + 45
    assert_equal(len(result.positions), 2)
    assert_equal(result.positions[0], 0)
    assert_equal(result.positions[1], 1)


def test_production_match_has_no_reference_tie_break_limit() raises:
    var pattern = String()
    var candidate = String()
    for _ in range(10):
        pattern += "a"
    for _ in range(1_300):
        candidate += "a"
    var result = Matcher(pattern).match(candidate)
    assert_true(result.matched)
    assert_equal(result.score, 1_390)  # 1_000 + 60 + 60 + 225 + 45
    assert_equal(len(result.positions), 10)
    assert_equal(result.positions[0], 0)
    assert_equal(result.positions[9], 9)
    for index in range(1, len(result.positions)):
        assert_true(result.positions[index - 1] < result.positions[index])


def test_production_match_has_no_reference_state_table_limit() raises:
    var pattern = String()
    var candidate = String()
    for _ in range(1_000):
        pattern += "a"
    for _ in range(1_001):
        candidate += "a"
    var result = Matcher(pattern).match(candidate)
    assert_true(result.matched)
    assert_equal(result.score, 125_140)  # 100_000 + 60 + 60 + 24_975 + 45
    assert_equal(len(result.positions), 1_000)
    assert_equal(result.positions[0], 0)
    assert_equal(result.positions[999], 999)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
