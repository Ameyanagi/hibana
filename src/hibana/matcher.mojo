"""Prepared fuzzy matcher facade."""

from std.collections import List

from .algorithms.scalar import scalar_match
from .pattern import CaseMode, Pattern, _scalar_values
from .ranking import Ranked, TopK
from .result import MatchResult
from .scoring import Scheme


struct Matcher(Copyable):
    """A reusable mutable value backed by one canonical prepared pattern.

    Construction copies the pattern, so later mutation of the source ``Pattern``
    does not affect this matcher. Direct mutation of underscore-prefixed matcher
    storage changes later matches and is outside the stable public API.

    Scores follow the fixed table in ``docs/scoring.md``. A non-match and an
    empty-pattern match both score zero; inspect ``matched`` to distinguish
    them. Returned positions are Unicode scalar indices, not UTF-8 byte
    offsets.
    """

    var _pattern: Pattern
    var _scheme: Scheme

    def __init__(
        out self,
        query: StringSlice,
        case_mode: CaseMode = CaseMode.SMART_ASCII,
        scheme: Scheme = Scheme.DEFAULT,
    ):
        """Prepare ``query`` and its scoring scheme for repeated matching."""
        self._pattern = Pattern(query, case_mode=case_mode)
        self._scheme = scheme

    def __init__(
        out self,
        pattern: Pattern,
        scheme: Scheme = Scheme.DEFAULT,
    ):
        """Build a matcher from an already prepared pattern."""
        self._pattern = pattern.copy()
        self._scheme = scheme

    def match(self, candidate: StringSlice) -> MatchResult:
        """Decode once and return the best match or canonical non-match."""
        var candidate_scalars = _scalar_values(candidate)
        return scalar_match(self._pattern, candidate_scalars, self._scheme)

    def match_scalars(self, candidate: Span[UInt32, _]) -> MatchResult:
        """Match caller-prepared Unicode scalar values without copying them.

        Positions are Unicode scalar indices into the caller's span, not byte
        offsets — convert via moji for byte-range highlighting. Candidate ASCII
        folding and boundary classification remain part of this shared core.
        """
        return scalar_match(self._pattern, candidate, self._scheme)

    def rank(
        self,
        candidates: Span[String, _],
        k: Int,
    ) raises -> List[Ranked]:
        """Boundedly rank caller-owned candidates by their span positions.

        results sorted by score descending, ties broken by input index ascending — stable and deterministic.
        """
        var top_k = TopK(k)
        for index in range(len(candidates)):
            var result = self.match(candidates[index])
            top_k.push(index, result^)
        return top_k^.take_ranked()
