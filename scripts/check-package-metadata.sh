#!/usr/bin/env bash
set -euo pipefail

package_name="mojo-hibana"
workspace_version="$(sed -n 's/^version = "\([^"]*\)"$/\1/p' pixi.toml)"
artifact_count="$(find output -type f -name "${package_name}-${workspace_version}-*.conda" | wc -l | tr -d '[:space:]')"

if [[ "$artifact_count" -ne 1 ]]; then
  echo "expected one ${package_name} ${workspace_version} artifact, found ${artifact_count}" >&2
  exit 1
fi

artifact="$(find output -type f -name "${package_name}-${workspace_version}-*.conda" -print -quit)"
extract_dir="$(mktemp -d)"
trap 'rm -rf "$extract_dir"' EXIT

pixi run rattler-build package extract "$artifact" --dest "$extract_dir"
index_json="$extract_dir/info/index.json"

if [[ ! -f "$index_json" ]]; then
  echo "package does not contain info/index.json: $artifact" >&2
  exit 1
fi

jq -e \
  --arg package_name "$package_name" \
  --arg package_version "$workspace_version" \
  '
    .name == $package_name
    and .version == $package_version
    and ([.depends[] | select(split(" ")[0] == "mojo-compiler")]
         == ["mojo-compiler ==1.0.0"])
  ' "$index_json" >/dev/null
