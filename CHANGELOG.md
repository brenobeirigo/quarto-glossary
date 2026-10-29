# Changelog

## 0.5.0

- Define entries in the document or project metadata with `glossary.entries`.
  A self-contained document needs no vocabulary file.
- `glossary.path` accepts a list of files. Files and `entries` combine, and a
  key defined twice stops the render with both sources named. `path: false`
  loads no file. A missing file now produces an error that explains both
  options.
- Add the `include-unused` placeholder attribute, so a website's shared
  glossary page can list every entry without repeating the project options.
- Print entries named by `see` or `see-also` with the entries that cite them,
  in HTML and LaTeX, so cross-references always have a target.
- Create links only when the list entry exists. Pages without a list get
  focusable, unlinked terms instead of links to missing anchors, and Typst
  output no longer fails to compile on such links.
- Fix comma-separated `see` and `see-also` values such as `see: a, b`.
- Keep one `<dd>` per entry in HTML lists, so a See line or a second paragraph
  no longer shifts the list grid.
- Drop parenthetical citations from balloon, title, and `aria-label` text.
- Expand references with spaces that touch each other, such as
  `[[a|x y]][[b|z w]]`.
- Replace the private-path test with generic e-mail, home-path, and token
  checks plus an optional untracked `tests/private-terms.txt`.
- Rebuild the manual's landing page with a live demo, the ways to define
  terms, a guide to writing with AI agents, and a comparison with related
  tools. The manual now publishes a PDF demo and a shared Glossary page.

## 0.4.0

- Add `html-glossary-page`. In a website or book whose lists live on one page,
  references on every other page link to the entry on that page. A page with
  its own `.glossary` placeholder keeps in-page links. The option was already
  in use in a consuming project and is now part of the published extension.

## 0.3.0

- Publish a complete Quarto website manual with installation, authoring,
  HTML, LaTeX, option-reference, and practical-example pages.
- Add a GitHub Pages workflow and public contribution and security guidance.
- Remove project-specific references from the documentation and add a
  regression check for private paths and common secret markers.
- Expand the website example into a reusable demonstration of balloons in
  callouts, table cells, captions, and ordinary prose.

## 0.2.3

- Render definition balloons as body-level fixed popups so callouts, table
  cells, captions, responsive table wrappers, and other overflow containers
  cannot clip them.
- Preserve the native overflow and scrolling behavior of every source
  container instead of overriding it for glossary references.
- Add cell and caption coverage to the website example and regression tests.

## 0.2.2

- Allow definition balloons to escape Quarto callouts that clip overflowing
  content, targeting only final callouts that contain a balloon.
- Add callout coverage to the website example and TOC regression test.

## 0.2.1

- Prevent duplicate HTML definitions by emitting either the CSS balloon or the
  title-based tooltip, never both.
- Add `html-definition-display` with `balloon` as the default and `tooltip` as
  an opt-in alternative.

## 0.2.0

- Distinguish acronym and glossary entries in both HTML and LaTeX output.
- Expand acronyms on first use and support semantic short, long, full, plural,
  capitalized, symbol, and literal reference forms.
- Add plural, first-use, symbol, sorting, `see`, and `see-also` fields.
- Preserve Markdown, mathematics, and citations in definitions.
- Default to `glossaries-extra` with the academic `long-short-desc` acronym
  style while retaining optional base `glossaries` support.
- Add configurable location lists and glossary/acronym styles.
- Add `noidx`, `makeindex`, and generated-database `bib2gls` backends.
- Keep glossary markup out of website headings and tables of contents.
- Remove the project-specific retired/replacement vocabulary mechanism.

## 0.1.1

- Initial release with Obsidian-style references, HTML tooltips,
  no-index LaTeX glossaries, separate LaTeX acronym output, examples, and TOC
  alignment regression coverage.
