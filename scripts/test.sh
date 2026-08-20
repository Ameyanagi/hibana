#!/usr/bin/env bash
set -euo pipefail

for test_file in tests/test_*.mojo; do
  mojo run -I src "$test_file"
done

mkdir -p .pixi/test-bin
mojo build -I src examples/basic.mojo -o .pixi/test-bin/basic
mojo build -I src examples/rank_paths.mojo -o .pixi/test-bin/rank_paths
