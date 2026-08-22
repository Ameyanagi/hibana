"""Tests for allocation-bounded hybrid corpus ranking."""

from hibana import CaseMode, Matcher, Pattern, Ranked, Scheme
from hibana.hybrid import hybrid_rank
from hibana.prepared import PreparedCandidate
from std.collections import List
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


comptime _RANDOM_SEED = UInt64(0x243F6A8885A308D3)


def _next_xorshift64(mut state: UInt64) -> UInt64:
    state ^= state << 13
    state ^= state >> 7
    state ^= state << 17
    return state


def _prepare(
    values: List[String], scheme: Scheme = Scheme.DEFAULT
) -> List[PreparedCandidate]:
    var prepared = List[PreparedCandidate](capacity=len(values))
    for value in values:
        prepared.append(PreparedCandidate(value, scheme=scheme))
    return prepared^


def _assert_rows_equal(left: List[Ranked], right: List[Ranked]) raises:
    assert_equal(len(left), len(right))
    for index in range(len(left)):
        assert_true(left[index] == right[index])


def test_hybrid_counts_all_members_before_shortlisting() raises:
    var values: List[String] = ["ab", "a_b", "axb", "zzz", "also b"]
    var prepared = _prepare(values)
    var result = hybrid_rank(Pattern("ab"), prepared, k=1, shortlist_size=1)
    assert_equal(result.total_matches, 4)
    assert_equal(len(result.rows), 1)


def test_hybrid_final_rows_have_exact_scores_and_positions() raises:
    var values: List[String] = [
        "src/AlphaModule/component.mojo",
        "src/app/main_controller.mojo",
        "tests/search_match_case.mojo",
        "docs/unrelated.md",
        "src/SimpleMapCache.mojo",
    ]
    var prepared = _prepare(values, scheme=Scheme.PATH)
    var pattern = Pattern("smc")
    var result = hybrid_rank(pattern, prepared, k=3, shortlist_size=5)
    var matcher = Matcher(pattern, scheme=Scheme.PATH)
    for row in result.rows:
        var exact = matcher.match(values[row.index])
        assert_equal(row.score, exact.score)
        assert_equal(len(row.positions), len(exact.positions))
        for index in range(len(row.positions)):
            assert_equal(row.positions[index], exact.positions[index])


def test_hybrid_is_deterministic_and_stable_on_ties() raises:
    var values: List[String] = ["z", "a", "x", ""]
    var prepared = _prepare(values)
    var expected = hybrid_rank(Pattern(""), prepared, k=3, shortlist_size=3)
    assert_equal(expected.total_matches, 4)
    assert_equal(expected.rows[0].index, 0)
    assert_equal(expected.rows[1].index, 1)
    assert_equal(expected.rows[2].index, 2)
    for _ in range(16):
        var actual = hybrid_rank(Pattern(""), prepared, k=3, shortlist_size=3)
        _assert_rows_equal(actual.rows, expected.rows)


def test_hybrid_validates_bounds() raises:
    var empty = _prepare(List[String]())
    with assert_raises(contains="hybrid_rank requires k >= 1, got 0"):
        _ = hybrid_rank(Pattern("a"), empty, k=0)
    with assert_raises(contains="hybrid_rank requires shortlist_size >= 1, got 0"):
        _ = hybrid_rank(Pattern("a"), empty, k=1, shortlist_size=0)

    var prepared = _prepare(["a", "ab", "ac", "ad"])
    with assert_raises(
        contains=(
            "hybrid_rank requires the corpus-bounded shortlist to cover the "
            "corpus-bounded row limit; got effective shortlist=2, effective rows=3"
        )
    ):
        _ = hybrid_rank(Pattern("a"), prepared, k=3, shortlist_size=2)


def test_hybrid_empty_and_unbounded_limits_are_corpus_bounded() raises:
    var empty = _prepare(List[String]())
    var empty_result = hybrid_rank(
        Pattern("a"), empty, k=1_000_000_000, shortlist_size=1
    )
    assert_equal(empty_result.total_matches, 0)
    assert_equal(len(empty_result.rows), 0)

    var prepared = _prepare(["abc", "axc"])
    var bounded = hybrid_rank(
        Pattern("ac"),
        prepared,
        k=1_000_000_000,
        shortlist_size=2,
    )
    assert_equal(bounded.total_matches, 2)
    assert_equal(len(bounded.rows), 2)


def _random_path(mut state: UInt64, index: Int) -> String:
    var text = String("src/")
    for position in range(28):
        var choice = _next_xorshift64(state) % 12
        if choice == 0:
            text += "s"
        elif choice == 1:
            text += "m"
        elif choice == 2:
            text += "c"
        elif choice == 3:
            text += "S"
        elif choice == 4:
            text += "M"
        elif choice == 5:
            text += "C"
        elif choice == 6:
            text += "/"
        elif choice == 7:
            text += "_"
        elif position % 3 == 0:
            text += "a"
        else:
            text += "x"
    text += String(index)
    text += ".mojo"
    return text^


def _recall(exact: List[Ranked], approximate: List[Ranked]) -> Int:
    var overlap = 0
    for exact_row in exact:
        for approximate_row in approximate:
            if exact_row.index == approximate_row.index:
                overlap += 1
                break
    return overlap


def test_seeded_corpora_quality_recall_against_full_exact_rank() raises:
    var seeds: List[UInt64] = [
        _RANDOM_SEED,
        UInt64(0x13198A2E03707344),
        UInt64(0xA4093822299F31D0),
    ]
    var queries: List[String] = ["smc", "mcs", "csm"]
    var narrow_total = 0
    var wide_total = 0
    var exact_total = 0
    for corpus_index in range(len(seeds)):
        var state = seeds[corpus_index]
        var values = List[String](capacity=256)
        for index in range(256):
            values.append(_random_path(state, index))
        var prepared = _prepare(values, scheme=Scheme.PATH)

        var query = queries[corpus_index]
        var k = 10
        var narrow = hybrid_rank(Pattern(query), prepared, k=k, shortlist_size=64)
        var wide = hybrid_rank(Pattern(query), prepared, k=k, shortlist_size=192)
        var exact = Matcher(query, scheme=Scheme.PATH).rank(values, k)
        narrow_total += _recall(exact, narrow.rows)
        wide_total += _recall(exact, wide.rows)
        exact_total += len(exact)

    # These three deterministic corpora currently produce aggregate recall@10
    # of 19/30 at B=64 and 27/30 at B=192. Keep floors explicit without
    # claiming the same recall for unrelated data.
    assert_equal(exact_total, 30)
    assert_true(narrow_total >= 19)
    assert_true(wide_total >= 27)


def test_shortlist_covering_all_members_matches_full_exact_rank() raises:
    var values: List[String] = [
        "a_b_c",
        "abc",
        "axbyc",
        "zzz",
        "A-B-C",
        "ab",
        "cab",
        "a/b/c",
    ]
    var prepared = _prepare(values, scheme=Scheme.PATH)
    var pattern = Pattern("abc", case_mode=CaseMode.IGNORE_ASCII)
    var hybrid = hybrid_rank(pattern, prepared, k=5, shortlist_size=len(values))
    var exact = Matcher(pattern, scheme=Scheme.PATH).rank(values, 5)
    _assert_rows_equal(hybrid.rows, exact)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
