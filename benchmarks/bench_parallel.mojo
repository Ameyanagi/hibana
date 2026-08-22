"""Serial-versus-parallel exact prepared-ranking benchmark."""

from hibana import Pattern, Scheme
from hibana.parallel import ParallelRankPage, rank_corpus_exact, rank_prepared_exact
from hibana.prepared import PreparedCandidate, PreparedCorpus
from std.benchmark import keep
from std.collections import List
from std.runtime.asyncrt import parallelism_level
from std.time import perf_counter_ns


comptime _SAMPLES = 31
comptime _WARMUPS = 3


def _candidates(count: Int) -> List[PreparedCandidate]:
    var candidates = List[PreparedCandidate](capacity=count)
    for index in range(count):
        candidates.append(
            PreparedCandidate(
                String(
                    "workspace/pkg-",
                    index % 97,
                    "/src/component-",
                    index,
                    "/view.mojo",
                ),
                scheme=Scheme.PATH,
            )
        )
    return candidates^


def _corpus(count: Int) raises -> PreparedCorpus:
    var corpus = PreparedCorpus(scheme=Scheme.PATH)
    corpus.reserve(candidate_capacity=count, scalar_capacity=count * 50)
    for index in range(count):
        corpus.append(
            String(
                "workspace/pkg-",
                index % 97,
                "/src/component-",
                index,
                "/view.mojo",
            )
        )
    return corpus^


def _checksum(page: ParallelRankPage) -> Int:
    var checksum = page.total_matches * 17 + len(page.rows)
    for row in page.rows:
        checksum += row.source_index + row.score + len(row.positions) * 31
        for position in row.positions:
            checksum += position
    return checksum


def _scan(
    candidates: Span[PreparedCandidate, _],
    pattern: Pattern,
    grain_size: Int,
) raises -> Int:
    var page = rank_prepared_exact(candidates, pattern, k=20, grain_size=grain_size)
    var checksum = _checksum(page)
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


def _measure(
    candidates: Span[PreparedCandidate, _],
    pattern: Pattern,
    grain_size: Int,
    expected_checksum: Int,
) raises -> Tuple[Int, Int]:
    for _ in range(_WARMUPS):
        if _scan(candidates, pattern, grain_size) != expected_checksum:
            raise Error("parallel exact checksum changed during warmup")

    var timings = List[Int](capacity=_SAMPLES)
    for _ in range(_SAMPLES):
        var started = perf_counter_ns()
        var checksum = _scan(candidates, pattern, grain_size)
        var elapsed = perf_counter_ns() - started
        if checksum != expected_checksum:
            raise Error("parallel exact checksum changed during measurement")
        timings.append(elapsed)
    _sort_timings(timings)
    # Nearest-rank percentiles: ranks 16 and 30 for 31 sorted samples.
    return (timings[15], timings[29])


def _scan_corpus(
    corpus: PreparedCorpus,
    pattern: Pattern,
    grain_size: Int,
) raises -> Int:
    var page = rank_corpus_exact(corpus, pattern, k=20, grain_size=grain_size)
    var checksum = _checksum(page)
    keep(checksum)
    return checksum


def _measure_corpus(
    corpus: PreparedCorpus,
    pattern: Pattern,
    grain_size: Int,
    expected_checksum: Int,
) raises -> Tuple[Int, Int]:
    for _ in range(_WARMUPS):
        if _scan_corpus(corpus, pattern, grain_size) != expected_checksum:
            raise Error("parallel exact corpus checksum changed during warmup")

    var timings = List[Int](capacity=_SAMPLES)
    for _ in range(_SAMPLES):
        var started = perf_counter_ns()
        var checksum = _scan_corpus(corpus, pattern, grain_size)
        var elapsed = perf_counter_ns() - started
        if checksum != expected_checksum:
            raise Error("parallel exact corpus checksum changed during measurement")
        timings.append(elapsed)
    _sort_timings(timings)
    return (timings[15], timings[29])


def _run(count: Int) raises:
    var candidates = _candidates(count)
    var pattern = Pattern("pkgsrcview")
    var serial = rank_prepared_exact(candidates, pattern, k=20, grain_size=count + 1)
    var parallel = rank_prepared_exact(candidates, pattern, k=20)
    if serial != parallel:
        raise Error("parallel exact benchmark result differs from serial")
    var expected_checksum = _checksum(serial)

    var serial_ns = _measure(candidates, pattern, count + 1, expected_checksum)
    var parallel_ns = _measure(candidates, pattern, 4_096, expected_checksum)
    print(
        "BENCH hibana parallel_exact storage=owned candidates=",
        count,
        " workers=",
        parallelism_level(),
        " samples=31 statistic=nearest-rank",
        " serial_p50_ns=",
        serial_ns[0],
        " serial_p95_ns=",
        serial_ns[1],
        " parallel_p50_ns=",
        parallel_ns[0],
        " parallel_p95_ns=",
        parallel_ns[1],
        " p50_speedup=",
        Float64(serial_ns[0]) / Float64(parallel_ns[0]),
        " p95_speedup=",
        Float64(serial_ns[1]) / Float64(parallel_ns[1]),
        " checksum=",
        expected_checksum,
        sep="",
    )


def _run_corpus(count: Int) raises:
    var corpus = _corpus(count)
    var pattern = Pattern("pkgsrcview")
    var serial = rank_corpus_exact(corpus, pattern, k=20, grain_size=count + 1)
    var parallel = rank_corpus_exact(corpus, pattern, k=20)
    if serial != parallel:
        raise Error("parallel exact arena result differs from serial")
    var expected_checksum = _checksum(serial)

    var serial_ns = _measure_corpus(corpus, pattern, count + 1, expected_checksum)
    var parallel_ns = _measure_corpus(corpus, pattern, 4_096, expected_checksum)
    print(
        "BENCH hibana parallel_exact storage=arena candidates=",
        count,
        " scalars=",
        corpus.scalar_count(),
        " estimated_payload_bytes=",
        corpus.estimated_payload_bytes(),
        " workers=",
        parallelism_level(),
        " samples=31 statistic=nearest-rank",
        " serial_p50_ns=",
        serial_ns[0],
        " serial_p95_ns=",
        serial_ns[1],
        " parallel_p50_ns=",
        parallel_ns[0],
        " parallel_p95_ns=",
        parallel_ns[1],
        " p50_speedup=",
        Float64(serial_ns[0]) / Float64(parallel_ns[0]),
        " p95_speedup=",
        Float64(serial_ns[1]) / Float64(parallel_ns[1]),
        " checksum=",
        expected_checksum,
        sep="",
    )


def main() raises:
    print(
        "BENCH_HEADER hibana parallel_exact mojo=1.0.0 samples=31 ",
        "warmup=3 statistic=nearest-rank-p50-p95 k=20",
        sep="",
    )
    _run(10_000)
    _run(100_000)
    _run_corpus(10_000)
    _run_corpus(100_000)
