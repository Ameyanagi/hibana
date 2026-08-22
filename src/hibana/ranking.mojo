"""Bounded deterministic ranking over fuzzy-match results."""

from std.collections import List
from std.io import Writable, Writer

from .result import MatchResult


struct _Validated:
    def __init__(out self):
        pass


struct Ranked(Copyable, Equatable, Writable):
    """One retained match tied to its caller-owned input identity."""

    var index: Int
    var score: Int
    var positions: List[Int]

    def __init__(
        out self,
        index: Int,
        score: Int,
        var positions: List[Int],
    ):
        self.index = index
        self.score = score
        self.positions = positions^

    def __eq__(self, other: Self) -> Bool:
        """Return whether every public ranked field is equal."""
        if (
            self.index != other.index
            or self.score != other.score
            or len(self.positions) != len(other.positions)
        ):
            return False
        for position_index in range(len(self.positions)):
            if self.positions[position_index] != other.positions[position_index]:
                return False
        return True

    def __str__(self) -> String:
        var result = String()
        self.write_to(result)
        return result^

    def write_to[W: Writer](self, mut writer: W):
        """Write every public field in a readable constructor-like form."""
        writer.write(
            "Ranked(index=",
            self.index,
            ", score=",
            self.score,
            ", positions=",
            self.positions,
            ")",
        )


def _is_worse(left: Ranked, right: Ranked) -> Bool:
    """Return whether ``left`` loses to ``right`` under public ordering."""
    return left.score < right.score or (
        left.score == right.score and left.index > right.index
    )


def _is_better(left: Ranked, right: Ranked) -> Bool:
    """Return whether ``left`` strictly precedes ``right`` in output."""
    return left.score > right.score or (
        left.score == right.score and left.index < right.index
    )


struct TopK(Copyable):
    """A size-K binary min-heap whose root is the worst retained match.

    Storage remains ``O(K)`` regardless of the number of pushed candidates.
    Lower scores are worse; among equal scores, the larger input index is worse.
    Direct mutation of underscore-prefixed storage is outside the public API;
    ``validate`` is an explicit checkpoint after unusual caller mutation.
    """

    var _k: Int
    var _heap: List[Ranked]

    def __init__(out self, k: Int) raises:
        """Create an empty heap after validating ``k >= 1``."""
        if k < 1:
            raise Error(
                String(
                    "TopK requires k >= 1, got ",
                    k,
                    (
                        "; construct TopK with the number of matches to retain, or use"
                        " Matcher.rank without k to keep every match"
                    ),
                )
            )
        self._k = k
        self._heap = List[Ranked](capacity=k)

    def __init__(out self, k: Int, *, _validated: _Validated):
        """Create an empty heap from an already-validated positive ``k``."""
        self._k = k
        self._heap = List[Ranked](capacity=k)

    @staticmethod
    def _of_validated(k: Int) -> Self:
        """Create an empty heap while trusting that ``k >= 1``."""
        return Self(k, _validated=_Validated())

    def validate(self) raises:
        """Revalidate capacity and heap order after unusual caller mutation."""
        if self._k < 1:
            raise Error(
                String(
                    "TopK requires k >= 1, got ",
                    self._k,
                    (
                        "; construct TopK with the number of matches to retain, or use"
                        " Matcher.rank without k to keep every match"
                    ),
                )
            )
        if len(self._heap) > self._k:
            raise Error(
                String(
                    "TopK retained ",
                    len(self._heap),
                    " results but k is ",
                    self._k,
                    "; truncate the heap or rebuild with TopK(k)",
                )
            )
        for child in range(1, len(self._heap)):
            var parent = (child - 1) // 2
            if _is_worse(self._heap[child], self._heap[parent]):
                raise Error(
                    String(
                        "TopK heap order violated: child ",
                        child,
                        " = ",
                        String(self._heap[child]),
                        " is worse than parent ",
                        parent,
                        " = ",
                        String(self._heap[parent]),
                        "; rebuild the heap or undo the direct mutation",
                    )
                )

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

    def push(mut self, index: Int, var result: MatchResult):
        """Consume and consider one result, ignoring only non-matches.

        ``matched == False`` results are ignored. An empty-pattern or
        zero-atom query result has ``matched == True`` and score zero, so it is
        retained and ranked.
        """
        if not result.matched:
            return
        var positions = List[Int]()
        swap(positions, result.positions)
        var ranked = Ranked(index, result.score, positions^)
        if len(self._heap) < self._k:
            self._heap.append(ranked^)
            self._sift_up(len(self._heap) - 1)
            return
        if _is_better(ranked, self._heap[0]):
            self._heap[0] = ranked^
            self._sift_down(0)

    def len(self) -> Int:
        """Return the number of currently-retained matches."""
        return len(self._heap)

    def take_ranked(var self) -> List[Ranked]:
        """Return results and consume this heap's retained storage.

        Results are sorted by score descending, with ties broken by input index
        ascending, so ordering is stable and deterministic.
        """
        var worst_first = List[Ranked](capacity=len(self._heap))
        while len(self._heap) > 0:
            var final_index = len(self._heap) - 1
            if final_index > 0:
                self._swap(0, final_index)
            var worst = self._heap.pop()
            worst_first.append(worst^)
            if len(self._heap) > 0:
                self._sift_down(0)

        var ranked = List[Ranked](capacity=len(worst_first))
        while len(worst_first) > 0:
            var best = worst_first.pop()
            ranked.append(best^)
        return ranked^
