# CLAUDE.md - AudioSilo Meta community layer

Guidance for working in this repository. Keep it updated as things change. This
is the community half of the AudioSilo metadata database; the core repository,
`KodeStar/audiosilo-meta`, is authoritative for everything not stated here and
its CLAUDE.md is worth reading before any non-trivial change.

## What this is

**Data only.** One pack family, `data/works-community/`, holding the CC BY-SA
4.0 characters and recaps sidecars, keyed by work slug. No Go module, no
schemas, no build - the tooling all lives in core and is run against this tree.
The three authoring guides (AUTHORING.md, EXTRACTION.md, EXTRACTION-AUDIO.md)
live here because they document the process that produces this content.

Data releases are cut from CORE, composing this tree with core's into one
`meta.sqlite`. Nothing here is published on its own.

## The one command

```sh
# from a core checkout beside this one:
cd ../audiosilo-meta
go run ./cmd/metafmt  --check -data ../audiosilo-meta-community/data --profile community
go run ./cmd/metacheck       -data ../audiosilo-meta-community/data --profile community
```

`--write` instead of `--check` fixes formatting and placement. `--profile
community` is load-bearing: it tells the tooling this root deliberately holds
one family, so a stray file belonging to another family is an unrecognized
location rather than being silently walked past, and the cross-family rules
whose other side is not in this tree stand down instead of failing.

A healthy tree prints `ok: 0 works, 0 people, 0 series` - the core families are
not in this root by design.

The pack layout itself (bounds, caps, splits, self-healing placement) is
specified in core:
[PACK-SPEC.md](https://github.com/KodeStar/audiosilo-meta/blob/main/PACK-SPEC.md).
Never compute placement by hand; `metafmt --write` does it.

## Entry keys are CORE work slugs

This is the rule the split creates and the only one this repository cannot
answer by itself. An entry key is the slug of a work in core's `data/works/`.
Three consequences:

- The work must exist in core BEFORE its sidecar lands here.
- A core repair wave that MERGES duplicate works retires slugs (tombstoned in
  core's `data/redirects.json`). An entry keyed by a retired slug still resolves
  for a reader - metaserve answers 301 - but it must be re-keyed. That is a
  mechanical fix: rename the entry to the surviving slug and re-run `metafmt
  --write`.
- `metacheck --profile community` deliberately does NOT fail on a key it cannot
  resolve: the works family is not in this tree, so the parent-work arm of its
  integrity rule stands down. The check happens in two other places instead.

**The cross-repo integrity story, in the order it runs:**

1. **This repository's CI, on every pull request** (`.github/workflows/check.yml`,
   the `keys` job): `scripts/key-check.sh` reads every entry key out of the pack
   files and resolves it against the NEWEST data release's `meta.sqlite` - live
   work, retired (fail, naming the slug to re-key to), or unknown (fail, naming
   the entry). Cheap and slightly stale: a work added to core since the last
   release reports as unknown, which is the intended failure.
2. **Core's release build, authoritatively**: it checks out both repositories
   and runs the full cross-tree check before building the artifact. A dangling
   key there is a red release, never a silently dropped sidecar.

And one layer EARLIER, so a bad key never becomes a pull request in the first
place: the **intake bot** (`.github/workflows/intake.yml`) asks the same artifact
the same question BEFORE it composes anything (`metaissue --profile community
--works-db meta.sqlite`). Three outcomes, and they are deliberately the key
check's own with one divergence: a live slug composes, an unknown slug is refused
with the slug named, and a RETIRED slug composes under the SURVIVOR with a note
on the pull request. The divergence is the retired case, and only in direction -
key-check.sh fails a retired key because it is already written down and the fix
is to re-key it, while the bot is choosing the key and simply chooses the live
one. A bot that wrote the tombstoned key would open a pull request its own CI
rejects.

## The tooling checkout (both workflows)

Neither workflow can `go run github.com/kodestar/audiosilo-meta/...`: the core
module carries the ~1.5GB core data tree and proxy.golang.org times out on every
post-seed version, so a direct fetch clones the whole repository (~40 minutes,
measured). Both workflows instead do a **blobless sparse checkout of core's
tooling directories at a pinned sha** and run from it. `check.yml` and
`intake.yml` must name the SAME `CORE_REF`, or the bot would compose with
different rules than the checks validate against - bump them in one pull request.
The full rationale is in check.yml's own comment; consolidating the two into one
pin is a recorded follow-up rather than a second mechanism.

## Conventions

- **No AI attribution anywhere.** No `Co-Authored-By` trailers, no "Generated
  with ..." lines in commits or pull request bodies. This is a hard rule.
- **Hyphens, never em dashes**, in data, docs, comments and generated text
  alike (workspace-wide).
- **Own words, never verbatim.** The whole point of the CC BY-SA layer is that
  it is written, not scraped. No jacket copy, no wiki text, no retailer blurbs -
  see AUTHORING.md's copyright section and the `metaextract ngram` check.
- **Facts only, never fabricated.** If a fact cannot be verified, omit the
  optional field rather than guess. A sidecar written from model recollection
  says so in its `sources[]`; it never invents specifics to fill a gap.
- **CI security is deliberate**: plain `pull_request`, never
  `pull_request_target`, and a read-only token with no secrets. Core carries the
  same rule for the same reason.
- **The merge driver is not optional for pack conflicts.** git's line merge can
  write one entry key twice, which is not valid pack storage. Configure
  `scripts/pack-union-merge.sh` (see README.md) before resolving one by hand.
