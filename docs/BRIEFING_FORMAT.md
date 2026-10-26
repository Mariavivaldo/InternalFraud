# Daily briefing file format

Each day's briefing is **one file**. Adding it to `_posts/` and pushing to `main` is all it
takes: GitHub Actions checks the file, rebuilds the site, and publishes it. There is no
approval step.

A complete, working example is in [`samples/2026-10-25-briefing.md`](../samples/2026-10-25-briefing.md).

## File name and date

```
_posts/YYYY-MM-DD-briefing.md        e.g. _posts/2026-10-26-briefing.md
```

* One file per day. The date is the edition date in **US Eastern time**.
* The `date:` field inside the file, if present, must match the file name.
* Everything lives in the front matter (between the two `---` lines). Leave the area below
  the second `---` empty.

## Structure

```yaml
---
date: 2026-10-26
regions:
  - id: us                       # short permanent id: lowercase letters, digits, hyphens
    name: United States          # shown on the board and in the brief
    summary: One or two sentences for the region's card on the daily board.
    overview: >-
      The region's "Overall summary" paragraph at the top of its brief.
      Markdown is allowed here (bold, italics, links).
incidents:
  - id: deepfake-voice-wire-desks   # optional; made from the title if left out
    region: us                      # must be one of the region ids above
    category: Scams & social eng.   # short label; see suggestions below
    title: Deepfake voice scam targets regional bank wire desks
    summary: One line for the daily board.
    detail: >-
      The full summary shown in the regional brief. Markdown is allowed.
    keywords: [deepfake, wire fraud, social engineering]
    story: exec-voice-impersonation   # optional; see "Story labels"
    sources:                          # listed in rank order, best first
      - name: Federal Banking Advisory
        url: https://example.com/advisory
        note: Why this source ranks where it does.
        primary: true                 # optional; marks the original/official source
---
```

### Required fields

| Where | Field | Notes |
|---|---|---|
| each region | `id`, `name`, `summary`, `overview` | `id` must never change once used. `board` is reserved. |
| each incident | `region`, `category`, `title`, `summary`, `detail`, `keywords`, `sources` | At least one keyword and one source. |
| each source | `name`, `url` | `url` must start with `https://` (or `http://`). `note` is strongly recommended. |

`incidents: []` is valid for a day with nothing to report.

### Order matters

* **Within a region, the first incident listed is the lead story** of that region's brief. The
  rest appear under "Also today in …".
* **Sources are ranked in the order listed.** Put the best reporting first.
* The order of `regions` in the file does not matter. The board keeps a stable column order
  (the order in which regions first appeared), so columns don't jump around day to day.

## Keywords

Keywords drive the Keyword dropdown, the chips on each item, and the keyword pages
(`/keyword/<name>/`), which list every item with that keyword from every day, newest first.
The day's Jekyll `tags` are filled in automatically from them.

* Give each incident **2 to 5 keywords**: usually the fraud type(s), plus any institution,
  product or regulator that a reader would want to follow over time.
* **Reuse existing keywords.** The live site publishes every keyword in use at
  `/vocabulary.json` (`keywords` list). You can also read the files in `_posts/`. Matching ignores
  capitalization and punctuation ("Deepfake", "deepfake" and "deep-fake" are the same
  keyword), but different words are different keywords: "deepfake" and "deepfakes" would split.
* Use lowercase for ordinary terms (`wire fraud`, `e-wallets`) and normal capitalization for
  names and acronyms (`Bank of America`, `BEC`, `FinCEN`).
* Prefer one consistent form: singular or plural as already used, full names over nicknames
  (`Bank of America`, not `BofA`).

## Story labels

`story` is optional and separate from keywords. It never appears in the Keyword dropdown.
Give the same label to every item that is part of one developing story, across days and regions.
The site then adds, automatically:

* a **FOLLOW-UP** tag and a "Follows our coverage: …" box linking to earlier items,
* a "Developments since: …" box on the earlier items, linking forward,
* a "Related in another region: …" link when another region covers the same story that day.

Reuse a label from `/vocabulary.json` (`stories` list, with each story's latest title) when an
item continues a story. Make a new one (lowercase words joined by hyphens, like
`synthetic-id-ring`) only for a genuinely new story.

## Regions

* Add a new region by adding it to that day's `regions` list. It gets the next color
  automatically and from then on shows "Nothing reported today" on days it has no items.
* Include a region in the file on any day it has incidents. A region with no incidents can be
  left out; the board shows it as empty.
* Optional overrides (display name, column order, colors, hiding a retired region) go in
  `_data/regions.yml`. This is rarely needed.

## Category suggestions

Free text, but reusing the same labels keeps the per-region breakdown readable:
`Scams & social eng.`, `Payments & cards`, `Enforcement`, `Regulatory`, `Industry controls`,
`Cyber & breaches`, `Insider & employee fraud`, `Money laundering`.

## YAML pitfalls

* **Put quotes around any text that contains `: ` (a colon followed by a space)**, or that starts
  with a quote, `[`, `{`, `*`, `&`, `!`, `|`, `>`, `%`, `@` or a backtick. For example:
  `summary: "Impersonation leads: a deepfake voice campaign"`.
* For longer text, use `>-` on the field line and indent the text underneath (as in `detail`
  above). No quotes are needed inside a `>-` block.
* Indent with spaces, never tabs.

## Check before committing

```
ruby scripts/validate.rb _posts/2026-10-26-briefing.md
```

It prints `✓` when the file is good, or names each problem (for example
`incidents[2] ("Brokerage breach…").sources[0].url: must be a full web address`). The same check
runs on GitHub before every build. If it fails there, nothing is published and the previous
day's site stays up.
