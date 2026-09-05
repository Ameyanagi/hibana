"""Checked exact DP budgets reject work before allocating score tables."""

from hibana import Matcher, Pattern
from hibana.budget import WorkspaceBudget
from hibana.hybrid import hybrid_rank, hybrid_rank_corpus
from hibana.parallel import (
    _rank_corpus_exact_with_worker_limit,
    _rank_prepared_exact_with_worker_limit,
)
from hibana.prepared import MatchWorkspace, PreparedCandidate, PreparedCorpus
from std.collections import List
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def test_budget_validates_configuration_and_dimensions_without_allocating() raises:
    var budget = WorkspaceBudget(max_cells=6)
    assert_equal(budget.max_cells(), 6)
    assert_true(budget == WorkspaceBudget(max_cells=6))
    assert_false(budget == WorkspaceBudget(max_cells=5))
    assert_equal(String(budget), "WorkspaceBudget(max_cells=6)")
    assert_equal(budget.max_bytes(), 48)
    assert_equal(budget.required_cells(2, 3), 6)
    assert_equal(budget.required_cells(0, Int.MAX), 0)
    budget.validate()
    var addressable = WorkspaceBudget()
    assert_equal(
        addressable.required_cells(1, addressable.max_cells()), addressable.max_cells()
    )
    with assert_raises(
        contains="requires 8 cells (64 bytes); allowed 6 cells (48 bytes)"
    ):
        _ = budget.required_cells(2, 4)
    with assert_raises(contains="max_cells must be within"):
        _ = WorkspaceBudget(max_cells=-1)
    with assert_raises(contains="max_cells must be within"):
        _ = WorkspaceBudget(max_cells=Int.MAX)
    with assert_raises(contains="pattern_count must be >= 0; got -1"):
        _ = budget.required_cells(-1, 0)
    with assert_raises(contains="candidate_count must be >= 0; got -1"):
        _ = budget.required_cells(0, -1)
    with assert_raises(contains="cell count exceeds Int.MAX"):
        _ = budget.required_cells(Int.MAX, 2)
    with assert_raises(contains="byte count exceeds Int.MAX"):
        _ = WorkspaceBudget().required_cells(1, Int.MAX)


def test_budget_exact_boundary_and_capacity_growth() raises:
    var workspace = MatchWorkspace(budget=WorkspaceBudget(max_cells=6))
    var candidate = PreparedCandidate("abc")
    var short = workspace.match(Pattern("a"), candidate)
    assert_true(short.matched)
    assert_equal(workspace.retained_cells(), 3)
    var exact = workspace.match(Pattern("ab"), candidate)
    assert_true(exact == Matcher("ab").match("abc"))
    assert_equal(workspace.retained_cells(), 6)
    with assert_raises(
        contains="requires 9 cells (72 bytes); allowed 6 cells (48 bytes)"
    ):
        _ = workspace.score(Pattern("abc"), candidate)
    assert_equal(workspace.retained_cells(), 6)
    assert_equal(workspace.score(Pattern("a"), candidate).score, short.score)


def test_budget_caps_geometric_growth_and_rejects_without_reserving() raises:
    var workspace = MatchWorkspace(budget=WorkspaceBudget(max_cells=5))
    _ = workspace.score(Pattern("a"), PreparedCandidate("abc"))
    _ = workspace.score(Pattern("a"), PreparedCandidate("abcd"))
    assert_equal(workspace.retained_cells(), 5)
    var fresh = MatchWorkspace(budget=WorkspaceBudget(max_cells=5))
    with assert_raises(contains="requires 6 cells"):
        _ = fresh.match(Pattern("ab"), PreparedCandidate("abc"))
    assert_equal(fresh.retained_cells(), 0)
    var positions: List[Int] = [99]
    with assert_raises(contains="requires 6 cells"):
        _ = fresh.match_into(Pattern("ab"), PreparedCandidate("abc"), positions)
    assert_equal(fresh.retained_cells(), 0)
    assert_equal(len(positions), 0)


def test_zero_budget_keeps_empty_and_nonmatch_fast_paths() raises:
    var budget = WorkspaceBudget(max_cells=0)
    var workspace = MatchWorkspace(budget=budget)
    var candidate = PreparedCandidate("abc")
    assert_true(workspace.match(Pattern(""), candidate).matched)
    assert_false(workspace.score(Pattern("z"), candidate).matched)
    assert_equal(workspace.retained_cells(), 0)
    assert_false(Matcher("z", budget=budget).match("abc").matched)
    assert_true(Matcher("", budget=budget).match("abc").matched)
    with assert_raises(contains="allowed 0 cells (0 bytes)"):
        _ = Matcher("a", budget=budget).match("abc")


def test_matcher_budget_applies_to_atoms_list_and_span_rank() raises:
    var budget = WorkspaceBudget(max_cells=3)
    var matcher = Matcher("a b", budget=budget)
    assert_true(matcher.match("abc") == Matcher("a b").match("abc"))
    var values: List[String] = ["abcd"]
    with assert_raises(contains="requires 4 cells"):
        _ = matcher.rank(values, 1)
    with assert_raises(contains="requires 4 cells"):
        _ = matcher.rank(Span(values))


def test_corpus_budget_matches_owned_workspace_contract() raises:
    var corpus = PreparedCorpus()
    corpus.append("abc")
    var workspace = MatchWorkspace(budget=WorkspaceBudget(max_cells=5))
    with assert_raises(contains="requires 6 cells"):
        _ = workspace.score_at(Pattern("ab"), corpus, 0)
    var positions: List[Int] = [99]
    with assert_raises(contains="requires 6 cells"):
        _ = workspace.match_into_at(Pattern("ab"), corpus, 0, positions)
    assert_equal(len(positions), 0)
    assert_equal(workspace.retained_cells(), 0)


def test_parallel_budget_propagates_errors_and_preserves_exact_rows() raises:
    var values = [
        PreparedCandidate("abc"),
        PreparedCandidate("a_b"),
        PreparedCandidate("zzz"),
    ]
    var corpus = PreparedCorpus()
    corpus.append("abc")
    corpus.append("a_b")
    corpus.append("zzz")
    var pattern = Pattern("ab")
    var expected = _rank_prepared_exact_with_worker_limit(values, pattern, 3, 1, 1)
    for workers in [1, 3]:
        var budget = WorkspaceBudget(max_cells=6)
        assert_true(
            _rank_prepared_exact_with_worker_limit(
                values, pattern, 3, 1, workers, budget
            )
            == expected
        )
        assert_true(
            _rank_corpus_exact_with_worker_limit(corpus, pattern, 3, 1, workers, budget)
            == expected
        )
        with assert_raises(contains="requires 6 cells"):
            _ = _rank_prepared_exact_with_worker_limit(
                values, pattern, 3, 1, workers, WorkspaceBudget(max_cells=5)
            )
        with assert_raises(contains="requires 6 cells"):
            _ = _rank_corpus_exact_with_worker_limit(
                corpus, pattern, 3, 1, workers, WorkspaceBudget(max_cells=5)
            )


def test_parallel_reports_first_failing_shard_and_later_shard_failure() raises:
    var values = [PreparedCandidate("abc"), PreparedCandidate("abcd")]
    for _ in range(8):
        with assert_raises(contains="requires 6 cells"):
            _ = _rank_prepared_exact_with_worker_limit(
                values, Pattern("ab"), 2, 1, 2, WorkspaceBudget(max_cells=5)
            )
    var later = [PreparedCandidate("zzz"), PreparedCandidate("abcd")]
    with assert_raises(contains="requires 8 cells"):
        _ = _rank_prepared_exact_with_worker_limit(
            later, Pattern("ab"), 2, 1, 2, WorkspaceBudget(max_cells=5)
        )


def test_hybrid_budget_reaches_exact_reranking_without_fallback() raises:
    var values = [PreparedCandidate("abc")]
    var corpus = PreparedCorpus()
    corpus.append("abc")
    with assert_raises(contains="requires 6 cells"):
        _ = hybrid_rank(Pattern("ab"), values, k=1, budget=WorkspaceBudget(max_cells=5))
    with assert_raises(contains="requires 6 cells"):
        _ = hybrid_rank_corpus(
            Pattern("ab"), corpus, k=1, budget=WorkspaceBudget(max_cells=5)
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
