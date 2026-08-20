"""Public scoring schemes and internal scalar score preparation."""

from std.collections import List

from .pattern import Pattern, _fold_ascii_scalar


struct Scheme(Copyable, Equatable, ImplicitlyCopyable):
    """Nominal boundary-bonus policy for fuzzy matching.

    ``DEFAULT`` rewards word, camel-case, number, and common delimiter
    boundaries, with whitespace strongest. ``PATH`` follows the same rules but
    treats only ``/`` and ``\\`` as delimiters and gives them the whitespace
    boundary value. The complete fixed score table is published in
    ``docs/scoring.md``.

    The constants are the public construction surface. The integer
    discriminant and its underscore-prefixed initializer argument are private
    by convention.
    """

    var _value: Int

    comptime DEFAULT = Scheme(_value=0)
    comptime PATH = Scheme(_value=1)

    def __init__(out self, *, _value: Int):
        self._value = _value

    def __eq__(self, other: Self) -> Bool:
        return self._value == other._value


comptime _SCORE_MATCH = 100
comptime _SCORE_ADJACENCY = 25
comptime _BONUS_BOUNDARY_WHITE = 60
comptime _BONUS_BOUNDARY_DELIMITER = 55
comptime _BONUS_BOUNDARY = 50
comptime _BONUS_CAMEL = 40
comptime _BONUS_NON_WORD = 50
comptime _BONUS_FIRST_CHAR_MULTIPLIER = 2
comptime _BONUS_EXACT_CASE = 45

comptime _WHITESPACE = 0
comptime _DELIMITER = 1
comptime _NON_WORD = 2
comptime _LOWER = 3
comptime _UPPER = 4
comptime _DIGIT = 5
comptime _WORD_OTHER = 6


def _char_class(scalar: UInt32) -> Int:
    """Classify one scalar under the default ASCII delimiter policy."""
    if (
        scalar == UInt32(32)
        or scalar == UInt32(9)
        or scalar == UInt32(10)
        or scalar == UInt32(13)
        or scalar == UInt32(11)
        or scalar == UInt32(12)
    ):
        return _WHITESPACE
    if (
        scalar == UInt32(47)
        or scalar == UInt32(44)
        or scalar == UInt32(58)
        or scalar == UInt32(59)
        or scalar == UInt32(124)
    ):
        return _DELIMITER
    if scalar >= UInt32(48) and scalar <= UInt32(57):
        return _DIGIT
    if scalar >= UInt32(65) and scalar <= UInt32(90):
        return _UPPER
    if scalar >= UInt32(97) and scalar <= UInt32(122):
        return _LOWER
    if scalar >= UInt32(128):
        return _WORD_OTHER
    return _NON_WORD


def _scheme_char_class(scalar: UInt32, scheme: Scheme) -> Int:
    var cls = _char_class(scalar)
    if scheme == Scheme.PATH:
        if scalar == UInt32(47) or scalar == UInt32(92):
            return _DELIMITER
        if cls == _DELIMITER:
            return _NON_WORD
    return cls


def _is_word_class(cls: Int) -> Bool:
    return cls == _LOWER or cls == _UPPER or cls == _DIGIT or cls == _WORD_OTHER


def _bonus(prev_class: Int, cls: Int, scheme: Scheme) -> Int:
    """Return the fixed context bonus for a matched candidate scalar."""
    if not _is_word_class(cls):
        return _BONUS_NON_WORD
    if prev_class == _WHITESPACE:
        return _BONUS_BOUNDARY_WHITE
    if prev_class == _DELIMITER:
        if scheme == Scheme.PATH:
            return _BONUS_BOUNDARY_WHITE
        return _BONUS_BOUNDARY_DELIMITER
    if prev_class == _NON_WORD:
        return _BONUS_BOUNDARY
    if prev_class == _LOWER and cls == _UPPER:
        return _BONUS_CAMEL
    if prev_class != _DIGIT and cls == _DIGIT:
        return _BONUS_CAMEL
    return 0


def _candidate_bonuses(scalars: Span[UInt32, _], scheme: Scheme) -> List[Int]:
    """Classify borrowed candidate scalars without copying the caller's span."""
    var bonuses = List[Int](capacity=len(scalars))
    var prev_class = _WHITESPACE
    for index in range(len(scalars)):
        var cls = _scheme_char_class(scalars[index], scheme)
        bonuses.append(_bonus(prev_class, cls, scheme))
        prev_class = cls
    return bonuses^


def _candidate_match_scalar(scalar: UInt32, fold_ascii: Bool) -> UInt32:
    """Apply the prepared pattern's candidate-side ASCII case policy."""
    return _fold_ascii_scalar(scalar) if fold_ascii else scalar


def _exact_case_score(
    pattern: Pattern,
    candidate: Span[UInt32, _],
    positions: List[Int],
) -> Int:
    """Return the ranking-only exact-case bonus after position selection."""
    if not pattern._fold_ascii:
        return 0
    for pattern_index in range(len(positions)):
        if pattern._raw_scalars[pattern_index] != candidate[positions[pattern_index]]:
            return 0
    return _BONUS_EXACT_CASE
