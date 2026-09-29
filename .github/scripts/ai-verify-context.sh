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
#   === ENTRY <slug> (CHANGED)    a line naming the members the pull request
#                                 changes, each (added|changed|removed), then
#                                 the new entry, then the previous version of
#                                 each member that changed (an unchanged member
#                                 is printed once, in the new entry)
#   === ENTRY <slug> (REMOVED)    the previous entry
#
# An entry that a pack split merely MOVED is identical on both sides and is not
# printed at all. The base side is the merge base, so what main gained since the
# branch point is never read as the pull request's work.
#
# It writes nothing when no entry changed (a pure re-render or pack split), and
# ai-verify.yml then records a storage-only pass without calling the model.
set -euo pipefail

BASE="${1:?base sha required}"
HEAD="${2:?head sha required}"
OUT="${3:?output path required}"

MB="$(git merge-base "$BASE" "$HEAD")"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# The packs the pull request changed, on either side (a pack a split removed is
# still read on the base side). --no-renames is load-bearing: with rename
# detection (git's default) a pack whose file name changed is listed under its
# NEW name only, the base side never reads the old one, and every entry in it
# would be rendered as ADDED.
git diff --no-renames --name-only "$MB" "$HEAD" -- 'data/**/*.json' > "$tmp/files"

# One map of every entry in those packs, per side. A pack absent on a side
# contributes nothing; any OTHER failure to read one fails the run, because a
# side read as empty would turn its entries into ADDED or REMOVED ones (or, on
# both sides, into "nothing changed").
side() {
  local rev="$1"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    git cat-file -e "$rev:$f" 2>/dev/null || continue
    git show "$rev:$f"
  done < "$tmp/files" | jq -s 'map(.entries // {}) | add // {}'
}
side "$MB" > "$tmp/base.json"
side "$HEAD" > "$tmp/head.json"

# Every entry that differs between the two sides, rendered in ONE jq pass:
# under -r a string prints raw (the headers) and an object pretty (the entry).
jq -r -n --slurpfile b "$tmp/base.json" --slurpfile h "$tmp/head.json" '
  $b[0] as $B | $h[0] as $H
  | ([$B, $H] | map(keys) | add | unique)[] as $k
  | if ($B | has($k) | not) then "=== ENTRY \($k) (ADDED)", $H[$k], ""
    elif ($H | has($k) | not) then "=== ENTRY \($k) (REMOVED)", $B[$k], ""
    elif $B[$k] != $H[$k] then
      (($B[$k] + $H[$k]) | keys | map(. as $m
        | select(($B[$k] | has($m)) != ($H[$k] | has($m)) or $B[$k][$m] != $H[$k][$m]))) as $changed
      | "=== ENTRY \($k) (CHANGED)",
      "--- this pull request changes: " + ($changed | map(. as $m | "\($m) (\(if ($B[$k] | has($m) | not) then "added"
        elif ($H[$k] | has($m) | not) then "removed" else "changed" end))") | join(", ")),
      "--- new", $H[$k],
      "--- previous (the members that changed)", ($B[$k] | with_entries(select(.key | IN($changed[])))), ""
    else empty end' > "$OUT"

echo "ai-verify-context: $(grep -c '^=== ENTRY ' "$OUT" || true) changed entries across $(wc -l < "$tmp/files" | tr -d ' ') packs"
