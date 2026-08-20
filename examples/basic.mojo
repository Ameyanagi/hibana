from hibana import Matcher


def main() raises:
    var matcher = Matcher("kmr")
    var result = matcher.match("kamera")

    print("matched:", result.matched)
    print("score:", result.score)
    print("positions:", result.positions)
