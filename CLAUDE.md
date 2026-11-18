# CLAUDE.md - AudioSilo Meta community layer

Guidance for working in this repository. Keep it updated as things change. This
is the community half of the AudioSilo metadata database; the core repository,
`KodeStar/audiosilo-meta`, is authoritative for everything not stated here and
its CLAUDE.md is worth reading before any non-trivial change.

## What this is

**Data only.** One pack family, `data/works-community/`, holding the CC BY-SA
4.0 characters, recaps and description sidecars, keyed by work slug, plus the
optional `position_scale` member stating the ruler those positions are on
(AUTHORING.md). The third
member, `description`, is the spoiler-free intro paragraph. No Go module, no
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

## App-filed issues (route.yml)

An AudioSilo Bridge files characters/recaps issues through the AudioSilo GitHub
App, and they arrive label-less. `route.yml` is a thin caller of core's
`route-reusable.yml` (the one copy of the routing, shared with core's own
route.yml), called at a pinned full commit sha with `[characters] ` and
`[recaps] ` as the title-prefix allowlist (`routes`) and a cap of 50 open
App-filed issues per account; it labels the issue with this repository's
GITHUB_TOKEN, which starts no workflow, and route.yml then calls OUR
`intake.yml` through its `workflow_call` entry in the same run. A re-run of a
decided issue is a no-op (the guard is described once, in core's
route-reusable.yml header). The App id is a routing hint, not trust;
holds (`intake:held`) and the denylist (`.github/intake-denylist`) are described
in core's GOVERNANCE.md. When core changes route-reusable.yml, bump the sha in
route.yml in its own pull request, as with `.github/core-ref` (dependabot
ignores it).

## The tooling checkout (both workflows)

Neither workflow can `go run github.com/kodestar/audiosilo-meta/...`: the core
module carries the ~1.5GB core data tree and proxy.golang.org times out on every
post-seed version, so a direct fetch clones the whole repository (~40 minutes,
measured). Both workflows instead do a **blobless sparse checkout of core's
tooling directories at a pinned sha** and run from it. The sha is ONE file,
`.github/core-ref`, which both read into `CORE_REF` through
`.github/scripts/core-ref.sh`, so the bot always composes with the rules the
checks validate against; bump it in its own pull request, to a commit of core's
main. core-ref.sh refuses any other sha through the compare API, because GitHub
serves a fork's commits through the parent repository and a checkout would build
them (`.github/scripts/core-ref-test.sh` covers it, in check.yml). Each core
checkout's `ref` falls back to a name that does not exist, so a job that never
read the pin fails rather than floating on core's main. The full rationale is in
check.yml's env comment.

## The AI review (ai-verify.yml) and the steward

`ai-verify.yml` reviews a data pull request's PROSE against AUTHORING.md and
posts `### AI verification: passed|flagged` plus the `ai-verified` /
`ai-flagged` label. `.github/scripts/ai-verify.sh` is core's script of the same
name with a community prompt: the transport, the untrusted-data handling, the
verdict parse and the comment render are copied and must stay in step with
core's. The transport prefers the `ANTHROPIC_API_KEY` secret (billed per pull
request) and falls back to the Claude Code CLI on `CLAUDE_CODE_OAUTH_TOKEN`, the
subscription meta-sync's resolver shares (meta-sync#63).
The comment's pass note and flag lead are core's bot-origin ones for every pull
request: the steward merges a data-only pull request on a pass and never while
flagged, so neither calls the verdict advisory (the pass note adds that a fork's
pull request, which the steward only lists, is a maintainer's to merge), and the
flag lead stays ONE line
ending in a colon (the steward's `watcher.FindingOf` drops it as the line that
does). `bash .github/scripts/ai-verify-test.sh` tests that transport, the note
and the lead with stub `claude` and `curl` (core's `scripts/aiverify_test.go`
cases; this repository has no Go module), and check.yml's `structure` job
runs it. With the key set, ai-verify.yml skips the CLI install.
`.github/scripts/ai-verify-context.sh` renders the changed ENTRIES
(keyed by work slug across the touched packs, so a pack split is invisible),
never a raw diff.

Three names are a CONTRACT with audiosilo-meta-sync's steward, which merges a
community data pull request only when `keys`, `structure` and `verify` concluded
well on its exact head and `ai-verified` is on it: the job key `verify`, the
comment heading, and the two labels. The prompt tells the model it has not read
the book and may never have heard of it: "I cannot verify this" is never a
finding (core learned that on a real preorder it called fabricated four times).

**It judges the pull request's change, not the whole entry.** The context
names, for every CHANGED entry, the members the pull request changes
(`--- this pull request changes: recaps (added), ...`); every other member is
shown as context only. The prompt puts a problem wholly inside an unchanged
member in the verdict's `existing` list, never in `findings`, and the script
makes that stick: a flag whose every concern is under `existing` (no finding,
at least one note) counts as a pass, so a concern listed there cannot flag the
pull request - while a flag with neither still flags, since a label must never
assert a pass the model did not give; the
comment quotes those notes (as `>` lines, never list items) under `#### Already
on main`, so a maintainer can fix them on main. Before this, #60 - a recaps pull
request - was flagged for a characters card #59 had already merged, which no fix
on that pull request could touch. Every finding and note begins `<work-slug>
<member>: ...`: the steward reads that shape to recognise a flag about data
outside the pull request (audiosilo-meta-sync `scope.go`). This render and
aggregation are the community's own; core's script has no `existing` list.

**A rebase that leaves the judged context unchanged reuses the verdict**
(`.github/scripts/ai-verify-reuse.sh`, core's byte for byte; the `reuse` step).
The key is the SHA-256 of context.txt and the scripts and workflow that judge it;
a fresh verdict appends `<!-- ai-verify-key: <sha> verdict: pass|flag -->` as
its comment's LAST line, and a later run with the same key re-applies that label
with no model call and no new comment. Only github-actions[bot]'s newest verdict
comment counts and only its last line is read; a skip is never reused; a
workflow_dispatch, a re-run (`run_attempt > 1`) or the opt-in label always
judges afresh. Every merge makes the intake sweep rebase every open intake pull
request, and each rebase re-ran the model on content it had already judged: N
ready pull requests cost about N*(N+1)/2 model runs (14, about 100, on
2026-09-30), and a verdict on unchanged content could flip between rebases.

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
  says so in its `sources[]`; it never invents specifics to fill a gap. A
  `description` is the exception that goes further: recollection is **not**
  accepted for it at all (maintainer decision, 2026-08-21), because it asserts
  what a book is about with no spoiler gate and no reader position to bound it.
  Skip the work over inventing its premise.
- **CI security is deliberate**: plain `pull_request`, never
  `pull_request_target`, and a read-only token with no secrets. Core carries the
  same rule for the same reason. The one exception is `ai-verify.yml`, which
  needs a model secret and `pull-requests: write` to post its verdict - and
  therefore runs only on same-repo branches (and a maintainer's dispatch), never
  on a fork, with the contributor text handed to a tool-less model as data.
- **The merge driver is not optional for pack conflicts.** git's line merge can
  write one entry key twice, which is not valid pack storage. Configure
  `scripts/pack-union-merge.sh` (see README.md) before resolving one by hand.
- **The intake sweep runs nothing from a swept branch.** intake.yml's `rebase`
  job holds a persisted write token while it checks intake branches out, so it
  builds metafmt and metacheck from the pinned core and copies main's
  `scripts/pack-union-merge.sh` into the runner temp before touching any branch,
  and names the driver by that absolute path. It skips a fork's branch (a log
  line) and refuses, with one comment, a branch whose whole change or any one
  commit changes anything but a regular file plainly named `data/**/*.json` (a
  symbolic link, a submodule or an executable included). It fetches main and
  the branch into two refs of its own (`refs/intake-sweep/main`,
  `refs/intake-sweep/head`) and works by their commit ids, since a tag or
  branch called `origin/main`, or a branch called `HEAD`, would otherwise
  become the rebase base. Two things a branch still
  reaches are held as well. metafmt runs only on a tree whose every entry key is
  a slug: it names a split pack after an entry key, so a key like `a/../../x`
  was a file written outside `data/` (the root fix is core's, in pkg/pack). And
  what git and the tools print goes to the log with workflow commands stopped,
  since a commit subject or a quoted value could otherwise issue one. Every
  rebase, clean or not, is followed by metafmt and metacheck before the push,
  and a failure parks the branch with the give-up comment below: a clean replay
  with no driver merge once kept a stale split pack, a copy of main's entries in
  a second pack, and pushed it for three days (#517). metafmt is not run on a
  tree that holds one entry in two packs with different content (`one_copy`):
  it settles an entry held twice by keeping the copy in the pack whose range
  covers it and discarding the other, and a stale pack makes the kept copy the
  branch's, so over #517's tree it deleted recaps main had merged since and left
  a tree metacheck passes. Identical copies are metafmt's to settle. The test's
  stub metafmt changes nothing, so it covers these guards and not what the real
  metafmt does to a tree. The step
  runs under `bash -e` (GitHub's default for a `run:` with no `shell:`), so a
  status it reads goes through `||`; `.github/scripts/intake-sweep-test.sh` runs
  the step that way against a local origin (check.yml runs it; it needs bash
  4.4, so not macOS's). The give-up comment opens with its marker alone on the
  first line (`<!-- intake-sweep:rebase-failed <head> <reason> -->`), then
  "The intake bot could not rebase this branch onto ...": a CONTRACT with
  audiosilo-meta-sync's steward (`watcher.IsSweepFailure`,
  `watcher.SweepFailureHead`). Core's intake.yml carries the same sweep, with
  the same rules, guards and comment shape; keep the two in step.
