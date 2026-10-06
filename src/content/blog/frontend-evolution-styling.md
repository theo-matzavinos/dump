---
title: "Components + Tailwind: benefits and tradeoffs"
description: "A practical case for local styling, component-based reuse, fewer selector relationships, shared design values, visual control, and faster iteration—without pretending other approaches are obsolete."
pubDate: "2026-10-02"
tags:
  - css
  - tailwind
  - angular
  - frontend
---

Changing the spacing in a task row is easier to follow when the row has one implementation and every instance uses it. A completed state is easier to trace when its presentation sits beside the condition that selects it. A shared color is easier to change consistently when the interface uses one named value.

Components and Tailwind address different parts of that work. A component can reuse the row's structure, interaction, and presentation. Tailwind utilities compose styling on the elements that need it. Shared design values keep those local compositions connected to the same decisions.

The pairing offers six potential benefits: **locality, component-based reuse, less selector management, consistent design values, visual control, and faster iteration**. Understanding how those benefits arise—and what they cost—is more useful than comparing the length of class lists.

Each part matters. Components without Tailwind can work well. Utilities without shared decisions can still produce an inconsistent interface. Neither removes the need to understand CSS.

The examples continue the task interface from [part 1: behavior](/dump/blog/frontend-evolution-behavior/): a form, a filter, task checkboxes, and a remaining count. This time the changes are presentation changes. The [CSS layout article](/dump/blog/css-layout-fundamentals/) explains the underlying sizing and layout mechanisms.

## Contents

1. [Start with the work, not the syntax](#start-with-the-work-not-the-syntax)
2. [CSS, naming conventions, and preprocessors solve different problems](#css-naming-conventions-and-preprocessors-solve-different-problems)
3. [Bootstrap and Material provide a starting design](#bootstrap-and-material-provide-a-starting-design)
4. [Components provide a unit of reuse](#components-provide-a-unit-of-reuse)
5. [Tailwind places presentation beside markup](#tailwind-places-presentation-beside-markup)
6. [Local composition still needs shared decisions](#local-composition-still-needs-shared-decisions)
7. [The costs of the pairing](#the-costs-of-the-pairing)

## Start with the work, not the syntax

Consider these changes to the task interface:

- Give every task row more breathing room.
- Distinguish a completed task without making its title unreadable.
- Reuse the row without copying its interaction and styling independently.
- Support both dark and light presentation consistently.

For each change, ask:

1. Where is the implementation?
2. Which relationship needs to be understood before changing it?
3. What else intentionally changes with it?
4. What stays consistent because it shares the same implementation or value?

**Locality** means keeping related decisions close enough to understand and change them together. It does not mean that everything belongs in one enormous file, or that the application should have no shared configuration.

A row component can own the row's structure, checkbox interaction, and presentation. A shared theme can own colors. The task board can still own which tasks exist and whether they are complete. These are different kinds of ownership.

Keep behavior and presentation connected without confusing them:

```text
board owns task data
        ↓
row receives a task
        ├──→ checkbox shows done or active
        └──→ title receives the corresponding presentation
        ↑
row reports the user's choice to the board
```

Changing the text color does not make the task complete. The data and the checkbox's checked state express completion; the styling is an additional visible result.

## CSS, naming conventions, and preprocessors solve different problems

### Ordinary CSS gives direct control

A class name connects an element to matching CSS rules. Here is a rendered snapshot of one completed row inside the task list:

```html
<li>
  <label class="task-row task-row--completed">
    <input class="task-row__checkbox" type="checkbox" checked />
    <span class="task-row__title">Read the DOM article</span>
  </label>
</li>
```

Ordinary CSS can style it directly:

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

The browser matches the row, checkbox, and title classes to their rules. The final title rule requires both a completed ancestor and the title class. It expresses the relationship between the state class and that part of the row.

Several rules can match the same element and supply different values for one property. The browser resolves those competing declarations through a set of priority rules called the **cascade**.

The checkbox is a native control, and its enclosing label names it. The title can wrap rather than forcing the row wider than its container. Completion does not remove the title or rely only on color.

This is only a presentation snapshot. The `checked` attribute supplies the checkbox's initial state; the class does not stay synchronized with future interaction by itself. In the task board, rendering must derive both the checked property and completed presentation from task data, just as part 1 derived the count.

To change spacing, edit `gap` and `padding`. To change the completed presentation, edit the corresponding rule. There is nothing inadequate about CSS being used this way.

### BEM makes names informative

The names above use the two-dashes form of **BEM: Block, Element, Modifier**:

- `task-row` identifies the independently meaningful piece, called the block.
- `task-row__title` identifies a part of that piece, called an element in BEM terminology. This is a naming role, not a different kind of DOM element.
- `task-row--completed` identifies a variation or state, called a modifier.

The convention gives a teammate useful clues about ownership and relationships. BEM also has other naming forms; the two-dashes spelling is not the only one.

A naming convention does not create browser-enforced isolation. A matching global rule can still affect the element. Nor does the convention keep markup, state classes, and stylesheet rules synchronized automatically.

Those names can be useful, but each custom name adds a connection to maintain between markup and stylesheet rules. When a component already identifies the interface piece, utilities can avoid many additional names for its presentation.

### Sass reduces repetitive authoring

Browsers consume CSS, not Sass source. **Sass** is a tool that transforms an extended authoring language into CSS. **SCSS** is its CSS-like syntax, usually saved in `.scss` files.

For example, two spacing variants need nearly identical rules. Instead of repeating those rules, the Sass source can define two name/value pairs and instruct the tool to emit one padding rule for each pair:

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

The map associates each name with a value. `@each` repeats the block for each pair. `#{$name}` inserts the name into the selector during compilation. The resulting CSS is ordinary rules:

```css
.task-row--compact {
  padding: 0.5rem;
}

.task-row--comfortable {
  padding: 0.75rem;
}
```

Sass also offers modules for organizing stylesheet code, and mixins for named, reusable groups of declarations. Those can be useful when authoring a larger styling system or customizing a library's Sass source.

That is an authoring benefit. It does not decide which task is complete, encapsulate an interactive row, or maintain the relationship between a class in a template and its rule.

Modern CSS also has custom properties and nesting. Sass is not required merely to share a color or nest a selector. Its additional authoring features should solve an actual problem rather than be added automatically.

These approaches can coexist: BEM is a convention, Sass is an authoring tool, and CSS is what the browser applies. They are not three generations of the same thing.

## Bootstrap and Material provide a starting design

A UI library can provide a useful collection of established decisions instead of requiring every control to be designed from scratch.

With Bootstrap 5.3, a task row can combine supplied form styling and layout utilities:

```html
<li class="list-group-item bg-body-tertiary text-body">
  <label class="d-flex align-items-start gap-3 p-2">
    <input class="form-check-input flex-shrink-0" type="checkbox" checked />
    <span class="text-break text-decoration-line-through">Read the DOM article</span>
  </label>
</li>
```

This assumes Bootstrap's stylesheet is loaded and the row belongs to a list with `class="list-group"`. For its dark color mode, Bootstrap 5.3 accepts `data-bs-theme="dark"` on the document's `<html>` element. The body and tertiary-surface utilities then use the corresponding shared color values.

The checkbox here is still a native input. Bootstrap supplies its appearance; other Bootstrap components may also need JavaScript for their interaction.

Angular Material goes further than a set of CSS classes: its Angular components implement controls and associated interaction behavior. Their design follows Material conventions, and their theming APIs support substantial customization.

For example, this theme uses Material's supported Sass API rather than reaching into a component's internal elements:

```scss
@use "@angular/material" as mat;

html {
  color-scheme: dark;
  @include mat.theme(
    (
      color: mat.$azure-palette,
      typography: system-ui,
      density: 0,
    )
  );
}

body {
  background: var(--mat-sys-surface);
  color: var(--mat-sys-on-surface);
}
```

This is the current `mat.theme` API, checked with Angular Material 22.2.1. It supplies color, typography, and density values for Material components. Density controls spacing within supported controls. The body rules use the generated surface and text values for the surrounding page too.

The theme's color variables can contain CSS `light-dark(...)` values. That function holds two color choices: one for light mode and one for dark mode. The `color-scheme` property selects which choice applies; changing it to `light` selects the light presentation. A theme is not a task model or an automatic preference-saving system.

### Supported customization is different from fighting internals

Bootstrap exposes Sass settings and CSS variables. Angular Material exposes theme and component-token overrides. Changing a supported value through those APIs is normal use, not evidence that a library is difficult to customize.

The friction appears when the desired presentation does not fit the supplied structure or supported choices. The available options are to accept the library's conventions, find a supported extension, implement that part separately, or override details the library does not promise to keep stable.

Angular Material explicitly treats its component DOM structure and internal CSS classes as private implementation details. Targeting them with deep selectors creates a maintenance relationship with something the library may change. That is different from using its documented theme APIs.

Direct composition starts with the desired presentation rather than a supplied visual system that needs adjusting. That can reduce customization work when the designs differ substantially; it does not mean library-based interfaces must look generic.

There is also an important overlap: **Bootstrap has utilities**, so composition beside markup is not unique to Tailwind. Library controls can also be used inside application components. A library can be a useful starting point when its controls and design assumptions fit the product.

## Components provide a unit of reuse

Sharing a CSS rule shares declarations. It does not, by itself, share the row's HTML, accessible label, event handling, or relationship to task data.

A component gives those related pieces one implementation and a clear usage boundary. Instead of copying a checkbox, title, spacing classes, and event hookup into every list, each list renders instances of the same task row.

In this example, the boundary is simple:

```text
TaskBoard
  owns tasks, filtering, and the remaining count
       ↓ passes a task
TaskRow
  owns the row's markup and presentation
       ↑ reports a requested done value
TaskBoard
  applies that change to its task data
```

The row does not become the owner of the task collection just because it displays one task. Reuse and state ownership are separate decisions.

This also gives a change a predictable reach. Editing the shared row implementation changes its instances intentionally. If one context genuinely needs a different presentation, give that need an explicit variant rather than hoping a distant selector changes the right instance.

Do not extract a generic styling abstraction merely because two elements both have padding and a border. A task row is a meaningful product concept. An all-purpose “styled container” with many unrelated options may not be.

### Components do not require Tailwind

Angular can keep CSS in a component's `styles` or a file referenced by `styleUrl`. It can keep markup inline or in a file referenced by `templateUrl`. Those files can be adjacent, so ordinary component CSS can also be local.

Consider this small, independent example of a component that displays a task title. It demonstrates style scoping; it is not an extra component required by the task board below:

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

A global `.title` rule could match any element with that class. Angular changes this component rule's reach without requiring a longer class name:

1. It adds a generated attribute to elements created from the component's template. The `title` class stays unchanged.
2. It rewrites the component's CSS selector to require that same attribute.
3. The browser applies the resulting ordinary CSS rule only when both the class and the attribute match.

The rendered markup has this shape:

```html
<task-title _nghost-example>
  <span class="title" _ngcontent-example>Read the DOM article</span>
</task-title>
```

The component's rule has this shape:

```css
.title[_ngcontent-example] {
  font-weight: 600;
}
```

Here, `example` stands in for Angular's generated identifier; these are simplified illustrations, not exact output to copy. The content attribute marks template elements. The host attribute marks the component's own `<task-title>` element and lets Angular transform component rules using `:host`. The generated names are implementation details, not selectors to maintain by hand.

Another component can also use `class="title"`, but its template elements receive a different component marker. This rule does not match them merely because the class name is the same. Instances of the same component type share its marker; the marker is not an individual task's identity.

This selector transformation is Angular's default **emulated view encapsulation**: the framework provides a component-specific selector boundary using ordinary attributes and CSS.

Browsers also offer a different mechanism: an internal DOM tree attached to an element, with its own stylesheet scope. That feature is called **Shadow DOM**. Angular's default mode does not create such a tree; the template elements remain in the ordinary DOM.

### Similar goals, different scoping mechanisms

**CSS Modules** also make simple local names practical, but take a different route. Their tooling maps a local class name to a generated name, and importing the stylesheet into JavaScript exposes that mapping as an object. Code uses a value such as `styles.title` to put the mapped class name on the element. Angular's default mechanism keeps `class="title"` and changes selectors through attributes instead.

**BEM** relies on a naming convention that makes ownership and variations recognizable. It does not automatically rewrite names or selectors. All three approaches can reduce naming conflicts, but only the tooling-based approaches establish the corresponding generated names or selector boundaries.

The boundary is not complete style isolation. A global `.title` rule still matches Angular's internal span because the span retains that class. Global element rules, inherited values, and custom properties can also affect it. The usual cascade still decides between competing declarations. CSS Modules likewise do not create a native Shadow DOM boundary; global rules can still match elements through other selectors, and values can inherit.

With Angular's default scoping, simple local classes such as `title` may be enough. BEM can still be useful for communicating structure or organizing shared global CSS, but it is not required merely to prevent two component-local `title` rules from matching each other's template elements.

So “CSS requires distant stylesheets, Tailwind does not” would be an unfair comparison. Components already provide local styles, reuse, and—under Angular's default mode—selector scoping. Tailwind's additional role is utility composition and shared design values, not supplying that component boundary.

## Tailwind places presentation beside markup

A **utility class** expresses a focused styling operation. Tailwind generates CSS for the utilities found in the project's source. Those operations are composed on the elements that need them.

For example:

```html
<label class="flex items-start gap-3 rounded-lg border border-line bg-surface p-3 text-foreground">
  <!-- The row's control and title go here. -->
</label>
```

Here is the mechanism before treating the names as vocabulary:

- `flex` sets the element's `display` to `flex`.
- `items-start` aligns its flex items at the start of the cross axis.
- `gap-3` uses three spacing steps between those items.
- `p-3` uses three spacing steps for padding.
- `rounded-lg` uses the shared large-radius value.
- `border` supplies a border width; `border-line` selects its color.
- `bg-surface` and `text-foreground` use shared color roles defined below.

With Tailwind's default spacing step of `0.25rem`, three steps are `0.75rem`. At a root font size of `16px`, that is `12px`. These are CSS relationships, not a new layout engine.

Conceptually, the two spacing utilities apply rules like these:

```css
.gap-3 {
  gap: calc(var(--spacing) * 3);
}

.p-3 {
  padding: calc(var(--spacing) * 3);
}
```

The browser still lays out flex items, resolves `rem`, and applies the cascade. Tailwind helps generate and compose CSS; it does not replace those mechanisms.

### One small change stays in the row

To increase both the gap and padding to four spacing steps, replace `gap-3` with `gap-4` and `p-3` with `p-4` in the row implementation. With the default spacing step, each becomes `1rem`.

This change needs no new selector, search for an existing selector's definition, or override tied to an ancestor. When the row is a component, its other instances use the changed composition too.

The benefit here is fewer naming and navigation decisions during ordinary changes, not a guarantee that every change is faster.

Do **replace** conflicting utilities. Keeping both `p-3` and `p-4` and moving one to the end of the HTML class list does not make that final word win. The CSS cascade and generated rule order decide which declarations apply, not the order of class names in the attribute.

### Data attributes can provide state and part hooks

The BEM example uses `task-row--completed` to mark state and `task-row__title` to identify a part. Custom HTML attributes can provide those hooks too: `data-state="completed"` records a state value on the row, while `data-slot="title"` names a part. Their names and values are application conventions, not built-in browser behavior.

CSS can match those attributes with selectors such as `[data-state="completed"]` or `[data-slot="title"]`. A **hook** is simply a name that styling or other application code can target. Data attributes are not specific to Tailwind; ordinary CSS can use them instead of, or alongside, BEM classes.

Tailwind can generate the conditional selectors while keeping the styling operations beside the element. Here is the same completed-row snapshot, using the shared colors defined later:

```html
<li>
  <label
    data-state="completed"
    class="group flex items-start gap-3 rounded-lg border border-line bg-surface p-3 text-foreground"
  >
    <input class="mt-1 size-4 shrink-0 accent-accent" type="checkbox" checked />
    <span
      data-slot="title"
      class="min-w-0 break-words group-data-[state=completed]:line-through group-data-[state=completed]:text-muted"
    >
      Read the DOM article
    </span>
  </label>
</li>
```

Follow the relationship:

1. `group` marks the label as an ancestor whose state descendant utilities can inspect.
2. `group-data-[state=completed]:line-through` applies the title's text decoration when that ancestor has `data-state="completed"`.
3. `group-data-[state=completed]:text-muted` applies the completed color under the same condition.
4. Changing the attribute to `data-state="active"` makes those conditions stop matching. The utility names stay unchanged.

The prefix before `:` is a **variant**: a condition for applying the utility after it. For a condition on the styled element itself, `data-[state=completed]:line-through` checks that element's own attribute instead of an ancestor's.

The optional `data-slot="title"` offers a named part hook comparable to the BEM element class. It is not required by the utilities in this example, which are attached directly to the title. Neither part names nor state attributes create style isolation.

This replaces a handwritten modifier-to-title rule with generated conditional utilities; it does not remove the relationship between state and presentation. Rendering still has to derive the attribute and the checkbox's checked property from the same task data. Changing a data attribute alone does not change the checkbox's checked property or its accessible checked state. The component below selects a class list instead; data hooks are an alternative, not an additional source of task state.

### A reusable Angular row

Here is a concrete replacement for the repeated row markup in part 1. These examples use Angular 22.2.1 and Tailwind CSS 4.3.3.

Move the task interface from `TaskBoard` into `task.ts`, exporting it so the board and row share the same type:

```ts
export interface Task {
  id: number;
  title: string;
  done: boolean;
}
```

In Angular, an **input** supplies data to a component. An **output** reports a custom event to its consumer. Here, the input supplies a task; the output reports the checked choice back to the board. The row reads the task, rather than mutating an object owned by its parent.

Save this component in `task-row.ts`:

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

The required input makes a missing task a template-compilation error. Calling `task()` reads the supplied task. When the checkbox changes, `doneChange.emit(...)` reports a boolean choice. The parent decides how to apply it.

The span retains its static wrapping utilities, while Angular's `[class]` binding adds or removes the completed-state classes. `computed` derives that class list from the supplied task. The full names `line-through` and `text-muted` exist literally in source, so Tailwind can detect them.

The `host` entry puts `block` on the component's own `<task-row>` element. That element participates in layout too; a component boundary does not remove its host from the DOM.

`accent-accent` looks repetitive because the first part names the CSS `accent-color` utility and the second names the shared color role. It colors the native checkbox. It does not turn a drawn square into a checkbox or provide keyboard interaction—the native input already does that.

### Use the row through its consumer

In `TaskBoard`, import `Task` from `./task` instead of declaring the interface there. Import `TaskRow` from `./task-row` and add `imports: [TaskRow]` to the existing `@Component` metadata.

Keep the board's signals, derived values, and methods from part 1. Replace its template with this one:

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

The input's `basis-48` supplies a preferred width of `12rem`, while `grow` lets it use spare space. Together with the wrapping parent, that avoids squeezing the field into a tiny sliver beside the button on narrow screens or at larger text sizes. `min-w-0` still allows it to shrink when its own line is narrower than that preferred width.

The row emits a boolean, so `$event` in `(doneChange)` is that boolean—not a native DOM `Event`. The board's existing `setDone` method still replaces the appropriate task, updates its derived count and visible collection, and moves focus if the affected row disappears.

The new composition changes presentation and introduces a row boundary; it does not replace the task rules with styling logic. Each repeated task uses the same row implementation, rather than copying that implementation into the board.

For the CSS entry and document setup, use the next section. This is code for an Angular application configured to process Tailwind, not an instruction to paste `@theme` into a browser stylesheet unchanged. Follow the [current Angular installation guide](https://tailwindcss.com/docs/installation/framework-guides/angular) for that integration. Detailed input/output and content-composition design belongs to the next article.

## Local composition still needs shared decisions

If every element picks unrelated colors and spacing, writing those choices beside markup does not make the result coherent.

A **design value** is a shared choice, such as the spacing step or a surface color. A **design token** gives that choice a name other code can use. The name makes it possible to use the same decision repeatedly and change it deliberately.

CSS already provides a mechanism for sharing values. A custom property has a name beginning with `--`; `var(...)` reads its value. Custom properties normally inherit through the element tree, so a value on the document root can supply values to descendants.

Tailwind's `@theme` adds an authoring relationship: a color variable named `--color-surface` makes utilities such as `bg-surface` available. The generated CSS retains a custom property for the value.

### Define the shared palette once

Use this in the application's Tailwind CSS entry, such as `styles.css`:

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

In the host document, use `data-theme="dark"` on `<html>` and `class="bg-page font-sans text-foreground"` on `<body>`. Keep the `<task-board></task-board>` host used to bootstrap the board in part 1.

Now follow the color:

```text
bg-surface in the row
        ↓
generated background-color rule
        ↓
var(--color-surface)
        ↓
current value inherited from the root
```

Changing the root's `data-theme` to `light` changes those inherited values. The component does not need a second copy of its markup or a separate color decision for each row. `color-scheme` also tells the browser which scheme to use for native controls.

Tailwind has a `dark:` variant too. Here, named color roles carry the theme change instead of repeating light/dark color pairs across every element. That is a choice within Tailwind, not a requirement of utility styling. The application still needs to decide how a user selects a mode and whether that preference is saved; this example defaults to dark mode.

The same theme change covers regular titles, completed titles, borders, focus indicators, and the input surface. Readability and focus still need checking in both modes; naming a color `muted` does not guarantee sufficient contrast.

### Shared values are guidance, not automatic design quality

Using `p-3`, `p-4`, and `gap-3` draws from the spacing scale. It makes reusing established values easy. It does not decide which spacing is appropriate for the task.

The board's `font-sans` also uses a shared font stack, while `text-3xl` selects a value from the type scale. Color is not the only shared decision: spacing and typography need deliberate choices too.

Tailwind also allows arbitrary values, such as `p-[13px]`. That escape hatch can be useful, but it means consistency is not enforced merely by installing the tool. Repeated one-off choices should prompt a design discussion, not a larger pile of utility names.

A shared token change intentionally affects all consumers. A component edit intentionally affects that component's instances. Locality does not mean that no change can have wider consequences; it means that those relationships have understandable owners.

### Dynamic state does not mean dynamically inventing class names

The completed-state method selects a complete literal class list. Avoid constructing utility names from fragments such as `"text-" + colorName` and expecting Tailwind to evaluate that JavaScript during its build.

Tailwind scans source text for complete candidate names; it does not execute application logic to discover them. Source files also have to be included in the scan. Dependency packages and ignored files are not automatically treated like application source.

If a component variant selects different compositions, keep its possible class names literal and findable in the configured source. That is a build relationship to maintain, even though there are fewer handwritten selectors.

## The costs of the pairing

### Templates become denser

The row's class list is longer than `class="task-row"`. The information is present instead of hidden behind a name, but it is still information that must be read.

Breaking attributes across lines helps. Moving a meaningful repeated row into a component helps. Replacing every long class list with a vague wrapper can merely hide the information again.

### Vocabulary and tooling are real dependencies

A teammate must learn how utility names map to CSS, how state and responsive variants work, and how the build finds source files. The examples here use Tailwind 4's CSS-based theme configuration; older versions and tutorials may use a different setup. Tailwind 4 also targets modern browsers, so check its compatibility requirements if a project needs older browser support.

Tailwind 4 is itself a CSS build tool and is not designed to use Sass as a preprocessor for the same stylesheet. The Material theme example is Sass; the Tailwind entry is CSS. The fact that approaches address overlapping concerns does not make every build-pipeline combination interchangeable.

Tailwind's import also includes **Preflight**, a shared set of base CSS resets. Those affect defaults for elements such as headings, controls, and lists. It is not only a bag of classes with no effect until used. The board template sets its heading and control presentation explicitly, and retains `role="list"` because removing list markers can affect how some browsers expose list semantics.

### CSS knowledge remains necessary

`flex`, `min-w-0`, and `break-words` are useful only with an understanding of the layout problem they address. A utility cannot explain why the available width is small or why another declaration wins.

The classes are not private to the component. They refer to shared CSS rules. These examples use Angular's default emulated style mode, where that global utility stylesheet reaches the rendered elements. A native Shadow DOM boundary requires styles to be available within its scope; it is not automatically styled by document-level utilities.

### Tailwind does not supply accessible behavior

It does not provide the checkbox's native semantics, label, keyboard activation, form validation, focus movement, or live count announcement. Those come from the HTML and behavior design carried over from part 1.

A custom control still needs its own behavior and accessibility work, or an appropriate control library. Choosing Tailwind for presentation does not require implementing every complex control from scratch.

### Ordinary CSS remains useful

A named animation, a complex selector relationship, or a particularly clear component rule can be better expressed in CSS. There is no prize for spelling every possible declaration through a utility.

Utility composition can be the default approach without excluding ordinary CSS where it is clearer.

## How the pairing supports the six goals

The examples connect the pairing to six concrete benefits:

- **Locality:** read the structure and most of its presentation together.
- **Component-based reuse:** share a task row as a product concept, including its interaction and semantics.
- **Less selector management:** avoid creating names and relationships for every styling combination.
- **Consistent design values:** use shared spacing and color decisions rather than unrelated numbers everywhere.
- **Visual control:** compose the intended presentation without first adopting a different visual system.
- **Faster iteration:** make ordinary changes with fewer naming and navigation decisions.

The pairing is useful when these benefits outweigh denser templates and an additional vocabulary. Existing component CSS, library integrations, or product constraints may make a different combination a better fit.

Components, scoping, naming conventions, preprocessing, UI libraries, and utility composition solve different problems. The useful question is which relationships a team needs to maintain—and which tools make that work clearer.

## Closing check

1. Why does extracting a shared CSS class not necessarily replace a row component?
2. How can Angular keep simple component-local classes such as `title` from matching another component's template, and why can global CSS still affect them?
3. Why does changing `--color-surface` affect many rows without editing each class list?
4. Why can `"text-" + colorName` fail to produce the expected utility CSS?
5. Which parts of the checkbox interaction did Tailwind not provide?

Check your reasoning:

- A shared rule reuses declarations, not necessarily markup, event behavior, or an interface's usage boundary.
- Angular's default mode adds component-specific attributes and requires them in component selectors. A global rule is not restricted by that generated marker. Component styles can also be inline or adjacent to markup, so locality and scoping are not benefits unique to Tailwind.
- The utility reads a shared CSS custom property. Its consumers use the same current value, so a token change has an intentional shared reach.
- The build scans source text for complete class names; it does not execute the expression to discover every possible result.
- The native control, accessible label, parent-owned task updates, validation, focus management, and live count announcement remain separate responsibilities.

## Sources and further reading

- [BEM: official naming conventions and alternatives (source)](https://raw.githubusercontent.com/bem/bem-method/78e5d110a237df0c3841a9ae48d3d760cd970c36/method/naming-convention/naming-convention.en.md)
- [Sass: repeating styles with each](https://sass-lang.com/documentation/at-rules/control/each/)
- [Bootstrap 5.3: customization](https://getbootstrap.com/docs/5.3/customize/overview/)
- [Bootstrap 5.3: color modes](https://getbootstrap.com/docs/5.3/customize/color-modes/)
- [Angular Material: theming and supported overrides](https://material.angular.dev/guide/theming)
- [Angular: component styles and scoping](https://angular.dev/guide/components/styling)
- [Angular: component inputs](https://angular.dev/guide/components/inputs)
- [Angular: component outputs](https://angular.dev/guide/components/outputs)
- [CSS Modules: local names and stylesheet imports (source)](https://raw.githubusercontent.com/css-modules/css-modules/c7bf6c02472fdce4dd8e569abc10d2aeb234e1c2/README.md)
- [Tailwind: composing utility classes](https://tailwindcss.com/docs/styling-with-utility-classes)
- [Tailwind: data-attribute variants](https://tailwindcss.com/docs/hover-focus-and-other-states#data-attributes)
- [Tailwind: theme variables](https://tailwindcss.com/docs/theme)
- [Tailwind: finding classes in source](https://tailwindcss.com/docs/detecting-classes-in-source-files)
- [Tailwind: dark mode](https://tailwindcss.com/docs/dark-mode)
- [Tailwind: Preflight](https://tailwindcss.com/docs/preflight)
- [Tailwind: compatibility and preprocessors](https://tailwindcss.com/docs/compatibility)
