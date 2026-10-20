# Planned articles — suggested order

1. **HTML, the DOM, and events** — markup, event propagation, default actions, and semantics.
2. **CSS layout fundamentals** — normal flow, the box model, flex/grid, overflow, and positioning.
3. **Values, references, and identity** — assignment, mutation, equality, closures, and Angular implications.
4. **Frontend evolution, part 1: behavior** — direct DOM manipulation → jQuery-like libraries → SPA frameworks; problems solved and complexity introduced.
5. **Frontend evolution, part 2: styling** — handwritten CSS, naming conventions such as BEM, preprocessors, Bootstrap/Material, component styling, and Tailwind. These are overlapping approaches, not a strict replacement ladder.
6. **Angular component composition** — component-extraction litmus, state ownership, inputs, outputs, and content projection.
7. **Accessibility in practice** — semantic HTML, keyboard navigation, and focus management.
8. **Forms and validation** — user input, form state, validation, and submission.
9. **From API responses to UI models** — missing versus null, dates, DTOs versus domain models, and transformation boundaries.
10. **URLs as application state** — shareable filters, pagination, browser history, and router state.
11. **Browser rendering and performance** — how DOM and CSS become pixels: layout, paint, and compositing.
12. **Caching static files and requests** — browser/CDN caches, freshness, revalidation, invalidation, and application-level caching.
13. **Testing observable behavior** — testing externally visible contracts at useful boundaries, not implementation details. “Observable” here does not mean RxJS.
14. **Git behind the scenes** — objects, snapshots, staging, references, merging, rebasing, squashing, and recovery.
15. **Docker behind the scenes** — images, layers, caching, containers, networking, mounts, Compose, and multi-stage builds.
16. **Coding with agents** — tokens, context, tools/skills/MCP, task communication, bounded workflows, verification, and permissions; advice reflects current capabilities rather than permanent rules.

## Ordering rationale

Foundations → architectural context → everyday Angular development → performance and testing. Git and Docker are independent deep dives and could move earlier based on team interest.

## Feedback

Which topics would you move earlier, and are any prerequisites missing?

## Scope

This is a proposed sequence for the parked topic backlog, not a commitment to draft or publish every article. It excludes existing articles, deferred RxJS topics, and unselected suggestions.

## Agreed outline: HTML, the DOM, and events

Agreed with loozo on 2026-10-01 and parked for later drafting. Saving this outline does not authorize drafting or publication. Topics without an explicitly agreed outline below remain a proposed sequence, not agreed outlines.

**Draft status (2026-10-01):** loozo approved the final outline and authorized the first draft. Written in `src/content/blog/html-dom-and-events.md` with `draft: true`; publication is not authorized. Other articles remain parked.

**Revision (2026-10-01):** Revised with loozo's approval for entry-level and junior readers. Capture now follows the ancestor path down from the document to the clicked span, followed by target handling and bubbling back up. Added a small three-listener example before the detailed trace and explained unfamiliar terms before relying on them. Verified ten Chromium checks, including the new example, the full event path, and stopping propagation in the target's capture group; Angular strict template compilation, Astro build/check, browser preview, and production draft exclusion also passed.

**Draft verification:** Rechecked WHATWG DOM at `b2e32dc730eb0dc0cce1a431393fe4a17fda1d54`, WHATWG HTML at `bae538d057faf3fd81cd43e3187b8f9fb7fca9cb`, and Angular's event-listener/output guides at `3f9191166936166085320652eef1a562504aa3e4`. Tested the JavaScript examples in Chromium and compiled the Angular component with Angular 21.2.17 and strict template checking. Verified Angular keyboard/button submission, Astro rendering, and production draft exclusion.

**Working title:** What happens when you click: HTML, the DOM, and browser behavior.

**Reader outcome:** Understand what the browser creates from HTML, what JavaScript changes, and how an interaction reaches application code.

**Running example:** A tiny “add a task” interface: a form with a labeled text input, a submit button containing a nested `<span>`, and a list of tasks. Introduce ordinary HTML, add a little JavaScript, then show the Angular equivalent. No backend or styling exercise.

### 1. Start with three small mysteries

- Why does submitting a form navigate away?
- Why can clicking a button also trigger a listener on its parent?
- Why can an input’s current value differ from its HTML attribute?

### 2. HTML describes meaning, not just appearance

- Elements, attributes, text, and nesting.
- Links navigate; buttons perform actions; forms collect and submit input.
- Labels connect text to controls.
- A styled `<div>` does not become a button.
- Misconception: HTML is just the scaffolding that JavaScript makes interactive.

### 3. The browser builds a live object tree

- Diagram: HTML source → parsing → DOM tree; JavaScript can change that tree.
- Document, element, and text nodes; parent, child, and sibling relationships.
- Source HTML versus the current DOM in DevTools.
- Selecting an element and changing its text.
- Attributes versus properties: an input’s initial `value` attribute versus current `.value`.
- Misconception: editing the DOM changes the downloaded HTML file.
- Keep parsing details brief; this is not a parser-internals article.

### 4. Events report something happening

- Register a listener with `addEventListener` and inspect the event object.
- Distinguish `click`, `input`, and `submit`.
- Handle form submission rather than treating a button click as the entire interaction.
- Misconception: an event listener replaces whatever the browser would normally do.

### 5. Events can travel through the tree

Walk through a click on the button’s nested `<span>`:

```text
Capture:  document → … → form → button
Target:   span
Bubble:   button → form → … → document
```

- Capturing phase: ancestor capture listeners run from the outside inward, before the event reaches its target. Register them with `{ capture: true }`.
- Target phase: target capture listeners run before target non-capture listeners.
- Bubbling phase: if the event bubbles, ancestor non-capture listeners run from the target’s parent outward. Ordinary `addEventListener("click", handler)` ancestor listeners run here.
- One event travels along a path; the elements are not generating separate clicks.
- `target` identifies where the event originated in this ordinary DOM example; `currentTarget` identifies where the running listener is registered.
- Log listener location, `eventPhase`, `target`, and `currentTarget`; have readers predict the order before observing it.
- A non-bubbling event can still reach ancestor capture listeners.
- Briefly show bubbling-based event delegation and how capture allows observation before descendant handlers run.
- Omit Shadow DOM and retargeting.

### 6. Propagation and default behavior are separate

- `preventDefault()` cancels a cancelable default action; it does not stop propagation. Explain cancelability and note that passive listeners cannot cancel default actions.
- `stopPropagation()` stops further propagation, without stopping the remaining listeners in the current listener pass.
- `stopImmediatePropagation()` also stops the remaining listeners in the current listener pass.
- Neither propagation-stopping method cancels navigation or form submission.
- Demonstrate two ordinary bubbling listeners on the same button (A, then B) and one on its parent (C): calling `stopPropagation()` in A leaves B running but blocks C; calling `stopImmediatePropagation()` in A blocks both B and C.
- Cancel native submission when replacing it with client-side behavior.
- Prefer correct elements and listener placement over scattering suppression calls.

### 7. Angular uses the same browser foundation

- Revisit the example with template event bindings and `$event`.
- Angular manages template updates; the resulting elements still participate in native browser behavior.
- Keep this DOM lesson separate from change detection.
- Briefly distinguish native events from component outputs; defer composition details.

### Boundaries and closing check

Leave CSS layout, detailed validation, focus management, rendering performance, SSR/hydration, and framework evolution to their own articles. `src/content/blog/html-rendering-methods.md` already covers where HTML comes from; this article starts with what the browser does with it.

Closing check: can the reader predict listener order, identify `target` versus `currentTarget`, distinguish both propagation-stopping methods, and explain why a form still submits?

### Technical references for later drafting

- WHATWG DOM source checked at commit `b2e32dc730eb0dc0cce1a431393fe4a17fda1d54`: https://github.com/whatwg/dom.
- Angular event binding guide checked on 2026-10-01: https://angular.dev/guide/templates/event-listeners.
- Reverify technical details and runnable examples when drafting.

## Agreed outline: CSS layout fundamentals

Agreed with loozo on 2026-10-01: “good to park”. Saved for later drafting only; no drafting or publication is authorized by that original agreement.

**Draft status (2026-10-02):** loozo approved the final outline and authorized the second draft. Written in `src/content/blog/css-layout-fundamentals.md` with `draft: true`. loozo accepted the completed draft and requested its commit: `c5353dd` — `Add CSS layout fundamentals article draft`. Publication remains unauthorized.

**Technical verification:** Rechecked CSS Display, CSS Sizing, CSS Values and Units, Flexbox, Grid, Overflow, and Positioned Layout against CSSWG source at `d06dc03e286cadddd43e524a7d2edad62d6a225a`. Browser measurements cover flow, both box models, percentages, units, margin collapse/gap, flex/grid minimums, overflow, relative/absolute/fixed/sticky positioning, the running task example, and narrow-container behavior. Also checked the combined example at 320px with 16px and 32px root fonts. Final verification includes Astro build/check, development preview, links/anchors, and production draft exclusion.

**Working title:** How CSS decides where things go.

**Reader outcome:** Explain an element’s size and position, and debug a layout without randomly trying properties.

**Running example:** Reuse the task interface: input and button, task rows with actions, then a sidebar beside the task list. Test it with long text and a narrow viewport.

### 1. Layout exists before you write CSS

- Start with the unstyled document.
- Normal flow: block boxes stack; inline content flows into lines.
- Introduce block and inline directions, using ordinary horizontal text.
- `display` affects both how a box participates in its surroundings and how its children are laid out.
- Misconception: every element needs explicit positioning.

### 2. The box model explains occupied space

```text
margin
└─ border
   └─ padding
      └─ content
```

- Content, padding, border, and margin.
- Calculate one element’s width under `content-box` and `border-box`.
- Explain why `width: 100%` plus padding can overflow with `content-box`.
- Briefly demonstrate collapsing block margins; contrast with `gap` in flex/grid.
- Misconception: the declared width is always the element’s outer width.

### 3. Size comes from content, available space, and constraints

- Automatic sizing versus explicit dimensions.
- `min-width`, `max-width`, and their height equivalents.
- Percentage sizes depend on a containing block; percentage height needs particular care.
- Content has intrinsic size: a long unbreakable string can resist shrinking.
- Introduce units through their reference points: `px`, `%`, `rem`, and viewport units.
- Misconception: setting a width completely determines the final size.

### 4. Flexbox distributes space along an axis

- Container versus items; main axis versus cross axis.
- Lay out the input and submit button.
- Explain basis, growing, shrinking, alignment, wrapping, and gaps.
- Show why `flex: 1` does not necessarily make an item shrink past its automatic minimum; demonstrate when `min-width: 0` is appropriate.
- Misconception: flexbox means horizontal layout.

### 5. Grid organizes shared rows and columns

- Tracks, grid lines, placement, and gaps.
- Lay out the sidebar and task list.
- Explain fractional space and content constraints.
- Contrast `1fr` with `minmax(0, 1fr)` using overflowing content.
- Flexbox is primarily axis-oriented; grid coordinates rows and columns. Neither replaces the other.
- Misconception: an `fr` unit guarantees a fixed fraction regardless of content.

### 6. Overflow is a consequence, not automatically a bug

- Distinguish the box’s size from content extending beyond it.
- Visible overflow, clipping, and scrolling.
- Decide whether long content should wrap, scroll, or truncate.
- Show why `overflow: hidden` can conceal a sizing problem rather than solve it.
- Misconception: hiding overflow fixes the layout.

### 7. Positioning changes the rules

- `relative`: offset visually while retaining its original space.
- `absolute`: leave normal flow and position against a containing block, not necessarily the immediate parent.
- `fixed`: typically viewport-relative, with a brief caveat about ancestors that establish its containing block.
- `sticky`: retain flow participation but constrain movement during scrolling.
- Use positioning for a small badge, not for assembling the entire page.
- Misconception: `position: relative` moves an element by itself.

### 8. Debug the browser’s actual layout

- Inspect computed styles, box dimensions, and flex/grid overlays.
- Find the parent layout mode and relevant constraints before editing properties.
- In Angular, inspect component host elements too: component boundaries are not layout boundaries.
- Test longer content, narrower containers, and text zoom.
- Preserve meaningful DOM order rather than relying on visual reordering.

### Boundaries and closing check

Assume basic selectors and declarations. Keep flex/grid introductory, not exhaustive references. Leave cascade/specificity, framework styling approaches, detailed stacking contexts, animations, and rendering performance out.

Closing check: can the reader explain an overflowing row, choose flow/flex/grid, and identify what an absolutely positioned element is positioned against?

### Technical references for later drafting

- MDN introduction to CSS layout checked on 2026-10-01: https://developer.mozilla.org/en-US/docs/Learn_web_development/Core/CSS_layout/Introduction.
- MDN `min-width` reference checked on 2026-10-01: https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/min-width.
- Reverify technical details and runnable examples when drafting.

## Agreed outline: Values, references, and identity

Agreed with loozo on 2026-10-01: “good to park”. That original agreement parked the outline without authorizing drafting or publication.

**Draft status (2026-10-02):** loozo reviewed the seven-section outline and selected “Write the draft”. Written in `src/content/blog/values-references-and-identity.md` with `draft: true`. After reviewing the draft, loozo approved disabling ligatures in inline code and code blocks, then explicitly selected committing both the draft and display fix: `d2e30c5` — `Add values, references, and identity article draft`. Publication and push remain unauthorized. Remaining articles stay parked.

**Technical verification:** Rechecked ECMAScript at `2477796715947008b0eb7b170ed3d13ad3d78c9c`, Angular signal documentation/source at `860832591d58f49e5618d2898509f18d7c1cfa50`, and the TypeScript Handbook at `6556b08756b766fd41d0f887174cb0b042e5f72c`. Verification exercises the article's independent JavaScript blocks in Chromium, expected const-assignment failure, shallow freezing, equality notes, TypeScript readonly checking, and Angular's cached-computation behavior. TypeScript/Angular snippets use strict checking with TypeScript 6.0.3 and Angular core 22.2.1; the compiler version follows Angular 22.2.1's published compatibility range. Final checks include Astro build/check, development rendering, links/anchors, and production draft exclusion. No reusable verification tooling added to the repository.

**Working title:** What actually changes when you change a variable?

**Reader outcome:** Predict what assignment, mutation, copying, and callbacks do, and recognize when several parts of an application share the same object.

**Running example:** A task object, a selected task, and an editable draft with a nested owner object.

### 1. Separate the name, the value, and the object

- A variable is a binding, not the object itself.
- Primitive values are immutable; objects can have mutable properties.
- Arrays and functions are objects too.
- `const` prevents reassignment of the binding, not mutation of an object.
- Misconception: a `const` object cannot change.

### 2. Assignment does not clone an object

```text
task ──────────┐
               ├──→ one task object
selectedTask ──┘
```

- Compare assigning a number with assigning an object.
- Mutating the shared object is visible through both variables.
- Reassigning one variable does not redirect the other.
- Draw the relationships before and after each operation.
- Misconception: each variable contains its own independent object.

### 3. Function calls preserve this distinction

- Arguments are passed by value.
- Passing an object gives the parameter access to the same object; it does not clone it.
- Mutating a property can affect the caller’s object.
- Reassigning the parameter does not reassign the caller’s variable.
- Make mutation intentional at function boundaries.
- Misconception: objects are passed by reference, so replacing the parameter replaces the caller’s object.

### 4. Identity is different from matching contents

- Two separately created objects can contain identical fields without being the same object.
- `===` compares object identity, not their fields.
- Briefly introduce `Object.is`; keep `NaN` and signed-zero differences to a small note.
- Distinguish object identity, domain identity such as `task.id`, and content equality.
- Functions have identity too: two identical-looking arrow expressions create different function objects.
- Misconception: same data means same object.

### 5. A shallow copy still shares nested objects

```text
task  ──→ object A ──→ owner object
draft ──→ object B ──→ owner object
```

- Object spread creates a new outer object but retains nested object values.
- Copying an array does not copy its task objects.
- Show an edit unexpectedly changing the original task’s owner.
- Copy the changed path when isolation is needed.
- Mutation is not inherently wrong; the problem is unexpected sharing.
- Briefly distinguish TypeScript `readonly` restrictions from runtime immutability.
- Misconception: spread makes an independent copy of everything.

### 6. Closures retain access, not automatic snapshots

- Introduce lexical scope through a small callback.
- A closure can read a binding’s later value when it runs.
- Contrast reading the current selection with deliberately capturing a task for a later operation.
- Capturing an object still does not clone or freeze it.
- Briefly show a returned function retaining access after its outer function finishes.
- Misconception: a callback remembers every value exactly as it was when the callback was created.

### 7. Connect the model to Angular

- Mutating an object and replacing it are different operations at an input or signal boundary.
- Signals use `Object.is` by default; deep mutation is not itself a signal notification.
- A new outer object can still contain shared nested state.
- Updating data and arranging a UI refresh are separate concerns.
- Link to `src/content/blog/angular-change-detection.md` rather than reteaching its machinery.

### Boundaries and closing check

Leave coercion puzzles, engine memory layout, garbage-collector internals, cloning-library comparisons, and state-management frameworks out. No blanket “always mutate” or “never mutate” prescription.

Closing check: can the reader draw which objects are shared, predict what changes after a function call, and explain whether a callback reads current state or deliberately captured state?

### Technical references for later drafting

- MDN functions guide checked on 2026-10-01: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Guide/Functions.
- Angular signals guide checked on 2026-10-01: https://angular.dev/guide/signals.
- Existing change-detection article reviewed to keep the Angular connection brief and avoid duplicating its coverage.
- Reverify technical details and runnable examples when drafting.

## Agreed outline: Frontend evolution, part 1: behavior

Agreed with loozo on 2026-10-01: “park and next”. That original agreement parked the outline without authorizing drafting or publication.

**Publication status (2026-10-02):** loozo reviewed the outline and selected “Write the draft”, then explicitly requested “publish, commit and push”. Removed the draft flag from `src/content/blog/frontend-evolution-behavior.md`; the article body is unchanged from the verified draft. Committed only the article as `ba5d24c` — `Add frontend evolution behavior article` — and pushed to `origin/main`. Production build/check, article route, home listing, blog redirect, RSS, and sitemap pass. GitHub Pages deployment `37009593477` succeeded, and the live article, anchors, home listing, RSS, and sitemap were verified at `https://theo-matzavinos.github.io/dump/blog/frontend-evolution-behavior/`. Remaining articles stay parked.

**Technical verification:** Rechecked jQuery's official overview, APIs, and 4.0 upgrade guide against immutable source checkouts: jQuery `dc2b78f92c0e8939c80feb3311abdd535af0b55f`, jquery.com `0726343a888685024f24fec40d9d17de98dd1eb6`, and api.jquery.com `16e469b12ada2cef8d14a8bc8cbcec0263218eb8`. Angular template, signal, and lifecycle behavior was checked against source at `860832591d58f49e5618d2898509f18d7c1cfa50`. Actual article examples pass 59 Chromium cases using jQuery 4.0.0 and Angular 22.2.1, covering both intentionally stale-count examples and the complete task contract: adding, validation, literal title text, duplicate titles, completion/reactivation, filters, counts, empty states, DOM identity, and focus. The Angular component passes strict TypeScript 6.0.3/template compilation. Final checks include desktop/mobile development rendering, all 12 reference URLs, local/cross-article anchors, Astro build/check, and production draft exclusion. Temporary example fixtures and dependencies remain outside the repository; no verification framework or dependency added.

**Working title:** From changing elements to managing application state.

**Reader outcome:** Understand which problems direct DOM code, jQuery-like libraries, and application frameworks solve, and where each puts the complexity.

**Running example:** The same task interface implemented three ways: native JavaScript, jQuery, and Angular. Add completion, filtering, and a remaining-task count to expose synchronization problems, not just compare syntax.

### 1. The browser already provides behavior

- Links navigate; forms submit; controls maintain their own interaction state.
- Server-generated pages can be interactive without a client application framework.
- JavaScript can enhance one interaction without taking ownership of the entire page.
- Misconception: before frameworks, websites were static.

### 2. Direct DOM manipulation: tell the browser what to change

- Find elements, register listeners, create nodes, update text and properties.
- Implement adding and completing a task.
- Explain imperative instructions: create this row, change this count, hide this element.
- Small scripts can be clear and sufficient.
- Misconception: plain JavaScript inevitably becomes spaghetti.

### 3. jQuery: make browser operations easier and more consistent

- Historical context: uneven browser APIs and behavior.
- Selection, DOM manipulation, event handling, Ajax, and plugins through a convenient API.
- Show the same interaction with less repetitive plumbing.
- State ownership, rendering rules, and keeping related elements consistent remain the application's responsibility.
- Distinguish jQuery itself from UI/plugin libraries built around it.
- Misconception: jQuery automatically keeps the UI synchronized with application data.

### 4. More behavior creates a coordination problem

- Completing a task affects the row, remaining count, and filtered list.
- Adding, deleting, and editing introduce more paths that must preserve the same rules.
- Show a forgotten count update or displayed row state disagreeing with data.
- Ask where the source of truth lives: DOM, JavaScript state, or an intentional combination.
- A centralized render function is a valid plain-JavaScript response; a framework is not the only possible next step.
- Misconception: shorter DOM code solves application structure.

### 5. Frameworks describe the relationship between state and view

```text
User event → application state changes
                       ↓
              template/rendering rules
                       ↓
                   DOM updates
```

- Introduce declarative rendering: describe what the UI should show for a given state.
- Demonstrate the task list and count in Angular.
- Components give related behavior and rendering a boundary.
- Framework-managed lifecycles help organize setup and teardown.
- Complexity moves into framework rules, dependencies, tooling, and update semantics; it does not disappear.
- Briefly acknowledge earlier MVC/MVVM approaches without turning this into a framework genealogy.
- Misconception: a framework removes the need to understand the DOM.

### 6. SPAs expand what the client owns

- Distinguish a rendering library/framework from a single-page application architecture.
- Client-side navigation keeps an application alive across route changes.
- That brings ownership of navigation, history, loading/error states, and resource cleanup.
- A framework can enhance one page; using one does not inherently require an SPA.
- Link to `src/content/blog/html-rendering-methods.md` for SSR, hydration, and hybrid arrangements.
- Misconception: framework, SPA, and client-side rendering mean the same thing.

### 7. Compare responsibilities, not winners

For each implementation, ask:

- Where does state live?
- Who updates the DOM?
- Who keeps multiple representations consistent?
- Who owns listeners and cleanup?
- What must a teammate understand to change the feature?

Explain why modern native APIs reduce some historical reasons for jQuery, while existing integrations can still justify it. Likewise, a framework's coordination benefits must justify its costs.

Angular connection: understand the state/template boundary before reaching for selectors and manual DOM writes inside a component.

### Boundaries and closing check

Not a migration guide, benchmark, or “old bad, new good” history. Leave styling approaches to part 2, detailed component composition to its article, and change-detection internals to the existing article.

Closing check: can the reader explain what jQuery simplifies, what a framework takes ownership of, and what additional responsibilities an SPA introduces?

### Technical references for later drafting

- jQuery official overview checked on 2026-10-01: https://jquery.com/.
- Angular binding guide checked on 2026-10-01: https://angular.dev/guide/templates/binding.
- Reverify technical details, historical claims, and runnable examples when drafting.

## Agreed outline: Frontend evolution, part 2: styling

Agreed with loozo on 2026-10-01: “good. park and next”. That original agreement parked the outline without authorizing drafting or publication. This revised outline replaces the neutral comparison proposed earlier: the article builds toward loozo's choice of components + Tailwind, while representing the alternatives fairly rather than treating them as a replacement ladder.

**Draft history (2026-10-02):** loozo reviewed the outline and selected “Write the unpublished draft”. Initially written in `src/content/blog/frontend-evolution-styling.md` with `draft: true`. The article explains the six agreed benefits and honest tradeoffs, includes a reusable Angular task row with its task-board consumer, and uses shared dark/light design values. Subsequent revisions below add neutral narration, data-attribute hooks, and component-style scoping.

**Publication status (2026-10-06):** loozo explicitly requested “publish, commit and push”. Removed only the draft flag; approved article body and all 19 examples remain unchanged. Committed only this article as `ab4273038933db7f9569ac9ff1e1da2d60ca9ed7` — `Add components and Tailwind styling article` — and pushed to `origin/main`. GitHub Pages run `37431090354` completed successfully for that exact commit. Verified live HTTP 200, all 19 rendered code blocks, 30 anchors, home listing, sitemap, and RSS item inclusion. Live: https://theo-matzavinos.github.io/dump/blog/frontend-evolution-styling/. Astro build/check passes with zero diagnostics; the existing internal-helper build warning is unchanged. Planning files remain untracked and the existing `pnpm-lock.yaml` modification is excluded and preserved. Remaining articles stay parked.

**Publication caveat:** RSS item URLs still omit `/dump`, an existing feed-wide issue already proposed in parked work `2026-09-30T18-02-54-688Z--correct-rss-post-urls-for-the-dump-github-pages-base--ef71e156-fbef-42b8-ac72-e613e542222e.md`. RSS includes this article, but its link is affected too. No unrelated feed repair was performed.

**Technical verification:** BEM source checked at `78e5d110a237df0c3841a9ae48d3d760cd970c36`; Bootstrap 5.3.8 at `25aa8cc0b32f0d1a54be575347e6d84b70b1acd7`; Angular Material 22.2.1 guides at `f41e439ffce7d059ab65d5f6983069fbcdc83b8e`; Angular guides at `860832591d58f49e5618d2898509f18d7c1cfa50`; Sass documentation at `fe1ecc3751a1525bc0c6e8cba14527594d431dc8`; and Tailwind CSS 4.3.3 source at `c2b24dd15fed1c59dd521bd86082f520c9f5ad0d`, supplemented by current official Tailwind documentation. Actual article blocks compile with Sass 1.105.1, Angular 22.2.1/TypeScript 6.0.3 strict templates, and Tailwind CLI 4.3.3. Missing the required task input produces expected NG8008. The documented consumer and spacing variant pass 55 Chromium cases covering the task contract, component reuse, classes, CSS spacing, dark/light colors and contrast, focus, Bootstrap/Material modes, and generated Sass output. True 320px checks at 16px and 32px root fonts verify wrapping and usable input width; the larger-text check exposed and corrected a squeezed field by assigning a preferred flex basis. Final checks include desktop/mobile article rendering, all 15 official references, anchors/cross-article links, Astro build/check, and production draft exclusion. Fixtures and dependencies are temporary and outside the repository.

**Voice revision (2026-10-02):** loozo rejected the first-person narrative and explicitly selected “Neutral technical explanation”. The draft now frames mechanisms, benefits, and tradeoffs without author-centered I/we language. Title, opening, headings, and narrative revised; all 15 previously verified code blocks are byte-identical. The original outline below records the earlier framing, not the revised narrative voice. Publication, commit, and push remain unauthorized.

**Data-hook comparison (2026-10-02):** loozo requested data-attribute hooks in the Tailwind section to complete the BEM comparison. Added “Data attributes can provide state and part hooks”: `data-state` parallels a modifier hook, optional `data-slot` parallels a part hook, and `group-data-[state=completed]` conditionally styles descendants with static utility names. The explanation distinguishes own-element variants, ordinary CSS support, optional part names, and native checked semantics. Existing component implementation and all 15 earlier code blocks remain unchanged; the new HTML example brings the total to 16 blocks. Tailwind 4.3.3 compilation and 14 new Chromium checks verify state transitions, colors, ancestor versus own-element matching, optional part hooks, static classes, and unchanged native checkbox state. Current official Tailwind variants documentation and pinned source tests checked. Fresh Astro build/check, all 16 references (including the new external section anchor), internal/cross-article anchors, and production draft exclusion pass. Draft remains unpublished and uncommitted.

**Component-scoping comparison (2026-10-02):** loozo explicitly authorized a concrete explanation of Angular's CSS-Modules-like mechanics. Expanded the component styling section with an independent `TaskTitle` example and illustrative generated HTML/CSS, followed by a BEM/CSS Modules/Angular comparison. Explain marker-based selectors versus mapped class names, shared markers across component instances, host/content attributes, default emulated encapsulation versus native Shadow DOM, and the continued reach of global rules/inheritance. Clarify that Angular already supplies local component styles and scoping; Tailwind supplies utility composition rather than that boundary. Updated the comprehension check. Angular guide and renderer verified at `860832591d58f49e5618d2898509f18d7c1cfa50`; CSS Modules README/local-scope documentation at `c7bf6c02472fdce4dd8e569abc10d2aeb234e1c2`. Strict Angular 22.2.1/TypeScript 6.0.3 compilation and 17 new Chromium cases verify actual component output, authored names, selector transformation, shared/different component markers, host marker, style boundaries, no native shadow root, and global/inherited styles. All 16 prior blocks remain byte-identical; there are now 19 article blocks. Fresh Astro build/check passes with zero diagnostics; all 17 references, local/cross-article anchors, mobile rendering, and production draft exclusion pass. Draft remains unpublished and uncommitted.

**Working title:** Components + Tailwind: benefits and tradeoffs.

**Reader outcome:** Understand the pairing through six benefits explicitly selected by loozo: locality, component-based reuse, less selector management, consistent design values, visual control, and faster iteration.

**Running example:** The task interface from part 1. Follow ordinary changes: add a completed state, adjust spacing, reuse a row, and introduce dark mode.

### 1. Start with the work we actually do

- Build an interface, change it, reuse parts, and maintain consistency.
- Judge approaches by how those tasks work, not by stylesheet size or fashionable syntax.

### 2. What handwritten CSS, conventions, and preprocessors solve

- Handwritten CSS gives direct control.
- BEM makes ownership and variants explicit.
- Sass helps with repetitive authoring and shared configuration.
- Show their benefits, then the remaining work: naming presentation classes, following selectors between files, and maintaining relationships between markup and rules.
- Point: these approaches are useful; they leave coordination work that loozo prefers to avoid.

### 3. What Bootstrap and Material buy, and what customization costs

- Ready-made controls, consistency, and established design decisions.
- Variables and theming APIs provide substantial customization.
- Explain the friction when desired presentation diverges from the library's assumptions.
- Distinguish using supported configuration from fighting internal selectors.
- Point: loozo prefers control over presentation rather than adopting a complete visual system and then reshaping it.

### 4. Components become the unit of reuse

- A task row owns its markup, behavior, and presentation.
- Reuse the interface through a component, not merely a collection of shared CSS rules.
- Keep a little repeated styling until a meaningful reusable UI concept emerges.
- Components alone do not require Tailwind; explain what the pairing adds.
- Point: reuse follows product concepts rather than premature styling abstractions.

### 5. Tailwind keeps presentation where it is composed

- Read and change layout, spacing, colors, and states alongside the markup.
- Avoid inventing a semantic class for every styling combination.
- Demonstrate a small change without navigating a chain of selectors.
- Explain utilities through their underlying CSS, not as magic vocabulary.
- Point: less naming and indirection makes implementation and iteration more direct.

### 6. Local composition still uses shared design decisions

- Shared spacing, color, and typography values constrain choices.
- Components carry reusable compositions and variants.
- Demonstrate consistent dark-mode and state styling.
- Utilities do not automatically produce a coherent design; the shared decisions still matter.
- Point: local styling does not have to mean arbitrary styling.

### 7. State the tradeoff honestly

- Templates become denser.
- Tailwind adds vocabulary and build tooling.
- CSS knowledge is still needed.
- Tailwind does not provide control behavior or accessibility.
- Ordinary component CSS remains useful when it expresses something more clearly.

Conclusion: loozo accepts those costs because locality, component reuse, fewer selector relationships, shared design constraints, and visual freedom fit how he wants to work.

### Boundaries

Explain loozo's choice, not claim every project should make it. Component CSS can also be local, and Bootstrap/Material can also be used inside components. Naming, preprocessing, scoping, UI libraries, and utility composition solve different concerns and can overlap. Do not make straw-man comparisons or turn this into a framework ranking or exhaustive methodology survey. Specific named conventions beyond BEM remain unselected.

### Technical references for later drafting

- Official BEM methodology source checked at commit `78e5d110a237df0c3841a9ae48d3d760cd970c36`: https://github.com/bem/bem-method.
- Bootstrap customization overview: https://getbootstrap.com/docs/5.3/customize/overview/.
- Angular Material theming: https://material.angular.dev/guide/theming.
- Angular component styling: https://angular.dev/guide/components/styling.
- Tailwind utility styling: https://tailwindcss.com/docs/styling-with-utility-classes.
- These references were inspected during the outline discussion on 2026-10-01. Reverify technical details and runnable examples when drafting.

## Agreed outline: Angular component composition

Agreed with loozo on 2026-10-01: “park and next”. That original agreement saved the outline for later drafting; it did not authorize drafting or publication.

**Draft status (2026-10-06):** loozo authorized “Write the unpublished draft” and explicitly requested a litmus for extracting components. Written in `src/content/blog/angular-component-composition.md` with `draft: true`. During review, loozo requested the linked-signal revision recorded below. Publication, commit, and push are not authorized.

**Agreed lifetime:** loozo selected one editor separate from the filtered list. The page owns edit selection, so filtering preserves unfinished text. Save, Cancel, or deleting the selected task destroys the editor; a later edit creates a fresh instance and draft. Row-local Details state has the row's shorter rendered lifetime.

**Draft contents:** Seven agreed sections plus the extraction litmus (named responsibility, cohesive parts, understandable consumer contract, and reduced coordination), ownership diagram, complete task-page/row/editor/section example, save trace, and comprehension answers. Neutral technical narration; no generic component framework or detailed forms/accessibility/change-detection detour.

**Initial draft verification:** Rechecked Angular inputs, outputs, projection, lifecycle, queries, DOM APIs, tracked control flow, and dependency-injection scope at source commit `7d96a37af4f7b7dd9dc9a2b9b90cc043c7da2a31`. Extracted all 10 actual fenced blocks; Angular 22.2.1, TypeScript 6.0.3, and strict templates compile the complete consumer. Missing the required task input produces `NG8008`; setting the readonly input signal and emitting a string on the boolean output correctly fail TypeScript, while assigning to the contained task's title compiles. Tailwind 4.3.3 compiles the shared styling setup. All 53 Chromium contract checks pass, including row identity/lifetime, filtered editor persistence, save/cancel, input replacement, save while hidden, completion-driven row destruction with an unfinished draft, deletion while hidden, projected bindings, and focus. Actual keyboard Enter add/save and Tab/Space checkbox behavior pass. True 320px layouts pass at 16px dark and 32px light, including a long unbroken title and an open editor, without page overflow or offscreen controls. Astro check/build, desktop/mobile article rendering, all eight official references, local links/anchors, exact rendered code (apart from the renderer's final fence newline), and production draft exclusion pass. The existing Astro unused-import build warning is unchanged. Verification artifacts are outside the repository in `/tmp/dump-composition-article-_s633nas`; article SHA-256 is `a870eaa26dc5fa91109a7131b9d5b85acf1c0157ed24d06bf0952fb7fca938c3`.

**Initial targeted review:** Fresh filesystem-read-only inspection found no material article/consumer defect in the draft-lifetime contract. It identified one temporary harness assertion that ran before the relevant row output; that evidence defect was accepted and corrected, the combined hidden-row cases were added, and all 53 checks passed. A fresh capture/recheck confirmed the correction and current evidence. Main-agent current-source/artifact review and freshness checks also passed; this does not substitute for loozo's article review or authorize delivery beyond an unpublished working-tree draft.

**Linked-signal revision (2026-10-06):** At loozo's explicit request, replaced the editor's `signal` plus `ngOnInit` with `linkedSignal<Task, string>`. Its computation retains `previous.value` for the same task ID and starts from the supplied title for a different ID. Removed the `OnInit` interface/import and hook, revised the explanation and save trace, and added the official linked-signal reference. Eight of ten fenced blocks remain byte-identical; only the editor and trace changed. The article explains that the naive linked signal can reset unfinished text on task-object replacement, and that registration defers required-input reading until the draft is read. Also recorded loozo's durable preference in `~/AGENTS.md`: avoid method-based lifecycle hooks when signal- or function-based Angular APIs express the behavior. That eligible file was staged with yadm; no commit or push was made.

**Revision verification/review:** Recompiled all actual examples with Angular 22.2.1/TypeScript 6.0.3 strict templates and Tailwind 4.3.3. All 53 prior consumer cases plus six new public `createComponent`/`setInput` checks of the actual extracted editor pass (59 total): initial value without a hook, same-ID completion/title replacements retaining a draft, a different ID resetting the same instance, later local writes, and destruction. Fresh Astro check/build, all nine official references, local links/anchors, exact rendered code, and production draft exclusion pass. True 320px/light/32px editor layout and native Enter Save pass with no browser errors. Fresh filesystem-read-only inspection of this revision found no material defect; main actual-current-result review and freshness checks passed. Linked-signal revision SHA-256: `11275ee5f14bedcc7191be7ee14ed1bc8ce33bfd8807f6264cbbc548efb36782`. Linked-signal revision artifacts: `/tmp/dump-composition-linked-signal-vch0cqxw`. Initial-draft receipts above remain historical, not approval of this revision.

**Inline-template presentation note (2026-10-06):** At loozo's request, added a disclaimer beside the complete page example: the class/template split is for article readability, while the frontend team uses inline Angular templates in the component's `template` property. The run instructions now explicitly describe running the example as presented, not changing that convention. All ten fenced blocks are byte-identical to the linked-signal revision; no example or map/filter/self-closing refactor was made. Recorded the team-oriented convention and article-presentation exception in `~/AGENTS.md`, staged with yadm only.

**Note verification:** Native Markdown formatting and changed-JS/TS helper (empty target set), Astro check/build, fresh rendered disclaimer/exact code/anchors, and production draft exclusion pass. No runtime suite rerun: all example bytes remain identical to the verified 59-case linked-signal revision. Main reviewed the exact prose/global-instruction changes and freshness; unrelated project work, HEAD and index are preserved. Template-note revision SHA-256: `3d4d0d33a2a1a7a53dac5a590b015bb0cd459108aecce363590ce2e2f51037ff`. Note artifacts: `/tmp/dump-composition-template-note-dnr9ya9j`. The article remains unpublished, with no commit or push authorization.

**Requested simplifications (2026-10-06):** Corrected the missed review requests: empty Angular-template `task-row`, `task-editor`, and `ng-content` usages are self-closing; `setDone` and `renameTask` use one `.map()` each with immutable matching-record replacements; `removeTask` uses `.filter()`. Projection containers with content remain paired, as does the native browser-parsed `<task-page></task-page>` host. Removed the redundant internal-team convention sentences, retaining only the short class/template split-for-readability note. Tightened the prior `~/AGENTS.md` instruction so an article explains its presentation choice without reciting internal team conventions; staged with yadm only. Four of ten code fences changed; six, including the linked-signal editor, remain unchanged.

**Simplification verification/review:** Extracted and strictly compiled the actual revised examples with Angular 22.2.1/TypeScript 6.0.3, built Tailwind 4.3.3, and reran all 59 Chromium contracts successfully. Additional public-method checks of the actual AOT-compiled `TaskPage` with frozen records/arrays verify no input mutation, stable unaffected identity, preserved current completion during rename, and deletion. Astro check/build, nine official references, local anchors/links, exact rendered code, and production draft exclusion pass. Fresh filesystem-read-only collection/template boundary inspection and main actual-current-result review found no material issue. Existing build warning unchanged; no project commit/publication/push. Current article SHA-256: `1ad5f5f3a24205b5a4fc5522153df1adb9d7914c8d312662bcade74dec08632a`. Current artifacts: `/tmp/dump-composition-refinements-xj94bi3q`. Previous receipts above describe their respective historical revisions.

**Working title:** Building components with clear ownership.

**Reader outcome:** Decide where state belongs, design understandable inputs and outputs, and use content projection without building a configuration-heavy component.

**Running example:** Split the task interface into a task page, task rows, and a task editor. Introduce projection through a small section with caller-supplied heading/actions.

### 1. A component boundary should explain a responsibility

- Start with the working interface in one component.
- Extract a task row because its presentation and interactions belong together.
- Extract the editor because editing has its own behavior and lifetime.
- Reuse is one reason to extract, not the only reason.
- Avoid turning every element into a component or every component into a generic library primitive.
- Misconception: smaller templates automatically mean better composition.

### 2. Give each piece of state an owner

- The task page owns the canonical task collection.
- A row can own local presentation state, such as expanded details.
- An editor owns an intentional draft, not another competing canonical task.
- Place shared state where its consumers and required lifetime justify it.
- Derive counts and filtered views rather than keeping synchronized copies.
- Misconception: every component receiving data should keep its own writable copy.

### 3. Inputs describe what a component needs

- Introduce typed `input()` and `input.required()`.
- Distinguish required data from optional configuration with meaningful defaults.
- Give the row a task, not the entire parent instance.
- Treat incoming data according to its ownership contract.
- A readonly input signal does not freeze the object it contains.
- Misconception: passing an object transfers ownership or creates a copy.

### 4. Outputs communicate across the boundary

- Introduce typed `output()` and template listeners.
- Report a changed value or a meaningful interaction, such as requesting deletion.
- The owning feature decides what happens to canonical state.
- Prefer domain-specific names and payloads over a generic “something changed” event.
- Angular outputs do not bubble like native DOM events.
- Misconception: emitting an output automatically changes the parent’s data.

### 5. Local state needs a deliberate lifetime

- Contrast completing a task immediately with editing a draft and saving or cancelling.
- Show why editing the shared input object makes cancellation ineffective.
- Explain when a draft starts, when it resets, and what saving communicates.
- Initializing from an input once is not the same as staying synchronized with it.
- Keep the example focused on ownership; validation belongs in the forms article.
- Misconception: copying an input once solves synchronization.

### 6. Content projection lets the caller supply composition

- Inputs supply values; projection supplies caller-authored content.
- Use `<ng-content>` for the section’s heading/actions and body.
- Introduce selected placeholders and a default placeholder.
- Projected bindings remain in the declaring component’s context.
- Avoid adding strings, flags, and callback options merely to reconstruct markup the caller could provide directly.
- Explain that hiding a projection placeholder is not lazy creation of its content.
- Misconception: projected content becomes part of the receiving component’s own template context.

### 7. Trace the whole interaction

```text
Task page ── task input ──→ Task row
    ↑                          │
    └──── completion output ───┘
    │
    └── updates owned state → inputs reflect the result
```

- Follow one interaction through the contract.
- Identify who reads, who changes, and who decides.
- Briefly explain when shared state through dependency injection is appropriate; inputs/outputs need not become an endless forwarding chain.
- Review the boundary from its consumer’s template: is its usage understandable?

### Boundaries and closing check

No component framework, inheritance hierarchy, state-management library, RxJS prerequisite, or exhaustive lifecycle/API reference. Leave detailed forms, accessibility, and change detection to their own articles.

Closing check: can the reader identify each state owner, explain the effect of an output, and choose between an input and projected content?

### Technical references for later drafting

- Angular inputs: https://angular.dev/guide/components/inputs.
- Angular outputs: https://angular.dev/guide/components/outputs.
- Angular content projection: https://angular.dev/guide/components/content-projection.
- These current guides were checked on 2026-10-01. Reverify technical details and runnable examples when drafting.

## Agreed outline: Accessibility in practice

Agreed with loozo on 2026-10-01: “good. park”. Saved for later drafting only; no drafting or publication is authorized by that original agreement.

**Draft status (2026-10-06):** After article 6's publication, loozo selected “Write the unpublished draft” and requested “continue”. Written in `src/content/blog/accessibility-in-practice.md` with `draft: true`. Seven agreed sections, complete inline-template Angular task page/editor, native modal dialog, focus trace, validation/status feedback, keyboard walkthrough, and comprehension answers. The article explicitly distinguishes this modal editor from article 6's non-modal editor. No UI library, site dependency, commit, publication, or push.

**Technical verification:** Angular source `7d96a37af4f7b7dd9dc9a2b9b90cc043c7da2a31`, WHATWG HTML `ba3400bb4f3d86477a5c8cfc07ff91fc0caaf21c`, WAI-ARIA APG `0f765e4dc33e966026114ac12a8380db1de3b787`, ARIA `a4af4eb449462c00f673f264956ef9c63f0e9e06`, and WCAG `23bad5904949904275a08f1c6e395b78a02aa6f3` checked. Actual examples strictly compile with Angular 22.2.1/TypeScript 6.0.3 and Tailwind 4.3.3. Chromium 152 passes 84 interaction/AX/layout checks, including real Tab/Shift+Tab/Enter/Space/Escape, named modal/inert background, Save/Cancel/selected deletion, filtered completion, invalid fields/descriptions, polite atomic status properties, and true 320px dark/16px and light/32px layouts with long titles. The independent native label fragment passes five checks. Four axe-core 4.14.0 runs find no detectable WCAG-tagged violations; this is not conformance proof. Screen-reader speech, other browser combinations, real-device touch, and actual browser zoom are not tested. Article states its verification boundary. Astro check/build, desktop/mobile article rendering, all 12 references and external section anchors, local links/19 anchors, exact six rendered fences, and production draft exclusion pass. Existing build warning unchanged.

**Review and provenance:** Fresh filesystem-read-only inspection of dialog close/output/destruction timing and focus found no material issue; main reviewed the actual complete current article, assertions, evidence, and source freshness. Reviewer inspected captured results, not independently rerun tests. Final prose-only corrections fix a cross-article anchor and define top layer/WCAG/in-memory lifetime; all six example fences remain unchanged from the verified runtime revision. Final article SHA-256: `ff7caf4cdfd2368055fd71ee8eb4de7d64599b675ec602cf296953d9dec38899`; runtime revision: `642e9b0767b44d5f3fcf819e10e8ee44f462c3ad8e541c8c7b46811f23739d9a`. Artifacts and exported review: `/tmp/dump-accessibility-article-9zdygcfk`. Temporary esbuild verification imports the Angular compiler for unlinked partial library dependencies; article components themselves are AOT-compiled. An initial fixture-only missing-compiler failure and a verifier working-directory error were corrected. Invalid stitched modal screenshots were replaced with viewport captures. Unrelated lockfile/article-series bytes, HEAD, and empty index preserved; remaining articles stay parked.

**Names/descriptions and validation-feedback revision (2026-10-06):** At loozo's explicit request, added a side-by-side comparison: `aria-label` supplies a literal name, `aria-labelledby` supplies a name from referenced text, and `aria-describedby` supplies a separate description. A small dialog excerpt shows the computed name/description distinction. The repeated-action paragraph now points directly to the existing Angular `aria-label` binding. Expanded error guidance: include the validation message element's ID alongside help-text IDs in the field's `aria-describedby`; `aria-invalid` alone does not explain the failure. Added an independent failed-validation HTML snapshot, retained-message versus conditional-message guidance, and the distinction between description association and live notification. Added W3C ARIA21 as a source.

**Revision verification:** All six original fences—including every complete Angular example—remain byte-identical; two illustrative HTML fences bring the total to eight. Nineteen fresh Chromium accessibility-tree checks of the actual new fences verify referenced versus literal names, separate descriptions, help-plus-error text, invalid state, label activation, omission of unreferenced visible errors, updated/cleared message text, and independent polite-live properties. Original task/Angular runtime suites were not rerun because their example bytes are unchanged; those receipts remain historical, not a claim of fresh execution. Fresh Astro check/build, desktop/mobile changed-section rendering, 13 references/external fragments, 20 anchors/local links, all eight exact rendered fences, and production draft exclusion pass. Main actual-change review and read-only source freshness pass. Screen-reader speech remains untested. Current article SHA-256: `41ecf5ee8848ab0fcde3a5f920d989c0c9a44c988cbf6e9071a48d009c4ccdda`; revision artifacts: `/tmp/dump-accessibility-feedback-pstze0ub`. No commit, publication, push, dependency change, or unrelated source repair.

**Working title:** Making the whole interaction accessible.

**Reader outcome:** Build interfaces people can understand and operate without depending on a mouse, visual positioning, or color alone.

**Running example:** Add, complete, edit, and delete tasks. Open the editor as a dialog, then follow what happens to focus and feedback throughout the interaction.

### 1. The interface has more than one representation

- Contrast the visual interface, DOM structure, and accessibility tree.
- Introduce accessible role, name, and state.
- Explain how assistive technology uses that information; a screen reader is not simply reading every HTML tag aloud.
- Start with a concrete failure: an icon-only action that looks obvious but has no useful name.
- Misconception: if it looks understandable, it is understandable to everyone.

### 2. Native semantics provide behavior and meaning

- Use buttons for actions, links for navigation, and checkboxes for completion.
- Associate visible labels with controls.
- Give repeated edit/delete actions enough context to distinguish their targets.
- Use headings and meaningful document structure.
- ARIA supplements semantics; adding a role does not implement keyboard behavior.
- Keep decorative icons from becoming redundant announcements.
- Misconception: adding `role="button"` makes a `<div>` equivalent to a button.

### 3. Keyboard operation is an interaction contract

- Walk through Tab, Shift+Tab, and native control activation.
- Keep focus order meaningful and consistent with the interface.
- Explain `tabindex="0"` versus `tabindex="-1"`; avoid positive values as an ordering fix.
- Make focus visibly identifiable.
- Do not require hover to discover or operate an action.
- Custom widgets need their expected keyboard patterns, not arbitrary key handlers.
- Misconception: being focusable means being keyboard-accessible.

### 4. Focus must survive changes to the interface

- Opening the editor moves focus to an appropriate place inside it.
- A modal keeps interaction within itself while the background is inert.
- Provide keyboard dismissal and a visible close/cancel action.
- Closing usually returns focus to the opener; choose a logical alternative if it no longer exists.
- Deleting or filtering away the focused task needs an intentional destination.
- Prefer native controls or established accessible primitives over inventing dialog infrastructure.
- Misconception: focus will always take care of itself when Angular updates the DOM.

### 5. State and feedback must be perceivable

- Expose completion and expanded/collapsed state through appropriate native semantics or ARIA.
- Associate instructions and errors with their controls.
- Explain status feedback such as “Task saved” or a result count without stealing focus.
- Introduce live-region/status semantics and distinguish ordinary updates from urgent alerts.
- Avoid announcing every incidental DOM change.
- Misconception: displaying a message means everyone will notice it.

### 6. Visual styling still carries accessibility responsibilities

- Preserve readable text and visible focus in light and dark modes.
- Do not communicate completion or errors through color alone.
- Test zoom, text enlargement, narrow layouts, and long labels.
- Keep controls comfortably operable; avoid tiny icon targets.
- Explain why hiding an outline or clipping content can remove essential information.
- Misconception: accessibility is only about screen readers.

### 7. Verify the complete task, not isolated attributes

- Perform the whole workflow using only a keyboard.
- Inspect computed accessible names, roles, and states.
- Try a screen reader to check context, announcements, and focus transitions.
- Use automated checks for detectable problems, not as proof of accessibility.
- In Angular, test rendered behavior across component creation, updates, and destruction.
- With components + Tailwind, reuse includes semantics, keyboard behavior, and focus styling, not appearance alone.

### Boundaries and closing check

Not a complete WCAG course, legal-compliance claim, screen-reader manual, or custom-widget library. Keep validation mechanics for the forms article.

Closing check: can someone complete the task, understand the result, and continue from a sensible focus position without using a mouse?

### Technical references for later drafting

- W3C ARIA Authoring Practices source checked at commit `0f765e4dc33e966026114ac12a8380db1de3b787`: https://github.com/w3c/aria-practices. Reviewed modal-dialog interaction/focus, accessible names and descriptions, and keyboard-interface guidance.
- W3C WCAG source checked at commit `71c891a49f50f58766597a8980f6b2d2eedd5679`: https://github.com/w3c/wcag. Reviewed status-message and visible-focus guidance.
- Sources were inspected on 2026-10-01. Reverify technical details and runnable examples when drafting; inspect actual behavior with relevant browser/assistive-technology combinations.

## Agreed outline: Forms and validation

Agreed with loozo on 2026-10-01: “park and next”. loozo selected fundamentals → Signal Forms and explicitly added a mention of Standard Schema and Zod. Saved for later drafting only; no drafting or publication is authorized.

**Draft status (2026-10-06):** loozo subsequently selected “Write the unpublished draft” for article 8. Written in `src/content/blog/forms-and-validation.md`, with `draft: true`, and left uncommitted. No publication, commit, or push is authorized. The original outline-only agreement above remains historical context.

**Verification receipt:** Current article SHA-256 `268b1ef1b5a3a0afdf7c6d1fa5a83b5d6bee2a12805cc4971f2158d5b23e427a`. Actual post-format examples passed strict Angular 22.2.1/TypeScript 6.0.3 compilation with Zod 4.6.5 and Tailwind 4.3.3; 32 fresh Chromium checks cover draft/accepted ownership, field history, validation and associations, save/rejection/network retry, reset/focus, duplicate prevention, and true 320px dark/16px and light/32px layouts. Three axe-core 4.14.0 states had no detectable violations. Parent verified all 12 exact rendered fences, 22 anchors/local links, 11 references, Astro check/build, and production route/listing/RSS/sitemap exclusion. Main actual-result review and fresh filesystem-read-only inspection of async submission/read-only/error/reset/focus found no material issue at the one-task, permanent-inline-editor scope. Inspector reviewed captured evidence and source; it did not independently execute tests. Screen-reader speech, other browsers, actual browser zoom, real-device touch, backend/persistence, and asynchronous-validator behavior remain untested. Verification artifacts are outside the repository in `/tmp/dump-forms-article-6yx9ng1h`.

**Working title:** A form is more than its values.

**Reader outcome:** Understand how input, draft data, validation, interaction history, and submission fit together, then express that model with Angular Signal Forms.

**Running example:** Extend the task editor with a required title and optional description. Save can succeed, return a validation error, or fail to reach the server.

### 1. Start with three small mysteries

- Why is an empty field invalid before the user touches it, but showing an error immediately feels wrong?
- Why can a valid form still fail to save?
- Why does changing a value back not necessarily make the form pristine?

### 2. Separate the control, the draft, and the saved data

- An HTML input is an interface for editing a value, not the entire form model.
- Keep the editable draft separate from the saved task.
- Explain how edits reach the draft and when the application commits it.
- Cancel discards the draft; save does not mean every keystroke already changed the task.
- Connect to the earlier state-ownership article.

### 3. A form tracks several independent things

Introduce each through an interaction:

| Concern            | Question                                 |
| ------------------ | ---------------------------------------- |
| Value              | What is entered now?                     |
| Validation         | Does it satisfy the rules?               |
| Touched            | Has the user visited and left the field? |
| Dirty              | Has the user edited it?                  |
| Pending validation | Are we still checking it?                |
| Submission         | Are we saving, and what happened?        |

- Interaction flags can also be changed programmatically.
- Dirty tracks editing history, not necessarily a difference from the original value.
- Not yet valid and known invalid need not mean the same thing when validation is pending.

### 4. Validation describes rules, not when to show messages

- Begin with native HTML constraints such as `required`.
- Explain what application validation adds: custom rules and relationships between fields.
- Distinguish invalid data from the decision to display feedback.
- Show errors after leaving a field or attempting submission; update them as the user corrects the value.
- Explain why custom validation often disables native browser validation and takes responsibility for replacing its feedback.

### 5. Schemas: describe the rules once

- Why schemas exist: collect the expected shape and validation rules instead of scattering checks across handlers.
- Zod: a concrete schema library; show a small task schema with a required, nonblank title.
- Standard Schema: a shared interface that lets tools consume schemas from different libraries, not another validation library.
- Angular connection: Signal Forms supports compatible schemas through `validateStandardSchema()`, including Zod.
- Honest boundary: sharing a schema can reduce duplicated rules, but the server must still validate independently; not every server rule belongs in the browser.
- Keep this to one example, not a Zod tutorial.

### 6. Client and server validation have different jobs

- Client checks provide immediate guidance.
- The server validates independently because client checks can be bypassed and server state can change.
- Passing client validation does not guarantee acceptance.
- Distinguish a field rejection from a network failure; they need different messages.
- Preserve the draft when saving fails.

### 7. Submission is a workflow

```text
Attempt save
  → reveal relevant errors
  → check validation
  → capture the data being submitted
  → save
  → success or actionable failure
```

- Handle form submission, including keyboard submission, not just button clicks.
- Prevent duplicate saves while a request is running.
- Clear or replace the draft only after success.
- Do not make a disabled button the only explanation of what is wrong.

### 8. Map the model to Angular Signal Forms

- A writable signal holds the draft.
- `form()` builds a field tree around that model; it does not create an independent copy.
- `FormField` connects native controls to fields.
- Validation rules produce errors; field-state signals let the template decide what to display.
- Use the submission facilities to connect the save workflow.
- Briefly acknowledge reactive and template-driven forms without turning this into a three-way tutorial.

### 9. Make correction accessible

- Labels, instructions, and associated error messages.
- Do not communicate errors through color alone.
- After an unsuccessful submit, help the user locate and correct errors.
- Make saving, success, and failure understandable without unexpectedly moving focus.
- Link to the accessibility article rather than repeat it.

### Boundaries and closing check

Leave out custom control APIs, dynamic form builders, complex async validators, RxJS, and backend implementation.

Closing check: can the reader explain why a field can be invalid but show no error, dirty but unchanged, or valid while its save fails?

### Technical references for later drafting

- Angular source checked at commit `3f9191166936166085320652eef1a562504aa3e4`: https://github.com/angular/angular. The core `form()` API is marked `@publicApi 22.0`; check availability and status against the version targeted when drafting.
- Angular Signal Forms overview: https://angular.dev/guide/forms/signals/overview.
- Angular field-state guide: https://angular.dev/guide/forms/signals/field-state-management.
- Angular submission guide: https://angular.dev/guide/forms/signals/form-submission.
- Angular validation guide, including documented Standard Schema/Zod integration: https://angular.dev/guide/forms/signals/validation#integration-with-schema-validation-libraries.
- Standard Schema: https://standardschema.dev/. Zod: https://zod.dev/. Inspect their current documentation and reverify runnable examples during drafting; their integration was verified here through Angular's official guide.
- Sources were inspected on 2026-10-01. Reverify APIs, validation behavior, and submission defaults when drafting; no RxJS prerequisite.

## Agreed outline: From API responses to UI models

Agreed with loozo on 2026-10-01: “park and next”, after reviewing the revised full outline. loozo explicitly requested comparing domain models, DTOs, and UI view models, then clarified the persistence → backend application → wire DTO → frontend model path and that the shapes need not be the same. Saved for later drafting only; no drafting or publication is authorized.

**Draft status (2026-10-06):** loozo subsequently selected “Write the unpublished draft” for article 9. Written in `src/content/blog/api-responses-to-ui-models.md`, with `draft: true`, and left uncommitted. The original outline-only agreement above remains historical context. Publication, commit, and push are not authorized.

**Verification receipt:** Actual fences strictly compiled with Angular 22.2.1 / TypeScript 6.0.3 / Zod 4.6.5; 53 contract checks and 23 Chromium checks passed, including four keyboard regressions for incomplete native date entry, correction, deliberate clearing, and Discard. Main reproduced and verified the correction; fresh read-only inspection found no material issue in the revised consumer. True 320px dark/16px and light/32px layouts, two axe checks without detectable violations, all 15 rendered fences, 15 anchors/local links, 12 references, Astro check/build, and production draft exclusion verified. Backend shapes are illustrations and the exchange is a labelled in-memory simulation. No backend, screen-reader speech, other-browser, actual browser zoom, real-device, or conformance claim. Artifacts: `/tmp/dump-api-models-article-erm2hct7`.

**Working title:** One task, different models: from database rows to the interface.

**Reader outcome:** Distinguish persistence models, domain/application models, DTOs, and UI view models. Understand why their shapes can differ, and where validation and mapping belong.

**Running example:** Follow a task with an assignee, completion state, calendar due date, and creation timestamp from storage to a task row and editor.

### 1. Start with four small mysteries

- Why should changing a database column not necessarily change the API?
- Why does a property declared as `Date` arrive as a string?
- Why does the task editor need different data from the task row?
- Why can a typed response still contain an unexpected value?

### 2. Different models serve different owners

| Model                            | What it represents                        | What shapes it                     |
| -------------------------------- | ----------------------------------------- | ---------------------------------- |
| Persistence model                | Stored data and relationships             | Storage structure, keys, queries   |
| Backend domain/application model | Application concepts and behavior         | Business meaning, rules, use cases |
| DTO                              | Data exchanged for an operation           | Communication contract             |
| Frontend application model       | Concepts the client works with            | Client behavior and state          |
| UI view model                    | Data and state for a particular interface | Presentation and interaction needs |

- Explain domain model, DTO, and view model before using the abbreviations.
- Domain models can express rules and behavior; they do not have to be classes.
- The frontend's model need not reproduce the backend's entire domain.
- A row, editor, and summary can need different view models for the same task.
- These models do not need the same fields, names, nesting, or types.

### 3. Trace one task through the boundaries

```text
Database / persistence model
        ↕ ORM and application mapping
Backend application/domain model
        ↕ request/response mapping
DTOs — serialized across the wire
        ↕ validation and frontend mapping
Frontend application model
        ↓ screen-specific projection
UI view model
```

Show concrete shape changes:

- Storage represents the assignee relationship through a foreign key.
- The backend works with the task and its assignee as application concepts.
- A response DTO includes the assignee information this operation promises.
- The frontend interprets the response into the representation it needs.
- The row derives an assignee label and formatted due-date label.
- The editor holds editable values rather than display labels.

Mapping can select, rename, combine, split, and convert data, not just copy it.

ORM nuance: ORMs map storage into objects. Those objects may still be persistence-shaped entities; an ORM does not automatically design the application's domain model.

### 4. The wire carries representations, not application objects

- Show the actual JSON before declaring TypeScript types.
- JSON carries objects, arrays, strings, numbers, booleans, and null, not class instances or dates.
- Explain serialization and parsing through the example.
- A response DTO and an update-request DTO can differ because reading and changing a task are different operations.
- Misconception: receiving JSON reconstructs the backend's objects and behavior.

### 5. TypeScript describes expectations; validation checks values

- Types help during development; they do not inspect incoming JSON.
- Angular's `http.get<TaskDto>()` declares an expected type but does not verify the response.
- Introduce `unknown` at the external boundary, then validate before use.
- Reuse Zod for one response schema; infer the corresponding TypeScript type.
- Distinguish validation from mapping: checking the contract is not the same as choosing the frontend representation.
- Handle an invalid response explicitly rather than replacing it with plausible defaults.

### 6. Missing, null, and empty have contract meanings

- An absent property, explicit `null`, and `""` are different representations.
- Contrast this task has no assignee with assignee information was not included.
- Let the contract define what each means.
- In an update request, omission and explicitly clearing a value may mean different operations.
- Misconception: optional chaining or `??` resolves the meaning of missing data.

### 7. Dates need meaning before conversion

- Separate an instant, when the task was created, from a calendar date, which day it is due.
- Explain offsets and display time zones using the task.
- Do not blindly convert every date-shaped string into `Date`.
- Preserve calendar-date meaning; interpret instants deliberately.
- Keep interpretation separate from localized display formatting.
- Show how treating a calendar date as an instant can produce the wrong displayed day.

### 8. Give mapping an owner, and follow edits back out

- Backend boundaries own persistence and request/response mappings.
- The frontend API boundary owns response validation and necessary conversion.
- Screen-specific projections own display labels and UI-only state.
- Construct an explicit update DTO from the editor's draft.
- Do not send formatted labels, expanded-row state, or other incidental UI data.
- Use the server's response as the confirmed result rather than assuming it stored the draft unchanged.

Explain the coupling caused by mixing responsibilities:

- Database structure leaks into the public API.
- Transport conventions spread through application logic.
- Display formatting becomes mixed with domain meaning.
- UI state accidentally becomes part of a request.

### 9. Connect the model to Angular without imposing machinery

- Components receive usable application data rather than interpreting transport quirks.
- Signals hold application state; computed values can derive screen-specific representations.
- Keep repeated parsing and conversion out of templates.
- Review each model through its actual consumer.
- Separate responsibilities do not require a separate class or file at every step. Shapes may coincide when needs coincide, but that is a choice, not a requirement.

**Core takeaway:** The database schema does not have to become the API contract, and the API contract does not have to become the frontend's internal model.

### Boundaries and closing check

Leave out ORM configuration, backend architecture prescriptions, generated SDK pipelines, repository patterns, exhaustive Zod APIs, advanced date libraries, caching, and request races. No RxJS prerequisite.

Closing check: can the reader trace one task through the system, explain why each shape exists, and distinguish validation, application mapping, and presentation?

### Technical references for later drafting

- Angular HTTP guide: https://angular.dev/guide/http/making-requests. Verified the explicit warning that request generics assert rather than validate the response type against source commit `3f9191166936166085320652eef1a562504aa3e4` (https://github.com/angular/angular).
- Zod source checked at commit `004d800c9e3cd4c79930f55aa4ad080225b22efd`: https://github.com/colinhacks/zod. Reviewed parsing, failure handling, and schema-derived types in its README. Current documentation: https://zod.dev/basics.
- Sources were inspected on 2026-10-01. Reverify runnable validation/mapping examples when drafting, and check authoritative JSON/date documentation for the date demonstration. No particular ORM or backend architecture has been selected.

## Agreed outline: URLs as application state

Agreed with loozo on 2026-10-01: “park and next”. Saved for later drafting only; no drafting or publication is authorized.

**Draft status (2026-10-07):** loozo subsequently selected “Write the unpublished draft” for article 10. Written in `src/content/blog/urls-as-application-state.md`, with `draft: true`, and left uncommitted. The original outline-only agreement above remains historical context. Commit, push, and publication are not authorized.

**Verification:** Actual final five TypeScript fences and browser host extracted; strict Angular 22.2.1/TypeScript 6.0.3 AOT, templates, injection, official library linking, and Tailwind 4.3.3 passed. All 72 parsing/building/serialization/projection contracts and 74 Chromium Router observation groups passed, including direct entry/reload/copied context, real control/link activation, push/replace and Back/Forward, same-instance parameter removal, unfinished-search lifetime, malformed/repeated input, encoding, and recovery. Review found and corrected native text-input CR/LF sanitization disagreement; LF/CR/CRLF regressions cover field/draft/committed-value agreement and replacement. Clarified Router's initial encoding/order normalization. Main independently reproduced and checked the correction; fresh read-only revised-source inspection found no material issue. True 320px dark/16px and light/32px example layouts, all nine rendered fences, 15 anchors/local links, 14 references, Astro check/build, and production draft exclusion verified. Chromium evidence is not screen-reader speech, touch, actual zoom, cross-browser/production-host proof, or accessibility conformance. No backend, site dependency, commit, push, or publication. Mechanical design scan returned no findings in degraded regex-only mode; it did not evaluate computed contrast or selectors. Full QA/source/review artifacts are retained outside the repository in `/tmp/dump-url-state-article-2245gyd4`.

**Working title:** The URL is part of your application's state.

**Reader outcome:** Decide what belongs in the URL, restore a view from it, and make sharing, refresh, and browser history behave coherently.

**Running example:** Add search, completion filtering, sorting, and pagination to the task list:

```text
/tasks?status=open&q=report&sort=due&page=2
```

### 1. Start with three small mysteries

- Why does refreshing lose the selected filters?
- Why does a copied link open a different view for a teammate?
- Why does Back change the address but leave the controls unchanged?

Introduce the underlying problem: important view state exists only inside the running application.

### 2. The URL identifies more than a page

- Path: what resource or area is being addressed, such as `/tasks` or `/tasks/42`.
- Query parameters: which view of that resource, such as filters, search, sorting, and pagination.
- Fragment: a location within the document, such as a section.
- A URL is a serialized representation that the application interprets.
- A shared link restores view settings, not a frozen copy of the underlying data.

### 3. Decide what belongs where

| State                                                   | Usually belongs                |
| ------------------------------------------------------- | ------------------------------ |
| Selected task, committed search, filters, sorting, page | URL                            |
| Unsaved editor contents, hover, temporary menu state    | Local component state          |
| Task records and saved changes                          | Application/server data        |
| Cross-session preferences                               | Appropriate persistent storage |

- Ask whether copying, bookmarking, refreshing, or returning with Back should restore this state.
- Do not put the entire application state into the URL.
- URLs can appear in history, logs, and copied messages; exclude secrets and sensitive drafts.
- Navigation extras such as history state are not part of the copied URL.

### 4. Treat URL values as external input

- Query values are text representations, not automatically booleans, numbers, or valid enum members.
- Parse supported filters and positive page numbers deliberately.
- Distinguish an absent value from a malformed one.
- Define defaults and an explicit policy for unsupported values.
- Use URL-building tools rather than concatenating raw search text.
- Connect to the previous article: representation → validation → application meaning.

### 5. Give committed view state one owner

```text
User commits a filter change
        ↓
Navigate to the new URL
        ↓
Interpret route state
        ↓
Controls and results reflect it
```

- Treat the URL as the source of truth for the state chosen to live there.
- Derive controls and results from the interpreted state.
- Avoid independently updating a local filter and the URL, then trying to keep both synchronized.
- An uncommitted search draft can remain local; applying it changes the URL.
- Reset pagination when changing a filter makes the old page inappropriate.
- Preserve other parameters intentionally, not blindly merge everything.

### 6. Browser history is an interaction contract

- Explain adding a history entry versus replacing the current one.
- Add entries for meaningful navigable changes.
- Replace when correcting or normalizing the current representation.
- Discuss why adding an entry for every keystroke can make Back frustrating.
- Back and Forward must restore controls and results, not merely the address.
- Changing the URL through client-side navigation does not require downloading a new HTML document.

### 7. Map this to Angular Router

- Use `RouterLink` on actual links for navigation.
- Use router navigation APIs for committed control changes.
- Show `withComponentInputBinding()` with signal inputs as a small, RxJS-free route-state consumer.
- Parse/default those inputs deliberately, including when parameters disappear.
- Explain that route parameters can change while Angular reuses the same component.
- A snapshot is a point-in-time view, not an ongoing subscription to route changes.
- Show `replaceUrl` for replacing the current history entry.

### 8. Verify the complete navigation loop

- Open the URL directly in a new tab.
- Refresh.
- Copy it to another session.
- Change filters, then use Back and Forward.
- Remove parameters and try malformed values.
- Confirm that controls, results, and the address agree.
- Briefly explain why direct SPA links also require the hosting server to serve the application correctly; leave deployment configuration elsewhere.

### Boundaries and closing check

Leave out exhaustive router configuration, matrix parameters, custom URL-codec libraries, guards/resolvers, request races, caching, and RxJS.

Closing check: can the reader explain which state the link promises to restore, who owns it, and what Back should do?

### Technical references for later drafting

- Angular routing guides: https://angular.dev/guide/routing/read-route-state, https://angular.dev/guide/routing/navigate-to-routes, and https://angular.dev/guide/routing/common-router-tasks.
- Angular source checked at commit `3f9191166936166085320652eef1a562504aa3e4`: https://github.com/angular/angular. Reviewed `withComponentInputBinding()` and its handling of unmatched inputs, the default route-reuse strategy, and documented history/navigation behavior.
- Sources were inspected on 2026-10-01. Reverify route-input APIs, URL parsing/building, and runnable history/deep-link examples when drafting. Keep the examples RxJS-free.

## Agreed outline: Browser rendering and performance

Agreed with loozo on 2026-10-01: “park and next”. Saved for later drafting only; no drafting or publication is authorized.

**Draft status (2026-10-07):** loozo subsequently selected “Write the unpublished draft” for article 11. Written in `src/content/blog/browser-rendering-and-performance.md`, with `draft: true`, and left uncommitted. The original outline-only agreement above remains historical context. Commit, push, and publication are not authorized.

**Draft verification:** All nine agreed sections are present, with a complete native task-row comparison, Angular measurement consumer, qualified rendering/frame/layer explanations, answered comprehension prompts, and fresh authoritative references. The final seven fences were extracted and checked; strict Angular 22.2.1/TypeScript 6.0.3 AOT/templates/injection and library linking passed without consumer JIT fallback, and Tailwind 4.3.3 compiled the optional literal utilities. Captured Chromium checks cover identical initial/final every-row geometry and output, five native keyboard/theme/true-320px/16px-or-24px-root/reduced-motion paths, long titles, and the actual Angular event-method/read-phase path. Both fresh-page recordings returned the same 24 expanded heights of 122 CSS px. Their raw renderer-main-thread traces contain 24 versus one Layout and UpdateLayoutTree events inside the named expansion marks, with `offsetHeight` stack attribution; later status layout/painting is explicitly outside that interval. Main independently parsed the raw traces, and fresh filesystem-read-only inspection found no material issue. Main reviewed the actual current article, assertions/source/evidence, and findings. Formatting changed no source bytes; Astro check/build, six exact rendered code blocks, Mermaid source, 24 unique anchors, internal links, external references, desktop/mobile browser diagnostics, and production route/listing/RSS/sitemap draft exclusion passed. Evidence and exported helper results are preserved in `/tmp/dump-rendering-article-tw73ikff`. No physical-display/refresh-rate/hardware-GPU/presentation-time claim, universal speedup, screen-reader speech, actual browser zoom, touch, other-browser, or accessibility-conformance proof; 24px root text is larger text, not zoom. The existing feed-wide `/dump` RSS URL defect remains separately parked. No site dependency/configuration change or subsequent article.

**Working title:** From DOM changes to pixels: what the browser actually does.

**Reader outcome:** Explain style calculation, layout, paint, rasterization, and compositing, and use that model to investigate slow visual updates.

**Running example:** Expand a task row, change its completion styling, animate an editor panel, and measure element sizes.

### 1. Start with three small mysteries

- Why can a small DOM change make an interaction slow?
- Why can reading an element's size trigger work?
- Why can moving something with `transform` cost less than changing its position through layout?

### 2. Application rendering is not browser rendering

- Angular evaluates bindings and updates the DOM.
- The browser turns the resulting document and styles into displayed pixels.
- Finishing a handler or updating a signal does not mean the screen has already changed.
- This work happens whether the HTML came from a server, a build, or client JavaScript.
- Link the existing rendering-methods and change-detection articles rather than repeat them.

### 3. Follow the rendering pipeline

Introduce a simplified diagram, then explain each responsibility:

- Style calculation: determine which CSS values apply.
- Layout: calculate sizes and positions.
- Paint: determine what drawing operations are needed.
- Rasterization: turn drawing instructions into pixels.
- Compositing: combine rendered content and apply supported visual effects for display.

This is a teaching model, not a complete engine architecture. Browsers reuse previous results and can skip unnecessary stages.

### 4. Different changes invalidate different work

Compare changes to the same task row:

- Changing dimensions can require layout and subsequent visual work.
- Changing text color can require repainting without changing geometry.
- Suitable transform or opacity animations can reuse rendered content and update through compositing.
- Changes can affect surrounding elements, not just the element edited.
- CSS animations are not automatically cheap; JavaScript animations are not automatically expensive.
- Misconception: every DOM or CSS change redraws the entire page.

### 5. Layout reads can force pending work

- Start with a style change followed by `offsetHeight` or `getBoundingClientRect()`.
- Explain why the browser may need current layout before answering.
- A measurement is not inherently expensive; the problem is pending work and repeated forced synchronization.
- Show a loop alternating geometry reads and writes: layout thrashing.
- Batch compatible reads and writes while preserving what the code intends to measure.
- If new geometry is genuinely needed, acknowledge the required layout rather than blindly moving the read earlier.

### 6. Frames have deadlines, not unlimited time

- At 60 Hz, display updates are approximately 16.7 ms apart; at 120 Hz, approximately 8.3 ms.
- That interval is not a guaranteed JavaScript budget.
- Explain missed frames and uneven animation through the pipeline.
- Connect slow interactions to both application work and the browser work required to present the result.
- Briefly connect `requestAnimationFrame()` to visual-update timing; it does not make expensive work cheap.
- Link existing event-loop coverage instead of reteaching scheduling.

### 7. Compositing helps, but layers are not free

- Explain why independently rendered content can move without repainting it each frame.
- Distinguish compositing layers from DOM elements and CSS stacking contexts.
- Transform and opacity are useful candidates, not universal guarantees.
- Extra layers consume memory and introduce management/rasterization costs.
- Do not apply `will-change` everywhere or treat GPU accelerated as synonymous with fast.

### 8. Investigate one interaction before optimizing

- Record expanding the task row in browser performance tools.
- Identify JavaScript, style, layout, and paint work.
- Use paint flashing and layer inspection where useful.
- Find repeated forced layouts rather than guessing from source code.
- Change one demonstrated cause and compare equivalent recordings.
- Keep layout work that the interaction genuinely requires.

### 9. Connect the evidence back to Angular

- Separate time spent updating application bindings from time spent rendering the result.
- Keep layout measurements out of repeatedly evaluated template expressions.
- Preserve stable row identity to avoid unnecessary DOM replacement.
- Fewer checks do not automatically mean cheaper layout or paint.
- Tailwind utilities still produce ordinary CSS with ordinary rendering costs.

### Boundaries and closing check

Leave out browser-process internals, GPU programming, exhaustive property-cost lists, a complete Core Web Vitals course, network caching, and another event-loop/change-detection tutorial.

Closing check: can the reader predict which rendering work a change might require, explain a forced layout, and verify the suspected bottleneck in a recording?

### Technical references for later drafting

- MDN source checked at commit `827686870ee416d6f01739a48931618b61f4ce4e`: https://github.com/mdn/content. Reviewed browser rendering and animation/frame-rate guides as conceptual background.
- Chromium RenderingNG architecture: https://developer.chrome.com/docs/chromium/renderingng-architecture. Reviewed pipeline stages, skipped stages, compositor execution, and the paint/display-list versus rasterization distinction.
- web.dev layout guidance: https://web.dev/articles/avoid-large-complex-layouts-and-layout-thrashing. Reviewed pending layout, geometry reads, read/write loops, and profiling evidence.
- Existing overlap checked in `src/content/blog/html-rendering-methods.md`, `src/content/blog/angular-change-detection.md`, and `src/content/blog/javascript-engines-and-runtimes.md`; link rather than repeat those mechanisms.
- Sources were inspected on 2026-10-01. Reverify examples and tooling when drafting. Keep browser-specific implementation details qualified, avoid universal compositor/layer guarantees, and distinguish refresh interval from available JavaScript execution time.

## Agreed outline: Caching static files and requests

Agreed with loozo on 2026-10-01: “lgtm. park and next”. The agreement includes the stale-while-revalidate addition, distinguishing the HTTP directive from the application-data strategy, not a tutorial on the React SWR library. Saved for later drafting only; no drafting or publication is authorized.

**Working title:** Caching is permission to reuse, not proof that nothing changed.

**Reader outcome:** Explain cache keys, freshness, revalidation, and invalidation; distinguish HTTP caching from application-data caching.

**Running example:** Deploy the task application's HTML/JS/CSS, revisit a filtered task list, then save a task and explain which cached results may need updating.

### 1. Start with three small mysteries

- Why does a deployment still show an older interface?
- Why does `no-cache` sometimes produce `304 Not Modified`?
- Why does saving a task leave another view showing old data?

### 2. A cache keeps a reusable answer

Every cache needs answers to four questions:

- Key: which requests or operations can reuse this result?
- Value: what exactly is stored?
- Freshness: when is reuse acceptable?
- Invalidation: what makes the result unsuitable?

Distinguish:

- Browser HTTP caches.
- Shared HTTP caches such as CDNs.
- Application caches holding parsed data.
- Service-worker/Cache API storage, briefly: separately managed, not automatically governed by HTTP cache headers.
- Misconception: the cache is one place that a refresh clears.

### 3. Freshness is a policy, not knowledge of the server

- Fresh means the stored response is reusable under its caching policy, not that the server definitely remains unchanged.
- Stale does not mean deleted or necessarily incorrect.
- Expiration and eviction are different.
- A cache can lose an entry before its freshness period ends.
- Explain `max-age` through a small timeline.

### 4. Read the important HTTP directives correctly

- `max-age`: freshness lifetime.
- `no-cache`: require validation before reuse; storage is still allowed.
- `no-store`: do not store this response; it does not purge previously stored copies.
- `private`: prevent storage by shared HTTP caches.
- `public`: explicitly permit shared caching where applicable.
- `immutable`: the representation is not expected to change during its freshness lifetime.

Personalized responses need deliberate cache policy. Cookies alone do not make a response private.

### 5. Revalidation avoids downloading unchanged content

Walk through:

1. Receive a response and its `ETag`.
2. Reuse it while permitted.
3. Send `If-None-Match` when validation is needed.
4. Receive either `304 Not Modified` or a new response body.

- Briefly introduce `Last-Modified`/`If-Modified-Since`.
- A `304` is a successful reuse path, not missing data.
- Revalidation still involves communication; a fresh cache hit may not.
- Distinguish response headers from request-side cache controls.

### 6. Serve now, refresh in the background

- Return an acceptable cached result immediately.
- Revalidate in the background.
- Make the refreshed result available when it arrives.
- Tradeoff: faster responses in exchange for temporarily showing older data.

Distinguish two uses:

HTTP directive:

```http
Cache-Control: max-age=60, stale-while-revalidate=300
```

The response is fresh for 60 seconds. For the following 300 seconds, a supporting cache may serve it stale while revalidating.

Application-data strategy: show cached tasks immediately, fetch updated tasks, then update application state. Unlike HTTP caching, this can update the already-visible interface.

For the task example, explain:

- When slightly old list data is acceptable.
- Refresh indicators and failures without discarding usable data.
- Why a successful save still needs deliberate cache updates/invalidation; SWR is not a substitute.
- Why this policy does not suit every kind of data.
- Teach the strategy, not the React library named SWR.

### 7. Static assets and HTML need different policies

- Content-hashed JS/CSS URLs identify particular file contents.
- New contents get a new URL; unchanged assets can remain reusable.
- Long freshness plus `immutable` fits genuinely versioned assets.
- The HTML entry point must discover the current asset URLs, so it usually needs a different policy.
- Publishing new files does not automatically invalidate old cached HTML.
- Purging a CDN does not purge every browser cache.
- Keep old assets available when clients may still reference them.
- Misconception: changing a file on the server immediately changes every client's copy.

### 8. Application-data caching introduces another owner

- Define the key from everything affecting the result: filters, sorting, pagination, user/tenant scope where relevant.
- Briefly connect HTTP response variants to `Vary`; URL alone is not always sufficient.
- Distinguish sharing an in-flight request from retaining a completed result.
- Choose a freshness policy appropriate to the data.
- After a save, update or invalidate affected details, lists, and counts, not merely one object.
- Expiration limits stale-data duration; it does not guarantee immediate consistency.
- Clear or isolate user-specific entries when identity changes.
- Avoid accidentally retaining failed requests as successful cached results.
- Give the cache a bounded lifetime rather than an indefinitely growing global map.

### 9. Connect this to Angular without building a caching framework

- Angular HTTP requests can benefit from browser HTTP caching.
- `HttpClient` does not automatically create an application-level result cache.
- Keeping data in a signal does not establish freshness or invalidation rules.
- Show one small, domain-owned task-data cache, not a generic interceptor that caches every GET.
- Leave cache decisions near the consumer and mutation workflows that justify them.
- No RxJS caching recipes or prerequisite.

### 10. Verify which layer answered

- Inspect response headers, transfer sizes, cache indicators, and conditional requests in DevTools.
- Compare cold load, repeat load, revalidation, and a deployment.
- Save a task and revisit affected views.
- Check that different filters and users cannot reuse the wrong result.
- Explain why DevTools' Disable cache does not disable every CDN, service-worker, or application cache.
- Treat hard refresh as a diagnostic action, not the product's invalidation strategy.

### Boundaries and closing check

Leave out CDN-vendor configuration, offline/PWA implementation, cache-library comparisons, distributed-cache algorithms, and exhaustive HTTP directives.

Closing check: can the reader identify the cache owner and key, explain a `304`, and say what should happen after a deployment or task save?

### Technical references for later drafting

- MDN source checked at commit `827686870ee416d6f01739a48931618b61f4ce4e`: https://github.com/mdn/content. Reviewed the full HTTP caching guide, Cache API behavior, and the `stale-while-revalidate` response directive.
- HTTP caching guide: https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Caching.
- Cache-Control reference: https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Cache-Control.
- Cache API reference: https://developer.mozilla.org/en-US/docs/Web/API/Cache. This API does not automatically honor HTTP cache headers or expire entries.
- Angular HTTP guide checked against source commit `3f9191166936166085320652eef1a562504aa3e4`: https://github.com/angular/angular and https://angular.dev/guide/http/making-requests. Distinguish request execution/browser HTTP caching from application-level result retention.
- Sources were inspected on 2026-10-01. Reverify HTTP behavior, deployed CDN/browser policies, and runnable application-cache examples when drafting. Do not assume headers invalidate application caches, CDN purges invalidate browsers, or HTTP SWR refreshes an already-rendered interface.

## Agreed outline: Testing observable behavior

Agreed with loozo on 2026-10-01: “lgtm. park and next”. The agreement includes definitions of unit, component, integration, contract, end-to-end, smoke, regression, and acceptance tests, with scope/boundary distinguished from purpose rather than a mutually exclusive ladder. Saved for later drafting only; no drafting or publication is authorized.

**Working title:** Test what the consumer can observe.

**Reader outcome:** Choose useful test boundaries, exercise public contracts, and write tests that catch regressions without resisting harmless refactoring.

Observable means externally visible behavior, not RxJS.

**Running example:** Edit and save a task, reject an invalid title, preserve the draft after a failed save, and cancel without changing the saved task.

### 1. Start with three small mysteries

- Why does renaming a private method break a test?
- Why can all tests pass when the Save button no longer works?
- Why does a test pass locally but fail intermittently in CI?

Introduce the difference between checking implementation steps and protecting a meaningful contract.

### 2. Start with a consumer and a promise

- For a function: accepted input, returned result, and relevant side effects.
- For a component: inputs, rendered behavior, interactions, and outputs.
- For an API boundary: request contract and interpretation of responses.
- For a workflow: what the user can accomplish and what happens when it fails.
- Describe the expected behavior before choosing testing tools.

Example promise: when saving fails, the editor preserves the entered title and shows an actionable error.

### 3. Test types: what are we testing, and why?

Explain that the names describe different dimensions, not one mutually exclusive ladder.

By scope or boundary:

- Unit: checks a small, cohesive piece of behavior independently, such as parsing task filters. Not necessarily one method or class.
- Component: checks a UI component's rendered behavior and interactions. Depending on what collaborators are included, this can overlap with unit or integration testing.
- Integration: checks that real pieces work together, such as the editor, validation, and task-data boundary.
- Contract: checks the agreement at a boundary, such as request/response shapes. Mocking the expected response alone does not prove the backend honors that agreement.
- End-to-end: exercises a workflow through the assembled system. State explicitly which parts are real or substituted; a browser test with mocked HTTP does not cover the backend.

By purpose:

- Smoke: a small set of checks that the build/deployment is basically usable, such as application opening, main route loading, and an essential operation working.
- Regression: protects behavior against breaking again, often following a discovered bug. Can be unit, integration, or E2E.
- Acceptance: verifies a requirement's agreed outcome. Can overlap with other types and need not be automated.

Briefly acknowledge performance, security, accessibility, and visual-regression testing as additional concerns, not extra rungs on the same ladder.

Make the overlap concrete: a browser test confirming a task can be saved might be an E2E test, part of the smoke suite, and an acceptance check. A focused failed-save draft-preservation test might be a component regression test.

The lesson is choosing useful protection, not collecting one test of every type.

### 4. Choose the smallest boundary that proves the behavior

- Focused function tests: validation, URL parsing, and DTO mapping.
- Component/integration tests: controls, bindings, validation feedback, and collaboration.
- Browser workflow tests: navigation, browser behavior, and important paths through the assembled application.

Explain scope separately from environment: a component test can run in a real browser without becoming an end-to-end test.

Do not force every behavior through every level or prescribe a test-count ratio.

### 5. Exercise the interface, not a shortcut around it

Compare calling the component's save method directly with entering a title and submitting its rendered form. Only the second demonstrates that the interface reaches the behavior.

- Supply inputs through supported public mechanisms.
- Observe outputs through a consumer where useful.
- Prefer roles, accessible names, labels, and explicit test contracts over incidental DOM nesting or CSS classes.
- Public function calls are appropriate when the function itself is the consumer-facing contract.
- Checking a request payload can be meaningful; checking internal helper choreography usually is not.

### 6. Control dependencies without replacing the thing being tested

- Use controlled responses at external boundaries such as HTTP.
- Keep the relevant validation, mapping, and component collaboration real.
- Explain a small fake dependency before introducing mocking vocabulary.
- Distinguish a request-contract test from a test against the real backend.
- Avoid tests where mocks merely repeat the implementation's assumptions.
- Establish expected results independently, not by calling the production logic to calculate the answer.

### 7. Test important alternatives, not every imaginable combination

Use the task editor to cover:

- Successful save.
- Invalid title: feedback and no save request.
- Failed save: error and preserved draft.
- Cancel: saved task unchanged.

Choose cases for their contractual importance or demonstrated regression risk, not to increase test counts.

### 8. Async tests wait for evidence, not elapsed time

- Wait for a response, framework stabilization, or an expected rendered condition.
- Avoid arbitrary sleeps.
- Distinguish the operation starting from the result becoming visible.
- In Angular, changing an input element's value must be accompanied by the relevant event.
- Use supported rendering synchronization rather than forcing updates indiscriminately.
- In browser tests, use awaited, retrying assertions.
- Keep data and state isolated so tests do not depend on execution order.

### 9. Explain what the environment cannot prove

- DOM emulation is useful for many contracts but is not a browser layout engine.
- Use a real browser for behavior depending on actual rendering, focus, or browser integration.
- Finding a button by role does not prove the entire interaction is accessible.
- Passing tests with mocked HTTP does not prove compatibility with the deployed backend.
- Keep those limits explicit rather than adding machinery to every test.

### 10. Judge tests by their future feedback

- A useful test fails when its protected behavior breaks.
- A harmless internal refactor should usually leave it passing.
- Temporarily break the binding or outcome to check that the test detects it.
- Coverage shows execution, not correctness or adequate assertions.
- Keep failure messages and setup understandable.
- Remove or rewrite tests whose maintenance cost outweighs their regression protection.

### Angular connection

Use one small `TestBed` component example, one HTTP-boundary example with `HttpTestingController`, and a short browser workflow using Playwright. Explain what each tool provides without turning the article into setup documentation.

### Boundaries and closing check

Leave out runner migrations, CI infrastructure, exhaustive mocking APIs, snapshot-heavy suites, coverage targets, and RxJS testing.

Closing check: can the reader identify the protected contract, explain what would make the test fail, and state what a passing result does and does not prove?

### Technical references for later drafting

- Angular source checked at commit `3f9191166936166085320652eef1a562504aa3e4`: https://github.com/angular/angular. Reviewed current testing setup, component/DOM testing, input events and stabilization, and HTTP test boundaries.
- Angular testing guides: https://angular.dev/guide/testing/overview, https://angular.dev/guide/testing/components-basics, and https://angular.dev/guide/testing/components-scenarios.
- Angular HTTP testing: https://angular.dev/guide/http/testing.
- Playwright source checked at commit `82db81d9b8b97d439eda601e504d03daab1e9734`: https://github.com/microsoft/playwright. Reviewed user-visible behavior, isolation, user-facing locators, and awaited retrying assertions in `docs/src/best-practices-js.md`. Documentation: https://playwright.dev/docs/best-practices.
- Sources were inspected on 2026-10-01. Reverify runnable examples and version-specific setup when drafting. Test-type terminology varies between teams; define the intended boundaries/purposes explicitly rather than claim a universal taxonomy. No runner migration or additional test infrastructure is authorized.

## Agreed outline: Git behind the scenes

Agreed with loozo on 2026-10-01: “lgtm. park and next”. The full reviewed outline supersedes the earlier working outline while retaining loozo's explicit exclusions and request for mechanical rebase/squash explanations rather than workflow prescriptions. Saved for later drafting only; no drafting or publication is authorized.

**Working title:** Git behind the scenes: objects, snapshots, and moving pointers.

**Reader outcome:** Explain what Git stores and predict how staging, branching, merging, rebasing, squashing, and recovery change repository state.

**Running example:** A tiny task application with two files and two diverging branches. Inspect its objects and history; use a second local repository to demonstrate synchronization without GitHub.

### 1. Start with three small mysteries

- Why can a file contain both staged and unstaged changes?
- Why is creating a branch almost instantaneous?
- Why does rebasing change commit IDs even when the code looks similar?

### 2. Git is local; hosting is another responsibility

- Working files versus Git's repository storage.
- Commits, branches, and history exist without a network connection.
- GitHub and similar services host repositories and add collaboration features.
- A remote is another repository, not the authoritative meaning of Git itself.

### 3. Objects store content and relationships

- Blob: file contents, independently of the filename.
- Tree: names, modes, and references to blobs or other trees.
- Commit: a root tree, parent commits, author/committer metadata, and message.
- Briefly distinguish annotated tag objects from lightweight tags.
- Explain content-addressed object IDs and reuse of unchanged objects.
- Inspect a blob, tree, and commit with `git cat-file`.

Important distinction: Git's logical model is snapshots. Packfiles can still use compression and deltas internally.

### 4. A commit is a snapshot connected to history

- Follow commit → root tree → directories/files.
- Diffs are calculated by comparing snapshots; a commit is not merely a stored patch.
- Parent links form a history graph.
- Two commits can reference the same file snapshot while having different IDs.
- Changing a parent, message, or other commit data creates a different commit object.

### 5. Working tree, index, and commit are separate states

- The working tree is what you are editing.
- The index holds the proposed next tracked snapshot.
- A commit records that prepared snapshot.
- Stage a change, then edit the file again.
- Explain the two useful comparisons: working tree versus index, and index versus committed state.
- Staging is not a permanent connection that follows later edits.

### 6. Branches, tags, and HEAD are references

- A branch names a commit; it is not a copy of the project.
- Committing normally advances the current branch.
- `HEAD` normally identifies the current branch; detached HEAD identifies a commit directly.
- Tags do not advance automatically with new commits, although their references can be explicitly replaced.
- Deleting a branch removes a reference, not necessarily the commits immediately.

Use small diagrams to distinguish stored objects from movable names.

### 7. Merge reconciles histories

- Fast-forward: move a reference when no divergent history needs combining.
- Three-way merge: reconcile both sides using their merge base.
- A normal divergent merge records a resulting snapshot with both histories as parents.
- Explain why Git can combine some changes automatically and needs help with others.
- Resolving a conflict chooses the intended result; removing markers alone does not establish correctness.
- Misconception: merge replays every intervening commit.

### 8. Rebase, cherry-pick, and squash create new history

- Cherry-pick: apply a selected commit's change in another context.
- Rebase: replay selected commits onto another base, then move the branch to the resulting history.
- Show before/after graphs and explain changed parents and commit IDs.
- The original commit objects are not edited in place.
- Replaying changes can produce conflicts even when the original branch worked.
- Squash: combine several changes into one resulting commit.
- Explain the intermediate history lost from the new branch and distinguish interactive squashing from a squash merge.
- Explain why rewriting shared history affects collaborators, without prescribing always merge or always rebase.

### 9. Remotes synchronize objects and references

- Distinguish local branches, remote branches, and local remote-tracking references.
- Fetch: obtain objects and update local knowledge of the remote.
- Pull: fetch, then integrate according to the chosen configuration.
- Push: transfer objects and request reference updates in another repository.
- Demonstrate with two local repositories.
- Fetching does not automatically change the checked-out files.

### 10. Undo depends on which state you want to change

- Restore: restore selected working-tree or index content.
- Reset: change selected repository state; explain soft/mixed/hard through references, index, and working files.
- Revert: record a new commit undoing an earlier change.
- Reflog: local reference-update history that can help locate previous tips.
- Reachability and garbage collection explain why removed references do not immediately erase objects.
- Recovery is not permanent or guaranteed; reflogs expire and do not record every uncommitted file state.

### Boundaries and closing check

No stash internals, linked worktrees, `rerere`, bisect, exhaustive command reference, hosting tutorial, or workflow commandments.

Closing check: can the reader predict which objects are created, which references move, and which working/index states change for each operation?

### Technical references for later drafting

- Source supplied by loozo: `/home/loozo/Downloads/🚨🚨(LIVE) Everything You'll Need to Know About Git🚨🚨.txt`. Previously read in full on 2026-10-01. Use the Primeagen transcript as structural inspiration, not unquestioned technical authority or a command-by-command script.
- Git source checked at commit `a018953688f1b10bddf91bff8747068f5f4746a4`: https://github.com/git/git. Reviewed object/commit/tree/blob explanations, merge and rebase behavior, interactive squash/fixup, and reflog scope/expiration in its documentation. Earlier working notes retain the packfile, merge, reflog, and tag corrections.
- Reference documentation: https://git-scm.com/docs/git-rebase, https://git-scm.com/docs/git-merge, and https://git-scm.com/docs/git-reflog.
- Sources were inspected on 2026-10-01. Reverify all demonstrations in a disposable repository when drafting; do not experiment on the article repository or user work. Object-ID length/algorithm and storage details are implementation/version-dependent, not required assumptions of the model.

## Agreed outline: Docker behind the scenes

Agreed with loozo on 2026-10-01: “lgtm. park. this was the last one, right?” This is the fifteenth and final topic in the original proposed sequence. The reviewed full outline supersedes the earlier selected-topic/suggestion notes while preserving them in the backlog for traceability. Saved for later drafting only; no drafting or publication is authorized.

**Working title:** Docker behind the scenes: images, processes, and their environment.

**Reader outcome:** Explain what an image contains, how containers use it, and how building, caching, networking, storage, and Compose fit together.

**Running example:** A static Angular frontend, a small task API, and a database. Build the frontend with Node, serve its generated files from a separate runtime image, and connect the services through Compose.

### 1. Start with three small mysteries

- Why does a container exit immediately after starting?
- Why can deleting a large file leave the image large?
- Why does `localhost` work from one place but fail from another?

### 2. An image is an artifact; a container runs processes

- Images contain filesystem content and execution configuration.
- A container combines an image with runtime configuration, writable storage, and running processes.
- Several containers can use the same image independently.
- Linux containers share the kernel of their Linux host; they are not individual virtual machines.
- Explain the VM used by Docker Desktop where applicable.
- Isolation does not mean complete independence from the host or perfect security.

### 3. Layers describe filesystem changes

- Image layers contain additions, modifications, and deletions.
- Explain their combined filesystem view and reuse across images.
- Each container gets its own writable layer without modifying the image.
- Deleting a file in a later image layer does not remove its bytes from an earlier layer.
- Not every Dockerfile instruction adds filesystem content; some change image configuration.
- Do not copy secrets into image layers and assume later deletion removes them.

### 4. A Dockerfile describes a build, not container startup

- Follow `FROM`, `WORKDIR`, `COPY`, and `RUN` through a small build.
- Distinguish build-time execution from the default startup command.
- The build context defines which files the builder can access.
- `.dockerignore` excludes unnecessary or inappropriate context files.
- Editing source on the host does not change an already-built image automatically.

### 5. Build caching reuses previous work

- Explain how instructions and relevant inputs determine reuse.
- Compare copying everything before dependency installation with copying dependency manifests first.
- A source change need not repeat an unchanged dependency installation.
- Changes invalidate dependent build work.
- A cached package-install step does not become fresh merely because time passed.
- Distinguish Docker's build cache from package-manager caches and the HTTP/application caches covered earlier.

### 6. Multi-stage builds separate build tools from runtime needs

- Each `FROM` starts a build stage.
- Name the build stage and use `COPY --from=build`.
- Build the static Angular application using Node and its dependencies.
- Copy only the generated files into the serving image.
- Explain why the final image need not include the compiler, source tree, or build dependencies.
- Stages do not automatically accumulate into the final image.
- Qualify the example: server-rendered Angular has different runtime requirements.

### 7. Registries distribute images; tags name versions

- A registry stores and distributes image artifacts.
- Push and pull transfer required content; reusable layers need not be transferred repeatedly.
- Tags are movable names; digests identify particular content.
- `latest` is a tag, not an automatic guarantee of the newest release.
- Pulling or rebuilding an image does not replace an already-running container automatically.

### 8. Container lifetime follows the main process

- Explain create, start, stop, restart, and remove.
- The container stops when its main process exits.
- Contrast running a foreground server with starting a background process and exiting.
- Distinguish build arguments from runtime environment variables.
- Runtime configuration does not rewrite the image.
- Setting environment variables on a static web server does not automatically change configuration already compiled into browser JavaScript.

### 9. Networking depends on where the code runs

- A container's `localhost` normally refers to itself.
- Services on a Compose network can discover one another by service name.
- Distinguish container ports from published host ports.
- `EXPOSE` describes a port; it does not publish it.
- Trace browser → web server → API → database.

Important frontend distinction: Angular JavaScript runs in the user's browser, not inside the container serving its files. Docker service names available to a reverse proxy are not automatically resolvable by that browser.

### 10. Mounts give data a different owner and lifetime

- Bind mount: exposes a path from the Docker host.
- Volume: Docker-managed storage with a lifetime separate from the container.
- Contrast development source sharing with database persistence.
- Stopping a container preserves its writable layer; removing it discards that layer.
- Persistent mounts can survive container replacement, but can still be explicitly deleted.
- Mounting over an image directory can obscure the files already there.
- Bind mounts can modify host files; explain read-only mounts where appropriate.

### 11. Compose describes collaborating services

- Connect service definitions to containers, networks, volumes, and configuration.
- Compose is not one large container or an alternative image format.
- Walk through the frontend/API/database relationships.
- Explain build versus image references and container recreation after changes.
- Startup order is not readiness.
- Introduce health checks and readiness conditions without building a full orchestration tutorial.

### Boundaries and closing check

No Kubernetes, Swarm, exhaustive Dockerfile reference, storage-driver internals, production-hardening course, or deployment pipeline.

Closing check: can the reader explain what survives rebuilding, restarting, and removing a container, and trace which filesystem, process, and network each part uses?

### Technical references for later drafting

- Docker documentation source checked at commit `1cbac586f589fa6a3e8cebede7e3d22623373f34`: https://github.com/docker/docs. Reviewed container/image concepts, layers, Dockerfile instructions, build-cache invalidation, multi-stage builds, mutable tags/digests, bind mounts/volumes, and Compose networking/readiness.
- Multi-stage builds: https://docs.docker.com/build/building/multi-stage/.
- Build-cache invalidation: https://docs.docker.com/build/cache/invalidation/.
- Compose networking: https://docs.docker.com/compose/how-tos/networking/.
- Compose startup/readiness: https://docs.docker.com/compose/how-tos/startup-order/.
- Storage: https://docs.docker.com/engine/storage/bind-mounts/ and https://docs.docker.com/engine/storage/volumes/.
- Sources were inspected on 2026-10-01. Reverify runnable examples against the target Docker/Compose and Angular versions when drafting. Use a disposable example environment, never remove user containers/volumes or publish images as part of outline work. Distinguish static Angular serving from SSR, browser versus container execution, and daemon-host storage from client-local storage.

## Agreed outline: Coding with agents

Agreed with loozo on 2026-10-01: “cool. let's park it”. This is an additional sixteenth article, beyond the original fifteen-topic sequence. The agreement includes the practical workflow framing, tools versus skills versus MCP, provider-neutral source handling, and an explicit disclaimer that the advice is not necessarily future-proof. Saved for later drafting only; no drafting or publication is authorized.

**Working title:** Coding with agents: context, direction, and verification.

**Reader outcome:** Understand what an agent can see, give it a bounded task, and judge its result rather than its confidence.

**Running example:** Ask an agent to fix the task editor losing its draft after a failed save.

**Framing:** Tokens and prompting are foundations for reliable engineering work, not the entire article or a collection of AI tips.

### Opening disclaimer

> This advice is not necessarily future-proof. Models, agent tools, context limits, and effective workflows change quickly. These recommendations reflect current capabilities, not permanent rules. Check current documentation and test what works for your tasks rather than treating particular prompts or workflows as universal recipes.

Distinguish throughout between engineering principles, such as clear scope, explicit contracts, and verification, and current techniques, such as context-management strategies or product-specific settings. Do not present either a particular prompt or a workflow as a universal guarantee.

### 1. A model and an agent are different things

- The model generates responses from supplied context.
- The agent surrounds it with tools, repository access, execution, and a working loop.
- Having access to a repository is not the same as having read or understood it.
- Distinguish training knowledge, current context, and persistent notes.

### 2. Tools, skills, and MCP solve different problems

- Tool: a callable capability with inputs and results, such as reading a file, running tests, or querying an issue tracker.
- Skill: reusable instructions and supporting resources for performing a task. It can include scripts, but is not simply another tool.
- MCP: a protocol through which an agent application discovers and accesses server-provided tools, resources, and prompts. Servers can run locally or remotely.
- They work together rather than replace one another.

Example: a review skill guides the workflow; file-reading and test-running tools perform operations; an MCP server supplies issue-tracker access.

Connect this to context: skill instructions and tool results consume context when included. Adding integrations does not automatically make an agent more capable at the task.

### 3. Tokens and context windows

- Tokens are encoded pieces of content, not necessarily words.
- Instructions, conversation, code, tool results, and generated output consume budget.
- Context capacity and output limits are different.
- Explain their effects on cost and task length without hard-coding provider limits.

### 4. Capacity is not reliable understanding

- A larger window permits more material; it does not guarantee effective use of it.
- Irrelevant output, stale assumptions, and conflicting instructions make work harder.
- Compaction can preserve useful summaries while losing important details.
- Avoid invented rules such as quality collapsing at exactly a particular token count.
- Do not make the categorical claim that longer context always reduces quality.

### 5. Prompt around an engineering contract

- State the problem, expected outcome, constraints, and non-goals.
- Supply relevant evidence and explain how success will be checked.
- Distinguish investigation, proposal, and implementation.
- Compare fix the form with a precise failed-save regression request.
- Prompting is clear task communication, not finding magic wording.

### 6. Manage context deliberately

- Point to relevant files and authoritative documentation.
- Keep decisions and completion criteria explicit.
- Let the agent retrieve focused evidence rather than paste everything.
- Start a fresh task with a useful handoff when appropriate, not simply because the conversation is long.

### 7. Work in small, verifiable steps

- Investigate → propose → implement → verify → review.
- Keep changes bounded and inspectable.
- Stop drift rather than repeatedly adding corrective instructions.
- Do not add elaborate multi-agent machinery to a task one agent can handle.

### 8. Verify the actual result

- Inspect the diff, run meaningful checks, and exercise the interaction.
- Passing tests can still miss a broken requirement.
- Plausible explanations are not evidence.
- The developer remains responsible for the delivered change.

### 9. Give tools deliberate authority

- Editing, running commands, committing, pushing, and deploying are different permissions.
- Protect secrets and treat retrieved material as potentially untrusted.
- Prefer reviewable local changes before external effects.

### Boundaries and source handling

Leave out model rankings, API integration, agent-platform construction, and exhaustive prompt recipes.

Keep the article provider-neutral. Provider documentation can supply primary evidence for that provider's behavior, not universal rules or product endorsements. Cross-check shared concepts across providers and explicitly label model-specific limits, accounting, and compaction behavior during drafting.

### Technical references for later drafting

- Anthropic context-window guide inspected on 2026-10-01: https://platform.claude.com/docs/en/build-with-claude/context-windows. Reviewed context inputs/outputs, tool results, growth, and context-management discussion. Treat exact behavior and limits as Claude-specific; do not generalize them without cross-checking other providers' current documentation.
- Agent Skills source checked at commit `69ef37e9424c0a7ea9dd2293b559e43ec8176379`: https://github.com/agentskills/agentskills. Reviewed `docs/home.mdx` for instruction/resource/script packaging and on-demand loading. Documentation: https://agentskills.io/home.
- MCP source checked at commit `3098fe94caa1b9e0afaaa6d30e040b61d5802471`: https://github.com/modelcontextprotocol/modelcontextprotocol. Reviewed the `2026-07-28` architecture documentation for client/server roles, local/remote transports, and tools/resources/prompts. Documentation: https://modelcontextprotocol.io/docs/learn/architecture.
- Reverify current sources, tokenizer explanations, examples, and product-specific behavior when drafting. No chosen agent product, model, SDK, infrastructure, or multi-agent system is required or authorized by this outline.

## Backend track

Proposed with loozo on 2026-10-19. The sequence in `article-series.md` and the decisions below are agreed. Each article still needs its own agreed outline before drafting.

**Audience:** junior backend developers who know C# and the .NET stack. Same audience and voice rules as the frontend series.

### Agreed decisions

- **Database:** runnable examples use PostgreSQL; add a short note wherever SQL Server or MySQL behave differently.
- **.NET version:** .NET 10, the current LTS release.
- **Endpoint style:** minimal API endpoints in every example, written as one-liners where an article only needs a small endpoint.
- **Data access:** article 5 covers EF Core and writing SQL yourself; article 4 covers parameters and SQL injection.
- **gRPC:** the existing gRPC article stays off the backend reading list.
- **Auth:** examples use Keycloak. Include a checklist of what token validation must check, and cover Keycloak's nested `realm_access.roles` claim mapping.

### Comparison articles

- Articles 7–10 build the same task-board feature both ways and compare them on concrete criteria: files touched per change, whether the OpenAPI spec matches the code, how a new developer finds a feature's code, and test setup.
- Use everyday scenarios such as completing a task and adding a due date.
- Quote primary sources for claims instead of arguing them.
- Give each option a real "when it fits" section. No verdict.
- Use neutral names: layered and sliced, resource-style and action-style.
- Put layered and sliced last.
- Articles 11–18 use one style consistently, with one note linking to the comparison that explains the choice.

### Article 7 notes

- Microsoft's APIs overview (aspnetcore-10.0, checked 2026-10-19): "For new projects, we recommend using Minimal APIs." It lists controller cases: model binding extensibility, advanced validation, application parts or the application model, and OData. https://learn.microsoft.com/en-us/aspnet/core/fundamentals/apis?view=aspnetcore-10.0

### Article 8 notes

- Microsoft's OpenAPI metadata page (aspnetcore-10.0, checked 2026-10-19): "By default, there are no compile-time checks to ensure that the response metadata specified with a `[ProducesResponseType]` attribute is consistent with the actual behavior of the action method." Automatic metadata from `TypedResults` and `Results<...>` is documented for minimal APIs only. https://learn.microsoft.com/en-us/aspnet/core/fundamentals/openapi/include-metadata?view=aspnetcore-10.0
- Frame the article around keeping the spec in sync with the code, with fixes controller users can apply today. Before outlining, verify whether controller actions returning `TypedResults` get automatic metadata, and the current status of Microsoft's API analyzers.
- Cover responses that middleware sends (`401`, `403`, unhandled `500`) declared per route group, and generating the spec at build time so changes show up in review.

### Article 9 notes

- Open on a task-board search (status, tags, assignee, date range) sent as a `GET` with a growing query string.
- Name the misconception "REST doesn't allow `POST` here", then check it against sources: Fielding's "It is okay to use POST" (2009) says his dissertation never mentions CRUD or `POST` and that method definitions "simply don't matter to the REST architectural style"; RFC 9110 §9.3.3 defines `POST` as processing the enclosed data according to the resource's own semantics. https://roy.gbiv.com/untangled/2009/it-is-okay-to-use-post
- Vocabulary section: REST as defined requires hypermedia (Fielding, "REST APIs must be hypertext-driven", 2008). The task board's own API has no links, so the article calls it resource-style. State this as a plain definition. https://roy.gbiv.com/untangled/2008/rest-apis-must-be-hypertext-driven
- `GET` with a JSON body isn't an option: `fetch` throws a `TypeError` for a body on `GET` or `HEAD`, RFC 9110 §9.3.1 gives a `GET` body no defined semantics and warns it may be rejected, and caches key on the URL.
- Conclusion: reads are `GET` with simple query parameters, complex searches are a named `POST` such as `POST /tasks/search`, and changes are named `POST` actions.
- `QUERY` (RFC 10008, June 2026) as a sidebar on where HTTP is heading. Check ASP.NET Core, OpenAPI tooling, proxy, and CDN support before recommending it; cross-origin `QUERY` needs a CORS preflight. https://datatracker.ietf.org/doc/rfc10008/
- The page URL and the API request are separate: the Angular route can keep shareable filters in its URL while the component sends a `POST` search. Link to the URLs article.

### Article 6 notes

- Default isolation levels differ: PostgreSQL uses Read Committed; SQL Server uses Read Committed with locking unless read-committed snapshot is on; MySQL InnoDB uses Repeatable Read. Use an app-managed version column for portable optimistic concurrency. Verify against each engine's documentation when outlining.

### Site change for the backend track

Agreed with loozo on 2026-10-19 as a workable starting point. Ships together with the first backend article's publication, not before. Shipped with backend article 1 in `fb747eb`; see its publication status.

- **Audience field:** add a required `audience: z.array(z.enum(['frontend', 'backend'])).min(1)` to the blog schema in `src/content.config.ts`. Articles for both audiences list both.
- **Audience pages:** generate `/frontend/` and `/backend/` from one `src/pages/[audience].astro` with `getStaticPaths`. Each lists every article whose audience includes that value, newest first. No JavaScript. `/dump/backend/` is the link for onboarding backend developers.
- **Home page:** stays one list, newest first, with `All · Frontend · Backend` links at the top. No groups.
- **Tags:** show tags again as plain text under each description in the lists, reusing the existing `.tag-list` styles. Remove the `frontend` tag from all articles, since `audience` replaces it.
- **gRPC:** keeps its existing special case at the end of the home list.
- **Initial classification:** both audiences for HTTP from TCP to fetch, One task different models, caching, Git, Docker, and coding with agents. Frontend only for everything else, including gRPC and testing observable behavior (Angular examples) until backend article 18 exists.
- Considered and left out for now: grouping the home page by series (articles can belong to both audiences), per-tag pages, a client-side filter, and an `order` field for reading order.

## Agreed outline: What happens when a request reaches ASP.NET Core

Backend track, article 1. Agreed with loozo on 2026-10-19: "outline lgtm", after adding a short explainer on filters at loozo's request. Saved for later drafting only; no drafting or publication is authorized.

**Draft status (2026-10-19):** loozo asked for "draft and next outline". Written in `src/content/blog/aspnet-core-request-pipeline.md` with `draft: true` and left uncommitted. Commit, push, and publication are not authorized.

**Publication status (2026-10-19):** loozo said "article 1 good to publish". Removed the draft flag and shipped it together with the agreed site change: a required `audience` field on every article, `/frontend/` and `/backend/` listing pages built from a shared `ArticleIndex` component, tags shown in the lists again, and the `frontend` tag removed. The gRPC ordering special case moved into `ArticleIndex`, so it also applies on `/frontend/`. Committed as `fb747eb` (`Publish ASP.NET Core request pipeline article and audience filters`) and pushed to `origin/main`; GitHub Pages run `39230286454` succeeded. Live checks: home, `/frontend/`, `/backend/` (seven articles), the article page, RSS, and the sitemap return `200`, and the unpublished DI draft returns `404`. Dark-mode desktop and mobile screenshots of the listing and article pages were checked with headless Chromium. `AGENTS.md`, `pnpm-lock.yaml`, the planning files, and the article 2 draft stay uncommitted.

**Draft verification:** Every example was built and run with .NET SDK 10.0.402 (ASP.NET Core 10.0.13), installed temporarily in `/tmp/dump-dotnet`; the example projects and logs are in `/tmp/dump-aspnet-article`. The article quotes real output for the hand-built pipeline in both orders, routing logs, binding failures in `Production` and `Development`, the `{id:int}` constraint, JSON body cases, the controller endpoint and `[ApiController]` `400`, the endpoint list, the endpoint filter, `/crash`, and a response that had already started. `MapGroup(...).AddEndpointFilter` and `MapControllers().AddEndpointFilter` compile. `dotnet run --urls` and `--no-launch-profile` behave as described. `ApplicationBuilder.Build`, `AcceptsMatcherPolicy`, and `RouteHandlerOptions.ThrowOnBadRequest` were checked in dotnet/aspnetcore `release/10.0` at `b6da38d94a8e132a8be53ee90afa8c04483f84c1`. Astro check reports no diagnostics, the production build excludes the draft, and the development preview renders the page with all twelve internal anchors resolving.

**Corrections to the outline found while verifying:** `415` comes from routing, not binding. When an endpoint declares it accepts JSON and no endpoint accepts the request's `Content-Type`, routing selects a built-in "415 HTTP Unsupported Media Type" endpoint. In `Development`, minimal API binding failures throw `BadHttpRequestException`, which the developer exception page shows as a `400` (`ThrowOnBadRequest` defaults to `IsDevelopment()`). The MVC exception-filter contradiction was avoided rather than resolved; the draft makes no claim about model-binding exceptions.

**Working title:** From bytes to your handler: how ASP.NET Core runs a request.

**Reader outcome:** Trace a request from Kestrel through middleware and routing to an endpoint, predict which part of that path produced a response, and order middleware on purpose.

**Running example:** The task board API kept in memory, with no database yet: `GET /tasks/{id}` and `POST /tasks` in one `Program.cs`, plus one controller later. Requests are sent with `curl`.

**Prerequisites:** C# lambdas and `Func<>` delegates; basic `async` and `await` (article 3 explains what happens underneath); HTTP requests and responses (link the HTTP article instead of re-teaching them).

### 1. Opening: a 400 your code never sent

- `GET /tasks/abc` returns `400`, but a breakpoint in the handler never hits. `GET /task/1` returns `404` with no log line from your code.
- Who answered? The closing section answers this.

### 2. Kestrel turns bytes into an `HttpContext`

- Kestrel listens on a port, reads HTTP messages, and builds one `HttpContext` per request.
- Show `Request`, `Response`, `RequestAborted`, and `RequestServices`; mention `User` by name only.
- Kestrel then calls one function with that `HttpContext`; the rest of the article is about how that function gets built.
- One paragraph on reverse proxies: Kestrel can face the internet directly or sit behind nginx, IIS, or YARP, and both are supported.

### 3. The whole app is one `RequestDelegate`

- `delegate Task RequestDelegate(HttpContext context)`.
- Smallest app: `app.Run(ctx => ctx.Response.WriteAsync("hello"))`.

### 4. Build a pipeline by hand

- In plain C#, without ASP.NET Core: a list of `Func<RequestDelegate, RequestDelegate>`, composed in reverse on top of a final `404` delegate.
- Then show that `app.Use(...)` registers exactly this kind of component.
- Notice: code runs before and after `next`; not calling `next` short-circuits; each component wraps the ones registered after it.
- Order demo: a timing middleware before and after a short-circuiting one. Name the misconception first: "middleware order doesn't matter as long as everything is registered."
- Once the response has started, a later component can't change the status code or headers.

### 5. Routing picks an endpoint, and a later step runs it

- An endpoint is a `RequestDelegate` plus metadata plus a route pattern.
- `UseRouting` selects, `UseEndpoints` executes. Middleware between them can read `context.GetEndpoint()`; authorization and CORS work this way.
- `WebApplication` adds `UseRouting` and `UseEndpoints` automatically; show the effective pipeline, and note that routes mapped on `app` run at the end.
- Demo: a middleware that logs which endpoint was selected.
- No match: the request falls off the end of the pipeline and gets `404`. This explains `/task/1`.

### 6. `MapGet` turns your lambda into a `RequestDelegate`

- The generated delegate reads parameters, calls the lambda, and writes the result.
- Binding sources by default: route values when the name matches the template, then the query string, then services, then the body. `[From*]` attributes override this.
- Return values: a `string` becomes text, other objects become JSON, an `IResult` writes its own response.
- Binding failures happen before the lambda runs: an unparseable route or query value gives `400`, malformed JSON gives `400`, the wrong content type gives `415`. This explains `/tasks/abc`.
- Contrast: with `{id:int}`, `/tasks/abc` doesn't match the route, so the response is `404` instead of `400`.

### 7. Controllers are endpoints too

- The same `GET` endpoint as a controller action.
- `MapControllers` adds endpoints to the same routing table; list the endpoints at startup to show both kinds side by side.
- Inside its endpoint, a controller runs MVC's own steps: filters, model binding, the action, and result execution.
- Defer the comparison to backend article 7; state only what is true for both.

### 8. Filters, a second pipeline inside the endpoint

- Name the misconception first: "filters are a controller feature" or "filters and middleware are interchangeable."
- A filter wraps the handler the way middleware wraps the pipeline: before and after `next`, short-circuit by not calling it. Same order rules as section 4: first registered runs first on the way in and last on the way out.
- A filter runs after routing and binding, so it sees the handler's typed arguments and its return value; middleware sees only the raw `HttpContext`.
- Example: an endpoint filter on `POST /tasks` that logs the bound `CreateTaskRequest` and what the handler returned. Notice that it reads a typed request, not JSON text, and applies only to that endpoint or to a route group via `MapGroup(...)`. No validation; that belongs to backend article 9.
- Controllers have their own filter pipeline: Authorization → Resource → model binding → Action → action runs → Exception → Result, with one sentence per kind.
- Endpoint filters also work on controller actions through `MapControllers().AddEndpointFilter(...)`.
- Choosing: middleware for concerns that apply to every request whichever endpoint handles it (request logging, CORS, authentication, exception handling, which Microsoft's docs prefer to handle in middleware); a filter when the concern needs typed arguments or the result, or applies only to some endpoints.

### 9. When something throws

- An unhandled exception becomes `500`; in Development, the developer exception page shows it.
- Defer error shaping and `ProblemDetails` to backend article 9.

### 10. Closing: which layer answered?

| You see | Where it came from |
|---|---|
| No response at all | Network or Kestrel; see the HTTP article |
| `404`, handler never ran | No endpoint matched |
| `400` or `415`, handler never ran | Parameter binding |
| `401` or `403` | Authentication or authorization middleware (backend articles 13 and 14) |
| `500` | An exception |

Quiz, four questions:

1. Predict the log order for a given middleware order.
2. Where does `/tasks/abc` fail, with and without `{id:int}`?
3. Why can a middleware registered after `UseRouting` know which endpoint was selected?
4. A check needs the parsed request body and applies to three endpoints. Middleware or filter, and why?

### Boundaries

Leave dependency injection lifetimes (backend article 2), async internals (3), validation and `ProblemDetails` (9), OpenAPI (8), the full controllers comparison (7), and authentication and authorization (13 and 14) to their own articles. Leave out Kestrel configuration, HTTP/2 and HTTP/3, IIS hosting, Razor and Blazor, custom MVC filter types, and filter factories.

### Technical references for later drafting

- Middleware, aspnetcore-10.0, docs commit `0c08ef3bccc88b2769e087a5ed1608c00ab9dfd9`, checked 2026-10-19: `Use`, `Run`, short-circuiting, what `WebApplication` adds automatically, order rules. https://learn.microsoft.com/en-us/aspnet/core/fundamentals/middleware/?view=aspnetcore-10.0
- Routing, aspnetcore-10.0, checked 2026-10-19: selection versus execution, `GetEndpoint`, what an endpoint consists of. https://learn.microsoft.com/en-us/aspnet/core/fundamentals/routing?view=aspnetcore-10.0
- Minimal API parameter binding, aspnetcore-10.0, docs commit `e073388af85c37ed5207ca8bed5ea3445fcefcdd`, checked 2026-10-19: binding precedence and failure status codes. https://learn.microsoft.com/en-us/aspnet/core/fundamentals/minimal-apis/parameter-binding?view=aspnetcore-10.0
- Kestrel, aspnetcore-10.0, docs commit `0c08ef3bccc88b2769e087a5ed1608c00ab9dfd9`, checked 2026-10-19: edge and reverse-proxy setups. https://learn.microsoft.com/en-us/aspnet/core/fundamentals/servers/kestrel?view=aspnetcore-10.0
- Minimal API filters, aspnetcore-10.0, docs commit `22d0ff7ccc53b84c514cb1cc823c8a8bb7fe1ec9`, checked 2026-10-19: `AddEndpointFilter`, arguments, FIFO and FILO order, use on controller actions. https://learn.microsoft.com/en-us/aspnet/core/fundamentals/minimal-apis/min-api-filters?view=aspnetcore-10.0
- MVC filters, aspnetcore-10.0, checked 2026-10-19: filter kinds and order, middleware preferred for exception handling. https://learn.microsoft.com/en-us/aspnet/core/mvc/controllers/filters?view=aspnetcore-10.0
- Verify in ASP.NET Core source when drafting: `ApplicationBuilder.Build` composing in reverse on a final `404` delegate, and whether MVC exception filters catch model-binding exceptions (the docs page contradicts itself). Check the current .NET 10 patch version.

## Agreed outline: Dependency injection and service lifetimes

Backend track, article 2. Agreed with loozo on 2026-10-19: "article 2 ready to draft", which approves the outline with the recommended decisions (disappearing-task opening, a separate `dotnet new web` project for the container demo, concrete classes with one plain-fact interface example, `IMiddleware` in one sentence, the leak demo only in section 11, the name `TaskChanges`, twelve sections) and authorizes the draft. Outline research by a helper agent against Microsoft Learn and dotnet/runtime and dotnet/aspnetcore source at v10.0.13; the captive-dependency and root-resolution errors were confirmed by running them on .NET 10.

**Draft status (2026-10-19):** Written in `src/content/blog/aspnet-core-dependency-injection.md` with `draft: true` and left uncommitted. Commit, push, and publication are not authorized.

**Publication status (2026-10-19):** loozo said "article 2 good to publish". Removed only the draft flag. Committed only the article as `50028a9` (`Add ASP.NET Core dependency injection article`) and pushed to `origin/main`; GitHub Pages run `39230568229` succeeded. The Mermaid scopes diagram was checked visually in dark mode before publishing. Live checks: the article, `/backend/` (eight articles), and RSS return `200`; the article is absent from `/frontend/`; its links to the request pipeline and Angular DI articles are live.

**Draft verification:** Every example was built and run with .NET SDK 10.0.402 (ASP.NET Core 10.0.13); projects and logs are in `/tmp/dump-aspnet-article/di`. Quoted output comes from real runs: the opening's scoped-store `404`, wiring by hand, the container and two-scope demo, the forgotten-registration message, `/lifetimes` called twice with the middleware log and disposal after the response, the seeded store and `POST /tasks`, the transient-disposable leak disposed only at shutdown in reverse order, the captive `TaskImporter` (startup error in `Development`, one shared `TaskChanges` in `Production`), resolving scoped from the root (error in `Development`, silent root caching in `Production`), a scoped service in a middleware constructor (startup error in `Development`, one shared instance in `Production`), and `UseDefaultServiceProvider` validation failing in `Production`. The concurrency race is shown as a timeline, not run. Astro check reports no diagnostics, the production build excludes the draft, and the development preview renders the page with all fourteen internal anchors and both article links resolving. The Mermaid diagram was not checked visually.

**Working title:** Who creates your services: dependency injection and lifetimes in ASP.NET Core.

**Reader outcome:** Predict which instance a class receives in a request, choose singleton, scoped, or transient on purpose, know who disposes each service and when, recognize and fix a captive dependency, and know how handlers, filters, middleware, and controllers get their services.

**Running example:** The task board API with `TaskStore` (holds tasks, hands out ids) and `TaskChanges` (a per-request unit of work that collects changes and applies them on `Commit()`; `IDisposable`; the role EF Core's `DbContext` plays). Demo classes expose a short `Id` from a `Guid`.

**Prerequisites:** C# classes, constructors, and generic methods; `using` and `IDisposable`, defined in one line at first use; the request pipeline article. Link the Angular DI article for frontend readers without depending on it.

### Sections

1. **Opening: a task that disappears.** `POST /tasks` returns `201` with id `1`, then `GET /tasks/1` returns `404`, with no error. The cause, `AddScoped<TaskStore>()`, is revealed in section 6.
2. **Using a dependency versus creating it.** `new TaskStore()` inside the class, then a constructor parameter. That's dependency injection, with no framework. Define primary constructors.
3. **Wiring by hand.** Create `TaskStore` once and `TaskChanges` per request with `using`. Point out the three lifetime decisions and the hand-written cleanup.
4. **A container that does the wiring.** Separate project: `ServiceCollection`, `AddSingleton`, `AddScoped`, `BuildServiceProvider`, `GetRequiredService`. Define registration, `IServiceCollection`, building, `IServiceProvider`, and resolution. Constructor selection. The error for a forgotten registration. Concrete-class registration and interface registration as one-line plain facts. Angular terms table.
5. **Scopes and the three lifetimes.** A scope is a cache plus a list of objects to dispose. Lifetimes defined by where the instance is cached. Two-scope demo with ids. Scopes are flat; diagram.
6. **One scope per request in ASP.NET Core.** `builder.Services`, `app.Services`, `HttpContext.RequestServices`; scope created on first use, disposed after the response. `GET /lifetimes` demo called twice, plus a middleware logging the scoped id. Answer the opening. Misconception: "scoped means per thread."
7. **Choosing a lifetime.** Table with task-board examples; EF Core registers `DbContext` as scoped by default, stated as a fact. Singletons are shared by concurrent requests: a two-column interleaving timeline, a `lock` fix, and the container's thread safety covering only creation.
8. **Who disposes what.** The container disposes what it created, in reverse order: scoped and transient at scope end, singletons at shutdown. The disposed log line appears after the response. Don't dispose injected services. Instances passed in are never disposed.
9. **How each kind of code gets its services.** Table: handler parameters, typed endpoint filters (per call from the request scope, source-verified), lambda middleware and filters, middleware classes (constructed once; scoped services go in `InvokeAsync`), `IMiddleware` in one sentence, controllers.
10. **Captive dependencies and scope validation.** Misconception: "transient means safe." Singleton holding `TaskChanges`: the `Development` startup error, silent sharing in `Production`. Resolving scoped from the root and the `CreateScope` fix. What validation can't see; the one line that enables it everywhere. Three fixes, simplest first.
11. **Asking the container directly.** Misconception: "inject `IServiceProvider` everywhere." Hidden dependencies, no startup validation, the root provider inside singletons. The root-provider leak demo with a transient `IDisposable`. Legitimate uses, including a scope per background job, as plain facts.
12. **Closing: back to the disappearing task.** The answer, a four-step debugging checklist, and a four-question quiz.

### Boundaries

Out of scope: async internals, EF Core, the controllers comparison, code organization, options, keyed services, background services, testing, third-party containers, multiple registrations and `TryAdd*`, open generics beyond one sentence about `ILogger<T>`, Blazor scopes, and async factories. No mentions of unwritten articles.

### Docs problems to follow the source on

1. A scoped service in a middleware constructor throws only when scope validation is on (default in `Development`); otherwise it is cached in the root for the app's lifetime.
2. A scope is per request, not per connection.
3. Transients are disposed at request end only when resolved from the request scope.
4. The ASP.NET Core DI page's primary-constructor middleware sample uses an undeclared `_next`.

### Technical references for later drafting

All checked 2026-10-19.

- ASP.NET Core DI, docs commit `0c08ef3bccc88b2769e087a5ed1608c00ab9dfd9`: https://learn.microsoft.com/en-us/aspnet/core/fundamentals/dependency-injection?view=aspnetcore-10.0
- .NET DI overview, docs commit `1d96512298865d7bce113c7ba9c23a6ca650e86a`: https://learn.microsoft.com/en-us/dotnet/core/extensions/dependency-injection/overview
- Service lifetimes, registration, and guidelines, docs commit `156931bb4ec1e81b028c76ea983553f2e9778bdd`: https://learn.microsoft.com/en-us/dotnet/core/extensions/dependency-injection/service-lifetimes, https://learn.microsoft.com/en-us/dotnet/core/extensions/dependency-injection/service-registration, https://learn.microsoft.com/en-us/dotnet/core/extensions/dependency-injection/guidelines
- Write custom middleware, docs commit `22d0ff7ccc53b84c514cb1cc823c8a8bb7fe1ec9`: https://learn.microsoft.com/en-us/aspnet/core/fundamentals/middleware/write?view=aspnetcore-10.0
- Factory-based middleware, docs commit `0c08ef3bccc88b2769e087a5ed1608c00ab9dfd9`: https://learn.microsoft.com/en-us/aspnet/core/fundamentals/middleware/extensibility?view=aspnetcore-10.0
- Generic host and scope validation, docs commits `22d0ff7ccc53b84c514cb1cc823c8a8bb7fe1ec9` and `cb8ebc40c6f1ad3729f05670528384e64899b347`: https://learn.microsoft.com/en-us/aspnet/core/fundamentals/host/generic-host?view=aspnetcore-10.0
- Controllers DI, docs commit `bdf163830a286a0b8064e68367be018ad7e0e0f8`: https://learn.microsoft.com/en-us/aspnet/core/mvc/controllers/dependency-injection?view=aspnetcore-10.0
- dotnet/runtime v10.0.13 (`6aa72daa24f66c01c3d7b6a32519e9d21396deec`): `HostingHostBuilderExtensions.cs` (validation equals `isDevelopment`), `CallSiteValidator.cs`, `ServiceProvider.cs`, `CallSiteRuntimeResolver.cs`, `ServiceProviderEngineScope.cs`.
- dotnet/aspnetcore v10.0.13 (`0ef4bbfa3291b306a21e5001cb0491277bdd35bc`): `RequestServicesFeature.cs`, `UseMiddlewareExtensions.cs`, `EndpointFilterExtensions.cs`, `RequestDelegateFactory.cs`, `DefaultControllerActivator.cs`.

## Agreed outline: async, await, and the thread pool

Backend track, article 3. Agreed with loozo on 2026-10-19: "good to draft", which approves the outline with the recommended decisions (`.Result` in the opening and `Thread.Sleep` as the plain form, a dedicated monitor thread with `dotnet-counters` named once, the `LoadTest` console app, `ContinueWith` inline with the state machine collapsed, one sentence on the lock tension, thirteen sections) and authorizes the draft. Outline research by a helper agent against Microsoft Learn and dotnet/runtime and dotnet/aspnetcore source at v10.0.13, with measurements on .NET 10.

**Draft status (2026-10-19):** Written in `src/content/blog/aspnet-core-async-and-the-thread-pool.md` with `draft: true` and left uncommitted. Commit, push, and publication are not authorized.

**Publication status (2026-10-19):** loozo said "article 3 good to publish". Removed only the draft flag from the current file. Committed only the article as `282428e` (`Add async, await, and thread pool article`) and pushed to `origin/main`; GitHub Pages run succeeded. Live checks: the article, `/backend/` (nine articles), and RSS return `200`, and its three article links are live.

**Draft verification:** Every example was built and run with .NET SDK 10.0.402 (ASP.NET Core 10.0.13) in Debug and `Development`, as `dotnet run` does, on a 16-processor Linux laptop; projects, variants, scripts, and logs are in `/tmp/dump-aspnet-article/async`. Each load measurement used a freshly started server and the article's exact endpoint code, twice per variant: `await` 0.58 s on 17 threads with `/tasks/1` at 5 ms; `.Result` 2.7 to 2.8 s on 76 to 78 threads with `/tasks/1` at about 2 s; `GetAwaiter().GetResult()` 2.8 s on 77 to 78 threads; `Thread.Sleep` 6.1 s on 17 threads with `/tasks/1` at 5.4 s; `await Task.Run(Thread.Sleep)` 6.6 s on 17 threads. CPU work (about 30 ms of hashing) took 2.24 to 2.25 s called directly and 2.08 to 2.23 s through `Task.Run`, so the draft says `Task.Run` doesn't help rather than that it's slower; the research measurement of a small slowdown didn't reproduce. Also run: the `ContinueWith`, `await`, and hand-written state machine console demos; `/where` alone and with 30 concurrent requests; `CS1996` for `await` inside `lock`; `async void` crashing the process after `200`; a discarded task losing its exception silently; the awaited version returning `500` and staying up; cancellation logging `499` after two steps, and the version without a token running all ten steps and logging `200`; the dashboard at 1.0 s sequential and 0.5 s with `Task.WhenAll`. `.Wait()` was not measured separately with this code; the draft relies on the source showing it blocks through the same path as `.Result`. The explanation that `.Result` also delays its own wait, because the awaited method's continuation needs a pool thread, is stated as mechanism, not measured in isolation. Astro check reports no diagnostics, the production build excludes the draft, the development preview renders all thirteen internal anchors and three article links, and the thread pool diagram was checked visually in dark mode.

**Working title:** Waiting without blocking: async, await, and the thread pool in ASP.NET Core.

**Reader outcome:** Say what a thread does while handler code waits, recognize code that holds a thread while waiting, fix it by awaiting all the way down, pass the request's cancellation on, run independent waits at the same time, and explain why `Task.Run`, `async void`, and `.Result` don't belong in request handlers.

**Running example:** The in-memory task board with `GET /tasks/summary` calling a client that waits 500 ms, `GET /tasks/report` (a slow loop taking a `CancellationToken`), `POST /tasks/{id}/complete` notifying watchers, a `LoadTest` console app (`HttpClient`, `Task.WhenAll`, latency summary), and a monitor thread printing the pool's thread count and queue length.

**Prerequisites:** basic `async` and `await` syntax; the request pipeline article (`RequestAborted`, `CancellationToken` binding); the DI article (singletons shared by concurrent requests). The JavaScript runtimes article is optional.

### Sections

1. **Opening: one slow endpoint slows down every endpoint.** `.Result` under 200 concurrent requests: slow summaries, a growing pool, and a slow `/tasks/1`. One line changed to `await` fixes all three. Why did fewer threads serve faster?
2. **Set up the example.** The one setup and versions note, single-machine numbers, restarting between measurements because the pool keeps threads for 20 s, and scope limits.
3. **What a thread is, and what blocking costs.** `Thread.Sleep` holds a thread. Misconception: "a waiting thread costs nothing"; memory isn't what runs out, ready threads are. One paragraph for JavaScript readers.
4. **The thread pool.** Pool threads run request code; fast injection up to the processor count, then slow. `Thread.Sleep` demo under load. Thread pool starvation defined. `SetMinThreads` in one sentence as hiding the cause.
5. **Tasks and continuations.** A `Task` is an object for work that finishes later; `Task.Delay` uses a timer, not a thread. Misconception: "a Task is a thread." A hand-written `ContinueWith` continuation printing thread ids.
6. **What await does.** The five steps; awaiting a completed task doesn't pause; a simplified state machine collapsed. Misconceptions: "await creates a thread", "async makes code faster or parallel."
7. **Which thread continues after await.** Thread ids change under load. No `SynchronizationContext` in ASP.NET Core, so `ConfigureAwait(false)` changes nothing in app code and the classic deadlock becomes starvation. Shared-state recap linking the DI article; no `await` inside `lock`; one sentence on short locks without I/O.
8. **Blocking on async code starves the pool.** Misconception: "`.Result` is fine if it's quick." `.Result`, `.Wait()`, and `GetResult()` block the same way. Measurement table. Async all the way down.
9. **Task.Run doesn't free a thread.** `await Task.Run(blockingCall)` measured. I/O-bound versus CPU-bound; `Task.Run` adds overhead for CPU work in a server; why UI advice differs.
10. **async void can crash the server.** The client gets `200`, then the process dies. A discarded task loses its exception. Fix: return a `Task` and await it.
11. **Stopping work when the client leaves.** Cooperative cancellation; `curl --max-time` demo; status `499` in the log; the version without the token keeps working. Rules for passing tokens.
12. **Running independent waits at the same time.** Sequential awaits versus `Task.WhenAll`. Safety: `HttpContext` isn't thread-safe; a unit of work can't run two operations at once. `LoadTest` has used the pattern all along.
13. **Closing: back to the slow summary.** The answer, a four-item checklist, and a four-question quiz about threads during waits.

### Boundaries

Out of scope: background work after the response, parallel CPU work, UI synchronization contexts, custom awaitables and `ValueTask` beyond one sentence, `IAsyncEnumerable`, async locks beyond one sentence, diagnostic tools beyond one sentence, thread pool tuning, `ExecutionContext` and `AsyncLocal`, timeouts and linked tokens, EF Core, IIS. No mentions of unwritten articles.

### Docs problems to follow the source or measurements on

1. The async scenarios page ranks `.Result` and `.Wait()` as riskier than `GetAwaiter().GetResult()`; all three block through the same `InternalWait`.
2. The async scenarios page says to move CPU work to `Task.Run` (UI advice); the best-practices page says not to call `Task.Run` and immediately await it in ASP.NET Core.
3. The `Task.ConfigureAwait` remarks say the continuation usually runs on the creating thread; in ASP.NET Core it runs on any pool thread.
4. Two pages say `ValueTask` needs a NuGet package; it's built into .NET 10.
5. The best-practices samples for not sharing `HttpContext` across threads don't compile as shown.
6. Not on Learn: ASP.NET Core has no `SynchronizationContext` (2019 ConfigureAwait FAQ and source), and aborted requests log status `499` (source).

### Technical references for later drafting

All checked 2026-10-19.

- ASP.NET Core best practices, docs commit `cb8ebc40c6f1ad3729f05670528384e64899b347`: https://learn.microsoft.com/en-us/aspnet/core/fundamentals/best-practices?view=aspnetcore-10.0
- Asynchronous programming overview, TAP model, and async scenarios, docs commit `156931bb4ec1e81b028c76ea983553f2e9778bdd`: https://learn.microsoft.com/en-us/dotnet/csharp/asynchronous-programming/
- Async return types, docs commit `25c3f34f4c807ae3066783eb5a3a60b145ff0bad`: https://learn.microsoft.com/en-us/dotnet/csharp/asynchronous-programming/async-return-types
- Consuming TAP, docs commit `8b2033ff9f3b355e8fca60a4b0ee5e6501ab4fc7`: https://learn.microsoft.com/en-us/dotnet/standard/asynchronous-programming-patterns/consuming-the-task-based-asynchronous-pattern
- The managed thread pool, docs commit `156931bb4ec1e81b028c76ea983553f2e9778bdd`: https://learn.microsoft.com/en-us/dotnet/standard/threading/the-managed-thread-pool
- Threading runtime config, docs commit `028e3437c43bfb581b25dc2db98225ba93d87f64`: https://learn.microsoft.com/en-us/dotnet/core/runtime-config/threading
- Debug thread pool starvation, docs commit `bf699c1dc311a6c1eed1ac8c08470af78675dd42`: https://learn.microsoft.com/en-us/dotnet/core/diagnostics/debug-threadpool-starvation
- Cancellation in managed threads, docs commit `8b2033ff9f3b355e8fca60a4b0ee5e6501ab4fc7`: https://learn.microsoft.com/en-us/dotnet/standard/threading/cancellation-in-managed-threads
- ConfigureAwait FAQ (Stephen Toub, .NET Blog): https://devblogs.microsoft.com/dotnet/configureawait-faq/
- dotnet/runtime v10.0.13 (`6aa72daa24f66c01c3d7b6a32519e9d21396deec`): `PortableThreadPool.GateThread.cs`, `PortableThreadPool.Blocking.cs`, `PortableThreadPool.cs`, `Task.cs` (`InternalWait`).
- dotnet/aspnetcore v10.0.13 (`0ef4bbfa3291b306a21e5001cb0491277bdd35bc`): `HttpProtocol.cs` (`499`), no `SetSynchronizationContext` outside Blazor.

## Agreed outline: SQL, indexes, and parameters

Backend track, article 4. Agreed with loozo on 2026-10-19: "Good to draft", which approves the outline with the recommended decisions (Docker `postgres:18.6-trixie` for readers, 1,000,000 tasks and 1,000 users, no N+1, inline SQL Server and MySQL notes, single-process plan first then the parallel default once, `$1` parameters, `integer` ids, the `union` leak run and the `delete` variant described only) and authorizes the draft. Outline research by a helper agent against the PostgreSQL 18 docs, Npgsql docs, Microsoft Learn, the MySQL 8.4 manual, and OWASP, with plans measured on a portable PostgreSQL 18.6 and Npgsql 10.0.3. The article links the async article, so that article must be published first or the link dropped.

**Draft status (2026-10-19):** Written in `src/content/blog/sql-indexes-and-parameters.md` with `draft: true` and left uncommitted. Commit, push, and publication are not authorized. Publish the async article first, since this one links it.

**Publication status (2026-10-19):** loozo said "article 4 good to publish", after the async article was live. Removed only the draft flag. Committed only the article as `bd239bc` (`Add SQL, indexes, and parameters article`) and pushed to `origin/main`; GitHub Pages run succeeded. Live checks: the article, `/backend/` (ten articles), and RSS return `200`, and its five article links are live.

**Draft verification:** All SQL, plans, and timings come from the article's own `seed.sql` (`integer` ids, an `active` column on users) loaded into a fresh portable PostgreSQL 18.6 cluster (zonky binaries from the outline research) initialized with `en_US.UTF-8` and set to UTC like the Docker image; working files in `/tmp/dump-aspnet-article/sql`. Measured: the opening query at 55 ms single-process and 28 to 32 ms parallel over 10,205 pages, 0.87 ms with an `assignee_id` index, 0.08 ms and 119 buffers with `(assignee_id, due_on)`; lookup by id in 4 buffers with a three-level primary key index; skip scan with `Index Searches: 1002`; index-only scan; tiny-table and 80%-match sequential scans with the forced index slower; `created_at::date` at 64 to 69 ms against a range at 1.6 ms, and the IMMUTABLE error; newest 20 at 77 to 85 ms against 0.03 ms; search at 0.22 ms for a common term and 440 ms for a rare one; the stale-statistics estimate of 1,141 against 300,888; insert cost at about 0.2, 0.47, and 1.1 s; the foreign key check at 61 ms against 0.7 ms; both foreign key errors; join counts and the `Hash Join` rewrite. The Npgsql 10.0.3 minimal API ran the lookup, the concatenated search, the `union` leak returning 1,000 emails, the parameterized search returning `[]` with the value logged separately, `order by $2` not sorting, the allow-list `400`, `_` matching every title, and cancellation logging "canceling statement due to user request". Not run: the Docker commands themselves (the Docker daemon isn't running here), the destructive `delete` variant (verified by the outline research), and anything on SQL Server or MySQL (documentation only). Astro check reports no diagnostics, the production build excludes the draft, the development preview renders all fifteen internal anchors and five article links, and the B-tree diagram was checked visually in dark mode.

**Working title:** Why listing one person's tasks reads every task: tables, indexes, and parameters in PostgreSQL.

**Reader outcome:** Write the basic SQL behind the task board, explain what primary and foreign keys enforce and don't, predict how PostgreSQL finds rows with and without an index, read `EXPLAIN ANALYZE`, choose a two-column index order, and explain why parameters stop SQL injection when escaping doesn't.

**Running example:** `users` (1,000 rows) and `tasks` (1,000,000 generated rows) in PostgreSQL; a minimal API using Npgsql with parameters and the request's `CancellationToken`. No EF Core, no Dapper.

### Sections

1. **Opening: the foreign key is there, so why is it slow?** "My open tasks" reads every page of a million-row table; one `create index` fixes it.
2. **Set up the example.** One setup and versions note; PostgreSQL 18 required for these plans.
3. **Tables, rows, and the first queries.** Types, `not null`, `null`, `is null`; `LIMIT` and `ILIKE` engine notes.
4. **Primary keys, identity columns, and foreign keys.** Misconceptions: "a primary key is just a unique column", "foreign keys create indexes". Errors shown by running them. Engine notes.
5. **Joins.** Inner versus left; a `where` on the right table turns a left join into an inner join, visible in the plan; fix by meaning.
6. **How PostgreSQL stores rows, and the first plan.** Heap pages, sequential scan, single-process plan then parallel default. Clustered storage engine note.
7. **How a B-tree index finds rows.** Diagram; lookup by id; bitmap scan on `assignee_id`.
8. **Indexes with more than one column.** `(assignee_id, due_on)`, column order, skip scan misconception, index-only scans in one paragraph.
9. **Reading a query plan.** Tree order, cost, estimated versus actual rows, loops, buffers, timing; `EXPLAIN ANALYZE` runs the statement; statistics and `analyze`.
10. **When the planner doesn't use your index.** Tiny tables, low selectivity, functions on indexed columns (time zone and immutability), leading wildcards.
11. **LIMIT and the cost of indexes.** Misconception: "LIMIT makes the query cheap." Write cost, size, and the foreign key delete payoff.
12. **Queries from C#.** `AddNpgsqlDataSource`, `$1` parameters, `ExecuteReaderAsync` with the request's token, cancellation demo.
13. **SQL injection and what parameters fix.** Concatenated search, the `union` leak, the `delete` variant described, Parse and Bind, escaping misconception, `order by $1` and allow-lists, `LIKE` wildcards in values.
14. **Closing: back to the slow list.** Answer, checklist, four-question quiz.

### Boundaries

Out of scope: EF Core, Dapper, N+1 queries, transactions beyond `begin` and `rollback` for `EXPLAIN ANALYZE`, migrations and `create index concurrently`, many-to-many tables, index types other than B-tree beyond one `pg_trgm` sentence, partial and covering indexes, prepared statements and plan caching, batching and bulk loading, partitioning, tuning, `VACUUM` internals beyond one paragraph, and permissions beyond one sentence. No mentions of unwritten articles.

### Docs problems to follow measurements on

1. Npgsql's basic usage says parameterizing a column name fails; in `ORDER BY` it silently sorts by a constant.
2. Microsoft's SQL injection page advises rejecting comment characters; follow OWASP (parameters plus allow-lists).
3. "A composite index is useless without its first column" is contradicted by PostgreSQL 18 skip scan.
4. A plain `VACUUM` after a small update may skip index cleanup and leave heap fetches; don't build a demo on it.

### Technical references for later drafting

All checked 2026-10-19: PostgreSQL 18 docs (release notes, constraints, identity columns, table expressions, page layout, indexes intro, types, multicolumn, ordering, expressions, index-only scans, using EXPLAIN, EXPLAIN, planner statistics, pattern matching, pg_trgm, protocol flow) at https://www.postgresql.org/docs/18/; Npgsql basic usage and prepared statements at https://www.npgsql.org/doc/; Microsoft Learn SQL Server pages on keys, clustered indexes, SQL injection, IDENTITY, ORDER BY, and actual execution plans (sql-server-ver17); MySQL 8.4 manual pages on foreign keys, InnoDB index types, string literals, range optimization, EXPLAIN, and AUTO_INCREMENT; the OWASP SQL Injection Prevention Cheat Sheet; the Docker official `postgres` image docs.

## Agreed outline: EF Core behind the scenes, and when to write SQL yourself

Backend track, article 5. Agreed with loozo on 2026-10-19: "good to draft", which approves the outline with the recommended decisions (the `IEnumerable` helper opening, `EFCore.NamingConventions` shown after the `"Tasks"` error with one `HasColumnName` line, the manual loop for N+1 with lazy loading in one paragraph, one Dapper section without multi-mapping, the minimal API for behavior and a collapsed console program for measurements, a compact SQL log, `AddNpgsqlDataSource` with a parameterless `UseNpgsql()`, the `created_at` default gotcha, and one factual MySQL provider note rechecked when drafting) and authorizes the draft. Outline research by a helper agent against the EF Core 10 docs, the Npgsql EF Core provider docs and source, EFCore.NamingConventions, and Dapper source, with runs on PostgreSQL 18.6 using article 4's seed and index.

**Draft status (2026-10-19):** Written in `src/content/blog/ef-core-behind-the-scenes.md` with `draft: true` and left uncommitted. Commit, push, and publication are not authorized.

**Draft verification:** Every snippet ran with .NET SDK 10.0.402, Npgsql.EntityFrameworkCore.PostgreSQL 10.0.3 (EF Core 10.0.4), EFCore.NamingConventions 10.0.1, Npgsql.DependencyInjection 10.0.3, and Dapper 2.1.89 against a freshly reseeded copy of article 4's database with the `(assignee_id, due_on)` index; projects in `/tmp/dump-aspnet-article/ef` (`Lab` console in Release, `TaskBoard` web app in Development). Measured: the `IEnumerable` helper endpoint at 1.8 to 3 s against 2 to 23 ms, with about 970 MB allocated and 1,000,000 tracked in the console run; 100,000-row reads at about 240 ms and 99 MB tracked, 58 to 64 ms and 37 MB no-tracking, 54 to 63 ms and 35 MB projected; N+1 with 48 commands at 20 to 22 ms against one command at 6 to 10 ms; a singleton context failing 152 of 200 concurrent requests against 0 for scoped. Quoted output is real: the `"Tasks"` error, default command logs and Npgsql's `$1` log, sensitive data logging, client evaluation exceptions, `Contains` 0 against `ILike` 20, `DebugView`, the single-column `UPDATE`, the batched save with transaction logging, `-infinity` without the default, the identity map and `FindAsync` sending nothing, the detached no-tracking change, the second-operation exception, `FromSql` parameters, the `FromSqlRaw` injection, the EF1003 warning, `SqlQuery` naming error, `ExecuteUpdate` (178 rows) with the stale tracked entity, `ExecuteDelete`, Dapper's alias gotchas, and `MatchNamesWithUnderscores`. NuGet checked: Pomelo's latest is 9.0.0, Oracle's MySql.EntityFrameworkCore is at 10.0.9. Not rerun from the outline research: lazy-loading proxies, `AsSplitQuery`, `FromSqlRaw` with `{0}` arguments, and the analyzer missing a string built in a variable. Astro check reports no diagnostics, the production build excludes the draft, and the development preview renders all fourteen internal anchors and four article links.

**Revision (2026-10-19):** At loozo's request, the "`ToList()` at the end" paragraph now shows three versions with the SQL each sends, measured warm on a freshly reseeded database: `ToListAsync` first (no `WHERE`, 1,000,000 tracked, 3.2 to 3.8 s), in the middle (`WHERE` only, 160 tracked full rows, about 5 ms for user 7), and last (`WHERE`, `ORDER BY`, `LIMIT`, three columns, nothing tracked). Astro check still reports no diagnostics.

**Publication status (2026-10-19):** loozo said "article 5 good to publish". Removed only the draft flag. Committed only the article as `7b85121` (`Add EF Core behind the scenes article`) and pushed to `origin/main`; GitHub Pages run succeeded. Live checks: the article, `/backend/` (eleven articles), and RSS return `200`, and its four article links are live.

**Working title:** Why the same LINQ filter can read a million rows: what EF Core sends to PostgreSQL, and when to write SQL yourself.

**Reader outcome:** Map existing tables to entities and read the SQL each query sends, tell whether a LINQ operator runs in the database or in memory, predict what `SaveChanges` sends, avoid N+1 queries, use no-tracking reads and projections, and choose `FromSql`, `SqlQuery`, `ExecuteUpdate` and `ExecuteDelete`, or Dapper without opening an injection hole.

**Running example:** Article 4's `taskboard` database and `(assignee_id, due_on)` index; a minimal API with `TaskBoardDb : DbContext`, entities `User` and `TaskItem`, and response records.

### Sections

1. **Opening: a refactor that lost the WHERE.** An `IEnumerable<TaskItem>` helper parameter turns article 4's indexed query into a full table read.
2. **Set up the example.** One versions note.
3. **Mapping the existing tables.** Entities, navigations, `DbContext`, `DbSet`, conventions; the `"Tasks"` error and the snake_case convention; scoped registration; shared data source.
4. **Seeing the SQL EF Core sends.** Default command logging, literals versus parameters, sensitive data logging, `ToQueryString`, Npgsql's `$1` log, what the logged time measures.
5. **IQueryable and IEnumerable: where the filter runs.** Expression trees versus compiled delegates; the `AsEnumerable` and early `ToList` measurements; client evaluation rules; case-sensitive `Contains` and `ILike`.
6. **Change tracking and what SaveChanges sends.** States, snapshots, `DebugView`, changed-columns-only updates, batching, `RETURNING`, transaction facts, the `created_at` default gotcha.
7. **One instance per row: the identity map.** Same instance per row in a context; `FindAsync`.
8. **Reads that don't need tracking.** `AsNoTracking` and projection measurements; what you give up; the projection sends article 4's query and uses its index.
9. **One context per request, one operation at a time.** Two quoted facts; singleton failures under load; the second-operation exception.
10. **Loading related data and the N+1 problem.** Null navigations; loop, lazy loading, `Include`, projection; split queries briefly.
11. **Writing SQL yourself: FromSql and SqlQuery.** Interpolated parameters; `FromSqlRaw` concatenation injection; analyzer limits; `SqlQuery` naming and type rules.
12. **Bulk changes: ExecuteUpdate and ExecuteDelete.** One statement, nothing tracked; stale tracked entities.
13. **Dapper next to EF Core.** Shared data source, `CommandDefinition` with the token, the underscore mapping gotcha, when each tool fits.
14. **Closing: back to the missing WHERE.** Answer, checklist, four-question quiz.

### Boundaries

Out of scope: transactions beyond stated facts, isolation, concurrency tokens, migrations and scaffolding, the comparison articles' topics and any repository debate beyond the quoted fact, context pooling, compiled queries, owned, complex, and JSON types, inheritance, query filters, interceptors, explicit loading beyond one sentence, stored procedures, bulk inserts, Dapper multi-mapping, NodaTime, connection resiliency. No mentions of unwritten articles.

### Docs problems to follow runs or source on

1. The DbContext configuration page quotes an older second-operation exception text.
2. "All changes in a single call to SaveChanges are applied in a transaction": a single-statement save opens no explicit transaction (`AutoTransactionBehavior.WhenNeeded`).
3. The raw SQL page doesn't say naming conventions apply to `SqlQuery` result types.
4. Npgsql's docs don't document that a parameterless `UseNpgsql()` uses a DI-registered `NpgsqlDataSource` (`NpgsqlDataSourceManager.cs`, v10.0.3).
5. Dapper's README documents neither `MatchNamesWithUnderscores` nor cancellation through `CommandDefinition`.

### Technical references for later drafting

All checked 2026-10-19: Microsoft Learn EF Core pages on DbContext (API and configuration), client evaluation, tracking, change tracking and detection, transactions, efficient updating and querying, ExecuteUpdate and ExecuteDelete, SQL queries, related data and lazy loading, split queries, logging, and what's new in EF Core 10 (https://learn.microsoft.com/en-us/ef/core/); Npgsql EF Core provider docs (https://www.npgsql.org/efcore/) and npgsql/efcore.pg v10.0.3; EFCore.NamingConventions README; Dapper 2.1.89 source. Packages: Npgsql.EntityFrameworkCore.PostgreSQL 10.0.3 (resolves EF Core 10.0.4), EFCore.NamingConventions 10.0.1, Dapper 2.1.89.

## Agreed outline: Transactions and concurrent edits

Backend track, article 6. Agreed with loozo on 2026-10-19: "Good to draft", which approves the outline with the recommended decisions (the vanished-title opening, `PATCH /tasks/{id}` for edits and `POST /tasks/{id}/postpone` for the in-request demo without arguing endpoint design, an app-managed `version` column with one line each for `xmin` and `rowversion`, required `If-Match` with `428`, a strong quoted version ETag in the header, one-line problem bodies for `412` and `428`, a manual three-attempt `40001` retry, two-column timelines plus background `curl` requests for interleavings, a short Serializable section, thirteen sections) and authorizes the draft. Outline research by a helper agent against the PostgreSQL 18 docs and source, Npgsql docs and source, the EF Core docs, RFC 9110, RFC 6585, RFC 5789, the Fetch standard, SQL Server docs, and the MySQL 8.4 manual, with runs on PostgreSQL 18.6.

**Working title:** Why a saved edit can vanish: transactions, isolation, and concurrent edits in PostgreSQL.

**Reader outcome:** Make statements succeed or fail together from psql, Npgsql, and EF Core; predict what concurrent transactions see at each isolation level; spot a lost update and choose between an atomic update, a row lock, a retried Repeatable Read transaction, and a version check; send the version to the client as an ETag so a stale edit gets `412`.

**Running example:** The EF Core article's task board plus `version integer not null default 1`; `GET /tasks/{id}` with an ETag, `PATCH /tasks/{id}`, `POST /tasks/{id}/postpone`, `POST /users/{id}/deactivate?moveTo=`.

### Sections

1. **Opening: a saved edit that disappears.** Two editors, two `204`s, Bob's stale title wins.
2. **Set up the example.** One versions note; the `version` column; two psql windows.
3. **A transaction: all of it or none of it.** Autocommit half-done deactivation; the same inside `begin`, aborted transaction, `commit` answering `ROLLBACK`.
4. **Transactions from C#.** Npgsql transactions belong to one connection; rollback on dispose and on return to the pool; idle in transaction; EF Core `SaveChanges`, `ExecuteUpdate` without a transaction, `BeginTransactionAsync`.
5. **What other transactions see.** MVCC; readers don't wait, writers wait for row locks; Read Committed versus Repeatable Read; SQL Server and MySQL defaults.
6. **Lost updates inside one request.** Two postpones lose one; a transaction at Read Committed doesn't help.
7. **Four ways to stop a lost update.** Atomic update, `select … for update`, Repeatable Read with a `40001` retry, a version check; table; engine notes.
8. **Serializable, when the rule covers several rows.** Three-open-tasks rule; only Serializable catches it; retries for every transaction.
9. **Keep transactions short.** Locked postpones with a slow call inside; `pg_stat_activity`; no external calls or user waits in a transaction.
10. **Edits that span two requests.** Locking on open and `SaveChanges` misconceptions; optimistic concurrency with a version-checked `UPDATE`; `404` versus conflict.
11. **Optimistic concurrency with EF Core.** `IsConcurrencyToken`, `DbUpdateConcurrencyException`, the C# check race, every write must bump the version; `xmin` and `rowversion` in one line each.
12. **The version reaches the client as an ETag.** `If-Match`, `412`, `428`, strong comparison, CORS, what the client does on `412`.
13. **Closing: back to the vanished title.** Answer, checklist, four-question quiz.

### Boundaries

Out of scope: migrations beyond one `alter table`, retries and idempotency in general, execution strategies, authentication, endpoint-style and code-organization comparisons, `TransactionScope`, savepoints beyond one EF log line, `NOWAIT` and `SKIP LOCKED` beyond one sentence, advisory locks, deadlock analysis, SSI and VACUUM internals, Read Uncommitted beyond one sentence, `If-None-Match` and `Last-Modified` on the API, automatic merging, triggers, runnable SQL Server or MySQL examples. No mentions of unwritten articles.

### Docs problems to follow source or runs on

1. Npgsql doesn't document rollback on transaction dispose or on returning a connection to the pool.
2. Npgsql sends an explicit `READ COMMITTED` when no level is chosen.
3. Npgsql's EF concurrency page describes 11.0 behavior; 10.0.3 wraps `40001` as `InvalidOperationException` around `DbUpdateException` around `PostgresException`.
4. EF Core's concurrency page overgeneralizes Repeatable Read and doesn't show sending the token to a client.
5. "current transaction is aborted" appears only in PostgreSQL's source; the docs list code 25P02.

### Before drafting

Check SQL Server's version-checked `UPDATE` under `READ_COMMITTED_SNAPSHOT` in the docs, and the CORS behavior for `ETag` and `If-Match` in a real browser.

**Draft status (2026-10-19):** Written in `src/content/blog/transactions-and-concurrent-edits.md` with `draft: true` and left uncommitted. Commit, push, and publication are not authorized.

**Draft verification:** Pre-draft checks done: SQL Server's locking and row versioning guide (docs commit `cf9e6fbc58f7b72c5f278a42796b74394ad059e4`) says updates under read committed, with or without `READ_COMMITTED_SNAPSHOT`, select rows from the latest committed data, so version-checked updates are safe there; headless Chromium against three CORS policies confirmed that without exposing `ETag` the script reads `null`, and without allowing `If-Match` the preflight blocks the `PATCH` (database unchanged). All runs on a freshly reseeded copy of the SQL article's database plus the `version` column (about 1 ms to add) on the research cluster; projects and outputs in `/tmp/dump-aspnet-article/tx`. Quoted output is real: the psql autocommit and transaction deactivations including "current transaction is aborted" and `ROLLBACK`; Npgsql and EF Core deactivations with and without transactions (rollback visible in PostgreSQL's log, `BEGIN TRANSACTION ISOLATION LEVEL READ COMMITTED`, `SAVEPOINT "__EFSavePoint"`); two-window timelines for nonblocking reads and waiting writers (2.6 s), Read Committed and Repeatable Read reads, the lost update, the atomic update (31 January), `for update` (2.9 s), Repeatable Read `40001`, the version-checked `UPDATE 0`, and Repeatable Read and Serializable three-task rule runs including different users conflicting; API runs of the opening without a concurrency token, postpone in naive, transaction, atomic, locked (2 s and 4 s), and Repeatable Read retry (attempt 2 at 4 s) modes, the exception chain without retry, Read Committed and Serializable rule endpoints (4 open against one `500`), three locked postpones finishing at 2, 4, and 6 s with `pg_stat_activity`; the ETag flow (`200` with `"1"`, `204` with `"2"`, `412` and `428` problem bodies, `204` with `"3"`), If-Match edge cases (weak `412`, list and `*` match, unquoted `428`), the two-request race with `DbUpdateConcurrencyException`, and the version-bump gotcha and its fix. From documentation only: MySQL and SQL Server engine notes, `xmin`, `rowversion`. Astro check reports no diagnostics, the production build excludes the draft, the development preview renders all fifteen internal anchors and eight article links, and the timeline tables were checked visually in dark mode.

**Revision (2026-10-19):** loozo found the difference between Read Committed and Repeatable Read unclear. The isolation section now opens with the question isolation answers (does a later statement see what others committed after an earlier one), uses a count-then-list summary as the running case, and shows it in two timelines: Read Committed counted 160 and listed 159 rows after another session completed task 4869; Repeatable Read counted and listed 160. It adds a C# Repeatable Read snippet (verified: `{"openCount":160,"listed":160}`), explains why Read Committed is the default and what Repeatable Read costs when writing, and ends with a comparison table. The earlier due-date rereads were replaced. Astro check still reports no diagnostics.

**Publication status (2026-10-19):** loozo said "Good to publish", noting that isolation is an advanced topic. Removed only the draft flag. Committed only the article as `11ffdac` (`Add transactions and concurrent edits article`) and pushed to `origin/main`; GitHub Pages run succeeded. Live checks: the article, `/backend/` (twelve articles), and RSS return `200`, and its eight article links are live.

## Agreed outline: Controllers and minimal APIs compared

Backend track, article 7, the first comparison article. Agreed with loozo on 2026-10-19: "Good to draft", which approves the outline with the recommended decisions (the missing-`assigneeId` opening with the `404` body difference as a second beat, all five endpoints built both ways in small slices with full files collapsed, named static handlers in `TaskEndpoints` with one sentence on why, `TypedResults` in this article only, the compact measurement table framed as real but small next to a database round trip, DataAnnotations in both with the missing `AddProblemDetails()` gotcha, two-line authorization, a short Native AOT subsection, both behaviors per criterion, misconceptions in both directions, Microsoft's lists quoted for both, and no verdict) and authorizes the draft. Outline research by a helper agent against aspnetcore-10.0 docs and dotnet/aspnetcore v10.0.13 source, with runs on PostgreSQL 18.6.

**Working title:** Same endpoints, two styles: controllers and minimal APIs in ASP.NET Core.

**Reader outcome:** Write the same endpoints both ways; predict where binding defaults, validation setup, error bodies, dependency creation, and unit-test setup differ; quote Microsoft's recommendation and its reasons; know what the measured speed difference is worth; run both in one app; tell when each fits.

**Running example:** The transactions article's task board built twice, as `TasksController` and as a `TaskEndpoints` class with named static handlers in `MapGroup("/tasks")`, sharing model files: a filtered list, `GET /tasks/{id}` with an ETag, validated `POST /tasks`, `PATCH /tasks/{id}` with `If-Match`, and `POST /tasks/{id}/complete`.

### Sections

1. **Opening: the same request gets two answers.** Missing `assigneeId`: empty `400` against `200 []`; empty `404` against a problem `404`.
2. **Set up the example.** One versions note; two projects sharing model files; `Production`.
3. **What Microsoft recommends.** Quoted recommendation, reasons, and both lists; template defaults.
4. **Routes, and where the code lives.** Attribute routes against `MapGroup`; misconception "everything in Program.cs"; extension method; same size and same files per change.
5. **How dependencies arrive.** Constructor injection creates unused services, even on `415`; per-handler parameters; `[FromServices]`.
6. **Binding: the same signature, different rules.** Missing `int`; record on `GET`; `PATCH` without body; missing `string`.
7. **Validation.** `[ApiController]` against `AddValidation()`; plain JSON without `AddProblemDetails()`; route, query, header validation; misconception "minimal APIs can't validate".
8. **Results and error bodies.** `ActionResult<T>` against `Results<…>`; problem details defaults; `Location` headers; `TypedResults` in controllers; one OpenAPI sentence.
9. **Filters and authorization, one example.** Attributes against group methods; same `401` and header.
10. **Testing.** Identical integration tests; static handler unit test; controller `NullReferenceException` without `ControllerContext`.
11. **Speed, startup, memory, and Native AOT.** Misconceptions in both directions; measurement table; AOT support and EF Core's experimental status.
12. **Both styles in one app.** Coexistence; ambiguous route; moving one endpoint factually.
13. **When each fits.** Quoted, factual lists for both; no verdict.
14. **Closing: back to the two answers.** Different defaults; checklist table; four-question quiz.

### Boundaries

Out of scope: endpoint design, code organization across layers, OpenAPI accuracy beyond one sentence, authentication setup, FluentValidation, OData, custom binders, and application parts beyond naming them, Razor Pages and views, Native AOT walkthroughs, benchmarking methodology beyond one note, migration strategy. No mentions of unwritten articles.

### Docs problems to follow runs or source on

1. The APIs overview gives no evidence for "better performance" and "easier testing".
2. Minimal validation docs omit route values, which are validated.
3. Without `AddProblemDetails()`, the minimal validation `400` is `application/json` without `type` or `status` (`ValidationEndpointFilterFactory.cs`, v10.0.13).
4. The web API page's sample bodies show old RFC 7231 links and trace id formats.
5. The Native AOT page doesn't say that controller apps publish with warnings and then find no actions.
6. The APIs overview recommends controllers for large applications while saying minimal APIs scale; quote both.

**Draft status (2026-10-19):** Written in `src/content/blog/controllers-and-minimal-apis.md` with `draft: true` and left uncommitted. Commit, push, and publication are not authorized.

**Draft verification:** The article's code is the outline research's `Minimal`, `Controllers`, `Gotchas`, and test projects in `/tmp/dump-controllers-research`, rerun on its PostgreSQL 18.6 cluster in `Production`. Rerun and quoted: the opening (`400` empty against `200 []`; empty `404` against a problem `404`), `PATCH` without a body (`400` against `415`), validation bodies with and without `AddProblemDetails()` and `UseStatusCodePages()`, `Location` headers, `[BindRequired]` (new check, problem `400`), the record-on-`GET` startup error and `415`, missing `string`, unused constructor dependency created for every controller request (the outline's "even on `415`" didn't apply to this endpoint and was dropped), empty `404` from `TypedResults` in a controller, XML only from the controller, `401` and `no-store` in both, `AmbiguousMatchException`, both test suites (integration tests pass in both; the controller unit test without `ControllerContext` fails with `NullReferenceException`). Measurements are the research's raw load-test and startup logs (`out/load-ping.txt`, `out/load-task2.txt`, `out/load-task-c4.txt`, `out/startup.txt`), not rerun; the gap at full EF Core load is stated as 10 to 15%. Native AOT figures come from the research's publish and run logs. Astro check reports no diagnostics, the production build excludes the draft, and the development preview renders all fourteen internal anchors and three article links.

**Publication status (2026-10-19):** loozo said "Good to publish". Removed only the draft flag. Committed only the article and pushed to `origin/main`; GitHub Pages run succeeded. Live checks: the article, `/backend/` (thirteen articles), and RSS return `200`, and its three article links are live.

## Agreed outline: An OpenAPI spec that matches the code

Backend track, article 8, the second comparison article. Agreed with loozo on 2026-10-19: "Good to draft", which approves the outline with the recommended decisions (`responses` excerpts plus a table and real diffs, one `401` operation transformer, the CI `git diff --exit-code` check, one docs UI sentence, every fix in both styles with typed results available to both in .NET 10 and attributes kept as a valid controller path with their review blind spot stated, the `init`-property record only in the request-schema section, two-line authorization, an explicit `500` problem response with `default` in one sentence, the typed controller's empty `404` stated as a tradeoff, and the section 11 contrast framed as attributes against typed results rather than controllers against minimal APIs) and authorizes the draft. Outline research by a helper agent against aspnetcore-10.0 docs and dotnet/aspnetcore v10.0.13 source, with runs on .NET SDK 10.0.402.

**Working title:** The spec says 200, the endpoint sends 204: an OpenAPI document that matches your ASP.NET Core code.

**Reader outcome:** Predict what ASP.NET Core writes into an OpenAPI document for each style and why; find where document and code disagree; declare the responses code, middleware, and framework send; know what attributes, analyzers, conventions, typed results, and transformers guarantee; generate the document at build time so API changes show up in review.

**Running example:** The previous article's two copies of the task board API plus `Microsoft.AspNetCore.OpenApi`, `AddOpenApi()`, and `MapOpenApi()`.

### Sections

1. **Opening: the spec says 200, the endpoint sends 204.** Controller `PATCH` documents only `200`; real `204`, `404`, `412`, `428`.
2. **Set up the example.** Versions; OpenAPI 3.1.1; the template's Development-only `if`; integer schema noise explained once.
3. **What the document is for, and where its response list comes from.** Misconception "generated, so always right"; API explorer mechanism; default `200`.
4. **The task board's document, endpoint by endpoint.** Table of documented against sent; misconception "returning `IResult` documents itself"; `ProblemHttpResult` carries no status.
5. **Declaring responses by hand.** Attributes and `Produces…`; no compile-time checks; drift demo; declaring any response removes the inferred `200`; content types.
6. **API analyzers and conventions for controllers.** What `API1000` flags and misses; `ASPDEPR007`; conventions and parameter counts.
7. **Typed results describe themselves, in both styles.** .NET 10 controller support; limits for `412` and `428`; the typed controller's empty `404`.
8. **Responses your handler never sends.** Binding and validation `400`, status-code-pages `404` body, routing `415`, `401`, unhandled `500`; no `Produces` on groups.
9. **One transformer for responses that follow from metadata.** The `401` operation transformer; `WithOpenApi()` deprecated.
10. **Request schemas can drift too.** Positional record attributes missing from the document; `init`-property record works.
11. **Generate the document at build time and review the diff.** `Microsoft.Extensions.ApiDescription.Server`, `OpenApiDocumentsDirectory`, the build runs `Program.cs`, captured diffs, CI check, tools named, docs UI misconception.
12. **Closing: back to the 200.** Answer, checklist table, four-question quiz.

### Boundaries

Out of scope: security schemes, XML comments, schema and document transformers, versioned documents and YAML, client generation, docs UI setup, breaking-change tooling beyond naming it, Swashbuckle and NSwag, spec-first design. No verdict between styles. No mentions of unwritten articles.

### Docs problems to follow runs or source on

1. `Produces(...)` isn't available on `RouteGroupBuilder` (CS1929).
2. Pages disagree about typed results in controllers; they work since .NET 10 (PR #60096).
3. `MapOpenApi()` isn't restricted to Development; the template's `if` is.
4. The build-time document path is described inconsistently; observed `obj/<project>.json` without the property.
5. The `ASPDEPR007` help link redirects to a search engine.
6. `[ProducesDefault]` doesn't exist; `[ProducesDefaultResponseType]` does.
7. The authorization transformer sample uses the Microsoft.OpenApi 1.x API.
8. "Only IEndpointMetadataProvider return types create a responses entry" is imprecise.
9. No page says declaring any response suppresses the inferred `200`.
10. The analyzers page doesn't say `API1000` can't see status codes passed as arguments.

**Publication status (2026-10-19):** loozo approved publication ("Good to publish"). Published in commit `1ff9e03` with the draft flag removed. Astro check reports no diagnostics, the GitHub Pages run succeeded, and the live page, the backend index (14 articles), the RSS feed, all twelve internal anchors, and five article links return or resolve correctly.

**Draft verification:** Regenerated every main document with build-time generation in copies under `/tmp/dump-aspnet-article/openapi`: the base minimal and controller documents (the endpoint table), the minimal version with `Produces…` calls, the controller with attributes, and the typed controller (identical to the minimal document). Rerun: the attribute drift (document unchanged, `git diff --stat` shows only `TasksController.cs`), the typed minimal and typed controller changes (both show `openapi/TaskBoard.json` in the diff with `204` becoming `200` and a `TaskSummary` schema), `git diff --exit-code` exiting `1`, the API analyzers (`API1000` for `201`, `204`, `404`, nothing for `412` and `428`, plus `ASPDEPR007`), `ActionResult<T>` with only a `404` attribute documenting only `404`, the `401` transformer in both styles, the `init`-property `NewTask` (`required: ["title"]`, `maxLength: 200`, validation `400` in both, different errors for a missing title), and the minimal routing `415` problem body. From the outline research's captured runs: the real `PATCH` responses, class-level and group declarations removing the `200`, content types and MVC `[Produces]`, conventions, typed results plus attributes adding up, empty `401`, `500` bodies, `Produces` on groups failing with CS1929, and the positional record's schema. Astro check reports no diagnostics, the production build excludes the draft, and the development preview renders all twelve internal anchors and five article links.

## Agreed outline: Resource-style and action-style endpoints compared

Backend track, article 9, the third comparison article. Agreed with loozo on 2026-10-20: "good to draft", which approves the outline with these decisions: `QUERY` gets the smallest mention possible (two sentences at the end of the `GET`-with-a-body section, no section of its own); the resource-style completion adds `Done` to the existing `TaskEdit`, states that this `PATCH` replaces the editable fields, and names JSON Merge Patch and JSON Patch in one sentence each; minimal APIs only, with no controller note; a short URL-length demo; one short SQL block adding `tags` and `completed_at`; completing a task that's already done answers `204` and changes nothing; the published articles stay unchanged because none of them says `PATCH` applies only the fields sent; files touched per change is dropped as a criterion. Outline research by a helper agent against RFC 9110, RFC 10008, Fielding's posts, the Fetch spec, and dotnet/aspnetcore v10.0.13 source, with runs on .NET SDK 10.0.402, PostgreSQL 18.6, Chromium 152, Node 24, and Angular 22.2.

**Working title:** Same task board, two shapes: resource-style and action-style endpoints in ASP.NET Core.

**Reader outcome:** Define REST as Fielding did and name the style an API actually uses; quote what RFC 9110 and Fielding say about `POST`; explain why `GET` with a body isn't an option; build a search and task completion both ways; predict differences in binding, URL limits, caching, logs, client code, the OpenAPI document, concurrency, and where business rules live; keep shareable filters in the page URL while the API call is a `POST`; tell when each style fits.

**Running example:** The minimal API task board from the previous two articles plus `tags text[]` and `completed_at`. Resource-style: `GET /tasks?done=…&tag=…&assignee=…&dueFrom=…&dueTo=…&text=…` with an `[AsParameters]` record, and `PATCH /tasks/{id}` with `Done` added to `TaskEdit`. Action-style: `POST /tasks/search` with a JSON body, and the existing `POST /tasks/{id}/complete`, now setting `CompletedAt`. Both searches share one filter function and send the same SQL.

### Sections

1. **Opening: a search that outgrew its query string.** The growing `GET` URL; the proposed `POST /tasks/search`; "REST doesn't allow POST here."
2. **Set up the example.** Versions; one short SQL block; the task board already mixes both styles.
3. **Two ways to shape the same API.** Two route lists; resource-style URLs name things, action-style URLs name operations.
4. **What REST means.** Fielding's hypertext requirement as a plain definition; the task board returns no links, so the article says resource-style.
5. **What HTTP and Fielding say about `POST`.** Misconception "REST doesn't allow POST here"; RFC 9110 §9.3.3; safe and idempotent defined; `PATCH` not idempotent (RFC 5789); both Fielding sentences; Azure, Google AIP-136, and Graph.
6. **Why not `GET` with a body.** Misconception "the server accepts it, so it's fine"; `fetch` `TypeError`; Angular status `0`; RFC 9110 §9.3.1; caches key on the URL; two sentences on `QUERY`.
7. **Searching both ways.** Query-string binding (repeated keys, comma lists, `01/11/2026`, nested record fails at startup); JSON body; URL-length demo with Kestrel `414`, then IIS, CloudFront, browsers.
8. **Caching, logs, and history.** Browser cache reuse for `GET` only; query strings in access logs; misconception "a `POST` search can't be bookmarked"; page URL against API request.
9. **Completing a task both ways.** `PATCH` with `Done` replaces the editable fields; Merge Patch and JSON Patch named; `If-Match` and two requests; atomic `POST …/complete`, `204` when already done, stale editor still gets `412`; reopening.
10. **Client code and the OpenAPI document.** `HttpParams` against a JSON body; completion as a field against a named operation; positional `TaskSearch` marks every field required; CORS preflight.
11. **When each fits.** Real lists for both; mixing is normal; no verdict.
12. **Closing: back to the query string.** Answer, checklist table, four-question quiz.

### Boundaries

Out of scope: controllers, building hypermedia, OData, GraphQL, and JSON:API beyond naming them, idempotency keys and retries, authorization setup, pagination and sorting, full-text search, implementing JSON Patch or Merge Patch, versioning, gRPC, and `QUERY` beyond two sentences. No verdict between styles. No mentions of unwritten articles.

### Docs problems to follow runs or source on

1. The binding docs say body inference depends on the HTTP method without listing the methods; `RouteEndpointDataSource.cs` (v10.0.13) lists GET, DELETE, HEAD, OPTIONS, TRACE, and CONNECT as not inferring a body.
2. Microsoft.AspNetCore.OpenApi 10 drops `QUERY` endpoints without a warning (`OpenApiDocumentService.cs`, PR #63092).
3. The Kestrel options page doesn't state limit defaults; the `KestrelServerLimits` API reference does.
4. IIS answers an over-long URL with `404.14` or `404.15`, not `414`.
5. RFC 9111 doesn't use "primary cache key"; that was RFC 7234.
6. Fielding's "method definitions simply don't matter" carries the qualifier "aside from the retrieval:resource duality of GET", and the same post calls `POST` for retrieval of a potential resource not RESTful.

**Publication status (2026-10-20):** loozo approved publication ("good to publish"), covering both this article and the earlier articles' switch to `PUT`. Published in commit `b436e51` with the draft flag removed, after commit `df194f9` switched the transactions, controllers and minimal APIs, and OpenAPI articles to `PUT`. Astro check reports no diagnostics, the GitHub Pages run succeeded, and the live page, the backend index (15 articles), the RSS feed, all twelve internal anchors, and seven article links (including two section anchors) return or resolve correctly; the three updated articles show "Updated Oct 20, 2026" and no `PATCH` mentions.

**Draft verification:** The article's code is a copy of the outline research's project in `/tmp/dump-aspnet-article/endpoints/App`, reworked so both searches share one `init`-property `TaskSearch` record (`[AsParameters]` for `GET`, the JSON body for `POST`), rerun in `Production` against PostgreSQL 18.6. Rerun and quoted: both searches return the same eight tasks with identical SQL; query binding (repeated keys, a comma list matching nothing, `01/12/2026` binding as 12 January, `2026-13-01` and a slash date in JSON answering `400`, names ignoring case); a nested `DateRange` making every request answer `500` with the "Body was inferred" error and failing the build-time document, while the `POST` binds it; Kestrel's `414` at an 8,192-byte request line (582 tags `200`, 583 tags `414` with an empty body) and a 60 KB JSON body answering `200`; `GET` with `[FromBody]` answering `200` from curl, Node `fetch` and Chromium 152 throwing the `TypeError`, Angular 22.2 `HttpClient` reporting status `0`; Chromium reusing the cached `GET` and sending both `POST` requests, a preflight only for the cross-origin JSON `POST`, and the hosting log lines; the `PATCH` with `done` (`428`, `204`, repeat changes only the version, a rename without `done` reopening the task, a body without `title` answering `500`); `POST …/complete` (`204`, repeat `204` unchanged, `404`, a stale editor's `412`, the conditional `UPDATE`); Angular `HttpParams` building repeated keys and both searches returning the same 20 tasks; the completion snippets and the view-to-search mapping; the generated document's operations, query parameter names, and `TaskEdit` and `TaskSearch` schemas. Invariant-culture query parsing confirmed in `RequestDelegateFactory.cs` (v10.0.13). From the outline research, not rerun: IIS and CloudFront limits, Chromium's 2 MB URL limit, nginx access logs, `QUERY` support. Quotes checked against the fetched RFC 9110, RFC 5789, Fielding posts, AIP-136, and the Azure and Graph guidelines. Astro check reports no diagnostics, the production build excludes the draft, and the development preview renders all twelve internal anchors and seven article links, including two section anchors.

**Draft revision (2026-10-20):** loozo asked for the common convention of `PUT` to replace a resource and `PATCH` with `JsonPatchDocument` (RFC 6902) for partial changes, choosing JSON Patch when asked which partial format the article should show. This replaces the agreed decision that the resource-style completion is a replacing `PATCH`. The resource-style side is now `PUT /tasks/{id}` with `TaskEdit(Title, DueOn, Done)` (the earlier articles' edit body, moved to `PUT` with one sentence saying so) and `PATCH /tasks/{id}` with `JsonPatchDocument<TaskEdit>` from `Microsoft.AspNetCore.JsonPatch.SystemTextJson` 10.0.13, applied to a `TaskEdit` built from the current task; both end in a shared `ApplyEdit` that infers completing and reopening. The rename-reopens example moved to `PUT`; the idempotency note, client code, OpenAPI listing, closing table, quiz question 4, and sources changed to match. Rerun: JSON Patch completion `204` with title and due date unchanged, `428` without `If-Match`, `412` with a stale ETag for `PUT` and `PATCH`, `/version` and `/completedAt` paths answering a validation `400`, `application/json` answering `415` (`JsonPatchDocument<T>` adds `AcceptsMetadata` for `application/json-patch+json`), the same patch applied to `TaskItem` changing `id`, `version`, and `completedAt` without errors, the `PUT` rename reopening the task, a `PUT` without `title` answering `500`, Angular `HttpClient` sending the JSON Patch, and the document's generic `JsonPatchDocument` schema. Astro check reports no diagnostics, and the preview renders all twelve internal anchors and seven article links.

**Earlier articles switched to `PUT` (2026-10-20):** To keep the series consistent with `PUT` for replacing and `PATCH` for partial changes, loozo chose to change the task board's edit endpoint from `PATCH` to `PUT` in the published transactions, controllers and minimal APIs, and OpenAPI articles (option 3, over leaving them or adding a note). Changed: `MapPatch` and `[HttpPatch]` to `MapPut` and `[HttpPut]`, curl `-X PUT`, the CORS policy's `WithMethods("GET", "PUT")`, and the prose, table row, and quiz mentions; each article gets `updatedDate: "2026-10-20"`. Article 9 now says the earlier articles' `PUT` already replaces the editable fields and that `Replace` is the renamed `Edit` handler. Rerun with `PUT`: the transactions article's ETag flow (`200` with `"1"`, `204` with `"2"`, the `412` and `428` problem bodies, `204` with `"3"`), its `If-Match` edge cases, and all three CORS policies in Chromium 152 (`ETag` readable only when exposed; without `If-Match` allowed the preflight blocks the `PUT` and the database is unchanged); the controllers article's no-body request (minimal `400`, controller `415`), `428`, `204`, `412`; the OpenAPI article's regenerated base, `Produces…`, attribute, and typed controller documents (identical to the published ones apart from the `patch` key becoming `put`), the controller `PUT`'s real `204`, `404`, `412`, and `428` responses with problem content types, and identical `API1000` warnings. Copies in `/tmp/dump-aspnet-article/tx/Put-*`, `/tmp/dump-controllers-research/Put-*`, and `/tmp/dump-aspnet-article/openapi-put`. Astro check reports no diagnostics, the build shows the updated date on all three pages, and their internal anchors resolve.

## Agreed outline: Layered and sliced code organization compared

Backend track, article 10, the last comparison article. Agreed with loozo on 2026-10-20: "good to draft", accepting every recommended decision: the layered port returns a `TaskSummary` record so the repository projects the search in SQL (rerun after the change); the layered completion shows the measured `500`s without conflict handling, then the reload-and-retry, with two sentences on an atomic repository method and its tradeoff; the rule stays in the service with an anemic entity, and one paragraph covers the rich-entity alternative without building it; one sentence on when a shared `Common` project becomes worth having; both trees in full, change 1 as small excerpts, changes 2 and 3 as diff stats plus one excerpt each, full files collapsed; brief tests (one service unit test, one repository conflict test, one sliced handler test); the mail port is `IMailSender` with an `OutgoingMail` record; one sentence plus `WithTags` on the default OpenAPI tags; minimal APIs only. Outline research by a helper agent against Cockburn, Martin, Bogard, Fowler, Microsoft's architecture e-book, the EF Core testing docs, dotnet/aspnetcore v10.0.13 source, and six templates at exact commits, with runs on .NET SDK 10.0.402 and PostgreSQL 18.6.

**Working title:** Same task board, two layouts: layered and sliced code organization in ASP.NET Core.

**Reader outcome:** Build the same Tasks feature as an Application project plus an Adapter project joined by ports, and as one file per use case; say what the Application project buys and what the compiler enforces; predict what an everyday change touches in each layout and find a feature's code in both; test the completion rule with a fake repository and no database, or against PostgreSQL; put a port and an adapter where something outside the process is involved, whichever layout you use; tell when each layout fits.

**Running example:** The endpoints article's task board, built twice with minimal APIs against the same PostgreSQL database. Layered: `TaskBoard.Tasks.Application` (no framework references: `Model/`, `Ports/In/ITaskService.cs`, `Services/TaskService.cs` holding the rules, `Ports/Out/ITaskRepository.cs` with no `IQueryable` or `DbSet`) and `TaskBoard.Tasks.Adapter` (the host: `In/` endpoints, request and response records, hand-written mapping, ETags; `Out/` `TaskBoardDb` and the EF Core repository). Sliced: one project with a file per use case in `Tasks/`, using `TaskBoardDb` directly. Both are grouped by feature at the top; they differ inside the feature. Three changes applied to both in git: completing a task, adding a priority end to end, and mailing the assignee on completion with `TimeProvider` for the clock.

### Sections

1. **Opening: where does "mail the assignee" go?** A feature request, and where its code goes in each layout.
2. **Set up the example.** Versions; both builds start from the endpoints article's code; one SQL line for `priority`; scope limits once.
3. **Two ways to arrange one feature.** Both trees; Fowler on layering, granularity, and domain modules that are internally layered; Bogard's definition; Microsoft's sentence naming Hexagonal, Ports-and-Adapters, Onion, and Clean Architecture as one family.
4. **Ports and adapters, defined plainly.** Cockburn's port and adapter and his testing motivation; Martin's dependency rule and "no rule that says you must always have just these four"; the build's ports and adapters; misconception "an interface for every class".
5. **What the compiler enforces.** `CS0234` and `CS0246` when the Application project touches EF Core, ASP.NET Core, or an adapter type; `MSB4006` for a reference cycle; `In/` can still use `Out/TaskBoardDb`; sliced gets only access modifiers (`CS0122`); one sentence on architecture tests.
6. **Change 1: completing a task.** Excerpts and diff stats; the Application can't catch EF Core's exception, so the adapter translates it; eight simultaneous completes with and without conflict handling; the atomic-repository alternative in two sentences.
7. **Change 2: adding a priority.** Diff stats; the layered side's extra places are the Application records and the mapping; one sentence on Mapperly.
8. **Change 3: mail and the clock.** The same `IMailSender` port, HTTP adapter, and `TimeProvider` on both sides; diff stats and one excerpt; the mail service being down saves the task, answers `500`, and loses the mail on both sides.
9. **Finding a feature's code.** The files you open for "what happens when a task is completed?"; the completion rule written in two methods in both layouts; Bogard's caveat.
10. **Testing the completion rule.** A `TaskService` unit test with fakes and no database; repository tests against PostgreSQL; the sliced handler against PostgreSQL; what the EF Core testing docs say about repositories and test doubles.
11. **Startup registrations.** Both `Program.cs` files; link the DI article.
12. **When each fits.** Real lists for both; mixing them; no verdict.
13. **Closing: back to the mail.** Answer, checklist table, four-question quiz.

### Boundaries

Out of scope: MediatR beyond one sentence on its 2025 license change, AutoMapper, Mapperly beyond one sentence, specifications, domain events beyond the rich-entity paragraph, DDD aggregates, microservices and modular-monolith mechanics beyond the mixing paragraph, architecture test libraries beyond one sentence, controllers, OpenAPI accuracy beyond the tags sentence, reliable mail delivery, migrations, and full API testing. No verdict between layouts. No mentions of unwritten articles.

### Docs problems to follow runs or source on

1. Microsoft's "Architect Modern Web Applications" e-book tests with the EF Core in-memory provider, which EF Core's testing docs discourage; its index points to a newer guide, and its sample, eShopOnWeb, is archived.
2. The e-book calls the repository pattern the most common way to abstract data access, but its data chapter never mentions repositories.
3. Ardalis's README says the main branch uses .NET 9; the code targets `net10.0`.
4. Jason Taylor's docs say `IApplicationDbContext` avoids coupling handlers to EF Core, but it exposes `DbSet<T>` and the Application project references EF Core.
5. A minimal API endpoint's default OpenAPI tag is the class that declares its handler (`EndpointMetadataApiDescriptionProvider.cs`, v10.0.13); the minimal API docs don't say so.
6. Jason Taylor's template ships an `Infrastructure.IntegrationTests` project that contains only `GlobalUsings.cs`.

**Draft status (2026-10-20):** Written in `src/content/blog/layered-and-sliced-code-organization.md` with `draft: true`; publication isn't authorized.

**Publication status (2026-10-20):** loozo approved publication ("good to publish"). Published in commit `5e5351d` with the draft flag removed. Astro check reports no diagnostics, the GitHub Pages run succeeded, and the live page, the backend index (16 articles, this one first), the RSS feed, all twelve section anchors, and eleven article links (including five section anchors) return or resolve correctly.

**Draft verification:** The article's code is the outline research's two builds, rebuilt as git histories in `/tmp/dump-layered-research/article/{layered,sliced}` with the agreed changes: the layered repository port and service return an Application `TaskSummary` that the repository projects in SQL (the Adapter's own `TaskSummary` and its mapping removed), both route groups call `WithTags("Tasks")`, and the mail record is `OutgoingMail`. Rerun on .NET SDK 10.0.402 and PostgreSQL 18.6 against a freshly seeded database, in `Production`: diff stats per commit (sliced 2, 8, and 10 files; layered 3, 11, and 11 files; 7 production files each for change 3); final counts (layered 20 C# files and 524 lines, sliced 14 and 398); both searches sending `SELECT t.id, t.title, t.done, t.due_on, t.priority, t.tags`; the layered completion's `SELECT` plus version-checked `UPDATE` and the sliced single `UPDATE … WHERE … NOT (t.done)`; create with `High`, default `Normal`, `Urgent` answering `400`; complete `204`, repeat `204` unchanged, missing `404`; eight simultaneous completes in five runs (all `204` on both sides with the retry; layered without it, two to seven `500`s per run, logged as `ConcurrencyConflictException` wrapping `DbUpdateConcurrencyException`); one email per completion through `complete`, `PUT`, and `PATCH`, and one per race; mail service stopped answering `500` with the task saved, a retry `204`, and no email; the compile errors (`CS0234` and `CS0246` for EF Core, ASP.NET Core, and an Adapter type in the Application project; `MSB4006` for a reference cycle; `CS0122` in the sliced build), and builds succeeding for `In/` using `TaskBoardDb` and for `HttpClient` in the Application project; default OpenAPI tags per declaring class (`SearchTasks`, `GetTask`, `CreateTask`, `EditTask`, `CompleteTask`, and `TaskEndpoints`) and a single `Tasks` tag with `WithTags`; tests (layered Application 3 passed in 100 ms, Adapter 2 passed in 630 ms against PostgreSQL; sliced 3 passed in 769 ms). Quotes rechecked against the saved pages of Cockburn, Martin, Bogard, Fowler, the Microsoft e-book, the EF Core testing guide, and the TimeProvider overview, and against the Ardalis and Jason Taylor templates at the recorded commits. Not rerun: the template inspection and MediatR license facts from the outline research; the atomic repository alternative isn't built, and no unit test covers the conflict retry. Astro check reports no diagnostics, the production build excludes the draft, and the development preview renders all twelve section anchors and eleven article links, including five section anchors.

## Agreed outline: Idempotency, retries, and timeouts

Backend track, article 11, the first article written in one style (sliced layout, action-style endpoints, minimal APIs) with one note linking back to the comparisons. Agreed with loozo on 2026-10-20: "good to draft", accepting every recommended decision: the key row and the task are saved in one `SaveChanges` and the unique violation is caught, with a duplicate that arrives mid-flight waiting instead of answering `409`, stated plainly; a replay re-reads the task; the key is optional, with one sentence that an API can require it; expiry is a `delete` older than 24 hours, with scheduling out of scope; the fingerprint is a SHA-256 of the bound `NewTask`; the mail client gets the standard resilience handler plus an `Idempotency-Key` created once per send, with `DisableForUnsafeHttpMethods` as the fallback; Angular gets one paragraph and a short snippet; client-generated ids are a comparison section only; the request timeouts middleware is a demo, not in the final build; EF Core's `EnableRetryOnFailure` is mentioned only; a `Task.Delay` after the save stands in for a slow step; tests run without parallelization; Chromium's resend is described in prose. Outline research by a helper agent against RFC 9110, the expired Idempotency-Key draft -07, Stripe's and AWS's documentation, and source at dotnet/aspnetcore v10.0.13, dotnet/runtime v10.0.13, dotnet/extensions v10.11.0, Polly 8.4.2, EF Core 10.0.4, Npgsql 10.0.3, and Chromium, with runs on .NET SDK 10.0.402, PostgreSQL 18.6, and Chromium 152.

**Working title:** Sent twice, saved twice: retries, idempotency keys, and timeouts in ASP.NET Core.

**Reader outcome:** Explain why a timeout or a dropped connection after the save leads to a duplicate; know which task board requests are already safe to repeat and which parts of the stack retry without being asked; add an idempotency key to `POST /tasks` in PostgreSQL; keep the task board's own calls to the mail service from sending an email twice; choose timeouts and retry rules that don't make things worse.

**Running example:** The sliced task board from the layered and sliced article. `POST /tasks` gets an optional `Idempotency-Key` header backed by an `idempotency_keys` table; `HttpMailSender` gets `AddStandardResilienceHandler` and sends an `Idempotency-Key`.

### Sections

1. **Opening: two "Write the release notes" tasks.** A client times out and retries; the server committed both.
2. **Set up the example.** Versions; one sentence linking the comparison articles; the `Task.Delay` stand-in; scope limits once.
3. **What a timeout tells the client.** The commit happens before the timeout; cancellation doesn't undo it; `499` in the log; three cases the client can't tell apart; double submit.
4. **Which task board requests are safe to repeat.** `GET`, `complete`, `PUT` with `If-Match`, and `POST /tasks`; RFC 9110 §9.2.2.
5. **Who retries without being asked.** `HttpClient`'s stale-connection resend; Chromium's measured resend and Firefox's rule; Angular `retry()` in one sentence; the resilience handler retrying every method; `EnableRetryOnFailure` mentioned.
6. **Idempotency keys.** Mechanism; table, entity, and handler; replay, mid-flight duplicate, different body (`422`), no key, expiry; the expired IETF draft, Stripe, nothing built into ASP.NET Core.
7. **Sending the key.** Create it once outside the retry loop in `HttpClient`; Angular snippet with `crypto.randomUUID()`.
8. **Other ways to make creation safe to repeat.** Client-generated ids with `on conflict do nothing`; natural unique constraints; idempotent actions; comparison table.
9. **When the task board is the client.** The standard handler's defaults; two and three emails; the key fix and `DisableForUnsafeHttpMethods`; one sentence on background delivery being out of scope.
10. **Timeouts at each layer.** `HttpClient`, the handler's two timeouts, the request timeouts middleware (`504` with the task saved), a disconnect cancelling the query, Npgsql's command timeout and `statement_timeout`; table.
11. **Retry rules.** Status codes worth retrying; backoff with jitter; `Retry-After`; retry at one layer.
12. **SQL Server and MySQL notes.** Unique violation numbers, no `ON CONFLICT`, MySQL's documented deadlock, timeout differences.
13. **Closing: back to the duplicate task.** Checklist table and four-question quiz.

### Boundaries

Out of scope: reliable delivery and background jobs (including scheduling key cleanup), authentication and per-user keys, distributed locks, hedging, circuit-breaker tuning, EF Core's retry strategy in the build, and gRPC. No mentions of unwritten articles.

### Docs problems to follow runs or source on

1. `WithRequestTimeout` without `UseRequestTimeouts` silently does nothing, and the middleware's `504` has an empty body even with `AddProblemDetails`.
2. `DisableForUnsafeHttpMethods` is marked experimental, but calling it as an extension method raises no diagnostic; it also stops retries for `PUT` and `DELETE`, which RFC 9110 calls idempotent. The handler's `Retry-After` handling, on by default and not capped by `MaxDelay`, isn't on the Learn page.
3. ASP.NET Core's problem details link `422` to RFC 4918 rather than RFC 9110.
4. "MUST NOT automatically retry" is RFC 7230 wording; RFC 9110 says SHOULD NOT.
5. Angular's HTTP guide recommends `retry()` without a warning about requests that aren't safe to repeat.
6. The Idempotency-Key draft expired without becoming an RFC.

**Draft status (2026-10-20):** Written in `src/content/blog/retries-idempotency-keys-and-timeouts.md` with `draft: true`; publication isn't authorized.

**Draft verification:** The article's code is the layered and sliced article's final sliced build plus three commits in `/tmp/dump-idempotency-research/article/taskboard` (a three-second delay after saving a task, idempotency keys for `POST /tasks` with tests, and the standard resilience handler with an `Idempotency-Key` on `HttpMailSender`); the variants without a handler, without a key, with `DisableForUnsafeHttpMethods`, and with the request timeouts middleware are worktrees next to it. Rerun on .NET SDK 10.0.402, Microsoft.Extensions.Http.Resilience 10.11.0 (Polly 8.4.2), and PostgreSQL 18.6 against a freshly seeded database, in `Production`: a two-second `HttpClient` timeout with two attempts creating two tasks and logging two `499`s with no warnings; a double submit creating two tasks; repeated `complete` (`204`, `204`, one email) and `PUT` (`204`, `412`); the key cases (replay, other spacing and order, different title `422`, a 101-character key `400`, no key, the id gap from rolled-back inserts); a timed-out first attempt followed by a replay; eight simultaneous same-key requests in five runs creating one task each; a request waiting on a `psql` session's uncommitted key (`Lock`, `transactionid`), then creating after a rollback and answering `422` after a commit; expiry by `delete`; `on conflict do nothing` with a client-generated id, including a silently ignored different title; the mail runs (no handler `500` and one email; handler `204` and two emails; `DisableForUnsafeHttpMethods` `500` and one email, compiling without a warning once `Microsoft.Extensions.Http.Resilience` is imported; key and deduplicating stub `204` and one email; 12-second mail service `500` after 31.1 s and three emails, or `204` after 12.2 s and one email with the key); a client disconnect cancelling a waiting `UPDATE` (`499`, "canceling statement due to user request"); the request timeouts middleware (`504` with 0 bytes for a locked task and for a saved task, and no effect without `UseRequestTimeouts`); Npgsql `Command Timeout=2` and `statement_timeout=2000` (`500`, nothing saved, `57014`); `EnableRetryOnFailure` refusing a user-initiated transaction; `HttpClient.Timeout` defaulting to 100 s; `HttpClient` not resending a `POST` on a closed reused connection (`ResponseEnded`) while Chromium 152 resent it and the page saw one `201`; three PostgreSQL sessions inserting one key with the first rolling back (one insert, one unique violation, no deadlock); tests (6 passed). The Angular snippet compiles with Angular 22.2.3 and strict templates. From the outline research, not rerun: Firefox's resend rule (source only), the resilience handler's defaults and the 499 and timeout-middleware source lines, and the SQL Server and MySQL notes (documentation only). Astro check reports no diagnostics, the production build excludes the draft, the development preview resolves all internal anchors and five article links, and the eleven external source links answer `200`.

**Outline revision (2026-10-20):** After reading the first draft, loozo found its point unclear and its flow jumping between topics. Agreed ("good to draft") on a revised outline with one point: a failed request doesn't mean nothing happened, so the receiver of a request that can't safely run twice needs a way to recognize the repeat. Sections: (1) set up the example, with the logging note moved to where the log lines appear; (2) what a timeout tells the client; (3) repeats you don't control: the double click (moved here), Chromium and Firefox resending, `HttpClient` not resending a `POST`, Angular `retry()`, and one sentence on the resilience handler retrying `POST`; (4) which requests are safe to repeat, recapping the endpoints article's terms with a link before the table; (5) idempotency keys: the idea and the expired Internet-Draft up front, the smallest server version without a fingerprint, the client side (.NET loop, Angular) right after, and the opening rerun; (6) reused keys, simultaneous requests, and old keys: the smallest version silently replaying a different request, then the fingerprint and `422`, the key length `400`, the id gap, the concurrent and held-key runs, and expiry; (7) other ways to make creation safe to repeat; (8) when the task board sends the request: the one-line handler, its retry defaults in a sentence, the 1-email and 2-email runs, the key fix and `DisableForUnsafeHttpMethods`; (9) back to the duplicate task. The quiz swaps the retry-rules question for one about creating the key inside the retry loop. Moved out: the handler's full defaults, the slow mail service run, timeouts at each layer (the request timeouts middleware, a disconnect cancelling a query, Npgsql's `Command Timeout`, `statement_timeout`), EF Core's `EnableRetryOnFailure`, retry rules (statuses, backoff and jitter, `Retry-After`, one layer), and the SQL Server and MySQL section apart from the unique-violation error numbers. A separate article on timeouts and retry configuration was considered and parked until this one is published; its runs are recorded in the first draft verification above. Working title: "Sent twice, saved twice: idempotency keys in ASP.NET Core"; the file is now `src/content/blog/idempotency-keys-and-repeated-requests.md`.

**Revised draft status (2026-10-20):** Rewritten in `src/content/blog/idempotency-keys-and-repeated-requests.md` with `draft: true`; publication isn't authorized.

**Revised draft verification:** The scratch history in `/tmp/dump-idempotency-research/article/taskboard` is now branch `article2`: the slow step, the smallest key version (no fingerprint, no key length limit, `Created<TaskDetails>` return type), a commit adding the fingerprint, `422`, and `StringLength(100)`, and the mail commit; its final tree is identical to the first draft's. The smallest version is a worktree at `article/smallest`. Rerun against freshly seeded databases on .NET SDK 10.0.402 and PostgreSQL 18.6, in `Production`: on the smallest version, the no-key two-attempt client (two tasks, two `499`s), a double submit (two tasks), the keyed client (timeout, then `201` for the same task, one row), the curl replays, a different title with the same key returning the first task's `201` and title, and eight simultaneous same-key requests in five runs (one task each); on the final version, after a warm-up request, the replays, `422`, the 101-character key `400`, the id gap (10014 to 10018), a request waiting on a `psql` session's uncommitted key (`Lock`, `transactionid`; `201` after a rollback, `422` after a commit), and expiry; repeated `GET`, `complete`, and `PUT` (`200` and `200`, `204` and `204` with one email, `204` and `412`); the mail runs (no handler `500` and one email with the task saved as done, handler `204` and two emails, handler and key `204` with one email and a duplicate ignored, `DisableForUnsafeHttpMethods` `500` and one email); tests (smallest 5 passed, final 6 passed). The Angular snippet is unchanged from the first draft and was compiled then. Astro check reports no errors, the production build excludes the draft, the development preview resolves all eleven internal anchors and six article links (one with a section anchor), and the six external source links answer `200`.

**Draft edit (2026-10-20):** At loozo's request, the header's history was cut to one plain statement: the name comes from an IETF proposal that expired without becoming a standard, Stripe and other public APIs use it, and ASP.NET Core has nothing built in. Later mentions say "the IETF proposal"; the version and expiry stay in the sources entry. Datatracker rechecked: "Expired Internet-Draft", latest revision -07 from 2025-10-15. Astro check reports no errors.

**Publication status (2026-10-20):** loozo approved publication ("good to publish"). Published in commit `d394416` with the draft flag removed. Astro check reports no errors, the GitHub Pages run succeeded, and the live page, the backend index (17 articles, this one first), the RSS feed, all eleven internal anchors, and six article links (one with a section anchor) return or resolve correctly. The article 11 entry in `article-series.md` now describes the published scope.

## Agreed outline: Changing the schema without breaking anything

Backend track, article 12. Agreed with loozo on 2026-10-20: "good to draft", accepting every recommended decision: the `done` to status scenario; EF Core migrations as the main path with a real section on the same releases as SQL scripts with DbUp and on scaffolded (database-first) models; a baseline generated from the model and recorded as applied, with one paragraph on the measured drift and a `pg_dump --schema-only` comparison; four releases with one rule (a release's migrations run before it starts, after the previous release has fully rolled out), and one paragraph on a synchronization trigger and on folding the final drop into the next release; the lock queue demo, `lock_timeout`, and a short table of instant and rewriting changes with one row each for `CREATE INDEX CONCURRENTLY` and `NOT VALID`; responses keep `done`, computed from the status, and add `status`; the backfill is one `UPDATE` that also bumps `version`, plus a check query, with batching in one paragraph; a bundle per release commit and a `has-pending-model-changes` CI check; one sentence that tests should build their database with migrations; the enum is `TaskItemStatus` stored as an integer; SQL Server and MySQL differences are one-line notes where each comes up, not a section; one sentence on MySQL providers for EF Core 10. Outline research by a helper agent against the EF Core, Npgsql, PostgreSQL 18, SQL Server, and MySQL 8.4 documentation, EF Core v10.0.4 and Npgsql v10.0.3 source, Fowler and Sato's ParallelChange, Sadalage's evolutionary database design, and Ambler's database refactorings, with runs on .NET SDK 10.0.402, dotnet-ef 10.0.4, and PostgreSQL 18.6 against a 1,000,000-task database.

**Working title:** Two versions, one database: changing the schema without breaking the running app.

**Reader outcome:** Add EF Core migrations to an existing database and read what a migration and the snapshot contain; explain why a migration that's correct for the new code breaks the version still running; split a breaking change into expand, migrate, and contract releases that each work next to the one before; run migrations from one runner before a release starts; keep a fast migration from stalling the API with `lock_timeout`; apply the same releases with SQL scripts or a scaffolded model.

**Running example:** The sliced task board from the idempotency keys article with the slow step removed, on the 1,000,000-task database. It moves from hand-run SQL scripts to EF Core migrations with a baseline. The change: `done` becomes `status` (`Todo`, `InProgress`, `Done`) with a new `POST /tasks/{id}/start` action; responses keep `done` and add `status`. Two copies of the app on two ports stand in for a deployment.

### Sections

1. **Opening: the "In progress" column.** One generated migration breaks the running version (`500`, `42703`) and turns every done task into "To do".
2. **Set up the example.** Versions; starting code; the database; two ports as the deployment stand-in; one sentence linking the comparison articles; scope limits once.
3. **Migrations: schema changes as code.** Local tool, Design package, the baseline and its files, the history table, recording the baseline as applied; when the model and the database disagree.
4. **The change that breaks the running version.** The generated drop and add, the warning, the old version's `500`s, the data loss; why both versions run at once; the rule.
5. **Expand, migrate, contract.** ParallelChange and the transition phase; the four-release table.
6. **Release 1: add `status`, write both.**
7. **Release 2: copy the data, switch reads.** `migrationBuilder.Sql` with literal values and semicolons; the measured race and the `version` bump; `start`.
8. **Releases 3 and 4: stop using `done`, then drop it.** The default `done` needs once unmapped; dropping too early; `Down` doesn't restore data; the trigger and folding paragraph.
9. **Running a migration against the live app.** A bundle from one pipeline step; two runners failing; the lock queue and `lock_timeout`; instant and rewriting changes; the CI check; inline SQL Server and MySQL notes.
10. **Without EF migrations.** The releases as DbUp scripts; re-scaffolding and `Ignore`.
11. **Closing: back to the "In progress" column.** Release table, quiz of four questions.

### Boundaries

Out of scope: removing API fields and client versioning, online rewrite tools and partitioning, deployment platforms, rolling back with `Down` beyond the measured data loss, squashing migrations and merging snapshots, seeding, runnable SQL Server and MySQL examples, and updating the test project. No mentions of unwritten articles.

### Docs problems to follow runs or source on

1. EF Core's applying page says the migration lock is held for the whole run; with Npgsql 10.0.3 it's released after each migration and the applied list is read once, so two runners fail with `42P07`.
2. Non-transactional migrations run without the lock, and their history row is inserted outside a transaction.
3. `migrationBuilder.Sql` without a trailing semicolon breaks PostgreSQL idempotent scripts; a concurrent index fails in them.
4. EF Core's data-transformation sample puts add, populate, and drop in one migration; no page mentions old and new versions running at once.
5. No EF Core guidance for adopting migrations on an existing database.
6. The history table's columns are snake_case with EFCore.NamingConventions.
7. PostgreSQL's locking pages don't mention that a waiting `ACCESS EXCLUSIVE` request blocks later reads.

**Draft status (2026-10-20):** Written in `src/content/blog/changing-the-schema-without-breaking-the-app.md` with `draft: true`; publication isn't authorized.

**Draft verification:** The article's code is the outline research's history rebuilt in `/tmp/dump-schema-article/taskboard` (branch `article`: the dotnet-ef local tool and Design package, the baseline, the slow step removed, then releases 1 to 4; branch `naive` for the one-migration change), with the enum renamed to `TaskItemStatus`, the backfill bumping `version`, and every `migrationBuilder.Sql` statement ending in a semicolon. Builds and bundles are in `builds/`, scripts in `scripts/`, the DbUp runner in `dbup/`, the scaffolded model in `dbfirst/`. Rerun on .NET SDK 10.0.402, dotnet-ef 10.0.4, and PostgreSQL 18.6 against fresh copies of the million-task database, in `Production`: `database update` on the existing database (`42P07`); the printed history-table SQL followed by `migrations list` and release 1's bundle; the `pg_dump --schema-only` comparison and the foreign key migration failing on the hand-made database (`42704`) while applying to a migration-built one; the generated drop-and-add with its warning and SQL, the rename's `RENAME COLUMN` without a warning, and the running version failing on the rename with `42703`; the opening (both versions before and after; 799,521 done tasks becoming `Todo`); the whole four-release sequence with two versions running at each step, including release 2 answering `500` on complete after the drop; the backfill race with and without the version bump (`204` leaving `done=false, status=2` against `412`); backfill times of 8 to 15 s on fresh copies with or without the bump; `Command Timeout=5` failing and rolling back, `Command Timeout=0` succeeding; the batched procedure (3.5 s; `2D000` inside a migration's transaction; success with `suppressTransaction: true`); release 3's code answering `500` with `23502` on a migration-built database until release 3's migration ran; `Down` of release 4 leaving every row `done=false`; the idempotent script running twice with semicolons and failing without them, and a concurrent index failing in it while `database update` applied it; the bundle needing `appsettings.json` in its working directory; `has-pending-model-changes` exit codes; two runners (the article's own migrations never collided, because the second runner waited and re-read the history after taking the lock; the outline research's three two-second migrations reproduced the failure at one second apart and not at three); the lock queue (`6.03 s` reads), `lock_timeout` (`1.00 s` reads), and the bundle with `Options=-c lock_timeout=2s` (`55P03`, retry succeeding); lock modes from `pg_locks` and DDL timings on two fresh copies; DbUp with `MarkAsExecuted`, releases 1, 2, and 4, `set local lock_timeout` failing with `55P03`, and a second run doing nothing; scaffolding with and without `Ignore` in `OnModelCreatingPartial`, which survives re-scaffolding. Quotes rechecked against the live EF Core, PostgreSQL 18, SQL Server, Fowler, Sadalage, Ambler, and DbUp pages, the MySQL pages through headless Chromium (curl gets `403`), and NuGet for the MySQL providers. Not rerun: `Database.Migrate()` at startup in two instances (not claimed as measured), and the SQL Server and MySQL behavior itself (documentation only). Astro check reports no errors or warnings, the production build excludes the draft, and the development preview resolves all eleven internal anchors and eight article links (two with section anchors); the external links answer `200` except dev.mysql.com, which answers `403` to scripts.

**Publication status (2026-10-20):** loozo approved publication ("good to publish"). Published in commit `c6d402f` with the draft flag removed. Astro check reports no errors, the GitHub Pages run succeeded, and the live page, the backend index (18 articles, this one first), the RSS feed, all eleven internal anchors, and eight article links (two with section anchors) return or resolve correctly.

## Agreed outline: Authentication

Backend track, article 13. Agreed with loozo on 2026-10-20: "Good to draft", accepting every recommended decision: the opening is the Reports app's token starting a task while audience validation is off; the article covers the API receiving and checking a bearer token, with one section on cookies and tokens that gives RFC 10017's recommendation of a backend for frontend for business apps (not built) and one paragraph on SPAs holding tokens; Keycloak runs in a container started from a realm file with a fixed `--hostname`, with a note that importing over an existing realm is skipped; each client that calls the API gets a hardcoded audience mapper, full scope is off, and clients get an `editor` scope mapping; realm roles are mapped in `JwtBearerEvents.OnTokenValidated` with `MapInboundClaims = false`, `preferred_username` as the name, and `roles` as the role claim, with one sentence on a flat Keycloak mapper; JWT internals are shown with `openssl` (sign, verify, edit a claim) plus a results-only table of refused forged tokens; tests sign tokens with a test key in `WebApplicationFactory`; the OpenAPI security scheme gets at most one sentence; curl gets tokens through the code flow by hand once and then the password grant on a test-only client, stated as forbidden for real apps; `RequireHttpsMetadata` stays at its secure default in configuration and is turned off in the local run command; the 5-minute clock skew is kept and explained; `ValidAlgorithms` is set to RS256; the `at+jwt` type check is a checklist row only. The responses (`401`, `403`, `WWW-Authenticate`, empty bodies) appear in the sections where they first occur rather than in their own section. Outline research by a helper agent against RFC 7515, 7518, 7519, 6750, 7636, 8725, 9068, 9110, 9700, and 10017, OpenID Connect Core, the cookies draft, Microsoft's JwtBearer, claims, and BFF documentation, Keycloak 26.8.1's documentation, and source at dotnet/aspnetcore v10.0.13 and Microsoft.IdentityModel 8.19.2, with runs on .NET SDK 10.0.402, Keycloak 26.8.1 in podman, PostgreSQL 18.6, and Chromium 152.

**Working title:** Signed isn't enough: what an ASP.NET Core API must check in a Keycloak token.

**Reader outcome:** Explain how a request says who sent it with a cookie or a bearer token and what the browser attaches by itself; get a token from Keycloak with the authorization code flow and PKCE; decode a JWT, sign and verify one by hand, and say what a valid signature proves and what it doesn't; configure JwtBearer against Keycloak and name what each check catches; set up Keycloak so access tokens carry the API's audience and only the roles it needs; map `realm_access.roles` so role policies work; read `401`, `403`, and `WWW-Authenticate`; test protected endpoints without Keycloak.

**Running example:** The sliced task board at the end of the schema article, plus `AddJwtBearer`, `RequireAuthorization()` on the `/tasks` group, a `GET /me` endpoint showing what ASP.NET Core built from the token, the role mapping, and one `editor` policy on `POST /tasks`. Keycloak realm `taskboard` with clients `taskboard-api` (the audience), `taskboard-web` (public, PKCE), `taskboard-cli` (local testing only), and `reports` (another app); users `ada` (role `editor`) and `grace` (no role).

### Sections

1. **Opening: the Reports app's token starts Ada's task.** Audience validation off, `204`; with it on, `401`.
2. **Set up the example.** Versions; starting code and the two-line test fix; the Keycloak container; the logging line; one sentence linking the comparison articles; scope limits once.
3. **How a request says who sent it.** Session cookies and bearer tokens, what the browser attaches, request forgery and token theft, `SameSite` and `HttpOnly`, RFC 10017's recommendation, and the API's checks being the same either way.
4. **Getting a token from Keycloak.** Realm, client, user, and role at first use; the code flow with PKCE by hand; the test-only client.
5. **What a JWT signature proves.** Three parts; decoding isn't verifying; signing and verifying by hand; the edited claim; refused forgeries; what the signature doesn't prove.
6. **The smallest working check.** Package, `Authority`, `Audience`, `RequireAuthorization`, discovery and keys, the HTTPS metadata `500`, the opening rerun.
7. **Each check and what it catches.** Signature and algorithm, issuer, audience and Keycloak's mapper, lifetime and clock skew, key rotation; the checklist table.
8. **Roles from `realm_access.roles`.** `/me` before and after, the mapping, one policy, `401` and `403`.
9. **Testing protected endpoints.** A test signing key in `WebApplicationFactory`.
10. **Closing: back to the Reports token.** The checklist; quiz of three or four questions.

### Boundaries

Out of scope: per-task authorization rules, building a backend for frontend and Angular login code, refresh tokens, sessions and logout, revocation and introspection, linking Keycloak users to the `users` table, service-to-service tokens, sender-constrained tokens, running Keycloak in production, several issuers in one API, and ID token validation in the OpenID Connect handler. One sentence on where other identity providers put roles. No mentions of unwritten articles.

### Docs problems to follow runs or source on

1. Since IdentityModel 8.8 the audience error hides the token's audience (`'(null)'`) unless an app context switch is set.
2. Validation failures are logged at Information under `Microsoft.AspNetCore.Authentication`, so the template's `Warning` level hides them.
3. An unreachable metadata endpoint surfaces as an issuer error.
4. After a signature failure, the error description names a claim problem.
5. Keycloak's zero-downtime rotation advice meets JwtBearer's five-minute refresh limit; a deleted key stays trusted until the next automatic refresh.
6. Keycloak's audience documentation doesn't mention the default `aud: account`, and its guide both describes and deprecates full scope.
7. Keycloak's default access token `typ` is `JWT`, not RFC 9068's `at+jwt`, and the switch for it is undocumented in the administration guide.
8. Microsoft's JwtBearer page understates what a basic setup validates and lists `client_id` as required.

**Draft status (2026-10-20):** Written in `src/content/blog/what-an-api-must-check-in-a-token.md` with `draft: true`; publication isn't authorized.

**Draft verification:** The article's code is the outline research's commits rebuilt in `/tmp/dump-auth-article/taskboard` (branch `auth` on the schema article's release 4: the test fix, the smallest JwtBearer setup with `RequireHttpsMetadata` left to its default in configuration and `Microsoft.AspNetCore.Authentication` logged at `Information`, `ValidAlgorithms`, roles with `GET /me` in `Auth/`, and the WebApplicationFactory tests; the OpenAPI commit left out). Rerun against a fresh Keycloak 26.8.1 container started from the realm file, PostgreSQL 18.6, and Chromium 152, with the API in `Production`: the opening (the Reports token starting task 1 with the audience check off, status 0 to 1; `401` "The audience 'empty' is invalid" with it on, logged as IDX10206); no token, a valid token, and `not-a-jwt` (IDX14100); the ID token (`401` "The audience '(null)' is invalid" with the check on, `200` with it off); the HTTPS metadata `500` including `/openapi/v1.json`; signing and verifying by hand with OpenSSL 3.6.4, the edited payload, and a Keycloak token checked with the realm's public key; the six forged tokens; a token from a second realm (`401`, issuer); a second Keycloak container without `--hostname` (`401` for a token fetched through `127.0.0.1`); `PS256`, a token without `exp`, and a future `nbf` against a static issuer whose key was held locally, with and without `ValidAlgorithms`; a 10-second token answering `200` until 297 seconds after `exp` and `401` at 302 seconds; a new key (`401` then `200` 0.3 s later), a passive key published but not used, and an unknown-kid token one second before a rotation keeping new tokens refused until 301 seconds and accepted at 311 seconds; the `at+jwt` client attribute; the code flow with PKCE by hand and the exchange without a verifier; the cookie handler's `Set-Cookie` defaults; `/me` before and after the role mapping; `201`, `403`, `200`, and `401` for the policy; the default OpenAPI document having no security scheme; the realm's 60-second code and 300-second token lifetimes; the printed `podman run` with a relative volume and `Auth__RequireHttpsMetadata=false dotnet run`; ten tests passing with Keycloak stopped. Quotes rechecked against the live RFCs, OpenID Connect Core, Keycloak, Microsoft, and IdentityModel pages. Not rerun: the `IClaimsTransformation` and flat Keycloak mapper variants (one sentence), a deleted key staying trusted up to 12 hours (from the IdentityModel source), Entra ID and Auth0 (documentation only). Astro check reports no errors or warnings, the production build excludes the draft, and the development preview resolves all ten internal anchors and seven article links (two with section anchors); every external link answers `200`.

**Draft edit (2026-10-20):** At loozo's request, the cookies and tokens passage was restructured: each mechanism now says only who attaches it and what its attributes do, followed by two concrete attacks (another site sending a request, and a script injected into the page) tried against both, so that `samesite` answers request forgery and `httponly` answers token theft through XSS, including that an injected script can still send requests with an `httponly` cookie but can't carry it away. Astro check reports no errors.

**Publication status (2026-10-20):** loozo approved publication ("Good to publish"). Published in commit `3112e3e` with the draft flag removed. Astro check reports no errors, the GitHub Pages run succeeded, and the live page, the backend index (19 articles), the RSS feed, all ten internal anchors, and seven article links (two with section anchors) return or resolve correctly. The index lists it fifth: the five articles dated 2026-10-20 sort among themselves by file name, because the index sorts only by `pubDate`.

## Agreed outline: Authorization

Backend track, article 14. Agreed with loozo on 2026-10-20: "good to draft", accepting every recommended decision: the opening is Grace, who has no role, completing Ada's task (`204`, the task done, a completion email to Ada), with Grace's `PUT` shown in the rules section as the second gap and closed by the `editor` policy on `PUT` and `PATCH`; the rule set is reads for anyone signed in, creating and editing for editors, and starting and completing for the task's assignee or any editor, so unassigned tasks are for editors only; the caller's `users` row is found through a new `users.keycloak_id text` column with a unique index, looked up by the token's `sub`, added in one additive migration, with fixed Keycloak user ids for Ada and Grace in the realm file and one paragraph on how real rows get linked; email and a custom claim are rejected with the measured takeovers; the default policy also requires a `sub` claim; the check moves from load-then-check (shown first, with a short subsection on the same check through `IAuthorizationService`) into the `WHERE` of the `UPDATE`, after the race; the null-comparison trap and its guard sit in that section, and the navigation trap gets one short paragraph; `403` rather than `404`, with one paragraph on when `404` fits; the fallback policy is one paragraph with its measured effects, not adopted; read filtering is out, with one sentence; the WebApplicationFactory tests are extended. Outline research by a helper agent against Microsoft's authorization documentation (resource-based, policies, minimal API security, roles, handler dependency injection), EF Core's `ExecuteUpdate`, null semantics, and query filter pages, OWASP API Security Top 10 2023 (API1 and API5) and the Authorization Cheat Sheet, RFC 9110, OpenID Connect Core, PostgreSQL 18's isolation documentation, Keycloak's administration guide, and source at dotnet/aspnetcore v10.0.13, EF Core v10.0.4, Npgsql v10.0.3, and Keycloak 26.8.1, with runs on .NET SDK 10.0.402, Keycloak 26.8.1 in podman, and PostgreSQL 18.6.

**Working title:** Signed in isn't allowed: checking who may change a task in ASP.NET Core.

**Reader outcome:** Tell a rule a role can express ("editors may edit") from one that needs the task's row ("the assignee may complete it"); say what an endpoint policy can see and why it can't check a task; link a token's `sub` to a `users` row and say why email or username won't do; put the per-task check in the `UPDATE` so a change between check and update can't slip through, and avoid EF Core's null-comparison and navigation traps there; tell "missing", "not yours", and "already done" apart and choose between `403` and `404`; test the rules with WebApplicationFactory.

**Running example:** The task board at the end of the authentication article, plus the `keycloak_id` migration, rows for Ada and Grace linked to fixed Keycloak ids, the `editor` policy on `PUT` and `PATCH`, the `sub` requirement in the default policy, the per-task rule in `start` and `complete`, and six new tests. An editor reassigning a task is played by `psql`, since the task board has no endpoint for it.

### Sections

1. **Opening: Grace completes Ada's task.** `204`, done, email to Ada; the API knew it was Grace.
2. **Set up the example.** Versions; starting code; Ada's and Grace's rows and realm ids; one sentence linking the comparison articles; scope limits once.
3. **Who may do what on the task board.** The rule table; what a role can say and what needs the task (OWASP API5 and API1); Grace's `PUT` and the `editor` policy on `PUT` and `PATCH`; the fallback policy paragraph.
4. **What a policy can see.** Requirements and handlers; the policy runs before the handler with the request as its resource; `editor` on `complete` locks Grace out of her own task, and a handler written for a task never runs.
5. **Which users row is the caller.** `sub` against email and a custom claim; the `keycloak_id` column and why it's text; the additive migration with the old build still working; linking Ada and Grace; requiring `sub`.
6. **Checking after loading the task.** Load the assignee, compare, `Forbid`; the answers; the same check through `IAuthorizationService` with a requirement and a handler.
7. **Checking in the statement that changes the task.** The race with a reassignment; the check in the `WHERE` and the race giving `403`; why PostgreSQL rechecks the `WHERE`; the null guard; the navigation trap; `PUT` already closing the gap with its version check.
8. **Missing, not yours, or already done.** The follow-up query; `403` against `404`.
9. **Testing the rules.** WebApplicationFactory tests with linked users, the caller without a row, the existing handler tests needing a user; what tests can't catch.
10. **Closing: back to Grace's request.** `403`, unchanged task, no email; quiz of four questions.

### Boundaries

Out of scope: read restrictions and query filters (one sentence), endpoints that assign or reassign tasks, creating users at first sign-in and admin tooling for linking (one paragraph on linking), Keycloak's authorization services and external policy engines, OAuth scopes as permissions, audit logging, documenting `403` in OpenAPI beyond one sentence, and runnable SQL Server and MySQL examples. No mentions of unwritten articles.

### Docs problems to follow runs or source on

1. Microsoft's resource-based authorization pages have no minimal API example and don't say an endpoint policy's resource is the `HttpContext`, so a handler typed for a task silently never runs.
2. Microsoft's examples identify users by name, which OpenID Connect says must not be used as a unique identifier.
3. The policies page's `RequireAssertion` snippet is a garbled include.
4. The handler dependency injection page doesn't say what a singleton handler using EF Core does in `Production` (39 of 40 concurrent requests answered `500`).
5. `FallbackPolicy`'s XML doc says it's mainly relevant for middleware-based flows; it also turns unknown paths into `401` and protects the OpenAPI document.
6. EF Core's `ExecuteUpdate` concurrency guidance doesn't mention that a navigation in the filter becomes a joined subquery that PostgreSQL rechecks against a stale copy.
7. EF Core's null-semantics page doesn't show a column compared with a null variable becoming `IS NULL`.
8. EF Core's query filters page still calls named filters a preview.

**Draft status (2026-10-20):** Written in `src/content/blog/checking-who-may-change-a-task.md` with `draft: true`; publication isn't authorized. Working title changed to "Valid token, wrong task: checking who may change a task in ASP.NET Core". Two ordering changes against the outline: the load-then-check version compares the assignee's `keycloak_id` with `sub` through the join, so the caller's `users.id` lookup first appears in the `UPDATE` section, where comparing a column of the task row is what the race requires; and the `sub` requirement moved from the users-row section into the load-then-check section, right after the comparison it protects.

**Draft verification:** The article's code is rebuilt in `/tmp/dump-authz-article/taskboard` (branch `authz` on the token article's code: the `editor` policy on `PUT` and `PATCH`, the `keycloak_id` migration, the `sub` requirement, load-then-check, the check in the `UPDATE`, and the tests), with variant branches for the `editor` policy on `complete`, a task-typed handler in an endpoint policy, a handler loading the task from the route, `IAuthorizationService`, matching by email, no `sub` requirement, the navigation in the `WHERE`, no null guard, and the fallback policy. Rerun against a fresh Keycloak 26.8.1 container from the realm file with fixed user ids, PostgreSQL 18.6 copies of the million-task database with Ada and Grace added, and the mail stand-in, with the API in `Production`: the opening (`204`, task 1 done, email to Ada) and Grace's `PUT` (`204`) on the unchanged build; `403` for Grace's `PUT` and `PATCH` after the policy; the `editor` policy on `complete` (`403` on Grace's own task, with the roles requirement logged); the task-typed handler never running in an endpoint policy (the resource was `DefaultHttpContext`); the route-loading handler (`403` for a missing task; as a singleton, 39 of 40 concurrent requests answered `500`, twice; scoped, 40 of 40 `403`; `Development` refusing to start); the migration's SQL and the previous build still answering after it; Grace's email change through the account API and the email-matching build completing user 876's task; the undeclared attribute dropped, the user-editable attribute set to `1001` by Grace, and the admin-only one refusing her with `400`; load-then-check answers and its SQL; a token without `sub` (the `basic` scope removed) completing user 876's task and starting an unassigned one, and `403` everywhere with the default policy; the `IAuthorizationService` variant's answers; the race with `psql` holding a reassignment (load-then-check and `IAuthorizationService` `204` with the email to user 876; the `UPDATE` check `403`, no email); the generated `UPDATE` for Grace and for Ada; a Keycloak user without a `users` row starting an unassigned task (`204` and `IS NULL` without the guard, `403` with it); the navigation's `UPDATE … FROM` subquery completing the reassigned task with `version` left at 3; `PUT` answering `412` in the same race; missing, not yours, and already done (`404`, `403`, `204`); the OpenAPI document listing only `204` and `404`; the fallback policy (`401` for `/openapi/v1.json` and an unknown path without a token, the document public again with `AllowAnonymous`); 16 tests passing, one failing without the guard, and all 16 passing on load-then-check; the closing request (`403`, task 1 unchanged, no email). Quotes rechecked against the live Microsoft, OpenID Connect, PostgreSQL, RFC 9110, and OWASP pages; the Keycloak user-profile quote and the storage id format from the saved guide and Keycloak 26.8.1 source. Not rerun: SQL Server and MySQL behavior (not claimed). Astro check reports no errors or warnings, the production build excludes the draft, and the development preview resolves all ten internal anchors and fourteen article links (eight with section anchors); every external link answers `200`.

**Publication status (2026-10-20):** loozo approved publication ("Good to publish"). Published in commit `84e2b42` with the draft flag removed. Astro check reports no errors, the GitHub Pages run succeeded, and the live page, the backend index (20 articles), the RSS feed, all ten internal anchors, and fourteen article links (eight with section anchors) return or resolve correctly. The index lists it second, after the schema changes article, because articles dated 2026-10-20 sort among themselves by file name.
