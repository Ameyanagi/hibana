#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="${TMPDIR:-/tmp}/hibana-profile"
binary="$output_dir/profile-corpus"
mode="${1:-hybrid}"

case "$mode" in
  hybrid|arena-hybrid|exact|arena-exact) ;;
  *)
    echo "unknown mode '$mode'; expected hybrid, arena-hybrid, exact, or arena-exact" >&2
    exit 2
    ;;
esac

case "$(uname -s)" in
  Darwin)
    profile_cpu=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || uname -m)
    ;;
  *)
    profile_cpu=$(uname -m)
    ;;
esac

printf '%s\n' 'metadata_schema=hibana-corpus-profile-metadata-v1'
printf 'run_utc=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
printf 'git_head=%s\n' "$(git -C "$repo_root" rev-parse --verify HEAD)"
if [[ -n $(git -C "$repo_root" status --porcelain --untracked-files=normal) ]]; then
  printf '%s\n' 'git_state=dirty'
else
  printf '%s\n' 'git_state=clean'
fi
printf 'cpu=%s\n' "$profile_cpu"
printf 'os=%s\n' "$(uname -srv)"
printf 'architecture=%s\n' "$(uname -m)"
printf 'mojo=%s\n' "$(pixi run mojo --version)"
printf '%s\n' 'compiler_options=--optimization-level 3 --debug-level=line-tables -I src'
printf '%s\n' 'dataset_provenance=deterministic 100000-path fixture generated in benchmarks/profile_corpus.mojo'
printf 'dataset_source_git_blob=%s\n' \
  "$(git -C "$repo_root" hash-object benchmarks/profile_corpus.mojo)"
workspace_source_git_blob=$(
  git -C "$repo_root" ls-files --cached --others --exclude-standard \
    | LC_ALL=C sort \
    | while IFS= read -r source_path; do
        printf '%s %s\n' \
          "$(git -C "$repo_root" hash-object "$source_path")" "$source_path"
      done \
    | git -C "$repo_root" hash-object --stdin
)
printf 'workspace_source_manifest_git_blob=%s\n' "$workspace_source_git_blob"
printf 'command=bash scripts/profile-corpus.sh %s\n' "$mode"

mkdir -p "$output_dir"
pixi run mojo build --optimization-level 3 --debug-level=line-tables \
  -I "$repo_root/src" \
  "$repo_root/benchmarks/profile_corpus.mojo" -o "$binary"

trace="$output_dir/${mode}-time-profile.trace"
rm -rf "$trace"
xcrun xctrace record --template "Time Profiler" \
  --output "$trace" --launch -- "$binary" "$mode"

echo "trace=$trace"
profile_output=$(/usr/bin/time -l "$binary" "$mode")
printf '%s\n' "$profile_output"

case "$mode" in
  hybrid) comparison_mode="arena-hybrid" ;;
  arena-hybrid) comparison_mode="hybrid" ;;
  exact) comparison_mode="arena-exact" ;;
  arena-exact) comparison_mode="exact" ;;
esac

comparison_output=$("$binary" "$comparison_mode")
printf '%s\n' "$comparison_output"
profile_checksum=$(printf '%s\n' "$profile_output" | sed -n 's/.*result_checksum=\([-0-9]*\).*/\1/p')
comparison_checksum=$(printf '%s\n' "$comparison_output" | sed -n 's/.*result_checksum=\([-0-9]*\).*/\1/p')
if [[ -z "$profile_checksum" || -z "$comparison_checksum" ]]; then
  echo "profile output did not contain a result checksum" >&2
  exit 1
fi
if [[ "$profile_checksum" != "$comparison_checksum" ]]; then
  echo "result mismatch: $mode=$profile_checksum $comparison_mode=$comparison_checksum" >&2
  exit 1
fi
echo "verified_result_equivalence=$mode,$comparison_mode checksum=$profile_checksum"
