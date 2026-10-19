---
title: "How CSS decides where things go"
description: "Work out an element's size and position from normal flow, the box model, flexbox, grid, overflow, and positioning, then debug the layout the browser actually built."
pubDate: "2026-10-02"
updatedDate: "2026-10-15"
tags:
  - css
  - layout
  - angular
audience:
  - frontend
---

You add a task with a long title, and the Done and Remove buttons slide off the edge of the row. You give the main column `1fr` so it takes the leftover space, and it pushes past the side of the page anyway. You put a small count badge in the top-right corner of the task panel, and it shows up in the top-right corner of the whole page.

The usual reaction is to keep changing values until the page looks right. That works until the next long title arrives. It's faster to ask three plain questions about the element that's misbehaving:

- What's laying it out: normal flow, flexbox, or grid?
- Where does its width come from?
- When it says `50%` or `top: 0`, that's 50% of what, and the top of what?

This article answers those questions on a small task page and fixes all three bugs along the way. It reuses the task interface from [HTML, the DOM, and events](/dump/blog/html-dom-and-events/), but the tasks are already written into the HTML and the buttons don't do anything yet. The point here is where things sit on the page.

You'll need to recognize HTML elements and attributes; the DOM article covers those. For CSS, you only need the basic shape of a rule:

```css
.task-panel {
  padding: 16px;
}
```

`.task-panel` is a **selector**: it picks out the elements that have `class="task-panel"`. Inside the braces, `padding` is a **property** and `16px` is its **value**, and the semicolon ends that declaration. Each layout property is explained when it first shows up.

The examples are plain HTML and CSS, so any current browser works. Some snippets are marked **scratch**: try them, look at the result, then delete them. Others are marked **add to `layout.css`**: those stay, and the last section shows the complete file.

## Contents

1. [The layout the browser gives you for free](#the-layout-the-browser-gives-you-for-free)
2. [The box model: content, padding, border, margin](#the-box-model-content-padding-border-margin)
3. [Where a width comes from](#where-a-width-comes-from)
4. [Flexbox: one row of items sharing space](#flexbox-one-row-of-items-sharing-space)
5. [Grid: columns for the whole page](#grid-columns-for-the-whole-page)
6. [Choosing what happens to content that doesn't fit](#choosing-what-happens-to-content-that-doesnt-fit)
7. [Positioning: taking a box out of the flow](#positioning-taking-a-box-out-of-the-flow)
8. [Debugging the layout the browser built](#debugging-the-layout-the-browser-built)
9. [The complete page](#the-complete-page)

## The layout the browser gives you for free

Save this as `index.html`, create an empty `layout.css` file next to it, and open the HTML file in a browser:

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
          <div class="panel-heading">
            <h2 id="tasks-heading">Tasks</h2>
            <span class="task-badge">2 open</span>
          </div>
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

Notice that the page already has a layout, even though `layout.css` is empty. The browser ships with default styles: headings get margins, list items get bullet markers, and inputs and buttons get their usual look.

The default way the browser arranges boxes is called **normal flow**, and it has two kinds of boxes:

- **Block boxes**, like the headings, the `section`, and the `div`s, stack on top of each other, one per line. When nothing sets their width, its value is `auto`, which means "let the layout rules decide". For a block in normal flow, that decision is to stretch across the full width of its parent.
- **Inline boxes**, like words and `span`s, sit next to each other in a line of text and wrap onto the next line when they run out of room.

That's why the input and the Add task button sit side by side: inputs and buttons are inline-level boxes, so they line up like words. They still have their own width and height; "inline" doesn't mean they're plain text.

In normal flow, every box takes up room and pushes the next one along. Make the first task's title longer and everything below it moves down. You never have to calculate a new position for the elements underneath.

### Block and inline are directions too

In English text, the two kinds of boxes also name two directions:

```text
Inline direction: words run left to right along a line
Block direction:  lines and blocks stack top to bottom
```

These directions follow the language's writing mode, so in vertical writing systems they turn. All the examples here use horizontal, left-to-right text, and that's why later sections can say "row" and "column" without qualifying them.

### `display` answers two questions at once

The `display` property controls how a box sits among its neighbors, and how it lays out its own children:

- `display: block`: the box takes a full line, and its children follow normal flow.
- `display: flex`: the box acts like a block on the outside, and its children become flex items.
- `display: inline-flex`: the box sits in a line like a word, and its children are still flex items.

So changing a parent's `display` changes the rules for its direct children only. Their children keep following whatever rules their own parents set.

## The box model: content, padding, border, margin

Every box has four layers, from the inside out:

```text
margin: space outside the border
└─ border: the edge around the box
   └─ padding: space inside the border
      └─ content: text, controls, or child boxes
```

Padding is inside the box, so the background color shows behind it. Margin is outside the box, so it's always transparent. The **border box** is the content plus padding plus border, which is the visible box you'd draw a frame around.

### Calculate the same width two ways

To measure a box, first stop it from stretching across the page. `display: inline-block` makes the panel sit in a line like a word while keeping a width you set. Try this **scratch** rule:

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

With `box-sizing: content-box`, which is the browser's default, `width: 200px` sets the width of the **content** only. Padding and border get added on top:

```text
200px content + 16px left padding + 16px right padding
              +  2px left border  +  2px right border
= 236px border box
```

The two 12px margins add another 24px of space around it, so the panel takes up 260px across.

Now change only `box-sizing` in the scratch rule:

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

With `border-box`, `width: 200px` sets the width of the whole **border box**, and the content gets what's left:

```text
200px border box - 32px horizontal padding - 4px horizontal border
= 164px content
```

Margins still sit outside, so the panel takes up 224px across. (This arithmetic ignores scrollbars and minimum and maximum widths, which come up later.)

Delete the scratch rule before moving on.

### Why `width: 100%` can overflow

Say a parent's content area is 300px wide, and its child has `width: 100%`, 16px of padding on each side, and a 2px border on each side.

With `content-box`, the child's content becomes 300px wide, and then padding and border add 36px more. The child is 336px wide and pokes 36px out of its parent.

With `border-box`, the 100% includes the padding and border, so the child is exactly 300px wide. And in many cases you don't need `width: 100%` at all: a block with `auto` width already fills its parent.

Most projects switch every element to `border-box` so widths mean what they look like they mean. **Add to `layout.css`:**

```css
*,
*::before,
*::after {
  box-sizing: border-box;
}
```

The `*` selector matches every element. `::before` and `::after` are extra boxes CSS can generate inside an element, and they need the rule too.

One more box-model surprise: when two blocks in normal flow sit on top of each other, their vertical margins **collapse** into one gap the size of the larger margin, instead of adding up. A 24px bottom margin above a 16px top margin gives a 24px gap. Flex and grid items don't do this, and they usually space their items with the `gap` property instead.

## Where a width comes from

When nothing sets an element's width, its width is `auto`, and `auto` means "ask the layout rules of the parent". So the answer depends on what's laying the element out:

- A block in normal flow stretches to fill its parent.
- A flex item starts from the size of its content, then grows or shrinks to share the row.
- A grid item fills the column it's placed in.

That's the first question from the introduction in practice: before you can tell where a width comes from, you need to know whether the parent is normal flow, flexbox, or grid.

### Content has a minimum width too

Content pushes back. Text wraps at spaces, so a title like "Read the DOM article" can squeeze down to the width of its longest word, "article". That narrowest possible width is called the **min-content width**: the width of the longest piece that can't be broken.

Now change the first task's title in `index.html` to an identifier with no spaces:

```text
task_abcdefghijklmnopqrstuvwxyz_abcdefghijklmnopqrstuvwxyz_abcdefghijklmnopqrstuvwxyz
```

There's nowhere to break it, so its min-content width is the whole 80-odd characters. Keep it in the HTML for now: it's the test case that triggers the first two bugs, and flexbox and grid both look at min-content width when they decide how small an item may get.

### A quick note on units

Lengths in CSS are always measured against something:

- `px` is a CSS pixel. Browser zoom and high-resolution screens change how many physical dots it covers, so treat it as a fixed size you design with, not a device pixel.
- `rem` is a multiple of the root font size, the font size on the `html` element. With the usual 16px default, `2rem` is 32px. Sizes in `rem` grow when someone increases their browser's font size.
- `%` is a percentage of a reference size, and the reference depends on the property. A percentage `width` is measured against the parent's content width in normal flow; the positioning section shows a case where the reference is somewhere else.
- `vw` and `vh` are hundredths of the **viewport**, the visible area of the browser window. On phones, the browser's toolbars can slide in and out and change that height; `svh` and `dvh` are variants for that situation.

## Flexbox: one row of items sharing space

Start with the text input and the Add task button. The goal is a row where the button keeps its natural size and the input takes all the remaining space.

**Add to `layout.css`:**

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

Here's what to notice:

- `.task-entry` is the **flex container**, because it has `display: flex`. Its direct children, the input and the button, are **flex items**. The label sits outside `.task-entry`, so it isn't part of the row; `display: block` just puts it on its own line above.
- `gap: 0.75rem` puts space between the items, and only between them.
- `flex: 1` on the input means "grow to fill the free space". `flex: none` on the button means "stay at your natural size".
- `min-width: 0` on the input is there for the same reason the first bug happens. The next few sections explain it.

### Main axis and cross axis

A flex container lines its items up along one direction, called the **main axis**. The direction across it is the **cross axis**:

```text
main axis:  input → button  (left to right)
cross axis: top to bottom, across the row
```

`justify-content` spreads leftover space along the main axis. `align-items` lines the items up along the cross axis, and `center` here keeps the input and button vertically centered against each other.

Set `flex-direction: column` and the main axis turns vertical. So flexbox means "a line of items sharing space", in whichever direction you pick.

### What `flex: 1` is short for

The `flex` property is shorthand for three separate settings:

```css
.task-entry input {
  flex: 1 1 12rem;
}
```

In order, those are:

1. **`flex-grow: 1`**: when there's extra space in the row, this item takes a share of it.
2. **`flex-shrink: 1`**: when the items don't fit, this item gives up some of its size.
3. **`flex-basis: 12rem`**: the item starts at 12rem along the main axis, before any growing or shrinking.

So `flex: 1` is short for `flex: 1 1 0%`: grow, shrink, and start from a basis of `0%`. In this row, where the parent's width is known, that works out to zero, so the input's starting size is nothing and all of the row's free space goes to growing. And `flex: none` is short for `flex: 0 0 auto`: don't grow, don't shrink, and start from the item's own size.

Grow factors divide only the *extra* space, the space left after every item's basis. Two items with `flex-grow: 1` and `flex-grow: 2` that each start at 100px in a 500px row share the leftover 300px as 100px and 200px, so they end up 200px and 300px wide, not 1:2. Start both from a zero basis, as `flex: 1` and `flex: 2` do, and all the space is extra, so the final widths follow the 1:2 factors, as long as padding, borders, and minimum or maximum sizes don't get in the way.

### The title that refuses to shrink

Now give the task rows the same treatment. **Add to `layout.css`:**

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

With the long identifier still in the first row, make the browser window narrow. The Done and Remove buttons slide out of the row. This is the first bug from the introduction, and `flex: 1` says the title is allowed to shrink, so why doesn't it?

Every flex item has a hidden lower limit. Its `min-width` defaults to `auto`, and for a flex item, `auto` means "no narrower than your min-content width". The identifier's min-content width is the whole string, so the title stops shrinking there and pushes the buttons out.

The fix is to lift that limit on the item that has to shrink. **Add to `layout.css`:**

```css
.task-title {
  min-width: 0;
}
```

The buttons come back into the row. The text inside the title still doesn't wrap, though; it now spills out of a box that's narrower than it. `min-width: 0` lets the **box** shrink, and deciding what happens to the **text** is a separate step, covered in the overflow section.

The same limit explains the input: text inputs have a built-in default width, and `min-width: 0` lets the input shrink below it on narrow screens.

### Let items wrap instead of squeezing

A flex row stays on one line unless you allow it to wrap. With `flex-wrap: wrap`, an item that doesn't fit at its starting size moves to the next line instead.

Combine that with a 12rem starting size, and the input and Add task button share a line when there's room and stack when there isn't. The same works for the task rows: on a narrow screen, the actions drop below the title.

**Update `layout.css`:** replace the flex rules from this section with this combined version, which keeps everything above and adds wrapping:

```css
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

.task-actions {
  display: flex;
  flex-wrap: wrap;
  flex: none;
  max-width: 100%;
  gap: 0.5rem;
}
```

The action group can now wrap its own two buttons too, and `max-width: 100%` keeps it from being wider than its row. That only matters at very narrow widths or with large text, but those are exactly the cases that break layouts.

## Grid: columns for the whole page

Now step out from a single row to the whole page. The sidebar and the task panel should sit side by side as two columns, and that's what grid is for.

**Add to `layout.css`:**

```css
.workspace {
  display: grid;
  grid-template-columns: 12rem 1fr;
  gap: 1rem;
}
```

`.workspace` is the **grid container**, and its two direct children, the sidebar and the task panel, are **grid items**. `grid-template-columns` defines two columns, which grid calls **tracks**: a fixed 12rem track and a `1fr` track. The browser places the items into the tracks in the order they appear in the HTML.

### `fr` takes a share of the remaining space

An `fr` is one share of the space left over after the fixed tracks and gaps are taken out. Say `.workspace` is 768px wide and the root font size is 16px, so the sidebar track is 12rem (192px) and the gap is 1rem (16px):

```text
768px - 192px sidebar - 16px gap = 560px for the 1fr track
```

With `1fr 2fr`, two flexible tracks would split that space one part to two.

### Why `1fr` can still overflow

Narrow the window with the long identifier still in the task list. The task panel grows past the edge of the page instead of fitting into the leftover space. This is the second bug from the introduction.

It's the same hidden limit as in flexbox. A plain `1fr` track is really `minmax(auto, 1fr)`: "at least as wide as the widest content inside it, at most one share". The identifier is wide, so the track won't go below it.

Set the lower limit yourself. **Update `layout.css`:** change the `.workspace` columns to:

```css
.workspace {
  display: grid;
  grid-template-columns: 12rem minmax(0, 1fr);
  gap: 1rem;
}
```

`minmax(0, 1fr)` means "at least zero, at most one share". Now the track fits the space, and the text inside the task panel needs the same treatment the title box did: a decision about what happens to text that doesn't fit. `min-width: 0` in flexbox and `minmax(0, 1fr)` in grid are the same idea. Allowing the box to get smaller and deciding what to do with its content are two separate steps.

### One column on narrow screens

On a phone, two columns side by side leave too little room for either. A **media query** applies rules only when a condition is true, such as the viewport being at least a certain width. **Update `layout.css`:** replace the `.workspace` rule with a single column by default, plus two columns on wider screens:

```css
.workspace {
  display: grid;
  grid-template-columns: minmax(0, 1fr);
  gap: 1rem;
}

@media (min-width: 48rem) {
  .workspace {
    grid-template-columns: 12rem minmax(0, 1fr);
  }
}
```

Below 48rem, the sidebar sits above the task panel. From 48rem up, they sit side by side. Two details are easy to miss:

- In a media query, `rem` uses the browser's default font size, not a font size your CSS sets on `html`. With default settings, 48rem is 768px.
- The query checks the width of the viewport, not the width of `.workspace`. If you drop this layout into a narrow box on a wide screen, it still gets two columns.

Pick the breakpoint by narrowing the window until the content looks cramped, not from a list of device sizes.

### Flexbox or grid?

Use flexbox when things line up in one direction, like a row of buttons or a form field next to its button. Use grid when things need to line up in two directions, like a sidebar beside content or a grid of cards. Most pages use both: this one is a grid, and every task row inside it is a flex row.

## Choosing what happens to content that doesn't fit

**Overflow** is content that sticks out of its box. The box itself can be exactly the right size while its text runs past the edge, and that's where the task title is now: the box shrinks correctly, but the identifier spills out.

So now you pick a policy for that content:

- **Wrap** it when the reader needs to see the whole value, like a task title.
- **Scroll** it when its shape matters, like a wide code sample.
- **Truncate** it with an ellipsis when it's a preview and the full value is available somewhere else.
- **Clip** it only when the hidden part really isn't needed. An action button is always needed.

Task titles should stay readable, so wrap them. **Add to `layout.css`:**

```css
.task-title {
  overflow-wrap: anywhere;
}
```

`overflow-wrap: anywhere` lets the browser break the identifier between any two characters. That also shrinks its min-content width to a single character, so the title no longer forces anything wider. Wrapping fixes how the text looks and the size calculation at the same time.

### What the `overflow` values do

The `overflow` property decides what a box does with content that sticks out:

- `visible`, the default, lets content draw outside the box.
- `auto` cuts content off at the box's edge and adds scrollbars when needed.
- `hidden` cuts content off with no scrollbars, but the box can still scroll, for example when JavaScript scrolls it or when the browser brings a focused element inside it into view.
- `clip` cuts content off and the box can't scroll at all.

A box with `auto` or `hidden` is a **scroll container**: a box with its own scrollable area. That matters for sticky positioning later.

### Hiding the problem hides the buttons

When the actions slide out of the row, it's tempting to add `overflow: hidden` to `.task-row`. The page's horizontal scrollbar disappears and the row looks tidy. But Remove is now cut off, and nobody can click it. So before hiding anything, check which box grew too wide and why.

An ellipsis is a choice about presentation, and it's an alternative to wrapping, not an addition to it. As a **scratch** experiment, try this instead of the wrapping rule:

```css
.task-title {
  min-width: 0;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
```

`nowrap` keeps the title on one line, `hidden` cuts off whatever doesn't fit, and `ellipsis` draws "…" where it was cut. Task titles need to be readable in full, so delete this and keep the wrapping rule.

## Positioning: taking a box out of the flow

Normal flow, flexbox, and grid place boxes so they make room for each other. The `position` property lets you move a single box with offsets like `top` and `left`, and some values take the box out of that shared arrangement completely.

The default is `position: static`, which means "no special positioning". On a static box, `top` and `left` do nothing.

### `relative`: shift the box, keep its space

Try this **scratch** rule:

```css
.task-row {
  position: relative;
  top: 8px;
}
```

Each row is laid out as usual, then drawn 8px lower. Its original space stays reserved, and the rows below don't move, so the shifted row can overlap them. Delete the rule afterwards.

`position: relative` with no offsets doesn't move anything, but it does something useful: it makes the box the reference point for absolutely positioned elements inside it. The badge needs exactly that.

### Containing blocks: what offsets are measured against

When a box says `top: 0` or `width: 50%`, the browser measures against a rectangle called the **containing block**. For a block in normal flow, that's its parent's content area, which is why `width: 100%` matched the parent earlier.

Absolutely positioned boxes use a different rule, and that's what causes the third bug.

### `absolute`: the badge in the wrong corner

The HTML already has a count badge next to the Tasks heading. **Add to `layout.css`:**

```css
.task-badge {
  position: absolute;
  top: 1rem;
  right: 1rem;
}
```

`position: absolute` takes the badge out of normal flow, so it no longer takes up space next to the heading. Its `top` and `right` are measured from its containing block. Reload, and the badge jumps to the top-right corner of the whole page. That's the third bug from the introduction.

Here's how the browser picks the containing block for an absolute box:

1. It looks at the badge's parent, `.panel-heading`. That `div` is `position: static`, so it doesn't count.
2. It keeps walking up through `.task-panel`, `.workspace`, `main`, and `body`. They're all static too.
3. It runs out of ancestors, so it uses the **initial containing block**, a rectangle the size of the viewport at the top of the page.

An ancestor counts if its `position` is anything other than `static`. (A few other properties, such as `transform`, also make an element count.) So mark the panel as the reference. **Add to `layout.css`:**

```css
.task-panel {
  position: relative;
}

.panel-heading {
  padding-right: 6rem;
}
```

Now the walk stops at `.task-panel`, and the badge sits 1rem from the panel's top-right corner, measured from the inside of its border. It's positioned against the panel even though its direct parent is `.panel-heading`.

The padding on `.panel-heading` is the price of taking something out of the flow: nothing makes room for the badge automatically anymore, so you reserve the space yourself. Otherwise a long heading would run underneath it on a narrow screen.

### `fixed`: pinned to the window

`position: fixed` also takes a box out of the flow, but its containing block is usually the viewport itself. So a fixed box stays at the same spot on screen while the page scrolls under it, which suits something like a floating help button. (There's one exception: if an ancestor has a `transform`, the fixed box is pinned to that ancestor instead of the viewport.) Like any box outside the flow, a fixed box can cover content, so keep it for a small control that really needs to stay on screen. This page doesn't need one.

### `sticky`: keep the sidebar in view

On a wide screen, a short sidebar beside a long task list scrolls out of view. `position: sticky` keeps it in place: the box stays in normal flow until scrolling would carry it past a threshold, and then it sticks there.

**Update `layout.css`:** add the sticky rule inside the existing media query, so it only applies to the two-column layout:

```css
@media (min-width: 48rem) {
  .workspace {
    grid-template-columns: 12rem minmax(0, 1fr);
  }

  .sidebar {
    position: sticky;
    top: 1rem;
    align-self: start;
  }
}
```

Here's what each line does:

- `top: 1rem` is the threshold: once the sidebar's top edge would scroll to within 1rem of the top of the scrolling area, it stops there. Without an offset like `top`, sticky does nothing.
- `align-self: start` stops the grid from stretching the sidebar to the full height of the row. A sidebar as tall as the task panel would have no room to move.
- The sidebar never leaves its own grid area, so once the bottom of the task panel scrolls past, the sidebar scrolls away with it.

"The scrolling area" is the nearest ancestor that's a scroll container. Usually that's the page itself, but if any ancestor has `overflow: auto` or `overflow: hidden`, the sidebar sticks inside that ancestor instead, which often looks like sticky isn't working at all.

## Debugging the layout the browser built

When the layout is wrong, look at what the browser built before you add another rule. Open DevTools and go through these steps:

1. **Select the element that's misplaced or too wide.** The Elements panel shows the live page, including anything JavaScript or a framework changed.
2. **Check what's laying it out.** Look at its parent's `display`. Is the element in normal flow, a flex item, or a grid item?
3. **Check its size and limits.** The box-model diagram in the Computed panel shows content, padding, border, and margin separately. Look for `min-width` and `max-width`. The flex and grid overlays draw the axes and tracks on the page.
4. **Find what it's measured against.** For an absolute box, which ancestor has a `position` other than `static`? For a sticky box, which ancestor scrolls?
5. **Separate the box from its content.** Is the box too wide, or is the box the right size with text spilling out of it?
6. **Change the rule that's causing it.** Lift a minimum, let text wrap, let items wrap, or choose scrolling on purpose. Then test the whole interaction again, not just whether the scrollbar went away.

The Computed panel shows the final values after the browser combined every rule that applies. A `width` in the Styles panel is only one input to that result.

### Angular components are boxes too

In an Angular app, every component has a **host element**: the element that matches the component's selector, like `<task-details>`. It's a real element in the page, and it takes part in layout like any other.

Two things follow from that. First, a custom tag like `<task-details>` isn't an element the browser knows, so it gets no default styles, and its `display` falls back to the CSS default, `inline`. So a component you expect to behave like a block, with a width, padding, or margins that push its neighbors away, behaves like a word in a sentence instead. (A component whose selector matches a native element, such as `section[task-details]`, keeps that element's usual display, so this only applies to custom tags.) Give the custom tag a display in the component's styles:

```css
:host {
  display: block;
}
```

`:host` selects the component's own host element from inside its styles. (The Angular CLI can add this rule for you: `ng generate component` has a `--display-block` option.)

Second, if a flex row contains `<task-details>` and a button, the flex item is the `<task-details>` host element, not the `span` inside its template. So when the details refuse to shrink, put `min-width: 0` on the host, with `:host { min-width: 0; }`. Changing the inner `span` won't help, because the span isn't the item that's holding the row open.

### Test with awkward content

One screenshot at one width proves very little. Try:

- the long identifier, a title that's a whole sentence, and twenty tasks;
- a narrow window, and a narrow parent on a wide window;
- browser zoom at 200%, and a larger default font size;
- longer button labels, like a translation would produce.

Keep the HTML in a sensible reading order too. Flex `order` and grid placement can move things around visually, but keyboard focus and screen readers still follow the HTML order.

## The complete page

Put the first task's original title back, or leave the identifier in as a test. A few rules are still missing: the ones that frame the page. **Add to `layout.css`:**

```css
body {
  margin: 0;
  font: 1rem/1.5 system-ui;
}

input,
button {
  font: inherit;
}
```

`body` drops the browser's default 8px margin and sets one font for the page. Browsers give inputs and buttons their own font, so `font: inherit` makes them use the page's font too.

**Add to `layout.css`:**

```css
.page {
  max-width: 64rem;
  margin-inline: auto;
  padding: 1rem;
}
```

`.page` caps the content at 64rem wide, and `margin-inline: auto` splits the leftover space between the left and right margins, which centers it.

**Add to `layout.css`:**

```css
.sidebar,
.task-panel {
  padding: 1rem;
  border: 1px solid;
}
```

The sidebar and the task panel get padding and a border so you can see their edges.

**Add to `layout.css`:**

```css
.task-list {
  display: grid;
  gap: 1rem;
  padding: 0;
  list-style: none;
}
```

The task list drops its bullet markers and the indentation that comes with them, and lays the rows out as a one-column grid with a gap between them. The HTML's `role="list"` keeps screen readers announcing it as a list; Safari stops treating a list as a list once its markers are removed with `list-style: none`.

That's everything. The complete file contains every rule marked "add to `layout.css`" in its final version, grouped with short comments:

<details>
<summary>The complete <code>layout.css</code></summary>

```css
/* Box model and page frame */
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

/* Workspace, panels, and badge */
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

.task-panel {
  position: relative;
}

.panel-heading {
  padding-right: 6rem;
}

.task-badge {
  position: absolute;
  top: 1rem;
  right: 1rem;
}

/* Task form and rows */
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

/* Two columns on wider screens */
@media (min-width: 48rem) {
  .workspace {
    grid-template-columns: 12rem minmax(0, 1fr);
  }

  .sidebar {
    position: sticky;
    top: 1rem;
    align-self: start;
  }
}
```

</details>

Each of the three bugs from the introduction now has a cause and a fix. The buttons slid out of the row because a flex item won't shrink below its min-content width until you give it `min-width: 0`. The `1fr` column overflowed because `1fr` has the same content-based minimum, which `minmax(0, 1fr)` removes. And the badge landed in the page's corner because no ancestor had a position, so it measured from the viewport until `.task-panel` got `position: relative`. In each case, the fix came from asking what's laying the element out, where its width comes from, and what its offsets are measured against.

### Check your understanding

1. A flex item with `flex: 1` won't shrink below the width of a long word. What's setting that lower limit, and what removes it?
2. After you change a column to `minmax(0, 1fr)`, the column fits but text still spills out of it. Why, and what's the next decision?
3. A badge with `position: absolute` has a static parent and a grandparent with `position: relative`. Which box are its offsets measured from?

Answers:

1. A flex item's `min-width` defaults to `auto`, which means its min-content width. `min-width: 0` removes the limit.
2. `minmax(0, 1fr)` only lets the track get smaller. The content still needs a policy, such as wrapping with `overflow-wrap: anywhere`.
3. The grandparent. The browser skips static ancestors and uses the nearest one with a `position` other than `static`.

## Sources and further reading

- [MDN: introduction to CSS layout and normal flow](https://developer.mozilla.org/en-US/docs/Learn_web_development/Core/CSS_layout/Introduction)
- [MDN: the box model](https://developer.mozilla.org/en-US/docs/Learn_web_development/Core/Styling_basics/Box_model)
- [MDN: containing blocks](https://developer.mozilla.org/en-US/docs/Web/CSS/Guides/Display/Containing_block)
- [MDN: list styles and accessibility](https://developer.mozilla.org/en-US/docs/Web/CSS/list-style#accessibility)
- [CSS Values and Units: relative lengths and their references](https://drafts.csswg.org/css-values-4/#relative-lengths)
- [CSS Sizing: `box-sizing`](https://drafts.csswg.org/css-sizing-3/#box-sizing)
- [CSS Flexible Box Layout: the `flex` shorthand](https://drafts.csswg.org/css-flexbox-1/#flex-common)
- [CSS Flexible Box Layout: automatic minimum size of flex items](https://drafts.csswg.org/css-flexbox-1/#min-size-auto)
- [CSS Grid Layout: track sizing and flexible tracks](https://drafts.csswg.org/css-grid-1/#track-sizing)
- [CSS Positioned Layout: containing blocks](https://drafts.csswg.org/css-position-3/#def-cb)
- [CSS Positioned Layout: sticky positioning](https://drafts.csswg.org/css-position-3/#stickypos-insets)
- [CSS Overflow: overflow properties](https://drafts.csswg.org/css-overflow-3/#overflow-properties)
- [Angular: component styling and `:host`](https://angular.dev/guide/components/styling)
- [Angular CLI: `ng generate component` options](https://angular.dev/cli/generate/component)
