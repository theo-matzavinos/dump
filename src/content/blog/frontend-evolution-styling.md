---
title: "Components + Tailwind: benefits and tradeoffs"
description: "When you need to change how a task row looks, where do you go and what else changes? Compare plain CSS, Sass, UI libraries, and Angular component styles, then see what Angular components with Tailwind make easier and what they cost."
pubDate: "2026-10-02"
updatedDate: "2026-10-15"
tags:
  - css
  - tailwind
  - angular
  - frontend
---

Say a designer asks for two changes to the task board from [part 1: behavior](/dump/blog/frontend-evolution-behavior/). Each task row needs more breathing room, and completed tasks should look finished while their titles stay readable. Then a third request arrives: the board should offer a light theme as well as the dark one.

None of these touches the task data. They're presentation changes, and they all raise the same question:

> When you need to change how something looks, where do you go, and what else changes with it?

This article answers that question for plain CSS, Sass, a UI library, and Angular component styles. Then it spends most of its time on one combination: Angular components styled with Tailwind utility classes. You'll see which changes that combination makes easier, and what you pay for it.

You'll need the Angular task board from part 1 for the code examples. If flexbox or `rem` units are new to you, read the [CSS layout article](/dump/blog/css-layout-fundamentals/) first, because the examples rely on both. The code uses Angular 22.2.1 and Tailwind CSS 4.3.3.

## Contents

1. [Plain CSS with BEM class names](#plain-css-with-bem-class-names)
2. [Sass generates the CSS for you](#sass-generates-the-css-for-you)
3. [Bootstrap and Angular Material](#bootstrap-and-angular-material)
4. [Angular components keep the row in one place](#angular-components-keep-the-row-in-one-place)
5. [Tailwind utility classes](#tailwind-utility-classes)
6. [Define the shared palette once](#define-the-shared-palette-once)
7. [A task row built from utilities](#a-task-row-built-from-utilities)
8. [What the pairing costs](#what-the-pairing-costs)
9. [Where each styling change goes](#where-each-styling-change-goes)

## Plain CSS with BEM class names

A class name connects an element to the CSS rules that mention that class. Here's one completed row from the task list, as rendered HTML:

```html
<li>
  <label class="task-row task-row--completed">
    <input class="task-row__checkbox" type="checkbox" checked />
    <span class="task-row__title">Read the DOM article</span>
  </label>
</li>
```

And here's a stylesheet for it:

```css
.task-row {
  display: flex;
  align-items: flex-start;
  gap: 0.75rem;
  padding: 0.75rem;
  border: 1px solid #52616c;
  border-radius: 0.5rem;
  background: #181d21;
  color: #f3efe8;
}

.task-row__checkbox {
  flex-shrink: 0;
  width: 1rem;
  height: 1rem;
  margin-top: 0.25rem;
  accent-color: #ff9b6d;
}

.task-row__title {
  min-width: 0;
  overflow-wrap: anywhere;
}

.task-row--completed .task-row__title {
  color: #b8b0a5;
  text-decoration: line-through;
}

.task-row__checkbox:focus-visible {
  outline: 2px solid #ff9b6d;
  outline-offset: 2px;
}
```

Notice the fourth rule. A space between two selectors means "inside", so `.task-row--completed .task-row__title` matches a title that sits inside a completed row. That's how the completed state reaches the title: the state class goes on the row, and the rule connects it to the title.

Both the third and the fourth rule match a completed title. When two rules set the same property on the same element, the browser has to pick one, and the set of rules it uses to pick is called the **cascade**. One of those rules is specificity: a selector with two classes beats a selector with one, wherever each sits in the file. So if `.task-row__title` also set a `color`, the completed rule's gray would still win on completed titles.

The completed title keeps its text and gets a line through it, so completion doesn't rely on color alone. The title can also wrap (`overflow-wrap: anywhere`) instead of pushing the row wider than the list.

This is a snapshot. In the real board, code has to keep the `task-row--completed` class in step with the task's `done` value, the same way part 1 kept the remaining count in step with the tasks.

The class names follow **BEM**, short for Block, Element, Modifier:

- `task-row` is the block: a piece of the interface that makes sense on its own.
- `task-row__title` is an element: a part of that block. Here "element" is a BEM naming role, so it doesn't mean an HTML element.
- `task-row--completed` is a modifier: a variation or state of the block.

So where do you go for the three changes?

- **More breathing room:** open the stylesheet, find `.task-row`, and edit `gap` and `padding`. Every element with that class changes. To know what else changes, you search the HTML for `task-row` and hope nobody reused the class for something else.
- **Completed look:** edit the fourth rule. The class that turns it on lives in the markup, so the condition and the presentation sit in different files.
- **Light theme:** the colors are repeated hex values, so you either hunt for each one or replace them with shared CSS variables first.

BEM names make that search easier, because `task-row__title` tells you where the element belongs. But the browser doesn't enforce the convention. A rule such as `.sidebar span { color: red; }` in some other file still reaches the title if the row ends up inside a sidebar.

## Sass generates the CSS for you

A **preprocessor** is a program that runs before your site is served and turns another language into plain CSS. Browsers only read CSS, so the preprocessor's output is what they actually get. **Sass** is the most common one, and **SCSS** is its CSS-like syntax, usually saved in `.scss` files.

Say the row needs two spacing variants. Instead of writing two nearly identical rules, the Sass source can list the variants once and generate a rule for each:

```scss
$densities: (
  compact: 0.5rem,
  comfortable: 0.75rem,
);

@each $name, $padding in $densities {
  .task-row--#{$name} {
    padding: $padding;
  }
}
```

`$densities` is a map that pairs each name with a value. `@each` repeats the block once per pair, and `#{$name}` inserts the name into the selector. The output is ordinary CSS:

```css
.task-row--compact {
  padding: 0.5rem;
}

.task-row--comfortable {
  padding: 0.75rem;
}
```

So Sass saves typing. It doesn't change how the browser applies styles, because by the time the browser sees anything, it's plain CSS with the same selectors and the same cascade. For the three changes, you go to the same place as before, and the same things change.

Modern CSS has also caught up on two of Sass's classic reasons to exist: custom properties share values such as colors, and nesting groups related selectors. So reach for Sass when you need its extra features, such as loops and mixins, rather than by default.

## Bootstrap and Angular Material

A UI library hands you a finished set of design decisions, so you don't design every control from scratch.

With Bootstrap 5.3, a task row can use Bootstrap's own classes:

```html
<li class="list-group-item bg-body-tertiary text-body">
  <label class="d-flex align-items-start gap-3 p-2">
    <input class="form-check-input flex-shrink-0" type="checkbox" checked />
    <span class="text-break text-decoration-line-through">Read the DOM article</span>
  </label>
</li>
```

This assumes Bootstrap's stylesheet is loaded and the row sits in a list with `class="list-group"`. For dark mode, Bootstrap 5.3 reads `data-bs-theme="dark"` on the `<html>` element, and classes such as `bg-body-tertiary` switch to their dark colors.

Angular Material goes further. It ships Angular components that implement controls and their interaction, styled to follow Google's Material Design. You customize it through its theming API, which sets colors, typography, and density (the spacing inside components) for every Material component at once. The [theming guide](https://material.angular.dev/guide/theming) shows the setup.

So where do you go?

- **More breathing room** and **light theme:** you change a setting the library supports, such as a Bootstrap Sass variable or CSS variable, or a Material theme value. That's normal use, and it changes every control that reads the setting.
- **Completed look:** easy if the library has a class for it, like Bootstrap's `text-decoration-line-through`.

The trouble starts when your design doesn't match the library's. With Tailwind, covered below, you start from a blank page and build the look your designer drew. With a library you start from its look and adjust it. If your design is close, that's a head start. If it's far off, you spend your time overriding the library's styles. Angular Material's documentation calls its components' internal HTML structure and CSS classes private implementation details, so a selector that reaches into them can break when you update the library.

Bootstrap also has **utility classes**: classes that each do one small styling job, such as `d-flex`, which sets `display: flex`, and `gap-3`, which sets the space between flex items. So styling an element by putting small classes on it isn't unique to Tailwind.

## Angular components keep the row in one place

All the approaches so far share styles. A shared CSS class gives every row the same declarations, but each list still has its own copy of the row's HTML, its checkbox label, and its event handling. Change one copy and the others drift.

An Angular **component** puts all of that in one place. The board renders a `<task-row>` for each task, and every one of them comes from the same implementation:

```text
TaskBoard
  keeps the tasks, the filter, and the remaining count
       ↓ passes one task
TaskRow
  renders the checkbox and title, with their styles
       ↑ reports the new done value
TaskBoard
  updates its task list
```

The row only displays the task it receives. The list of tasks still lives in the board, and the board decides what happens when a checkbox changes.

This gives every change a predictable reach. Edit the row component, and all its instances change, which is the point. If one screen really needs a different row, give the component an explicit variant instead of overriding it from a distant stylesheet.

Make components for things your product has names for, like a task row. A generic "box with padding and a border" component with a dozen options tends to become harder to change than the CSS it replaced.

### Component styles stay with the component

Components don't need Tailwind to keep styles local. An Angular component can carry its own CSS in `styles`, or in a file next to it referenced by `styleUrl`. Here's a tiny component, separate from the task board, that shows what Angular does with that CSS:

```ts
import { Component } from "@angular/core";

@Component({
  selector: "task-title",
  template: `<span class="title">Read the DOM article</span>`,
  styles: `
    .title {
      font-weight: 600;
    }
  `,
})
export class TaskTitle {}
```

A global `.title` rule would match every element with that class anywhere on the page. Angular narrows this one without a longer class name:

1. It adds a generated attribute to every element in the component's template. The `title` class stays as it is.
2. It rewrites the component's CSS selector to require that attribute too.
3. The browser applies the rule only to elements that have both the class and the attribute.

The rendered markup looks roughly like this, with `example` standing in for the identifier Angular generates:

```html
<task-title _nghost-example>
  <span class="title" _ngcontent-example>Read the DOM article</span>
</task-title>
```

And the rule becomes:

```css
.title[_ngcontent-example] {
  font-weight: 600;
}
```

In CSS, `[x]` means "has an attribute named x". So this rule matches elements with the `title` class *and* the `_ngcontent-example` attribute, and only this component's template elements have that attribute. (`_nghost-example` marks the component's own `<task-title>` element; you can ignore it here.) Angular calls this **emulated view encapsulation**, and it's the default.

The protection only works in one direction. The component's `.title` rule won't leak out to other components. But if someone writes `.title { color: red; }` in the global `styles.css`, it still hits this span, because the span still has `class="title"`.

So with components, the answer to "where do you go?" becomes "the component file", and the change reaches every instance of that component. You get that **locality**, meaning the code you change sits next to the thing it affects, and that reuse from components, with or without Tailwind. What's left is everything inside the component: you still name classes, keep the CSS in step with the template, and repeat values such as `#52616c` across components unless you share them somehow. That's the part Tailwind changes.

## Tailwind utility classes

Tailwind is built around utility classes. You style an element by putting several of them on it, each doing one job, such as setting padding or making the element a flex container. Tailwind scans your source files for the class names you use and generates CSS for those classes only.

Here's the outside of a task row:

```html
<label class="flex items-start gap-3 rounded-lg border p-3">
  <!-- The checkbox and title go here. -->
</label>
```

Each class maps to a small piece of CSS:

- `flex` sets `display: flex`.
- `items-start` sets `align-items: flex-start`, so the checkbox and the title line up at the top instead of stretching to the same height.
- `gap-3` puts three spacing steps between the flex items.
- `p-3` adds three spacing steps of padding.
- `rounded-lg` uses Tailwind's large corner radius.
- `border` adds a 1px border.

A spacing step is `0.25rem` by default, so three steps are `0.75rem`. At the browser's default root font size of `16px`, that's `12px`. Here's roughly what Tailwind generates for the two spacing classes:

```css
.gap-3 {
  gap: calc(var(--spacing) * 3);
}

.p-3 {
  padding: calc(var(--spacing) * 3);
}
```

`--spacing` is a CSS variable that holds the spacing step. It's still plain CSS: the browser lays out the flex items, resolves `rem`, and runs the cascade exactly as it did for the BEM stylesheet. Tailwind writes that CSS for you from the class names.

Notice what's missing from the example: colors. The row needs a surface color, a text color, and a border color that all switch with the theme. Those come from a palette you define once.

## Define the shared palette once

To set up Tailwind in an Angular project, follow the [Tailwind installation guide for Angular](https://tailwindcss.com/docs/installation/framework-guides/angular). It adds the packages and an `@import "tailwindcss";` line to your global stylesheet, usually `src/styles.css`.

Before the palette itself, two CSS terms. A **custom property** is a CSS variable: a name starting with `--` that holds a value, read back with `var(...)`. Custom properties are inherited, so a value set on the root `<html>` element is available to every element inside it. A **design token** is a named design decision, such as `--color-surface: #181d21`. Code uses the name, so changing the value in one place changes it everywhere the name is used.

Tailwind's `@theme` block turns tokens into utilities. A variable named `--color-surface` makes classes such as `bg-surface`, `text-surface`, and `border-surface` available, and each of them reads `var(--color-surface)`.

Here's the complete `styles.css`:

```css
@import "tailwindcss";

@theme {
  --color-page: #111417;
  --color-surface: #181d21;
  --color-foreground: #f3efe8;
  --color-muted: #b8b0a5;
  --color-line: #52616c;
  --color-accent: #ff9b6d;
  --color-accent-strong: #ffb38d;
}

:root {
  color-scheme: dark;
}

:root[data-theme="light"] {
  --color-page: #f4efe8;
  --color-surface: #fbf7f2;
  --color-foreground: #201916;
  --color-muted: #66564d;
  --color-line: #8a7568;
  --color-accent: #a34d2d;
  --color-accent-strong: #7e3417;
  color-scheme: light;
}
```

The `@theme` values are the dark palette, which is the default. The second rule replaces the same variables when the `<html>` element has `data-theme="light"`. `color-scheme` tells the browser which scheme its native controls, such as the checkbox and the select, should use.

In `src/index.html`, put `data-theme="dark"` on `<html>` and `class="bg-page font-sans text-foreground"` on `<body>`. Keep the `<task-board></task-board>` element from part 1.

Now follow one color from a class to its value:

```text
bg-surface on the row
        ↓
generated rule: background-color: var(--color-surface)
        ↓
--color-surface inherited from <html>
        ↓
#181d21 when dark, #fbf7f2 when light
```

So switching `data-theme` on `<html>` to `light` changes every row's background, border, text, and focus outline, without touching a single class list. Deciding how the user picks a theme, and whether that choice is saved, is a separate job; this example simply defaults to dark.

Tailwind also has a `dark:` prefix, as in `bg-white dark:bg-gray-900`, which writes both colors on every element. Named color roles like `surface` keep that pair in one place instead. Either works with Tailwind; this article uses the color roles.

A name like `muted` doesn't check contrast for you, so test that text stays readable and focus outlines stay visible in both themes.

## A task row built from utilities

Now put the utilities and the palette together in a row component.

First, move the `Task` interface out of `TaskBoard` into its own file, `task.ts`, so the board and the row share it:

```ts
export interface Task {
  id: number;
  title: string;
  done: boolean;
}
```

The row needs two connections to the board. An **input** passes data into a component, so the board can hand the row a task. An **output** lets a component emit its own event, so the row can tell the board the checkbox changed. The row never changes the task itself; it reports the choice and the board updates its list.

Save this as `task-row.ts`:

```ts
import { Component, computed, input, output } from "@angular/core";
import type { Task } from "./task";

@Component({
  selector: "task-row",
  host: { class: "block" },
  template: `
    <label
      class="flex items-start gap-3 rounded-lg border border-line bg-surface p-3 text-foreground"
    >
      <input
        #checkbox
        class="mt-1 size-4 shrink-0 accent-accent focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
        type="checkbox"
        [checked]="task().done"
        (change)="doneChange.emit(checkbox.checked)"
      />
      <span class="min-w-0 break-words" [class]="completedClasses()">
        {{ task().title }}
      </span>
    </label>
  `,
})
export class TaskRow {
  readonly task = input.required<Task>();
  readonly doneChange = output<boolean>();

  readonly completedClasses = computed(() => {
    if (this.task().done) {
      return "line-through text-muted";
    }
    return "";
  });
}
```

Here's what to notice:

- `input.required<Task>()` means the board must pass a task. Forgetting it is a compile error. Calling `task()` reads the current task.
- When the checkbox changes, `doneChange.emit(checkbox.checked)` sends `true` or `false` to the board.
- The label now uses the palette: `border-line`, `bg-surface`, and `text-foreground`.
- The span always has `min-w-0 break-words`, so long titles wrap. Angular's `[class]` binding adds `line-through text-muted` when the task is done. `computed` recalculates that class list whenever `task()` changes.
- `focus-visible:outline-2` uses a **variant**: the part before `:` is a condition, and the utility after it applies only when the condition holds. Here the outline appears only when the checkbox has keyboard focus.
- `accent-accent` looks odd, but it's two names: `accent-` is the utility for the CSS `accent-color` property, and `accent` is the palette color. It colors the native checkbox, which still provides its own keyboard support.
- `host: { class: "block" }` puts `block` on the `<task-row>` element itself. That element is still in the page and takes part in layout, so it needs a display value like any other element.

### Make the three changes

Now answer the opening question for this row.

**More breathing room:** open `task-row.ts` and change `gap-3` to `gap-4` and `p-3` to `p-4`. Each becomes `1rem`. You didn't search for a selector, check who else uses a class, or add an override. Every row on the board changes, because they all come from this component, and nothing else changes, because these classes sit on this component's elements only.

Replace the old class rather than adding the new one. If the list contains both `p-3` and `p-4`, putting `p-4` last doesn't make it win. The browser ignores the order of names in the `class` attribute; the order of the generated rules in the stylesheet decides, and you don't control that from the template.

**Completed look:** the condition and its presentation sit together in `completedClasses`. To change how a completed task looks, you edit that one string.

Keep each class name written out in full. Tailwind finds classes by reading your source files as plain text, so it sees `"line-through text-muted"` and generates both. It never runs your code, so something like `"text-" + colorName` produces no CSS. Tailwind also skips files listed in `.gitignore`, so classes written only in ignored files won't be generated either.

**Light theme:** already done, through the palette. The row doesn't need a second set of classes.

### Use the row in the board

In `task-board.ts`, delete the `Task` interface and import it from `./task` instead. Import `TaskRow` from `./task-row` and add `imports: [TaskRow]` to the `@Component` metadata. Keep the board's signals, computed values, and methods from part 1.

In the template, the repeated row markup becomes one element:

```html
<ul id="task-list" class="space-y-2" role="list">
  @for (task of visibleTasks(); track task.id) {
    <li>
      <task-row [task]="task" (doneChange)="setDone(task, $event, filterSelect)"></task-row>
    </li>
  }
</ul>
```

`$event` holds whatever the output emitted. Because the row emits a boolean, `$event` here is `true` or `false`, the same value the old template passed as `checkbox.checked`. So `setDone` works unchanged: it replaces the task, the count updates, and focus moves to the filter if the row disappears.

`space-y-2` adds space between the list items. `role="list"` stays on the `<ul>` for a reason covered under [What the pairing costs](#what-the-pairing-costs).

The rest of the board template gets utility classes the same way:

<details>
<summary>Full board template</summary>

```html
<main class="mx-auto max-w-2xl px-4 py-8">
  <h1 class="mb-6 text-3xl font-semibold">Task notes</h1>

  <form id="task-form" class="mb-6 space-y-2" (submit)="addTask($event, titleInput)">
    <label for="task-title" class="block font-medium">Task title</label>
    <div class="flex flex-wrap gap-2">
      <input
        #titleInput
        id="task-title"
        name="title"
        type="text"
        required
        class="min-w-0 grow basis-48 rounded-lg border border-muted bg-surface px-3 py-2 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
        (input)="titleInput.setCustomValidity('')"
      />
      <button
        type="submit"
        class="rounded-lg bg-accent px-4 py-2 font-medium text-page hover:bg-accent-strong focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
      >
        Add task
      </button>
    </div>
  </form>

  <label for="task-filter" class="mb-2 block font-medium">Show tasks</label>
  <select
    #filterSelect
    id="task-filter"
    class="rounded-lg border border-muted bg-surface px-3 py-2 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
    [value]="filter()"
    (change)="setFilter(filterSelect.value)"
  >
    <option value="all">All</option>
    <option value="active">Active</option>
    <option value="completed">Completed</option>
  </select>

  <p id="remaining-count" class="my-4" aria-live="polite">Remaining tasks: {{ remaining() }}</p>
  <ul id="task-list" class="space-y-2" role="list">
    @for (task of visibleTasks(); track task.id) {
      <li>
        <task-row [task]="task" (doneChange)="setDone(task, $event, filterSelect)"></task-row>
      </li>
    }
  </ul>
  <p id="empty-message" class="text-muted" [hidden]="visibleTasks().length > 0">
    No tasks to show.
  </p>
</main>
```

On the title input, `basis-48` asks for a width of `12rem`, `grow` lets it take spare space, and `flex-wrap` on its parent moves the button to the next line when there isn't room for both.

</details>

The board's behavior hasn't changed. The task rules from part 1 still decide what happens; the template now gets its look from utilities, and each task's row comes from one component instead of markup repeated inline.

## What the pairing costs

### Templates get denser

The row's class list is much longer than `class="task-row"`. The information that used to sit behind a name in a stylesheet is now on the element, and you still have to read it. Breaking attributes across lines helps, and so does moving a repeated piece into a component. Hiding every long class list behind a vague wrapper component just moves the information somewhere harder to find.

### You learn a vocabulary and a tool

Your team has to learn how utility names map to CSS, how variants work, and how Tailwind finds class names in source files. A few details catch people out:

- The examples use Tailwind 4, which is configured in CSS with `@theme`. Older versions and many tutorials use a JavaScript config file instead.
- Tailwind 4 targets modern browsers. Check its [compatibility page](https://tailwindcss.com/docs/compatibility) if you need to support older ones.
- Tailwind 4 isn't designed to be used together with Sass, Less, or Stylus. If a project already uses Sass heavily, that's a migration cost.
- `@import "tailwindcss"` includes **Preflight**, a set of base styles that resets browser defaults. For example, headings lose their default size and lists lose their bullets. That's why the board template sets its heading size explicitly, and why the list keeps `role="list"`: some browsers stop announcing a list to screen readers once its bullets are removed.

### Consistency still takes discipline

Using `p-3` and `gap-3` draws from the shared spacing scale, which makes reusing established values easy. It doesn't decide which spacing suits the task row; that's still a design decision.

Tailwind also accepts one-off values in square brackets, such as `p-[13px]`. That's useful as an escape hatch, but it means installing Tailwind doesn't enforce consistency on its own. If one-off values keep appearing, the design needs a new shared value, and that's a conversation to have with the designer.

### CSS knowledge is still required

`flex`, `min-w-0`, and `break-words` only help if you understand the layout problem they solve. A class name won't tell you why a title overflows or why another rule wins. And utilities are global CSS rules from `styles.css`, so they reach every component's elements, the same as any other global rule.

### Accessibility comes from HTML and behavior

Tailwind styles elements. The checkbox's keyboard support, its label, form validation, focus movement, and the live remaining count all come from the HTML and the behavior carried over from part 1. A custom control still needs its own behavior and accessibility work, or a control library that provides it. You can use Tailwind for presentation and a library for complex controls together.

### Plain CSS still has a place

A named animation, a complicated selector, or a rule that's simply clearer as CSS can live in a stylesheet. Utilities can be the default without being the only tool.

## Where each styling change goes

Back to the opening question: when you need to change how something looks, where do you go, and what else changes with it?

| Approach                 | Where you go                            | What else changes                                      |
| ------------------------ | --------------------------------------- | ------------------------------------------------------ |
| Plain CSS with BEM       | A shared stylesheet                     | Anything using the class, which you find by searching  |
| Sass                     | The Sass source for that stylesheet     | The same as plain CSS                                  |
| Bootstrap or Material    | A supported setting or theme value      | Every control that reads it                            |
| Angular component styles | The component file                      | Every instance of that component                       |
| Component with Tailwind  | The element in the component's template | Every instance of that component                       |
| Shared Tailwind palette  | One block in `styles.css`               | Every element that uses that color                     |

Components give you the "one place" and the predictable reach. Tailwind adds the rest:

- **Locality:** the structure and its presentation are on the same lines of the same file.
- **Component-based reuse:** the task row shares its markup, its label, the event it emits, and its look, not just a CSS rule.
- **Less selector management:** no class names to invent, no selectors to search for, no overrides tied to an ancestor.
- **Consistent design values:** spacing comes from one scale and colors from one palette, so the light theme was a single block of CSS.
- **Visual control:** you build the design you were given instead of reshaping a library's design.
- **Faster iteration:** the breathing-room change was two class names in one file.

You pay for it with denser templates, a vocabulary and a build tool to learn, and consistency that still depends on your team. If those costs outweigh the benefits, for example in a project built on Material or with a lot of working component CSS, a different combination fits better.

## Closing check

1. A designer wants more padding in every task row. With components and Tailwind, where do you make that change, and which elements does it affect?
2. Why doesn't a shared CSS class replace a task row component?
3. Why does switching `data-theme` to `light` restyle every row without editing any class list?
4. Which parts of the task row's behavior and accessibility did Tailwind not provide?

Check your reasoning:

- You change `p-3` to `p-4` in the row component's template. Every rendered task row changes, because they all come from that component, and nothing outside it does.
- A shared class only shares CSS declarations. The component also shares the row's HTML, the checkbox's label, and the event that reports a change to the board.
- Utilities such as `bg-surface` read CSS variables such as `--color-surface`. The light theme replaces those variables on `<html>`, and every element inherits the new values.
- The native checkbox, its label, keyboard activation, the board's task updates, focus movement, and the live count announcement all come from HTML and the behavior from part 1.

## Sources and further reading

- [BEM: official naming conventions and alternatives (source)](https://raw.githubusercontent.com/bem/bem-method/78e5d110a237df0c3841a9ae48d3d760cd970c36/method/naming-convention/naming-convention.en.md)
- [Sass: repeating styles with each](https://sass-lang.com/documentation/at-rules/control/each/)
- [Bootstrap 5.3: customization](https://getbootstrap.com/docs/5.3/customize/overview/)
- [Bootstrap 5.3: color modes](https://getbootstrap.com/docs/5.3/customize/color-modes/)
- [Angular Material: theming and supported overrides](https://material.angular.dev/guide/theming)
- [Angular: component styles and scoping](https://angular.dev/guide/components/styling)
- [Angular: component inputs](https://angular.dev/guide/components/inputs)
- [Angular: component outputs](https://angular.dev/guide/components/outputs)
- [Tailwind: composing utility classes](https://tailwindcss.com/docs/styling-with-utility-classes)
- [Tailwind: theme variables](https://tailwindcss.com/docs/theme)
- [Tailwind: finding classes in source](https://tailwindcss.com/docs/detecting-classes-in-source-files)
- [Tailwind: dark mode](https://tailwindcss.com/docs/dark-mode)
- [Tailwind: Preflight](https://tailwindcss.com/docs/preflight)
- [Tailwind: compatibility and preprocessors](https://tailwindcss.com/docs/compatibility)
