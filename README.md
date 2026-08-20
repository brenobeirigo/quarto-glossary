# Quarto Glossary

[![Quarto extension checks](https://github.com/brenobeirigo/quarto-glossary/actions/workflows/checks.yml/badge.svg)](https://github.com/brenobeirigo/quarto-glossary/actions/workflows/checks.yml)

`glossary` is a dependency-free Quarto Lua filter for one glossary source and
two publication targets:

- Obsidian-style `[[key]]` and `[[key|display text]]` references in `.qmd`
  source;
- accessible, keyboard-focusable HTML tooltips and a generated glossary;
- LaTeX `glossaries` entries, references, acronym expansion, and printed
  glossary sections.

The extension is the reusable form of the project-specific filter recovered
from `project/rendering/filters/glossary.lua` in the MODRLSO study history. It
retains that filter's strict unknown-key and retired-key checks while removing
its hard-coded data path and schema.

## Install

During development, add this directory to another Quarto project:

```console
quarto add /path/to/quarto-glossary
```

For this private GitHub repository, clone with an authenticated GitHub CLI and
add the local clone to the consuming Quarto project:

```console
gh repo clone brenobeirigo/quarto-glossary /path/to/quarto-glossary
quarto add /path/to/quarto-glossary
```

The shorter `quarto add brenobeirigo/quarto-glossary` command works after the
repository is made public. Quarto's GitHub shorthand does not authenticate to a
private repository.

Quarto copies extensions into each consuming project. Commit the installed
`_extensions` directory so old projects remain reproducible.

## Use

Add the filter and its glossary data path to a document or `_quarto.yml`:

```yaml
filters:
  - glossary

glossary:
  path: glossary.yml
```

Reference entries with wiki-link syntax:

```markdown
The [[fleet-management]] policy uses [[adp|ADP]].
```

In headings, wiki links resolve to plain text. They still count as glossary
usage, but do not create tooltip links or styling in Quarto website sidebars
and tables of contents. Body references retain their tooltips and links.

## Expected behavior

The repository ships two runnable examples:

- `example.qmd` renders the same source to HTML, LaTeX, and PDF. Body wiki
  links become focusable tooltip references; the glossary placeholder becomes
  an HTML definition list or LaTeX `glossaries` sections.
- `website-example/` demonstrates the website contract. Wiki links in headings
  become plain heading and table-of-contents text, keeping every TOC entry on
  Quarto's normal alignment. The same links in body paragraphs remain
  interactive tooltips.

Run the website example with:

```console
quarto preview website-example
```

Place the generated glossary where it should be printed:

```markdown
::: {.glossary}
:::
```

The placeholder creates an HTML heading and definition list. In LaTeX it emits
`\printnoidxglossary`, with separate Acronyms and Glossary sections when both
kinds exist. The no-index workflow compiles with ordinary Quarto PDF rendering;
it does not require a separate `makeglossaries` command.

The placeholder accepts optional attributes:

```markdown
::: {.glossary title="Terms" acronym-title="Abbreviations" level="2"}
:::
```

## Data

YAML and JSON are supported. The portable schema is:

```yaml
entries:
  - id: fleet-management
    term: fleet management
    definition: Coordinating fleet resources to meet service objectives.

  - id: adp
    kind: acronym
    short: ADP
    long: approximate dynamic programming
    definition: Methods that approximate downstream value in sequential decisions.

  - id: former-term
    term: former term
    definition: Kept only so old references fail with a useful message.
    status: retired
    replacement: Use fleet management.
```

Term entries require `id`, `term`, and `definition`. Acronym entries require
`id`, `kind: acronym`, `short`, and `long`; `definition` may provide a fuller
glossary description. Optional `tooltip` and `sort` fields override the default
tooltip and ordering.

For migration, these field aliases are accepted:

- `key` or `label` for `id`;
- `name` for `term`;
- `description` or `tooltip` for `definition`;
- `abbreviation` or `acronym` for `short`;
- `expansion` for `long`.

The recovered MODRLSO shape is accepted directly: `groups[].rows` is flattened,
and acronym rows with `term` as the short form and `definition` as the expansion
are normalized automatically.

## Options

```yaml
glossary:
  path: glossary.yml          # relative to the Quarto project or input file
  strict: true                # fail on unknown [[keys]]
  include-unused: false       # print only referenced entries
  link: true                  # link HTML references to glossary anchors
  title: Glossary
  acronym-title: Acronyms
  heading-level: 1
  latex-load-package: true    # set false if the template loads glossaries
```

Retired keys always fail because silently reviving retired vocabulary is rarely
safe. With `strict: false`, unknown wiki links are left unchanged.

Entry IDs must start with a letter or number and may contain letters, numbers,
underscores, periods, colons, and hyphens. Custom display text may contain
spaces and punctuation; keep formatting outside the wiki-link marker.

## Develop and verify

```console
quarto render example.qmd --to html
quarto render example.qmd --to latex
quarto render example.qmd --to pdf
quarto render website-example
python -m unittest discover -s tests -v
```

The example exercises ordinary terms, acronyms, custom display text, tooltips,
glossary anchors, LaTeX definitions, `\gls`, `\glslink`, and both printed
glossary types.

## Publish

Use this directory as the root of a dedicated public GitHub repository named
`quarto-glossary`. The distribution layout already follows Quarto's required
shape: README, LICENSE, example, and `_extensions/glossary/_extension.yml`.
Before the first release, create a `v0.1.1` tag matching the extension manifest.

## License

MIT.
