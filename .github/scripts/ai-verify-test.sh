#!/usr/bin/env bash
# ai-verify-test.sh - tests of ai-verify.sh's transport and its flag comment.
#
# Usage: bash .github/scripts/ai-verify-test.sh
#
# The community repository has no Go module, so these are the shell half of core's
# scripts/aiverify_test.go cases for the shared transport (TestAIVerifyPrefersTheAPIKey,
# TestAIVerifyAPIRequestIsNeverAnArgument, TestAIVerifyLeavesNoTempFiles) and the
# comment's pass note and flag lead (TestAIVerifyCommentSaysWhatTheVerdictDoes,
# its bot-origin case). The claude CLI,
# curl and timeout are stubs on PATH; nothing reaches the network. Needs bash, jq and perl,
# as the script itself does. Runs every case and exits non-zero if any failed.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/ai-verify.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

REAL_JQ="$(command -v jq)" || { echo "ai-verify-test: jq is required" >&2; exit 2; }
FAILED=0
fail() { echo "FAIL: $*" >&2; FAILED=1; }

# argLimit refuses what Linux's execve refuses: one argument over MAX_ARG_STRLEN
# (128 KiB with its NUL). macOS has no such limit, so without it a request passed
# as an argument would only fail on the runners.
ARG_LIMIT='#!/usr/bin/env bash
for a in "$@"; do
  if [ "${#a}" -gt 131071 ]; then echo "$0: Argument list too long (${#a} bytes)" >&2; exit 126; fi
done
'

BIN="$WORK/bin"
mkdir -p "$BIN"
# The claude stub records that it ran and its stdin, and answers a pass or, with
# REPLY_FILE set, that file's contents.
cat > "$BIN/claude" <<'EOF'
#!/usr/bin/env bash
cat > "$OUTDIR/stdin.txt"
if [ -n "${REPLY_FILE:-}" ]; then cat "$REPLY_FILE"; exit 0; fi
printf '%s' '{"result":"{\"verdict\":\"pass\",\"findings\":[]}"}'
EOF
# The curl stub notes that it ran, keeps the request body it read on stdin and
# answers the Messages API with a pass.
{
  printf '%s' "$ARG_LIMIT"
  cat <<'EOF'
touch "$OUTDIR/curl-called"
cat > "$OUTDIR/request.json"
printf '%s' '{"content":[{"type":"text","text":"{\"verdict\":\"pass\",\"findings\":[]}"}]}'
EOF
} > "$BIN/curl"
# jq behind the same argument limit.
printf '%sexec "%s" "$@"\n' "$ARG_LIMIT" "$REAL_JQ" > "$BIN/jq"
# The timeout stub stands in for GNU timeout, which older macOS does not ship: it
# drops the options and the duration and runs the command, as timeout does when
# the command answers in time.
cat > "$BIN/timeout" <<'EOF'
#!/usr/bin/env bash
while [ "${1#-}" != "$1" ]; do shift; done
shift
exec "$@"
EOF
chmod +x "$BIN/claude" "$BIN/curl" "$BIN/jq" "$BIN/timeout"

CONTEXT="$WORK/context.txt"
printf '=== ENTRY a-work (ADDED)\n{"characters": {}}\n' > "$CONTEXT"

# invoke <name> <context> [VAR=value ...]: ai-verify.sh over <context> with the stubs
# first on PATH and nothing else inherited, so a key in the caller's environment
# cannot reach it (a VAR given here, PATH and TMPDIR included, replaces the
# default). Leaves its files in $WORK/<name>/ and returns the script's status.
invoke() {
  local out="$WORK/$1" context="$2"
  shift 2
  mkdir -p "$out"
  env -i PATH="$BIN:$PATH" HOME="$out" TMPDIR="$out" OUTDIR="$out" "$@" \
    bash "$SCRIPT" "$context" "$out/verdict.json" "$out/comment.md" > "$out/log.txt" 2>&1
}
# run: invoke, which must exit zero.
run() { invoke "$@" || fail "$1: ai-verify.sh exited non-zero: $(cat "$WORK/$1/log.txt")"; }

# With both credentials the API key is used (billed per pull request, not the
# subscription meta-sync's resolver shares); with the subscription token alone
# the CLI still is.
run both "$CONTEXT" CLAUDE_CODE_OAUTH_TOKEN=test ANTHROPIC_API_KEY=key
[ -e "$WORK/both/curl-called" ] || fail "both credentials: curl was not called"
[ ! -e "$WORK/both/stdin.txt" ] || fail "both credentials: the CLI was called"
grep -q '"verdict":"pass"' "$WORK/both/verdict.json" || fail "both credentials: verdict $(cat "$WORK/both/verdict.json")"

run oauth "$CONTEXT" CLAUDE_CODE_OAUTH_TOKEN=test
[ ! -e "$WORK/oauth/curl-called" ] || fail "subscription token alone: curl was called"
[ -s "$WORK/oauth/stdin.txt" ] || fail "subscription token alone: the CLI was not called"

# ai-verify.yml installs no CLI when the key is set, so the key must reach a
# verdict on a PATH with no `claude` at all: the curl and jq stubs alone, ahead
# of the caller's PATH less every directory that holds one.
NOCLI_BIN="$WORK/bin-nocli"
mkdir -p "$NOCLI_BIN"
cp "$BIN/curl" "$BIN/jq" "$NOCLI_BIN/"
NOCLI_PATH="$NOCLI_BIN"
while IFS= read -r -d : dir; do
  if [ -n "$dir" ] && [ ! -x "$dir/claude" ]; then NOCLI_PATH="$NOCLI_PATH:$dir"; fi
done <<< "$PATH:"
run nocli "$CONTEXT" ANTHROPIC_API_KEY=key PATH="$NOCLI_PATH"
[ -e "$WORK/nocli/curl-called" ] || fail "the key with no CLI installed: curl was not called"
grep -q '"verdict":"pass"' "$WORK/nocli/verdict.json" || fail "the key with no CLI installed: verdict $(cat "$WORK/nocli/verdict.json" 2>/dev/null)"

# On the API key transport the prompt and the message reach jq as files and the
# request reaches curl on stdin. One entry can run to MAX_INPUT_BYTES (200 kB),
# past the 128 KiB Linux allows one argument, where jq or curl handed it as one
# does not start and the run is a skip.
BIG="$WORK/big.txt"
{
  echo '=== ENTRY a-long-work (ADDED)'
  "$REAL_JQ" -n '{characters: [range(0; 1200) | {id: "c\(.)", name: "A character named \(.)", description: "Somebody the reader meets early on, described at length."}]}'
} > "$BIG"
[ "$(wc -c < "$BIG")" -gt 140000 ] && [ "$(wc -c < "$BIG")" -lt 200000 ] || fail "the large context is $(wc -c < "$BIG") bytes, want 140-200 kB"
run big "$BIG" ANTHROPIC_API_KEY=key
REQ="$WORK/big/request.json"
if ! "$REAL_JQ" -e . "$REQ" > /dev/null 2>&1; then
  fail "the request curl read on stdin is not JSON: $(head -c 200 "$REQ" 2>/dev/null)"
else
  MAX_TOKENS="$("$REAL_JQ" -r '.max_tokens' "$REQ")"
  [ "$MAX_TOKENS" = 16000 ] || fail "max_tokens = $MAX_TOKENS, want 16000"
  "$REAL_JQ" -e '.model != "" and (.system | contains("You are a careful reviewer for the COMMUNITY layer"))' "$REQ" > /dev/null \
    || fail "the request's model or system prompt is wrong"
  "$REAL_JQ" -e '(.messages | length) == 1 and .messages[0].role == "user"' "$REQ" > /dev/null \
    || fail "the request does not carry the one user message"
  # The whole entry, byte for byte (the script's $(cat chunk) drops its final
  # newline), not a line of it: a message cut short still holds any one line.
  "$REAL_JQ" -e --rawfile big "$BIG" '.messages[0].content | contains($big | rtrimstr("\n"))' "$REQ" > /dev/null \
    || fail "the message does not carry the whole $(wc -c < "$BIG")-byte entry"
fi

# audiosilo-meta-sync's steward reads a flag that lists no findings by its prose
# lines, dropping the lead as the one that ends in a colon (watcher.FindingOf). A
# lead ending otherwise would be the same "finding" on every such flag.
printf '%s' '{"result":"{\"verdict\":\"flag\",\"findings\":[\"a-work characters: a finding\"]}"}' > "$WORK/flag.json"
run flag "$CONTEXT" CLAUDE_CODE_OAUTH_TOKEN=test REPLY_FILE="$WORK/flag.json"
grep -qF -- '- a-work characters: a finding' "$WORK/flag/comment.md" || fail "the flag's finding is missing: $(cat "$WORK/flag/comment.md")"
# The comment says what the verdict DOES (core's TestAIVerifyCommentSaysWhatTheVerdictDoes,
# its bot-origin case): the steward merges a community data-only pull request on a
# pass and never on a flag, so neither comment may call the verdict advisory.
grep -qF 'does not merge a pull request while it is flagged' "$WORK/flag/comment.md" \
  && ! grep -qF 'not a merge block' "$WORK/flag/comment.md" \
  || fail "the flag comment does not say the steward holds the merge: $(cat "$WORK/flag/comment.md")"
grep -qF 'merges a data-only pull request on this verdict' "$WORK/oauth/comment.md" \
  && ! grep -qF 'a maintainer still reviews before merge' "$WORK/oauth/comment.md" \
  || fail "the pass comment does not say the steward merges on it: $(cat "$WORK/oauth/comment.md")"
# A fork's pull request (judged on a maintainer's dispatch) carries this comment
# too, and the steward only lists that one, so the pass note leaves it to a
# maintainer rather than promise a merge that never comes.
grep -qF "a pull request from a fork is a maintainer's to merge" "$WORK/oauth/comment.md" \
  || fail "the pass comment does not leave a fork's pull request to a maintainer: $(cat "$WORK/oauth/comment.md")"
while IFS= read -r line; do
  line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  case "$line" in "" | "#"* | "- "*) continue ;; esac
  case "$line" in *:) ;; *) fail "the flag comment's lead does not end in a colon: $line" ;; esac
done < "$WORK/flag/comment.md"

# Temp files: the chunks, the API request and the CLI's stderr live in one
# directory the script removes on every exit, a skip's included (core's
# TestAIVerifyLeavesNoTempFiles). Each case has its own TMPDIR, which the script's
# mktemp template puts every temp path under on every platform, and its transport
# stub lists TMPDIR while it runs, so a script that stopped making its directory
# there cannot pass on an empty TMPDIR. The rows also pin the skip reasons of
# their own, on both transports: a timeout (curl's exit 28, timeout's 124 around
# the CLI) apart from other transport errors, and a refusal, whose partial text is
# never read as a verdict even when it holds a pass.
# no_leak <name> <stub curl|claude|timeout> <stub body, or "" for the default stub>
#   <want exit 0|1> <want in comment> [VAR=value ...]
no_leak() {
  local name="$1" tool="$2" body="$3" want_exit="$4" want="$5" out="$WORK/leak-$1" status=0
  shift 5
  mkdir -p "$out/bin" "$out/tmp"
  [ -n "$body" ] || body="$(cat "$BIN/$tool")"
  {
    printf '%s\n' "${body%%$'\n'*}"
    printf '%s\n' 'ls -A "$TMPDIR" > "$DURING"'
    printf '%s\n' "${body#*$'\n'}"
  } > "$out/bin/$tool"
  chmod +x "$out/bin/$tool"
  invoke "leak-$name" "$CONTEXT" PATH="$out/bin:$BIN:$PATH" TMPDIR="$out/tmp" DURING="$out/during.txt" "$@" || status=1
  [ "$status" = "$want_exit" ] || fail "$name: exit $status, want $want_exit: $(cat "$out/log.txt")"
  # A run that wrote no comment died before skip() could, and its log says why.
  if [ ! -e "$out/comment.md" ]; then
    fail "$name: no comment was written: $(cat "$out/log.txt")"
  else
    grep -qF -- "$want" "$out/comment.md" || fail "$name: comment lacks '$want': $(cat "$out/comment.md")"
  fi
  # The one directory and nothing beside it (a case pattern's * matches a line
  # break, so a second entry is refused first).
  case "$(cat "$out/during.txt" 2>/dev/null)" in
  *$'\n'*) fail "$name: TMPDIR held more than the script's directory while the transport ran: $(cat "$out/during.txt")" ;;
  ai-verify.*) ;;
  *) fail "$name: TMPDIR held '$(cat "$out/during.txt" 2>/dev/null)' while the transport ran, want the script's ai-verify.* directory" ;;
  esac
  [ -z "$(ls -A "$out/tmp")" ] || fail "$name: TMPDIR still holds $(ls -A "$out/tmp")"
}
CURL_FAILS='#!/usr/bin/env bash
cat > /dev/null
exit 7
'
CURL_TIMES_OUT='#!/usr/bin/env bash
cat > /dev/null
exit 28
'
CURL_REFUSES='#!/usr/bin/env bash
cat > /dev/null
printf "%s" '"'"'{"stop_reason":"refusal","stop_details":{"type":"refusal","category":"cyber"},"content":[{"type":"text","text":"{\"verdict\":\"pass\",\"findings\":[]}"}]}'"'"'
'
no_leak curl-fails curl "$CURL_FAILS" 1 'transport error, curl exit 7' ANTHROPIC_API_KEY=key
no_leak curl-times-out curl "$CURL_TIMES_OUT" 1 'timed out (no answer within 300 seconds)' ANTHROPIC_API_KEY=key
no_leak refusal curl "$CURL_REFUSES" 1 '(stop_reason refusal, category cyber)' ANTHROPIC_API_KEY=key
no_leak api-pass curl "" 0 'AI verification: passed' ANTHROPIC_API_KEY=key
no_leak cli-pass claude "" 0 'AI verification: passed' CLAUDE_CODE_OAUTH_TOKEN=test
CLI_TIMES_OUT='#!/usr/bin/env bash
cat > /dev/null
exit 124
'
no_leak cli-times-out timeout "$CLI_TIMES_OUT" 1 'The Claude Code CLI timed out (no answer within 900 seconds).' CLAUDE_CODE_OAUTH_TOKEN=test

# A runner with no `timeout` skips rather than run the CLI with no time limit. The
# PATH is the claude and jq stubs and links to the other commands the script runs
# and nothing else: a recent macOS ships a timeout in /usr/bin beside them, so no
# PATH of whole directories can leave it out.
NOTIMEOUT_BIN="$WORK/bin-notimeout"
mkdir -p "$NOTIMEOUT_BIN"
cp "$BIN/claude" "$BIN/jq" "$NOTIMEOUT_BIN/"
for tool in bash awk cat find head mkdir mktemp perl rm tr wc; do
  ln -s "$(command -v "$tool")" "$NOTIMEOUT_BIN/$tool" || fail "no timeout installed: $tool is not on PATH"
done
if invoke notimeout "$CONTEXT" CLAUDE_CODE_OAUTH_TOKEN=test PATH="$NOTIMEOUT_BIN"; then
  fail "no timeout installed: ai-verify.sh exited zero: $(cat "$WORK/notimeout/log.txt")"
fi
[ ! -e "$WORK/notimeout/stdin.txt" ] || fail "no timeout installed: the CLI ran with no time limit"
grep -qF 'cannot be given a time limit' "$WORK/notimeout/comment.md" 2>/dev/null \
  || fail "no timeout installed: comment $(cat "$WORK/notimeout/comment.md" 2>/dev/null)"

if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
echo "ai-verify-test: ok"
