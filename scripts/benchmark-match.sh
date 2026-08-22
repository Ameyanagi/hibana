#!/usr/bin/env bash
set -euo pipefail

case "$(uname -s)" in
  Darwin)
    benchmark_cpu=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || uname -m)
    ;;
  Linux)
    benchmark_cpu=""
    if command -v lscpu >/dev/null 2>&1; then
      benchmark_cpu=$(lscpu | awk -F: '/Model name/ {sub(/^[ \t]+/, "", $2); print $2; exit}')
    fi
    if [[ -z "$benchmark_cpu" ]]; then
      benchmark_cpu=$(uname -m)
    fi
    ;;
  *)
    benchmark_cpu=$(uname -m)
    ;;
esac

printf '%s\n' 'metadata_schema=hibana-prepared-benchmark-metadata-v1'
printf 'run_utc=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
printf 'git_head=%s\n' "$(git rev-parse --verify HEAD)"
if [[ -n $(git status --porcelain --untracked-files=normal) ]]; then
  printf '%s\n' 'git_state=dirty'
else
  printf '%s\n' 'git_state=clean'
fi
printf 'cpu=%s\n' "$benchmark_cpu"
printf 'os=%s\n' "$(uname -srv)"
printf 'architecture=%s\n' "$(uname -m)"
printf 'mojo=%s\n' "$(mojo --version)"
printf '%s\n' 'compiler_options=--optimization-level 3 -I src'
printf '%s\n' 'dataset_provenance=deterministic fixtures generated in benchmarks/bench_match.mojo'
printf 'dataset_source_git_blob=%s\n' \
  "$(git hash-object benchmarks/bench_match.mojo)"
workspace_source_git_blob=$(
  git ls-files --cached --others --exclude-standard \
    | LC_ALL=C sort \
    | while IFS= read -r source_path; do
        printf '%s %s\n' "$(git hash-object "$source_path")" "$source_path"
      done \
    | git hash-object --stdin
)
printf 'workspace_source_manifest_git_blob=%s\n' "$workspace_source_git_blob"
printf '%s\n' 'command=pixi run bench'

mojo run --optimization-level 3 -I src benchmarks/bench_match.mojo
