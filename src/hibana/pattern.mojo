"""Prepared fuzzy-match patterns."""

from std.collections import List


struct CaseMode(Copyable, Equatable, ImplicitlyCopyable):
    """Nominal ASCII case policy for fuzzy matching.

    ``EXACT`` compares every Unicode scalar exactly. ``IGNORE_ASCII`` folds
    ASCII ``A`` through ``Z`` to lowercase on both sides while leaving every
    other scalar unchanged. ``SMART_ASCII`` behaves as ``EXACT`` when the query
    contains an ASCII uppercase letter and as ``IGNORE_ASCII`` otherwise.

    The constants are the public construction surface. The integer
    discriminant and its underscore-prefixed initializer argument are private
    by convention.
    """

    var _value: Int

    comptime EXACT = CaseMode(_value=0)
    comptime IGNORE_ASCII = CaseMode(_value=1)
    comptime SMART_ASCII = CaseMode(_value=2)

    def __init__(out self, *, _value: Int):
        self._value = _value

    def __eq__(self, other: Self) -> Bool:
        return self._value == other._value


def _scalar_values(text: StringSlice) -> List[UInt32]:
    var values = List[UInt32]()
    for scalar in text.codepoints():
        values.append(scalar.to_u32())
    return values^


def _fold_ascii_scalar(scalar: UInt32) -> UInt32:
    return scalar + (
        UInt32(32) if scalar >= UInt32(65) and scalar <= UInt32(90) else UInt32(0)
    )


def _contains_ascii_uppercase(scalars: List[UInt32]) -> Bool:
    for scalar in scalars:
        if scalar >= UInt32(65) and scalar <= UInt32(90):
            return True
    return False


def _folds_ascii(case_mode: CaseMode, raw_scalars: List[UInt32]) -> Bool:
    return case_mode == CaseMode.IGNORE_ASCII or (
        case_mode == CaseMode.SMART_ASCII and not _contains_ascii_uppercase(raw_scalars)
    )


struct Pattern(Copyable, Sized):
    """An owned query prepared once for repeated candidate matching.

    ASCII folding is decided once during construction. The pattern retains both
    the raw query scalars and the prepared match scalars so later scoring can
    distinguish exact case without reconstructing the query. Candidate folding
    never changes scalar count, so returned positions always index the original
    candidate scalar sequence.

    ``Pattern`` is a mutable Mojo value. Copying it snapshots its storage, while
    direct mutation of underscore-prefixed fields changes that value's future
    behavior and is outside the stable public API.
    """

    var _raw_scalars: List[UInt32]
    var _scalars: List[UInt32]
    var _case: CaseMode
    var _fold_ascii: Bool

    def __init__(
        out self,
        text: StringSlice,
        case_mode: CaseMode = CaseMode.SMART_ASCII,
    ):
        var raw_scalars = _scalar_values(text)
        var fold_ascii = _folds_ascii(case_mode, raw_scalars)
        var match_scalars = raw_scalars.copy()
        if fold_ascii:
            for index in range(len(match_scalars)):
                match_scalars[index] = _fold_ascii_scalar(match_scalars[index])
        self._raw_scalars = raw_scalars^
        self._scalars = match_scalars^
        self._case = case_mode
        self._fold_ascii = fold_ascii

    def __len__(self) -> Int:
        """Return the number of Unicode scalar values in the pattern."""
        return len(self._scalars)

    def is_empty(self) -> Bool:
        """Return whether this pattern matches every candidate."""
        return len(self._scalars) == 0
