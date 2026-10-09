# Checking runnable article examples

These helpers reuse Python 3's standard library and your existing Chromium. They do
not launch browsers, manage servers, or add a test framework. Keep fixtures, browser
profiles, and DOM dumps in temporary storage, not in the repository.

## 1. Extract the actual source

Identify a fenced example by its language and a unique literal substring inside it:

```sh
scratch=$(mktemp -d /tmp/dump-article-checks-XXXXXX)
python scripts/article_checks.py extract src/content/blog/css-layout-fundamentals.md \
  --language html --contains '<title>Task layout</title>' > "$scratch/index.html"
python scripts/article_checks.py extract src/content/blog/css-layout-fundamentals.md \
  --language css --contains '@media (min-width: 48rem)' > "$scratch/layout.css"
cp scripts/article-check-report.mjs "$scratch/"
```

Run these commands from the repository root. Missing or ambiguous matches exit
nonzero instead of silently selecting another example. Check each command's exit
status before continuing; shell redirection can leave an empty destination on failure.
Inserting an unrelated fence does not change the selected example. If the source
anchor changes, update the caller deliberately.

The extractor supports **unindented backtick and tilde fences** used by these articles,
including longer fences containing shorter ones. It is not a general Markdown parser:
examples nested in lists or blockquotes and indented code blocks are unsupported.

## 2. Run checks, then report once

Create a fixture-only `checks.mjs` beside the extracted files:

```js
import { reportChecks } from "./article-check-report.mjs";

window.addEventListener("load", () => {
  const sidebar = document.querySelector(".sidebar").getBoundingClientRect();
  const panel = document.querySelector(".task-panel").getBoundingClientRect();
  let expectedArrangement = panel.top > sidebar.top;
  if (window.innerWidth >= 768) {
    expectedArrangement = panel.left > sidebar.left && panel.top === sidebar.top;
  }

  reportChecks([
    { name: "sidebar and task panel follow the responsive layout", passed: expectedArrangement },
    {
      name: "two task rows are rendered",
      passed: document.querySelectorAll(".task-row").length === 2,
    },
  ]);
});
```

Insert `<script type="module" src="./checks.mjs"></script>` before `</body>` in the
**temporary HTML**, not the article. Each check supplies a nonempty name and a boolean
`passed`. Complete the relevant interactions, awaited operations, and measurements
before calling `reportChecks`; the helper does not infer completion. An exception
before reporting leaves no result and therefore cannot pass validation.

The reporter appends a single `<pre id="article-check-result">` with JSON containing
all checks and **measured** `window.innerWidth` / `window.innerHeight` in CSS pixels.
It uses text content, so names containing `<` or `&` remain text. Calling it twice
throws; do not reuse an old result after changing the fixture or viewport.

## 3. Verify the result, not a word in script source

Serve only the temporary fixture, in a separate terminal:

```sh
python -m http.server 8765 --bind 127.0.0.1 --directory "$scratch"
```

Use a free port; do not start another Astro/Vite server sharing the checkout's cache.
Then, in the terminal where `scratch` is defined:

```sh
chromium --headless --user-data-dir="$scratch/browser-profile" \
  --window-size=800,600 --dump-dom http://127.0.0.1:8765/ \
  > "$scratch/dom.html" 2> "$scratch/chromium.log"
python scripts/article_checks.py check "$scratch/dom.html" --width 800
```

Check Chromium's exit status and log separately. The checker prints the actual
viewport and every PASS/FAIL; it exits nonzero for a failed check, wrong width,
missing/duplicate result element, or malformed/empty report. It parses only the
result element, so PASS text in scripts or elsewhere is not evidence.

**A window-size flag is not proof of viewport size.** In particular, Chromium CLI
has produced a 500px viewport when asked for 320px. If that happens, the checker
fails even when all layout assertions pass. Use a browser session with an explicitly
controlled 320px viewport instead; inspect its fresh result element and save its DOM
for the same checker. Do not relabel the 500px run as a narrow-viewport pass.

A passing report proves only the checks you wrote at that measured viewport. It does
not prove accessible keyboard behavior, browser-console cleanliness, or all examples
in an article. Remove the temporary directory and stop the fixture server when done.

## Helper regression tests

```sh
PYTHONDONTWRITEBYTECODE=1 python -m unittest discover -s scripts -p 'test_article_checks.py'
```
