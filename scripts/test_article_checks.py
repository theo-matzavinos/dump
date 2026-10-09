import html
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from article_checks import extract_example, read_browser_result

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "scripts/article_checks.py"


def result_dom(*, width=800, checks=None):
    if checks is None:
        checks = [{"name": "task layout", "passed": True}]
    report = {"viewport": {"width": width, "height": 600}, "checks": checks}
    payload = html.escape(json.dumps(report))
    return f'<pre id="article-check-result">{payload}</pre>'


class ExtractionTests(unittest.TestCase):
    def test_unrelated_fence_does_not_change_selection(self):
        example = '```html\n<form id="tasks"></form>\n```\n'
        source = "## Example\n\n" + example
        inserted = "```js\nconsole.log('new introduction');\n```\n\n"
        expected = '<form id="tasks"></form>\n'
        self.assertEqual(extract_example(source, "html", 'id="tasks"'), expected)
        self.assertEqual(extract_example(inserted + source, "html", 'id="tasks"'), expected)

    def test_language_is_part_of_identity(self):
        source = "```js\nanchor\n```\n```html\nanchor html\n```\n"
        self.assertEqual(extract_example(source, "html", "anchor"), "anchor html\n")

    def test_long_fences_preserve_shorter_fences_in_body(self):
        source = "````markdown\n```html\nexample\n```\n````\n"
        self.assertEqual(
            extract_example(source, "markdown", "example"), "```html\nexample\n```\n"
        )

    def test_tilde_fence_and_longer_closing_fence(self):
        self.assertEqual(extract_example("~~~css\n.test {}\n~~~~", "css", ".test"), ".test {}\n")

    def test_missing_ambiguous_and_unclosed_examples_fail(self):
        source = "```js\nanchor\n```\n"
        for markdown, anchor in ((source, "absent"), (source * 2, "anchor"), ("```js\nanchor", "anchor")):
            with self.subTest(markdown=markdown, anchor=anchor):
                with self.assertRaises(ValueError):
                    extract_example(markdown, "js", anchor)

    def test_real_css_article_examples(self):
        source = (ROOT / "src/content/blog/css-layout-fundamentals.md").read_text()
        markup = extract_example(source, "html", "<title>Task layout</title>")
        styles = extract_example(source, "css", "@media (min-width: 48rem)")
        self.assertIn('<div class="workspace">', markup)
        self.assertIn("grid-template-columns: 12rem minmax(0, 1fr);", styles)


class ResultTests(unittest.TestCase):
    def test_script_source_is_not_a_result(self):
        source = '<script>const fake = \'<pre id="article-check-result">PASS</pre>\';</script>'
        with self.assertRaises(ValueError):
            read_browser_result(source)

    def test_decodes_text_entities_without_interpreting_them_as_markup(self):
        checks = [{"name": '<button> & "label"', "passed": True}]
        report = read_browser_result(result_dom(checks=checks))
        self.assertEqual(report["checks"], checks)
        self.assertEqual(report["viewport"], {"width": 800, "height": 600})

    def test_missing_duplicate_incomplete_and_nested_results_fail(self):
        valid = result_dom()
        cases = (
            "PASS all checks",
            valid + valid,
            valid.replace("</pre>", ""),
            '<pre id="article-check-result"><span>PASS</span></pre>',
            valid.replace("pre", "div"),
        )
        for source in cases:
            with self.subTest(source=source):
                with self.assertRaises(ValueError):
                    read_browser_result(source)

    def test_malformed_reports_fail(self):
        reports = (
            "not JSON",
            "null",
            "[]",
            '{}',
            '{"viewport":{"width":true,"height":600},"checks":[]}',
            '{"viewport":{"width":800,"height":0},"checks":[]}',
            '{"viewport":{"width":800,"height":600},"checks":[]}',
            '{"viewport":{"width":800,"height":600},"checks":[{"name":"x","passed":"true"}]}',
            '{"viewport":{"width":800,"height":600},"checks":[{"name":"","passed":true}]}',
        )
        for payload in reports:
            with self.subTest(payload=payload):
                with self.assertRaises(ValueError):
                    read_browser_result(f'<pre id="article-check-result">{html.escape(payload)}</pre>')

    def run_check(self, source, width):
        with tempfile.TemporaryDirectory(prefix="dump-article-check-test-") as directory:
            path = Path(directory) / "dom.html"
            path.write_text(source, encoding="utf-8")
            return subprocess.run(
                [sys.executable, str(CLI), "check", str(path), "--width", str(width)],
                text=True,
                capture_output=True,
                check=False,
            )

    def test_cli_reports_measured_viewport_and_success(self):
        completed = self.run_check(result_dom(), 800)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertIn("800 × 600 CSS px", completed.stdout)
        self.assertIn("PASS task layout", completed.stdout)

    def test_cli_fails_on_actual_failure_despite_pass_in_script(self):
        source = '<script>console.log("PASS all tests");</script>'
        source += result_dom(checks=[{"name": "task layout", "passed": False}])
        completed = self.run_check(source, 800)
        self.assertEqual(completed.returncode, 1)
        self.assertIn("FAIL task layout", completed.stdout)

    def test_cli_rejects_500px_when_320px_was_requested(self):
        completed = self.run_check(result_dom(width=500), 320)
        self.assertEqual(completed.returncode, 1)
        self.assertIn("500 × 600 CSS px", completed.stdout)
        self.assertIn("FAIL viewport width", completed.stdout)

    def test_cli_rejects_missing_result_and_nonpositive_expected_width(self):
        self.assertEqual(self.run_check("<script>PASS</script>", 800).returncode, 1)
        self.assertEqual(self.run_check(result_dom(), 0).returncode, 2)


if __name__ == "__main__":
    unittest.main()
