"""10,000-candidate all-hit and no-hit fast-score benchmark."""

from hibana import CaseMode, Pattern, Scheme
from hibana.fast import fast_score
from hibana.prepared import MatchWorkspace, PreparedCandidate
from std.benchmark import keep
from std.collections import List
from std.time import perf_counter_ns


comptime _CANDIDATE_COUNT = 10_000
comptime _SAMPLES = 7
comptime _WARMUPS = 3


def _make_candidates() -> List[PreparedCandidate]:
    var candidates = List[PreparedCandidate](capacity=_CANDIDATE_COUNT)
    for index in range(_CANDIDATE_COUNT):
        var text = String("src/AlphaModule/component_")
        text += String(index)
        text += "/render_target.mojo"
        candidates.append(PreparedCandidate(text, scheme=Scheme.PATH))
    return candidates^


def _scan(pattern: Pattern, candidates: List[PreparedCandidate]) -> Int:
    var checksum = 0
    for candidate in candidates:
        var result = fast_score(pattern, candidate)
        checksum += result.score + (1 if result.matched else 0)
    keep(checksum)
    return checksum


def _scan_exact(pattern: Pattern, candidates: List[PreparedCandidate]) -> Int:
    var checksum = 0
    var workspace = MatchWorkspace()
    for candidate in candidates:
        var score = workspace.score(pattern, candidate)
        checksum += score.score + (1 if score.matched else 0)
    keep(checksum)
    return checksum


def _measure(
    variant: StringLiteral,
    name: StringLiteral,
    pattern: Pattern,
    candidates: List[PreparedCandidate],
) raises:
    var expected = _scan(pattern, candidates)
    for _ in range(_WARMUPS):
        if _scan(pattern, candidates) != expected:
            raise Error("fast-score checksum changed during warmup")

    var best_ns = 0
    for sample in range(_SAMPLES):
        var started = perf_counter_ns()
        var checksum = _scan(pattern, candidates)
        var elapsed_ns = perf_counter_ns() - started
        if checksum != expected:
            raise Error("fast-score checksum changed during measurement")
        if sample == 0 or elapsed_ns < best_ns:
            best_ns = elapsed_ns
    print(
        "case=", name,
        " variant=", variant,
        " candidates=", len(candidates),
        " best_elapsed_ns=", best_ns,
        " ns_per_candidate=", Float64(best_ns) / Float64(len(candidates)),
        " checksum=", expected,
        sep="",
    )


def _measure_exact(
    name: StringLiteral,
    pattern: Pattern,
    candidates: List[PreparedCandidate],
) raises:
    var expected = _scan_exact(pattern, candidates)
    for _ in range(_WARMUPS):
        if _scan_exact(pattern, candidates) != expected:
            raise Error("exact checksum changed during warmup")

    var best_ns = 0
    for sample in range(_SAMPLES):
        var started = perf_counter_ns()
        var checksum = _scan_exact(pattern, candidates)
        var elapsed_ns = perf_counter_ns() - started
        if checksum != expected:
            raise Error("exact checksum changed during measurement")
        if sample == 0 or elapsed_ns < best_ns:
            best_ns = elapsed_ns
    print(
        "case=", name,
        " variant=exact",
        " candidates=", len(candidates),
        " best_elapsed_ns=", best_ns,
        " ns_per_candidate=", Float64(best_ns) / Float64(len(candidates)),
        " checksum=", expected,
        sep="",
    )


def main() raises:
    var candidates = _make_candidates()
    var all_hit = Pattern("sAmcrt", case_mode=CaseMode.IGNORE_ASCII)
    var no_hit = Pattern("zzzzzz", case_mode=CaseMode.IGNORE_ASCII)
    _measure(
        "fast",
        "all_hit",
        all_hit,
        candidates,
    )
    _measure(
        "fast",
        "no_hit",
        no_hit,
        candidates,
    )
    _measure_exact("all_hit", all_hit, candidates)
    _measure_exact("no_hit", no_hit, candidates)
