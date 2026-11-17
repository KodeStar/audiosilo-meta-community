#!/usr/bin/env bash
# core-ref.sh - print CORE_REF=<sha> from .github/core-ref, for $GITHUB_ENV.
#
# Usage (a workflow step, after the checkout of this repository):
#   bash .github/scripts/core-ref.sh >> "$GITHUB_ENV"
#
# .github/core-ref is the ONE pin of the core commit whose tooling check.yml
# validates with and intake.yml composes with (check.yml's env comment says why
# it is a sha and a sparse checkout). Both workflows read it through this, so
# the two can no longer name different commits. The file holds one full
# 40-character sha; anything else fails the step rather than checking out
# whatever a malformed ref would resolve to.

set -euo pipefail

ref="$(tr -d '[:space:]' < "$(dirname "${BASH_SOURCE[0]}")/../core-ref")"
if ! printf '%s' "$ref" | grep -Eq '^[0-9a-f]{40}$'; then
  echo ".github/core-ref must hold one full 40-character commit sha, not '$ref'" >&2
  exit 1
fi
echo "CORE_REF=$ref"
