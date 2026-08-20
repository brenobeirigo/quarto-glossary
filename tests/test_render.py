from __future__ import annotations

import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


PACKAGE_ROOT = Path(__file__).resolve().parents[1]
QUARTO = shutil.which("quarto")


@unittest.skipUnless(QUARTO, "Quarto is not installed")
class GlossaryRenderTests(unittest.TestCase):
    def make_project(self, body: str) -> Path:
        temporary = Path(tempfile.mkdtemp(prefix="quarto-glossary-test-"))
        self.addCleanup(shutil.rmtree, temporary, True)
        shutil.copytree(PACKAGE_ROOT / "_extensions", temporary / "_extensions")
        shutil.copy2(PACKAGE_ROOT / "glossary.yml", temporary / "glossary.yml")
        (temporary / "test.qmd").write_text(
            "---\n"
            "title: Test\n"
            "filters: [glossary]\n"
            "glossary:\n"
            "  path: glossary.yml\n"
            "---\n\n"
            + body,
            encoding="utf-8",
        )
        return temporary

    def render(self, project: Path, target: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [QUARTO, "render", "test.qmd", "--to", target],
            cwd=project,
            text=True,
            encoding="utf-8",
            capture_output=True,
            check=False,
        )

    def render_project(self, project: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [QUARTO, "render"],
            cwd=project,
            text=True,
            encoding="utf-8",
            capture_output=True,
            check=False,
        )

    def test_html_and_latex_contract(self) -> None:
        project = self.make_project(
            "[[fleet-management]] and [[adp|ADP]].\n\n"
            "::: {.glossary}\n:::\n"
        )

        html_result = self.render(project, "html")
        self.assertEqual(html_result.returncode, 0, html_result.stdout + html_result.stderr)
        html = (project / "test.html").read_text(encoding="utf-8")
        self.assertIn('class="glossary-link glossary-term"', html)
        self.assertIn('data-glossary-definition=', html)
        self.assertIn('id="glossary-fleet-management"', html)
        self.assertIn('class="glossary-list"', html)

        latex_result = self.render(project, "latex")
        self.assertEqual(latex_result.returncode, 0, latex_result.stdout + latex_result.stderr)
        latex = (project / "test.tex").read_text(encoding="utf-8")
        self.assertIn(r"\newglossaryentry{fleet-management}", latex)
        self.assertIn(r"\newacronym", latex)
        self.assertIn(r"\gls{fleet-management}", latex)
        self.assertIn(r"\glslink{adp}{ADP}", latex)
        self.assertIn(r"\printnoidxglossary[type=\acronymtype", latex)
        self.assertIn(r"\printnoidxglossary[title={Glossary}]", latex)

    def test_unknown_key_fails_in_strict_mode(self) -> None:
        project = self.make_project("An [[unknown-key]].\n")
        result = self.render(project, "html")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unknown glossary key [[unknown-key]]", result.stdout + result.stderr)

    def test_retired_key_fails_with_replacement(self) -> None:
        project = self.make_project("The [[old-name]].\n")
        result = self.render(project, "html")
        self.assertNotEqual(result.returncode, 0)
        output = result.stdout + result.stderr
        self.assertIn("glossary key [[old-name]] is retired", output)
        self.assertIn("Use fleet management", output)

    def test_website_toc_keeps_plain_aligned_heading_text(self) -> None:
        project = self.make_project(
            "## [[fleet-management]] decisions\n\n"
            "Body reference: [[adp]].\n\n"
            "## [[adp|ADP]] methods\n\n"
            "More prose.\n\n"
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
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        html = (project / "_site" / "test.html").read_text(encoding="utf-8")
        toc_match = re.search(r'<nav id="TOC".*?</nav>', html, flags=re.DOTALL)
        self.assertIsNotNone(toc_match, "rendered website has no table of contents")
        toc = toc_match.group(0)
        self.assertNotIn("glossary-term", toc)
        self.assertNotIn("glossary-link", toc)
        self.assertNotIn("data-glossary-", toc)
        self.assertIn("fleet management decisions", toc)
        self.assertIn("ADP methods", toc)

        # Heading markup itself is plain, but ordinary body references retain
        # the interactive tooltip contract.
        heading = re.search(
            r'<h2[^>]*id="fleet-management-decisions".*?</h2>',
            html,
            flags=re.DOTALL,
        )
        self.assertIsNotNone(heading)
        self.assertNotIn("glossary-term", heading.group(0))
        self.assertIn('class="glossary-link glossary-term"', html)


if __name__ == "__main__":
    unittest.main()
