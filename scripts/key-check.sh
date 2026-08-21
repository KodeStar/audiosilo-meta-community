#!/usr/bin/env bash
#
# Check every works-community entry key against a built meta.sqlite artifact.
#
# The one cross-repo rule this repository cannot check on its own: an entry key
# IS a core work slug (KodeStar/audiosilo-meta, data/works/). Standalone
# validation - metacheck --profile community - covers everything WITHIN the
# family (schema, caps, placement, member rules) and deliberately stands down on
# the parent-work rule, because the works family is not in this tree. So the
# artifact stands in for it: the newest data release is the catalogue as the
# world currently sees it.
#
# Three verdicts per key:
#
#   live       works.id holds it                                pass
#   retired    redirects(kind='works', old_slug=key) holds it    FAIL, re-key
#   unknown    neither                                          FAIL, name it
#
# A retired key still RESOLVES for a reader (metaserve answers 301), so it is no
# correctness emergency - but it must not land in a pull request as-is: the fix
# is mechanical (rename the entry to the new slug, re-run metafmt), and leaving
# it defers the rename to whoever hits it next.
#
# The check is stale in ONE direction, deliberately: a work added to core after
# the newest data release has no row yet and reports as unknown. That is the
# intended failure - wait for the release, or cut one - because the alternative
# (passing an unknown key) is exactly what a dangling sidecar looks like. The
# authoritative check remains core's release build over both checkouts.
#
# Usage:
#   scripts/key-check.sh <meta.sqlite> [data-dir]
#
# Needs: sqlite3, jq. Exits 0 clean, 1 with findings, 2 on a usage/tool error.
set -euo pipefail

db=${1:-}
data=${2:-data}
if [ -z "$db" ]; then
  echo "usage: $0 <meta.sqlite> [data-dir]" >&2
  exit 2
fi
for tool in sqlite3 jq; do
  command -v "$tool" >/dev/null || { echo "key-check: $tool is required" >&2; exit 2; }
done
[ -f "$db" ] || { echo "key-check: no such artifact: $db" >&2; exit 2; }
[ -d "$data/works-community" ] || { echo "key-check: no such directory: $data/works-community" >&2; exit 2; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
keys="$work/keys.tsv"

# One row per entry: the file it sits in (for the report) and its key. Sorted so
# the report is deterministic whatever order the walk hands the files over in.
find "$data/works-community" -type f -name '*.json' -print0 |
  xargs -0 jq -r 'input_filename as $f | (.entries // {}) | keys_unsorted[] | [$f, .] | @tsv' |
  LC_ALL=C sort > "$keys"

total=$(wc -l < "$keys" | tr -d ' ')
if [ "$total" -eq 0 ]; then
  echo "key-check: no entries found under $data/works-community" >&2
  exit 2
fi

# An artifact older than schema_version 5 carries no redirects table. Treat that
# as "no tombstones recorded": a retired key is then simply unknown, which is the
# honest answer for a release predating the mechanism.
has_redirects=$(sqlite3 "$db" \
  "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='redirects';")

# Retired: the catalogue has tombstoned this slug. Mechanical fix, named.
retired_sql="
SELECT 'retired', k.file, k.slug, r.new_slug
FROM entry_keys k
JOIN redirects r ON r.kind = 'works' AND r.old_slug = k.slug
LEFT JOIN works w ON w.id = k.slug
WHERE w.id IS NULL
ORDER BY k.slug;
"
# Unknown: no live work, and no tombstone naming one. A tombstone whose target
# the catalogue does not hold counts here too - it resolves to nothing.
unknown_sql="
SELECT 'unknown', k.file, k.slug, ''
FROM entry_keys k
LEFT JOIN works w ON w.id = k.slug
LEFT JOIN redirects r ON r.kind = 'works' AND r.old_slug = k.slug
LEFT JOIN works t ON t.id = r.new_slug
WHERE w.id IS NULL AND (r.old_slug IS NULL OR t.id IS NULL)
ORDER BY k.slug;
"
if [ "$has_redirects" = "0" ]; then
  echo "key-check: artifact carries no redirects table (pre-schema_version-5); a retired key reports as unknown" >&2
  retired_sql=""
  unknown_sql="
SELECT 'unknown', k.file, k.slug, ''
FROM entry_keys k
LEFT JOIN works w ON w.id = k.slug
WHERE w.id IS NULL
ORDER BY k.slug;
"
fi

report="$work/report.tsv"
sqlite3 "$db" > "$report" <<SQL
.bail on
.mode tabs
CREATE TEMP TABLE entry_keys(file TEXT, slug TEXT);
.import '$keys' entry_keys
CREATE INDEX temp.idx_entry_keys ON entry_keys(slug);
$retired_sql
$unknown_sql
SQL

retired=0
unknown=0
while IFS=$'\t' read -r kind file slug target; do
  [ -n "${kind:-}" ] || continue
  case "$kind" in
    retired)
      retired=$((retired + 1))
      echo "$file: entry \"$slug\" names a RETIRED work slug - re-key to $target"
      ;;
    unknown)
      unknown=$((unknown + 1))
      echo "$file: entry \"$slug\" names no work in the catalogue"
      ;;
  esac
done < "$report"

bad=$((retired + unknown))
if [ "$bad" -gt 0 ]; then
  echo "key-check: $bad of $total entry key(s) do not resolve ($retired retired, $unknown unknown)" >&2
  exit 1
fi
echo "key-check: all $total entry keys resolve to live works" >&2
