# Contributing

Issues and pull requests are welcome. Keep changes focused, include a small
reproduction for behavior changes, and preserve support for both HTML and
LaTeX outputs.

Before opening a pull request, run:

```console
python -m unittest discover -s tests -v
quarto render example.qmd --to html
quarto render website-example
quarto render docs
```

Changes to LaTeX behavior should also render `example.qmd` to PDF when the
required TeX packages are available. Never include private documents,
credentials, local user paths, unpublished datasets, or organization-specific
vocabularies in an issue, fixture, or example.

The test suite rejects e-mail addresses, home-directory paths, and token
patterns in tracked files. To check for your own private words as well (a
project name, an affiliation), list them one per line in
`tests/private-terms.txt`. Git ignores that file.

By contributing, you agree that your contribution is licensed under the MIT
License used by this repository.
