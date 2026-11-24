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
# 2. The rebase job's core steps are .github/actions/core-tooling's, the one copy
#    every other job uses (the job says why it writes the steps out): the pin
#    read through core-ref.sh, then every step of the action from its checkout
#    on with nothing between, every input and its indentation, so the ref's
#    unread-pin fallback, the credential, the sparse list and its mode included,
#    and each step's `uses:` version, with only the names that say where the
#    steps live (the action's inputs and pin output, the job's env) set aside.
#    dependabot.yml groups each of those actions' bumps across both places into
#    one pull request, so a bump that reaches one copy alone is a difference
#    here. And no other workflow checks core out.
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
# either way round (the group comes first in the file), and so is either block
# gone missing.
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
perl -pe 's/^    if: >-$/    if: x/' "$WORKFLOW" > "$WORK/noif.yml"
for mutated in group if nogroup noif; do
  if copies_if "$WORK/$mutated.yml" 2>/dev/null; then
    fail "the check passed with the $mutated copy changed"
  fi
done

# steps_from <file> <name> [<count>]: <count> steps of <file> (every step to the
# end of its list when not given) from the one named `- name: <name>`, as <file>
# writes them: each line with its indentation taken relative to that step's dash,
# so a key indented into a block scalar above it (cone mode swallowed into the
# sparse list) is a difference, trailing blanks, comments and blank lines dropped,
# and the action's names for the repository and the pin spelled as the job's env.
# Empty when there is no such step.
steps_from() {
  awk -v name="$2" -v max="${3:-0}" '
    !found && match($0, /^ *- name: /) && substr($0, RLENGTH + 1) == name { found = 1; ind = RLENGTH - 8 }
    found && NF {
      match($0, /^ */)
      if (RLENGTH < ind || (RLENGTH == ind && /^ *- / && ++steps > max && max > 0)) exit
      line = substr($0, ind + 1); sub(/[[:space:]]+$/, "", line)
      if (line ~ /^[[:space:]]*#/) next
      gsub(/inputs\.core-repo/, "env.CORE_REPO", line); gsub(/steps\.pin\.outputs\.ref/, "env.CORE_REF", line)
      print line
    }
  ' "$1"
}

# The rebase job's pin read, which the action's differs from only in where it
# writes the sha: core-ref.sh, and so its on-main check, with the read-only token.
PIN_STEP='- name: Read the core tooling pin
  env:
    GH_TOKEN: ${{ github.token }}
  run: bash .github/scripts/core-ref.sh >> "$GITHUB_ENV"'

# same_steps <workflow> [<action>]: succeeds when <workflow> reads the pin with
# PIN_STEP and then writes every step of the action from its core checkout on
# out, with no step between.
same_steps() {
  local action="${2:-$ACTION}" steps want got
  steps="$(steps_from "$action" "Checkout the core tooling")"
  want="$PIN_STEP"$'\n'"$steps"
  got="$(steps_from "$1" "Read the core tooling pin" "$(($(printf '%s\n' "$steps" | grep -c '^- ') + 1))")"
  if [ "$got" != "$want" ]; then
    printf 'the core steps in %s:\n%s\nwant the pin read and the action'"'"'s:\n%s\n' "$1" "$got" "$want" >&2
    return 1
  fi
}

[ -n "$(steps_from "$ACTION" "Checkout the core tooling")" ] || fail "core-tooling/action.yml has no \`Checkout the core tooling\` step"
same_steps "$WORKFLOW" || fail "intake.yml: the rebase job's core steps are not the action's"
# The rebase job's is the one core checkout a workflow writes out: a
# `repository:` naming core, sparse or not.
for wf in "$HERE"/../workflows/*.yml "$HERE"/../workflows/*.yaml; do
  [ -e "$wf" ] || continue
  want=0
  [ "$wf" != "$WORKFLOW" ] || want=1
  have="$(grep -cE '^[[:space:]]*repository:.*(CORE_REPO|core-repo|audiosilo-meta([^-[:alnum:]]|$))' "$wf" || true)"
  [ "$have" = "$want" ] || fail "$(basename "$wf") checks core out $have time(s), want $want (only intake.yml's rebase job writes core's checkout out)"
done
# Each change below, made to the rebase job's copy alone, fails the check.
n=0
for program in \
  's/^\s+schema\.go\n//' \
  "s/env\\.CORE_REF \\|\\| 'core-ref-not-read'/env.CORE_REF/" \
  's/^\s+persist-credentials: false\n//' \
  's/^(\s+sparse-checkout-cone-mode:) false$/$1 true/' \
  's/^(\s+)(sparse-checkout-cone-mode: false)$/$1  $2/' \
  's/core-ref\.sh >>/core-ref-unchecked.sh >>/' \
  's/^(\s+)(- name: Checkout the core tooling)$/$1- run: echo CORE_REF=0 >> "\$GITHUB_ENV"\n$1$2/' \
  's/^(\s+uses: actions\/setup-go)@\S+$/$1\@v0/'; do
  n=$((n + 1))
  perl -pe "$program" "$WORKFLOW" > "$WORK/steps-$n.yml"
  if cmp -s "$WORKFLOW" "$WORK/steps-$n.yml"; then
    fail "the change $program left intake.yml as it was"
  elif same_steps "$WORK/steps-$n.yml" 2>/dev/null; then
    fail "the check passed with the rebase job's copy changed by $program"
  fi
done
# And so does a change made to the action alone: a step it gains after its Go
# set-up, written out nowhere, or a version bumped there alone.
for program in \
  's/^(\s+)(go-version-file: core\/go\.mod)$/$1$2\n\n    - name: More\n      shell: bash\n      run: "true"/' \
  's/^(\s+uses: actions\/checkout)@\S+$/$1\@v0/'; do
  n=$((n + 1))
  perl -pe "$program" "$ACTION" > "$WORK/action-$n.yml"
  if cmp -s "$ACTION" "$WORK/action-$n.yml"; then
    fail "the change $program left action.yml as it was"
  elif same_steps "$WORKFLOW" "$WORK/action-$n.yml" 2>/dev/null; then
    fail "the check passed with the action alone changed by $program"
  fi
done

if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
echo "workflow-copies-test: ok"
