"""Prepared hybrid ranking benchmark at 10,000 and 100,000 candidates."""

from hibana import CaseMode, Pattern, Scheme
from hibana.hybrid import HybridRankResult, hybrid_rank, hybrid_rank_corpus
from hibana.prepared import PreparedCandidate, PreparedCorpus
from std.benchmark import keep
from std.collections import List
from std.time import perf_counter_ns


comptime _SAMPLES = 31
comptime _WARMUPS = 3


def _make_candidates(count: Int) -> List[PreparedCandidate]:
    var candidates = List[PreparedCandidate](capacity=count)
    for index in range(count):
        var text = String("src/AlphaModule/component_")
        text += String(index)
        text += "/render_target.mojo"
        candidates.append(PreparedCandidate(text, scheme=Scheme.PATH))
    return candidates^


def _make_corpus(count: Int) raises -> PreparedCorpus:
    var corpus = PreparedCorpus(scheme=Scheme.PATH)
    # These generated paths are 45-50 scalars at this benchmark's sizes.
    corpus.reserve(candidate_capacity=count, scalar_capacity=count * 50)
    for index in range(count):
        var text = String("src/AlphaModule/component_")
        text += String(index)
        text += "/render_target.mojo"
        corpus.append(text)
    return corpus^


def _checksum(result: HybridRankResult) -> Int:
    var checksum = result.total_matches * 17 + len(result.rows)
    for row in result.rows:
        checksum += row.index + row.score + len(row.positions) * 31
        for position in row.positions:
            checksum += position
    return checksum


def _scan(pattern: Pattern, candidates: List[PreparedCandidate]) raises -> Int:
    var result = hybrid_rank(pattern, candidates, k=20, shortlist_size=1_000)
    var checksum = _checksum(result)
    keep(checksum)
    return checksum


def _sort_timings(mut values: List[Int]):
    # Thirty-one samples make this benchmark-only insertion sort negligible.
    for index in range(1, len(values)):
        var value = values[index]
        var destination = index
        while destination > 0 and values[destination - 1] > value:
            values[destination] = values[destination - 1]
            destination -= 1
        values[destination] = value


def _measure_owned(
    name: StringLiteral,
    pattern: Pattern,
    candidates: List[PreparedCandidate],
) raises:
    var expected = _scan(pattern, candidates)
    for _ in range(_WARMUPS):
        if _scan(pattern, candidates) != expected:
            raise Error("hybrid checksum changed during warmup")

    var timings = List[Int](capacity=_SAMPLES)
    for _ in range(_SAMPLES):
        var started = perf_counter_ns()
        var checksum = _scan(pattern, candidates)
        var elapsed_ns = perf_counter_ns() - started
        if checksum != expected:
            raise Error("hybrid checksum changed during measurement")
        timings.append(elapsed_ns)
    _sort_timings(timings)
    # Nearest-rank percentiles: ranks 16 and 30 for 31 sorted samples.
    var p50_ns = timings[15]
    var p95_ns = timings[29]
    print(
        "storage=owned case=",
        name,
        " candidates=",
        len(candidates),
        " shortlist=1000 k=20",
        " samples=31 statistic=nearest-rank",
        " p50_ns=",
        p50_ns,
        " p95_ns=",
        p95_ns,
        " p50_ns_per_candidate=",
        Float64(p50_ns) / Float64(len(candidates)),
        " p95_ns_per_candidate=",
        Float64(p95_ns) / Float64(len(candidates)),
        " checksum=",
        expected,
        sep="",
    )


def _scan_corpus(pattern: Pattern, corpus: PreparedCorpus) raises -> Int:
    var result = hybrid_rank_corpus(pattern, corpus, k=20, shortlist_size=1_000)
    var checksum = _checksum(result)
    keep(checksum)
    return checksum


def _measure_corpus(
    name: StringLiteral,
    pattern: Pattern,
    corpus: PreparedCorpus,
) raises:
    var expected = _scan_corpus(pattern, corpus)
    for _ in range(_WARMUPS):
        if _scan_corpus(pattern, corpus) != expected:
            raise Error("corpus hybrid checksum changed during warmup")

    var timings = List[Int](capacity=_SAMPLES)
    for _ in range(_SAMPLES):
        var started = perf_counter_ns()
        var checksum = _scan_corpus(pattern, corpus)
        var elapsed_ns = perf_counter_ns() - started
        if checksum != expected:
            raise Error("corpus hybrid checksum changed during measurement")
        timings.append(elapsed_ns)
    _sort_timings(timings)
    var p50_ns = timings[15]
    var p95_ns = timings[29]
    print(
        "storage=arena case=",
        name,
        " candidates=",
        len(corpus),
        " scalars=",
        corpus.scalar_count(),
        " estimated_payload_bytes=",
        corpus.estimated_payload_bytes(),
        " shortlist=1000 k=20",
        " samples=31 statistic=nearest-rank",
        " p50_ns=",
        p50_ns,
        " p95_ns=",
        p95_ns,
        " p50_ns_per_candidate=",
        Float64(p50_ns) / Float64(len(corpus)),
        " p95_ns_per_candidate=",
        Float64(p95_ns) / Float64(len(corpus)),
        " checksum=",
        expected,
        sep="",
    )


def _run_size(count: Int) raises:
    var candidates = _make_candidates(count)
    _measure_owned(
        "all_hit",
        Pattern("sAmcrt", case_mode=CaseMode.IGNORE_ASCII),
        candidates,
    )
    _measure_owned(
        "no_hit",
        Pattern("zzzzzz", case_mode=CaseMode.IGNORE_ASCII),
        candidates,
    )
    var corpus = _make_corpus(count)
    _measure_corpus(
        "all_hit",
        Pattern("sAmcrt", case_mode=CaseMode.IGNORE_ASCII),
        corpus,
    )
    _measure_corpus(
        "no_hit",
        Pattern("zzzzzz", case_mode=CaseMode.IGNORE_ASCII),
        corpus,
    )


def main() raises:
    print(
        "BENCH_HEADER hibana hybrid mojo=1.0.0 samples=31 warmup=3 ",
        "statistic=nearest-rank-p50-p95 shortlist=1000 k=20",
        sep="",
    )
    _run_size(10_000)
    _run_size(100_000)
