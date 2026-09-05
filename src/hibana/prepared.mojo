"""Advanced prepared-candidate matching with reusable workspace storage."""

from std.collections import List

from .algorithms.scalar import (
    _is_subsequence_match,
    _scalar_match_core,
    _scalar_match_into_core,
    _scalar_score_core,
)
from .budget import WorkspaceBudget
from .pattern import Pattern, _scalar_values
from .result import MatchResult, MatchScore
from .scoring import (
    _WHITESPACE,
    Scheme,
    _bonus,
    _candidate_bonuses,
    _scheme_char_class,
)


struct PreparedCandidate(Copyable, Sized):
    """Owned candidate scalars and scoring context prepared once.

    Use this advanced value when the same candidate is matched against many
    queries, such as an interactive finder. Construction decodes Unicode and
    classifies boundary bonuses once. Positions returned by a
    ``MatchWorkspace`` remain indices into the original Unicode scalar list.

    The scoring scheme is fixed at construction because it changes boundary
    bonuses. Direct mutation of underscore-prefixed storage is outside the
    public contract; ``validate`` is an explicit checkpoint after unusual
    mutation.
    """

    var _raw_scalars: List[UInt32]
    var _bonuses: List[Int]
    var _scheme: Scheme

    def __init__(
        out self,
        text: StringSlice,
        scheme: Scheme = Scheme.DEFAULT,
    ):
        var raw_scalars = _scalar_values(text)
        var bonuses = _candidate_bonuses(raw_scalars, scheme)
        self._raw_scalars = raw_scalars^
        self._bonuses = bonuses^
        self._scheme = scheme

    def __len__(self) -> Int:
        """Return the candidate's Unicode scalar count."""
        return len(self._raw_scalars)

    def scheme(self) -> Scheme:
        """Return the boundary-scoring scheme prepared with this candidate."""
        return self._scheme

    def validate(self) raises:
        """Revalidate parallel storage after unusual caller mutation."""
        if self._scheme != Scheme.DEFAULT and self._scheme != Scheme.PATH:
            raise Error(
                String(
                    (
                        "PreparedCandidate scheme must be Scheme.DEFAULT or"
                        " Scheme.PATH; got "
                    ),
                    self._scheme._value,
                    "; reconstruct the candidate with a supported scheme",
                )
            )
        if len(self._bonuses) != len(self._raw_scalars):
            raise Error(
                String(
                    "PreparedCandidate bonus count must equal raw scalar count ",
                    len(self._raw_scalars),
                    "; got ",
                    len(self._bonuses),
                )
            )
        for index in range(len(self._raw_scalars)):
            var scalar = self._raw_scalars[index]
            if scalar > UInt32(0x10FFFF) or (
                scalar >= UInt32(0xD800) and scalar <= UInt32(0xDFFF)
            ):
                raise Error(
                    String(
                        "PreparedCandidate scalar at index ",
                        index,
                        " must be a Unicode scalar value; got ",
                        scalar,
                        "; reconstruct the candidate from valid text",
                    )
                )
        var expected_bonuses = _candidate_bonuses(self._raw_scalars, self._scheme)
        for index in range(len(self._bonuses)):
            if self._bonuses[index] != expected_bonuses[index]:
                raise Error(
                    String(
                        "PreparedCandidate bonus at index ",
                        index,
                        " must equal scheme-derived value ",
                        expected_bonuses[index],
                        "; got ",
                        self._bonuses[index],
                        "; reconstruct the candidate to restore prepared storage",
                    )
                )


struct PreparedCorpus(Copyable, Sized):
    """Arena-backed candidates for broad repeated corpus scans.

    All Unicode scalars and boundary bonuses live in two contiguous arenas.
    One offset table identifies candidate ranges, replacing two owned lists per
    ``PreparedCandidate`` with three corpus-wide buffers. The scoring scheme is
    shared by the corpus to keep the scan representation compact and
    unambiguous.

    Source strings are intentionally not retained. A result's source index can
    be used to retrieve display text from the caller's own list, while match
    positions remain Unicode scalar offsets within that source string.

    Copy construction deep-copies all three backing lists. Borrow or move a
    large corpus when independent storage is not required.
    """

    var _raw_scalars: List[UInt32]
    var _bonuses: List[Int]
    var _offsets: List[Int]
    var _scheme: Scheme

    def __init__(out self, scheme: Scheme = Scheme.DEFAULT):
        self._raw_scalars = List[UInt32]()
        self._bonuses = List[Int]()
        self._offsets = List[Int](capacity=1)
        self._offsets.append(0)
        self._scheme = scheme

    def __len__(self) -> Int:
        """Return the number of prepared candidates."""
        return len(self._offsets) - 1

    def scheme(self) -> Scheme:
        """Return the boundary-scoring scheme shared by all candidates."""
        return self._scheme

    def scalar_count(self) -> Int:
        """Return the number of Unicode scalars retained across the corpus."""
        return len(self._raw_scalars)

    def estimated_payload_bytes(self) -> Int:
        """Return arena and offset payload bytes on supported 64-bit targets.

        This excludes the three list headers and allocator bookkeeping. Scalars
        use four bytes, bonuses eight bytes, and candidate offsets eight bytes.
        """
        return 12 * len(self._raw_scalars) + 8 * len(self._offsets)

    def reserve(
        mut self,
        *,
        candidate_capacity: Int,
        scalar_capacity: Int,
    ) raises:
        """Reserve expected arena sizes without changing logical contents."""
        if candidate_capacity < len(self):
            raise Error(
                String(
                    "candidate_capacity must be at least the current count ",
                    len(self),
                    "; got ",
                    candidate_capacity,
                )
            )
        if candidate_capacity == Int.MAX:
            raise Error("candidate_capacity must leave room for the final offset")
        if scalar_capacity < len(self._raw_scalars):
            raise Error(
                String(
                    "scalar_capacity must be at least the current scalar count ",
                    len(self._raw_scalars),
                    "; got ",
                    scalar_capacity,
                )
            )
        self._offsets.reserve(candidate_capacity + 1)
        self._raw_scalars.reserve(scalar_capacity)
        self._bonuses.reserve(scalar_capacity)

    def append(mut self, text: StringSlice):
        """Decode and classify one candidate directly into both arenas."""
        var previous_class = _WHITESPACE
        for codepoint in text.codepoints():
            var scalar = codepoint.to_u32()
            var current_class = _scheme_char_class(scalar, self._scheme)
            self._raw_scalars.append(scalar)
            self._bonuses.append(_bonus(previous_class, current_class, self._scheme))
            previous_class = current_class
        self._offsets.append(len(self._raw_scalars))

    def candidate_length(self, index: Int) raises -> Int:
        """Return one candidate's Unicode scalar count."""
        self._check_index(index)
        return self._offsets[index + 1] - self._offsets[index]

    def _check_index(self, index: Int) raises:
        if index < 0 or index >= len(self):
            raise Error(
                String(
                    "PreparedCorpus candidate index out of range: ",
                    index,
                    " for ",
                    len(self),
                    " candidates",
                )
            )

    def validate(self) raises:
        """Revalidate offsets, scalars, and scheme-derived bonuses."""
        if self._scheme != Scheme.DEFAULT and self._scheme != Scheme.PATH:
            raise Error("PreparedCorpus has an unsupported scoring scheme")
        if len(self._offsets) < 1 or self._offsets[0] != 0:
            raise Error("PreparedCorpus offsets must start at zero")
        if len(self._bonuses) != len(self._raw_scalars):
            raise Error("PreparedCorpus scalar and bonus arena lengths differ")
        var previous = 0
        for offset_index in range(1, len(self._offsets)):
            var offset = self._offsets[offset_index]
            if offset < previous or offset > len(self._raw_scalars):
                raise Error("PreparedCorpus offsets must be ordered and in range")
            previous = offset
        if previous != len(self._raw_scalars):
            raise Error("PreparedCorpus final offset must equal scalar count")

        for candidate_index in range(len(self)):
            var start = self._offsets[candidate_index]
            var end = self._offsets[candidate_index + 1]
            var scalars = Span(self._raw_scalars)[start:end]
            for scalar in scalars:
                if scalar > UInt32(0x10FFFF) or (
                    scalar >= UInt32(0xD800) and scalar <= UInt32(0xDFFF)
                ):
                    raise Error("PreparedCorpus contains an invalid Unicode scalar")
            var expected = _candidate_bonuses(scalars, self._scheme)
            for offset in range(end - start):
                if self._bonuses[start + offset] != expected[offset]:
                    raise Error("PreparedCorpus contains a stale boundary bonus")


struct MatchWorkspace:
    """Reusable scratch storage for matching prepared candidates.

    A workspace is mutable, not thread-safe, and intended for one matching
    loop. Its retained suffix table grows to the largest successful ``P*C``
    match and is reused by later calls. Results own their position list and do
    not borrow the workspace. ``budget`` caps retained score-table cells,
    including geometric capacity growth. Exact operations raise before DP
    allocation if dimensions overflow or exceed that budget; non-matches and
    empty patterns still require no score cells. See ``docs/workspace-budget.md``
    for memory exclusions and parallel shard accounting.
    """

    var _suffix_scores: List[Int]
    var _budget: WorkspaceBudget

    def __init__(out self, *, budget: WorkspaceBudget = WorkspaceBudget()):
        self._suffix_scores = List[Int]()
        self._budget = budget

    def retained_cells(self) -> Int:
        """Return current allocated DP capacity, at most the configured budget."""
        return self._suffix_scores.capacity()

    def match(
        mut self,
        pattern: Pattern,
        candidate: PreparedCandidate,
    ) raises -> MatchResult:
        """Match prepared values, reusing scratch capacity when sufficient."""
        if pattern.is_empty():
            return MatchResult(True, 0, List[Int]())
        if not _is_subsequence_match(pattern, candidate._raw_scalars):
            return MatchResult.no_match()
        return _scalar_match_core(
            pattern,
            candidate._raw_scalars,
            candidate._bonuses,
            self._suffix_scores,
            self._budget,
        )

    def score(
        mut self,
        pattern: Pattern,
        candidate: PreparedCandidate,
    ) raises -> MatchScore:
        """Return the exact match score without allocating owned positions.

        This performs the same dynamic program and tie-breaking as ``match``.
        It traces the winning path to preserve the ranking-only exact-case
        bonus, but stores no positions. After the workspace has grown to the
        required DP size, steady-state calls allocate no dynamic storage.
        """
        if pattern.is_empty():
            return MatchScore(True, 0)
        if not _is_subsequence_match(pattern, candidate._raw_scalars):
            return MatchScore.no_match()
        return _scalar_score_core(
            pattern,
            candidate._raw_scalars,
            candidate._bonuses,
            self._suffix_scores,
            self._budget,
        )

    def match_into(
        mut self,
        pattern: Pattern,
        candidate: PreparedCandidate,
        mut positions: List[Int],
    ) raises -> MatchScore:
        """Return the exact score and write positions into reusable storage.

        ``positions`` is cleared for every outcome. Successful non-empty
        matches resize it to the pattern length; callers can reserve that
        capacity once and reuse it across visible-result reconstruction.
        """
        positions.clear()
        if pattern.is_empty():
            return MatchScore(True, 0)
        if not _is_subsequence_match(pattern, candidate._raw_scalars):
            return MatchScore.no_match()
        return _scalar_match_into_core(
            pattern,
            candidate._raw_scalars,
            candidate._bonuses,
            self._suffix_scores,
            positions,
            self._budget,
        )

    def score_at(
        mut self,
        pattern: Pattern,
        corpus: PreparedCorpus,
        index: Int,
    ) raises -> MatchScore:
        """Return an exact score for one arena-backed corpus candidate."""
        corpus._check_index(index)
        return self._score_at_unchecked(pattern, corpus, index)

    def _score_at_unchecked(
        mut self,
        pattern: Pattern,
        corpus: PreparedCorpus,
        index: Int,
    ) raises -> MatchScore:
        """Score one corpus slot after bounds have been established."""
        var start = corpus._offsets[index]
        var end = corpus._offsets[index + 1]
        var scalars = Span(corpus._raw_scalars)[start:end]
        if pattern.is_empty():
            return MatchScore(True, 0)
        if not _is_subsequence_match(pattern, scalars):
            return MatchScore.no_match()
        return _scalar_score_core(
            pattern,
            scalars,
            Span(corpus._bonuses)[start:end],
            self._suffix_scores,
            self._budget,
        )

    def match_into_at(
        mut self,
        pattern: Pattern,
        corpus: PreparedCorpus,
        index: Int,
        mut positions: List[Int],
    ) raises -> MatchScore:
        """Write exact positions for one arena-backed corpus candidate.

        A valid index clears ``positions`` for every match outcome. An invalid
        index raises before touching the caller-owned list.
        """
        corpus._check_index(index)
        positions.clear()
        return self._match_into_at_unchecked(pattern, corpus, index, positions)

    def _match_into_at_unchecked(
        mut self,
        pattern: Pattern,
        corpus: PreparedCorpus,
        index: Int,
        mut positions: List[Int],
    ) raises -> MatchScore:
        """Reconstruct one corpus slot after bounds have been established."""
        var start = corpus._offsets[index]
        var end = corpus._offsets[index + 1]
        var scalars = Span(corpus._raw_scalars)[start:end]
        if pattern.is_empty():
            return MatchScore(True, 0)
        if not _is_subsequence_match(pattern, scalars):
            return MatchScore.no_match()
        return _scalar_match_into_core(
            pattern,
            scalars,
            Span(corpus._bonuses)[start:end],
            self._suffix_scores,
            positions,
            self._budget,
        )
