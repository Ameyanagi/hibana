"""Deterministic fuzzy-match results."""

from std.collections import List


struct MatchResult(Copyable):
    """A mutable value containing one match attempt's output.

    ``Matcher.match`` produces zero-based Unicode scalar positions in strictly
    increasing order for a non-empty match. It produces score zero and no
    positions for a non-match. ``MatchResult`` fields are ordinary mutable Mojo
    value fields, so callers may change them after return; Hibana does not claim
    or revalidate producer invariants after caller mutation.
    """

    var matched: Bool
    var score: Int
    var positions: List[Int]

    def __init__(
        out self,
        matched: Bool,
        score: Int,
        var positions: List[Int],
    ):
        self.matched = matched
        self.score = score
        self.positions = positions^

    @staticmethod
    def no_match() -> Self:
        """Construct the canonical non-match value."""
        return Self(False, 0, List[Int]())
