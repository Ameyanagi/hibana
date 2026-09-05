"""Bounded top-K ranking and public ranked-value contracts."""

from hibana import CaseMode, MatchResult, Matcher, Ranked, TopK
from std.collections import List
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


comptime _RANDOM_SEED = UInt64(0xBB67AE8584CAA73B)
comptime _RANDOM_CASE_COUNT = 250


def _next_xorshift64(mut state: UInt64) -> UInt64:
    state ^= state << 13
    state ^= state >> 7
    state ^= state << 17
    return state


def _random_text(mut state: UInt64, length: Int) -> String:
    var text = String()
    for _ in range(length):
        var scalar = _next_xorshift64(state) % 9
        if scalar == 0:
            text += "a"
        elif scalar == 1:
            text += "b"
        elif scalar == 2:
            text += "m"
        elif scalar == 3:
            text += "A"
        elif scalar == 4:
            text += "M"
        elif scalar == 5:
            text += "_"
        elif scalar == 6:
            text += "/"
        elif scalar == 7:
            text += "京"
        else:
            text += "🔥"
    return text^


def _is_better(left: Ranked, right: Ranked) -> Bool:
    return left.score > right.score or (
        left.score == right.score and left.index < right.index
    )


def _naive_rank(matcher: Matcher, candidates: List[String], k: Int) -> List[Ranked]:
    var all_matches = List[Ranked]()
    for index in range(len(candidates)):
        var result = matcher.match(candidates[index])
        if result.matched:
            var positions = List[Int]()
            swap(positions, result.positions)
            all_matches.append(Ranked(index, result.score, positions^))

    for index in range(1, len(all_matches)):
        var cursor = index
        while cursor > 0 and _is_better(all_matches[cursor], all_matches[cursor - 1]):
            all_matches.swap_elements(cursor - 1, cursor)
            cursor -= 1

    var ranked = List[Ranked]()
    var ranked_count = min(k, len(all_matches))
    for _ in range(ranked_count):
        var best = all_matches.pop(0)
        ranked.append(best^)
    return ranked^


def test_top_k_validates_k_with_teaching_message() raises:
    with assert_raises(
        contains=(
            "TopK requires k >= 1, got 0; construct TopK with the number of matches to"
            " retain, or use Matcher.rank without k to keep every match"
        )
    ):
        _ = TopK(0)
    with assert_raises(
        contains=(
            "TopK requires k >= 1, got -3; construct TopK with the number of matches to"
            " retain, or use Matcher.rank without k to keep every match"
        )
    ):
        _ = TopK(-3)


def test_top_k_validate_reports_offending_storage_values() raises:
    var over_retained = TopK(1)
    var first_positions = List[Int]()
    var second_positions = List[Int]()
    over_retained._heap.append(Ranked(0, 20, first_positions^))
    over_retained._heap.append(Ranked(1, 10, second_positions^))
    with assert_raises(contains="retained 2 results but k is 1"):
        over_retained.validate()

    var unordered = TopK(3)
    var parent_positions = List[Int]()
    var child_positions = List[Int]()
    unordered._heap.append(Ranked(0, 20, parent_positions^))
    unordered._heap.append(Ranked(1, 10, child_positions^))
    with assert_raises(contains="heap order violated"):
        unordered.validate()
    with assert_raises(contains="child 1"):
        unordered.validate()


def test_rank_k_one_keeps_only_the_best_match() raises:
    var candidates: List[String] = ["ammo", "MatchMode", "nothing"]
    var ranked = Matcher("mm").rank(candidates, 1)

    assert_equal(len(ranked), 1)
    assert_equal(ranked[0].index, 1)
    assert_equal(ranked[0].score, 356)


def test_rank_k_larger_than_match_count_and_ignores_non_matches() raises:
    var candidates: List[String] = ["ab", "zzz", "a_b", "also no"]
    var ranked = Matcher("ab", case_mode=CaseMode.EXACT).rank(candidates, 10)

    assert_equal(len(ranked), 2)
    assert_equal(ranked[0].index, 2)
    assert_equal(ranked[1].index, 0)


def test_rank_ties_are_broken_by_input_order() raises:
    var candidates: List[String] = ["xa", "ya"]
    var ranked = Matcher("a", case_mode=CaseMode.EXACT).rank(candidates, 2)

    assert_equal(ranked[0].score, ranked[1].score)
    assert_equal(ranked[0].index, 0)
    assert_equal(ranked[1].index, 1)


def test_top_k_push_ignores_non_matches() raises:
    var top_k = TopK(2)
    var positions: List[Int] = [0]
    var matched = MatchResult(True, 10, positions^)
    var no_match = MatchResult.no_match()
    top_k.push(0, matched^)
    top_k.push(1, no_match^)

    assert_equal(top_k.len(), 1)
    var ranked = top_k^.take_ranked()
    assert_equal(ranked[0].index, 0)


def test_empty_pattern_matches_are_ranked() raises:
    var candidates: List[String] = ["z", "a", ""]
    var ranked = Matcher("").rank(candidates, 5)

    assert_equal(len(ranked), 3)
    for index in range(len(ranked)):
        assert_equal(ranked[index].index, index)
        assert_equal(ranked[index].score, 0)
        assert_equal(len(ranked[index].positions), 0)


def test_take_ranked_ordering_is_pinned() raises:
    var top_k = TopK(3)
    var first_positions: List[Int] = [5]
    var second_positions: List[Int] = [4]
    var third_positions: List[Int] = [2]
    var first = MatchResult(True, 10, first_positions^)
    var second = MatchResult(True, 20, second_positions^)
    var third = MatchResult(True, 20, third_positions^)
    top_k.push(5, first^)
    top_k.push(4, second^)
    top_k.push(2, third^)
    var ranked = top_k^.take_ranked()

    assert_equal(ranked[0].index, 2)
    assert_equal(ranked[1].index, 4)
    assert_equal(ranked[2].index, 5)


def test_top_k_equal_score_replaces_the_larger_index() raises:
    var top_k = TopK(2)
    var first_positions: List[Int] = [0]
    var second_positions: List[Int] = [1]
    var better_positions: List[Int] = [2]
    var first = MatchResult(True, 20, first_positions^)
    var second = MatchResult(True, 20, second_positions^)
    var better = MatchResult(True, 20, better_positions^)
    top_k.push(4, first^)
    top_k.push(5, second^)
    top_k.push(2, better^)
    var ranked = top_k^.take_ranked()

    assert_equal(ranked[0].index, 2)
    assert_equal(ranked[1].index, 4)


def test_ranked_is_equatable_and_writable() raises:
    var positions: List[Int] = [0, 5]
    var same_positions: List[Int] = [0, 5]
    var different_positions: List[Int] = [0, 4]
    var ranked = Ranked(2, 345, positions^)
    var same = Ranked(2, 345, same_positions^)
    var different = Ranked(2, 345, different_positions^)

    assert_true(ranked == same)
    assert_false(ranked == different)
    assert_true(String(ranked) == "Ranked(index=2, score=345, positions=[0, 5])")


def test_flagship_match_mode_ranks_above_ammo() raises:
    var candidates: List[String] = ["ammo", "MatchMode"]
    var ranked = Matcher("mm").rank(candidates, 2)

    assert_equal(ranked[0].index, 1)
    assert_equal(ranked[0].score, 356)
    assert_equal(ranked[1].index, 0)
    assert_equal(ranked[1].score, 269)


def test_fixed_seed_rank_matches_naive_full_sort_oracle() raises:
    var random_state = _RANDOM_SEED
    for _ in range(_RANDOM_CASE_COUNT):
        var pattern_length = Int(_next_xorshift64(random_state) % 5)
        var candidate_count = Int(_next_xorshift64(random_state) % 18)
        var k = Int(_next_xorshift64(random_state) % 8) + 1
        var pattern = _random_text(random_state, pattern_length)
        var candidates = List[String](capacity=candidate_count)
        for _ in range(candidate_count):
            var candidate_length = Int(_next_xorshift64(random_state) % 11)
            var candidate = _random_text(random_state, candidate_length)
            candidates.append(candidate^)

        var matcher = Matcher(pattern)
        var actual = matcher.rank(candidates, k)
        var expected = _naive_rank(matcher, candidates, k)
        assert_equal(len(actual), len(expected))
        for index in range(len(actual)):
            assert_true(actual[index] == expected[index])


def test_rank_clamps_unbounded_limit_for_empty_and_singleton_inputs() raises:
    var matcher = Matcher("a")
    var empty = List[String]()
    assert_equal(len(matcher.rank(empty, Int.MAX)), 0)
    assert_equal(len(matcher.rank(Span(empty), Int.MAX)), 0)
    var singleton: List[String] = ["a"]
    var expected = matcher.rank(singleton)
    var from_list = matcher.rank(singleton, Int.MAX)
    var from_span = matcher.rank(Span(singleton), Int.MAX)
    assert_equal(len(from_list), 1)
    assert_equal(len(from_span), 1)
    assert_true(from_list[0] == expected[0])
    assert_true(from_span[0] == expected[0])


def test_rank_validates_limit_before_returning_empty_input() raises:
    var empty = List[String]()
    for k in [0, -1]:
        with assert_raises(contains="rank requires k >= 1"):
            _ = Matcher("a").rank(empty, k)
        with assert_raises(contains="rank requires k >= 1"):
            _ = Matcher("a").rank(Span(empty), k)


def test_rank_clamped_limit_preserves_ties_in_both_overloads() raises:
    var candidates: List[String] = ["xa", "ya", "za", "none"]
    var matcher = Matcher("a", case_mode=CaseMode.EXACT)
    var expected = matcher.rank(candidates)
    var from_list = matcher.rank(candidates, Int.MAX)
    var from_span = matcher.rank(Span(candidates), Int.MAX)
    assert_equal(len(from_list), len(expected))
    assert_equal(len(from_span), len(expected))
    for index in range(len(expected)):
        assert_true(from_list[index] == expected[index])
        assert_true(from_span[index] == expected[index])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
