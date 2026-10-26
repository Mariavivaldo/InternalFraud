# InternalFraud · Fraud Board

A daily antifraud news briefing, summarized by region, with links to the original sources.
Published with GitHub Pages at **https://mariavivaldo.github.io/InternalFraud/**.

## How it works

Every day, one file is added: `_posts/YYYY-MM-DD-briefing.md`. Pushing it to `main` starts
GitHub Actions, which checks the file, builds the site with Jekyll, and publishes it. No one
needs to approve anything.

From that single file the site builds:

* **The daily board**: one column per region, with counts for incidents, sources,
  follow-ups and regions reporting.
* **A regional brief for each region**, opened from the board. It shows the lead story,
  sources ranked by reporting quality, prior coverage, and the region's other items.
  Each brief has its own link, such as `/2026/10/25/#us`.
* **Keyword pages**: picking a keyword lists every item with that keyword from every day,
  newest first.
* **The Edition calendar**: days with a briefing are shaded by how many stories they cover.
* **Follow-up links** between days and regions, from shared `story` labels.

The file format, with every field and rule, is in [`docs/BRIEFING_FORMAT.md`](docs/BRIEFING_FORMAT.md).
A full example is in [`samples/`](samples/).

## One-time setup on GitHub

In the repository: **Settings → Pages → Build and deployment → Source: GitHub Actions**.

## Checking a file

```
ruby scripts/validate.rb                                  # every file in _posts/
ruby scripts/validate.rb _posts/2026-10-26-briefing.md    # one file
```

If a file has a problem, the build stops, nothing is published, and the previous day's site
stays up. The Actions tab on GitHub shows which field to fix.

## Previewing on your own computer (optional)

With Ruby installed: `bundle install`, then `bundle exec jekyll serve`, and open
http://localhost:4000/InternalFraud/. To try it with sample content, copy the files from
`samples/` into `_posts/` first, and don't commit those copies.

## What's where

| Path | What it is |
|---|---|
| `_posts/` | The daily briefing files: the only thing that changes day to day |
| `_plugins/briefings.rb` | Turns the daily files into boards, briefs, keyword pages and calendar data |
| `lib/briefing_validator.rb`, `scripts/validate.rb` | The file checker |
| `_layouts/`, `_includes/`, `assets/` | Page templates, styles and scripts (design from concept #11) |
| `_data/regions.yml` | Optional region names, order and colors |
| `.github/workflows/pages.yml` | The GitHub Actions build and publish |
| `docs/`, `samples/` | Format guide and example briefings (not published on the site) |
