# AudioSilo Meta - community layer

The **CC BY-SA 4.0 community layer** of the AudioSilo audiobook metadata
database behind [meta.audiosilo.app](https://meta.audiosilo.app): the
spoiler-tagged **characters** and position-keyed **recaps** written by people who
have read or heard the book.

The repository IS the data. There is one family here,
`data/works-community/`, in the range-packed pack layout the whole project uses,
and nothing else - no tooling, no schemas, no build. Those live in the core
repository.

```
data/works-community/<dir-bound>/<bound>.json
```

Each pack file is `{"entries": {"<work-slug>": {...}}}`, and each entry holds up
to two members:

- **characters** - the cast, each entry gated by a `reveal` position, described
  in own words for a reader who has just reached that chapter.
- **recaps** - "story so far" summaries keyed by a `through` position, plus the
  optional whole-book `in_short` and `ending` summaries for a reader who has
  finished.

Read **[AUTHORING.md](AUTHORING.md)** before writing either. To produce them from
a book you own rather than from memory, follow **[EXTRACTION.md](EXTRACTION.md)**
(from an EPUB) or **[EXTRACTION-AUDIO.md](EXTRACTION-AUDIO.md)** (from the
audiobook, via local ASR). Source material never enters this repository - only
the derived sidecars.

## Its relationship to KodeStar/audiosilo-meta

[KodeStar/audiosilo-meta](https://github.com/KodeStar/audiosilo-meta) is the
**core** repository: the CC0 factual database (works, recordings, people,
series), every JSON Schema, and all the Go tooling - `metacheck`, `metafmt`,
`metabuild`, `metaserve` and the rest. This repository is the community half of
the same database, split out because it is the growth surface and because its
review bar (prose, spoiler policy, own-words policy) is not the core's
(verifiable facts, mechanical checks).

Three things follow from that:

1. **An entry key IS a core work slug.** `data/works-community/…/x.json` has an
   entry named `a-deadly-education` exactly when core holds the work
   `a-deadly-education`. The book must exist in core first; add it there if it
   does not.
2. **One implementation of everything.** This repository forks no pack math, no
   canonical JSON, no validation - it runs core's tools against its own tree
   with `--profile community`, which is the tooling's own name for "this root
   deliberately holds only the community family".
3. **One artifact, one release stream.** Data releases are still cut from core;
   the build composes this tree with core's and publishes a single
   `meta.sqlite`, which is what `meta.audiosilo.app`, the AudioSilo player and
   the Audiobookshelf provider facade all read. A merge here reaches readers
   through that release, not through this repository directly.

## Contributing

Two routes, both fine:

- **An issue form.** Open
  [Add characters](https://github.com/KodeStar/audiosilo-meta-community/issues/new?template=add-characters.yml)
  or
  [Add recaps](https://github.com/KodeStar/audiosilo-meta-community/issues/new?template=add-recaps.yml)
  and attach the file the guided builder at
  [meta.audiosilo.app/build](https://meta.audiosilo.app/build) produces. The
  **intake bot** composes the pull request for you
  (`.github/workflows/intake.yml`): it checks the work slug against the newest
  published catalogue, places the entry in the right pack file, validates the
  result and opens a pull request for review. A work the catalogue does not hold
  is refused with the slug named rather than composed; a slug a core merge has
  RETIRED is composed under the surviving one, noted on the pull request.
- **A pull request** against `data/works-community/` directly. Put the entry in
  the pack whose range covers the work slug - or the nearest one - and let
  `metafmt --write` place it correctly (see below). Approximately right is
  enough; placement self-heals.

Whichever route, [AUTHORING.md](AUTHORING.md) is the standard the entry is
reviewed against: own words, neutral reference-guide voice, the length caps, and
the spoiler model. A member you write must carry `"license":
"CC-BY-SA-4.0"` - the schema enforces it, because a CC0 record can never carry
the share-alike licence and a sidecar can never carry CC0.

## Validating locally

Clone core beside this repository and run its tools against this tree:

```sh
git clone https://github.com/KodeStar/audiosilo-meta.git
cd audiosilo-meta

# canonical formatting + pack placement (--check to report, --write to fix)
go run ./cmd/metafmt --write -data ../audiosilo-meta-community/data --profile community

# schema, entry key/id agreement, caps, bounds, member rules
go run ./cmd/metacheck      -data ../audiosilo-meta-community/data --profile community
```

Both must be clean before a pull request. `metacheck` prints `ok: 0 works, 0
people, 0 series` on a healthy community tree - the core families are not in
this root, which is the point.

The one rule those two cannot check is the cross-repo one: that every entry key
names a live work. `scripts/key-check.sh` checks it against a built artifact:

```sh
gh release download <newest data-v… tag> --repo KodeStar/audiosilo-meta \
  --pattern meta.sqlite.gz && gunzip meta.sqlite.gz
scripts/key-check.sh meta.sqlite data
```

CI runs both halves on every pull request (`.github/workflows/check.yml`): the
structure job against a pinned core commit, the keys job against the newest data
release. A key core has RETIRED (merged away) fails with the new slug to re-key
to - a mechanical fix that must not land as-is.

Pack files are maps, not text, so two pull requests touching one file need a
three-way merge of the entries rather than git's line merge:
`scripts/pack-union-merge.sh` is that merge, and `.gitattributes` names it as
the merge driver for `data/**/*.json`. Configure it in your checkout with

```sh
git config merge.packjson.name "three-way merge of pack-file entries"
git config merge.packjson.driver "scripts/pack-union-merge.sh %O %A %B %P"
```

The layout rules themselves - bounds, caps, splits, placement - are specified in
[PACK-SPEC.md](https://github.com/KodeStar/audiosilo-meta/blob/main/PACK-SPEC.md)
in core.

## Licence

**The data in this repository is licensed
[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)** (the full
legalcode is in [LICENSE](LICENSE)). So is everything else here: the guides
(AUTHORING.md, EXTRACTION.md, EXTRACTION-AUDIO.md), the issue forms and the two
scripts under `scripts/` - one licence for one repository, no per-file
exceptions. `scripts/pack-union-merge.sh` is a copy of core's, which is
AGPL-3.0 there; it is included here under that licence, and core remains its
source of truth.

Attribution for reuse: **AudioSilo Meta community contributors**, linking to
this repository or to https://meta.audiosilo.app. Share-alike means a derivative
of this content carries CC BY-SA 4.0 too.

The CC0 factual core - titles, authors, narrators, identifiers, series - is a
different licence in a different repository. The boundary is structural, not a
convention: it is the repository you are in, the family the file sits in, and an
enum in the schema. See
[LICENSING.md](https://github.com/KodeStar/audiosilo-meta/blob/main/LICENSING.md)
for the full policy.
