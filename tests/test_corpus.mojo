"""Differential and storage coverage for arena-backed prepared corpora."""

from hibana import CaseMode, Pattern, Ranked, Scheme
from hibana.algorithms.reference import reference_match
from hibana.fast import fast_score, fast_score_at
from hibana.hybrid import hybrid_rank, hybrid_rank_corpus
from hibana.prepared import MatchWorkspace, PreparedCandidate, PreparedCorpus
from hibana.parallel import (
    _rank_corpus_exact_with_worker_limit,
    _rank_prepared_exact_with_worker_limit,
)
from std.collections import List
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


comptime _RANDOM_SEED = UInt64(0xD1B54A32D192ED03)


def _next_xorshift64(mut state: UInt64) -> UInt64:
    state ^= state << 13
    state ^= state >> 7
    state ^= state << 17
    return state


def _random_text(mut state: UInt64, length: Int) -> String:
    var text = String()
    for _ in range(length):
        var choice = _next_xorshift64(state) % 10
        if choice == 0:
            text += "a"
        elif choice == 1:
            text += "B"
        elif choice == 2:
            text += "m"
        elif choice == 3:
            text += "_"
        elif choice == 4:
            text += "/"
        elif choice == 5:
            text += "9"
        elif choice == 6:
            text += "京"
        elif choice == 7:
            text += "🔥"
        else:
            text += "x"
    return text^


def _assert_rows_equal(left: List[Ranked], right: List[Ranked]) raises:
    assert_equal(len(left), len(right))
    for index in range(len(left)):
        assert_true(left[index] == right[index])


def test_corpus_storage_accounting() raises:
    var corpus = PreparedCorpus(scheme=Scheme.PATH)
    corpus.reserve(candidate_capacity=3, scalar_capacity=8)
    corpus.append("a/京🔥")
    corpus.append("")
    corpus.append("xy")
    assert_equal(len(corpus), 3)
    assert_equal(corpus.scalar_count(), 6)
    assert_equal(corpus.estimated_payload_bytes(), 12 * 6 + 8 * 4)
    assert_equal(corpus.candidate_length(0), 4)
    assert_equal(corpus.candidate_length(1), 0)
    assert_equal(corpus.candidate_length(2), 2)
    assert_true(corpus.scheme() == Scheme.PATH)
    corpus.validate()


def test_corpus_validates_bounds_and_reservation() raises:
    var corpus = PreparedCorpus()
    corpus.append("abc")
    with assert_raises(contains="candidate index out of range: -1"):
        _ = corpus.candidate_length(-1)
    with assert_raises(contains="candidate index out of range: 1"):
        _ = corpus.candidate_length(1)
    with assert_raises(contains="candidate_capacity must be at least"):
        corpus.reserve(candidate_capacity=0, scalar_capacity=3)
    with assert_raises(contains="must leave room for the final offset"):
        corpus.reserve(candidate_capacity=Int.MAX, scalar_capacity=3)
    with assert_raises(contains="scalar_capacity must be at least"):
        corpus.reserve(candidate_capacity=1, scalar_capacity=2)

    var workspace = MatchWorkspace()
    var positions: List[Int] = [7, 11]
    with assert_raises(contains="candidate index out of range: 1"):
        _ = workspace.match_into_at(Pattern("a"), corpus, 1, positions)
    assert_equal(len(positions), 2)
    assert_equal(positions[0], 7)
    assert_equal(positions[1], 11)
    with assert_raises(contains="candidate index out of range: -1"):
        _ = workspace.match_into_at(Pattern("a"), corpus, -1, positions)
    assert_equal(len(positions), 2)
    assert_equal(positions[0], 7)
    assert_equal(positions[1], 11)


def test_corpus_validation_rejects_corrupted_arenas_and_offsets() raises:
    var corpus = PreparedCorpus(scheme=Scheme.PATH)
    corpus.append("a/b")
    corpus.append("京🔥")

    var mismatched = PreparedCorpus(copy=corpus)
    _ = mismatched._bonuses.pop()
    with assert_raises(contains="scalar and bonus arena lengths differ"):
        mismatched.validate()

    var unordered = PreparedCorpus(copy=corpus)
    unordered._offsets[1] = len(unordered._raw_scalars) + 1
    with assert_raises(contains="offsets must be ordered and in range"):
        unordered.validate()

    var truncated = PreparedCorpus(copy=corpus)
    truncated._offsets[len(truncated._offsets) - 1] -= 1
    with assert_raises(contains="final offset must equal scalar count"):
        truncated.validate()

    var invalid_scalar = PreparedCorpus(copy=corpus)
    invalid_scalar._raw_scalars[0] = UInt32(0xD800)
    with assert_raises(contains="invalid Unicode scalar"):
        invalid_scalar.validate()

    var stale_bonus = PreparedCorpus(copy=corpus)
    stale_bonus._bonuses[1] = 999
    with assert_raises(contains="stale boundary bonus"):
        stale_bonus.validate()

    var unsupported_scheme = PreparedCorpus(copy=corpus)
    unsupported_scheme._scheme = Scheme(_value=99)
    with assert_raises(contains="unsupported scoring scheme"):
        unsupported_scheme.validate()

    var empty_offsets = PreparedCorpus(copy=corpus)
    empty_offsets._offsets.clear()
    with assert_raises(contains="offsets must start at zero"):
        empty_offsets.validate()

    var nonzero_first_offset = PreparedCorpus(copy=corpus)
    nonzero_first_offset._offsets[0] = 1
    with assert_raises(contains="offsets must start at zero"):
        nonzero_first_offset.validate()


def test_corpus_copy_has_independent_arenas_and_offsets() raises:
    var original = PreparedCorpus(scheme=Scheme.PATH)
    original.append("a/b")
    original.append("京🔥")
    var copied = PreparedCorpus(copy=original)

    copied._raw_scalars[0] = UInt32(0x7A)
    copied._bonuses[0] = 999
    copied._offsets[1] = 0

    original.validate()
    assert_equal(original.candidate_length(0), 3)
    assert_equal(original.candidate_length(1), 2)
    var workspace = MatchWorkspace()
    var score = workspace.score_at(Pattern("ab"), original, 0)
    assert_true(score.matched)


def test_corpus_exact_and_fast_paths_match_owned_preparation() raises:
    var values: List[String] = [
        "src/AlphaModule/京🔥.mojo",
        "tests/a_b9.mojo",
        "nothing",
        "",
    ]
    var corpus = PreparedCorpus(scheme=Scheme.PATH)
    for value in values:
        corpus.append(value)

    var patterns = [
        Pattern("sAm京", case_mode=CaseMode.IGNORE_ASCII),
        Pattern("ab9", case_mode=CaseMode.EXACT),
        Pattern("missing"),
        Pattern(""),
    ]
    var workspace = MatchWorkspace()
    var positions = List[Int]()
    for pattern in patterns:
        for index in range(len(values)):
            var owned = PreparedCandidate(values[index], scheme=Scheme.PATH)
            var expected = reference_match(pattern, values[index], Scheme.PATH)
            var score = workspace.score_at(pattern, corpus, index)
            assert_equal(score.matched, expected.matched)
            assert_equal(score.score, expected.score)
            var into = workspace.match_into_at(pattern, corpus, index, positions)
            assert_equal(into.matched, expected.matched)
            assert_equal(into.score, expected.score)
            assert_equal(len(positions), len(expected.positions))
            for position_index in range(len(positions)):
                assert_equal(
                    positions[position_index], expected.positions[position_index]
                )
            assert_true(
                fast_score_at(pattern, corpus, index) == fast_score(pattern, owned)
            )


def test_fixed_seed_corpus_matches_owned_exact_oracle() raises:
    var state = _RANDOM_SEED
    var workspace = MatchWorkspace()
    for case_index in range(500):
        var candidate = _random_text(state, Int(_next_xorshift64(state) % 14))
        var query = _random_text(state, Int(_next_xorshift64(state) % 5))
        var scheme = Scheme.DEFAULT if case_index % 2 == 0 else Scheme.PATH
        var mode = CaseMode.SMART_ASCII
        if case_index % 3 == 0:
            mode = CaseMode.EXACT
        elif case_index % 3 == 1:
            mode = CaseMode.IGNORE_ASCII
        var pattern = Pattern(query, case_mode=mode)
        var corpus = PreparedCorpus(scheme=scheme)
        corpus.append(candidate)
        var expected = reference_match(pattern, candidate, scheme)
        var actual = workspace.score_at(pattern, corpus, 0)
        assert_equal(actual.matched, expected.matched)
        assert_equal(actual.score, expected.score)


def test_corpus_hybrid_matches_owned_hybrid_contract_and_ties() raises:
    var values: List[String] = [
        "src/AlphaModule/component.mojo",
        "src/app/main_controller.mojo",
        "tests/search_match_case.mojo",
        "docs/unrelated.md",
        "src/SimpleMapCache.mojo",
        "src/SimpleMapCache.mojo",
    ]
    var owned = List[PreparedCandidate](capacity=len(values))
    var corpus = PreparedCorpus(scheme=Scheme.PATH)
    for value in values:
        owned.append(PreparedCandidate(value, scheme=Scheme.PATH))
        corpus.append(value)
    var pattern = Pattern("smc", case_mode=CaseMode.IGNORE_ASCII)
    var expected = hybrid_rank(pattern, owned, k=4, shortlist_size=5)
    var actual = hybrid_rank_corpus(pattern, corpus, k=4, shortlist_size=5)
    assert_equal(actual.total_matches, expected.total_matches)
    _assert_rows_equal(actual.rows, expected.rows)


def test_corpus_parallel_exact_matches_owned_across_worker_counts() raises:
    var values: List[String] = [
        "src/AlphaModule/component.mojo",
        "src/app/main_controller.mojo",
        "tests/search_match_case.mojo",
        "docs/unrelated.md",
        "src/SimpleMapCache.mojo",
        "src/SimpleMapCache.mojo",
        "a_b_c",
        "axbyc",
    ]
    var owned = List[PreparedCandidate](capacity=len(values))
    var corpus = PreparedCorpus(scheme=Scheme.PATH)
    for value in values:
        owned.append(PreparedCandidate(value, scheme=Scheme.PATH))
        corpus.append(value)
    var pattern = Pattern("smc", case_mode=CaseMode.IGNORE_ASCII)
    var expected = _rank_prepared_exact_with_worker_limit(owned, pattern, 5, 2, 1)
    for worker_count in range(1, 5):
        for _ in range(20):
            var owned_actual = _rank_prepared_exact_with_worker_limit(
                owned, pattern, 5, 2, worker_count
            )
            var corpus_actual = _rank_corpus_exact_with_worker_limit(
                corpus, pattern, 5, 2, worker_count
            )
            assert_true(owned_actual == expected)
            assert_true(corpus_actual == expected)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
