#!/usr/bin/env bash
# core-ref-test.sh - tests of core-ref.sh, the reader of the core tooling pin.
#
# Usage: bash .github/scripts/core-ref-test.sh
#
# gh is a stub on PATH that answers the compare call with STATUS (or fails with
# GH_FAIL set) and records the endpoint it was asked; nothing reaches the
# network. Each case runs a copy of core-ref.sh beside its own .github/core-ref.
# Runs every case and exits non-zero if any failed.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAILED=0
fail() { echo "FAIL: $*" >&2; FAILED=1; }

mkdir -p "$WORK/bin" "$WORK/repo/.github/scripts"
cp "$HERE/core-ref.sh" "$WORK/repo/.github/scripts/core-ref.sh"
cat > "$WORK/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$WORK/gh-args"
if [ -n "${GH_FAIL:-}" ]; then echo "gh: Not Found (HTTP 404)" >&2; exit 1; fi
printf '%s\n' "$STATUS"
EOF
chmod +x "$WORK/bin/gh"

SHA=0123456789abcdef0123456789abcdef01234567

# run PIN STATUS [GH_FAIL]: the script's exit code in $code, stdout in $out.
run() {
  printf '%s\n' "$1" > "$WORK/repo/.github/core-ref"
  rm -f "$WORK/gh-args"
  out="$(PATH="$WORK/bin:$PATH" WORK="$WORK" STATUS="$2" GH_FAIL="${3:-}" CORE_REPO=example/core \
    bash "$WORK/repo/.github/scripts/core-ref.sh" 2> "$WORK/stderr")"
  code=$?
}

# A commit of main, or main's tip, is the pin.
for status in behind identical; do
  run "$SHA" "$status"
  [ "$code" -eq 0 ] || fail "$status: exit $code, want 0 ($(cat "$WORK/stderr"))"
  [ "$out" = "CORE_REF=$SHA" ] || fail "$status: printed '$out'"
done
grep -q "repos/example/core/compare/main...$SHA" "$WORK/gh-args" \
  || fail "the compare call names main...<sha> on CORE_REPO: $(cat "$WORK/gh-args")"

# A commit not on main - a fork's, which GitHub serves through the parent, or
# another branch's - prints nothing for GITHUB_ENV.
for status in ahead diverged ""; do
  run "$SHA" "$status"
  [ "$code" -ne 0 ] || fail "status '$status': exit 0, want a failure"
  [ -z "$out" ] || fail "status '$status': printed '$out'"
done

# The API answering nothing (a sha it cannot find, or an outage) is a failure.
run "$SHA" behind 1
[ "$code" -ne 0 ] || fail "a failed compare call: exit 0, want a failure"
[ -z "$out" ] || fail "a failed compare call: printed '$out'"

# A malformed pin fails before any API call.
for pin in main "${SHA:0:12}" "${SHA}0" "$(printf '%s' "$SHA" | tr 'a-f' 'A-F')"; do
  run "$pin" behind
  [ "$code" -ne 0 ] || fail "pin '$pin': exit 0, want a failure"
  [ ! -e "$WORK/gh-args" ] || fail "pin '$pin': gh was called"
done

if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
echo "core-ref-test: ok"
