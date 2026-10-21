---
title: "Splitting a task page into Angular components"
description: "Decide which component holds each piece of state, connect components with typed inputs and outputs, keep an edit draft alive with linkedSignal, and wrap page content with a projected section frame."
pubDate: "2026-10-06T09:00:00Z"
updatedDate: "2026-10-15"
tags:
  - angular
  - components
audience:
  - frontend
---

The task board can add, complete, and filter tasks. Now it needs a way to rename one. You click Edit on a task, type half of a new title, and then tick that task's checkbox, or switch the filter so the task drops out of the list. Should your half-typed title survive? And if you click Cancel instead, should the old title come back?

Splitting the markup into more files doesn't answer those questions by itself. The answer comes from deciding which component holds each piece of data, which component is allowed to change it, and how long it lives. This article works through those decisions while it builds a task row that reports clicks to the page, an editor that keeps an unfinished draft, and a small frame that wraps content the page supplies.

You'll need the task board and its `TaskRow` component from the [styling article](/dump/blog/frontend-evolution-styling/) as a starting point, and the signals (`signal` and `computed`) from the [behavior article](/dump/blog/frontend-evolution-behavior/) to follow the state code. The examples use Angular 22.2.1. They leave out most Tailwind classes so the component code stays readable; if you're following the styling article's setup, keep its classes on the matching elements.

## Contents

1. [Decide which component holds each piece of state](#decide-which-component-holds-each-piece-of-state)
2. [Pass a task into the row with an input](#pass-a-task-into-the-row-with-an-input)
3. [Report the checkbox with an output](#report-the-checkbox-with-an-output)
4. [Add editing, deleting, and details to the row](#add-editing-deleting-and-details-to-the-row)
5. [Keep an unfinished title in an editor](#keep-an-unfinished-title-in-an-editor)
6. [Wrap page content with a section frame](#wrap-page-content-with-a-section-frame)
7. [Put the page together](#put-the-page-together)
8. [When to extract a component](#when-to-extract-a-component)

## Decide which component holds each piece of state

Before writing any component, list the data the page works with:

- the tasks themselves, each with an `id`, a `title`, and a `done` flag
- the filter choice (all, active, or completed)
- which task is being edited, if any
- the title someone is typing but hasn't saved yet
- whether a row's extra details are expanded

The tasks the list, filter, and remaining count all read from are the **accepted tasks**: the current saved version of each task, as opposed to an edit that's still in progress.

Here's where each piece lives in this article's page. An arrow means the parent component passes a task down to the child. "Reports" means the child tells its parent that something happened, and the parent decides what to do about it.

```text
TaskPage
  holds the accepted tasks, the filter, and which task is being edited
      │
      ├── task → TaskRow
      │           holds whether its details are expanded
      │           reports completion, edit, and delete clicks
      │
      └── task → TaskEditor
                  holds the unfinished title draft
                  reports a saved title or a cancel
```

A useful rule of thumb: put each piece of state in the lowest component that sits above every component that reads it, and that lives at least as long as the state needs to. Here's how that plays out:

- **The remaining count and the filtered list** are calculated from the tasks with `computed`, so there's no separate copy that every change has to remember to update.
- **Which task is being edited** lives in the page. The filter can remove a row from the list, and a removed row is destroyed along with anything it holds. The editor has to stay open when that happens, so the page holds the selection.
- **The unfinished title** lives in the editor. It's allowed to differ from the accepted title while you type, and it only becomes the accepted title when you click Save. The editor is created when editing starts and destroyed when it ends, which is exactly how long the draft should live.
- **Whether details are expanded** lives in the row. Only the row reads it, and losing it when the row disappears is fine.

The shared task type is the one the styling article moved into `task.ts`:

```ts
export interface Task {
  id: number;
  title: string;
  done: boolean;
}
```

## Pass a task into the row with an input

A component's **parent** is the component whose template uses its tag. The page's template will contain `<task-row>`, so the page is the row's parent, and the row is its **child**.

The styling article's row already has an input and an output. This section and the next rebuild it one piece at a time, so you can see what each piece does.

The row needs one thing from the page: the task to display. An **input** is a named value a parent passes into a child. Here's the smallest version of the row:

```ts
import { Component, input } from "@angular/core";
import type { Task } from "./task";

@Component({
  selector: "task-row",
  template: `
    <label>
      <input type="checkbox" [checked]="task().done" />
      <span>{{ task().title }}</span>
    </label>
  `,
})
export class TaskRow {
  readonly task = input.required<Task>();
}
```

And here's how the page passes a task in, inside its `@for` loop over the visible tasks:

```html
<task-row [task]="task" />
```

Notice three things:

- `input.required<Task>()` declares an input named `task` that holds a `Task`. "Required" means every `<task-row>` must supply one. Leave out `[task]` and the template fails to compile.
- An input is a read-only signal, so the row reads it by calling it: `task().title`.
- In `[task]="task"`, the left side is the row's input name and the right side is the page's loop variable. The `/>` at the end closes the tag in one go, which Angular allows for component tags.

The row now shows the right checkbox state, but ticking the checkbox only changes the checkbox on screen. Nothing tells the page, so the task's `done` value and the remaining count stay the same. The next section fixes that.

### The row gets the page's object, not a copy

The input signal has no `set` method, so the row can't replace the task it was given. It can still change that task's fields, though. Assigning `this.task().title = "x"` inside the row compiles fine, and it changes the same object the page holds in its `tasks` array, because passing an object to an input passes a reference to it rather than a copy. The [values and identity article](/dump/blog/values-references-and-identity/) explains why that kind of change also slips past the page's signals.

So the row follows a rule that Angular doesn't enforce: it reads the task and reports what the user did. The page is the only component that changes tasks, and it does that by replacing task objects.

## Report the checkbox with an output

An **output** is a named event a child component sends to its parent. Add one to the row and emit it when the checkbox changes:

```ts
import { Component, input, output } from "@angular/core";
import type { Task } from "./task";

@Component({
  selector: "task-row",
  template: `
    <label>
      <input
        #checkbox
        type="checkbox"
        [checked]="task().done"
        (change)="doneChange.emit(checkbox.checked)"
      />
      <span>{{ task().title }}</span>
    </label>
  `,
})
export class TaskRow {
  readonly task = input.required<Task>();
  readonly doneChange = output<boolean>();
}
```

The page listens with parentheses, the same syntax it uses for native events like `(change)`:

```html
<task-row [task]="task" (doneChange)="setDone(task, $event, filterSelect)" />
```

Here's what happens when you tick the checkbox:

1. The browser fires a `change` event on the native checkbox.
2. The row's `(change)` binding runs `doneChange.emit(checkbox.checked)`. `#checkbox` names the native input element, so the template can read its `checked` property.
3. Angular calls the page's `(doneChange)` listener. There, `$event` is the boolean the row emitted, not a native DOM `Event`.
4. The page's `setDone` method, unchanged from the board, replaces that task with a new object whose `done` value matches.
5. The `tasks` signal changes, so the remaining count and the filtered list update, and the row receives the new task object through its input.

Emitting only reports. If the page didn't listen to `(doneChange)`, step 4 would never happen: the checkbox would show a tick, but the task's `done` value and the remaining count would stay the same.

### Outputs don't bubble

If you've worked with DOM events, you might expect to catch every row's output on a surrounding element, the way a `click` bubbles up from a button to its parent `<ul>`. Angular outputs don't bubble. `(doneChange)` on the `<ul>` never fires. You listen on the `<task-row>` element itself.

That also means a component sitting between the page and the row has to declare its own output and emit it again whenever the row's output fires. Doing that once is fine, but if a component in the middle does nothing except pass inputs down and outputs up, it's worth asking whether it should exist at all. The last section comes back to that question.

## Add editing, deleting, and details to the row

The row needs three more interactions: an Edit button, a Delete button, and a Details button that shows the task's ID. Here's the finished row, saved in `task-row.ts`:

```ts
import { Component, input, output, signal } from "@angular/core";
import type { Task } from "./task";

@Component({
  selector: "task-row",
  template: `
    <label>
      <input
        #checkbox
        type="checkbox"
        [checked]="task().done"
        (change)="doneChange.emit(checkbox.checked)"
      />
      <span>{{ task().title }}</span>
    </label>
    <button
      type="button"
      [disabled]="!canEdit()"
      [attr.aria-label]="'Edit ' + task().title"
      (click)="editRequested.emit()"
    >
      Edit
    </button>
    <button
      type="button"
      [attr.aria-expanded]="detailsOpen()"
      [attr.aria-controls]="'task-details-' + task().id"
      (click)="toggleDetails()"
    >
      Details
    </button>
    <button
      type="button"
      [attr.aria-label]="'Delete ' + task().title"
      (click)="deleteRequested.emit()"
    >
      Delete
    </button>
    <p [id]="'task-details-' + task().id" [hidden]="!detailsOpen()">
      Task identifier: {{ task().id }}
    </p>
  `,
})
export class TaskRow {
  readonly task = input.required<Task>();
  readonly canEdit = input(true);
  readonly doneChange = output<boolean>();
  readonly editRequested = output<void>();
  readonly deleteRequested = output<void>();
  readonly detailsOpen = signal(false);

  toggleDetails(): void {
    this.detailsOpen.set(!this.detailsOpen());
  }
}
```

What to notice:

- **`canEdit` has a default.** `input(true)` declares an optional input that starts as `true`. The page passes `false` while an editor is open, which disables every Edit button so only one task is edited at a time.
- **`editRequested` and `deleteRequested` carry no value.** `output<void>()` means `emit()` sends nothing. The page already knows which task each row shows, because it rendered the row from its own loop variable.
- **`detailsOpen` stays in the row.** Clicking Details changes a signal inside the row. The page never hears about it, because nothing else needs to know.
- **Some bindings use `attr.`** `[checked]` and `[disabled]` set properties on the DOM element. `[attr.aria-label]` sets an HTML attribute instead, which is how ARIA values are written.
- **The ARIA attributes describe the buttons to screen readers.** Every row has a button labelled "Edit", so `aria-label` makes each one announce which task it edits, such as "Edit Read the DOM article". `aria-expanded` tells screen readers whether the details are currently shown, and `aria-controls` points to the `id` of the paragraph the button shows and hides.

The page now renders each row like this:

```html
<task-row
  [task]="task"
  [canEdit]="editingId() === undefined"
  (doneChange)="setDone(task, $event, filterSelect)"
  (editRequested)="startEditing(task.id)"
  (deleteRequested)="removeTask(task.id, filterSelect)"
/>
```

`editingId`, `startEditing`, and `removeTask` are new page members. They're added in [Put the page together](#put-the-page-together).

## Keep an unfinished title in an editor

The simplest way to rename a task would be to type straight into the task object's `title`. But then every keystroke would change the accepted task immediately, and a Cancel button would have nothing to go back to.

So the editor keeps a separate string, the **draft**, and only changes that. Clicking Save sends the draft to the page. Clicking Cancel sends nothing. The page stays the only component that changes tasks.

Here's the lifetime the editor and its draft should have:

1. Clicking Edit creates an editor and starts its draft from that task's title.
2. Typing changes the draft, not the accepted task.
3. Ticking the task's checkbox or changing the filter leaves the draft alone.
4. Save updates the accepted title and closes the editor. Cancel closes it without updating anything.
5. Closing destroys the editor. Opening another edit creates a fresh editor with a fresh draft.

### Start the draft with linkedSignal

The draft needs to start from the task's title, and it also needs to change as you type. A plain `computed` can't be written to, and a plain `signal` doesn't know about the task. `linkedSignal` is both: you write to it with `set`, like a `signal`, and Angular recalculates it from other signals whenever they change, like a `computed`. A recalculation replaces whatever was last written.

Here's the first version of the editor, saved in `task-editor.ts`:

```ts
import { Component, input, linkedSignal, output } from "@angular/core";
import type { Task } from "./task";

@Component({
  selector: "task-editor",
  template: `
    <form (submit)="submitTitle($event, titleInput)">
      <label for="draft-title">New task title</label>
      <input
        #titleInput
        id="draft-title"
        name="title"
        type="text"
        required
        [value]="draftTitle()"
        (input)="draftTitle.set(titleInput.value); titleInput.setCustomValidity('')"
      />
      <button type="submit">Save title</button>
      <button type="button" (click)="cancelled.emit()">Cancel</button>
    </form>
  `,
})
export class TaskEditor {
  readonly task = input.required<Task>();
  readonly titleSubmitted = output<string>();
  readonly cancelled = output<void>();
  readonly draftTitle = linkedSignal(() => this.task().title);

  submitTitle(event: SubmitEvent, titleInput: HTMLInputElement): void {
    event.preventDefault();
    const title = this.draftTitle().trim();

    if (title === "") {
      titleInput.setCustomValidity("Enter a task title.");
      titleInput.reportValidity();
      return;
    }

    this.titleSubmitted.emit(title);
  }
}
```

What to notice:

- `linkedSignal(() => this.task().title)` starts the draft from the task's title, and recalculates it whenever `task` changes.
- `[value]="draftTitle()"` puts the draft into the text field, and `(input)` writes each keystroke back with `draftTitle.set(...)`.
- Save emits the trimmed draft through `titleSubmitted`. Cancel emits `cancelled` with no value.
- The empty-title check uses the same browser validation as the board's add form. The [forms article](/dump/blog/forms-and-validation/) covers validation in depth.

### Ticking the checkbox wipes the draft

This version has a bug. Open the editor for "Read the DOM article", change the field to "Read the DOM notes", and then tick that task's checkbox in the list. The field jumps back to "Read the DOM article". Here's why:

1. The row emits `doneChange`, and the page's `setDone` replaces the task with a new object, `{ ...task, done: true }`.
2. The page passes the task being edited to the editor's `task` input, so the editor receives that new object.
3. `draftTitle` reads `this.task()`, so it recalculates. It returns the new object's `title`, which is the accepted title. Your typing is gone.

The draft should only start over when the editor switches to a different task. When the same task comes back as a new object, the draft should keep what you typed.

### Keep the draft for the same task

The longer form of `linkedSignal` takes an object with two properties: a `source` signal to watch, and a `computation` function that receives the new source value plus the result of the last calculation. Replace the `draftTitle` line with this:

```ts
readonly draftTitle = linkedSignal<Task, string>({
  source: this.task,
  computation: (task, previous) => {
    if (previous !== undefined && previous.source.id === task.id) {
      return previous.value;
    }

    return task.title;
  },
});
```

The `previous` argument has two fields:

- `previous.source` is the task the computation saw last time.
- `previous.value` is the draft's current value, including anything you typed with `set`.

On the very first calculation there's no last time, so `previous` is `undefined`. The `<Task, string>` part gives the source type and the draft type; Angular needs both written out when the computation uses `previous`.

Here's the same scenario with the fix, step by step:

1. You click Edit. The page creates the editor and passes "Read the DOM article" into its `task` input.
2. The template reads `draftTitle()` for the first time. `previous` is `undefined`, so the computation returns `task.title`, "Read the DOM article".
3. You change the field to "Read the DOM notes". Each keystroke calls `draftTitle.set(...)`.
4. You tick the checkbox. The page replaces the task, and the editor's `task` input receives the new object. The computation runs again: `previous.source.id` is `1` and `task.id` is `1`, so it returns `previous.value`, "Read the DOM notes". Your draft survives.
5. You click Save. The editor emits "Read the DOM notes", and the page renames the task. The task keeps `done: true`, because the page copies the current task and only replaces its title.

### One edit at a time

If the editor's `task` input switched to a task with a different ID, the computation would start a new draft from that task's title. That would silently throw away an unfinished edit, so the page prevents it: while an editor is open, every row's Edit button is disabled through `canEdit`.

When you click Save or Cancel, the page destroys the editor. Clicking Edit again creates a new editor whose draft starts from the accepted title, even for the same task.

This rule is enough here because nothing else changes a title while you type. A page that also received title changes from a server would need its own rule for what happens to a draft when that happens.

### How long each piece of state lives

The row and the editor live for different lengths of time:

- The list renders rows with `@for (...; track task.id)`. Because rows are matched by ID, a row keeps its instance, and its open details, when the page replaces its task with a new object that has the same ID.
- When the filter removes a task from the visible list, its row is destroyed. If the task comes back into view, a new row is created, and Details starts closed again.
- The editor sits outside the filtered list, so filtering never destroys it, and the draft survives.

All of this state is in memory. Reloading the page starts over from the two sample tasks.

### Move focus into the editor

When the editor appears, keyboard and screen reader users should land in its text field rather than having to find it. That takes three more pieces of Angular. Add `ElementRef`, `afterNextRender`, and `viewChild` to the editor's import list, then add these members to the class:

```ts
readonly titleInput = viewChild.required<ElementRef<HTMLInputElement>>("titleInput");

constructor() {
  afterNextRender(() => {
    const inputElement = this.titleInput().nativeElement;
    inputElement.focus();
  });
}
```

Here's what each piece does:

- `viewChild.required(...)` finds the element marked `#titleInput` in the editor's own template. It returns an `ElementRef`, a small wrapper whose `nativeElement` property is the real `<input>`.
- The constructor runs when Angular creates the editor instance. At that moment, Angular hasn't created the template's elements yet, so there's no input to focus.
- `afterNextRender` registers a callback that runs once, after Angular next finishes updating the page. By then the input exists. Angular needs `afterNextRender` to be called while it's creating the component, which is why the call sits in the constructor.

## Wrap page content with a section frame

The task list and the editor both need the same frame: a header with a heading on one side and a few actions on the other, followed by the main content. You could build that frame with inputs for the heading text, the heading level, the button labels, and the button handlers. But the frame would end up recreating markup the page can already write.

Instead, the page writes ordinary markup between the frame's opening and closing tags, and the frame marks where that markup goes. Angular calls this **content projection**. Save the frame in `task-section.ts`:

```ts
import { Component, input } from "@angular/core";

@Component({
  selector: "task-section",
  template: `
    <section [attr.aria-labelledby]="labelledBy()">
      <header class="flex flex-wrap items-start justify-between gap-3">
        <ng-content select="[data-section-heading]" />
        <div>
          <ng-content select="[data-section-actions]" />
        </div>
      </header>
      <ng-content />
    </section>
  `,
})
export class TaskSection {
  readonly labelledBy = input.required<string>();
}
```

The header keeps its Tailwind classes because arranging the heading and the actions side by side is the frame's whole job.

Here's how the page uses it for the editor:

```html
@if (editingTask(); as task) {
  <task-section labelledBy="editor-heading">
    <h2 data-section-heading id="editor-heading">Edit task {{ task.id }}</h2>
    <button data-section-actions type="button" (click)="removeTask(task.id, filterSelect)">
      Delete task
    </button>
    <task-editor
      [task]="task"
      (titleSubmitted)="renameTask(task.id, $event, filterSelect)"
      (cancelled)="closeEditor(filterSelect)"
    />
  </task-section>
}
```

What to notice:

- **Each `<ng-content>` is a slot.** `select` takes a CSS selector, and `[data-section-heading]` matches elements that have that attribute. So the `<h2>` goes into the heading slot and the button goes into the actions slot. The `data-section-*` names are this example's own; any attribute would work.
- **Anything that matches no `select` goes into the plain `<ng-content />`.** Here that's the editor.
- **`<ng-content>` isn't an element.** Angular replaces it at build time with the projected content, so it adds nothing to the DOM. The `<header>` and the actions `<div>` come from the frame's own template.
- **`labelledBy="editor-heading"` has no brackets**, so it passes the plain string `editor-heading` to the input. The frame puts it in `aria-labelledby`, which tells screen readers to name the section with the text of the heading that has that `id`.
- **`@if (editingTask(); as task)`** renders the block only while a task is being edited, and `as task` names that task so the block can use it.

### Projected markup uses the page's data and methods

The Delete button renders inside `TaskSection`, but it's written in the page's template. So `task.id` and `removeTask(...)` come from the page. `TaskSection` has no `task` and no `removeTask` method, and it doesn't need them. The same goes for `{{ task.id }}` in the heading.

When you read a template, the component that wraps some content isn't necessarily the one that supplies its data and handlers. Look at whose template the markup is written in.

Angular always creates projected content, even if the frame hides its `<ng-content>`. That's why the page wraps the whole section in its own `@if`: with no task being edited, the editor isn't created at all, and closing the editor destroys it along with its draft.

## Put the page together

The page is the board from the styling article with a few additions, renamed to `TaskPage` in `task-page.ts`. Here's the top of the class, with the template left out until further down:

```ts
import { Component, computed, signal } from "@angular/core";
import type { Task } from "./task";
import { TaskEditor } from "./task-editor";
import { TaskRow } from "./task-row";
import { TaskSection } from "./task-section";

type TaskFilter = "all" | "active" | "completed";

@Component({
  selector: "task-page",
  imports: [TaskEditor, TaskRow, TaskSection],
  template: `...`,
})
export class TaskPage {
  readonly tasks = signal<Task[]>([
    { id: 1, title: "Read the DOM article", done: false },
    { id: 2, title: "Review the CSS layout", done: false },
  ]);
  readonly filter = signal<TaskFilter>("all");
  readonly editingId = signal<number | undefined>(undefined);
  private nextId = 3;

  readonly editingTask = computed(() => {
    const id = this.editingId();
    for (const task of this.tasks()) {
      if (task.id === id) {
        return task;
      }
    }
    return undefined;
  });

  // remaining, visibleTasks, addTask, setFilter, and setDone stay as they were in the board.
}
```

What's new:

- The page starts with two sample tasks, so the rows and the editor have something to show, and `nextId` starts after them.
- `editingId` holds the ID of the task being edited, or `undefined` when nothing is.
- `editingTask` looks that ID up in the current tasks. Whenever the page replaces the task, `editingTask` returns the new object, which is how the editor's `task` input receives it.

Then add the methods the row and the editor's outputs call:

```ts
startEditing(id: number): void {
  this.editingId.set(id);
}

renameTask(id: number, title: string, filterSelect: HTMLSelectElement): void {
  this.tasks.update((current) => {
    const next: Task[] = [];
    for (const task of current) {
      if (task.id === id) {
        next.push({ ...task, title });
      } else {
        next.push(task);
      }
    }
    return next;
  });

  this.closeEditor(filterSelect);
}

closeEditor(filterSelect: HTMLSelectElement): void {
  this.editingId.set(undefined);
  filterSelect.focus();
}

removeTask(id: number, filterSelect: HTMLSelectElement): void {
  this.tasks.update((current) => {
    const next: Task[] = [];
    for (const task of current) {
      if (task.id !== id) {
        next.push(task);
      }
    }
    return next;
  });

  if (this.editingId() === id) {
    this.editingId.set(undefined);
  }
  filterSelect.focus();
}
```

What to notice:

- `renameTask` copies the current task with `...task` and replaces only `title`, so a task you ticked while editing stays done.
- Deleting the task that's being edited also closes the editor, so a draft can never be saved into a task the page has removed.
- Save, Cancel, and Delete all remove the button that was just clicked, either with its row or with the editor. Moving focus to the filter keeps keyboard users somewhere useful instead of losing focus to the top of the page.

The template has two sections inside `<main>`. The first is the task list, now wrapped in `<task-section>` with the filter as its action:

```html
<main>
  <task-section labelledBy="tasks-heading">
    <h1 data-section-heading id="tasks-heading">Task notes</h1>
    <div data-section-actions>
      <label for="task-filter">Show tasks</label>
      <select
        #filterSelect
        id="task-filter"
        [value]="filter()"
        (change)="setFilter(filterSelect.value)"
      >
        <option value="all">All</option>
        <option value="active">Active</option>
        <option value="completed">Completed</option>
      </select>
    </div>

    <!-- The add-task form from the board goes here, unchanged. -->

    <p aria-live="polite">Remaining tasks: {{ remaining() }}</p>
    @if (editingTask()) {
      <p>Save or cancel the current edit before starting another.</p>
    }
    <ul id="task-list" role="list">
      @for (task of visibleTasks(); track task.id) {
        <li>
          <task-row
            [task]="task"
            [canEdit]="editingId() === undefined"
            (doneChange)="setDone(task, $event, filterSelect)"
            (editRequested)="startEditing(task.id)"
            (deleteRequested)="removeTask(task.id, filterSelect)"
          />
        </li>
      }
    </ul>
    <p [hidden]="visibleTasks().length > 0">No tasks to show.</p>
  </task-section>
```

The second is the editor section from [Wrap page content with a section frame](#wrap-page-content-with-a-section-frame). Put it after the list section, then close `</main>`. Because the editor section sits outside the `@for` loop, filtering the list never touches it.

`#filterSelect` is declared inside the first section, but the editor section can still use it. A template reference declared outside any `@if` or `@for` block is visible everywhere in that template, including inside those blocks. Markup between a component's tags, like the content of `<task-section>`, still counts as part of the page's template.

Finally, in the application's entry point, bootstrap `TaskPage` instead of `TaskBoard`, and change the host page's `<task-board></task-board>` to `<task-page></task-page>`:

```ts
import { bootstrapApplication } from "@angular/platform-browser";
import { TaskPage } from "./task-page";

await bootstrapApplication(TaskPage);
```

### Trace one save

Here's the whole rename, from click to updated list:

```text
Edit button → row emits editRequested
            → page sets editingId
            → @if creates the editor → first draftTitle() read starts the draft
Typing      → editor changes draftTitle only
Save title  → editor emits titleSubmitted(string)
            → page replaces the task with a renamed copy
            → page clears editingId
            → @if destroys the editor; the row receives the renamed task
```

The section frame never decides anything along the way. The row and the editor report what the user did, and the page changes the tasks.

## When to extract a component

A file getting long is a reason to look, not a reason to split. Pulling a chunk of template into its own component sometimes makes the page easier to follow, and sometimes it just means you jump between three files to follow one click. These questions help you tell which:

- **Can you say in one sentence what goes in and what comes out?** For the row: a task goes in, and done, edit, and delete clicks come out. If a split would need the whole parent component passed in, or a long list of unrelated flags, it's in the wrong place.
- **Do its parts belong together?** The editor's draft, text field, Save button, and Cancel button are created together, used together, and destroyed together. That shared lifetime is a good reason for a component, even though only one editor ever shows at a time.
- **Does it handle something so the parent doesn't have to?** The row handles its details toggle completely. A component that only passes inputs down and outputs up adds a file without taking any work off the parent.
- **Can you still trace one operation?** Follow one click, the way the trace above follows a save. If finding which component reads the data, which one changes it, and which one decides means opening several components that only pass things along, the split made the feature harder to follow.

A component that only adds some padding usually fails these questions, so a `<div>` with a class is clearer. Repeated markup is worth noticing, but a little duplication is fine until you can see what the repeated pieces actually share.

When components far apart in the tree genuinely need the same feature state, passing it through every component in between gets tedious. Angular's dependency injection can give those components a shared object instead; the [dependency injection article](/dump/blog/angular-dependency-injection/) explains how. This page's parents and children are directly connected, so inputs and outputs are enough.

That also answers the question from the start. Your half-typed title survives ticking the checkbox because `draftTitle` keeps its value while the task ID stays the same. It survives a filter change because the editor lives outside the filtered list. And Cancel brings back the old title because typing only ever changed the editor's draft. The page's task didn't change until you clicked Save.

## Closing check

1. Why does the page, not the row, hold which task is being edited?
2. The row emits `doneChange`, but the page has no `(doneChange)` listener. What happens to the task and the remaining count?
3. Why does `linkedSignal(() => this.task().title)` lose your draft when you tick the checkbox, and what does the fixed version compare?
4. The projected Delete button calls `removeTask(task.id, ...)`. Where do `task` and `removeTask` come from?

Check your reasoning:

- The filter can destroy the row. The editor has to stay open when that happens, so the selection lives in the page, which outlives every row.
- Nothing changes. The checkbox shows a tick, but only a listener on the page can replace the task, so `done` and the count stay the same.
- Ticking the checkbox gives the editor a new task object, and the simple version recalculates from it, returning the accepted title. The fixed version compares `previous.source.id` with the new task's `id` and keeps `previous.value` when they match.
- From the page. The button is written in the page's template, so it uses the page's `@if` variable and the page's method, even though it renders inside `TaskSection`.

## Sources and further reading

- [Angular: component inputs](https://angular.dev/guide/components/inputs)
- [Angular: custom events with outputs](https://angular.dev/guide/components/outputs)
- [Angular: content projection](https://angular.dev/guide/components/content-projection)
- [Angular: dependent writable state with linkedSignal](https://angular.dev/guide/signals/linked-signal)
- [Angular: component lifecycle and render callbacks](https://angular.dev/guide/components/lifecycle)
- [Angular: queries and template references](https://angular.dev/guide/components/queries)
- [Angular: using DOM APIs](https://angular.dev/guide/components/dom-apis)
- [Angular: control flow and tracked identity](https://angular.dev/guide/templates/control-flow)
- [Angular: hierarchical dependency injection](https://angular.dev/guide/di/hierarchical-dependency-injection)
