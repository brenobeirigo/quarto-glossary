from __future__ import annotations

import json
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


@unittest.skipUnless(QUARTO, "Quarto is not installed")
class GlossaryRenderTests(unittest.TestCase):
    def make_project(
        self,
        body: str,
        *,
        glossary_options: str = "",
        glossary_text: str | None = None,
        glossary_name: str = "glossary.yml",
        bibliography: bool = True,
    ) -> Path:
        temporary = Path(tempfile.mkdtemp(prefix="quarto-glossary-test-"))
        self.addCleanup(shutil.rmtree, temporary, True)
        shutil.copytree(PACKAGE_ROOT / "_extensions", temporary / "_extensions")
        if glossary_text is None:
            shutil.copy2(PACKAGE_ROOT / "glossary.yml", temporary / glossary_name)
        else:
            (temporary / glossary_name).write_text(glossary_text, encoding="utf-8")
        if bibliography:
            shutil.copy2(PACKAGE_ROOT / "references.bib", temporary / "references.bib")

        options = "".join(f"  {line}\n" for line in glossary_options.splitlines())
        bibliography_meta = "bibliography: references.bib\n" if bibliography else ""
        (temporary / "test.qmd").write_text(
            "---\n"
            "title: Test\n"
            "filters: [glossary]\n"
            "glossary:\n"
            f"  path: {glossary_name}\n"
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
        self.assertIn('class="glossary-link glossary-term"', html)
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

    def test_unknown_key_fails_in_strict_mode(self) -> None:
        project = self.make_project("An [[unknown-key]].\n")
        result = self.render(project, "html")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unknown glossary key [[unknown-key]]", result.stdout + result.stderr)

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
        self.assertIn('class="glossary-link glossary-term"', html)
        self.assertIn("approximate dynamic programming (ADP)", html)


if __name__ == "__main__":
    unittest.main()
