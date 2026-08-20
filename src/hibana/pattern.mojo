"""Prepared fuzzy-match patterns."""

from std.collections import List


def _scalar_values(text: StringSlice) -> List[UInt32]:
    var values = List[UInt32]()
    for scalar in text.codepoints():
        values.append(scalar.to_u32())
    return values^


struct Pattern(Copyable, Sized):
    """An owned query prepared once for repeated candidate matching.

    The initial implementation preserves Unicode scalar values exactly. Case
    folding and other normalization are deliberately separate future policy.

    A pattern stores only its canonical scalar sequence; it does not retain a
    second text representation that could become inconsistent. ``Pattern`` is
    a mutable Mojo value. Copying it snapshots the sequence, while direct
    mutation of underscore-prefixed storage changes that value's future match
    behavior. Such storage is implementation detail, not stable public API.
    """

    var _scalars: List[UInt32]

    def __init__(out self, text: StringSlice):
        self._scalars = _scalar_values(text)

    def __len__(self) -> Int:
        """Return the number of Unicode scalar values in the pattern."""
        return len(self._scalars)

    def is_empty(self) -> Bool:
        """Return whether this pattern matches every candidate."""
        return len(self._scalars) == 0
