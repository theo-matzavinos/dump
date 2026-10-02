---
title: "How CSS decides where things go"
description: "Explain an element's size and position through normal flow, the box model, flexbox, grid, overflow, and positioning—then debug the layout the browser actually built."
pubDate: "2026-10-02"
tags:
  - css
  - layout
  - frontend
  - angular
---

An input pushes its button outside the page. A column refuses to shrink even though its width is `1fr`. A badge appears in the corner of the page instead of the corner of its card.

It is tempting to try more CSS until the result looks right. But these problems become easier to explain when we separate three questions:

1. **Arrangement:** Which rules arrange this element and its neighbors?
2. **Size:** Which content, available space, and constraints determine its dimensions?
3. **Reference:** Which box are its percentages or position offsets measured against?

We will reuse the task interface from [HTML, the DOM, and events](/dump/blog/html-dom-and-events/). This time the task data is already in the HTML. We are investigating layout, not wiring up the action buttons.

You only need the basic shape of a CSS rule:

```css
.task-panel {
  padding: 16px;
}
```

`.task-panel` is a **selector**: it selects elements with `class="task-panel"`. Inside the braces, `padding` is a property and `16px` is its value. The declaration ends with a semicolon. We will explain the layout properties as we use them.

## Contents

1. [Layout exists before you write CSS](#layout-exists-before-you-write-css)
2. [The box model explains occupied space](#the-box-model-explains-occupied-space)
3. [Size comes from content, space, and constraints](#size-comes-from-content-space-and-constraints)
4. [Flexbox distributes space along an axis](#flexbox-distributes-space-along-an-axis)
5. [Grid organizes shared rows and columns](#grid-organizes-shared-rows-and-columns)
6. [Overflow is a consequence, not automatically a bug](#overflow-is-a-consequence-not-automatically-a-bug)
7. [Positioning changes the rules](#positioning-changes-the-rules)
8. [Debug the browser's actual layout](#debug-the-browsers-actual-layout)
9. [Put the layout together](#put-the-layout-together)

## Layout exists before you write CSS

Save this as `index.html` beside an initially empty `layout.css` file, then open the HTML in a browser:

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Task layout</title>
    <link rel="stylesheet" href="./layout.css" />
  </head>
  <body>
    <main class="page">
      <h1>Task notes</h1>
      <div class="workspace">
        <aside class="sidebar" aria-labelledby="views-heading">
          <h2 id="views-heading">Views</h2>
          <a href="#tasks-heading">All tasks</a>
        </aside>
        <section class="task-panel" aria-labelledby="tasks-heading">
          <h2 id="tasks-heading">Tasks</h2>
          <form class="task-form" method="get">
            <label for="task-title">Task title</label>
            <div class="task-entry">
              <input id="task-title" name="title" type="text" required />
              <button type="submit">Add task</button>
            </div>
          </form>
          <ul class="task-list" role="list">
            <li class="task-row">
              <span class="task-title">Read the DOM article</span>
              <div class="task-actions">
                <button type="button">Done</button>
                <button type="button">Remove</button>
              </div>
            </li>
            <li class="task-row">
              <span class="task-title">Inspect the task layout</span>
              <div class="task-actions">
                <button type="button">Done</button>
                <button type="button">Remove</button>
              </div>
            </li>
          </ul>
        </section>
      </div>
    </main>
  </body>
</html>
```

The page already has a layout. The browser supplies default styles: headings have margins, list items have markers, and controls have their usual appearance.

Its default arrangement is called **normal flow**:

- **Block boxes**, such as these headings and sections, follow one another vertically. In our example, a typical block with automatic width fills the width available inside its parent.
- **Inline content**, such as words and spans within a line, follows the text direction and wraps into more lines when necessary.

The controls appear beside each other when they fit because inputs and buttons normally participate as inline-level boxes. They still have their own dimensions; “inline” does not mean “just text.”

An element in normal flow contributes to the arrangement around it. Make a paragraph longer, and the following content moves down. We do not need to calculate a new `top` position for every element below it.

### Block and inline describe directions too

In ordinary horizontal English text:

```text
Inline direction: words proceed left → right within a line
Block direction:  additional lines and blocks proceed downward
```

These names follow the document's writing mode. They are not permanent synonyms for horizontal and vertical: vertical writing changes the directions. Our examples use horizontal, left-to-right text.

### `display` has two responsibilities

`display` affects:

1. How the element's box participates in its surroundings.
2. How that box arranges its children.

For example, `display: flex` normally creates a block-level box in its surroundings and a flex layout for its children. `display: inline-flex` uses the same child-layout rules but participates as an inline-level box outside.

Changing a parent's `display` changes the rules for its children. It does not automatically apply the same layout mode to all the elements nested inside them.

**Start with the arrangement you need, not with `position: absolute`.** Normal flow, flexbox, and grid can arrange the main page while allowing it to respond to changing content.

## The box model explains occupied space

A layout box has several distinct parts:

```text
margin: space outside the border
└─ border: the edge around the box
   └─ padding: space inside the border
      └─ content: text, controls, or child boxes
```

Padding belongs inside the box. Margin is outside it. A background normally covers content and padding, not the margin.

The **border box** includes content, padding, and border. A width declaration does not always refer to that whole box.

### Calculate the same width two ways

For this measurement, make the panel an **inline-block**: it participates at inline level but keeps its own box dimensions. Try this temporary rule:

```css
.task-panel {
  display: inline-block;
  box-sizing: content-box;
  width: 200px;
  padding: 16px;
  border: 2px solid;
  margin: 12px;
}
```

Here, `width: 200px` sizes the **content**. The border-box width is:

```text
200px content + 16px left padding + 16px right padding
              +  2px left border  +  2px right border
= 236px border box
```

Adding the two horizontal margins gives 260px across the margin box in this simple example. Margins are not included in the declared width.

Now change only `box-sizing`:

```css
.task-panel {
  display: inline-block;
  box-sizing: border-box;
  width: 200px;
  padding: 16px;
  border: 2px solid;
  margin: 12px;
}
```

The **whole border box** is now 200px wide. The content gets what remains:

```text
200px border box - 32px horizontal padding - 4px horizontal border
= 164px content
```

With its margins, that box occupies 224px horizontally. `border-box` includes padding and borders in the declared size; it does not include margins.

These calculations assume no other minimum or maximum overrides the size and no scrollbar consumes space. Padding and borders also cannot produce a negative content size: if they exceed the declared size, the box still needs room for them.

### Why `width: 100%` can overflow

Suppose an ordinary block parent has a 300px-wide content box. A child using `content-box` has `width: 100%`, 16px padding, and a 2px border on each side.

The content becomes 300px wide, then padding and borders add another 36px. The child's border box is **336px**, not 300px.

With `border-box`, the 100% width includes that padding and border, so the child's border box is 300px. Alternatively, an ordinary block's automatic width can often fill the available space without needing `width: 100%` at all.

Many projects choose a consistent box model:

```css
*,
*::before,
*::after {
  box-sizing: border-box;
}
```

The `*` selector matches all elements. The other two selectors cover generated `::before` and `::after` boxes. This is a useful sizing convention, not a cure for every overflow problem.

### Vertical margins can collapse

In ordinary block flow, adjoining vertical margins can combine rather than add. That is **margin collapsing**.

If one paragraph has `margin-bottom: 24px` and the next has `margin-top: 16px`, those positive margins can form a **24px gap**, not 40px.

Horizontal margins do not collapse this way. Flex and grid items' margins do not collapse either. Parent/child margins have additional collapsing cases; we are not covering every case here.

When a flex or grid container should own the spacing between its items, `gap` expresses that directly. Set the items' margins deliberately too: `gap` does not remove existing margins.

## Size comes from content, space, and constraints

An element's size is not simply the number written next to `width`.

The browser considers its layout mode, available space, content, and minimum/maximum constraints. `width: auto` asks the layout algorithm to determine a size; it does not always mean “as wide as the content.”

For example, an ordinary block with automatic width generally fills its available width. A block's automatic height usually grows with its content. A flex item follows flex sizing rules instead.

### A containing block is a reference rectangle

A **containing block** is the rectangular area the browser uses as a reference for certain sizes and positions.

For the ordinary block boxes in our task page, it is usually the parent's content box. A child's percentage width is measured against the width of that reference box.

The reference is determined by layout rules, not merely by nesting. Absolutely positioned elements use different containing-block rules, which we will follow in the positioning section.

### Minimum and maximum sizes constrain the result

For a simple block panel:

```css
.task-panel {
  width: 100%;
  max-width: 40rem;
  min-width: 0;
}
```

`width: 100%` asks for the reference width. `max-width` caps it at 40rem. `min-width` supplies a lower bound; here we do not impose a positive minimum.

There are corresponding `min-height` and `max-height` properties. A minimum can override a requested width, and if a minimum exceeds a maximum, the minimum wins. We will also see that flex and grid can supply an automatic minimum when we have not explicitly set one.

Replace this experiment when moving to the next layout example; the final stylesheet near the end combines the intended rules without the temporary width caps.

### Units tell you what a size is measured against

- **`px`:** CSS pixels. They are not necessarily physical screen pixels; device scaling and browser zoom affect the mapping.
- **`%`:** a percentage of the reference defined for that property. For our ordinary block's width, that reference is its containing block's width. Do not assume every percentage property uses the same dimension.
- **`rem`:** multiples of the font size on the root element, `html`. With a 16px root font size, `2rem` is 32px; with a 20px root font size, it is 40px.
- **`vw`:** hundredths of the viewport width. The **viewport** is the browser's area for displaying the page, not the full document height.
- **Viewport height units:** `vh` uses the large viewport height. On mobile, browser controls can make the currently visible area smaller. `svh` uses the small viewport height; `dvh` follows the changing viewport height as those controls change.

Use the reference that matches the requirement. A content-based height often serves a task panel better than a fixed viewport height: more tasks should have somewhere to go.

### Percentage height needs a resolvable reference

Suppose a block parent's height is `auto`: it grows according to its children. A normal-flow child's `height: 50%` often cannot resolve against that content-dependent height and behaves like `auto` instead.

If the parent has a definite `height: 200px`, the child's 50% can resolve to 100px. Merely giving the parent `min-height: 200px` is not equivalent to giving it that definite height.

Flex and grid have additional rules for resolving percentage sizes. The useful first question is **“50% of which height, and is that height available to this layout calculation?”**, not “Why is CSS ignoring my number?”

### Content has size requirements too

Replace a task title with a long identifier that contains no spaces:

```text
task_abcdefghijklmnopqrstuvwxyz_abcdefghijklmnopqrstuvwxyz_abcdefghijklmnopqrstuvwxyz
```

Text normally wraps at allowed break points, such as spaces between words. This identifier has no ordinary word breaks, so it can require much more width than a short title.

A box's **intrinsic size** is a size derived from its content rather than simply imposed by an outside width. One important measure is the width needed when the browser uses the available line-break opportunities as much as possible. That is its **min-content width**. An unbreakable string can keep that minimum large.

This matters even when you have not declared a width. Flex and grid use content measurements when deciding how small their items or tracks can become.

## Flexbox distributes space along an axis

For the input and Add task button, we want a row where the input can take remaining space.

Remove the earlier panel-sizing experiments and add this to `layout.css`:

```css
.task-form label {
  display: block;
  margin-bottom: 0.5rem;
}

.task-entry {
  display: flex;
  gap: 0.75rem;
  align-items: center;
}

.task-entry input {
  flex: 1;
  min-width: 0;
}

.task-entry button {
  flex: none;
}
```

`.task-entry` is the **flex container**. Its direct children—the input and button—are the **flex items**. The label is outside that container, so it is not part of this flex row.

### Main and cross axes describe the two directions

The **main axis** is the direction along which flex items are arranged. The **cross axis** runs across it.

For the default `flex-direction: row` in our horizontal writing mode:

```text
main axis:  input → button
cross axis: perpendicular to that row, up/down
```

`justify-content` distributes available space along the main axis. `align-items` aligns the items along the cross axis; `center` aligns the input and button across the row.

Change `flex-direction` to `column`, and the main axis becomes vertical in this writing mode. Flexbox does not inherently mean “horizontal.”

### Basis, growing, and shrinking are separate choices

The `flex` shorthand combines three controls:

```css
.task-entry input {
  flex: 1 1 12rem;
}
```

Read those numbers as:

1. **`flex-grow: 1`:** let the item receive a share of extra space.
2. **`flex-shrink: 1`:** let it give up space when the items do not fit.
3. **`flex-basis: 12rem`:** use 12rem as the starting size along the main axis before distributing space.

With an `auto` basis, an explicit main-axis size such as `width` can supply that starting size; otherwise content sizing contributes.

Growth shares **extra space**, not necessarily the entire final width. If two items start at different sizes, grow factors of 1 and 2 do not automatically produce final widths in a 1:2 ratio. Shrinking also accounts for starting sizes, not only the shrink factors.

`flex: 1` is a convenient grow-and-shrink setup using a zero basis in this row, where the parent provides a known available width. `flex: none` makes the button keep its automatically determined size rather than grow or shrink through flex distribution.

Minimum and maximum sizes still constrain both. Flex distribution does not erase them.

### Why a flexible title can refuse to shrink

Use the same arrangement for a task row:

```css
.task-row {
  display: flex;
  gap: 0.75rem;
  align-items: center;
}

.task-title {
  flex: 1;
}

.task-actions {
  display: flex;
  gap: 0.5rem;
  flex: none;
}
```

Now use the long identifier as the title and narrow the page. It may push the actions outside the row even though `flex: 1` permits shrinking.

By default, a flex item's `min-width` is `auto`. In this ordinary horizontal row with visible overflow, that can become a **content-based minimum**: the title is not allowed to shrink below the width its content requires.

Setting a shrink factor did not remove that minimum. To permit a smaller title box, add:

```css
.task-title {
  min-width: 0;
}
```

This allows the **box** to shrink. It does not, by itself, make the long text wrap. We still need to choose how to handle that text in the overflow section.

The minimum-size rules have other cases, including scrolling items. The lesson is not “add `min-width: 0` everywhere”; it is “inspect the minimum on the flex item that must be allowed to shrink.”

### Wrapping can be better than squeezing

Flex rows are single-line by default. With `flex-wrap: wrap`, items can move onto additional lines when their starting sizes do not fit.

For example, an input with a 12rem basis can share a line with Add task when there is room, and move the button onto a second line when there is not.

A wrapped flex container still arranges items along its main axis, one line at a time. It does not make items on different lines share the same column tracks. That is one reason to use grid for other arrangements.

## Grid organizes shared rows and columns

For a sidebar beside the task panel, give their shared parent a grid:

```css
.workspace {
  display: grid;
  grid-template-columns: 12rem 1fr;
  gap: 1rem;
}
```

`.workspace` is the **grid container**. The sidebar and task panel are its direct children, so they are **grid items**. In this two-child example, automatic placement puts them beside each other in document order.

A **track** is a row or column of the grid. **Grid lines** mark the track boundaries. Two columns have three column lines: the sidebar occupies the first track, and the task panel occupies the second. Grid can coordinate widths across multiple rows as well as heights across columns.

### `fr` shares remaining space

An `fr` unit is a share of the space available for flexible tracks, after accounting for non-flexible tracks and gaps.

For example, if this grid's content width is 768px, the root font is 16px, the sidebar is 12rem (192px), and the gap is 1rem (16px):

```text
768px - 192px sidebar - 16px gap = 560px for the flexible track
```

That is the expected second-column width **if its minimum size allows it**. In a grid with `1fr 2fr`, the flexible tracks normally share that available space in a 1:2 ratio, again subject to their sizing constraints.

### Why `1fr` can still overflow

A plain `1fr` track has an automatic minimum. Content can make that minimum larger than the space we intended to give it.

Put the unbreakable identifier in the task panel. The main track can grow beyond the available width instead of becoming the neat “remaining space” column we expected.

To allow that track to become smaller, change its minimum explicitly:

```css
.workspace {
  display: grid;
  grid-template-columns: 12rem minmax(0, 1fr);
  gap: 1rem;
}
```

`minmax(0, 1fr)` means **a minimum of zero, with a flexible maximum that receives one share**. It removes the track's automatic minimum from this calculation.

The track can now fit the available space, but content can still overflow its smaller box. Just as with `min-width: 0` in flexbox, permitting a smaller layout size and deciding what happens to the content are separate steps.

Flexbox is a good starting point for a row or column of items distributing space along one main direction. Grid is useful when the arrangement needs shared rows and columns. A grid page containing flex task rows is an ordinary combination, not a compromise.

## Overflow is a consequence, not automatically a bug

**Overflow** means something extends beyond a box's bounds. The box can be the intended size while its text extends outside it.

After allowing our title box and grid track to shrink, choose a content policy:

- **Wrap** a task title when readers should be able to read the full value.
- **Scroll** content that should preserve its structure, such as a wide code sample.
- **Truncate** a preview when hiding part of the value is deliberate and readers have a way to access it elsewhere.
- **Clip** content when the hidden part is genuinely not needed. Do not use clipping to silently remove an essential action button.

For our long titles:

```css
.task-title {
  min-width: 0;
  overflow-wrap: anywhere;
}
```

`overflow-wrap: anywhere` permits breaks inside an otherwise unbreakable string. Those break opportunities also affect its intrinsic minimum size. That means wrapping can change the sizing calculation as well as what the text looks like.

### What the overflow values do

- `overflow: visible` allows content to extend outside the box.
- `overflow: auto` clips overflow and allows scrolling when needed.
- `overflow: hidden` clips and hides the overflowing part from ordinary view, but the box can still be scrolled by code or browser behavior such as bringing focused content into view.
- `overflow: clip` clips without making the box a scroll container.

A **scroll container** is a box whose overflowing content can be scrolled. Its visible interior is the viewing area for that content.

This distinction will matter for sticky positioning. `hidden` and `clip` are not interchangeable names for the same behavior.

### Hiding is not the same as fixing

If the actions have been pushed out of a task row, adding `overflow: hidden` to the row can make the page's horizontal scrollbar disappear while also hiding Remove.

The row may look contained, but the required interaction is still broken. Inspect the item sizes and their minimums before choosing what to hide.

Likewise, an ellipsis is a deliberate presentation policy, not a sizing rule by itself:

```css
.task-title {
  min-width: 0;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
```

In the flex row, the title has limited available width. `nowrap` keeps the text on one line, `hidden` clips the excess, and `ellipsis` indicates that text was omitted. This is an **alternative** to wrapping, not something to add to the wrapping version. For these task titles, we will keep the full text visible by wrapping.

## Positioning changes the rules

Normal flow, flexbox, and grid arrange boxes while accounting for one another. The `position` property changes how a particular box is placed.

The default is `static`: no special offset positioning. Properties such as `top` and `left` do not move a statically positioned box.

### `relative`: move visually, keep the original space

```css
.task-row {
  position: relative;
  top: 8px;
}
```

The row is laid out normally, then drawn 8px lower. Its neighbors do not move to make room for that offset. It can overlap something below it while leaving its original space behind.

`position: relative` without offsets does not move the row. It can still establish a reference for absolutely positioned descendants.

### `absolute`: leave flow and use a containing block

Consider a small task-count badge inside this panel fragment:

```html
<section class="task-panel">
  <h2>Tasks</h2>
  <div>
    <span class="task-badge">2</span>
  </div>
</section>
```

```css
.task-panel {
  position: relative;
}

.task-badge {
  position: absolute;
  top: 0.5rem;
  right: 0.5rem;
}
```

The badge is removed from normal flow, so it does not reserve space beside the heading. Its `top` and `right` offsets are measured from its containing block.

Here is how the browser finds that reference:

1. The badge's immediate parent is the inner `div`, which has its default `position: static`.
2. The browser continues upward to `.task-panel`.
3. That panel has `position: relative`, so it establishes the badge's containing block. For this ordinary block ancestor, the reference is its padding box: inside its border and including its padding.

The badge is positioned against the panel, **not its immediate parent**. Other properties can also establish containing blocks; a transform is one example. If no ancestor establishes one, absolute positioning uses the initial containing block, based on the viewport, rather than arbitrarily choosing the nearest parent.

Reserve enough room so the badge does not cover the heading, and test the narrow case. Removing something from flow makes avoiding overlap your responsibility.

Use this as a separate positioning experiment. The complete page stylesheet below keeps its ordinary content in flow and does not require this badge.

### `fixed`: usually stay at a viewport edge

```css
.help-button {
  position: fixed;
  right: 1rem;
  bottom: 1rem;
}
```

A fixed element is also removed from flow. In the common case, its reference is the viewport, so it stays at that corner while the document scrolls.

But an ancestor can establish a different fixed-position containing block. For example, a transformed ancestor can make the fixed descendant use that ancestor instead of the viewport. “Fixed always means viewport-relative” is too absolute.

A fixed control can cover content because the surrounding layout does not reserve space for it. Use it for a genuine persistent control, not to arrange the whole page.

### `sticky`: stay in flow, then constrain movement during scrolling

```css
.sidebar {
  position: sticky;
  top: 1rem;
  align-self: start;
}
```

The sidebar initially occupies its normal place. During scrolling, the browser can shift it to keep its top edge 1rem from the top of its relevant scrolling area, while keeping it within its containing block.

The reference for the sticking threshold is the nearest relevant scroll container's visible area—not automatically the browser window. An ancestor with `overflow: auto` or even `overflow: hidden` can change that reference.

`top: 1rem` supplies a sticking threshold. Without an applicable offset, sticky positioning does not produce that sticking behavior. There also needs to be room to move: a sidebar as tall as its containing block has little or no distance over which to stick.

`align-self: start` keeps this grid item from stretching to fill the row's height. A short sidebar beside a long task panel then has room to remain visible while the panel scrolls past. The sidebar still stops at the bottom boundary of its containing block; it is not fixed forever.

## Debug the browser's actual layout

When a layout is wrong, inspect the result before adding another rule.

1. **Select the overflowing or misplaced element in DevTools.** The Elements panel shows the current DOM, not just the source file.
2. **Identify its parent layout.** Is the element a normal-flow block, a flex item, or a grid item? Look at the parent's `display`.
3. **Inspect dimensions and constraints.** Check width, padding, borders, and minimum/maximum sizes. The box-model diagram separates them; browser flex/grid overlays show axes and tracks.
4. **Find the sizing or positioning reference.** What is the containing block? For sticky positioning, which ancestor owns scrolling?
5. **Separate the box from its content.** Did the box itself grow too wide, or is long text overflowing a correctly sized box?
6. **Change the rule responsible.** Permit shrinking, create break opportunities, wrap controls, or choose scrolling deliberately. Recheck the whole interaction, not just the scrollbar.

The **Computed** panel shows the values the browser resolved after combining applicable styles; layout measurements show the resulting box dimensions. A declared width in the Styles panel is only one input to that result.

### Angular components still produce layout boxes

Suppose a flex task row contains `<task-details>` and an action button. The component's **host element**, `<task-details>`, is the flex item—not the span inside its template.

If that host's automatic minimum prevents shrinking, changing only the inner span's `min-width` may not solve it. Inspect the host and its parents too. A component boundary does not remove an element from the browser's layout calculations.

### Test content and available space, not just one screenshot

Try:

- The long identifier, a multi-sentence title, and more tasks.
- A narrower viewport **and** a narrower parent container.
- Browser zoom and larger text settings.
- Labels and button text that need more room.

Keep the DOM in a meaningful reading and interaction order. Flex `order` and explicit grid placement can change visual order without changing the order used for keyboard navigation and reading. Do not rearrange the interface visually and assume every other way of using it changed too.

## Put the layout together

Return to the original HTML, without the optional badge experiment. This complete `layout.css` combines the layout choices we made:

```css
*,
*::before,
*::after {
  box-sizing: border-box;
}

body {
  margin: 0;
  font: 1rem/1.5 system-ui;
}

input,
button {
  font: inherit;
}

.page {
  max-width: 64rem;
  margin-inline: auto;
  padding: 1rem;
}

.workspace {
  display: grid;
  grid-template-columns: minmax(0, 1fr);
  gap: 1rem;
}

.sidebar,
.task-panel {
  padding: 1rem;
  border: 1px solid;
}

.task-form label {
  display: block;
  margin-bottom: 0.5rem;
}

.task-entry,
.task-row {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.75rem;
}

.task-entry input,
.task-title {
  flex: 1 1 12rem;
  min-width: 0;
}

.task-entry button {
  flex: none;
}

.task-list {
  display: grid;
  gap: 1rem;
  padding: 0;
  list-style: none;
}

.task-title {
  overflow-wrap: anywhere;
}

.task-actions {
  display: flex;
  flex-wrap: wrap;
  flex: none;
  max-width: 100%;
  gap: 0.5rem;
}

@media (min-width: 48rem) {
  .workspace {
    grid-template-columns: 12rem minmax(0, 1fr);
  }
}
```

`margin-inline: auto` shares available horizontal margin between the two sides in this writing mode, centering the capped page. `list-style: none` removes the list markers, and resetting list padding removes their usual indentation.

The HTML's `role="list"` explicitly identifies the task list to tools such as screen readers. This preserves list announcements in Safari, which can otherwise stop recognizing a list when its markers are removed with `list-style: none`.

The layout starts with a single column. The **media query**, `@media (min-width: 48rem)`, applies the two-column arrangement when the viewport is wide enough for this example. In media queries, font-relative units use the browser's initial font size rather than a font size the page sets on `html`.

The query checks the viewport, not the width of `.workspace`. If you reuse the layout inside a narrow container on a wide page, reconsider the column arrangement for that context. Choose a threshold based on the content's needs, not because a device category supposedly begins there.

The form and task rows can wrap independently. Their text can shrink and break, and the action group can wrap its own buttons. We have not used absolute positioning to hold the page together or hidden overflow to make missing controls disappear.

### Closing check

Before changing CSS, can you explain these cases?

1. A 100%-wide child with padding is wider than its parent. Which box did that width size?
2. A `flex: 1` title refuses to shrink. What might its minimum width be based on?
3. A `1fr` column grows beyond the grid. What does `minmax(0, 1fr)` change, and what does it leave unresolved?
4. A badge's immediate parent is static, but its grandparent is relative. Which one supplies the absolute-position reference?
5. A sticky sidebar does not follow page scrolling. Which scroll container is it using, and does it have room to move?

Check your reasoning:

- With `content-box`, the 100% width sizes the content; padding and borders are added outside it. `border-box` includes those edges in the width.
- The flex title's automatic minimum can be based on its content. Allowing shrink through `flex` does not remove that minimum.
- `minmax(0, 1fr)` lets the track shrink below its automatic minimum. The content still needs an overflow policy, such as wrapping.
- In that badge example, the relative grandparent supplies the reference, not the static immediate parent.
- The sticky sidebar may be using an ancestor's scrolling area instead of page scrolling, or may have no space to move within its containing block.

Once you identify those inputs, the next CSS change can be a reasoned choice rather than another guess.

## Sources and further reading

- [MDN: introduction to CSS layout and normal flow](https://developer.mozilla.org/en-US/docs/Learn_web_development/Core/CSS_layout/Introduction)
- [MDN: the box model](https://developer.mozilla.org/en-US/docs/Learn_web_development/Core/Styling_basics/Box_model)
- [MDN: containing blocks](https://developer.mozilla.org/en-US/docs/Web/CSS/Guides/Display/Containing_block)
- [MDN: list styles and accessibility](https://developer.mozilla.org/en-US/docs/Web/CSS/list-style#accessibility)
- [CSS Values and Units: relative lengths and their references](https://drafts.csswg.org/css-values-4/#relative-lengths)
- [CSS Sizing: `box-sizing`](https://drafts.csswg.org/css-sizing-3/#box-sizing)
- [CSS Flexible Box Layout: automatic minimum size of flex items](https://drafts.csswg.org/css-flexbox-1/#min-size-auto)
- [CSS Grid Layout: track sizing and flexible tracks](https://drafts.csswg.org/css-grid-1/#track-sizing)
- [CSS Positioned Layout: containing blocks](https://drafts.csswg.org/css-position-3/#def-cb)
- [CSS Positioned Layout: sticky positioning](https://drafts.csswg.org/css-position-3/#stickypos-insets)
- [CSS Overflow: overflow properties](https://drafts.csswg.org/css-overflow-3/#overflow-properties)
