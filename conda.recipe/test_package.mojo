from hibana import Matcher, Pattern
from std.testing import assert_equal, assert_true


def main() raises:
    var pattern = Pattern("kmr")
    var result = Matcher(pattern).match("kamera")
    assert_true(result.matched)
    assert_equal(result.score, 298)
    assert_equal(result.positions[0], 0)
    assert_equal(result.positions[1], 2)
    assert_equal(result.positions[2], 4)
