"""Opt-in synchronous parallel ranking over prepared candidates."""

from std.collections import List
from std.math import ceildiv
from std.runtime.asyncrt import TaskGroup, parallelism_level

from .budget import WorkspaceBudget
from .pattern import Pattern
from .prepared import MatchWorkspace, PreparedCandidate, PreparedCorpus


struct ParallelRanked(Copyable, Equatable):
    """One exact prepared-candidate result in deterministic rank order.

    ``source_index`` is the candidate's zero-based position in the input span.
    ``positions`` contains Unicode scalar offsets within that candidate.
    """

    var source_index: Int
    var score: Int
    var positions: List[Int]

    def __init__(
        out self,
        source_index: Int,
        score: Int,
        var positions: List[Int],
    ):
        self.source_index = source_index
        self.score = score
        self.positions = positions^

    def __eq__(self, other: Self) -> Bool:
        if (
            self.source_index != other.source_index
            or self.score != other.score
            or len(self.positions) != len(other.positions)
        ):
            return False
        for index in range(len(self.positions)):
            if self.positions[index] != other.positions[index]:
                return False
        return True


struct ParallelRankPage(Copyable, Equatable):
    """Bounded exact rows plus the untruncated number of matches."""

    var rows: List[ParallelRanked]
    var total_matches: Int

    def __init__(out self):
        self.rows = List[ParallelRanked]()
        self.total_matches = 0

    def __init__(
        out self,
        var rows: List[ParallelRanked],
        total_matches: Int,
    ):
        debug_assert(total_matches >= len(rows))
        self.rows = rows^
        self.total_matches = total_matches

    def __eq__(self, other: Self) -> Bool:
        if self.total_matches != other.total_matches or len(self.rows) != len(
            other.rows
        ):
            return False
        for index in range(len(self.rows)):
            if self.rows[index] != other.rows[index]:
                return False
        return True


@fieldwise_init
struct _ScoredCandidate(Copyable):
    var source_index: Int
    var score: Int


def _is_worse(left: _ScoredCandidate, right: _ScoredCandidate) -> Bool:
    return left.score < right.score or (
        left.score == right.score and left.source_index > right.source_index
    )


def _is_better(left: _ScoredCandidate, right: _ScoredCandidate) -> Bool:
    return left.score > right.score or (
        left.score == right.score and left.source_index < right.source_index
    )


struct _ScoreTopK:
    var _k: Int
    var _heap: List[_ScoredCandidate]

    def __init__(out self, k: Int):
        self._k = k
        self._heap = List[_ScoredCandidate](capacity=k)

    def _swap(mut self, left: Int, right: Int):
        self._heap.swap_elements(left, right)

    def _sift_up(mut self, start: Int):
        var current = start
        while current > 0:
            var parent = (current - 1) // 2
            if not _is_worse(self._heap[current], self._heap[parent]):
                break
            self._swap(current, parent)
            current = parent

    def _sift_down(mut self, start: Int):
        var current = start
        while True:
            var left = current * 2 + 1
            if left >= len(self._heap):
                return
            var worse_child = left
            var right = left + 1
            if right < len(self._heap) and _is_worse(
                self._heap[right], self._heap[left]
            ):
                worse_child = right
            if not _is_worse(self._heap[worse_child], self._heap[current]):
                return
            self._swap(current, worse_child)
            current = worse_child

    def push(mut self, source_index: Int, score: Int):
        var ranked = _ScoredCandidate(source_index, score)
        if len(self._heap) < self._k:
            self._heap.append(ranked^)
            self._sift_up(len(self._heap) - 1)
            return
        if _is_better(ranked, self._heap[0]):
            self._heap[0] = ranked^
            self._sift_down(0)

    def merge_into(self, mut destination: _ScoreTopK):
        for index in range(len(self._heap)):
            destination.push(
                self._heap[index].source_index,
                self._heap[index].score,
            )

    def take_ranked(var self) -> List[_ScoredCandidate]:
        var worst_first = List[_ScoredCandidate](capacity=len(self._heap))
        while len(self._heap) > 0:
            var final_index = len(self._heap) - 1
            if final_index > 0:
                self._swap(0, final_index)
            var worst = self._heap.pop()
            worst_first.append(worst^)
            if len(self._heap) > 0:
                self._sift_down(0)

        var ranked = List[_ScoredCandidate](capacity=len(worst_first))
        while len(worst_first) > 0:
            ranked.append(worst_first.pop())
        return ranked^


struct _ShardState:
    var workspace: MatchWorkspace
    var top_k: _ScoreTopK
    var total_matches: Int
    var error_message: Optional[String]

    def __init__(out self, k: Int, budget: WorkspaceBudget):
        self.workspace = MatchWorkspace(budget=budget)
        self.top_k = _ScoreTopK(k)
        self.total_matches = 0
        self.error_message = Optional[String]()


def _scan_shard(
    pattern: Pattern,
    candidates: Span[PreparedCandidate, _],
    mut state: _ShardState,
    start: Int,
    end: Int,
) raises:
    for source_index in range(start, end):
        var result = state.workspace.score(pattern, candidates[source_index])
        if result.matched:
            state.total_matches += 1
            state.top_k.push(source_index, result.score)


async def _scan_shard_task(
    pattern: Pattern,
    candidates: Span[PreparedCandidate, _],
    state_slot: Span[mut=True, _ShardState, _],
    start: Int,
    end: Int,
):
    try:
        _scan_shard(pattern, candidates, state_slot[0], start, end)
    except error:
        state_slot[0].error_message = String(error)


def _scan_corpus_shard(
    pattern: Pattern,
    corpus: PreparedCorpus,
    mut state: _ShardState,
    start: Int,
    end: Int,
) raises:
    for source_index in range(start, end):
        var result = state.workspace._score_at_unchecked(pattern, corpus, source_index)
        if result.matched:
            state.total_matches += 1
            state.top_k.push(source_index, result.score)


async def _scan_corpus_shard_task(
    pattern: Pattern,
    corpus: PreparedCorpus,
    state_slot: Span[mut=True, _ShardState, _],
    start: Int,
    end: Int,
):
    try:
        _scan_corpus_shard(pattern, corpus, state_slot[0], start, end)
    except error:
        state_slot[0].error_message = String(error)


def _shard_bounds(item_count: Int, shard_count: Int, shard: Int) -> Tuple[Int, Int]:
    var base, extra = divmod(item_count, shard_count)
    var start = shard * base + min(shard, extra)
    var end = start + base + Int(shard < extra)
    return (start, end)


def _rank_prepared_exact_with_worker_limit(
    candidates: Span[PreparedCandidate, _],
    pattern: Pattern,
    k: Int,
    grain_size: Int,
    worker_limit: Int,
    budget: WorkspaceBudget = WorkspaceBudget(),
) raises -> ParallelRankPage:
    """Internal implementation with an injectable maximum worker count."""
    debug_assert(worker_limit >= 1, "worker limit must be positive")
    if k < 1:
        raise Error(String("parallel exact ranking requires k >= 1, got ", k))
    if grain_size < 1:
        raise Error(
            String(
                "parallel exact ranking requires grain_size >= 1, got ",
                grain_size,
            )
        )
    if len(candidates) == 0:
        return ParallelRankPage()

    # A caller may use an effectively unbounded limit. Never reserve more
    # worker or merge storage than the corpus can possibly return.
    var effective_k = min(k, len(candidates))

    var shard_count = min(
        worker_limit,
        ceildiv(len(candidates), grain_size),
    )
    var states = List[_ShardState](capacity=shard_count)
    for _ in range(shard_count):
        states.append(_ShardState(effective_k, budget))

    if shard_count == 1:
        _scan_shard(pattern, candidates, states[0], 0, len(candidates))
    else:
        var state_slots = Span[mut=True](states)
        var group = TaskGroup()
        for shard in range(shard_count):
            var start, end = _shard_bounds(len(candidates), shard_count, shard)
            group.create_task(
                _scan_shard_task(
                    pattern,
                    candidates,
                    state_slots[shard : shard + 1],
                    start,
                    end,
                )
            )
        group.wait()

    # Worker failures are reported synchronously after every task has joined.
    # Fixed shard order makes the selected error deterministic.
    for shard in range(shard_count):
        if states[shard].error_message:
            raise Error(states[shard].error_message.value())
    var total_matches = 0
    var merged = _ScoreTopK(effective_k)
    for shard in range(shard_count):
        total_matches += states[shard].total_matches
        states[shard].top_k.merge_into(merged)

    # Drop retained worker DP buffers before the reconstruction workspace grows.
    states.clear()
    var scored = merged^.take_ranked()
    var rows = List[ParallelRanked](capacity=len(scored))
    var workspace = MatchWorkspace(budget=budget)
    for ranked_index in range(len(scored)):
        var positions = List[Int](capacity=len(pattern))
        var score = workspace.match_into(
            pattern,
            candidates[scored[ranked_index].source_index],
            positions,
        )
        debug_assert(score.matched)
        debug_assert(score.score == scored[ranked_index].score)
        rows.append(
            ParallelRanked(
                scored[ranked_index].source_index,
                score.score,
                positions^,
            )
        )
    return ParallelRankPage(rows^, total_matches)


def rank_prepared_exact(
    candidates: Span[PreparedCandidate, _],
    pattern: Pattern,
    k: Int = 20,
    grain_size: Int = 4_096,
    *,
    budget: WorkspaceBudget = WorkspaceBudget(),
) raises -> ParallelRankPage:
    """Rank prepared candidates exactly with bounded worker-local storage.

    ``source_index`` is the candidate's zero-based input-span index. Scores are
    ordered descending, with smaller input indices winning exact ties.
    ``positions`` are Unicode scalar offsets within the corresponding
    candidate. Every match is counted before ``k`` truncation. Workers allocate
    no match-position results while scanning; each worker-local workspace may
    allocate or grow dynamic-programming scratch, then reuses that capacity.
    Exact positions are reconstructed only for the final rows. ``budget`` caps
    each workspace's retained DP cells; W shards can retain W times its byte
    limit. Worker buffers are freed before final reconstruction. Errors are
    raised after every task joins; no partial or approximate page is returned.

    This synchronous opt-in API uses one flat ``TaskGroup``. Do not call it
    from a Mojo async-runtime task or move its active task group. Use the serial
    fallback for small scans and await a supported nested-task runtime before
    placing this function behind background execution.
    """
    return _rank_prepared_exact_with_worker_limit(
        candidates,
        pattern,
        k,
        grain_size,
        max(parallelism_level(), 1),
        budget,
    )


def _rank_corpus_exact_with_worker_limit(
    corpus: PreparedCorpus,
    pattern: Pattern,
    k: Int,
    grain_size: Int,
    worker_limit: Int,
    budget: WorkspaceBudget = WorkspaceBudget(),
) raises -> ParallelRankPage:
    """Internal arena ranking with an injectable maximum worker count."""
    debug_assert(worker_limit >= 1, "worker limit must be positive")
    if k < 1:
        raise Error(String("parallel corpus ranking requires k >= 1, got ", k))
    if grain_size < 1:
        raise Error(
            String(
                "parallel corpus ranking requires grain_size >= 1, got ",
                grain_size,
            )
        )
    if len(corpus) == 0:
        return ParallelRankPage()

    var effective_k = min(k, len(corpus))
    var shard_count = min(worker_limit, ceildiv(len(corpus), grain_size))
    var states = List[_ShardState](capacity=shard_count)
    for _ in range(shard_count):
        states.append(_ShardState(effective_k, budget))

    if shard_count == 1:
        _scan_corpus_shard(pattern, corpus, states[0], 0, len(corpus))
    else:
        var state_slots = Span[mut=True](states)
        var group = TaskGroup()
        for shard in range(shard_count):
            var start, end = _shard_bounds(len(corpus), shard_count, shard)
            group.create_task(
                _scan_corpus_shard_task(
                    pattern,
                    corpus,
                    state_slots[shard : shard + 1],
                    start,
                    end,
                )
            )
        group.wait()

    # Worker failures are reported synchronously after every task has joined.
    # Fixed shard order makes the selected error deterministic.
    for shard in range(shard_count):
        if states[shard].error_message:
            raise Error(states[shard].error_message.value())
    var total_matches = 0
    var merged = _ScoreTopK(effective_k)
    for shard in range(shard_count):
        total_matches += states[shard].total_matches
        states[shard].top_k.merge_into(merged)

    # Drop retained worker DP buffers before the reconstruction workspace grows.
    states.clear()
    var scored = merged^.take_ranked()
    var rows = List[ParallelRanked](capacity=len(scored))
    var workspace = MatchWorkspace(budget=budget)
    for ranked_index in range(len(scored)):
        var positions = List[Int](capacity=len(pattern))
        var score = workspace._match_into_at_unchecked(
            pattern,
            corpus,
            scored[ranked_index].source_index,
            positions,
        )
        debug_assert(score.matched)
        debug_assert(score.score == scored[ranked_index].score)
        rows.append(
            ParallelRanked(
                scored[ranked_index].source_index,
                score.score,
                positions^,
            )
        )
    return ParallelRankPage(rows^, total_matches)


def rank_corpus_exact(
    corpus: PreparedCorpus,
    pattern: Pattern,
    k: Int = 20,
    grain_size: Int = 4_096,
    *,
    budget: WorkspaceBudget = WorkspaceBudget(),
) raises -> ParallelRankPage:
    """Rank an arena-backed corpus exactly and deterministically.

    This has the same score, position, total-count, tie, and synchronous task
    contract as ``rank_prepared_exact`` while avoiding per-candidate retained
    list ownership. Source strings remain caller-owned and are addressed by
    each row's ``source_index``.
    """
    return _rank_corpus_exact_with_worker_limit(
        corpus,
        pattern,
        k,
        grain_size,
        max(parallelism_level(), 1),
        budget,
    )
