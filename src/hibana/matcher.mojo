"""Prepared fuzzy matcher facade."""

from std.collections import List

from .algorithms.scalar import scalar_match
from .budget import WorkspaceBudget
from .pattern import CaseMode, Pattern, _scalar_values
from .ranking import Ranked, TopK
from .result import MatchResult
from .scoring import Scheme


def _is_query_whitespace(scalar: UInt32) -> Bool:
    return (
        scalar == UInt32(32)
        or scalar == UInt32(9)
        or scalar == UInt32(10)
        or scalar == UInt32(13)
    )


def _query_atoms(query: StringSlice, case_mode: CaseMode) -> List[Pattern]:
    var atoms = List[Pattern]()
    var word_start = 0
    var byte_offset = 0
    for codepoint in query.codepoints():
        var next_byte_offset = byte_offset + codepoint.utf8_byte_length()
        if _is_query_whitespace(codepoint.to_u32()):
            if word_start < byte_offset:
                atoms.append(
                    Pattern(
                        query[byte=word_start:byte_offset],
                        case_mode=case_mode,
                    )
                )
            word_start = next_byte_offset
        byte_offset = next_byte_offset
    if word_start < byte_offset:
        atoms.append(Pattern(query[byte=word_start:byte_offset], case_mode=case_mode))
    return atoms^


struct Matcher(Copyable):
    """A reusable fuzzy matcher backed by prepared query atoms.

    A string query splits on runs of ASCII space, tab, LF, and CR. Every atom
    must fuzzy-match the candidate; smart case is decided per atom, scores are
    summed, and positions are merged in strictly increasing order. Constructing
    from ``Pattern`` preserves one literal atom, including whitespace. Pattern
    construction is copied, so later source mutation does not affect this
    matcher. Direct mutation of underscore-prefixed storage is outside the
    stable public API.

    Scores follow the fixed table in ``docs/scoring.md``. A non-match and an
    empty or all-whitespace query match both score zero; inspect ``matched`` to
    distinguish them. Returned positions are Unicode scalar indices, not UTF-8
    byte offsets. ``budget`` limits each atom's DP table; exact execution raises
    on unrepresentable cell/byte sizes or an exceeded budget. It never falls back
    to approximate matching.
    """

    var _atoms: List[Pattern]
    var _scheme: Scheme
    var _budget: WorkspaceBudget

    def __init__(
        out self,
        query: StringSlice,
        case_mode: CaseMode = CaseMode.SMART_ASCII,
        scheme: Scheme = Scheme.DEFAULT,
        *,
        budget: WorkspaceBudget = WorkspaceBudget(),
    ):
        """Split and prepare a whitespace-AND query for repeated matching."""
        self._atoms = _query_atoms(query, case_mode)
        self._scheme = scheme
        self._budget = budget

    def __init__(
        out self,
        pattern: Pattern,
        scheme: Scheme = Scheme.DEFAULT,
        *,
        budget: WorkspaceBudget = WorkspaceBudget(),
    ):
        """Build a single-atom matcher without splitting pattern whitespace."""
        self._atoms = List[Pattern]()
        self._atoms.append(pattern.copy())
        self._scheme = scheme
        self._budget = budget

    def match(self, candidate: StringSlice) raises -> MatchResult:
        """Decode once and AND every prepared atom over the same scalars."""
        var candidate_scalars = _scalar_values(candidate)
        return self.match_scalars(candidate_scalars)

    def match_scalars(self, candidate: Span[UInt32, _]) raises -> MatchResult:
        """AND every atom over caller-prepared scalars without copying them.

        Positions are Unicode scalar indices into the caller's span, not byte
        offsets — convert via moji for byte-range highlighting. Candidate ASCII
        folding and boundary classification remain part of this shared core.
        """
        if len(self._atoms) == 0:
            return MatchResult(True, 0, List[Int]())
        if len(self._atoms) == 1:
            return scalar_match(self._atoms[0], candidate, self._scheme, self._budget)

        var score = 0
        var selected = List[Bool](length=len(candidate), fill=False)
        for atom in self._atoms:
            var result = scalar_match(atom, candidate, self._scheme, self._budget)
            if not result.matched:
                return MatchResult.no_match()
            score += result.score
            for position in result.positions:
                selected[position] = True

        var positions = List[Int]()
        for position in range(len(selected)):
            if selected[position]:
                positions.append(position)
        return MatchResult(True, score, positions^)

    def _rank_with_top_k(
        self,
        candidates: Span[String, _],
        var top_k: TopK,
    ) raises -> List[Ranked]:
        for index in range(len(candidates)):
            var result = self.match(candidates[index])
            top_k.push(index, result^)
        return top_k^.take_ranked()

    def _rank_all(self, candidates: Span[String, _]) raises -> List[Ranked]:
        if len(candidates) == 0:
            return List[Ranked]()
        return self._rank_with_top_k(candidates, TopK._of_validated(len(candidates)))

    def rank(self, candidates: Span[String, _]) raises -> List[Ranked]:
        """Return every match by descending score, then ascending index.

        Pass ``k`` to retain only the best bounded subset. Exact DP raises if
        its dimensions overflow or exceed this matcher's workspace budget.
        """
        return self._rank_all(candidates)

    def rank(
        self,
        candidates: Span[String, _],
        k: Int,
    ) raises -> List[Ranked]:
        """Return at most ``k`` matches by descending score, then index.

        ``k`` must be at least one. Omit it for every match. Internal heap
        capacity is capped at the number of candidates.
        """
        if k < 1:
            raise Error(
                String(
                    "rank requires k >= 1, got ",
                    k,
                    "; omit k to rank every match",
                )
            )
        if len(candidates) == 0:
            return List[Ranked]()
        return self._rank_with_top_k(
            candidates, TopK._of_validated(min(k, len(candidates)))
        )

    def rank(self, candidates: List[String]) raises -> List[Ranked]:
        """Return every match from an owned list or bare list literal."""
        return self._rank_all(candidates)

    def rank(self, candidates: List[String], k: Int) raises -> List[Ranked]:
        """Return at most ``k`` matches from an owned list or list literal."""
        if k < 1:
            raise Error(
                String(
                    "rank requires k >= 1, got ",
                    k,
                    "; omit k to rank every match",
                )
            )
        if len(candidates) == 0:
            return List[Ranked]()
        return self._rank_with_top_k(
            candidates, TopK._of_validated(min(k, len(candidates)))
        )
