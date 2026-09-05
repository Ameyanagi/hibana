"""Allocation-bounded approximate ranking over prepared candidates."""

from std.collections import List

from .budget import WorkspaceBudget
from .fast import _fast_score_at_unchecked, fast_score
from .pattern import Pattern
from .prepared import MatchWorkspace, PreparedCandidate, PreparedCorpus
from .ranking import Ranked


struct HybridRankResult(Copyable):
    """Hybrid rows plus the exact number of fuzzy-match members.

    ``total_matches`` is exact because the linear first stage preserves
    subsequence membership. Every retained row has an exact score and exact
    positions. The selected row set is approximate because candidates outside
    the fast top-B shortlist are not exact-reranked.
    """

    var total_matches: Int
    var rows: List[Ranked]

    def __init__(
        out self,
        total_matches: Int,
        var rows: List[Ranked],
    ):
        self.total_matches = total_matches
        self.rows = rows^


struct _ScoredIndex(Copyable, ImplicitlyCopyable):
    var index: Int
    var score: Int

    def __init__(out self, index: Int, score: Int):
        self.index = index
        self.score = score


def _is_worse(left: _ScoredIndex, right: _ScoredIndex) -> Bool:
    return left.score < right.score or (
        left.score == right.score and left.index > right.index
    )


def _is_better(left: _ScoredIndex, right: _ScoredIndex) -> Bool:
    return left.score > right.score or (
        left.score == right.score and left.index < right.index
    )


struct _ScoreTopK:
    """Internal root-worst heap with score/index-only bounded storage."""

    var _limit: Int
    var _heap: List[_ScoredIndex]

    def __init__(out self, limit: Int):
        debug_assert(limit >= 1, "hybrid argument validation guarantees limit")
        self._limit = limit
        self._heap = List[_ScoredIndex](capacity=limit)

    def _swap(mut self, left: Int, right: Int):
        self._heap.swap_elements(left, right)

    def _sift_up(mut self, start: Int):
        var current = start
        while current > 0:
            var parent = (current - 1) // 2
            if not _is_worse(self._heap[current], self._heap[parent]):
                return
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

    def push(mut self, index: Int, score: Int):
        var entry = _ScoredIndex(index, score)
        if len(self._heap) < self._limit:
            self._heap.append(entry)
            self._sift_up(len(self._heap) - 1)
            return
        if _is_better(entry, self._heap[0]):
            self._heap[0] = entry
            self._sift_down(0)

    def take_entries(var self) -> List[_ScoredIndex]:
        """Consume and return retained entries in unspecified heap order."""
        var entries = List[_ScoredIndex]()
        swap(entries, self._heap)
        return entries^

    def take_best(var self) -> List[_ScoredIndex]:
        """Consume and return score-descending, index-ascending entries."""
        var worst_first = List[_ScoredIndex](capacity=len(self._heap))
        while len(self._heap) > 0:
            var final_index = len(self._heap) - 1
            if final_index > 0:
                self._swap(0, final_index)
            var worst = self._heap.pop()
            worst_first.append(worst)
            if len(self._heap) > 0:
                self._sift_down(0)

        var best_first = List[_ScoredIndex](capacity=len(worst_first))
        while len(worst_first) > 0:
            best_first.append(worst_first.pop())
        return best_first^


def hybrid_rank(
    pattern: Pattern,
    candidates: Span[PreparedCandidate, _],
    *,
    k: Int,
    shortlist_size: Int = 1_000,
    budget: WorkspaceBudget = WorkspaceBudget(),
) raises -> HybridRankResult:
    """Rank prepared candidates with bounded allocation and exact finalists.

    All candidates receive Hibana's allocation-free linear fast score. Every
    fuzzy match increments ``total_matches`` and competes for a deterministic
    top-B shortlist. Only those B candidates run the exact dynamic program;
    only the final K run position reconstruction through ``match_into``.

    Memory is ``O(B + K*P + P*Cmax)`` beyond caller-owned candidates: the
    score heaps contain no position lists, and one exact workspace retains
    scratch for the largest shortlisted candidate. Ties prefer lower original
    input indices at both stages.

    Results are not guaranteed to equal a full exact corpus ranking. The fast
    stage may exclude a candidate whose exact score would enter the final K.
    Increase ``shortlist_size`` to trade exact work for recall; setting it to
    at least the number of exact members makes the selected rows exact. Both
    limits are capped to the corpus size before checking that the effective
    shortlist can contain every requested row.
    """
    if k < 1:
        raise Error(String("hybrid_rank requires k >= 1, got ", k))
    if shortlist_size < 1:
        raise Error(
            String(
                "hybrid_rank requires shortlist_size >= 1, got ",
                shortlist_size,
            )
        )
    if len(candidates) == 0:
        return HybridRankResult(0, List[Ranked]())

    var requested_rows = min(k, len(candidates))
    var effective_shortlist = min(shortlist_size, len(candidates))
    if effective_shortlist < requested_rows:
        raise Error(
            String(
                (
                    "hybrid_rank requires the corpus-bounded shortlist to cover "
                    "the corpus-bounded row limit; got effective shortlist="
                ),
                effective_shortlist,
                ", effective rows=",
                requested_rows,
                " (shortlist_size=",
                shortlist_size,
                ", k=",
                k,
                ", candidates=",
                len(candidates),
                ")",
            )
        )

    var fast_top = _ScoreTopK(effective_shortlist)
    var total_matches = 0
    for index in range(len(candidates)):
        var score = fast_score(pattern, candidates[index])
        if not score.matched:
            continue
        total_matches += 1
        fast_top.push(index, score.score)

    var shortlist = fast_top^.take_entries()
    var effective_k = max(1, min(k, len(shortlist)))
    var exact_top = _ScoreTopK(effective_k)
    var workspace = MatchWorkspace(budget=budget)
    for entry in shortlist:
        var score = workspace.score(pattern, candidates[entry.index])
        debug_assert(score.matched, "fast and exact membership must agree")
        exact_top.push(entry.index, score.score)

    var finalists = exact_top^.take_best()
    var rows = List[Ranked](capacity=len(finalists))
    for finalist in finalists:
        var positions = List[Int](capacity=len(pattern))
        var score = workspace.match_into(pattern, candidates[finalist.index], positions)
        debug_assert(score.matched, "exact finalist must remain a match")
        debug_assert(score.score == finalist.score, "exact finalist score changed")
        rows.append(Ranked(finalist.index, score.score, positions^))

    return HybridRankResult(total_matches, rows^)


def hybrid_rank_corpus(
    pattern: Pattern,
    corpus: PreparedCorpus,
    *,
    k: Int,
    shortlist_size: Int = 1_000,
    budget: WorkspaceBudget = WorkspaceBudget(),
) raises -> HybridRankResult:
    """Rank an arena-backed corpus with the same hybrid contract.

    Membership totals, finalist scores, positions, and tie ordering are exact.
    Candidate selection remains approximate because the exact dynamic program
    is limited to the deterministic fast top-B shortlist. Compared with
    ``hybrid_rank``, the retained corpus replaces per-candidate list ownership
    with contiguous scalar and bonus arenas.
    """
    if k < 1:
        raise Error(String("hybrid_rank_corpus requires k >= 1, got ", k))
    if shortlist_size < 1:
        raise Error(
            String(
                "hybrid_rank_corpus requires shortlist_size >= 1, got ",
                shortlist_size,
            )
        )
    if len(corpus) == 0:
        return HybridRankResult(0, List[Ranked]())

    var requested_rows = min(k, len(corpus))
    var effective_shortlist = min(shortlist_size, len(corpus))
    if effective_shortlist < requested_rows:
        raise Error(
            String(
                (
                    "hybrid_rank_corpus requires the corpus-bounded shortlist "
                    "to cover the corpus-bounded row limit; got effective "
                    "shortlist="
                ),
                effective_shortlist,
                ", effective rows=",
                requested_rows,
            )
        )

    var fast_top = _ScoreTopK(effective_shortlist)
    var total_matches = 0
    for index in range(len(corpus)):
        var score = _fast_score_at_unchecked(pattern, corpus, index)
        if not score.matched:
            continue
        total_matches += 1
        fast_top.push(index, score.score)

    var shortlist = fast_top^.take_entries()
    var effective_k = max(1, min(k, len(shortlist)))
    var exact_top = _ScoreTopK(effective_k)
    var workspace = MatchWorkspace(budget=budget)
    for entry in shortlist:
        var score = workspace._score_at_unchecked(pattern, corpus, entry.index)
        debug_assert(score.matched, "fast and exact membership must agree")
        exact_top.push(entry.index, score.score)

    var finalists = exact_top^.take_best()
    var rows = List[Ranked](capacity=len(finalists))
    for finalist in finalists:
        var positions = List[Int](capacity=len(pattern))
        var score = workspace._match_into_at_unchecked(
            pattern, corpus, finalist.index, positions
        )
        debug_assert(score.matched, "exact finalist must remain a match")
        debug_assert(score.score == finalist.score, "exact finalist score changed")
        rows.append(Ranked(finalist.index, score.score, positions^))

    return HybridRankResult(total_matches, rows^)
