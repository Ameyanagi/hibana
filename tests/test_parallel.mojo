"""Differential tests for opt-in synchronous parallel exact ranking."""

from hibana import CaseMode, Pattern, Scheme, TopK
from hibana.parallel import (
    ParallelRankPage,
    _rank_prepared_exact_with_worker_limit,
    rank_prepared_exact,
)
from hibana.prepared import MatchWorkspace, PreparedCandidate
from std.collections import List
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


def _serial_page(
    candidates: Span[PreparedCandidate, _], pattern: Pattern, k: Int
) raises -> ParallelRankPage:
    var workspace = MatchWorkspace()
    var top_k = TopK(k)
    var total_matches = 0
    for source_index in range(len(candidates)):
        var result = workspace.match(pattern, candidates[source_index])
        if result.matched:
            total_matches += 1
        top_k.push(source_index, result^)

    var ranked = top_k^.take_ranked()
    var page = rank_prepared_exact(
        candidates,
        pattern,
        k=k,
        grain_size=max(len(candidates), 1),
    )
    assert_equal(page.total_matches, total_matches)
    assert_equal(len(page.rows), len(ranked))
    for index in range(len(ranked)):
        assert_equal(page.rows[index].source_index, ranked[index].index)
        assert_equal(page.rows[index].score, ranked[index].score)
        assert_equal(page.rows[index].positions, ranked[index].positions)
    return page^


def _assert_parallel_matches_serial(
    candidates: Span[PreparedCandidate, _],
    pattern: Pattern,
    k: Int,
    grain_size: Int,
) raises:
    var expected = _serial_page(candidates, pattern, k)
    var actual = rank_prepared_exact(candidates, pattern, k=k, grain_size=grain_size)
    assert_true(actual == expected)


def test_parallel_exact_matches_serial_for_mixed_unicode_and_ties() raises:
    var candidates = List[PreparedCandidate]()
    var texts = [
        "src/alpha_beta.mojo",
        "src/alpha_beta.mojo",
        "src/AlphaBeta.mojo",
        "src/京alpha🔥beta.mojo",
        "unrelated",
        "alpha/beta",
        "a_l_p_h_a___beta",
    ]
    for text in texts:
        candidates.append(PreparedCandidate(text, scheme=Scheme.PATH))
    _assert_parallel_matches_serial(
        candidates,
        Pattern("ab", case_mode=CaseMode.IGNORE_ASCII),
        5,
        1,
    )


def test_parallel_exact_counts_empty_pattern_before_truncation() raises:
    var candidates = List[PreparedCandidate]()
    for index in range(37):
        candidates.append(PreparedCandidate(String("candidate-", index)))
    var page = rank_prepared_exact(candidates, Pattern(""), k=7, grain_size=3)
    assert_equal(page.total_matches, 37)
    assert_equal(len(page.rows), 7)
    for index in range(7):
        assert_equal(page.rows[index].source_index, index)
        assert_equal(page.rows[index].score, 0)
        assert_equal(len(page.rows[index].positions), 0)


def test_parallel_exact_shard_tails_match_serial() raises:
    var lengths = [0, 1, 2, 3, 4, 5, 7, 8, 9, 15, 16, 17, 31, 32, 33]
    for length in lengths:
        var candidates = List[PreparedCandidate](capacity=length)
        for index in range(length):
            var text = String(
                "src/pkg-", index, "/alpha_beta.mojo"
            ) if index % 4 != 0 else String("src/pkg-", index, "/other.mojo")
            candidates.append(PreparedCandidate(text, scheme=Scheme.PATH))
        _assert_parallel_matches_serial(candidates, Pattern("ab"), 6, 3)


def test_internal_worker_limit_forces_two_shard_task_group() raises:
    var candidates = List[PreparedCandidate]()
    for index in range(17):
        candidates.append(
            PreparedCandidate(
                String("src/pkg-", index, "/alpha_beta.mojo"),
                scheme=Scheme.PATH,
            )
        )
    var expected = _serial_page(candidates, Pattern("ab"), 6)
    var actual = _rank_prepared_exact_with_worker_limit(
        candidates,
        Pattern("ab"),
        6,
        3,
        2,
    )
    assert_true(actual == expected)


def test_parallel_exact_no_match_and_serial_fallback_match_oracle() raises:
    var candidates = List[PreparedCandidate]()
    for index in range(25):
        candidates.append(PreparedCandidate(String("candidate-", index)))
    _assert_parallel_matches_serial(
        candidates,
        Pattern("not-present-anywhere"),
        4,
        10_000,
    )


def test_parallel_exact_rejects_invalid_k_and_grain() raises:
    var candidates = [PreparedCandidate("abc")]
    with assert_raises(contains="parallel exact ranking requires k >= 1, got 0"):
        _ = rank_prepared_exact(candidates, Pattern("a"), k=0)
    with assert_raises(
        contains="parallel exact ranking requires grain_size >= 1, got 0"
    ):
        _ = rank_prepared_exact(candidates, Pattern("a"), grain_size=0)


def test_parallel_exact_clamps_unbounded_limit_to_corpus_size() raises:
    var candidates = [PreparedCandidate("abc"), PreparedCandidate("axc")]
    var page = rank_prepared_exact(
        candidates,
        Pattern("ac"),
        k=1_000_000_000,
        grain_size=1,
    )
    assert_equal(page.total_matches, 2)
    assert_equal(len(page.rows), 2)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
