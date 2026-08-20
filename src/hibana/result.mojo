"""Deterministic fuzzy-match results."""

from std.collections import List
from std.io import Writable, Writer


struct MatchResult(Copyable, Equatable, Writable):
    """A mutable value containing one match attempt's output.

    ``Matcher.match`` produces zero-based Unicode scalar positions in strictly
    increasing order for a non-empty match. It produces score zero and no
    positions for a non-match. An empty-pattern match also has score zero and
    no positions, but has ``matched == True``. ``MatchResult`` fields are
    ordinary mutable Mojo value fields, so callers may change them after
    return; Hibana does not claim or revalidate producer invariants after caller
    mutation. Positions are Unicode scalar indices, not UTF-8 byte offsets.
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

    def __eq__(self, other: Self) -> Bool:
        """Return whether every public result field is equal."""
        if (
            self.matched != other.matched
            or self.score != other.score
            or len(self.positions) != len(other.positions)
        ):
            return False
        for index in range(len(self.positions)):
            if self.positions[index] != other.positions[index]:
                return False
        return True

    def __str__(self) -> String:
        var result = String()
        self.write_to(result)
        return result^

    def write_to[W: Writer](self, mut writer: W):
        """Write every public field in a readable constructor-like form."""
        writer.write(
            "MatchResult(matched=",
            self.matched,
            ", score=",
            self.score,
            ", positions=",
            self.positions,
            ")",
        )
