#!/usr/bin/env bash
# intake-sweep-test.sh - tests of the rebase sweep in intake.yml.
#
# Usage: bash .github/scripts/intake-sweep-test.sh
#
# The sweep is the one step that checks other people's branches out beside a
# write token, and it lives in the workflow file, so this lifts the step's own
# script out of .github/workflows/intake.yml and runs it the way GitHub does
# (bash -e) against a local bare origin. gh is a stub on PATH that serves the
# pull request listing and keeps the comments it is asked to post; `go build`
# is a stub that installs a metafmt and a metacheck which only record that they
# ran. Nothing reaches the network. Runs every case and exits non-zero if any
# failed. This repository's stand-in for core's scripts/intakesweep_test.go.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

# The step is written for the runner's bash (mapfile -d is 4.4) and coreutils.
# A machine without them cannot run it; CI must.
if [ "${BASH_VERSINFO[0]}" -lt 4 ] || { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -lt 4 ]; } \
    || ! command -v sha256sum > /dev/null || ! command -v jq > /dev/null; then
  if [ -n "${CI:-}" ]; then
    echo "intake-sweep-test: needs bash 4.4 or later, jq and sha256sum" >&2
    exit 1
  fi
  echo "intake-sweep-test: skipped (needs bash 4.4 or later, jq and sha256sum)"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAILED=0
fail() { echo "FAIL: $*" >&2; FAILED=1; }

# The step's script: the run block of the step, less its indent.
awk '
  /^      - name: Rebase open intake pull requests$/ { step = 1; next }
  step && !body && /^        run: \|$/ { body = 1; next }
  body && /^          / { print substr($0, 11); next }
  body && /^[ ]*$/ { print ""; next }
  body { exit }
' "$ROOT/.github/workflows/intake.yml" > "$WORK/sweep.sh"
grep -q 'git rebase' "$WORK/sweep.sh" || { echo "FAIL: could not read the sweep step out of intake.yml" >&2; exit 1; }

export GIT_CONFIG_GLOBAL="$WORK/gitconfig" GIT_CONFIG_NOSYSTEM=1
git config --global user.name test
git config --global user.email test@example.invalid
git config --global init.defaultBranch main
git config --global advice.detachedHead false

mkdir "$WORK/bin"
cat > "$WORK/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "pr list")
    printf '%s\n' "$*" > "$C/gh-list-args"
    [ -z "${LIST_FAIL:-}" ] || exit 1
    if [ -e "$C/listing" ]; then cat "$C/listing"; else jq -s . "$C/prs.jsonl"; fi ;;
  "api graphql") echo "intake-bot" ;;
  "pr view") jq -s --arg n "$3" '{comments: map(select(.number == $n))}' "$C/comments.jsonl" ;;
  "pr comment") jq -cn --arg n "$3" --arg b "$5" '{number: $n, author: {login: "intake-bot"}, body: $b}' >> "$C/comments.jsonl" ;;
  *) echo "gh stub: unexpected $*" >&2; exit 1 ;;
esac
EOF
# go build -o DIR/ ./cmd/metafmt ./cmd/metacheck. The tools it installs print
# what a workflow command looks like, as a real one quoting a branch's value
# could, and say so if they are ever run over a tree holding a symbolic link.
cat > "$WORK/bin/go" <<'EOF'
#!/usr/bin/env bash
for t in metafmt metacheck; do
  cat > "$3$t" <<TOOL
#!/usr/bin/env bash
echo "$t" >> "\$C/tools.log"
[ -z "\$(find "\$GITHUB_WORKSPACE/data" -type l)" ] || echo "$t saw a symbolic link" >> "\$C/tools.log"
echo "::error::forged by $t"
echo "$t says ##[error]forged mid-line"
TOOL
  chmod +x "$3$t"
done
EOF
chmod +x "$WORK/bin/gh" "$WORK/bin/go"

# new_case NAME: a bare origin and a seed clone holding one commit on main, a
# pack with the entry alpha.
new_case() {
  NAME="$1"
  # Exported: the gh stub and the stub tools keep their records under it.
  export C="$WORK/$1"
  mkdir -p "$C/rt"
  : > "$C/prs.jsonl"
  : > "$C/comments.jsonl"
  : > "$C/tools.log"
  prs=0
  git init -q --bare "$C/origin.git"
  git clone -q "$C/origin.git" "$C/seed" 2> /dev/null
  mkdir -p "$C/seed/scripts"
  cp "$ROOT/scripts/pack-union-merge.sh" "$C/seed/scripts/"
  cp "$ROOT/.gitattributes" "$C/seed/"
  echo readme > "$C/seed/README.md"
  put data/works-community/0/0.json '{"entries":{"alpha":{"characters":{"x":1}}}}'
  commit base
  seed push -q origin main
  BASE="$(seed rev-parse HEAD)"
}
seed() { git -C "$C/seed" "$@"; }
# put PATH CONTENT, commit SUBJECT: one file into the seed, then a commit of
# everything.
put() { mkdir -p "$(dirname "$C/seed/$1")" && printf '%s\n' "$2" > "$C/seed/$1"; }
commit() { seed add -A && seed commit -q -m "$1"; }
# start: a fresh branch off the first commit, so every pull request is behind
# main once main moves.
start() { seed checkout -q -B work "$BASE"; }
# pr BRANCH [true]: the seed's HEAD becomes that branch on origin and a row of
# the listing (true: listed as a fork's). Rows are listed oldest first.
pr() {
  prs=$((prs + 1))
  seed push -q origin "HEAD:refs/heads/$1"
  jq -cn --argjson n "$prs" --arg b "$1" --arg s "$(seed rev-parse HEAD)" --argjson fork "${2:-false}" \
    '{number: $n, headRefName: $b, headRefOid: $s, isCrossRepository: $fork, updatedAt: "2026-01-0\($n)T00:00:00Z"}' >> "$C/prs.jsonl"
}
# main_moves PATH CONTENT: main gains a commit after the branches were cut.
main_moves() {
  seed checkout -q main
  put "$1" "$2"
  commit "main moves"
  seed push -q origin main
}
# sweep: a fresh clone of origin, as actions/checkout leaves it, and the step
# run in it under bash -e. $PRE runs in the clone first.
sweep() {
  rm -rf "$C/ws"
  git clone -q "$C/origin.git" "$C/ws"
  mkdir "$C/ws/core"
  code=0
  (cd "$C/ws" && eval "${PRE:-:}" && PATH="$WORK/bin:$PATH" RUNNER_TEMP="$C/rt" GITHUB_WORKSPACE="$C/ws" \
    LIST_FAIL="${LIST_FAIL:-}" bash -e "$WORK/sweep.sh") > "$C/log" 2>&1 || code=$?
}

# 2> /dev/null: the names case's tags make every ref name ambiguous to git,
# which resolves the full name first and warns each time.
tip() { git -C "$C/origin.git" rev-parse "refs/heads/$1" 2> /dev/null; }
exited() { [ "$code" -eq "$1" ] || fail "$NAME: the sweep exited $code, want $1: $(tail -n 3 "$C/log" | tr '\n' ' ')"; }
logged() { grep -qF -- "$1" "$C/log" || fail "$NAME: the log does not say '$1'"; }
# rebased BRANCH: on top of origin's main now. unmoved BRANCH SHA: not pushed.
rebased() { git -C "$C/origin.git" merge-base --is-ancestor refs/heads/main "refs/heads/$1" 2> /dev/null || fail "$NAME: $1 was not rebased onto main"; }
unmoved() { [ "$(tip "$1")" = "$2" ] || fail "$NAME: $1 was pushed"; }
# commented NUMBER TEXT: a comment on that pull request holds the text.
commented() {
  jq -e --arg n "$1" --arg t "$2" 'select(.number == $n and (.body | contains($t)))' "$C/comments.jsonl" > /dev/null \
    || fail "$NAME: no comment on #$1 holds '$2'"
}
# first_lines NUMBER MARKER SENTENCE: a comment on that pull request has a
# first line that opens with the marker and a second that opens with the
# sentence, the shape audiosilo-meta-sync's steward reads
# (watcher.IsSweepFailure) and core posts.
first_lines() {
  jq -e --arg n "$1" --arg m "$2" --arg t "$3" \
    'select(.number == $n and ((.body | split("\n")) as $l | ($l[0] | startswith($m)) and (($l[1] // "") | startswith($t))))' \
    "$C/comments.jsonl" > /dev/null \
    || fail "$NAME: no comment on #$1 opens with '$2' and then '$3'"
}
comments() { [ "$(wc -l < "$C/comments.jsonl" | tr -d ' ')" -eq "$1" ] || fail "$NAME: $(wc -l < "$C/comments.jsonl" | tr -d ' ') comment(s), want $1"; }
tools_ran() { [ "$(tr '\n' ' ' < "$C/tools.log")" = "$1" ] || fail "$NAME: the tools that ran were '$(tr '\n' ' ' < "$C/tools.log")', want '$1'"; }
# quiet: nothing git or a tool printed reached the log where the runner would
# act on it, which is outside a ::stop-commands::<token> ... ::<token>:: pair.
quiet() {
  awk '
    token == "" && /^::stop-commands::/ { token = substr($0, 18); next }
    token != "" && $0 == "::" token "::" { token = ""; next }
    token == "" && (/##\[/ || /^::error::forged/) { bad = 1 }
    END { exit bad || token != "" }
  ' "$C/log" || fail "$NAME: a workflow command from git or a tool reached the log live"
}

# A sweep goes on past the pull requests it cannot take: a refusal and a
# give-up each get their one comment, a fork is passed over, and the honest
# pull request behind main is rebased and pushed.
new_case sweep
start; ln -s ../../.git/config "$C/seed/data/works-community/l.json"; commit link; pr intake/issue-1
link_tip="$(tip intake/issue-1)"
start; put data/works-community/0/0.json '{"entries":{"alpha":{"characters":{"x":99}}}}'
commit 'clash ##[error]forged by a commit subject'; pr intake/issue-2
clash_tip="$(tip intake/issue-2)"
start; put data/works-community/f/f.json '{"entries":{"fork":{"recaps":{"y":2}}}}'; commit fork; pr fork-branch true
fork_tip="$(tip fork-branch)"
start; put data/works-community/b/b.json '{"entries":{"beta":{"recaps":{"y":2}}}}'; commit "intake: issue #4"; pr intake/issue-4
main_moves data/works-community/0/0.json '{"entries":{"alpha":{"characters":{"x":7}}}}'
sweep
exited 0
grep -q -- '--base main' "$C/gh-list-args" || fail "$NAME: the listing is not held to pull requests into main"
unmoved intake/issue-1 "$link_tip"
commented 1 "it changes something other than a regular file plainly named \`data/**/*.json\` (\`data/works-community/l.json\`)"
first_lines 1 "<!-- intake-sweep:not-rebased -->" "The intake bot does not rebase this pull request"
unmoved intake/issue-2 "$clash_tip"
first_lines 2 "<!-- intake-sweep:rebase-failed ${clash_tip} " \
  "The intake bot could not rebase this branch onto \`main\` mechanically: the pack merge could not resolve data/works-community/0/0.json"
unmoved fork-branch "$fork_tip"
logged "::warning::PR #3 is from a fork"
rebased intake/issue-4
logged "rebased 1 pull request(s)"
comments 2
tools_ran ""
quiet
# The same sweep again says nothing twice, and leaves the rebased branch alone.
done_tip="$(tip intake/issue-4)"
sweep
exited 0
comments 2
unmoved intake/issue-4 "$done_tip"
logged "already on top of main"

# Two branches adding entries to one pack: the driver merges them inside the
# replay, the trusted tools normalize and check the result, and what they
# print is not the runner's to act on.
new_case merge
start; put data/works-community/0/0.json '{"entries":{"alpha":{"characters":{"x":1}},"beta":{"recaps":{"y":2}}}}'
commit "intake: issue #1"; pr intake/issue-1
main_moves data/works-community/0/0.json '{"entries":{"alpha":{"characters":{"x":1}},"gamma":{"characters":{"z":3}}}}'
sweep
exited 0
rebased intake/issue-1
[ "$(git -C "$C/origin.git" show refs/heads/intake/issue-1:data/works-community/0/0.json | jq -c '.entries | keys')" = '["alpha","beta","gamma"]' ] \
  || fail "$NAME: the pushed pack does not hold both sides' entries"
tools_ran "metafmt metacheck "
comments 0
quiet

# What a branch may not carry, each refused before it is checked out: a link a
# merge commit adds (git log shows no diff for one), a submodule entry, a file
# outside data/ that a later commit removes again, a name written to be read
# as markdown, and an executable data file.
new_case refused
start; put data/works-community/b/b.json '{"entries":{"beta":{"recaps":{"y":2}}}}'; commit c1
seed checkout -q -B side "$BASE"; put data/works-community/c/c.json '{"entries":{}}'; commit side
seed checkout -q work; seed merge -q --no-ff --no-commit side 2> /dev/null
ln -s ../../.git/config "$C/seed/data/works-community/l.json"; commit "merge side"; pr intake/issue-1
start; seed update-index --add --cacheinfo "160000,${BASE},data/works-community/sub.json"; seed commit -q -m gitlink; pr intake/issue-2
seed reset -q --hard
start; put scripts/run-me.sh 'echo run me'; commit added; seed rm -q scripts/run-me.sh
put data/works-community/b/b.json '{"entries":{"beta":{"recaps":{"y":2}}}}'; commit removed; pr intake/issue-3
start; put 'x [click](http:evil.example) #1 @someone <!-- m -->.json' '{}'; commit markdown; pr intake/issue-4
# chmod in the working tree, not update-index: an index-only bit leaves the
# file modified, and main_moves's checkout of main would then abort.
start; put data/works-community/e/e.json '{"entries":{"eta":{"recaps":{"y":2}}}}'
chmod +x "$C/seed/data/works-community/e/e.json"; commit executable; pr intake/issue-5
before="$(for b in 1 2 3 4 5; do tip "intake/issue-$b"; done)"
main_moves README.md more
sweep
exited 0
[ "$(for b in 1 2 3 4 5; do tip "intake/issue-$b"; done)" = "$before" ] || fail "$NAME: a refused branch was pushed"
commented 1 "it changes something other than a regular file plainly named \`data/**/*.json\` (\`data/works-community/l.json\`)"
commented 2 "it changes something other than a regular file plainly named \`data/**/*.json\` (\`data/works-community/sub.json\`)"
commented 3 "it changes something other than a regular file plainly named \`data/**/*.json\` (\`scripts/run-me.sh\`)"
commented 4 "(\`x ?click??http?evil.example? ?1 ?someone ??-- m --?.json\`)"
commented 5 "it changes something other than a regular file plainly named \`data/**/*.json\` (\`data/works-community/e/e.json\`)"
comments 5
tools_ran ""
logged "rebased 0 pull request(s)"

# An entry key that is no slug: metafmt names a split pack after a key, so it
# is not run on the tree at all.
new_case keys
start; put data/works-community/0/0.json '{"entries":{"alpha":{"characters":{"x":1}},"a/../../../outside":{"recaps":{"y":2}}}}'
commit "intake: issue #1"; pr intake/issue-1
key_tip="$(tip intake/issue-1)"
main_moves data/works-community/0/0.json '{"entries":{"alpha":{"characters":{"x":1}},"gamma":{"characters":{"z":3}}}}'
sweep
exited 0
unmoved intake/issue-1 "$key_tip"
tools_ran ""
commented 1 "metafmt could not normalize the merged tree"

# Names chosen to be mistaken for main: a branch called HEAD (origin/HEAD is
# git's pointer at origin/main) and tags spelled like every ref the sweep
# reads, all at a commit that rewrites the merge driver. The honest pull
# request still lands on the real main and nothing of that commit is pushed;
# the branch called HEAD is seen as behind main, then fails as no branch name.
new_case names
start; put data/works-community/h/h.json '{"entries":{"eta":{"recaps":{"y":2}}}}'; commit "a branch named HEAD"; pr HEAD
head_tip="$(tip HEAD)"
start; put data/works-community/b/b.json '{"entries":{"beta":{"recaps":{"y":2}}}}'; commit "intake: issue #2"; pr intake/issue-2
main_moves README.md more
real_main="$(tip main)"
seed checkout -q -B evil main; put scripts/pack-union-merge.sh 'echo run me'; commit evil
for t in main origin/main refs/heads/main refs/remotes/origin/main refs/intake-sweep/main refs/intake-sweep/head \
    intake/issue-2 origin/intake/issue-2; do
  seed tag "$t" evil
done
seed push -q origin --tags
sweep
exited 0
unmoved HEAD "$head_tip"
commented 1 "the branch could not be checked out"
unmoved main "$real_main"
rebased intake/issue-2
[ "$(git -C "$C/origin.git" rev-parse "refs/heads/intake/issue-2~1" 2> /dev/null)" = "$real_main" ] \
  || fail "$NAME: intake/issue-2 was not rebased onto the real main"
logged "rebased 1 pull request(s)"

# A rebase that fails without a conflict has left a tree nobody checked: the
# tools are not run over it.
new_case stopped
start; put data/works-community/b/b.json '{"entries":{"beta":{"recaps":{"y":2}}}}'; commit "intake: issue #1"; pr intake/issue-1
stop_tip="$(tip intake/issue-1)"
main_moves README.md more
PRE='mkdir .git/rebase-merge' sweep
exited 0
unmoved intake/issue-1 "$stop_tip"
tools_ran ""
commented 1 "the rebase stopped without a conflict to resolve"

# A listing that fails, or is anything but a JSON array, is a red step and not
# "no open intake pull requests"; an empty array is that, and green.
new_case listing
start; put data/works-community/b/b.json '{"entries":{"beta":{"recaps":{"y":2}}}}'; commit "intake: issue #1"; pr intake/issue-1
list_tip="$(tip intake/issue-1)"
main_moves README.md more
for reply in '' '{"message":"Bad credentials"}'; do
  printf '%s' "$reply" > "$C/listing"
  sweep
  exited 1
  logged "::error::could not list the open intake pull requests"
done
rm "$C/listing"
LIST_FAIL=1 sweep
exited 1
logged "::error::could not list the open intake pull requests"
echo '[]' > "$C/listing"
sweep
exited 0
logged "no open intake pull requests"
unmoved intake/issue-1 "$list_tip"

if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
echo "intake-sweep-test: ok"
