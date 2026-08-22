"""Differential coverage for advanced prepared-candidate matching."""

from hibana import CaseMode, MatchResult, Matcher, Pattern, Scheme
from hibana.algorithms.reference import reference_match
from hibana.prepared import MatchWorkspace, PreparedCandidate
from std.collections import List
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


comptime _RANDOM_SEED = UInt64(0x3C6EF372FE94F82B)
comptime _RANDOM_CASE_COUNT = 1_000


def _next_xorshift64(mut state: UInt64) -> UInt64:
    state ^= state << 13
    state ^= state >> 7
    state ^= state << 17
    return state


def _random_text(mut state: UInt64, length: Int) -> String:
    var text = String()
    for _ in range(length):
        var scalar = _next_xorshift64(state) % 11
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
            text += "\\"
        elif scalar == 8:
            text += " "
        elif scalar == 9:
            text += "京"
        else:
            text += "🔥"
    return text^


def _assert_same(actual: MatchResult, expected: MatchResult) raises:
    if actual != expected:
        raise Error(String("prepared result differs from scalar oracle: ", actual))


def _assert_score_same(
    mut workspace: MatchWorkspace,
    pattern: Pattern,
    candidate: PreparedCandidate,
    expected: MatchResult,
) raises:
    var score = workspace.score(pattern, candidate)
    assert_equal(score.matched, expected.matched)
    assert_equal(score.score, expected.score)

    var positions = List[Int]()
    positions.append(999)
    var into_score = workspace.match_into(pattern, candidate, positions)
    assert_equal(into_score.matched, expected.matched)
    assert_equal(into_score.score, expected.score)
    assert_equal(len(positions), len(expected.positions))
    for index in range(len(positions)):
        assert_equal(positions[index], expected.positions[index])


def test_prepared_candidate_reports_scalar_length_and_scheme() raises:
    var candidate = PreparedCandidate("a京🔥", scheme=Scheme.PATH)
    assert_equal(len(candidate), 3)
    assert_true(candidate.scheme() == Scheme.PATH)
    candidate.validate()


def test_prepared_candidate_validate_reports_parallel_storage_mutation() raises:
    var candidate = PreparedCandidate("abc")
    _ = candidate._bonuses.pop()
    with assert_raises(
        contains="PreparedCandidate bonus count must equal raw scalar count 3; got 2"
    ):
        candidate.validate()


def test_prepared_candidate_validate_reports_stale_bonus_mutation() raises:
    var candidate = PreparedCandidate("abc")
    candidate._bonuses[1] = 99
    with assert_raises(
        contains=(
            "PreparedCandidate bonus at index 1 must equal scheme-derived value 0;"
            " got 99; reconstruct the candidate to restore prepared storage"
        )
    ):
        candidate.validate()


def test_workspace_reuses_one_candidate_across_incremental_queries() raises:
    var candidate_text = "src/hibana/algorithms/scalar.mojo"
    var candidate = PreparedCandidate(candidate_text, scheme=Scheme.PATH)
    var workspace = MatchWorkspace()
    var queries = ["s", "sc", "sca", "scal", "scalar", "scalarx", ""]
    for query in queries:
        var pattern = Pattern(query)
        var actual = workspace.match(pattern, candidate)
        var expected = reference_match(pattern, candidate_text, Scheme.PATH)
        _assert_same(actual, expected)


def test_workspace_reuses_scratch_across_growing_and_shrinking_queries() raises:
    var candidate_text = "a_b/camelCase123/京🔥/abcdefghijk"
    var candidate = PreparedCandidate(candidate_text)
    var workspace = MatchWorkspace()
    var queries = ["abc123京", "a", "not-present", "aCC1🔥k", "ab"]
    var retained_capacity = 0
    for query_index in range(len(queries)):
        var query = queries[query_index]
        var pattern = Pattern(query, case_mode=CaseMode.IGNORE_ASCII)
        _assert_same(
            workspace.match(pattern, candidate),
            reference_match(pattern, candidate_text),
        )
        if query_index == 0:
            retained_capacity = workspace._suffix_scores.capacity()
        else:
            assert_true(workspace._suffix_scores.capacity() >= retained_capacity)


def test_prepared_candidate_matches_reference_for_all_case_modes() raises:
    var candidate_text = "xxa/B-京🔥-Ab"
    var default_candidate = PreparedCandidate(candidate_text)
    var workspace = MatchWorkspace()
    var exact = Pattern("aB京", case_mode=CaseMode.EXACT)
    var ignored = Pattern("Ab京", case_mode=CaseMode.IGNORE_ASCII)
    var smart_lower = Pattern("ab京", case_mode=CaseMode.SMART_ASCII)
    var smart_upper = Pattern("aB京", case_mode=CaseMode.SMART_ASCII)
    _assert_same(
        workspace.match(exact, default_candidate),
        reference_match(exact, candidate_text),
    )
    _assert_same(
        workspace.match(ignored, default_candidate),
        reference_match(ignored, candidate_text),
    )
    _assert_same(
        workspace.match(smart_lower, default_candidate),
        reference_match(smart_lower, candidate_text),
    )
    _assert_same(
        workspace.match(smart_upper, default_candidate),
        reference_match(smart_upper, candidate_text),
    )


def test_score_and_match_into_cover_match_nonmatch_and_empty_pattern() raises:
    var candidate_text = "src/MatchMode/京🔥.mojo"
    var candidate = PreparedCandidate(candidate_text, scheme=Scheme.PATH)
    var workspace = MatchWorkspace()
    var patterns = [
        Pattern("sMM京", case_mode=CaseMode.EXACT),
        Pattern("smm京", case_mode=CaseMode.IGNORE_ASCII),
        Pattern("not-present"),
        Pattern(""),
    ]
    for pattern in patterns:
        var expected = reference_match(pattern, candidate_text, Scheme.PATH)
        _assert_score_same(workspace, pattern, candidate, expected)


def test_match_into_reuses_caller_position_capacity() raises:
    var candidate = PreparedCandidate("a_b/camelCase123/京🔥/abcdefghijk")
    var workspace = MatchWorkspace()
    var positions = List[Int]()
    var longest = Pattern("abc123京")
    var longest_score = workspace.match_into(longest, candidate, positions)
    assert_true(longest_score.matched)
    var retained_capacity = positions.capacity()
    assert_true(retained_capacity >= len(longest))

    var short_score = workspace.match_into(Pattern("a"), candidate, positions)
    assert_true(short_score.matched)
    assert_equal(len(positions), 1)
    assert_true(positions.capacity() >= retained_capacity)

    var missing_score = workspace.match_into(
        Pattern("not-present"), candidate, positions
    )
    assert_true(not missing_score.matched)
    assert_equal(len(positions), 0)
    assert_true(positions.capacity() >= retained_capacity)


def test_fixed_seed_prepared_matches_both_scalar_paths() raises:
    var random_state = _RANDOM_SEED
    var workspace = MatchWorkspace()
    for case_index in range(_RANDOM_CASE_COUNT):
        var pattern_length = Int(_next_xorshift64(random_state) % 5)
        var candidate_length = Int(_next_xorshift64(random_state) % 11)
        var pattern_text = _random_text(random_state, pattern_length)
        var candidate_text = _random_text(random_state, candidate_length)
        var case_code = case_index % 3
        var case_mode = CaseMode.SMART_ASCII
        if case_code == 0:
            case_mode = CaseMode.EXACT
        elif case_code == 1:
            case_mode = CaseMode.IGNORE_ASCII
        var scheme = Scheme.DEFAULT if case_index % 2 == 0 else Scheme.PATH
        var pattern = Pattern(pattern_text, case_mode=case_mode)
        var candidate = PreparedCandidate(candidate_text, scheme=scheme)
        var actual = workspace.match(pattern, candidate)
        var scalar = Matcher(pattern, scheme=scheme).match(candidate_text)
        var reference = reference_match(pattern, candidate_text, scheme)
        _assert_same(actual, scalar)
        _assert_same(actual, reference)
        _assert_score_same(workspace, pattern, candidate, reference)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
