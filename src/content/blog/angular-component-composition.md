---
title: "Building components with clear ownership"
description: "Use an extraction litmus, assign state owners, design typed inputs and outputs, and give edit drafts and projected content deliberate boundaries."
pubDate: "2026-10-06"
tags:
  - angular
  - components
  - frontend
---

A task row displays a title and a checkbox. An editor lets someone change that title without committing each keystroke. The task page must keep the list, filter, and remaining count consistent with the accepted task records.

These pieces need different responsibilities. Moving their markup into separate files does not, by itself, explain who may change a task, what cancelling means, or how long unsaved text should survive.

This article builds on the row from [Components + Tailwind](/dump/blog/frontend-evolution-styling/). It adds an editor and a small section with caller-supplied content. The examples use Angular 22.2.1 and the same Tailwind 4 styling setup; the styling article contains the shared dark/light palette and installation link.

The [values and identity article](/dump/blog/values-references-and-identity/) explains object sharing and signal updates. The [behavior article](/dump/blog/frontend-evolution-behavior/) explains the task form, filtering, and count. Here the focus is the contract between components—not an exhaustive Angular API guide.

## Contents

1. [Apply a litmus before extracting a component](#apply-a-litmus-before-extracting-a-component)
2. [Give each piece of state an owner](#give-each-piece-of-state-an-owner)
3. [Inputs describe what a component needs](#inputs-describe-what-a-component-needs)
4. [Outputs report across the boundary](#outputs-report-across-the-boundary)
5. [An edit draft needs a deliberate lifetime](#an-edit-draft-needs-a-deliberate-lifetime)
6. [Projection lets the caller supply composition](#projection-lets-the-caller-supply-composition)
7. [Prove the boundaries through their consumer](#prove-the-boundaries-through-their-consumer)

## Apply a litmus before extracting a component

A shorter template is not sufficient evidence that a component boundary helps. Splitting one understandable operation across several files can make it harder to follow.

Before extracting a piece, ask:

- **Can its responsibility be named?** “Task editor” explains a job. “The div around these three elements” only identifies markup.
- **Do its parts belong together?** Structure, interaction, local state, or a meaningful lifetime can make a cohesive piece. Sharing a border color does not necessarily do so.
- **Can its consumer describe the contract simply?** A task goes in; a requested change comes out. Passing the whole parent or many unrelated flags suggests that the boundary is unclear.
- **Does the boundary reduce what must be understood together?** A useful component hides its own coordination. A component that only forwards several inputs and outputs may add navigation without adding responsibility.

This is a reasoning aid, not a score where a certain number of answers mandates extraction. Keep a piece inline when the proposed boundary only makes the file shorter. Extract when it creates an understandable responsibility, contract, or lifetime.

Apply it to this interface:

- **Task row:** its label, checkbox, title presentation, and row actions belong together. It receives a task and reports interactions. Reuse is useful, but cohesion also justifies the boundary.
- **Task editor:** its draft, title field, save/cancel behavior, and creation/destruction belong together. That lifetime justifies a boundary even if only one editor is visible.
- **A padding wrapper:** if it adds no useful contract or shared composition, ordinary markup and classes may be clearer.

Repeated code is evidence to examine, not an automatic extraction trigger. A little duplication can reveal whether two pieces really share a concept before they acquire one configuration-heavy API.

## Give each piece of state an owner

The accepted task records are the data used by the list, filter, and count. They are the **canonical state**: the application's current accepted version, rather than an unfinished edit.

For this example:

```text
TaskPage
  owns accepted tasks, the filter, and which task is being edited
      │
      ├── task → TaskRow
      │           owns whether its details are expanded
      │           reports completion, edit, and deletion requests
      │
      └── task → TaskEditor
                  owns an unfinished title draft
                  reports a submitted title or cancellation
```

The remaining count and filtered list are derived from the tasks. They do not need separately writable copies that every operation must remember to synchronize.

A draft is different. It intentionally may disagree with the accepted title while someone types. The important distinction is not “all copies are bad”; it is whether the copy has an explicit purpose, owner, and point at which it becomes accepted.

The page owns edit selection because the editor must remain open when filtering hides its row. Only one task is edited at a time. The row's details toggle can disappear with the row; an unfinished title should not disappear merely because the filter changed.

State belongs where its consumers and lifetime require it—not automatically in the nearest component, a global store, or every component that receives the value.

The shared task type stays small. Save it in `task.ts`:

```ts
export interface Task {
  id: number;
  title: string;
  done: boolean;
}
```

## Inputs describe what a component needs

When the page renders a row, it supplies the task the row should display. It can also temporarily prevent another edit from starting:

```html
<task-row
  [task]="task"
  [canEdit]="editingId() === undefined"
  (doneChange)="setDone(task.id, $event, filterSelect)"
  (editRequested)="startEditing(task.id)"
  (deleteRequested)="removeTask(task.id, filterSelect)"
/>
```

This is a usage excerpt from the complete page below. The loop supplies `task`; `filterSelect` names the page's native select element.

The `[task]` binding supplies data to a named component **input**. The row declares that contract with `input.required<Task>()`. Calling `task()` reads the supplied value. A missing required input is a template-compilation error.

`input(true)` supplies a default for `canEdit`. The row is normally editable; this particular consumer passes `false` while an editor is open. That is a concrete interaction policy, not a collection of speculative options or an authorization check.

Save the row in `task-row.ts`:

```ts
import { Component, input, output, signal } from "@angular/core";
import type { Task } from "./task";

@Component({
  selector: "task-row",
  host: { class: "block" },
  template: `
    <div class="rounded-lg border border-line bg-surface p-3">
      <div class="flex flex-wrap items-start gap-3">
        <label class="flex min-w-0 grow basis-48 items-start gap-3">
          <input
            #checkbox
            type="checkbox"
            class="mt-1 size-4 shrink-0 accent-accent focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
            [checked]="task().done"
            (change)="doneChange.emit(checkbox.checked)"
          />
          <span
            class="min-w-0 break-words"
            [class.line-through]="task().done"
            [class.text-muted]="task().done"
          >
            {{ task().title }}
          </span>
        </label>
        <div class="flex flex-wrap gap-2">
          <button
            type="button"
            class="rounded border border-line px-3 py-1 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent disabled:opacity-60"
            [disabled]="!canEdit()"
            [attr.aria-label]="'Edit ' + task().title"
            (click)="editRequested.emit()"
          >
            Edit
          </button>
          <button
            type="button"
            class="rounded border border-line px-3 py-1 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
            [attr.aria-expanded]="detailsOpen()"
            [attr.aria-controls]="'task-details-' + task().id"
            (click)="toggleDetails()"
          >
            Details
          </button>
          <button
            type="button"
            class="rounded border border-line px-3 py-1 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
            [attr.aria-label]="'Delete ' + task().title"
            (click)="deleteRequested.emit()"
          >
            Delete
          </button>
        </div>
      </div>
      <p
        class="mt-3 text-sm text-muted"
        [id]="'task-details-' + task().id"
        [hidden]="!detailsOpen()"
      >
        Task identifier: {{ task().id }}
      </p>
    </div>
  `,
})
export class TaskRow {
  readonly task = input.required<Task>();
  readonly canEdit = input(true);
  readonly doneChange = output<boolean>();
  readonly editRequested = output<void>();
  readonly deleteRequested = output<void>();
  readonly detailsOpen = signal(false);

  toggleDetails() {
    this.detailsOpen.set(!this.detailsOpen());
  }
}
```

The row does not receive a parent instance, the full task collection, or methods for reaching into page state. Its local details toggle needs no round trip to the page.

### A read-only input does not freeze its object

The input signal does not offer the row a `set(...)` method. That does not make the task object immutable. With this interface, assigning to `this.task().title` would still be legal TypeScript—and would mutate a shared object.

Receiving an object neither copies it nor transfers ownership. Here the contract is that rows read tasks and report requests. The page applies accepted changes. That rule is an ownership decision; `input.required()` does not enforce it by freezing data.

## Outputs report across the boundary

The checkbox changes first. The row reads its native `checked` property and emits a boolean. The page's listener receives that boolean and decides how to update its tasks.

An Angular **output** is the component's named event interface. `output<boolean>()` declares a payload type; `emit(...)` reports a value. In `(doneChange)`, `$event` is that value, not a native DOM `Event`.

`editRequested` and `deleteRequested` carry no payload because the consumer already knows which task it rendered. Their names communicate specific interactions instead of a generic “something changed” event. The page decides whether and how to act on them.

Emitting does not automatically update canonical state. Without a listener applying the request, the model does not change. The native checkbox can temporarily show its own changed checked state; that alone is not an accepted task update or a new remaining count.

Angular outputs also do not bubble through the DOM like native `click` events. Putting `(deleteRequested)` on a surrounding `<div>` does not subscribe to every row's output. Bind at the component that declares the output. A wrapper that needs to expose an interaction must deliberately declare and forward a contract—or stop being an unnecessary wrapper.

Forwarding once is not inherently wrong. The question from the litmus still applies: does the intermediate component own meaningful behavior, or merely make consumers follow another link?

## An edit draft needs a deliberate lifetime

Typing into the shared task object's `title` would change accepted data immediately. A Cancel button could close the editor, but it could not undo that mutation merely by existing.

Instead, the editor starts with a string draft and changes only that draft. Saving submits its value; cancelling submits no title. The page remains the owner of accepted records.

The lifetime in this example is explicit:

1. Selecting a task creates an editor instance and initializes its draft from that task.
2. Typing changes the editor's draft, not the accepted task.
3. Completion updates and filter changes do not replace the draft.
4. Save updates the accepted title, then closes the editor. Cancel closes without updating it.
5. Closing destroys the editor instance. Opening another edit creates a fresh instance with a fresh draft.

The draft needs both an initial value and a reset rule: read the supplied task, keep the previous draft if it belongs to the same task ID, and otherwise start with the supplied title. Angular's `linkedSignal` expresses that writable dependent state without a method-based lifecycle hook.

Save this component in `task-editor.ts`:

```ts
import {
  Component,
  ElementRef,
  afterNextRender,
  input,
  linkedSignal,
  output,
  viewChild,
} from "@angular/core";
import type { Task } from "./task";

@Component({
  selector: "task-editor",
  host: { class: "block" },
  template: `
    <form class="space-y-3" (submit)="submitTitle($event, titleInput)">
      <label for="draft-title" class="block font-medium">New task title</label>
      <input
        #titleInput
        id="draft-title"
        name="title"
        type="text"
        required
        class="block w-full min-w-0 rounded-lg border border-muted bg-surface px-3 py-2 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
        [value]="draftTitle()"
        (input)="draftTitle.set(titleInput.value); titleInput.setCustomValidity('')"
      />
      <div class="flex flex-wrap gap-2">
        <button
          type="submit"
          class="rounded-lg bg-accent px-4 py-2 font-medium text-page hover:bg-accent-strong focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
        >
          Save title
        </button>
        <button
          type="button"
          class="rounded-lg border border-line px-4 py-2 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
          (click)="cancelled.emit()"
        >
          Cancel
        </button>
      </div>
    </form>
  `,
})
export class TaskEditor {
  readonly task = input.required<Task>();
  readonly titleSubmitted = output<string>();
  readonly cancelled = output<void>();
  readonly draftTitle = linkedSignal<Task, string>({
    source: this.task,
    computation: (task, previous) => {
      if (previous?.source.id === task.id) {
        return previous.value;
      }

      return task.title;
    },
  });
  readonly titleInput = viewChild.required<ElementRef<HTMLInputElement>>("titleInput");

  constructor() {
    afterNextRender(() => {
      const inputElement = this.titleInput().nativeElement;
      inputElement.focus();
    });
  }

  submitTitle(event: SubmitEvent, inputElement: HTMLInputElement) {
    event.preventDefault();
    const title = this.draftTitle().trim();

    if (title === "") {
      inputElement.setCustomValidity("Enter a task title.");
      inputElement.reportValidity();
      return;
    }

    this.titleSubmitted.emit(title);
  }
}
```

Declaring this linked signal passes functions; it does not immediately read the required input. The template's first `draftTitle()` read computes the initial title after Angular supplies `task`. The resulting signal remains writable, so typing still uses `draftTitle.set(...)`.

In this form, `source` supplies the task to the computation. On a later input change, `previous.source` is the task used for the previous computation, and `previous.value` is the current draft—including any local edits. On the first computation, there is no previous value. The explicit `<Task, string>` types describe the source and draft value.

The native form keeps the existing basic title validation. Detailed validation and form-state design belong to the forms article.

For focus, `viewChild` finds the element named `#titleInput` in the editor's own template. `ElementRef.nativeElement` provides the native input. `afterNextRender`, registered in the constructor, schedules the focus operation after Angular renders the page. It does not initialize or synchronize the draft. These are separate jobs.

### Resetting is an ownership policy

The simple `linkedSignal(() => this.task().title)` would reset the draft when the task input object is replaced—even if only `done` changed. Choosing this API does not automatically choose the right reset policy.

Here the computation compares task IDs and returns `previous.value` for the same task. If the page replaces that task object after a completion change, the existing editor receives the new input without losing unfinished text.

That is intentional here. The editor changes a title; the page applies it to the current record, preserving its current completion value. The application has no server or competing title editor. Adding either would require an explicit conflict/reset policy, not an automatic copy on every input change.

Supplying a different task ID would start a draft from that task's title. This page still disables other Edit buttons until Save or Cancel closes the current editor, so switching tasks cannot silently discard an unfinished edit. The `@if` below destroys the old instance before another edit begins; a fresh instance starts from the accepted title even when the same task is reopened.

Rows have a different lifetime. Their local details state survives replacement of a task record with the same ID because the list tracks `task.id`. If filtering removes a row from the rendered list, that row instance is destroyed; Details starts closed when it is rendered again. The editor stays open because it is outside that filtered list.

Component-local state is not permanent state. This demonstration is in memory; a page reload resets it.

## Projection lets the caller supply composition

A page sometimes needs the same section frame around different content. The frame owns the arrangement; the caller owns the actual heading, actions, and body. Reconstructing all that content through title strings, button flags, and callback options would give the frame responsibilities it does not need.

The caller can instead write ordinary markup between the section component's opening and closing tags. The section marks where that markup belongs. Angular calls this **content projection**.

Save the small frame in `task-section.ts`:

```ts
import { Component, input } from "@angular/core";

@Component({
  selector: "task-section",
  host: { class: "block" },
  template: `
    <section class="mb-6" [attr.aria-labelledby]="labelledBy()">
      <header class="mb-4 flex flex-wrap items-start justify-between gap-3">
        <ng-content select="[data-section-heading]" />
        <div class="flex flex-wrap gap-2">
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

The selected placeholders receive direct content whose static attributes match their selectors. The unselected placeholder receives the remaining content. The `data-section-*` names are this example's conventions, not Angular input properties.

`<ng-content>` is a compiler placeholder, not a DOM element that creates another wrapper. Any wrappers come from the section's actual template, such as its `<header>` and action `<div>`.

The required `labelledBy` value points the section's accessible name at the caller-supplied heading ID. It supplies a value; projection supplies the heading element itself. The page can choose an `<h1>` for its task list and an `<h2>` for its editor without asking the frame to manufacture tags from configuration.

This example uses the frame for two real regions. It shares a heading/actions/body arrangement, not task editing logic. The extraction litmus still applies: if there were only one trivial wrapper and no useful shared arrangement, keeping it inline would be reasonable. Projection is a capability, not a requirement to invent a container library.

### Projected bindings still belong to their caller

The editor section below contains a projected Delete button. Its `task.id` expression and click handler are declared in `TaskPage`, so they use that page's context. Rendering the button inside `TaskSection` does not move its bindings into the section class or transfer ownership of the task.

That distinction matters when reading a template: the component around some content need not be the component that owns its data and handlers.

### Hiding a placeholder is not lazy creation

A projection placeholder does not give the receiving component control over whether caller-authored content is created. Angular creates projected content even when a receiving placeholder is hidden; putting the placeholder inside an `@if` is not a reliable way to defer that work.

In this example, the page's `@if` surrounds the entire editor section and its caller-authored editor. With no selection, that branch is not created. Closing it destroys the editor and its draft. That is different from creating an editor and merely hiding where it is projected.

When a container must choose when to instantiate caller-supplied content, Angular has template-fragment mechanisms. They are not needed for this section's simple arrangement and are outside this article's scope.

## Prove the boundaries through their consumer

The complete page brings the contracts together. Compared with the earlier task board, it adds selected edit state and owner methods; it does not distribute writable task collections among the children.

**Example presentation:** The page's class and long template are shown in separate files below to make each block easier to follow.

To run the example as presented, save its class in `task-page.ts` and its template in `task-page.html`, then bootstrap `TaskPage` in place of the earlier `TaskBoard`. The sample starts with two task records so the component boundaries are immediately visible.

```ts
import { Component, computed, signal } from "@angular/core";
import type { Task } from "./task";
import { TaskEditor } from "./task-editor";
import { TaskRow } from "./task-row";
import { TaskSection } from "./task-section";

@Component({
  selector: "task-page",
  imports: [TaskEditor, TaskRow, TaskSection],
  templateUrl: "./task-page.html",
})
export class TaskPage {
  readonly tasks = signal<Task[]>([
    { id: 1, title: "Read the DOM article", done: false },
    { id: 2, title: "Review the CSS layout", done: false },
  ]);
  readonly filter = signal<"all" | "active" | "completed">("all");
  readonly editingId = signal<number | undefined>(undefined);
  private nextId = 3;

  readonly remaining = computed(() => {
    let count = 0;
    for (const task of this.tasks()) {
      if (!task.done) {
        count++;
      }
    }
    return count;
  });

  readonly visibleTasks = computed(() => {
    const filter = this.filter();
    const visible: Task[] = [];
    for (const task of this.tasks()) {
      if (filter === "active" && task.done) {
        continue;
      }
      if (filter === "completed" && !task.done) {
        continue;
      }
      visible.push(task);
    }
    return visible;
  });

  readonly editingTask = computed(() => {
    const id = this.editingId();
    for (const task of this.tasks()) {
      if (task.id === id) {
        return task;
      }
    }
    return undefined;
  });

  addTask(event: SubmitEvent, inputElement: HTMLInputElement) {
    event.preventDefault();
    const title = inputElement.value.trim();
    if (title === "") {
      inputElement.setCustomValidity("Enter a task title.");
      inputElement.reportValidity();
      return;
    }
    this.tasks.set([...this.tasks(), { id: this.nextId++, title, done: false }]);
    inputElement.value = "";
    inputElement.setCustomValidity("");
    inputElement.focus();
  }

  setFilter(value: string) {
    if (value !== "all" && value !== "active" && value !== "completed") {
      throw new Error("Unknown task filter.");
    }
    this.filter.set(value);
  }

  setDone(id: number, done: boolean, filterSelect: HTMLSelectElement) {
    const updated = this.tasks().map((task) => {
      if (task.id === id) {
        return { ...task, done };
      }

      return task;
    });
    this.tasks.set(updated);

    const hiddenByActiveFilter = this.filter() === "active" && done;
    const hiddenByCompletedFilter = this.filter() === "completed" && !done;
    if (hiddenByActiveFilter || hiddenByCompletedFilter) {
      filterSelect.focus();
    }
  }

  startEditing(id: number) {
    this.editingId.set(id);
  }

  renameTask(id: number, title: string, filterSelect: HTMLSelectElement) {
    const updated = this.tasks().map((task) => {
      if (task.id === id) {
        return { ...task, title };
      }

      return task;
    });
    this.tasks.set(updated);
    this.closeEditor(filterSelect);
  }

  closeEditor(filterSelect: HTMLSelectElement) {
    this.editingId.set(undefined);
    filterSelect.focus();
  }

  removeTask(id: number, filterSelect: HTMLSelectElement) {
    const kept = this.tasks().filter((task) => task.id !== id);
    this.tasks.set(kept);
    if (this.editingId() === id) {
      this.editingId.set(undefined);
    }
    filterSelect.focus();
  }
}
```

The owner updates current records rather than mutating a child-supplied object. Renaming preserves the record's current `done` value. Deleting the edited task also ends its editor; a draft cannot be saved back into a record this page has removed.

```html
<main class="mx-auto max-w-2xl px-4 py-8">
  <task-section labelledBy="tasks-heading">
    <h1 data-section-heading id="tasks-heading" class="text-3xl font-semibold">Task notes</h1>
    <button
      data-section-actions
      type="button"
      class="rounded-lg border border-line px-3 py-2 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
      (click)="setFilter('all'); filterSelect.focus()"
    >
      Show all tasks
    </button>

    <form class="mb-6 space-y-2" (submit)="addTask($event, titleInput)">
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
    <p class="my-4" aria-live="polite">Remaining tasks: {{ remaining() }}</p>
    @if (editingTask()) {
    <p class="mb-4 text-muted">Save or cancel the current edit before starting another.</p>
    }
    <ul id="task-list" class="space-y-2" role="list">
      @for (task of visibleTasks(); track task.id) {
      <li>
        <task-row
          [task]="task"
          [canEdit]="editingId() === undefined"
          (doneChange)="setDone(task.id, $event, filterSelect)"
          (editRequested)="startEditing(task.id)"
          (deleteRequested)="removeTask(task.id, filterSelect)"
        />
      </li>
      }
    </ul>
    <p class="text-muted" [hidden]="visibleTasks().length > 0">No tasks to show.</p>
  </task-section>

  @if (editingTask(); as task) {
  <task-section labelledBy="editor-heading">
    <h2 data-section-heading id="editor-heading" class="text-xl font-semibold">
      Edit task {{ task.id }}
    </h2>
    <button
      data-section-actions
      type="button"
      class="rounded-lg border border-line px-3 py-2 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
      (click)="removeTask(task.id, filterSelect)"
    >
      Delete edited task
    </button>
    <task-editor
      [task]="task"
      (titleSubmitted)="renameTask(task.id, $event, filterSelect)"
      (cancelled)="closeEditor(filterSelect)"
    />
  </task-section>
  }
</main>
```

Use `<task-page></task-page>` in the host document and bootstrap the new page:

```ts
import { bootstrapApplication } from "@angular/platform-browser";
import { TaskPage } from "./task-page";

bootstrapApplication(TaskPage);
```

The page template places the editor section after the filtered list, not inside a row. The form receives focus on creation. Save, Cancel, and deletion return focus to the existing filter control rather than leave it on a removed element. The native labels, checkbox interaction, live count, and list role remain part of the interface; component extraction does not supply them automatically.

### Trace one save

```text
Edit button → row emits editRequested
             → page sets editingId
             → @if creates editor → first draftTitle() read starts its draft
Typing      → editor changes draftTitle only
Save title  → editor emits titleSubmitted(string)
             → page replaces the current task's title
             → page clears editingId
             → editor is destroyed; rows receive the accepted task
```

The section arranges the content but does not decide any of those task changes. The row and editor report interactions; the feature owner applies them.

This is a useful final form of the extraction litmus: read the consumer and trace one operation. If identifying who reads, who changes, and who decides requires inspecting several unrelated wrappers, the decomposition has not made the feature clearer.

### Inputs and outputs are not an endless forwarding requirement

When several distant consumers genuinely share feature state, a feature-owned object supplied through dependency injection can be appropriate. That gives those consumers access to the same owner without passing every interaction through a chain of presentation components.

It is not permission to move every row toggle into an application-wide store. Choose the provider scope and lifetime to match the feature. The [dependency injection article](/dump/blog/angular-dependency-injection/) explains that mechanism; this example's direct parent/child contracts do not need another state layer.

## Closing check

1. What makes the editor a useful extraction even if only one is rendered?
2. Why can the row read a task without owning or copying it?
3. What changes automatically when an output is emitted, and what requires an owner listener?
4. Why does cancelling preserve the accepted title here?
5. Why does filtering away a row reset Details but preserve the editor draft?
6. Whose context supplies the projected Delete button's `task.id` and handler?

Check your reasoning:

- The editor has cohesive behavior and an intentional draft lifetime, not merely several reusable declarations.
- An input supplies a value; a shared object reference does not transfer ownership or create a copy.
- Emission notifies subscribed listeners. The page's listener performs the task update; the output itself does not update its collection.
- Typing changes a separate string draft. Cancel closes the editor without applying that draft.
- The row is created by the filtered loop; the editor is created by a separate page-owned selection branch.
- The declaring page owns those bindings even though the section determines where the button renders.

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
