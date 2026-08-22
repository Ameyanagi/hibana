"""Prepared-candidate and scalar fuzzy-matching benchmark matrix."""

from hibana import CaseMode, Matcher, MatchResult, Pattern, Scheme
from hibana.prepared import MatchWorkspace, PreparedCandidate
from std.benchmark import keep
from std.collections import List
from std.time import perf_counter_ns


comptime _SAMPLES = 5
comptime _WARMUP_ROUNDS = 2


def _checksum(result: MatchResult) -> Int:
    var checksum = result.score + len(result.positions) * 17
    checksum += 1 if result.matched else 0
    for index in range(len(result.positions)):
        checksum += (index + 1) * (result.positions[index] + 1)
    return checksum


def _print_result(
    identity: StringSlice,
    variant: StringLiteral,
    candidate_scalars: Int,
    query_scalars: Int,
    iterations: Int,
    best_elapsed_ns: Int,
    checksum: Int,
):
    print(
        "case=",
        identity,
        " variant=",
        variant,
        " candidate_scalars=",
        candidate_scalars,
        " query_scalars=",
        query_scalars,
        " iterations=",
        iterations,
        " best_elapsed_ns=",
        best_elapsed_ns,
        " ns_per_match=",
        Float64(best_elapsed_ns) / Float64(iterations),
        " checksum=",
        checksum,
        sep="",
    )


def _measure_scalar(
    identity: StringSlice,
    matcher: Matcher,
    candidate: String,
    query_scalars: Int,
    iterations: Int,
) raises:
    var expected_result = matcher.match(candidate)
    var expected_checksum = iterations * _checksum(expected_result)
    for _ in range(_WARMUP_ROUNDS):
        var checksum = 0
        for _ in range(iterations):
            var result = matcher.match(candidate)
            checksum += _checksum(result)
            keep(result)
        if checksum != expected_checksum:
            raise Error("scalar match checksum changed during warmup")

    var best_elapsed_ns = 0
    var best_checksum = 0
    for sample in range(_SAMPLES):
        var checksum = 0
        var started = perf_counter_ns()
        for _ in range(iterations):
            var result = matcher.match(candidate)
            checksum += _checksum(result)
            keep(result)
        var elapsed_ns = perf_counter_ns() - started
        if checksum != expected_checksum:
            raise Error("scalar match checksum changed during measurement")
        if sample == 0 or elapsed_ns < best_elapsed_ns:
            best_elapsed_ns = elapsed_ns
            best_checksum = checksum
    _print_result(
        identity,
        "scalar",
        len(PreparedCandidate(candidate)),
        query_scalars,
        iterations,
        best_elapsed_ns,
        best_checksum,
    )


def _measure_prepared(
    identity: StringSlice,
    pattern: Pattern,
    candidate: PreparedCandidate,
    iterations: Int,
) raises:
    var workspace = MatchWorkspace()
    var expected_result = workspace.match(pattern, candidate)
    var expected_checksum = iterations * _checksum(expected_result)
    for _ in range(_WARMUP_ROUNDS):
        var checksum = 0
        for _ in range(iterations):
            var result = workspace.match(pattern, candidate)
            checksum += _checksum(result)
            keep(result)
        if checksum != expected_checksum:
            raise Error("prepared match checksum changed during warmup")

    var best_elapsed_ns = 0
    var best_checksum = 0
    for sample in range(_SAMPLES):
        var checksum = 0
        var started = perf_counter_ns()
        for _ in range(iterations):
            var result = workspace.match(pattern, candidate)
            checksum += _checksum(result)
            keep(result)
        var elapsed_ns = perf_counter_ns() - started
        if checksum != expected_checksum:
            raise Error("prepared match checksum changed during measurement")
        if sample == 0 or elapsed_ns < best_elapsed_ns:
            best_elapsed_ns = elapsed_ns
            best_checksum = checksum
    _print_result(
        identity,
        "prepared_owned",
        len(candidate),
        len(pattern),
        iterations,
        best_elapsed_ns,
        best_checksum,
    )


def _measure_prepared_score(
    identity: StringSlice,
    pattern: Pattern,
    candidate: PreparedCandidate,
    iterations: Int,
) raises:
    var workspace = MatchWorkspace()
    var expected = workspace.score(pattern, candidate)
    var expected_unit_checksum = expected.score + (1 if expected.matched else 0)
    var expected_checksum = iterations * expected_unit_checksum
    for _ in range(_WARMUP_ROUNDS):
        var checksum = 0
        for _ in range(iterations):
            var result = workspace.score(pattern, candidate)
            checksum += result.score + (1 if result.matched else 0)
            keep(result)
        if checksum != expected_checksum:
            raise Error("prepared score checksum changed during warmup")

    var best_elapsed_ns = 0
    var best_checksum = 0
    for sample in range(_SAMPLES):
        var checksum = 0
        var started = perf_counter_ns()
        for _ in range(iterations):
            var result = workspace.score(pattern, candidate)
            checksum += result.score + (1 if result.matched else 0)
            keep(result)
        var elapsed_ns = perf_counter_ns() - started
        if checksum != expected_checksum:
            raise Error("prepared score checksum changed during measurement")
        if sample == 0 or elapsed_ns < best_elapsed_ns:
            best_elapsed_ns = elapsed_ns
            best_checksum = checksum
    _print_result(
        identity,
        "prepared_score",
        len(candidate),
        len(pattern),
        iterations,
        best_elapsed_ns,
        best_checksum,
    )


def _measure_prepared_into(
    identity: StringSlice,
    pattern: Pattern,
    candidate: PreparedCandidate,
    iterations: Int,
) raises:
    var workspace = MatchWorkspace()
    var positions = List[Int]()
    var expected = workspace.match_into(pattern, candidate, positions)
    var expected_unit_checksum = expected.score + len(positions) * 17
    expected_unit_checksum += 1 if expected.matched else 0
    for index in range(len(positions)):
        expected_unit_checksum += (index + 1) * (positions[index] + 1)
    var expected_checksum = iterations * expected_unit_checksum
    for _ in range(_WARMUP_ROUNDS):
        var checksum = 0
        for _ in range(iterations):
            var result = workspace.match_into(pattern, candidate, positions)
            checksum += result.score + len(positions) * 17
            checksum += 1 if result.matched else 0
            for index in range(len(positions)):
                checksum += (index + 1) * (positions[index] + 1)
            keep(result)
        if checksum != expected_checksum:
            raise Error("prepared match_into checksum changed during warmup")

    var best_elapsed_ns = 0
    var best_checksum = 0
    for sample in range(_SAMPLES):
        var checksum = 0
        var started = perf_counter_ns()
        for _ in range(iterations):
            var result = workspace.match_into(pattern, candidate, positions)
            checksum += result.score + len(positions) * 17
            checksum += 1 if result.matched else 0
            for index in range(len(positions)):
                checksum += (index + 1) * (positions[index] + 1)
            keep(result)
        var elapsed_ns = perf_counter_ns() - started
        if checksum != expected_checksum:
            raise Error("prepared match_into checksum changed during measurement")
        if sample == 0 or elapsed_ns < best_elapsed_ns:
            best_elapsed_ns = elapsed_ns
            best_checksum = checksum
    _print_result(
        identity,
        "prepared_into",
        len(candidate),
        len(pattern),
        iterations,
        best_elapsed_ns,
        best_checksum,
    )


def _make_long_path(repetitions: Int) -> String:
    var candidate = String()
    for index in range(repetitions):
        candidate += "src/AlphaBeta123/module_"
        candidate += String(index % 10)
        candidate += "/"
    return candidate^


def _measure_incremental_scalar(
    matchers: List[Matcher],
    candidate: String,
    query_scalars: Int,
    iterations: Int,
) raises:
    var expected_checksum = 0
    for matcher in matchers:
        var result = matcher.match(candidate)
        expected_checksum += _checksum(result)
    expected_checksum *= iterations

    for _ in range(_WARMUP_ROUNDS):
        var checksum = 0
        for _ in range(iterations):
            for matcher in matchers:
                var result = matcher.match(candidate)
                checksum += _checksum(result)
                keep(result)
        if checksum != expected_checksum:
            raise Error("incremental scalar checksum changed during warmup")

    var best_elapsed_ns = 0
    var best_checksum = 0
    for sample in range(_SAMPLES):
        var checksum = 0
        var started = perf_counter_ns()
        for _ in range(iterations):
            for matcher in matchers:
                var result = matcher.match(candidate)
                checksum += _checksum(result)
                keep(result)
        var elapsed_ns = perf_counter_ns() - started
        if checksum != expected_checksum:
            raise Error("incremental scalar checksum changed during measurement")
        if sample == 0 or elapsed_ns < best_elapsed_ns:
            best_elapsed_ns = elapsed_ns
            best_checksum = checksum
    _print_result(
        "incremental_path",
        "scalar",
        len(PreparedCandidate(candidate)),
        query_scalars,
        iterations * len(matchers),
        best_elapsed_ns,
        best_checksum,
    )


def _measure_incremental_prepared(
    patterns: List[Pattern],
    candidate: PreparedCandidate,
    query_scalars: Int,
    iterations: Int,
) raises:
    var workspace = MatchWorkspace()
    var expected_checksum = 0
    for pattern in patterns:
        var result = workspace.match(pattern, candidate)
        expected_checksum += _checksum(result)
    expected_checksum *= iterations

    for _ in range(_WARMUP_ROUNDS):
        var checksum = 0
        for _ in range(iterations):
            for pattern in patterns:
                var result = workspace.match(pattern, candidate)
                checksum += _checksum(result)
                keep(result)
        if checksum != expected_checksum:
            raise Error("incremental prepared checksum changed during warmup")

    var best_elapsed_ns = 0
    var best_checksum = 0
    for sample in range(_SAMPLES):
        var checksum = 0
        var started = perf_counter_ns()
        for _ in range(iterations):
            for pattern in patterns:
                var result = workspace.match(pattern, candidate)
                checksum += _checksum(result)
                keep(result)
        var elapsed_ns = perf_counter_ns() - started
        if checksum != expected_checksum:
            raise Error("incremental prepared checksum changed during measurement")
        if sample == 0 or elapsed_ns < best_elapsed_ns:
            best_elapsed_ns = elapsed_ns
            best_checksum = checksum
    _print_result(
        "incremental_path",
        "prepared",
        len(candidate),
        query_scalars,
        iterations * len(patterns),
        best_elapsed_ns,
        best_checksum,
    )


def _run_pair(
    identity: StringSlice,
    query: StringSlice,
    candidate: String,
    iterations: Int,
) raises:
    var pattern = Pattern(query)
    _measure_scalar(
        identity,
        Matcher(pattern, scheme=Scheme.PATH),
        candidate,
        len(pattern),
        iterations,
    )
    _measure_prepared(
        identity,
        pattern,
        PreparedCandidate(candidate, scheme=Scheme.PATH),
        iterations,
    )
    _measure_prepared_score(
        identity,
        pattern,
        PreparedCandidate(candidate, scheme=Scheme.PATH),
        iterations,
    )
    _measure_prepared_into(
        identity,
        pattern,
        PreparedCandidate(candidate, scheme=Scheme.PATH),
        iterations,
    )


def main() raises:
    print(
        "schema=hibana-prepared-benchmark-v2 mojo=1.0.0 ",
        "statistic=minimum_of_5 warmup_rounds=2",
        sep="",
    )
    _run_pair("short_path_match", "hm", String("src/hibana/matcher.mojo"), 50_000)
    _run_pair("long_candidate_match", "sAB1sAB1sAB1sAB1", _make_long_path(48), 500)
    _run_pair(
        "long_query_match",
        "sAB1sAB1sAB1sAB1sAB1sAB1sAB1sAB1",
        _make_long_path(96),
        100,
    )
    _run_pair(
        "long_candidate_nonmatch",
        "zzzzzzzz",
        _make_long_path(96),
        10_000,
    )

    var incremental_candidate = _make_long_path(24)
    var query_strings = ["s", "sa", "sab", "sab1", "sab1s", "sab1sa"]
    var matchers = List[Matcher](capacity=len(query_strings))
    var patterns = List[Pattern](capacity=len(query_strings))
    var total_query_scalars = 0
    for query in query_strings:
        var pattern = Pattern(query, case_mode=CaseMode.IGNORE_ASCII)
        total_query_scalars += len(pattern)
        matchers.append(Matcher(pattern, scheme=Scheme.PATH))
        patterns.append(pattern^)
    _measure_incremental_scalar(
        matchers,
        incremental_candidate,
        total_query_scalars,
        2_000,
    )
    _measure_incremental_prepared(
        patterns,
        PreparedCandidate(incremental_candidate, scheme=Scheme.PATH),
        total_query_scalars,
        2_000,
    )
