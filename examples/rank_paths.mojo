"""Rank paths and mark matched Unicode scalar positions."""

from hibana import Matcher, Scheme
from std.collections import List


def _position_markers(text: StringSlice, positions: List[Int]) -> String:
    var markers = String()
    var position_cursor = 0
    var scalar_index = 0
    for _ in text.codepoints():
        if (
            position_cursor < len(positions)
            and positions[position_cursor] == scalar_index
        ):
            markers += "^"
            position_cursor += 1
        else:
            markers += " "
        scalar_index += 1
    return markers^


def main() raises:
    var paths: List[String] = [
        "src/hibana/matcher.mojo",
        "src/hibana/pattern.mojo",
        "tests/test_basic.mojo",
        "README.md",
        "examples/rank_paths.mojo",
    ]
    var ranked = Matcher("mojo", scheme=Scheme.PATH).rank(paths, k=5)
    for item in ranked:
        print(paths[item.index], " score=", item.score)
        print(_position_markers(paths[item.index], item.positions))
