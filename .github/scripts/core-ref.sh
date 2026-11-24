#!/usr/bin/env bash
# core-ref.sh - print CORE_REF=<sha> from .github/core-ref, for $GITHUB_ENV.
#
# Usage (a workflow step, after the checkout of this repository, with GH_TOKEN
# set so gh can ask the GitHub API; .github/actions/core-tooling runs it so for
# every job but intake.yml's rebase, which writes the step out):
#   bash .github/scripts/core-ref.sh >> "$GITHUB_ENV"
#
# .github/core-ref is the ONE pin of the core commit whose tooling check.yml
# validates with and intake.yml composes with (check.yml's env comment says why
# it is a sha and a sparse checkout). Both workflows read it through this, so
# the two can no longer name different commits. The file holds one full
# 40-character sha; anything else fails the step rather than checking out
# whatever a malformed ref would resolve to.
#
# The sha must also be on core's main: the commit itself or one of its
# ancestors. Shape alone is not enough, because GitHub serves a fork's commits
# through the parent repository (a fork shares its object store), so
# actions/checkout of KodeStar/audiosilo-meta at a sha that exists ONLY in some
# fork succeeds and builds that fork's tooling. The compare API answers
# "identical" or "behind" exactly when the sha is reachable from main; a fork's
# or another branch's commit is "ahead" or "diverged", or not found at all, and
# every answer but those two fails the step. So does an API call that fails:
# an unverified pin is not used.
#
# CORE_REPO names the core repository (the workflows set it); the default is
# the real one.

set -euo pipefail

core_repo="${CORE_REPO:-KodeStar/audiosilo-meta}"

ref="$(tr -d '[:space:]' < "$(dirname "${BASH_SOURCE[0]}")/../core-ref")"
if ! printf '%s' "$ref" | grep -Eq '^[0-9a-f]{40}$'; then
  echo ".github/core-ref must hold one full 40-character commit sha, not '$ref'" >&2
  exit 1
fi

if ! status="$(gh api "repos/${core_repo}/compare/main...${ref}?per_page=1" --jq '.status')"; then
  echo ".github/core-ref names ${ref}, which ${core_repo} could not compare with its main (a fork's commit, or the API failed)" >&2
  exit 1
fi
case "$status" in
  identical|behind) ;;
  *)
    echo ".github/core-ref names ${ref}, which is not on ${core_repo}'s main (compare says '${status}'); pin a commit of main" >&2
    exit 1
    ;;
esac

echo "CORE_REF=$ref"
