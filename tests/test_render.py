from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


PACKAGE_ROOT = Path(__file__).resolve().parents[1]
QUARTO = shutil.which("quarto")
LUALATEX = shutil.which("lualatex")
MAKEGLOSSARIES = shutil.which("makeglossaries")
BIB2GLS = shutil.which("bib2gls")
NODE = shutil.which("node")
PRIVATE_TERMS_FILE = PACKAGE_ROOT / "tests" / "private-terms.txt"
EXTENSION_VERSION = re.search(
    r"^version:\s*(\S+)",
    (PACKAGE_ROOT / "_extensions" / "glossary" / "_extension.yml").read_text(
        encoding="utf-8"
    ),
    flags=re.MULTILINE,
).group(1)

# Inline entries for the front-matter tests, indented under `glossary:`.
INLINE_ENTRIES = """entries:
  - id: velocity
    term: velocity
    plural: velocities
    symbol: $v$
    definition: The rate of change of **position** with time [@powell2022].
    see: speed, si
  - id: speed
    term: speed
    definition: The magnitude of velocity.
  - id: si
    kind: acronym
    short: SI
    long: International System of Units
    definition: The modern form of the metric system.
"""


@unittest.skipUnless(QUARTO, "Quarto is not installed")
class GlossaryRenderTests(unittest.TestCase):
    def make_project(
        self,
        body: str,
        *,
        glossary_options: str = "",
        glossary_text: str | None = None,
        glossary_name: str | None = "glossary.yml",
        bibliography: bool = True,
    ) -> Path:
        temporary = Path(tempfile.mkdtemp(prefix="quarto-glossary-test-"))
        self.addCleanup(shutil.rmtree, temporary, True)
        shutil.copytree(PACKAGE_ROOT / "_extensions", temporary / "_extensions")
        if glossary_name is None:
            pass
        elif glossary_text is None:
            shutil.copy2(PACKAGE_ROOT / "glossary.yml", temporary / glossary_name)
        else:
            (temporary / glossary_name).write_text(glossary_text, encoding="utf-8")
        if bibliography:
            shutil.copy2(PACKAGE_ROOT / "references.bib", temporary / "references.bib")

        options = "".join(f"  {line}\n" for line in glossary_options.splitlines())
        path_meta = f"  path: {glossary_name}\n" if glossary_name else ""
        bibliography_meta = "bibliography: references.bib\n" if bibliography else ""
        (temporary / "test.qmd").write_text(
            "---\n"
            "title: Test\n"
            "filters: [glossary]\n"
            "glossary:\n"
            + path_meta
            + options
            + bibliography_meta
            + "---\n\n"
            + body,
            encoding="utf-8",
        )
        return temporary

    def run_command(
        self, args: list[str], project: Path
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            args,
            cwd=project,
            text=True,
            encoding="utf-8",
            capture_output=True,
            check=False,
        )

    def render(self, project: Path, target: str) -> subprocess.CompletedProcess[str]:
        return self.run_command([QUARTO, "render", "test.qmd", "--to", target], project)

    def render_project(self, project: Path) -> subprocess.CompletedProcess[str]:
        return self.run_command([QUARTO, "render"], project)

    def assert_success(self, result: subprocess.CompletedProcess[str]) -> None:
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_html_and_latex_academic_contract(self) -> None:
        project = self.make_project(
            "[[fleet-management]], [[decision-epoch]], [[adp]], then [[adp]].\n\n"
            "Forms: [[adp|long]], [[adp|full]], [[adp|short-plural]], "
            "[[decision-epoch|plural]], [[decision-epoch|cap:plural]], "
            "and [[decision-epoch|symbol]].\n\n"
            "::: {.glossary}\n:::\n"
        )

        html_result = self.render(project, "html")
        self.assert_success(html_result)
        html = (project / "test.html").read_text(encoding="utf-8")
        self.assertIn('class="glossary-link glossary-term glossary-balloon"', html)
        balloon = re.search(
            r'<a[^>]*class="glossary-link glossary-term glossary-balloon"[^>]*>',
            html,
        )
        self.assertIsNotNone(balloon)
        self.assertIn("data-glossary-definition=", balloon.group(0))
        self.assertNotIn(" title=", balloon.group(0))
        self.assertIn(f"quarto-glossary-{EXTENSION_VERSION}/glossary.js", html)
        self.assertIn("approximate dynamic programming (ADP)", html)
        self.assertRegex(html, r">ADP</a>\.")
        self.assertIn("ADP methods", html)
        self.assertIn("Decision epochs", html)
        self.assertIn('class="math inline"', html)
        self.assertIn("<strong>time point</strong>", html)
        self.assertIn('class="citation"', html)
        self.assertIn("<em>See:</em>", html)
        self.assertIn("<em>See also:</em>", html)
        self.assertIn('id="acronyms"', html)
        self.assertIn('class="glossary-list acronym-list"', html)
        self.assertIn('id="glossary"', html)
        self.assertIn('class="glossary-list term-list"', html)
        self.assertLess(html.index('id="acronyms"'), html.index('id="glossary"'))

        latex_result = self.render(project, "latex")
        self.assert_success(latex_result)
        latex = (project / "test.tex").read_text(encoding="utf-8")
        self.assertIn(
            r"\usepackage[acronym,toc,nopostdot,nonumberlist]{glossaries-extra}",
            latex,
        )
        self.assertIn(r"\makenoidxglossaries", latex)
        self.assertIn(r"\setabbreviationstyle[acronym]{long-short-desc}", latex)
        self.assertIn(r"\longnewglossaryentry{decision-epoch}", latex)
        self.assertIn(r"\newacronym", latex)
        self.assertIn(r"\textbf{time point}", latex)
        self.assertIn(r"\(S_t\)", latex)
        self.assertIn("Powell 2022", latex)
        self.assertIn(r"\gls{adp}", latex)
        self.assertIn(r"\glspl{decision-epoch}", latex)
        self.assertIn(r"\Glspl{decision-epoch}", latex)
        self.assertIn(r"\glsadd{adp}\glslink{adp}{ADP methods}", latex)
        self.assertIn(r"\printnoidxglossary[type=\acronymtype", latex)
        self.assertIn(r"\printnoidxglossary[title={Glossary}", latex)

    def test_html_definition_display_is_exclusive_and_configurable(self) -> None:
        callout = "::: {.callout-important}\n\n[[decision-epoch]].\n\n:::\n"
        for body, element in (
            (callout + "\n::: {.glossary}\n:::\n", r'<a[^>]*class="glossary-link glossary-term"[^>]*>'),
            (callout, r'<span[^>]*class="glossary-term"[^>]*>'),
        ):
            project = self.make_project(
                body, glossary_options="html-definition-display: tooltip"
            )
            result = self.render(project, "html")
            self.assert_success(result)
            html = (project / "test.html").read_text(encoding="utf-8")
            tooltip = re.search(element, html)
            self.assertIsNotNone(tooltip, element)
            self.assertIn(" title=", tooltip.group(0))
            self.assertNotIn("glossary-balloon", tooltip.group(0))
            self.assertNotIn("data-glossary-definition=", tooltip.group(0))
            self.assertNotIn("glossary.js", html)

        invalid = self.make_project(
            "[[decision-epoch]].\n",
            glossary_options="html-definition-display: both",
        )
        invalid_result = self.render(invalid, "html")
        self.assertNotEqual(invalid_result.returncode, 0)
        self.assertIn(
            "html-definition-display must be balloon or tooltip",
            invalid_result.stdout + invalid_result.stderr,
        )

    def test_unknown_key_fails_in_strict_mode(self) -> None:
        project = self.make_project("An [[unknown-key]].\n")
        result = self.render(project, "html")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(
            "unknown glossary key [[unknown-key]] in test.qmd",
            result.stdout + result.stderr,
        )

    @unittest.skipUnless(NODE, "Node.js is not installed")
    def test_balloon_script_has_valid_javascript_syntax(self) -> None:
        result = self.run_command(
            [
                NODE,
                "--check",
                str(PACKAGE_ROOT / "_extensions" / "glossary" / "glossary.js"),
            ],
            PACKAGE_ROOT,
        )
        self.assert_success(result)

    def test_public_surface_omits_private_provenance_and_secrets(self) -> None:
        excluded_parts = {".git", ".quarto", "_site", "__pycache__"}
        public_files = [
            path
            for path in PACKAGE_ROOT.rglob("*")
            if path.is_file()
            and not any(part in excluded_parts for part in path.parts)
            and path.name != PRIVATE_TERMS_FILE.name
            and (
                path.suffix.lower()
                in {
                    ".bib",
                    ".css",
                    ".html",
                    ".js",
                    ".json",
                    ".lua",
                    ".md",
                    ".py",
                    ".qmd",
                    ".svg",
                    ".txt",
                    ".yml",
                    ".yaml",
                }
                or path.name == "LICENSE"
            )
        ]
        # Generic leaks: personal e-mail addresses, home-directory paths, and
        # credentials. GitHub no-reply addresses are public by design.
        patterns = {
            "e-mail address": r"[A-Za-z0-9._%+-]+@(?!users\.noreply\.github\.com)"
            r"(?!anthropic\.com)[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}",
            "Windows user path": r"[A-Za-z]:[\\/]+Users[\\/]+[A-Za-z]",
            "macOS user path": r"/Users/[A-Za-z]",
            "Linux home path": r"/home/[a-z][a-z0-9_-]*/",
            "private key": "BEGIN " + "(RSA |EC |OPENSSH )?PRIVATE KEY",
            "GitHub token": r"\b(ghp|gho|ghs|ghu)_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}",
        }
        # Project names, affiliations, and other private words stay out of the
        # repository: list them one per line in the untracked
        # tests/private-terms.txt or in QUARTO_GLOSSARY_PRIVATE_TERMS
        # (comma-separated).
        private_terms = os.environ.get("QUARTO_GLOSSARY_PRIVATE_TERMS", "").split(",")
        if PRIVATE_TERMS_FILE.exists():
            private_terms += PRIVATE_TERMS_FILE.read_text(encoding="utf-8").splitlines()
        private_terms = [term.strip() for term in private_terms if term.strip()]

        for path in public_files:
            text = path.read_text(encoding="utf-8", errors="replace")
            relative = path.relative_to(PACKAGE_ROOT)
            for label, pattern in patterns.items():
                match = re.search(pattern, text)
                self.assertIsNone(
                    match, f"{label} in {relative}: {match and match.group(0)}"
                )
            lowered = text.lower()
            for term in private_terms:
                # assertFalse keeps the term and file contents out of the log.
                self.assertFalse(
                    term.lower() in lowered, f"private term in {relative}"
                )

    def test_json_source_and_related_key_lists(self) -> None:
        source = {
            "entries": [
                {
                    "id": "model",
                    "term": "model",
                    "plural": "models",
                    "definition": "A mathematical representation.",
                    "see-also": ["mdp"],
                },
                {
                    "id": "mdp",
                    "kind": "acronym",
                    "short": "MDP",
                    "long": "Markov decision process",
                    "definition": "A sequential decision model.",
                    "see": ["model"],
                },
            ]
        }
        project = self.make_project(
            "[[model]] and [[mdp]].\n\n::: {.glossary}\n:::\n",
            glossary_text=json.dumps(source),
            glossary_name="glossary.json",
            bibliography=False,
        )
        self.assert_success(self.render(project, "html"))
        html = (project / "test.html").read_text(encoding="utf-8")
        self.assertIn("Markov decision process (MDP)", html)
        self.assertIn("<em>See:</em>", html)
        self.assertIn("<em>See also:</em>", html)

    def test_latex_package_backend_and_location_options(self) -> None:
        base_glossary = (
            "entries:\n"
            "  - id: method\n"
            "    term: method\n"
            "    plural: methods\n"
            "    definition: A **documented** method with $x$.\n"
            "  - id: api\n"
            "    kind: acronym\n"
            "    short: API\n"
            "    long: application programming interface\n"
            "    definition: A software interface.\n"
        )
        body = "[[method]] and [[api]].\n\n::: {.glossary}\n:::\n"

        base = self.make_project(
            body,
            glossary_options="latex-package: glossaries",
            glossary_text=base_glossary,
            bibliography=False,
        )
        self.assert_success(self.render(base, "latex"))
        base_tex = (base / "test.tex").read_text(encoding="utf-8")
        self.assertIn(
            r"\usepackage[acronym,toc,nopostdot,nonumberlist]{glossaries}",
            base_tex,
        )
        self.assertIn(r"\setacronymstyle{long-short-desc}", base_tex)

        indexed = self.make_project(
            body,
            glossary_options=(
                "latex-backend: makeindex\n"
                "latex-location-lists: true\n"
                "latex-style: altlist"
            ),
            glossary_text=base_glossary,
            bibliography=False,
        )
        self.assert_success(self.render(indexed, "latex"))
        indexed_tex = (indexed / "test.tex").read_text(encoding="utf-8")
        self.assertIn(r"\makeglossaries", indexed_tex)
        self.assertIn(r"\setglossarystyle{altlist}", indexed_tex)
        self.assertIn(r"\printglossary[type=\acronymtype", indexed_tex)
        self.assertNotIn("nonumberlist", indexed_tex)

        bib = self.make_project(
            body,
            glossary_options="latex-backend: bib2gls\nlatex-location-lists: true",
            glossary_text=base_glossary,
            bibliography=False,
        )
        self.assert_success(self.render(bib, "latex"))
        bib_tex = (bib / "test.tex").read_text(encoding="utf-8")
        self.assertIn(
            r"\usepackage[acronym,toc,nopostdot,record]{glossaries-extra}",
            bib_tex,
        )
        self.assertIn(r"\GlsXtrLoadResources", bib_tex)
        self.assertIn("save-locations={true}", bib_tex)
        self.assertIn(r"\printunsrtglossary[type=\acronymtype", bib_tex)
        databases = list(bib.glob("_quarto-glossary-*.bib"))
        self.assertEqual(len(databases), 1)
        database = databases[0].read_text(encoding="utf-8")
        self.assertIn("@entry{method", database)
        self.assertIn("@acronym{api", database)
        self.assertIn(r"\textbf{documented}", database)
        self.assertIn(r"\(x\)", database)

    @unittest.skipUnless(LUALATEX and MAKEGLOSSARIES, "indexed LaTeX tools unavailable")
    def test_makeindex_backend_builds_pdf(self) -> None:
        project = self.make_project(
            "[[fleet-management]], [[decision-epoch|symbol]], [[adp]], and "
            "[[adp|long]].\n\n"
            "::: {.glossary}\n:::\n",
            glossary_options="latex-backend: makeindex\nlatex-location-lists: true",
        )
        self.assert_success(self.render(project, "latex"))
        for command in (
            [LUALATEX, "-interaction=nonstopmode", "-halt-on-error", "test.tex"],
            [MAKEGLOSSARIES, "test"],
            [LUALATEX, "-interaction=nonstopmode", "-halt-on-error", "test.tex"],
            [LUALATEX, "-interaction=nonstopmode", "-halt-on-error", "test.tex"],
        ):
            self.assert_success(self.run_command(command, project))
        self.assertTrue((project / "test.pdf").exists())

    @unittest.skipUnless(LUALATEX and BIB2GLS, "bib2gls tools unavailable")
    def test_bib2gls_backend_builds_pdf(self) -> None:
        project = self.make_project(
            "[[fleet-management]], [[decision-epoch|symbol]], [[adp]], and "
            "[[adp|long]].\n\n"
            "::: {.glossary}\n:::\n",
            glossary_options="latex-backend: bib2gls\nlatex-location-lists: true",
        )
        self.assert_success(self.render(project, "latex"))
        for command in (
            [LUALATEX, "-interaction=nonstopmode", "-halt-on-error", "test.tex"],
            [BIB2GLS, "test"],
            [LUALATEX, "-interaction=nonstopmode", "-halt-on-error", "test.tex"],
            [LUALATEX, "-interaction=nonstopmode", "-halt-on-error", "test.tex"],
        ):
            self.assert_success(self.run_command(command, project))
        self.assertTrue((project / "test.pdf").exists())

    def test_website_toc_keeps_plain_aligned_heading_text(self) -> None:
        project = self.make_project(
            "## [[fleet-management]] decisions\n\n"
            "Body reference: [[fleet-management]].\n\n"
            "## [[adp]] methods\n\n"
            "First body use: [[adp]].\n\n"
            "::: {.callout-important title=\"Callout definition\"}\n\n"
            "Callout reference: [[decision-epoch]].\n\n"
            ":::\n\n"
            "| Location | Glossary reference |\n"
            "|---|---|\n"
            "| Table cell | [[decision-epoch]] |\n"
            ": Caption reference to [[adp]]. {#tbl-balloon-containers}\n\n"
            "::: {.glossary}\n:::\n"
        )
        (project / "_quarto.yml").write_text(
            "project:\n"
            "  type: website\n"
            "website:\n"
            "  title: Glossary website test\n"
            "  sidebar:\n"
            "    contents: [test.qmd]\n"
            "format:\n"
            "  html:\n"
            "    toc: true\n",
            encoding="utf-8",
        )

        result = self.render_project(project)
        self.assert_success(result)
        html = (project / "_site" / "test.html").read_text(encoding="utf-8")
        toc_match = re.search(r'<nav id="TOC".*?</nav>', html, flags=re.DOTALL)
        self.assertIsNotNone(toc_match, "rendered website has no table of contents")
        toc = toc_match.group(0)
        self.assertNotIn("glossary-term", toc)
        self.assertNotIn("glossary-link", toc)
        self.assertNotIn("data-glossary-", toc)
        self.assertIn("fleet management decisions", toc)
        self.assertIn("ADP methods", toc)

        heading = re.search(
            r'<h2[^>]*id="fleet-management-decisions".*?</h2>',
            html,
            flags=re.DOTALL,
        )
        self.assertIsNotNone(heading)
        self.assertNotIn("glossary-term", heading.group(0))
        self.assertIn('class="glossary-link glossary-term glossary-balloon"', html)
        callout = re.search(
            r'<div class="[^"]*callout-important[^"]*".*?'
            r'class="glossary-link glossary-term glossary-balloon"',
            html,
            flags=re.DOTALL,
        )
        self.assertIsNotNone(callout)
        self.assertIn('id="tbl-balloon-containers"', html)
        self.assertRegex(
            html,
            r'(?s)<figcaption[^>]*>.*?'
            r'class="glossary-link glossary-term glossary-balloon"',
        )
        self.assertRegex(
            html,
            r'<td><a[^>]*class="glossary-link glossary-term glossary-balloon"',
        )
        css_files = list((project / "_site").rglob("glossary.css"))
        self.assertEqual(len(css_files), 1)
        self.assertIn(
            ".glossary-balloon-popup",
            css_files[0].read_text(encoding="utf-8"),
        )
        script_files = list((project / "_site").rglob("glossary.js"))
        self.assertEqual(len(script_files), 1)
        self.assertIn(
            "document.body.appendChild(popup)",
            script_files[0].read_text(encoding="utf-8"),
        )
        self.assertIn("approximate dynamic programming (ADP)", html)

    def test_html_glossary_page_links_references_on_other_pages(self) -> None:
        project = self.make_project(
            "This page holds the lists. First use: [[adp]].\n\n::: {.glossary}\n:::\n",
            glossary_options="include-unused: true",
        )
        (project / "_quarto.yml").write_text(
            "project:\n"
            "  type: website\n"
            "website:\n"
            "  title: Glossary page test\n"
            "filters: [glossary]\n"
            "bibliography: references.bib\n"
            "glossary:\n"
            "  path: glossary.yml\n"
            "  include-unused: true\n"
            "  html-glossary-page: test.qmd\n",
            encoding="utf-8",
        )
        (project / "chapter").mkdir()
        (project / "chapter" / "usage.qmd").write_text(
            "---\ntitle: Usage\n---\n\nThe operator applies [[fleet-management]] principles.\n",
            encoding="utf-8",
        )

        result = self.render_project(project)
        self.assert_success(result)
        usage = (project / "_site" / "chapter" / "usage.html").read_text(encoding="utf-8")
        self.assertIn("href=\"../test.html#glossary-fleet-management\"", usage)
        page = (project / "_site" / "test.html").read_text(encoding="utf-8")
        self.assertIn("href=\"#glossary-adp\"", page)
        self.assertIn("id=\"glossary-fleet-management\"", page)

    def test_front_matter_entries_need_no_vocabulary_file(self) -> None:
        project = self.make_project(
            "The [[velocity]] has a [[speed]].\n\n::: {.glossary}\n:::\n",
            glossary_options=INLINE_ENTRIES,
            glossary_name=None,
        )
        self.assertFalse((project / "glossary.yml").exists())

        self.assert_success(self.render(project, "html"))
        html = (project / "test.html").read_text(encoding="utf-8")
        self.assertIn('data-glossary-id="velocity"', html)
        self.assertIn("<strong>position</strong>", html)
        self.assertIn('class="citation"', html)
        # The SI entry is only named by `see`, so it is printed as a target.
        self.assertIn('id="glossary-si"', html)
        self.assertIn('href="#glossary-si"', html)

        self.assert_success(self.render(project, "latex"))
        latex = (project / "test.tex").read_text(encoding="utf-8")
        self.assertIn(r"\longnewglossaryentry{velocity}", latex)
        self.assertIn("see={speed,si}", latex)
        self.assertIn(r"\glsadd{si}", latex)

    def test_file_list_and_front_matter_entries_combine(self) -> None:
        project = self.make_project(
            "[[adp]], [[speed]], and [[extra]].\n\n::: {.glossary}\n:::\n",
            glossary_options=(
                "entries:\n"
                "  - id: extra\n"
                "    term: extra term\n"
                "    definition: Defined only in this document.\n"
            ),
            glossary_name=None,
        )
        (project / "physics.yml").write_text(
            "\n".join(INLINE_ENTRIES.splitlines()), encoding="utf-8"
        )
        shutil.copy2(PACKAGE_ROOT / "glossary.yml", project / "glossary.yml")
        source = (project / "test.qmd").read_text(encoding="utf-8")
        (project / "test.qmd").write_text(
            source.replace(
                "glossary:\n", "glossary:\n  path: [glossary.yml, physics.yml]\n", 1
            ),
            encoding="utf-8",
        )
        self.assert_success(self.render(project, "html"))
        html = (project / "test.html").read_text(encoding="utf-8")
        for entry in ("adp", "speed", "extra"):
            self.assertIn(f'id="glossary-{entry}"', html)

        (project / "test.qmd").write_text(
            source.replace(
                "glossary:\n",
                "glossary:\n  path: physics.yml\n",
                1,
            ).replace("id: extra", "id: speed"),
            encoding="utf-8",
        )
        duplicate = self.render(project, "html")
        self.assertNotEqual(duplicate.returncode, 0)
        self.assertIn(
            "glossary id 'speed' is defined differently in physics.yml and "
            "glossary.entries (term differs)",
            duplicate.stdout + duplicate.stderr,
        )

    def test_included_fragments_bring_their_own_entries(self) -> None:
        project = self.make_project(
            "Intro.\n\n{{< include part-a.qmd >}}\n\n"
            "::: {.exercise}\n{{< include part-b.qmd >}}\n:::\n\n"
            "{{< include part-a.qmd >}}\n\n"
            "<!-- {{< include unused.qmd >}} -->\n\n"
            "::: {.glossary}\n:::\n",
            glossary_name=None,
            bibliography=False,
        )
        source = (project / "test.qmd").read_text(encoding="utf-8")
        (project / "test.qmd").write_text(
            source.replace("glossary:\n", "glossary:\n  link: true\n", 1),
            encoding="utf-8",
        )

        def fragment(name: str, entry: str, body: str) -> None:
            (project / name).write_text(
                f"---\nglossary:\n  entries:\n    - {entry}\n---\n\n{body}\n",
                encoding="utf-8",
            )

        nested = "{id: nested-list, term: nested list, definition: A list of lists.}"
        fragment("part-a.qmd", nested, "Read a [[nested-list]].")
        fragment(
            "part-b.qmd",
            "{id: pass, term: pass, definition: One run of the outer loop.}",
            "Count each [[pass]].\n\n{{< include part-a.qmd >}}",
        )
        fragment("unused.qmd", "{id: pass, term: pass, definition: Other.}", "")

        self.assert_success(self.render(project, "html"))
        html = (project / "test.html").read_text(encoding="utf-8")
        self.assertEqual(html.count('data-glossary-id="nested-list"'), 3)
        self.assertIn('data-glossary-id="pass"', html)
        self.assertIn('id="glossary-nested-list"', html)
        self.assertIn('id="glossary-pass"', html)
        self.assertNotRegex(html, r"\[\[|glossary:\s*entries|id: nested-list")

        fragment(
            "part-b.qmd",
            "{id: nested-list, term: nested list, definition: Another meaning.}",
            "Count each [[nested-list]].",
        )
        conflict = self.render(project, "html")
        self.assertNotEqual(conflict.returncode, 0)
        self.assertIn(
            "glossary id 'nested-list' is defined differently in part-a.qmd and "
            "part-b.qmd (definition differs)",
            conflict.stdout + conflict.stderr,
        )

    def test_included_fragment_keeps_the_page_settings(self) -> None:
        project = self.make_project(
            "[[adp]] and [[pass]].\n\n{{< include part.qmd >}}\n\n"
            "::: {.glossary}\n:::\n",
            bibliography=False,
        )
        (project / "part.qmd").write_text(
            "---\nglossary:\n  entries:\n"
            "    - {id: pass, term: pass, definition: One run of the loop.}\n"
            "---\n\nCount each [[pass]].\n",
            encoding="utf-8",
        )
        self.assert_success(self.render(project, "html"))
        html = (project / "test.html").read_text(encoding="utf-8")
        self.assertIn('id="glossary-adp"', html)
        self.assertIn('id="glossary-pass"', html)

        (project / "part.qmd").write_text(
            (project / "part.qmd").read_text(encoding="utf-8").replace(
                "Count each [[pass]].", "Count each [[passs]]."
            ),
            encoding="utf-8",
        )
        result = self.render(project, "html")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(
            "unknown glossary key [[passs]] in part.qmd:7; did you mean [[pass]]?",
            result.stdout + result.stderr,
        )

    def test_text_problems_are_reported_together_with_suggestions(self) -> None:
        project = self.make_project(
            "[[ADP]], [[decison-epoch]], [[adp|cap:plurl]], and [[zzz]].\n\n"
            "Again [[zzz]].\n"
        )
        result = self.render(project, "html")
        output = result.stdout + result.stderr
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("glossary: 4 problems:", output)
        self.assertIn(
            "unknown glossary key [[ADP]] in test.qmd:9; did you mean [[adp]]?", output
        )
        self.assertIn("did you mean [[decision-epoch]]?", output)
        self.assertIn("unknown reference form 'cap:plurl' in test.qmd:9; "
                      "did you mean 'cap:plural'?", output)
        self.assertIn(
            "unknown glossary key [[zzz]] in test.qmd:9, test.qmd:11\n", output
        )

        project = self.make_project(
            "[[adp|plurals]] and [[adp|=plurals]].\n", glossary_options="strict: false"
        )
        result = self.render(project, "html")
        self.assert_success(result)
        output = result.stdout + result.stderr
        self.assertEqual(output.count("did you mean the form 'plural'?"), 1)

        project = self.make_project("[[nothing-here]].\n", glossary_options="strict: false")
        result = self.render(project, "html")
        self.assert_success(result)
        self.assertIn("glossary warning: unknown glossary key [[nothing-here]]",
                      result.stdout + result.stderr)

    def test_vocabulary_mistakes_name_file_and_field(self) -> None:
        project = self.make_project(
            "[[child]].\n",
            glossary_text=(
                "entries:\n"
                "  - {id: child, term: child, plurl: children, "
                "definition: A young person.}\n"
                "  - {id: category, term: category, definition: A class.}\n"
                "  - {id: analysis, term: analysis, definition: A study.}\n"
                "  - {id: box, term: box, definition: A container.}\n"
            ),
            bibliography=False,
        )
        source = (project / "test.qmd").read_text(encoding="utf-8")
        (project / "test.qmd").write_text(
            source.replace("[[child]].", "[[category|plural]], [[analysis|plural]], "
                           "[[box|plural]], [[child]]."),
            encoding="utf-8",
        )
        result = self.render(project, "html")
        self.assert_success(result)
        self.assertIn("entry 'child' in glossary.yml has unknown field 'plurl'; "
                      "did you mean 'plural'?", result.stdout + result.stderr)
        html = (project / "test.html").read_text(encoding="utf-8")
        for plural in ("categories", "analyses", "boxes"):
            self.assertIn(f">{plural}<", html)

        (project / "glossary.yml").write_text(
            "entries:\n  - {id: x, term: x, defintion: Typo.}\n", encoding="utf-8"
        )
        result = self.render(project, "html")
        self.assertNotEqual(result.returncode, 0)
        output = result.stdout + result.stderr
        self.assertIn("entry 'x' in glossary.yml has no definition", output)
        self.assertIn("did you mean 'definition'?", output)

        (project / "glossary.yml").write_text("entries:\n  - id: [x\n", encoding="utf-8")
        result = self.render(project, "html")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("glossary: cannot parse glossary.yml:", result.stdout + result.stderr)

    def test_top_level_entries_get_an_indentation_hint(self) -> None:
        project = self.make_project("[[x]].\n", glossary_name=None, bibliography=False)
        (project / "test.qmd").write_text(
            "---\ntitle: Test\nfilters: [glossary]\nentries:\n"
            "  - {id: x, term: x, definition: An x.}\n---\n\n[[x]].\n",
            encoding="utf-8",
        )
        result = self.render(project, "html")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Indent it under glossary:", result.stdout + result.stderr)

    def test_heading_only_use_reaches_the_pdf_list(self) -> None:
        project = self.make_project("# About [[adp]]\n\nText.\n\n::: {.glossary}\n:::\n")
        self.assert_success(self.render(project, "latex"))
        latex = (project / "test.tex").read_text(encoding="utf-8")
        self.assertIn(r"\glsadd{adp}", latex)

    def test_missing_vocabulary_file_explains_both_sources(self) -> None:
        project = self.make_project("[[adp]].\n", glossary_name=None)
        result = self.render(project, "html")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(
            "cannot find vocabulary file 'glossary.yml'", result.stdout + result.stderr
        )
        self.assertIn("glossary.entries", result.stdout + result.stderr)

    def test_comma_separated_related_keys(self) -> None:
        project = self.make_project(
            "[[alpha]].\n\n::: {.glossary}\n:::\n",
            glossary_text=(
                "entries:\n"
                "  - {id: alpha, term: alpha, definition: First., see: 'beta, gamma'}\n"
                "  - {id: beta, term: beta, definition: Second.}\n"
                "  - {id: gamma, term: gamma, definition: Third.}\n"
            ),
            bibliography=False,
        )
        self.assert_success(self.render(project, "html"))
        html = (project / "test.html").read_text(encoding="utf-8")
        self.assertIn('href="#glossary-beta"', html)
        self.assertIn('href="#glossary-gamma"', html)
        self.assertIn('id="glossary-gamma"', html)
        # The See line shares the entry's single <dd>, keeping the grid aligned.
        alpha = re.search(r'id="glossary-alpha".*?</dd>', html, flags=re.DOTALL)
        self.assertIsNotNone(alpha)
        self.assertIn("<em>See:</em>", alpha.group(0))

    def test_placeholder_can_list_every_entry(self) -> None:
        project = self.make_project(
            "Only [[adp]] is used.\n\n::: {.glossary include-unused=\"true\"}\n:::\n"
        )
        self.assert_success(self.render(project, "html"))
        html = (project / "test.html").read_text(encoding="utf-8")
        self.assertIn('id="glossary-fleet-management"', html)
        self.assertIn('id="glossary-decision-epoch"', html)

        self.assert_success(self.render(project, "latex"))
        latex = (project / "test.tex").read_text(encoding="utf-8")
        self.assertIn(r"\glsaddall", latex)

    def test_balloon_text_omits_parenthetical_citations(self) -> None:
        project = self.make_project(
            "[[method]].\n\n::: {.glossary}\n:::\n",
            glossary_text=(
                "entries:\n"
                "  - id: method\n"
                "    term: method\n"
                "    definition: A documented procedure [@powell2022].\n"
            ),
        )
        self.assert_success(self.render(project, "html"))
        html = (project / "test.html").read_text(encoding="utf-8")
        self.assertIn('data-glossary-definition="A documented procedure."', html)
        self.assertNotIn("[@powell2022]", html)
        self.assertIn('class="citation"', html)

    def test_references_with_spaces_can_touch(self) -> None:
        project = self.make_project(
            "Glued: [[adp|the long name]][[decision-epoch|each time point]] end.\n",
        )
        self.assert_success(self.render(project, "html"))
        html = (project / "test.html").read_text(encoding="utf-8")
        self.assertIn(">the long name</", html)
        self.assertIn(">each time point</", html)
        self.assertNotIn("[[", html.split("<main", 1)[-1])

    def test_references_without_a_list_are_not_dead_links(self) -> None:
        project = self.make_project("Only prose: [[adp]].\n")
        self.assert_success(self.render(project, "html"))
        html = (project / "test.html").read_text(encoding="utf-8")
        self.assertNotIn('href="#glossary-adp"', html)
        self.assertRegex(
            html, r'<span[^>]*class="glossary-term glossary-balloon"[^>]*data-glossary-id="adp"'
        )

    def test_typst_and_docx_render(self) -> None:
        for body in (
            "[[decision-epoch]] and [[adp]].\n\n::: {.glossary}\n:::\n",
            "[[decision-epoch]] and [[adp]], with no list.\n",
        ):
            project = self.make_project(body)
            for target, output in (("typst", "test.pdf"), ("docx", "test.docx")):
                with self.subTest(target=target, body=body[-20:]):
                    self.assert_success(self.render(project, target))
                    self.assertTrue((project / output).exists())

    def test_vocabulary_listing_and_page_warnings(self) -> None:
        project = self.make_project(
            "## Intro\n\nOnly [[speed]].\n",
            glossary_options=INLINE_ENTRIES,
            glossary_name=None,
        )
        result = self.run_command(
            [QUARTO, "render", "test.qmd", "--to", "html", "-M", "glossary-list:true"],
            project,
        )
        self.assert_success(result)
        output = result.stdout + result.stderr
        self.assertIn("glossary entry: [[si]]\tacronym\tSI (International System of Units)",
                      output)
        self.assertIn("glossary entry: [[speed]]\tterm\tspeed\tglossary.entries", output)
        # velocity is defined on the page and never used; si is not printed
        # either, since only velocity names it.
        self.assertIn("entry 'velocity' is defined for test.qmd but never used", output)
        self.assertIn("has no ::: {.glossary} placeholder", output)

        source = (project / "test.qmd").read_text(encoding="utf-8")
        (project / "test.qmd").write_text(
            source.replace("Only [[speed]].", "[[velocity]] and [[speed]].\n\n"
                           "::: {.glossary}\n:::"),
            encoding="utf-8",
        )
        result = self.render(project, "html")
        self.assert_success(result)
        self.assertNotIn("glossary warning", result.stdout + result.stderr)
        html = (project / "test.html").read_text(encoding="utf-8")
        # The lists follow the page's top section level, ##.
        self.assertRegex(html, r'<h2[^>]*>Glossary</h2>')

    def test_locations_skip_code(self) -> None:
        project = self.make_project(
            "Inline `[[zzz]]` mention.\n\n"
            "```markdown\n[[zzz]]\n```\n\n"
            "~~~\n[[zzz]]\n~~~\n\n"
            "Real [[zzz]] use.\n"
        )
        result = self.render(project, "html")
        self.assertNotEqual(result.returncode, 0)
        lines = (project / "test.qmd").read_text(encoding="utf-8").splitlines()
        real = lines.index("Real [[zzz]] use.") + 1
        self.assertIn(
            f"unknown glossary key [[zzz]] in test.qmd:{real}\n",
            result.stdout + result.stderr,
        )

    def test_only_reader_metadata_expands_references(self) -> None:
        project = self.make_project("Text.\n", bibliography=False)
        source = (project / "test.qmd").read_text(encoding="utf-8")
        (project / "test.qmd").write_text(
            source.replace(
                "title: Test\n",
                "title: Test\n"
                "image-alt: A figure showing [[not-a-key]]\n"
                "abstract: The [[adp]] policy.\n",
                1,
            ),
            encoding="utf-8",
        )
        self.assert_success(self.render(project, "html"))
        html = (project / "test.html").read_text(encoding="utf-8")
        self.assertIn('data-glossary-id="adp"', html)

    def test_pdf_acronym_list_matches_html(self) -> None:
        project = self.make_project("[[adp]].\n\n::: {.glossary}\n:::\n")
        self.assert_success(self.render(project, "latex"))
        latex = (project / "test.tex").read_text(encoding="utf-8")
        self.assertIn(r"\renewcommand*{\glsxtrlongshortdescsort}"
                      r"{\expandonce\glsxtrorgshort}", latex)


class VocabularySchemaTests(unittest.TestCase):
    SCHEMA = PACKAGE_ROOT / "_extensions" / "glossary" / "glossary.schema.json"

    def test_schema_knows_every_field_the_filter_reads(self) -> None:
        schema = json.loads(self.SCHEMA.read_text(encoding="utf-8"))
        fields = set(schema["definitions"]["entry"]["properties"])
        lua = (PACKAGE_ROOT / "_extensions" / "glossary" / "glossary.lua").read_text(
            encoding="utf-8"
        )
        block = re.search(r"local entry_fields = \{\}\nfor _, name in ipairs\(\{(.*?)\}\)",
                          lua, flags=re.S)
        self.assertIsNotNone(block)
        self.assertEqual(fields, set(re.findall(r'"([^"]+)"', block.group(1))))

    def test_vocabularies_validate(self) -> None:
        try:
            import jsonschema
            import yaml
        except ImportError:
            self.skipTest("jsonschema and PyYAML are not installed")
        validator = jsonschema.Draft7Validator(
            json.loads(self.SCHEMA.read_text(encoding="utf-8"))
        )
        for path in (PACKAGE_ROOT / "glossary.yml", PACKAGE_ROOT / "docs" / "glossary.yml"):
            with self.subTest(path=path.name):
                errors = list(validator.iter_errors(
                    yaml.safe_load(path.read_text(encoding="utf-8"))))
                self.assertEqual(errors, [], [error.message for error in errors])
        typo = {"entries": [{"id": "x", "term": "x", "defintion": "Typo."}]}
        self.assertTrue(list(validator.iter_errors(typo)))


if __name__ == "__main__":
    unittest.main()
