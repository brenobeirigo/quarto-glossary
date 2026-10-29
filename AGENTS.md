# Instructions for agents

This repository is the source of Quarto Glossary, a Quarto filter extension.
Authors write `[[key]]` in a document. HTML output gets a definition balloon
and a link to the list entry. LaTeX output gets `\gls{key}` from the
`glossaries` or `glossaries-extra` package. The `[[ ]]` syntax comes from
Obsidian's wikilinks.

There are two sections. The first is for changing this repository. The second
is for using the extension in another project.

## Changing this repository

### Where things are

| Path | Contents |
|---|---|
| `_extensions/glossary/glossary.lua` | The whole filter: loading, references, lists, LaTeX header |
| `_extensions/glossary/glossary.js`, `glossary.css` | The HTML balloon and list styles |
| `_extensions/glossary/glossary.schema.json` | JSON Schema for vocabulary files |
| `_extensions/glossary/_extension.yml` | Manifest and version |
| `tests/test_render.py` | Render tests; each builds a temporary project and runs Quarto |
| `example.qmd`, `glossary.yml`, `references.bib` | The repository example |
| `website-example/` | Balloons in callouts, tables, captions, and the TOC |
| `docs/` | The public manual, a Quarto website that uses the extension |

### How the filter runs

`Pandoc(doc)` at the end of `glossary.lua` does the work in this order:

1. `load_registry` reads vocabulary files from `glossary.path`, then the
   front matter of `{{< include >}}`d files, then the page's own
   `glossary.entries`. Identical copies of an entry merge; different
   meanings stop the render.
2. Front matter that an include left in the body is removed.
3. Headings are expanded to plain text, then body text is expanded. Each
   `[[key|form]]` becomes a link or span in HTML and a `\gls` command in
   LaTeX.
4. Problems found in the text are reported together, and the render stops.
5. `::: {.glossary}` placeholders become the Acronyms and Glossary lists.

Lua locals must be defined before use, so helpers sit above their callers.

### Commands

```console
python -m unittest discover -s tests -v
python -m unittest tests.test_render.GlossaryRenderTests.test_included_fragments_bring_their_own_entries
quarto render example.qmd --to html
quarto render website-example
quarto render docs
```

The full suite takes 5 to 10 minutes and builds PDFs with `noidx`,
`makeindex`, and `bib2gls` when those tools are installed. Run it in the
background and run single tests while you work.

### Rules

- Keep the extension consumer-neutral. A behavior belongs here only if it is
  useful to any Quarto project. Consumer projects may carry patched copies;
  compare their code with this one before adopting a patch, since equal
  version numbers do not prove equal code.
- A behavior change needs a test in `tests/test_render.py`, an entry in
  `CHANGELOG.md`, and updated pages in `docs/`.
- A release changes the version in `_extension.yml` and `VERSION` in
  `glossary.lua`. The HTML assets are served from a path that contains the
  version, which keeps browsers from using a stale script.
- An entry field is listed in `entry_fields` in `glossary.lua` and in
  `glossary.schema.json`. A test fails when the two differ.
- Errors start with `glossary:` and warnings with `glossary warning:`. Name
  the file, the line where possible, and a fix. Tests match the exact text,
  so change messages and tests together.
- Never commit private documents, vocabularies, credentials, e-mail
  addresses, or local paths. `test_public_surface_omits_private_provenance_and_secrets`
  checks tracked files; put extra private words in the git-ignored
  `tests/private-terms.txt`.
- For HTML changes, check light and dark themes, a 375px touch screen, and
  the keyboard. `website-example/` covers the hard layouts.
- The manual itself runs in strict mode with `docs/glossary.yml`. A new
  `[[key]]` in the manual needs an entry there. Write a literal shortcode in
  the manual as `{{{< include file.qmd >}}}`.

## Using the extension in another project

Install it from the project root and commit `_extensions/`:

```console
quarto add brenobeirigo/quarto-glossary
```

Before writing `[[key]]` references, list the keys the page can use:

```console
quarto render page.qmd -M glossary-list:true 2>&1 | grep '^glossary entry'
```

Use only those keys. Use `[[key|plural]]`, `[[key|short]]`, `[[key|long]]`,
or `[[key|cap:plural]]` for other forms, and avoid custom display text that
introduces a synonym. If a concept has no entry, propose one with `id`,
`term`, and `definition` instead of adding it silently. Render before you
finish and fix every line that starts with `glossary:`. The manual page
[Writing with agents](https://brenobeirigo.github.io/quarto-glossary/agents.html)
has instructions to copy into a project's own `AGENTS.md`.
