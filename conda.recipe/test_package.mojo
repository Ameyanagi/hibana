from hibana import Matcher, Pattern
from hibana.fast import fast_score
from hibana.hybrid import hybrid_rank, hybrid_rank_corpus
from hibana.parallel import rank_corpus_exact, rank_prepared_exact
from hibana.prepared import MatchWorkspace, PreparedCandidate, PreparedCorpus
from std.collections import List
from std.testing import assert_equal, assert_true


def main() raises:
    var pattern = Pattern("kmr")
    var result = Matcher(pattern).match("kamera")
    assert_true(result.matched)
    assert_equal(result.score, 463)  # 300 + 60 + 60 - 2 + 45
    assert_equal(result.positions[0], 0)
    assert_equal(result.positions[1], 2)
    assert_equal(result.positions[2], 4)

    # Keep the installed-package gate ahead of Yuragi's prepared-index use:
    # this must resolve from the built .mojoc, never a sibling source tree.
    var prepared = PreparedCandidate("kamera")
    var workspace = MatchWorkspace()
    var score = workspace.score(pattern, prepared)
    assert_true(score.matched)
    assert_equal(score.score, result.score)

    var positions = List[Int]()
    var into_score = workspace.match_into(pattern, prepared, positions)
    assert_equal(into_score, score)
    assert_equal(len(positions), 3)
    assert_equal(positions[0], 0)
    assert_equal(positions[1], 2)
    assert_equal(positions[2], 4)

    var corpus: List[PreparedCandidate] = [
        PreparedCandidate("kamera"),
        PreparedCandidate("other"),
    ]
    assert_true(fast_score(pattern, corpus[0]).matched)
    var hybrid = hybrid_rank(pattern, corpus, k=1, shortlist_size=2)
    assert_equal(hybrid.total_matches, 1)
    assert_equal(hybrid.rows[0].index, 0)
    var exact_page = rank_prepared_exact(corpus, pattern, k=1, grain_size=4)
    assert_equal(exact_page.total_matches, 1)
    assert_equal(exact_page.rows[0].source_index, 0)

    var arena = PreparedCorpus()
    arena.append("kamera")
    arena.append("other")
    arena.validate()
    var arena_score = workspace.score_at(pattern, arena, 0)
    assert_equal(arena_score, score)
    var arena_hybrid = hybrid_rank_corpus(pattern, arena, k=1, shortlist_size=2)
    assert_equal(arena_hybrid.total_matches, 1)
    assert_equal(arena_hybrid.rows[0].index, 0)
    var arena_exact = rank_corpus_exact(arena, pattern, k=1, grain_size=4)
    assert_equal(arena_exact.total_matches, 1)
    assert_equal(arena_exact.rows[0].source_index, 0)
