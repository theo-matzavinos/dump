"""Extract article examples and validate browser-produced result elements."""

import argparse
import json
import re
import sys
from html.parser import HTMLParser
from pathlib import Path

RESULT_ID = "article-check-result"


def extract_example(markdown, language, contains):
    """Select one unindented fenced example by language and literal source text."""
    if not language or not contains:
        raise ValueError("Language and source anchor must be nonempty.")

    matches = []
    fence = None
    body = []
    selected_language = None

    for line in markdown.splitlines(keepends=True):
        if fence is None:
            opening = re.fullmatch(r"(`{3,}|~{3,})([^\n]*)\n?", line)
            if opening is None:
                continue

            marker, info = opening.groups()
            if marker.startswith("`") and "`" in info:
                continue

            fence = marker
            tokens = info.split()
            selected_language = tokens[0] if tokens else ""
            body = []
            continue

        closing = re.fullmatch(r"([`~]+)[ \t]*\n?", line)
        if closing is not None:
            marker = closing.group(1)
            if set(marker) == {fence[0]} and len(marker) >= len(fence):
                source = "".join(body)
                if selected_language == language and contains in source:
                    matches.append(source)
                fence = None
                continue

        body.append(line)

    if fence is not None:
        raise ValueError("Unclosed code fence in article.")
    if len(matches) != 1:
        raise ValueError(
            f"Expected one {language!r} example containing {contains!r}; "
            f"found {len(matches)}. Choose a unique source anchor."
        )

    return matches[0]


class ResultParser(HTMLParser):
    """Read only the reporter's pre element, never script source or other text."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.count = 0
        self.active = False
        self.closed = False
        self.parts = []

    def handle_starttag(self, tag, attrs):
        if self.active:
            raise ValueError("Result element must contain plain JSON text, not markup.")

        if dict(attrs).get("id") != RESULT_ID:
            return

        self.count += 1
        if tag != "pre" or self.count != 1:
            raise ValueError(f"Expected exactly one pre#{RESULT_ID} element.")
        self.active = True

    def handle_endtag(self, tag):
        if self.active:
            if tag != "pre":
                raise ValueError("Unexpected closing tag inside result element.")
            self.active = False
            self.closed = True

    def handle_data(self, data):
        if self.active:
            self.parts.append(data)


def read_browser_result(dom):
    parser = ResultParser()
    parser.feed(dom)
    parser.close()
    if parser.count != 1 or not parser.closed:
        raise ValueError(f"Missing or incomplete pre#{RESULT_ID} result element.")

    result = json.loads("".join(parser.parts))
    if not isinstance(result, dict):
        raise ValueError("Result must be a JSON object.")

    viewport = result.get("viewport")
    if not isinstance(viewport, dict):
        raise ValueError("Result must include a measured viewport.")
    for dimension in ("width", "height"):
        value = viewport.get(dimension)
        if type(value) is not int or value <= 0:
            raise ValueError(f"Viewport {dimension} must be a positive integer.")

    checks = result.get("checks")
    if not isinstance(checks, list) or not checks:
        raise ValueError("Result must include at least one check.")
    for check in checks:
        if not isinstance(check, dict):
            raise ValueError("Each check must be an object.")
        name = check.get("name")
        if not isinstance(name, str) or not name.strip():
            raise ValueError("Each check must have a nonempty name.")
        if type(check.get("passed")) is not bool:
            raise ValueError(f"Check {name!r} must have a boolean passed value.")

    return result


def positive_integer(value):
    number = int(value)
    if number <= 0:
        raise argparse.ArgumentTypeError("Expected a positive integer.")
    return number


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)

    extract = commands.add_parser("extract", help="Print one identified fenced example.")
    extract.add_argument("article", type=Path)
    extract.add_argument("--language", required=True)
    extract.add_argument("--contains", required=True, help="Unique literal source anchor.")

    check = commands.add_parser("check", help="Validate a browser DOM dump or saved page DOM.")
    check.add_argument("dom", type=Path)
    check.add_argument("--width", type=positive_integer, required=True)

    args = parser.parse_args()
    try:
        if args.command == "extract":
            source = extract_example(
                args.article.read_text(encoding="utf-8"), args.language, args.contains
            )
            sys.stdout.write(source)
            return 0

        result = read_browser_result(args.dom.read_text(encoding="utf-8"))
        viewport = result["viewport"]
        print(
            f"Viewport: {viewport['width']} × {viewport['height']} CSS px "
            f"(expected width: {args.width})"
        )
        passed = viewport["width"] == args.width
        if not passed:
            print("FAIL viewport width: browser did not use the requested width.")

        for check in result["checks"]:
            label = "PASS"
            if not check["passed"]:
                label = "FAIL"
                passed = False
            print(f"{label} {check['name']}")

        if passed:
            return 0
        return 1
    except (OSError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
