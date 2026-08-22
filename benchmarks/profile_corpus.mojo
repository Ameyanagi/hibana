"""Long-running compiled workload for macOS CPU and peak-RSS profiling."""

from hibana import CaseMode, Pattern, Scheme
from hibana.hybrid import HybridRankResult, hybrid_rank, hybrid_rank_corpus
from hibana.parallel import ParallelRankPage, rank_corpus_exact, rank_prepared_exact
from hibana.prepared import PreparedCandidate, PreparedCorpus
from std.benchmark import keep
from std.collections import List
from std.sys import argv


comptime _CANDIDATE_COUNT = 100_000


def _hybrid_checksum(result: HybridRankResult) -> Int:
    """Cover the exact count and every visible finalist field."""
    var checksum = result.total_matches * 97 + len(result.rows)
    for row_index in range(len(result.rows)):
        var row_weight = row_index + 1
        checksum += row_weight * (
            result.rows[row_index].index * 17
            + result.rows[row_index].score * 31
            + len(result.rows[row_index].positions) * 43
        )
        for position_index in range(len(result.rows[row_index].positions)):
            checksum += (
                row_weight
                * (position_index + 1)
                * (result.rows[row_index].positions[position_index] + 1)
                * 59
            )
    return checksum


def _exact_checksum(result: ParallelRankPage) -> Int:
    """Cover the exact count and every visible finalist field."""
    var checksum = result.total_matches * 97 + len(result.rows)
    for row_index in range(len(result.rows)):
        var row_weight = row_index + 1
        checksum += row_weight * (
            result.rows[row_index].source_index * 17
            + result.rows[row_index].score * 31
            + len(result.rows[row_index].positions) * 43
        )
        for position_index in range(len(result.rows[row_index].positions)):
            checksum += (
                row_weight
                * (position_index + 1)
                * (result.rows[row_index].positions[position_index] + 1)
                * 59
            )
    return checksum


def _record_checksum(current: Int, mut expected: Int) raises -> Int:
    """Establish one result checksum and reject drift across repetitions."""
    if expected == -1:
        expected = current
    elif current != expected:
        raise Error(
            String(
                "profile result changed across iterations: expected ",
                expected,
                ", got ",
                current,
            )
        )
    return current


def _make_candidates() -> List[PreparedCandidate]:
    var candidates = List[PreparedCandidate](capacity=_CANDIDATE_COUNT)
    for index in range(_CANDIDATE_COUNT):
        var text = String("src/AlphaModule/component_")
        text += String(index)
        text += "/render_target.mojo"
        candidates.append(PreparedCandidate(text, scheme=Scheme.PATH))
    return candidates^


def _make_corpus() raises -> PreparedCorpus:
    var corpus = PreparedCorpus(scheme=Scheme.PATH)
    corpus.reserve(
        candidate_capacity=_CANDIDATE_COUNT,
        scalar_capacity=_CANDIDATE_COUNT * 50,
    )
    for index in range(_CANDIDATE_COUNT):
        var text = String("src/AlphaModule/component_")
        text += String(index)
        text += "/render_target.mojo"
        corpus.append(text)
    return corpus^


def main() raises:
    var arguments = argv()
    var mode = String("hybrid")
    if len(arguments) > 1:
        mode = String(arguments[1])
    if (
        mode != "hybrid"
        and mode != "arena-hybrid"
        and mode != "exact"
        and mode != "arena-exact"
    ):
        raise Error("mode must be hybrid, arena-hybrid, exact, or arena-exact")
    var iterations = 400
    if mode == "exact" or mode == "arena-exact":
        iterations = 40

    var pattern = Pattern("sAmcrt", case_mode=CaseMode.IGNORE_ASCII)
    var aggregate_checksum = 0
    var result_checksum = -1
    if mode == "arena-hybrid" or mode == "arena-exact":
        var corpus = _make_corpus()
        for _ in range(iterations):
            if mode == "arena-exact":
                var page = rank_corpus_exact(corpus, pattern, k=20, grain_size=25_000)
                aggregate_checksum += _record_checksum(
                    _exact_checksum(page), result_checksum
                )
            else:
                var page = hybrid_rank_corpus(
                    pattern, corpus, k=20, shortlist_size=1_000
                )
                aggregate_checksum += _record_checksum(
                    _hybrid_checksum(page), result_checksum
                )
    else:
        var candidates = _make_candidates()
        for _ in range(iterations):
            if mode == "exact":
                var page = rank_prepared_exact(
                    candidates, pattern, k=20, grain_size=25_000
                )
                aggregate_checksum += _record_checksum(
                    _exact_checksum(page), result_checksum
                )
            else:
                var page = hybrid_rank(pattern, candidates, k=20, shortlist_size=1_000)
                aggregate_checksum += _record_checksum(
                    _hybrid_checksum(page), result_checksum
                )
    keep(aggregate_checksum)
    print(
        "mode=",
        mode,
        " iterations=",
        iterations,
        " result_checksum=",
        result_checksum,
        " aggregate_checksum=",
        aggregate_checksum,
        sep="",
    )
