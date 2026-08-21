#!/usr/bin/env bash
set -euo pipefail

readme_file="README.md"
snippet_dir=".pixi/readme-snippets"
binary_dir=".pixi/readme-bin"

mkdir -p "$snippet_dir" "$binary_dir"
find "$snippet_dir" -maxdepth 1 -type f -name 'snippet_*.mojo' -delete

snippet_count=$(
  awk -v snippet_dir="$snippet_dir" '
    BEGIN {
      in_mojo = 0
      count = 0
    }
    !in_mojo && /^```mojo/ {
      count += 1
      in_mojo = 1
      output = sprintf("%s/snippet_%d.mojo", snippet_dir, count)
      next
    }
    in_mojo && /^```[[:space:]]*$/ {
      close(output)
      in_mojo = 0
      next
    }
    in_mojo {
      print > output
    }
    END {
      if (in_mojo) {
        print "README.md has an unterminated fenced mojo block" > "/dev/stderr"
        exit 1
      }
      print count
    }
  ' "$readme_file"
)

if [[ "$snippet_count" -eq 0 ]]; then
  printf '%s\n' 'README.md contains no fenced mojo code blocks.' >&2
  exit 1
fi

for ((snippet_number = 1; snippet_number <= snippet_count; snippet_number++)); do
  snippet="$snippet_dir/snippet_${snippet_number}.mojo"
  binary="$binary_dir/snippet_${snippet_number}"
  printf 'Compiling README Mojo snippet %d: %s\n' "$snippet_number" "$snippet"
  if ! mojo build -I src "$snippet" -o "$binary"; then
    printf 'README Mojo snippet %d failed to compile: %s\n' \
      "$snippet_number" "$snippet" >&2
    exit 1
  fi
done

printf 'Compiled %d README Mojo snippet(s).\n' "$snippet_count"
