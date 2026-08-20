"""Prepared fuzzy matcher facade."""

from .algorithms.scalar import scalar_match
from .pattern import CaseMode, Pattern
from .result import MatchResult


struct Matcher(Copyable):
    """A reusable mutable value backed by one canonical prepared pattern.

    Construction copies the pattern, so later mutation of the source ``Pattern``
    does not affect this matcher. Direct mutation of underscore-prefixed matcher
    storage changes later matches and is outside the stable public API.
    """

    var _pattern: Pattern

    def __init__(
        out self,
        query: StringSlice,
        case_mode: CaseMode = CaseMode.SMART_ASCII,
    ):
        """Prepare ``query`` for repeated candidate matching."""
        self._pattern = Pattern(query, case_mode=case_mode)

    def __init__(out self, pattern: Pattern):
        """Build a matcher from an already prepared pattern."""
        self._pattern = pattern.copy()

    def match(self, candidate: StringSlice) -> MatchResult:
        """Return the best match, or the canonical non-match result."""
        return scalar_match(self._pattern, candidate)
