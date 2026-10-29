# Security and privacy

Do not report credentials, private documents, or personal data in a public
issue. Use GitHub's private vulnerability-reporting interface for this
repository when a report requires non-public details.

The extension reads the vocabulary file configured by the Quarto project and
embeds its definitions in the requested output. Treat definitions, tooltips,
citations, and related-term labels as publication content: anything placed in
the vocabulary may appear in rendered HTML, LaTeX, generated glossary
databases, or build logs.

The HTML balloon helper has no external network dependency. Definitions are
inserted with `textContent`, not interpreted as executable HTML.
