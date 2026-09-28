#!/usr/bin/env bash
# ai-verify-context.sh - render what a pull request changed in the community
# data as whole ENTRIES, for ai-verify.sh to judge.
#
# Usage: ai-verify-context.sh <base-sha> <head-sha> <out-file>
#
# Every file under data/ is a range PACK ({"entries": {"<work-slug>": {...}}})
# holding many unrelated works, and a write re-renders the whole pack and may
# split it - so a text diff is mostly storage churn, and it shows prose as
# fragments of JSON lines. This reads every pack the pull request touched, on
# both sides, keys the entries by work slug ACROSS those packs, and prints each
# entry that is new, different or gone, in full:
#
#   === ENTRY <slug> (ADDED)      the new entry
#   === ENTRY <slug> (CHANGED)    the new entry, then the previous one
#   === ENTRY <slug> (REMOVED)    the previous entry
#
# An entry that a pack split merely MOVED is identical on both sides and is not
# printed at all. The base side is the merge base, so what main gained since the
# branch point is never read as the pull request's work.
#
# It writes nothing when no entry changed, and ai-verify.sh then skips.
set -euo pipefail

BASE="${1:?base sha required}"
HEAD="${2:?head sha required}"
OUT="${3:?output path required}"

MB="$(git merge-base "$BASE" "$HEAD")"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# The packs the pull request changed, on either side (a pack a split removed is
# still read on the base side).
git diff --name-only "$MB" "$HEAD" -- 'data/**/*.json' > "$tmp/files"

# One map of every entry in those packs, per side. A pack absent on a side
# contributes nothing.
side() {
  local rev="$1"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if git cat-file -e "$rev:$f" 2>/dev/null; then
      git show "$rev:$f"
    fi
  done < "$tmp/files" | jq -s 'map(.entries // {}) | add // {}'
}
side "$MB" > "$tmp/base.json"
side "$HEAD" > "$tmp/head.json"

# The slugs whose entry differs between the two sides, each with its kind.
jq -r -n --slurpfile b "$tmp/base.json" --slurpfile h "$tmp/head.json" '
  $b[0] as $B | $h[0] as $H
  | ([$B, $H] | map(keys) | add | unique)[] as $k
  | if ($B | has($k) | not) then "\($k)\tADDED"
    elif ($H | has($k) | not) then "\($k)\tREMOVED"
    elif $B[$k] != $H[$k] then "\($k)\tCHANGED"
    else empty end' > "$tmp/changed"

: > "$OUT"
while IFS=$'\t' read -r slug kind; do
  {
    echo "=== ENTRY $slug ($kind)"
    case "$kind" in
      ADDED)
        jq --arg k "$slug" '.[$k]' "$tmp/head.json" ;;
      CHANGED)
        echo "--- new"
        jq --arg k "$slug" '.[$k]' "$tmp/head.json"
        echo "--- previous"
        jq --arg k "$slug" '.[$k]' "$tmp/base.json" ;;
      REMOVED)
        jq --arg k "$slug" '.[$k]' "$tmp/base.json" ;;
    esac
    echo
  } >> "$OUT"
done < "$tmp/changed"

echo "ai-verify-context: $(wc -l < "$tmp/changed" | tr -d ' ') changed entries across $(wc -l < "$tmp/files" | tr -d ' ') packs"
