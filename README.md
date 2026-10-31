# Quarto Glossary

[![Quarto extension checks](https://github.com/brenobeirigo/quarto-glossary/actions/workflows/checks.yml/badge.svg)](https://github.com/brenobeirigo/quarto-glossary/actions/workflows/checks.yml)

Glossaries and acronym lists for Quarto, the way LaTeX's `glossaries` package
does them. Write `[[key]]` in your text. Web readers get a definition balloon
on hover, keyboard focus, or tap. The PDF gets native `\gls{key}` entries.
The first use of an acronym expands it, later uses abbreviate it, and the
lists at the end contain exactly the entries you cited. The `[[ ]]` syntax is
borrowed from [Obsidian's wikilinks](https://obsidian.md/help/links), including
`[[key|other text]]` for display text.

**[Manual, live demo, and comparison with other tools](https://brenobeirigo.github.io/quarto-glossary/)**

![A source document with wiki-link references next to the rendered page, where the first use of an acronym expands and a balloon shows the definition.](docs/images/social-card.png)

- Terms in the document's front matter, in YAML or JSON files, or in the
  fragments a document includes.
- Balloons that work with a mouse, a keyboard, a screen reader, and a
  finger, and that callouts, tables, and captions cannot clip.
- Separate Acronyms and Glossary lists, the same in HTML and PDF.
- `glossaries-extra` or `glossaries`, with `noidx`, `makeindex`, or `bib2gls`.
- Mistyped keys stop the render, all listed in one message with file, line,
  and the nearest defined key.
- No R, Python, or JavaScript dependencies. Requires Quarto 1.4 or newer.

## Install

Run this in the root of each Quarto project:

```bash
quarto add brenobeirigo/quarto-glossary
```

Quarto copies the extension into `_extensions/brenobeirigo/glossary`. Commit
that directory so every build uses the same version.

## Basic use

```markdown
---
title: First glossary
filters: [glossary]
glossary:
  entries:
    - id: adp
      kind: acronym
      short: ADP
      long: approximate dynamic programming
      definition: Methods that approximate downstream value.

    - id: decision-epoch
      term: decision epoch
      definition: A time point at which the system state is observed.
---

At each [[decision-epoch]], the [[adp]] policy acts. Later, [[adp]] is
abbreviated.

::: {.glossary}
:::
```

To share terms between documents, move the `entries` list into
`glossary.yml` and point the documents or `_quarto.yml` at it:

```yaml
filters: [glossary]
glossary:
  path: glossary.yml          # or a list: [terms.yml, acronyms.yml]
```

Terms need `id`, `term`, and `definition`. Acronyms need `id`,
`kind: acronym`, `short`, and `long`. Regular English plurals are formed
automatically; set `plural:` for irregular ones. Start `glossary.yml` with
this line for completion and typo checks in VS Code:

```yaml
# yaml-language-server: $schema=_extensions/brenobeirigo/glossary/glossary.schema.json
```

## Reference forms

| Markup | Shows |
|---|---|
| `[[key]]` | The term; an acronym expands on first use |
| `[[key\|plural]]` | The plural |
| `[[key\|short]]`, `[[key\|long]]`, `[[key\|full]]` | An acronym's short, long, or full form |
| `[[key\|cap:plural]]` | Any form, capitalized |
| `[[key\|any text]]` | Your own text, still linked and indexed |
| `[[key\|=plural]]` | The literal word, when it would name a form |

All forms are in the [authoring guide](https://brenobeirigo.github.io/quarto-glossary/authoring.html).

## When something looks wrong

- Literal `[[key]]` in the page: add `filters: [glossary]`.
- `glossary:` lines on the console name the problem, the file and line, and
  a fix. `glossary warning:` lines do not stop the render.
- To see every key a page can use:
  `quarto render page.qmd -M glossary-list:true 2>&1 | grep '^glossary entry'`.

The [troubleshooting table](https://brenobeirigo.github.io/quarto-glossary/getting-started.html#when-something-looks-wrong)
covers the common cases.

## Learn more

- [Ways to define terms](https://brenobeirigo.github.io/quarto-glossary/define-terms.html):
  files, front matter, included fragments, websites with one glossary page.
- [HTML output](https://brenobeirigo.github.io/quarto-glossary/html-output.html):
  balloons, links, and styling.
- [LaTeX output](https://brenobeirigo.github.io/quarto-glossary/latex-output.html):
  packages, `noidx`, `makeindex`, and `bib2gls` builds.
- [Writing with agents](https://brenobeirigo.github.io/quarto-glossary/agents.html):
  what the vocabulary gives an agent, and what the render does not check.
- [Configuration reference](https://brenobeirigo.github.io/quarto-glossary/reference.html):
  every option, field, and check.

## Development

```console
python -m unittest discover -s tests -v
quarto render example.qmd
quarto render website-example
quarto render docs
```

The tests build real PDFs with all three LaTeX backends when their tools are
installed. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT.
