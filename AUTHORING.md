# Authoring characters, recaps and descriptions (the CC BY-SA layer)

This guide covers the **expressive layer** of the database: community-authored
**character** entries, **recaps** ("story so far" summaries) and the work
**description** (the spoiler-free paragraph a stranger reads before deciding to
listen). It is separate from
[CONTRIBUTING.md](https://github.com/KodeStar/audiosilo-meta/blob/main/CONTRIBUTING.md),
which covers the factual CC0 core (works, recordings, people, series) in the
core repository. Read
[LICENSING.md](https://github.com/KodeStar/audiosilo-meta/blob/main/LICENSING.md)
first - this layer is **CC BY-SA 4.0**, not CC0, and it carries real copyright
obligations the core does not.

**Where the commands run.** This repository holds the community data; the
tooling lives in the core repository, `KodeStar/audiosilo-meta`. Every
`go run ./cmd/...` line below is run from a checkout of THAT repository, with
this repository's `data/` named explicitly and the community profile selected:

```sh
cd ../audiosilo-meta      # the core checkout, beside this one
go run ./cmd/metafmt  --write -data ../audiosilo-meta-community/data --profile community
go run ./cmd/metacheck       -data ../audiosilo-meta-community/data --profile community
```

See this repository's README.md for the full local-validation flow.

If you are filling out a whole series, do the CC0 core first (the works,
recordings, people, and series must already exist and validate) and add these
sidecars on top.

To PRODUCE these sidecars from a book you own (rather than from memory), follow
the text pipeline in [EXTRACTION.md](EXTRACTION.md) or the audio-only pipeline
in [EXTRACTION-AUDIO.md](EXTRACTION-AUDIO.md). They establish chapter-accurate
positions and add a mechanical no-verbatim check. Everything in this guide
still applies to their output. For `characters` and `recaps` that grounding is
strongly preferred; for a `description` it is **required** (see the
`description` section below).

## The three sidecar members

All three are **per-work sidecars**, and they live in the same place: one entry
in the `works-community` family, keyed by the work slug, holding up to three
members.

```
data/works-community/<dir>/<bound>.json

{
  "entries": {
    "a-deadly-education": {
      "characters":  { ... },   # the cast, spoiler-tagged
      "description": { ... },   # the spoiler-free intro paragraph
      "recaps":      { ... }    # position-keyed "story so far"
    }
  }
}
```

`description` is the newest member: it validates once core's schema change
(artifact `schema_version` 6) has landed and this repository's pinned
`CORE_REF` has been bumped to it. Written against an older pin, `metacheck`
rejects it as an unknown member.

The family is separate from `data/works/` so the licence boundary is structural:
everything in `works-community` is **CC BY-SA 4.0**, everything in the core
families is CC0. Every member carries `license` (**must** be `"CC-BY-SA-4.0"`)
and `sources`, and every member carries `work` (the parent work slug, which
must equal the entry key).

Add your entry to the community pack whose range covers the work slug - or the
nearest one - and run `go run ./cmd/metafmt --write`: it places the entry
correctly and re-renders the file. The sections below describe each member's
own shape; where they say "the file", read "the member".

### characters

```json
{
  "work": "a-deadly-education",
  "license": "CC-BY-SA-4.0",
  "sources": [{ "type": "community" }],
  "characters": [
    {
      "id": "el",
      "name": "El",
      "aliases": ["Galadriel Higgins"],
      "role": "protagonist",
      "reveal": { "chapter": 1 },
      "description": "A senior at the Scholomance with an affinity for mass destruction she refuses to use, scraping through on spite and hard-won craft.",
      "xref": { "wikidata": "Q..." }
    }
  ]
}
```

- **`id`** - a slug, unique **within this file** (not globally: two different
  works may each have a `narrator` or a `the-king`). Derive it from the name.
- **`name`** - the character's primary name as a reader of *this* book would know
  it.
- **`aliases`** (optional) - other names/titles. Omit the key if there are none.
- **`role`** (optional) - one of `protagonist`, `antagonist`, `supporting`,
  `minor`. The value must be safe at the reveal position: do not label an
  apparent ally as an antagonist when that is learned later. Use the apparent
  role at reveal or omit it if genuinely unclear.
- **`reveal`** (required) - the position where the character is first
  meaningfully introduced **in this book** (see Positions below).
- **`description`** (optional but expected) - your own words, **≤ 1500
  characters** (see Copyright).
- **`xref`** (optional) - `wikidata` (a `Q...` id) and/or `goodreads`. A shared
  `wikidata` QID is how the **same character across a series** is linked: each
  book gets its own card, and the QID ties them together. Only include a QID you
  have actually verified points at this character.

### recaps

```json
{
  "work": "the-last-graduate",
  "license": "CC-BY-SA-4.0",
  "sources": [{ "type": "community" }],
  "in_short": "The whole book in one paragraph, ending included, for someone about to start the next one.",
  "ending": "How the book closes: where every major player stands, and which threads stay open.",
  "recaps": [
    {
      "through": { "chapter": 0 },
      "scope": "series",
      "text": "Previously: El survived her senior year's first term at the Scholomance and reluctantly let Orion Lake befriend her..."
    },
    {
      "through": { "chapter": 6 },
      "scope": "book",
      "text": "So far this book: ..."
    }
  ]
}
```

A recaps file has two layers: **chaptered `recaps`** (spoiler-gated "story so
far" entries, the differentiator) and two optional **whole-book summaries**
(`in_short` and `ending`) for a reader who has already finished the book and
wants a fast refresher before the sequel. Structure your entries like a
dedicated recap site, but keep the neutral reference-guide **voice** (see
Copyright) - never their jokey, editorializing tone.

- **`recaps[].through`** (required) - the recap is safe to show to a listener who
  has **finished this chapter** (see Positions).
- **`recaps[].scope`** (optional) - `book` (recaps only this book) or `series`
  (also covers earlier books). A `chapter: 0` + `scope: "series"` entry is the
  "previously, in earlier books" recap - the single most useful recap in a
  series, shown when someone starts the next book.
- **`recaps[].text`** (required) - your own words, **≤ 3000 characters**, target
  **~150-300 words** per entry. The cap is **per entry** and the entry count is
  unbounded: recap capacity scales with the book by **adding through-points**,
  never by cramming more into one entry. Scale the count with the book's length
  and density - a short middle-grade book might carry 3-4 points; a 30-60+ hour
  epic or serial volume 12-20 or more. Rule of thumb: one through-point every
  ~5-10 chapters or ~2-4 listening hours, at natural act/arc breaks. An entry
  bumping the cap is the signal to **split** its span into two through-points,
  not to compress harder. The **final** chaptered entry must carry through the
  **actual ending** - state outcomes plainly; "reveals just enough to..."
  teasing is a defect, not a style.
- No two recaps in one file may share a `through` chapter.
- **`in_short`** (optional) - the **whole arc in one paragraph, ending
  included**: the fastest possible refresher for someone about to start the next
  book. Own words, **≤ 1500 characters**, target **~120-200 words** (one
  paragraph).
- **`ending`** (optional) - **how the book ends**, the sequel-handoff state:
  where every major player stands at the close and which threads stay open.
  State it plainly - never a tease. Own words, **≤ 2000 characters**, target
  **~150-300 words**. It is deliberately capped tighter than a chaptered `text`
  entry: a crisp handoff into the next book, **not** another full recap.
- `in_short` and `ending` describe the finished book, so they are inherently
  full-spoiler; a consumer only shows them to a reader who has completed the
  book (or who opts in).

### description

```json
{
  "work": "a-deadly-education",
  "license": "CC-BY-SA-4.0",
  "sources": [{ "type": "community", "ref": "audible:us:B012345678" }],
  "text": "A senior year at the Scholomance, a school with no teachers, no holidays and no way out until graduation. El has an affinity for mass destruction and refuses to use it, which leaves her scraping through on spite, hoarded mana and hard-won craft - and being repeatedly, publicly rescued by the one classmate everybody else adores."
}
```

**What it is.** The paragraph a stranger reads before deciding to listen. It is
the intro on the work's page at meta.audiosilo.app, it is that page's meta
description (so it is the sentence a search engine quotes), and it travels
downstream through the artifact to every other consumer - the AudioSilo player's
book detail, the Audiobookshelf provider facade. One per work. No positions, no
gate, no second version for a reader further in.

That reach is what makes its contract **stricter** than its neighbours', not
looser. Each of the following is load-bearing.

- **Spoiler-free, absolutely.** Setup only: the premise, the situation, who the
  book is about and what it is asking - nothing past the opening act. No
  reveals, no turns, no deaths, no late-book roles, and never the ending. This
  is the defining difference from the other two members. A recap's whole point
  is position-gated spoilers; `in_short` deliberately includes the ending. A
  description has **no gate on the page** - whatever it says, everyone sees, and
  a search engine may quote it to someone who has not opened the book. When a
  detail is arguably a reveal, leave it out.
- **Own words.** Never a rewritten, reworded or paraphrased retailer or
  publisher blurb - that is the one thing this layer exists not to be, and the
  core's LICENSING.md posture excludes publisher copy from the database
  outright. Do not read the blurb and restate it; write the paragraph from the
  book itself. No verbatim or near-verbatim text from the book
  either: `metaextract ngram` covers a `description` exactly as it covers a
  recap, and a hit is a rewrite, not a discussion.
- **Grounded in the actual book.** A description asserts what a book *is
  about* - a factual claim in the reader's first impression of it - so it must
  come from having read or heard the book, with extraction-backed provenance in
  `sources`. **Model recollection is not accepted for descriptions**, even
  though it is accepted best-effort for characters and recaps (maintainer
  decision, 2026-08-21): recollection of a title's premise is exactly where a
  plausible invention survives review. **Skip over invent, always** - a work
  with no description is a work waiting for one; a work with a confident wrong
  one is a defect a reader cannot see.
- **200-1500 characters**, schema-enforced, so the member has a floor as well
  as a cap. Target **~80-150 words**: one paragraph, two at the outside. Under
  the floor it is a label rather than a description; at the cap it is turning
  into a plot summary, which is what `recaps` is for.
- **Neutral reference-guide voice**, as everywhere else here - and this is the
  member most tempted away from it. No "gripping", no "unputdownable", no
  star-rating-by-adjective, no second-person sales pitch. Say what the book is;
  let the reader decide.
- **`license` is `"CC-BY-SA-4.0"`** (schema-locked, as for the other members)
  and **`sources` is required**, from the same provenance vocabulary the other
  sidecars use - see Format and validation below. Because the grounding rule
  above is a rule about provenance, `sources` is where it is actually checked:
  a `ref` naming the edition read or heard.

Note the name collision, which is only a name: `characters[].description` is a
single character's card, capped at 1500 characters and written for a reader at
that character's `reveal`. The `description` **member** is the whole work's
intro paragraph and is gated by nothing.

**How a description is contributed.** There is deliberately **no issue form**
for descriptions, and there will not be one until the intake pipeline has proven
itself on the two forms that already exist. Two routes:

- **A hand-authored pull request**, editing the work's `works-community` entry
  directly to add the member. This is the repository's ordinary PR path - put
  the entry in approximately the right pack file and let `metafmt --write` fix
  placement and formatting mechanically. See README.md's "Validating locally"
  for running the pinned core tooling against this tree.
- **A maintainer-reviewed generation batch**, where a run of the extraction
  pipeline produces descriptions for many works at once and a maintainer reviews
  them as one pull request. The contract above is the review standard either
  way; the batch route changes who writes it, never what is required of it.

## Positions (the spoiler model)

Every character and recap is tagged with a **position**: `{ "chapter": N }`. A
`description` carries none: it has no spoiler gate at all, which is precisely
why it must be spoiler-free outright rather than positioned.

- `chapter` is the **logical chapter of the work** - the book's own chapter
  numbering, 1-based. It is **edition-independent**: it is NOT the recording's
  track/marker number (recordings vary - some mark Parts or Books, some number
  chapters, some are abridged). Use the chapter as printed in the book.
- `chapter: 0` means front matter or knowledge carried from **earlier books** in
  the series (a character the reader already knows; a "story so far" recap).
- A consumer (the site, the player) compares the listener's current position
  against these numbers and only reveals what is already safe. That is the whole
  point: **get the position right and the spoiler protection is automatic.**

Guidance:

- For a **character**, `reveal.chapter` is where they are first named/introduced
  in *this* book. A returning series character introduced on page one is
  `chapter: 1` (or `0` if they are purely prior-book knowledge at the start).
- Write the **description for a reader who has just reached `reveal.chapter`** -
  do not fold in a late-book twist about that character. If a character's role
  changes dramatically later, that is a *different, later* recap's job, or a
  second character card in a later book.
- For **recaps**, place a `through` at natural catch-up points (see the
  recaps section for how many and how often, and always include a
  `chapter: 0` series recap for book 2+). Each recap may freely reveal
  everything **up to and including** its `through` chapter, and nothing after.

## Copyright (this is the load-bearing part)

Publication is the risk surface, so these rules are hard requirements, not
style:

1. **Own words only. No verbatim or near-verbatim text** from the book, its
   jacket copy, or any wiki. Paraphrase from memory of the facts; do not
   reword sentences from a source. Short, factual, reference-guide phrasing.
2. **Length caps are enforced by the schema** (character description ≤ 1500,
   recap `text` ≤ 3000, `in_short` ≤ 1500, `ending` ≤ 2000, the work
   `description` 200-1500 characters) and exist
   for a legal reason - a dense, blow-by-blow plot reconstruction is the danger
   zone. The raised recap cap buys **depth per entry**, not a licence to retell
   the book scene by scene. Summarize, do not retell.
3. **Neutral reference-guide voice.** Recap blogs are chatty and opinionated
   ("X is an arse"); we are not. No jokes, no editorializing, no profanity, no
   value judgements about the book or its characters - just what happens, stated
   plainly. Take the *structure* from those sites, never the tone.
4. **Facts, not invention.** Describe only what actually happens in the book. If
   you are unsure of a detail, **omit it** - an omitted field is always better
   than a fabricated one. (This is the same rule as the CC0 core.) For the
   `description` member the rule goes one step further: it must be grounded in
   the book itself rather than in recollection of it, and a work with no
   description is always better than a confident wrong one (see the
   `description` section).
5. **Reference-guide framing**, non-commercial. This is an index to help a
   listener, not a substitute for the book.
6. Rightsholders can request removal per book; keep `sources` accurate so any
   contribution can be audited or retracted.

## Format and validation

- `license` is `"CC-BY-SA-4.0"`. A manual contribution from the author's own
  knowledge may use `sources: [{ "type": "community" }]`. An automated
  audiobook/ebook extraction **must** use one community source whose `ref`
  identifies the edition actually processed, for example
  `audible:us:B012345678`, `isbn:9780123456789`, or
  `audiosilo-meta:recording:<work>/<recording>`. The authoring tool or pipeline
  name alone is not provenance. Add `imported_at` when the extraction date is
  known.
- **A `description` may not rest on `sources: [{ "type": "community" }]`
  alone.** Its grounding rule is a rule about provenance, so it takes the
  extraction form above: a `ref` naming the edition actually read or heard.
- Run the gate before submitting:
  ```sh
  go run ./cmd/metafmt --write     # canonical formatting (sorted keys, 2-space)
  go run ./cmd/metacheck           # schema + integrity + uniqueness
  ```
  metacheck enforces: valid JSON Schema, `work` matches the directory, the
  parent work exists, character ids are unique within the file, recap
  positions are unique within the file, and every length bound including the
  `description` floor.

## Checklist

- [ ] The work, its recording(s), author, and narrator already exist and validate.
- [ ] `work` equals the entry key the `characters` and `recaps` members sit under.
- [ ] `license` is `"CC-BY-SA-4.0"`; `sources` present.
- [ ] Every character has an `id` (unique within this work's characters member), `name`, and `reveal`.
- [ ] Descriptions/texts are your own words, within the caps, and accurate
      (character ≤ 1500, recap `text` ≤ 3000, `in_short` ≤ 1500, `ending` ≤ 2000).
- [ ] The final chaptered recap states the **actual ending**, not a tease; `ending`
      and `in_short` (if present) carry the real outcome plainly.
- [ ] Voice is neutral reference-guide - no jokes, editorializing, or profanity.
- [ ] Positions use the book's own (logical) chapter numbers; `0` = prior-book.
- [ ] Book 2+ has a `chapter: 0` series recap; a series opener does not.
- [ ] `metafmt --write` and `metacheck` both pass.

And for a `description`, which has no gate to fall back on:

- [ ] **Spoiler-free** - setup only, nothing past the opening act, never the ending.
- [ ] **Own words** - not a reworded retailer or publisher blurb, and not the book's own.
- [ ] **ngram-clean** - `metaextract ngram` finds no overlap with the text.
- [ ] **Grounded in the actual book**, read or heard - not recollection of it.
- [ ] **200-1500 characters**, ~80-150 words, one paragraph.
- [ ] `sources` names the edition processed (a `ref`), and `license` is `"CC-BY-SA-4.0"`.
