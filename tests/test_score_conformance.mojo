"""Literal score fixtures pin Hibana's public scoring contract."""

from hibana import CaseMode, Matcher, Scheme
from std.collections import List
from std.testing import TestSuite, assert_equal, assert_true


struct _ScoreFixture(Copyable):
    var pattern: String
    var candidate: String
    var case_mode: CaseMode
    var scheme: Scheme
    var expected_score: Int
    var expected_positions: List[Int]

    def __init__(
        out self,
        pattern: StringSlice,
        candidate: StringSlice,
        case_mode: CaseMode,
        scheme: Scheme,
        expected_score: Int,
        var expected_positions: List[Int],
    ):
        self.pattern = String(pattern)
        self.candidate = String(candidate)
        self.case_mode = case_mode
        self.scheme = scheme
        self.expected_score = expected_score
        self.expected_positions = expected_positions^


def _one(first: Int) -> List[Int]:
    var positions = List[Int]()
    positions.append(first)
    return positions^


def _two(first: Int, second: Int) -> List[Int]:
    var positions = List[Int]()
    positions.append(first)
    positions.append(second)
    return positions^


def _three(first: Int, second: Int, third: Int) -> List[Int]:
    var positions = List[Int]()
    positions.append(first)
    positions.append(second)
    positions.append(third)
    return positions^


def _fixtures() -> List[_ScoreFixture]:
    var fixtures = List[_ScoreFixture]()
    fixtures.append(
        _ScoreFixture(
            "ab",
            "a b",
            CaseMode.EXACT,
            Scheme.DEFAULT,
            379,  # (100 + 60) + (100 + 60) + 60 - 1
            _two(0, 2),
        )
    )
    fixtures.append(
        _ScoreFixture(
            "ab",
            "a\tb",
            CaseMode.EXACT,
            Scheme.DEFAULT,
            379,  # (100 + 60) + (100 + 60) + 60 - 1
            _two(0, 2),
        )
    )
    fixtures.append(
        _ScoreFixture(
            "ab",
            "a\nb",
            CaseMode.EXACT,
            Scheme.DEFAULT,
            379,  # (100 + 60) + (100 + 60) + 60 - 1
            _two(0, 2),
        )
    )
    fixtures.append(
        _ScoreFixture(
            "ab",
            "a\rb",
            CaseMode.EXACT,
            Scheme.DEFAULT,
            379,  # (100 + 60) + (100 + 60) + 60 - 1
            _two(0, 2),
        )
    )
    fixtures.append(
        _ScoreFixture(
            "ab",
            "a\vb",
            CaseMode.EXACT,
            Scheme.DEFAULT,
            379,  # (100 + 60) + (100 + 60) + 60 - 1
            _two(0, 2),
        )
    )
    fixtures.append(
        _ScoreFixture(
            "ab",
            "a\fb",
            CaseMode.EXACT,
            Scheme.DEFAULT,
            379,  # (100 + 60) + (100 + 60) + 60 - 1
            _two(0, 2),
        )
    )
    fixtures.append(
        _ScoreFixture(
            "ab",
            "a/b",
            CaseMode.EXACT,
            Scheme.DEFAULT,
            374,  # (100 + 60) + (100 + 55) + 60 - 1
            _two(0, 2),
        )
    )
    fixtures.append(
        _ScoreFixture(
            "ab",
            "a:b",
            CaseMode.EXACT,
            Scheme.DEFAULT,
            374,  # (100 + 60) + (100 + 55) + 60 - 1
            _two(0, 2),
        )
    )
    fixtures.append(
        _ScoreFixture(
            "ab",
            "a:b",
            CaseMode.EXACT,
            Scheme.PATH,
            369,  # (100 + 60) + (100 + 50) + 60 - 1
            _two(0, 2),
        )
    )
    fixtures.append(
        _ScoreFixture(
            "ab",
            "a;b",
            CaseMode.EXACT,
            Scheme.DEFAULT,
            374,  # (100 + 60) + (100 + 55) + 60 - 1
            _two(0, 2),
        )
    )
    fixtures.append(
        _ScoreFixture(
            "ab",
            "a;b",
            CaseMode.EXACT,
            Scheme.PATH,
            369,  # (100 + 60) + (100 + 50) + 60 - 1
            _two(0, 2),
        )
    )
    fixtures.append(
        _ScoreFixture(
            "ab",
            "a|b",
            CaseMode.EXACT,
            Scheme.DEFAULT,
            374,  # (100 + 60) + (100 + 55) + 60 - 1
            _two(0, 2),
        )
    )
    fixtures.append(
        _ScoreFixture(
            "ab",
            "a|b",
            CaseMode.EXACT,
            Scheme.PATH,
            369,  # (100 + 60) + (100 + 50) + 60 - 1
            _two(0, 2),
        )
    )
    fixtures.append(
        _ScoreFixture(
            "ab",
            "a/b",
            CaseMode.EXACT,
            Scheme.PATH,
            379,  # (100 + 60) + (100 + 60) + 60 - 1
            _two(0, 2),
        )
    )
    fixtures.append(
        _ScoreFixture(
            "ab",
            "a_b",
            CaseMode.EXACT,
            Scheme.DEFAULT,
            369,  # (100 + 60) + (100 + 50) + 60 - 1
            _two(0, 2),
        )
    )
    fixtures.append(
        _ScoreFixture(
            "aB",
            "aB",
            CaseMode.EXACT,
            Scheme.DEFAULT,
            385,  # (100 + 60) + (100 + 40) + 60 + 25
            _two(0, 1),
        )
    )
    fixtures.append(
        _ScoreFixture(
            "a1",
            "a1",
            CaseMode.EXACT,
            Scheme.DEFAULT,
            385,  # (100 + 60) + (100 + 40) + 60 + 25
            _two(0, 1),
        )
    )
    fixtures.append(
        _ScoreFixture(
            "a",
            "a",
            CaseMode.EXACT,
            Scheme.DEFAULT,
            220,  # (100 + 60) + 60 first-character multiplier extra
            _one(0),
        )
    )
    fixtures.append(
        _ScoreFixture(
            "ab",
            "ab",
            CaseMode.EXACT,
            Scheme.DEFAULT,
            345,  # (100 + 60) + 100 + 60 + 25 adjacency
            _two(0, 1),
        )
    )
    fixtures.append(
        _ScoreFixture(
            "a",
            "xa",
            CaseMode.EXACT,
            Scheme.DEFAULT,
            99,  # 100 - 1 leading scalar
            _one(1),
        )
    )
    fixtures.append(
        _ScoreFixture(
            "ab",
            "axb",
            CaseMode.EXACT,
            Scheme.DEFAULT,
            319,  # (100 + 60) + 100 + 60 - 1 internal scalar
            _two(0, 2),
        )
    )
    fixtures.append(
        _ScoreFixture(
            "a",
            "a",
            CaseMode.SMART_ASCII,
            Scheme.DEFAULT,
            265,  # (100 + 60) + 60 + 45 exact-case once
            _one(0),
        )
    )
    fixtures.append(
        _ScoreFixture(
            "a",
            "A",
            CaseMode.SMART_ASCII,
            Scheme.DEFAULT,
            220,  # (100 + 60) + 60; folded match, no exact-case bonus
            _one(0),
        )
    )
    fixtures.append(
        _ScoreFixture(
            "a",
            "a",
            CaseMode.EXACT,
            Scheme.DEFAULT,
            220,  # (100 + 60) + 60; EXACT never earns the 45 bonus
            _one(0),
        )
    )
    fixtures.append(
        _ScoreFixture(
            "A",
            "A",
            CaseMode.SMART_ASCII,
            Scheme.DEFAULT,
            220,  # (100 + 60) + 60; uppercase smart-case degrades to exact
            _one(0),
        )
    )
    fixtures.append(
        _ScoreFixture(
            "A",
            "A",
            CaseMode.IGNORE_ASCII,
            Scheme.DEFAULT,
            265,  # (100 + 60) + 60 + 45 under active ignore-case folding
            _one(0),
        )
    )
    fixtures.append(
        _ScoreFixture(
            "_",
            "_",
            CaseMode.EXACT,
            Scheme.DEFAULT,
            200,  # (100 + 50) + 50 first-character multiplier extra
            _one(0),
        )
    )
    fixtures.append(
        _ScoreFixture(
            "/",
            "/",
            CaseMode.EXACT,
            Scheme.PATH,
            200,  # (100 + 50) + 50; punctuation itself always earns 50
            _one(0),
        )
    )
    fixtures.append(
        _ScoreFixture(
            " ",
            " ",
            CaseMode.EXACT,
            Scheme.DEFAULT,
            200,  # (100 + 50) + 50; matching whitespace itself earns 50
            _one(0),
        )
    )
    fixtures.append(
        _ScoreFixture(
            "ab",
            "a\\b",
            CaseMode.EXACT,
            Scheme.DEFAULT,
            369,  # (100 + 60) + (100 + 50) + 60 - 1
            _two(0, 2),
        )
    )
    fixtures.append(
        _ScoreFixture(
            "ab",
            "a\\b",
            CaseMode.EXACT,
            Scheme.PATH,
            379,  # (100 + 60) + (100 + 60) + 60 - 1
            _two(0, 2),
        )
    )
    fixtures.append(
        _ScoreFixture(
            "ab",
            "a,b",
            CaseMode.EXACT,
            Scheme.DEFAULT,
            374,  # (100 + 60) + (100 + 55) + 60 - 1
            _two(0, 2),
        )
    )
    fixtures.append(
        _ScoreFixture(
            "ab",
            "a,b",
            CaseMode.EXACT,
            Scheme.PATH,
            369,  # (100 + 60) + (100 + 50) + 60 - 1
            _two(0, 2),
        )
    )
    fixtures.append(
        _ScoreFixture(
            "abc",
            "abbc",
            CaseMode.EXACT,
            Scheme.DEFAULT,
            444,  # (100 + 60) + 100 + 100 + 60 + 25 - 1
            _three(0, 1, 3),
        )
    )
    fixtures.append(
        _ScoreFixture(
            "a",
            "/Axxxxxxxx a",
            CaseMode.SMART_ASCII,
            Scheme.DEFAULT,
            209,  # 100 + 2*55 - 1 ties 100 + 2*60 - 11; choose index 1
            _one(1),  # Exact-case 45 cannot change the selected position.
        )
    )
    fixtures.append(
        _ScoreFixture(
            "mm",
            "MatchMode",
            CaseMode.SMART_ASCII,
            Scheme.DEFAULT,
            356,  # (100 + 60) + (100 + 40) + 60 - 4
            _two(0, 5),
        )
    )
    fixtures.append(
        _ScoreFixture(
            "mm",
            "ammo",
            CaseMode.SMART_ASCII,
            Scheme.DEFAULT,
            269,  # 100 + 100 + 25 - 1 + 45 exact-case once
            _two(1, 2),
        )
    )
    return fixtures^


def test_score_conformance_table() raises:
    var fixtures = _fixtures()
    for fixture in fixtures:
        var result = Matcher(
            fixture.pattern,
            case_mode=fixture.case_mode,
            scheme=fixture.scheme,
        ).match(fixture.candidate)
        assert_true(result.matched)
        assert_equal(result.score, fixture.expected_score)
        assert_equal(len(result.positions), len(fixture.expected_positions))
        for index in range(len(result.positions)):
            assert_equal(result.positions[index], fixture.expected_positions[index])


def test_boundary_bonus_ranks_match_mode_above_ammo() raises:
    var matcher = Matcher("mm")
    var match_mode = matcher.match("MatchMode")
    var ammo = matcher.match("ammo")
    assert_equal(match_mode.score, 356)  # 160 + 140 + 60 - 4
    assert_equal(ammo.score, 269)  # 100 + 100 + 25 - 1 + 45
    assert_true(match_mode.score > ammo.score)


def test_rank_flagship_returns_match_mode_before_ammo() raises:
    var candidates: List[String] = ["ammo", "MatchMode"]
    var ranked = Matcher("mm").rank(candidates, 2)
    assert_equal(ranked[0].index, 1)
    assert_equal(ranked[0].score, 356)
    assert_equal(ranked[1].index, 0)
    assert_equal(ranked[1].score, 269)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
