"""Whitespace-AND matching and ergonomic ranking contracts."""

from hibana import Matcher, Pattern, Ranked
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


def _rank_all(matcher: Matcher, candidates: List[String]) -> List[Ranked]:
    return matcher.rank(candidates)


def _rank_span_all(matcher: Matcher, candidates: Span[String, _]) -> List[Ranked]:
    return matcher.rank(candidates)


def test_multiword_audit_case_matches_and_ranks_every_candidate() raises:
    var candidates: List[String] = ["foo/bar", "bar/foo", "foobar"]
    var matcher = Matcher("foo bar")
    for candidate in candidates:
        assert_true(matcher.match(candidate).matched)

    var ranked = matcher.rank(candidates)
    assert_equal(len(ranked), 3)


def test_query_splits_on_runs_of_each_supported_ascii_whitespace() raises:
    var queries: List[String] = [
        "foo bar",
        "foo\tbar",
        "foo\nbar",
        "foo\rbar",
        " \tfoo\n\r bar  ",
    ]
    for query in queries:
        assert_true(Matcher(query).match("foo/bar").matched)


def test_multiword_score_is_the_sum_of_atom_scores() raises:
    var candidate = "foo/bar"
    var combined = Matcher("foo bar").match(candidate)
    var foo = Matcher("foo").match(candidate)
    var bar = Matcher("bar").match(candidate)
    assert_true(combined.matched)
    assert_equal(combined.score, foo.score + bar.score)


def test_every_query_atom_must_match() raises:
    assert_false(Matcher("foo baz").match("foo/bar").matched)


def test_multiword_positions_are_sorted_and_deduplicated() raises:
    var result = Matcher("aa a").match("aa")
    assert_true(result.matched)
    assert_equal(len(result.positions), 2)
    assert_equal(result.positions[0], 0)
    assert_equal(result.positions[1], 1)
    for index in range(1, len(result.positions)):
        assert_true(result.positions[index - 1] < result.positions[index])


def test_whitespace_only_query_matches_every_candidate() raises:
    var matcher = Matcher(" \t\n\r  ")
    var candidates: List[String] = ["anything", ""]
    for candidate in candidates:
        var result = matcher.match(candidate)
        assert_true(result.matched)
        assert_equal(result.score, 0)
        assert_equal(len(result.positions), 0)


def test_smart_case_is_decided_per_atom() raises:
    var matcher = Matcher("Foo bar")
    assert_true(matcher.match("FooBAR").matched)
    assert_false(matcher.match("foobar").matched)


def test_prepared_pattern_preserves_literal_space() raises:
    var matcher = Matcher(Pattern("foo bar"))
    assert_true(matcher.match("foo bar").matched)
    assert_false(matcher.match("foo/bar").matched)


def test_multiword_match_scalars_matches_string_path() raises:
    var matcher = Matcher("foo bar")
    var candidate = "bar/foo"
    var scalars = _scalar_values(candidate)
    assert_true(matcher.match(candidate) == matcher.match_scalars(scalars))


def test_rank_without_k_is_nonraising_and_returns_all_sorted_matches() raises:
    var candidates: List[String] = ["ammo", "MatchMode", "nothing"]
    var matcher = Matcher("mm")
    var ranked = _rank_all(matcher, candidates)
    assert_equal(len(ranked), 2)
    assert_equal(ranked[0].index, 1)
    assert_equal(ranked[1].index, 0)

    var span_ranked = _rank_span_all(matcher, candidates)
    assert_equal(len(span_ranked), len(ranked))
    for index in range(len(ranked)):
        assert_true(span_ranked[index] == ranked[index])


def test_rank_without_k_accepts_an_empty_list() raises:
    var candidates = List[String]()
    var ranked = _rank_all(Matcher("anything"), candidates)
    assert_equal(len(ranked), 0)


def test_rank_list_literal_overloads_compile_and_return_expected_match() raises:
    var matcher = Matcher("fb")
    var bounded = matcher.rank(["foo/bar", "x"], k=1)
    assert_equal(len(bounded), 1)
    assert_equal(bounded[0].index, 0)

    var all_matches = matcher.rank(["foo/bar", "x"])
    assert_equal(len(all_matches), 1)
    assert_equal(all_matches[0].index, 0)


def test_rank_reports_its_own_invalid_k_argument() raises:
    var candidates: List[String] = ["foo"]
    with assert_raises(
        contains="rank requires k >= 1, got 0; omit k to rank every match"
    ):
        _ = Matcher("f").rank(candidates, k=0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
