# Quarto Glossary

[![Quarto extension checks](https://github.com/brenobeirigo/quarto-glossary/actions/workflows/checks.yml/badge.svg)](https://github.com/brenobeirigo/quarto-glossary/actions/workflows/checks.yml)

`glossary` is a Quarto Lua filter for academic glossaries and acronym lists
authored with Obsidian-style wiki links. One YAML or JSON vocabulary produces:

- accessible, keyboard-focusable HTML tooltips;
- separate HTML Acronyms and Glossary lists;
- first-use acronym expansion in HTML and LaTeX;
- native LaTeX `glossaries` or `glossaries-extra` entries;
- portable `noidx`, traditional `makeindex`, or Unicode-aware `bib2gls`
  workflows.

Version 0.2.0 is the reusable form of the filter recovered from the MODRLSO
study history. It has no Lua or JavaScript runtime dependencies. Advanced
LaTeX indexing requires the corresponding TeX tools described below.

## Install

Install the extension directly from GitHub in each consuming Quarto project:

```console
cd C:/path/to/your/quarto-project
quarto add brenobeirigo/quarto-glossary
```

Confirm the installed version with `quarto list extensions`. Quarto copies the
extension into `_extensions/brenobeirigo/glossary`; commit that directory so
each project remains reproducible.

## Basic use

Add the filter and vocabulary path to a document or `_quarto.yml`:

```yaml
filters:
  - glossary

glossary:
  path: glossary.yml
```

Use a key twice and the acronym expands only on first use:

```markdown
The [[adp]] policy is evaluated. Later, [[adp]] is abbreviated.
```

Place the two generated lists where they should be printed:

```markdown
::: {.glossary}
:::
```

Terms and acronyms are distinct vocabulary classes and render into separate
Glossary and Acronyms sections. Empty sections are omitted. The placeholder
accepts custom labels and HTML anchors:

```markdown
::: {#terms .glossary title="Terms" acronym-title="Abbreviations" acronym-id="abbreviations" level="2"}
:::
```

In headings, wiki links resolve to plain text. They count as uses but do not
create nested links, first-use side effects, or tooltip styling in website
sidebars and tables of contents. Body references retain tooltips and links.

## Reference forms

The alias position can select a semantic form:

| Markup | Meaning |
|---|---|
| `[[key]]` | Automatic singular form; acronyms expand on first use |
| `[[key\|plural]]` | Automatic plural form; acronyms expand on first use |
| `[[key\|short]]` | Acronym short form |
| `[[key\|long]]` | Acronym long form |
| `[[key\|full]]` | Acronym long and short forms |
| `[[key\|short-plural]]` | Explicit short plural |
| `[[key\|long-plural]]` | Explicit long plural |
| `[[key\|full-plural]]` | Explicit full plural |
| `[[key\|text]]` | Entry's configured text form |
| `[[key\|first]]` | Entry's configured first-use form |
| `[[key\|symbol]]` | Associated symbol |
| `[[key\|cap:plural]]` | Capitalized version of any semantic form |
| `[[key\|capitalized]]` | Capitalized automatic singular form |
| `[[key\|custom text]]` | Literal custom display text |
| `[[key\|=plural]]` | Literal text that would otherwise name a form |

Semantic forms generate native `\gls`, `\glspl`, `\Gls`, or `\Glspl` calls
where state matters. Explicit and custom forms remain indexed and linked but
do not consume the acronym's first-use state.

## Vocabulary data

YAML and JSON are supported. Definitions and symbols accept Markdown,
citations, emphasis, links, and mathematics:

```yaml
entries:
  - id: decision-epoch
    term: decision epoch
    text: decision epoch
    plural: decision epochs
    first: decision epoch
    first-plural: decision epochs
    symbol: $t$
    definition: A **time point** at which state $S_t$ is observed [@source].
    tooltip: A time point at which the system state is observed.
    sort: decision epoch
    see: fleet-management
    see-also: adp

  - id: adp
    kind: acronym
    short: ADP
    long: approximate dynamic programming
    short-plural: ADP methods
    long-plural: approximate dynamic programming methods
    definition: Methods that approximate downstream value [@source].
    tooltip: Methods that approximate downstream value.
```

Terms require `id`, `term`, and `definition`. Acronyms require `id`,
`kind: acronym`, `short`, and `long`; `definition` supplies the richer acronym
list description. When omitted, regular plurals are formed by appending `s`,
so academic documents should explicitly set irregular or stylistically
preferred plurals. `see` and `see-also` accept a key or comma-separated/YAML
list of keys and are validated during rendering.

For migration, `key` or `label` aliases `id`; `name` aliases `term`;
`description` aliases `definition`; `abbreviation` or `acronym` aliases
`short`; and `expansion` aliases `long`. The recovered `groups[].rows` schema
is also accepted.

If definitions contain citations, configure the document's normal
`bibliography`. The filter uses Pandoc's citation processor for LaTeX header
definitions and inserts native citation nodes into HTML glossary content.

## Options

```yaml
glossary:
  path: glossary.yml
  strict: true
  include-unused: false
  link: true
  title: Glossary
  acronym-title: Acronyms
  heading-level: 1

  latex-load-package: true
  latex-package: glossaries-extra  # glossaries-extra | glossaries
  latex-backend: noidx             # noidx | makeindex | bib2gls
  latex-location-lists: false
  latex-sort: word                 # word | letter | case | def | use
  latex-style: ""                  # e.g. altlist
  acronym-style: long-short-desc
  bib2gls-file: ""                 # optional generated database path
```

`glossaries-extra` is the default because it supports per-category acronym
styles and `see-also`. The extension explicitly selects `long-short-desc`, so
acronyms use “long form (SHORT)” on first use rather than the package's
short-only acronym default. Set `latex-package: glossaries` for the base
package; `see-also` then intentionally fails because that key is an
extra-package feature.

`latex-location-lists: true` retains page/location references. Leave it false
for compact journal-style lists. Because LaTeX cross-references such as “see
also” live in the location list, enable location lists when those relations
must appear in PDF.

## LaTeX backends

| Backend | Best fit | Build |
|---|---|---|
| `noidx` | Articles and portable projects | Ordinary `quarto render ... --to pdf` |
| `makeindex` | Conventional theses/books and publisher toolchains | LaTeX, `makeglossaries`, LaTeX twice |
| `bib2gls` | Large or multilingual vocabularies and Unicode-aware sorting | LaTeX, `bib2gls`, LaTeX twice |

`noidx` is the default and needs no external indexing command. Quarto performs
the repeated LaTeX runs automatically.

For `makeindex`, first produce LaTeX and then run the indexer:

```console
quarto render paper.qmd --to latex
lualatex paper.tex
makeglossaries paper
lualatex paper.tex
lualatex paper.tex
```

For `bib2gls`, the filter generates `_quarto-glossary-paper.bib` from the
portable YAML/JSON vocabulary:

```console
quarto render paper.qmd --to latex
lualatex paper.tex
bib2gls paper
lualatex paper.tex
lualatex paper.tex
```

Install advanced tools through TeX Live when necessary:

```console
tlmgr install glossaries glossaries-extra bib2gls
```

`latex-sort: word` uses TeX word sorting with `noidx`; with `bib2gls` it uses
the document/JVM locale. `letter`, `case`, `def`, and `use` map to bib2gls's
`letter-nocase`, `letter-case`, `none`, and `use` methods respectively.

## Examples and verification

- `example.qmd` exercises terms, acronyms, first use, semantic reference
  forms, plurals, a symbol, Markdown, mathematics, citations, related terms,
  HTML tooltips, and separate output lists.
- `website-example/` verifies that glossary markup in headings never changes
  Quarto TOC alignment while body references remain interactive.

```console
quarto render example.qmd --to html
quarto render example.qmd --to latex
quarto render example.qmd --to pdf
quarto render website-example
python -m unittest discover -s tests -v
```

The test suite builds actual PDFs with all three backends when their tools are
available. The extension follows Quarto's distribution layout and can be
installed directly from this repository root.

## License

MIT.
