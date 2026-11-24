#!/usr/bin/env bash
# workflow-copies-test.sh - the two things the workflows keep as copies still match.
#
# Usage: bash .github/scripts/workflow-copies-test.sh
#
# 1. intake.yml's concurrency group carries the intake job's `if` whole. GitHub
#    keeps one PENDING run per concurrency group, so intake.yml sends an event
#    its job will skip to a `-noop` group and a real one to `run`, deciding which
#    by a VERBATIM copy of the job's `if` (the comment above the group says why).
#    A copy that drifts puts a real run in the group where a skipped event can
#    replace it while it waits, and the submission gets no pull request and no
#    comment. The two are compared with whitespace removed (they are wrapped
#    differently, and no label or event name holds a space). Core's
#    scripts/intakeconcurrency_test.go checks core's intake.yml the same way.
# 2. The rebase job's core checkout and Go set-up are .github/actions/core-tooling's,
#    the one copy every other job uses (the job says why it writes the steps
#    out): every input, so the ref's unread-pin fallback, the credential, the
#    sparse list and its mode included, with only the names that say where the
#    steps live (the action's inputs and pin output, the job's env) and the
#    actions' versions (dependabot moves each copy's) set aside. And no other
#    workflow writes a core checkout out.
#
# Each check is then shown to catch a change made to one side alone. Needs bash,
# awk and perl; no network.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOW="$HERE/../workflows/intake.yml"
ACTION="$HERE/../actions/core-tooling/action.yml"

# The group's text around the copied condition, whitespace removed.
HEAD="\${{github.event_name=='push'&&'intake-rebase'||format('intake-{0}-{1}',github.event.issue.number,("
TAIL=")&&'run'||'noop')}}"

# folded <file> <header>: the `>-` block scalar under the line equal to <header>
# (indentation included), whitespace removed; empty when there is no such line.
folded() {
  awk -v h="$2" '
    found && NF { match($0, /^ */); if (RLENGTH <= ind) exit }
    found { gsub(/[[:space:]]/, ""); printf "%s", $0 }
    !found && $0 == h { found = 1; match($0, /^ */); ind = RLENGTH }
  ' "$1"
}

# copies_if <file>: succeeds when the file's concurrency group is HEAD, the
# intake job's whole `if`, then TAIL; otherwise says how they differ.
copies_if() {
  local group cond
  group="$(folded "$1" "  group: >-")"
  cond="$(folded "$1" "    if: >-")"
  if [ -z "$group" ] || [ -z "$cond" ]; then
    echo "no concurrency \`group: >-\` or intake job \`if: >-\` block in $1" >&2
    return 1
  fi
  if [ "$group" != "$HEAD$cond$TAIL" ]; then
    printf 'the concurrency group is not the job'"'"'s `if` copied whole:\n group %s\n want  %s\n' \
      "$group" "$HEAD$cond$TAIL" >&2
    return 1
  fi
}

FAILED=0
fail() { echo "FAIL: $*" >&2; FAILED=1; }

copies_if "$WORKFLOW" || fail "intake.yml: the concurrency group and the intake job's if differ"

# The check itself: a label changed in only one of the two copies is caught
# either way round (the group comes first in the file), and so is a missing block.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
LABEL="github.event.label.name != 'data:duplicate'"
[ "$(grep -cF "$LABEL" "$WORKFLOW")" = 2 ] || fail "intake.yml should name \"$LABEL\" twice (the group and the job)"
# change_nth <n>: the workflow with the n-th line naming LABEL changed.
change_nth() {
  N="$1" LABEL="$LABEL" perl -pe 'if (index($_, $ENV{LABEL}) >= 0 && ++$n == $ENV{N}) { s/data:duplicate/data:other/ }' "$WORKFLOW"
}
change_nth 1 > "$WORK/group.yml"
change_nth 2 > "$WORK/if.yml"
perl -pe 's/^  group: >-$/  group: x/' "$WORKFLOW" > "$WORK/nogroup.yml"
for mutated in group if nogroup; do
  if copies_if "$WORK/$mutated.yml" 2>/dev/null; then
    fail "the check passed with the $mutated copy changed"
  fi
done

# sparse_lists <file>: every `sparse-checkout: |` list in <file>, one entry per
# line, trimmed, each list ended by a `--` line.
sparse_lists() {
  awk '
    found && NF { match($0, /^ */); if (RLENGTH <= ind) { print "--"; found = 0 } }
    found && NF { gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print }
    !found && /^ *sparse-checkout: \|$/ { found = 1; match($0, /^ */); ind = RLENGTH }
    END { if (found) print "--" }
  ' "$1"
}

# core_steps <file>: the core checkout and the Go set-up step after it, as
# <file> writes them: from `- name: Checkout the core tooling` to the end of the
# next step, each line trimmed, comments and blank lines dropped, the action's
# names for the repository and the pin spelled as the job's env, and every
# `uses:` without its version. Empty when there is no such step.
core_steps() {
  awk '
    !found && /^ *- name: Checkout the core tooling$/ { found = 1; match($0, /^ */); ind = RLENGTH }
    found && NF {
      match($0, /^ */)
      if (RLENGTH < ind || (RLENGTH == ind && /^ *- / && ++steps > 2)) exit
      sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+$/, "")
      if (/^#/) next
      gsub(/inputs\.core-repo/, "env.CORE_REPO"); gsub(/steps\.pin\.outputs\.ref/, "env.CORE_REF")
      if (/^uses: /) sub(/@.*$/, "")
      print
    }
  ' "$1"
}

# same_steps <file>: succeeds when <file> writes the action's core steps out.
same_steps() {
  local want got
  want="$(core_steps "$ACTION")"
  got="$(core_steps "$1")"
  if [ "$got" != "$want" ]; then
    printf 'the core steps in %s:\n%s\nwant the action'"'"'s:\n%s\n' "$1" "$got" "$want" >&2
    return 1
  fi
}

[ -n "$(core_steps "$ACTION")" ] || fail "core-tooling/action.yml has no \`Checkout the core tooling\` step"
same_steps "$WORKFLOW" || fail "intake.yml: the rebase job's core steps are not the action's"
# The rebase job's is the one core checkout a workflow writes out.
for wf in "$HERE"/../workflows/*.yml; do
  want=0
  [ "$wf" != "$WORKFLOW" ] || want=1
  have="$(sparse_lists "$wf" | grep -c -- '^--$' || true)"
  [ "$have" = "$want" ] || fail "$(basename "$wf") holds $have sparse checkout list(s), want $want (only intake.yml's rebase job writes core's checkout out)"
done
# Each change below, made to the rebase job's copy alone, fails the check.
n=0
for program in \
  's/^\s+schema\.go\n//' \
  "s/env\\.CORE_REF \\|\\| 'core-ref-not-read'/env.CORE_REF/" \
  's/^\s+persist-credentials: false\n//' \
  's/^(\s+sparse-checkout-cone-mode:) false$/$1 true/'; do
  n=$((n + 1))
  perl -pe "$program" "$WORKFLOW" > "$WORK/steps-$n.yml"
  if cmp -s "$WORKFLOW" "$WORK/steps-$n.yml"; then
    fail "the change $program left intake.yml as it was"
  elif same_steps "$WORK/steps-$n.yml" 2>/dev/null; then
    fail "the check passed with the rebase job's copy changed by $program"
  fi
done

if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
echo "workflow-copies-test: ok"
