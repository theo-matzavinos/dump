---
title: "Making the whole interaction accessible"
description: "Follow a task from keyboard activation to dialog editing, feedback, and a sensible focus destination—not just a collection of ARIA attributes."
pubDate: "2026-10-06"
tags:
  - accessibility
  - angular
  - frontend
---

A task interface can look complete and still fail halfway through an interaction. An Edit icon may have no useful name. An editor may open while keyboard focus stays behind it. Deleting a row may remove the very button someone was using, leaving no clear place to continue.

Accessibility means people can perceive the information, operate the controls, understand the result, and continue. A useful check is therefore a whole task—not whether each element has an attribute containing `aria`.

This article follows the task interface from the [component ownership article](/dump/blog/angular-component-composition/). It uses ordinary HTML controls and an Angular editor shown in a native dialog. The examples use Angular 22.2.1 and the [styling article's Tailwind 4 setup and dark/light palette](/dump/blog/frontend-evolution-styling/#define-the-shared-palette-once).

The previous editor was non-modal: filtering could happen while it stayed open. This example deliberately changes that interaction. A **modal** editor temporarily prevents interaction with the rest of the page until it closes. That is useful here for demonstrating entry, dismissal, and focus restoration; a dialog is not automatically better than an inline editor.

## Contents

1. [The interface has more than one representation](#the-interface-has-more-than-one-representation)
2. [Native semantics provide behavior and meaning](#native-semantics-provide-behavior-and-meaning)
3. [Keyboard operation is an interaction contract](#keyboard-operation-is-an-interaction-contract)
4. [Focus must survive changes to the interface](#focus-must-survive-changes-to-the-interface)
5. [State and feedback must be perceivable](#state-and-feedback-must-be-perceivable)
6. [Visual styling still carries responsibilities](#visual-styling-still-carries-responsibilities)
7. [Verify the complete task](#verify-the-complete-task)

## The interface has more than one representation

Imagine a button drawn as a pencil. A sighted person may recognize the drawing and infer “edit this task.” That inference is not necessarily information the browser can give another tool.

There are several related representations:

- The **visual interface** is what the browser draws: text, colors, positions, and shapes.
- The **DOM** is the live structure of elements and text that JavaScript and Angular work with.
- The **accessibility tree** is the browser's representation for accessibility APIs. It exposes useful objects and properties, rather than simply repeating every DOM element.

Assistive technology uses those APIs to present or operate the interface. For example, a screen reader can announce controls and let someone navigate by headings. It does not just read every HTML tag aloud.

For a control, three properties are especially useful:

| Property        | The question it answers        | Task example                    |
| --------------- | ------------------------------ | ------------------------------- |
| Role            | What kind of thing is this?    | Button, checkbox, or text field |
| Accessible name | Which thing or action is it?   | “Edit Read the DOM article”     |
| State           | What is its current condition? | Checkbox checked; input invalid |

### Names identify; descriptions explain

An **accessible name** is the label the browser computes for an object. It answers “What is this control or region?” A button's text often supplies it. An associated `<label>` supplies a text field's name.

An **accessible description** supplies additional information: instructions, a format requirement, or a validation message. It answers “What else should someone know about using this?” It does not replace the name.

These three attributes have two different jobs:

| Attribute          | Job                                     | Where the text comes from                             |
| ------------------ | --------------------------------------- | ----------------------------------------------------- |
| `aria-label`       | Supplies the accessible **name**        | Text written directly in the attribute                |
| `aria-labelledby`  | Supplies the accessible **name**        | Text from elements referenced by their IDs            |
| `aria-describedby` | Supplies the accessible **description** | Supporting text from elements referenced by their IDs |

This small dialog excerpt illustrates the two separate properties:

```html
<dialog aria-labelledby="example-heading" aria-describedby="example-help">
  <h2 id="example-heading">Edit task title</h2>
  <p id="example-help">Save accepts your changes. Cancel discards them.</p>
  <!-- Editor controls would go here. -->
</dialog>
```

The dialog's **name** is “Edit task title”. Its **description** is “Save accepts your changes. Cancel discards them.” The heading identifies the dialog; the paragraph explains how the edit works.

Using `aria-label="Edit task title"` instead of `aria-labelledby` would supply that same name directly, without referencing the heading. When suitable visible text already exists, referencing it avoids maintaining a separate copy of the name. For ordinary form fields, prefer their native `<label>` and use `aria-describedby` to associate additional help or errors.

Names and descriptions are separate browser properties, not a promise of an exact spoken sentence or announcement order. Screen-reader presentation and settings vary.

The browser does not reliably infer an action from an arbitrary drawing. An unnamed icon-only button is therefore incomplete even if the icon looks obvious. Fixing only that name still leaves keyboard behavior, feedback, and focus to examine.

## Native semantics provide behavior and meaning

Use elements that match the job:

- A `<button>` performs an action.
- An `<a href="…">` navigates to a location.
- An `<input type="checkbox">` represents a checked or unchecked choice.
- A `<label>` connects a control to its label and expands the area that can activate it.

These choices supply browser behavior as well as meaning. A native button participates in keyboard navigation and can be activated with the keyboard. A checkbox exposes its checked state. A link offers navigation behavior such as opening its destination in another tab.

The [HTML and events article](/dump/blog/html-dom-and-events/) explains these mechanisms. Replacing a button with a clickable `<div>` discards useful behavior; adding `role="button"` describes the intended role but does not implement focusability or Enter/Space activation.

### Start with visible labels

This independent HTML example gives the field a visible label and associates it through matching `for` and `id` values:

```html
<label for="task-title">Task title</label>
<input id="task-title" name="title" type="text" required />
<button type="submit">Add task</button>
```

Put these controls inside a form when implementing submission. A placeholder is not a replacement for the label: it can disappear as someone types, and instructions should not depend on remembering it.

For repeated actions, include their target in the accessible name. The complete Angular example uses visible “Edit” text and an accessible name such as “Edit Read the DOM article.” Its `[attr.aria-label]="'Edit ' + task.title"` binding supplies that name without changing the visible button text. Keeping the visible action word in that name also helps people who operate controls by speaking their labels.

If an icon accompanies that text, make a purely decorative SVG `aria-hidden="true"` so it does not add a redundant name. If the icon is the only visible content, give the button a useful name; the icon still does not implement the action.

### Structure is also information

Headings describe sections. A list identifies a collection of tasks. A main region identifies the page's primary content. These help someone navigate without scanning positions on a screen.

ARIA—**Accessible Rich Internet Applications**—provides attributes for roles, states, and relationships that native HTML does not already express adequately. Use it to supplement the structure, not as a parallel fictional interface. Setting `aria-checked="true"` on arbitrary markup neither checks a native checkbox nor changes the task record.

## Keyboard operation is an interaction contract

Keyboard **focus** identifies the element that receives keyboard interaction. It is distinct from selecting a task or marking it complete. In JavaScript, `document.activeElement` identifies the currently focused element within that document.

Try the ordinary controls before adding keyboard handlers:

| Control    | Ordinary keyboard interaction                                               |
| ---------- | --------------------------------------------------------------------------- |
| Button     | Tab to it; activate with Enter or Space                                     |
| Checkbox   | Tab to it; toggle with Space                                                |
| Text field | Type; in a suitable form, Enter can submit                                  |
| Select     | Use its native keyboard choices; exact popup interaction varies by platform |

Tab moves through the page's sequential focus order; Shift+Tab moves backward. Native controls normally participate without an added `tabindex`.

The `tabindex` attribute changes focus participation:

- `tabindex="0"` includes an otherwise suitable element in the normal sequential order.
- `tabindex="-1"` leaves it out of that order but allows programmatic focus, useful for a heading that is a deliberate focus destination.
- Positive values create a priority order ahead of normal controls. Avoid them as a repair for confusing layout; fix the structure instead.

A focusable `<div>` is not yet an operable button. Similarly, being reachable by Tab does not supply the keyboard model of a custom menu or grid. If a genuine custom widget is necessary, follow its established interaction pattern rather than inventing unrelated key bindings.

Keep DOM order meaningful, and do not visually reorder controls into a contradictory sequence. Show a visible focus indicator. An action must not require hovering to discover or operate it.

Browser and operating-system settings can affect which controls Tab visits. Test the supported environment and its keyboard settings; do not compensate for a platform difference by assigning positive `tabindex` values everywhere.

## Focus must survive changes to the interface

Angular can create and remove the editor correctly without deciding where a person should continue. That destination is part of the interaction design.

For this task interface:

```text
Edit button → title field inside the modal editor
Save/Cancel/Escape → the Edit button that opened it
Delete edited task → filter control, because that Edit button is removed
Complete a task hidden by the current filter → filter control
```

The filter is a stable destination here: it remains available and lets someone reveal more tasks. Another interface might sensibly choose the next row or an Add button instead.

### Native dialog behavior is a useful primitive

Calling `showModal()` on a connected `<dialog>` draws it above ordinary page content in the browser-managed **top layer** and makes the rest of that document inert. **Inert** means that background content cannot be interacted with normally and is excluded from the accessibility tree. This is more than painting a dark rectangle over the page.

The browser runs dialog focusing behavior. An `autofocus` attribute identifies the intended initial control. A short title editor starts at its title field; a long dialog may need a different initial destination so its introduction is not skipped.

Closing a native dialog normally restores the previously focused element. Escape requests cancellation and produces a cancelable `cancel` event. These are browser mechanisms, not features that an `aria-modal` attribute creates.

`show()`, an `open` attribute, and `showModal()` are not interchangeable. The first two can display a non-modal dialog; they do not create this modal background behavior. A native dialog opened with `showModal()` supplies dialog/modal semantics, so the example does not add a redundant `role="dialog"` or use ARIA to simulate modality.

Native behavior is a starting point, not permission to skip naming, appropriate initial focus, a visible dismissal action, or browser/assistive-technology testing.

### An Angular editor with an explicit close path

Keep the shared `Task` interface from the previous article in `task.ts`:

```ts
export interface Task {
  id: number;
  title: string;
  done: boolean;
}
```

Save this editor in `task-editor.ts`. It owns the draft and the native dialog. The page will own the accepted record and whether the editor exists.

```ts
import {
  Component,
  ElementRef,
  afterNextRender,
  input,
  linkedSignal,
  output,
  signal,
  viewChild,
} from "@angular/core";
import type { Task } from "./task";

@Component({
  selector: "task-editor",
  template: `
    <dialog
      #dialogElement
      class="m-auto max-h-[calc(100dvh-2rem)] w-[calc(100%-2rem)] max-w-lg overflow-y-auto rounded-xl border border-line bg-surface p-4 text-foreground backdrop:bg-black/60"
      aria-labelledby="editor-heading"
      (cancel)="cancelFromBrowser($event)"
    >
      <h2 id="editor-heading" class="mb-4 text-xl font-semibold">Edit task title</h2>
      <form class="space-y-3" novalidate (submit)="submitTitle($event, titleInput)">
        <label for="draft-title" class="block font-medium">New task title (required)</label>
        <p id="draft-hint" class="text-muted">Save accepts the title. Cancel discards this edit.</p>
        <input
          #titleInput
          id="draft-title"
          name="title"
          type="text"
          required
          autofocus
          aria-describedby="draft-hint draft-error"
          [attr.aria-invalid]="error() !== ''"
          class="block min-h-11 w-full min-w-0 rounded-lg border border-muted bg-surface px-3 py-2 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
          [value]="draftTitle()"
          (input)="draftTitle.set(titleInput.value); error.set('')"
        />
        <p id="draft-error" class="min-h-6 break-words text-accent" aria-live="polite">
          {{ error() }}
        </p>
        <div class="flex flex-wrap gap-2">
          <button
            type="submit"
            class="min-h-11 rounded-lg bg-accent px-4 py-2 font-medium text-page focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
          >
            Save title
          </button>
          <button
            type="button"
            class="min-h-11 rounded-lg border border-line px-4 py-2 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
            (click)="dismiss()"
          >
            Cancel
          </button>
          <button
            type="button"
            class="min-h-11 rounded-lg border border-line px-4 py-2 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
            (click)="dialogElement.close(); deleteRequested.emit()"
          >
            Delete edited task
          </button>
        </div>
      </form>
    </dialog>
  `,
})
export class TaskEditor {
  readonly task = input.required<Task>();
  readonly titleSubmitted = output<string>();
  readonly cancelled = output<void>();
  readonly deleteRequested = output<void>();
  readonly error = signal("");
  readonly draftTitle = linkedSignal<Task, string>({
    source: this.task,
    computation: (task, previous) => {
      if (previous?.source.id === task.id) {
        return previous.value;
      }

      return task.title;
    },
  });
  readonly dialog = viewChild.required<ElementRef<HTMLDialogElement>>("dialogElement");

  constructor() {
    afterNextRender(() => {
      this.dialog().nativeElement.showModal();
    });
  }

  submitTitle(event: SubmitEvent, inputElement: HTMLInputElement) {
    event.preventDefault();
    const title = this.draftTitle().trim();

    if (title === "") {
      this.error.set("Enter a task title, not just spaces.");
      inputElement.focus();
      return;
    }

    this.dialog().nativeElement.close();
    this.titleSubmitted.emit(title);
  }

  dismiss() {
    this.dialog().nativeElement.close();
    this.cancelled.emit();
  }

  cancelFromBrowser(event: Event) {
    event.preventDefault();
    this.dismiss();
  }
}
```

`viewChild.required(...)` finds the native dialog in the editor's template. The constructor registers `afterNextRender`, so `showModal()` runs after Angular renders it, rather than trying to use an element during class initialization. The callback does not run during server-side rendering; this is a client-side interaction example.

The heading names the dialog through `aria-labelledby`. The field has its own visible label; that name is distinct from the dialog's name. The `linkedSignal` uses the same intentional draft policy explained in the ownership article, without mutating the accepted task.

Each successful exit calls `close()` **before** notifying the page. That lets the browser end modality and restore focus while the dialog and opener are still connected. The page then removes the editor. Merely removing an open dialog would skip this deliberate close path.

The Escape handler cancels the browser's default close action only to route it through the same close-and-cancel operation as the visible Cancel button. It does not keep the user trapped. Cancellation never submits the draft. Deletion also closes first, but the page must choose a different destination because it removes the opener's row.

There is no global Escape listener, manual background `aria-hidden` toggle, or hand-written Tab trap. Those would introduce coordination this native primitive already handles. Test that page controls remain unreachable while the modal is open; browser chrome and operating-system controls are not part of the page's focus sequence.

## State and feedback must be perceivable

A crossed-out title tells a sighted reader something changed. The checkbox's native checked state expresses completion independently of the color or line-through effect. The page below also displays “Completed” or “Active” as ordinary text.

For a control that expands content, keep its `aria-expanded` value aligned with the actual open/closed state. That attribute reports state; it does not expand anything. The previous article's Details control demonstrates this contract.

### Associate help and errors with the field

**Include the validation message element's ID in the field's `aria-describedby`, alongside any help-text IDs.** In the editor, `aria-describedby="draft-hint draft-error"` connects the field to both its instructions and its error message. These are space-separated IDs of elements in the same document, not the instruction or error strings themselves.

This independent HTML snapshot shows that relationship after a failed submission:

```html
<label for="example-title">Task title (required)</label>
<p id="example-title-hint">Enter a title for the task.</p>
<input
  id="example-title"
  name="title"
  type="text"
  required
  aria-invalid="true"
  aria-describedby="example-title-hint example-title-error"
/>
<p id="example-title-error" aria-live="polite">Enter a task title, not just spaces.</p>
```

The field's **name** comes from the label. Its **description** includes the help text and the validation message. `aria-invalid="true"` reports that validation failed; it does not explain what went wrong. Displaying the error nearby, giving it an ID, or marking the field invalid alone does not create this descriptive association. The field must reference the message's ID too.

Keep the existing help-text ID when adding an error ID. The complete Angular editor keeps both referenced paragraphs in the DOM; the error paragraph starts empty and receives text after an invalid submission. If another implementation creates the paragraph conditionally, include its ID when it exists and remove that reference when the paragraph is removed.

Association and notification are separate jobs. `aria-describedby` makes the message available as part of the field's description; it does not, by itself, guarantee an immediate announcement while someone is already focused there. The example's `aria-live="polite"` requests notification when the error text changes. Actual announcements still need screen-reader testing.

After an invalid submission, the visible error says how to recover and focus stays at or moves to the title field. Typing clears the obsolete error and invalid flag. Do not mark an untouched field invalid before validation has failed.

The form uses `novalidate` to disable automatic browser validation popups while this small example supplies its own visible feedback. `required` still expresses the field's requirement; the submit method rejects empty or whitespace-only titles. This is not a complete validation architecture. The forms article covers that separately.

### Feedback need not move focus

After a successful save, “Task title saved” appears in a **live region**: an element whose changes can be presented by assistive technology without navigating to it.

`role="status"` supplies polite live-region semantics and an atomic update by default. **Polite** requests presentation without unnecessarily interrupting current speech. **Atomic** means the region's whole message provides context, rather than announcing only a changed number. The page makes `aria-atomic="true"` explicit.

An urgent message that requires immediate attention may justify `role="alert"`, with assertive announcement semantics. Do not use that for every count change or success message. The title errors here also use polite updates; they are associated with the field and follow the person's submission rather than appearing as an unrelated alarm.

Keep one useful status message rather than making the whole task list live. The page's remaining count is readable ordinary text; action messages include the count when relevant. This avoids two separate live regions announcing the same change.

A live region is not a guaranteed speech queue. Timing, repeated identical text, screen-reader settings, and browser combinations affect announcements. Keeping a region present before changing its text is a useful baseline; verify what people actually hear. Do not add timers or repeated-message machinery without a demonstrated need.

## Visual styling still carries responsibilities

Accessibility is not only about screen readers. A keyboard user needs to find focus. A person using larger text needs controls that still fit. Someone with limited precision needs a usable target, not a tiny icon with a large-looking shadow.

The example keeps the existing dark/light colors and adds these checks:

- Text, borders needed to identify controls, and focus indicators need adequate contrast in **both** themes. A token named `muted` is not proof of contrast.
- The checkbox and explicit status text communicate completion without relying on color alone.
- `focus-visible:outline-*` classes make keyboard focus visible rather than suppressing the browser indicator.
- Wrapping, `min-w-0`, and breakable task titles let the layout handle narrow widths and long content.
- Button `min-h-11` gives a preferred minimum height of 2.75rem; checkbox labels provide a larger clickable area than the small check mark alone.
- The dialog is width-constrained and can scroll vertically when content no longer fits. Save and Cancel must remain reachable at larger text sizes.

The Web Content Accessibility Guidelines (WCAG) 2.2 target-size minimum is generally 24 × 24 CSS pixels, with defined exceptions; the enhanced criterion uses 44 × 44 CSS pixels. These are different criteria, not a rule that every interactive thing must be exactly 44 pixels. Prefer comfortably usable targets instead of treating the smallest permitted target as the design goal.

CSS pixels are layout units, not fixed physical millimetres on every screen. Test real devices and input modes when they are part of the supported product.

Use zoom and text enlargement, not only a smaller window. Check for clipped labels, unreachable buttons, and horizontal scrolling that makes the interaction difficult. The [CSS layout article](/dump/blog/css-layout-fundamentals/) explains the sizing mechanisms behind those failures.

## Verify the complete task

This complete page is the editor's consumer. Save it in `task-page.ts`, alongside `task.ts` and `task-editor.ts`. It uses an inline template and keeps task state in the page; the editor never owns the accepted collection.

```ts
import { Component, computed, signal } from "@angular/core";
import type { Task } from "./task";
import { TaskEditor } from "./task-editor";

@Component({
  selector: "task-page",
  imports: [TaskEditor],
  template: `
    <main class="mx-auto max-w-2xl px-4 py-8">
      <h1 class="mb-6 text-3xl font-semibold">Task notes</h1>
      <form class="mb-6 space-y-2" novalidate (submit)="addTask($event, titleInput)">
        <label for="task-title" class="block font-medium">Task title (required)</label>
        <p id="task-hint" class="text-muted">Enter a title, then add it to the list.</p>
        <div class="flex flex-wrap gap-2">
          <input
            #titleInput
            id="task-title"
            name="title"
            type="text"
            required
            aria-describedby="task-hint task-error"
            [attr.aria-invalid]="addError() !== ''"
            class="min-h-11 min-w-0 grow basis-48 rounded-lg border border-muted bg-surface px-3 py-2 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
            (input)="addError.set('')"
          />
          <button
            type="submit"
            class="min-h-11 rounded-lg bg-accent px-4 py-2 font-medium text-page focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
          >
            Add task
          </button>
        </div>
        <p id="task-error" class="min-h-6 break-words text-accent" aria-live="polite">
          {{ addError() }}
        </p>
      </form>

      <label for="task-filter" class="mb-2 block font-medium">Show tasks</label>
      <select
        #filterSelect
        id="task-filter"
        class="min-h-11 rounded-lg border border-muted bg-surface px-3 py-2 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
        [value]="filter()"
        (change)="setFilter(filterSelect.value)"
      >
        <option value="all">All</option>
        <option value="active">Active</option>
        <option value="completed">Completed</option>
      </select>
      <p class="my-4">Remaining tasks: {{ remaining() }}</p>
      <p id="task-status" class="mb-4 min-h-6 break-words" role="status" aria-atomic="true">
        {{ status() }}
      </p>
      <ul class="space-y-3" role="list">
        @for (task of visibleTasks(); track task.id) {
          <li class="rounded-lg border border-line bg-surface p-3">
            <div class="flex flex-wrap items-start gap-3">
              <label class="flex min-h-11 min-w-0 grow basis-48 items-start gap-3 py-2">
                <input
                  #checkbox
                  type="checkbox"
                  class="mt-1 size-5 shrink-0 accent-accent focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
                  [checked]="task.done"
                  (change)="setDone(task, checkbox.checked, filterSelect)"
                />
                <span
                  class="min-w-0 break-words"
                  [class.line-through]="task.done"
                  [class.text-muted]="task.done"
                  >{{ task.title }}</span
                >
              </label>
              <div class="flex flex-wrap gap-2">
                <button
                  #editButton
                  type="button"
                  class="min-h-11 rounded-lg border border-line px-3 py-2 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
                  [attr.aria-label]="'Edit ' + task.title"
                  (click)="startEditing(task.id, editButton)"
                >
                  Edit
                </button>
                <button
                  type="button"
                  class="min-h-11 rounded-lg border border-line px-3 py-2 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
                  [attr.aria-label]="'Delete ' + task.title"
                  (click)="removeTask(task, filterSelect)"
                >
                  Delete
                </button>
              </div>
            </div>
            @if (task.done) {
              <p class="text-sm text-muted">Completed</p>
            } @else {
              <p class="text-sm text-muted">Active</p>
            }
          </li>
        }
      </ul>
      <p class="text-muted" [hidden]="visibleTasks().length > 0">No tasks to show.</p>

      @if (editingTask(); as task) {
        <task-editor
          [task]="task"
          (titleSubmitted)="renameTask(task.id, $event)"
          (cancelled)="editingId.set(undefined)"
          (deleteRequested)="removeTask(task, filterSelect)"
        />
      }
    </main>
  `,
})
export class TaskPage {
  readonly tasks = signal<Task[]>([
    { id: 1, title: "Read the DOM article", done: false },
    { id: 2, title: "Review the CSS layout", done: false },
  ]);
  readonly filter = signal<"all" | "active" | "completed">("all");
  readonly editingId = signal<number | undefined>(undefined);
  readonly addError = signal("");
  readonly status = signal("");
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
    const visible: Task[] = [];
    for (const task of this.tasks()) {
      if (this.filter() === "active" && task.done) {
        continue;
      }
      if (this.filter() === "completed" && !task.done) {
        continue;
      }
      visible.push(task);
    }
    return visible;
  });

  readonly editingTask = computed(() => {
    for (const task of this.tasks()) {
      if (task.id === this.editingId()) {
        return task;
      }
    }
    return undefined;
  });

  addTask(event: SubmitEvent, inputElement: HTMLInputElement) {
    event.preventDefault();
    const title = inputElement.value.trim();
    if (title === "") {
      this.addError.set("Enter a task title, not just spaces.");
      inputElement.focus();
      return;
    }

    this.tasks.set([...this.tasks(), { id: this.nextId++, title, done: false }]);
    this.addError.set("");
    inputElement.value = "";
    inputElement.focus();
    this.status.set(`Task added. Remaining tasks: ${this.remaining()}.`);
  }

  setFilter(value: string) {
    if (value !== "all" && value !== "active" && value !== "completed") {
      throw new Error("Unknown task filter.");
    }
    this.filter.set(value);
    this.status.set(`Tasks shown: ${this.visibleTasks().length}.`);
  }

  setDone(task: Task, done: boolean, filterSelect: HTMLSelectElement) {
    const updated = this.tasks().map((current) => {
      if (current.id === task.id) {
        return { ...current, done };
      }
      return current;
    });
    this.tasks.set(updated);

    const hiddenByActiveFilter = this.filter() === "active" && done;
    const hiddenByCompletedFilter = this.filter() === "completed" && !done;
    if (hiddenByActiveFilter || hiddenByCompletedFilter) {
      filterSelect.focus();
    }
    this.status.set(`Completion updated. Remaining tasks: ${this.remaining()}.`);
  }

  startEditing(id: number, opener: HTMLButtonElement) {
    opener.focus();
    this.editingId.set(id);
  }

  renameTask(id: number, title: string) {
    const updated = this.tasks().map((task) => {
      if (task.id === id) {
        return { ...task, title };
      }
      return task;
    });
    this.tasks.set(updated);
    this.editingId.set(undefined);
    this.status.set("Task title saved.");
  }

  removeTask(task: Task, filterSelect: HTMLSelectElement) {
    const kept = this.tasks().filter((current) => current.id !== task.id);
    this.tasks.set(kept);
    if (this.editingId() === task.id) {
      this.editingId.set(undefined);
    }
    filterSelect.focus();
    this.status.set(`Deleted "${task.title}". Remaining tasks: ${this.remaining()}.`);
  }
}
```

Bootstrap the page in `main.ts`:

```ts
import { bootstrapApplication } from "@angular/platform-browser";
import { TaskPage } from "./task-page";

bootstrapApplication(TaskPage);
```

Use `<task-page></task-page>` in the host document, with the styling article's CSS entry, dark-default document attributes, and body classes. Angular templates can self-close the empty `<task-editor />` usage; the browser-parsed custom-element host still needs its closing tag. This demonstration keeps tasks in memory; reloading resets its records and messages.

The page focuses the Edit button before creating the editor. That makes it the browser's restoration target even on platforms where clicking a button does not focus it. Tracking `task.id` preserves that same button when its title changes.

Save and Cancel close the native dialog before the page clears edit selection. Deletion takes focus to the still-existing filter before Angular removes the row. Completing a task moves focus there only if the active filter will remove that row. Changing the filter from the select leaves focus on the select; updating a count does not steal it.

### Walk the workflow without a mouse

1. Tab to the title field. Submit an empty or whitespace-only title. Check the visible error, invalid state, field association, and focus destination.
2. Type a title and press Enter. Confirm the new task, success feedback, and continued focus in the Add field.
3. Tab to a checkbox and press Space. Confirm its checked state, completion text, and remaining count.
4. Activate a task's Edit button. Confirm the dialog name and initial title-field focus. Tab and Shift+Tab through it; no background page control should receive focus.
5. Change the title and press Escape. Confirm the accepted title did not change, the dialog is gone, and focus returns to its opener. Reopen it: the draft should start from the accepted title.
6. Save a valid title. Confirm the record changed and focus returns to the same row's Edit button.
7. Open the editor and delete its task. Confirm focus lands on the filter rather than on the removed button. The background must become operable again.
8. With the Active filter selected, complete an active task. Confirm its row disappears, feedback remains available, and focus moves to the filter. Also test reactivating a task under Completed.

### Inspect more than the screenshot

Use the browser's accessibility inspection to check computed names, roles, states, and descriptions—not only source attributes. Confirm that labels reference existing IDs, the dialog is named and modal, and background controls are absent from the accessible interaction while it is open.

Then try the supported screen-reader/browser combination. Check whether names give enough context, field help and errors are useful, status updates are announced at an appropriate time, and focus transitions remain understandable. Keyboard-only testing does not exercise a screen reader's reading/navigation mode or speech behavior.

Automated checks can find unnamed controls, some invalid relationships, and detectable contrast problems. They cannot decide whether a message is useful, an initial focus choice makes sense, or the complete workflow is understandable. A clean result is evidence, not an accessibility certificate.

**Verification boundary:** The example is checked through strict Angular compilation, browser keyboard/focus behavior, accessible properties, and narrow/larger-text layouts. Screen-reader speech and real-device touch behavior require separate checks; no WCAG-compliance or legal-compliance claim follows from these examples.

Component reuse should preserve this whole contract: labels, keyboard operation, state, feedback, focus, and presentation. Reusing the border and colors while losing the interaction is not equivalent reuse.

## Closing check

1. Why does `role="button"` not make a clickable `<div>` equivalent to a button?
2. How is keyboard focus different from task completion?
3. What does `showModal()` provide that `aria-modal="true"` alone does not?
4. Why close the dialog before destroying its Angular editor?
5. Why does deleting the edited task use a different focus destination from Cancel?
6. Why is the entire task list not a live region?

Check your reasoning:

- A role describes meaning; it does not supply native focus or keyboard activation behavior.
- Focus identifies the keyboard's current interaction destination. Completion is application data exposed through the checkbox's state.
- `showModal()` supplies actual modal browser behavior, including an inert background and dialog focusing. ARIA alone reports semantics.
- Closing explicitly ends modality and runs native restoration while the relevant elements are connected; the page can then remove the editor.
- Cancel preserves the opener. Deletion removes it, so the person needs another sensible place to continue.
- Useful action feedback does not require announcing every inserted or changed row. A small status region avoids that noise.

The final question is practical: can someone complete the task, understand the result, and continue from a sensible position without using a mouse?

## Sources and further reading

- [WAI: introduction to web accessibility](https://www.w3.org/WAI/fundamentals/accessibility-intro/)
- [WAI-ARIA APG: accessible names and descriptions](https://www.w3.org/WAI/ARIA/apg/practices/names-and-descriptions/)
- [WAI-ARIA APG: developing a keyboard interface](https://www.w3.org/WAI/ARIA/apg/practices/keyboard-interface/)
- [WAI-ARIA APG: modal dialog pattern](https://www.w3.org/WAI/ARIA/apg/patterns/dialog-modal/)
- [HTML Standard: the dialog element](https://html.spec.whatwg.org/multipage/interactive-elements.html#the-dialog-element)
- [MDN: the dialog element](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/dialog)
- [WAI-ARIA: status role](https://www.w3.org/TR/wai-aria-1.2/#status)
- [WCAG: understanding status messages](https://www.w3.org/WAI/WCAG22/Understanding/status-messages.html)
- [WCAG: understanding focus visible](https://www.w3.org/WAI/WCAG22/Understanding/focus-visible.html)
- [WCAG: understanding reflow](https://www.w3.org/WAI/WCAG22/Understanding/reflow.html)
- [WCAG: understanding target size minimum](https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html)
- [WCAG: associating validation errors and invalid state](https://www.w3.org/WAI/WCAG22/Techniques/aria/ARIA21)
- [Angular: using DOM APIs and render callbacks](https://angular.dev/guide/components/dom-apis)
