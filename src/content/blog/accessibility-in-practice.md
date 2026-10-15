---
title: "Making the whole interaction accessible"
description: "Follow one task from a named Edit button through a modal editor, error and status messages, and a sensible focus destination after every action."
pubDate: "2026-10-06"
updatedDate: "2026-10-15"
tags:
  - accessibility
  - angular
  - frontend
---

Someone is using the task list with only a keyboard and a screen reader. They Tab to a button, and the screen reader says "button", but not what it does. They press it anyway. An editor opens, but their keyboard is still on the list behind it. They delete the task from the editor, the button they came from disappears, and focus falls back to the start of the page. Every screenshot of this interface looks fine. The task still failed.

So this article checks one thing: can someone get all the way through a task, from finding the right control to knowing where they ended up? It builds the task list's Edit, Delete, and complete actions, and checks each step along the way.

You'll need the [component composition article](/dump/blog/angular-component-composition/) for Angular's `input()`, `output()`, and how the page and the task editor split the task data. The examples use Angular 22.2.1 and the [styling article's Tailwind 4 setup and dark and light palette](/dump/blog/frontend-evolution-styling/#define-the-shared-palette-once). You can skip over the long `class="…"` strings; they only control appearance, and the [Contrast, target size, and zoom](#contrast-target-size-and-zoom) section explains the few that matter here.

## Contents

1. [What a screen reader gets from the page](#what-a-screen-reader-gets-from-the-page)
2. [Use the native element for the job](#use-the-native-element-for-the-job)
3. [Using the page with only a keyboard](#using-the-page-with-only-a-keyboard)
4. [Where focus goes after each action](#where-focus-goes-after-each-action)
5. [Help text, errors, and status messages](#help-text-errors-and-status-messages)
6. [Edit a task in a modal dialog](#edit-a-task-in-a-modal-dialog)
7. [Contrast, target size, and zoom](#contrast-target-size-and-zoom)
8. [Put the page together](#put-the-page-together)
9. [Walk the whole task with a keyboard](#walk-the-whole-task-with-a-keyboard)

## What a screen reader gets from the page

Imagine a button drawn as a pencil. A sighted person sees the drawing and guesses "edit this task". A screen reader can't see the drawing, so that guess never reaches its user.

A screen reader is one kind of **assistive technology**: software or hardware that lets people use a computer in ways other than looking at the screen and using a mouse. Voice control software, which lets someone say "click Edit", and switch devices, which let someone operate everything with one or two buttons, are others.

These programs don't read pixels or HTML. They ask the operating system questions such as "what's on screen?", "what has focus?", and "what is this thing called?". The operating system interface that answers them is an **accessibility API**. For a web page, the browser supplies the answers, and it builds them from the **accessibility tree**: a simplified version of the DOM that keeps the useful parts, such as buttons, headings, text, and form fields, and leaves out wrappers that exist only for layout.

So the same page exists in three forms:

- The **visual interface** is what the browser draws: text, colors, positions, and shapes.
- The **DOM** is the live structure of elements and text that JavaScript and Angular work with.
- The **accessibility tree** is what assistive technology gets, through the accessibility API.

For each control in that tree, three properties matter most:

| Property        | The question it answers        | Task example                    |
| --------------- | ------------------------------ | ------------------------------- |
| Role            | What kind of thing is this?    | Button, checkbox, or text field |
| Accessible name | Which thing or action is it?   | "Edit Read the DOM article"     |
| State           | What is its current condition? | Checkbox checked; input invalid |

### Accessible names

The **accessible name** is the label the browser works out for an element. A screen reader reads it out, and voice control software listens for it. A button's text usually becomes its name, and a `<label>` linked to a text field becomes that field's name.

When there's no suitable text, ARIA can supply one. **ARIA** (Accessible Rich Internet Applications) is a set of HTML attributes, most of them starting with `aria-`, that change what the accessibility tree reports about an element. They don't change how the element looks or behaves. Two of them set the name:

| Attribute         | Where the name comes from                          |
| ----------------- | -------------------------------------------------- |
| `aria-label`      | Text written directly in the attribute             |
| `aria-labelledby` | The text of other elements, referenced by their IDs |

For example, this dialog gets its name from its heading:

```html
<dialog aria-labelledby="example-heading">
  <h2 id="example-heading">Edit task title</h2>
  <!-- Editor controls would go here. -->
</dialog>
```

A screen reader announces the dialog as "Edit task title, dialog". `aria-label="Edit task title"` would give it the same name, but then the heading and the attribute are two copies of the same text that can drift apart. When visible text already says the right thing, point to it with `aria-labelledby`. For form fields, use a native `<label>`.

How a name is spoken depends on the screen reader and its settings. The name is the information; the exact sentence isn't up to you.

An icon-only button with no name is announced as just "button". The icon looks obvious on screen, but the browser has no way to turn a drawing into a name. Giving it a name fixes that one problem, but the keyboard, the feedback, and the focus still need checking, and the rest of this article covers them.

## Use the native element for the job

Pick the HTML element that matches what the control does:

- A `<button>` performs an action.
- An `<a href="…">` goes to another location.
- An `<input type="checkbox">` is a checked or unchecked choice.
- A `<label>` names its control, and clicking the label activates the control too.

These elements come with behavior as well as a role. A button can be reached with Tab and pressed with Enter or Space. A checkbox reports whether it's checked. A link can be opened in a new tab.

A clickable `<div>` gets none of that. Adding `role="button"` makes the accessibility tree call it a button, but it still can't be reached with Tab, and Enter and Space still do nothing. The [HTML and events article](/dump/blog/html-dom-and-events/) shows how these native behaviors work.

### Start with visible labels

Give each field a visible label, linked by matching `for` and `id` values:

```html
<label for="task-title">Task title</label>
<input id="task-title" name="title" type="text" required />
<button type="submit">Add task</button>
```

A placeholder can't replace the label. It disappears as soon as someone starts typing, so they'd have to remember what it said.

### Name repeated actions after their task

Every row has an Edit button. If each one is only called "Edit", a screen reader user moving through the buttons hears "Edit, button" over and over, with no idea which task each one edits. So the page's Angular template gives each button a name that includes the task:

```html
<button type="button" [attr.aria-label]="'Edit ' + task.title">Edit</button>
```

The button still shows "Edit", but its accessible name is "Edit Read the DOM article". The name starts with the visible word on purpose: someone using voice control says what they see, "click Edit", and that only works if the visible text is part of the name.

If you add an icon next to the text, mark a purely decorative SVG with `aria-hidden="true"`, so it doesn't add anything to the name. If the icon is the only thing inside the button, the button needs an `aria-label`.

### Structure is information too

Headings, lists, and landmarks such as `<main>` describe how the page is organized. Screen reader users jump between headings and landmarks the way sighted people scan the page, so use real `<h1>`, `<h2>`, `<ul>`, and `<main>` elements instead of styled `<div>` elements.

Use ARIA only for things HTML can't already say. A `<span role="checkbox" aria-checked="true">` is reported as a checked checkbox, but that's all ARIA does. The span can't be reached with Tab, pressing Space doesn't toggle it, and `aria-checked` stays `"true"` unless your code changes it. A real `<input type="checkbox">` handles the keyboard and reports its own checked state for you. Updating the task record is still your code's job, which is what the `(change)` handler does later in this article.

## Using the page with only a keyboard

Keyboard **focus** marks the one element that receives key presses. It's separate from completing a task or selecting it: a checkbox can have focus whether it's checked or not. In JavaScript, `document.activeElement` is the element that currently has focus.

Native controls already work with the keyboard:

| Control    | Keyboard interaction                                                    |
| ---------- | ----------------------------------------------------------------------- |
| Button     | Tab to it; press with Enter or Space                                    |
| Checkbox   | Tab to it; toggle with Space                                            |
| Text field | Type; inside a form, Enter can submit it                                |
| Select     | Change the choice with the arrow keys; the exact popup varies by platform |

Tab moves forward through the page's controls in order, and Shift+Tab moves back. Native controls are in that order without any extra attribute.

The `tabindex` attribute changes it:

- `tabindex="0"` adds an element that isn't normally focusable to the Tab order, in its place in the document.
- `tabindex="-1"` keeps an element out of the Tab order but lets code call `focus()` on it, which is useful for a heading you want to move focus to.
- A positive value pulls the element ahead of everything else in the Tab order. Avoid it: it makes the order jump around, and fixing the HTML order is almost always the real fix.

Making a `<div>` focusable with `tabindex="0"` still doesn't make it a button: Enter and Space do nothing until you write that code too. Custom widgets such as menus and grids have established keyboard patterns, which the [ARIA Authoring Practices Guide](https://www.w3.org/WAI/ARIA/apg/practices/keyboard-interface/) describes. Follow those instead of inventing your own keys.

A few more rules keep keyboard use predictable:

- Keep the HTML order in the order things appear on screen. If CSS moves controls around visually, Tab still follows the HTML.
- Show where focus is. The examples use `focus-visible:outline-*` classes for a clear outline.
- Never put an action only behind a mouse hover. Keyboard users can't hover.

Browser and operating system settings can change which controls Tab visits, so test with the browsers and settings you support. Don't try to compensate with positive `tabindex` values.

## Where focus goes after each action

When an action removes or covers the element that has focus, the browser doesn't decide where the person should continue. If your code doesn't decide either, focus can end up on the `<body>`, and a keyboard user has to Tab from the top of the page again. So decide a destination for every action:

```text
Edit button → title field inside the modal editor
Save, Cancel, or Escape → the Edit button that opened it
Delete edited task → filter control, because that Edit button is removed
Complete a task hidden by the current filter → filter control
```

The filter is a good destination here because it never goes away, and it lets someone show more tasks. Another interface might reasonably choose the next row, or an Add button.

Clicking Edit opens the title editor in a modal dialog, which the [dialog section](#edit-a-task-in-a-modal-dialog) builds. The browser already handles the first two lines of the table for a modal dialog: it moves focus into the dialog when it opens, and back to the element that had focus before it opened when it closes. The page component, `TaskPage`, handles the rest. Here are its three methods that move focus; the [complete page](#put-the-page-together) comes later.

First, starting an edit:

```ts
startEditing(id: number, opener: HTMLButtonElement) {
  opener.focus();
  this.editingId.set(id);
}
```

The page focuses the Edit button before it creates the editor, because the button that has focus when the dialog opens is where the browser sends focus back. Clicking a button usually focuses it, but not in every browser: Safari, for example, doesn't focus a button when you click it. Without this line, a Safari user who clicked Edit would end up somewhere else after Cancel. The rows are tracked by `task.id`, so after a title changes, Angular keeps the same row and the same button, and focus has somewhere to return to.

Next, completing a task:

```ts
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
```

Focus only moves when the current filter is about to remove the row, and with it the checkbox that has focus. Under the All filter, the checkbox stays, so focus stays on it.

Last, deleting a task:

```ts
removeTask(task: Task, filterSelect: HTMLSelectElement) {
  const kept = this.tasks().filter((current) => current.id !== task.id);
  this.tasks.set(kept);
  if (this.editingId() === task.id) {
    this.editingId.set(undefined);
  }
  filterSelect.focus();
  this.status.set(`Deleted "${task.title}". Remaining tasks: ${this.remaining()}.`);
}
```

Deleting always removes the row, so focus always moves to the filter. It moves before Angular updates the page and removes the row, so focus never lands on an element that's about to disappear. The same method runs for the Delete button in the row and for the Delete button in the editor.

Everything else leaves focus alone. Changing the filter keeps focus on the select, and updating the count or a status message never moves it.

## Help text, errors, and status messages

Completion has to be perceivable without seeing the strike-through. The checkbox's checked state tells the accessibility tree, and the page also shows the word "Completed" or "Active" as text in each row, so it doesn't rely on color or line style alone.

### Connect help and errors to the field

A field's name says what it is. Sometimes it also needs instructions, or an error message after a failed save. That extra text is the field's **accessible description**. Screen readers usually read it after the name and role, for example "Task title (required), edit text, Enter a title for the task."

`aria-describedby` builds the description from other elements, listed by their IDs and separated by spaces. Here's a field after a failed submission:

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

What to notice:

- The name, "Task title (required)", comes from the label. The description combines the hint and the error message, in the order the IDs are listed.
- `aria-invalid="true"` tells the screen reader the value failed validation. It doesn't say what went wrong; the error message does that.
- Placing the error next to the field isn't enough. Unless the field's `aria-describedby` lists the error's ID, a screen reader doesn't connect the two.
- Keep the hint's ID when you add the error's ID. If an implementation only creates the error paragraph when there's an error, it also has to add and remove that ID.

A description is read when someone moves to the field. It isn't necessarily read when it changes while they're already there. That's what `aria-live="polite"` on the error paragraph is for: it asks the screen reader to read the new text when it appears.

In the examples, a failed submission shows the error, sets `aria-invalid`, and puts focus on the field. Typing clears both again. Don't mark an untouched field invalid before anyone has tried to submit it.

The forms use `novalidate`, which turns off the browser's automatic validation bubbles, so the examples can show their own error text under the field. `required` stays, so the field still reports itself as required, and the submit code also rejects titles made only of spaces. The [forms article](/dump/blog/forms-and-validation/) covers validation properly.

### Status messages without moving focus

After a successful save, "Task title saved." appears in a **live region**: an element whose text changes a screen reader reads out, without the person moving there.

The page uses `role="status"` for its live region. That role is **polite**: the screen reader waits until it finishes what it's currently reading. When the status text changes from "Completion updated. Remaining tasks: 2." to "Completion updated. Remaining tasks: 1.", only the number changed. `aria-atomic="true"` tells the screen reader to read the whole message again rather than just "1". `role="status"` already implies that, and the page sets it explicitly anyway.

For a message that needs attention right away, there's `role="alert"`, which interrupts. Save it for urgent problems, not counts or successes. The title errors use polite announcements too: they follow the person's own submission, so there's nothing to interrupt.

The page has one status region, and its messages include the remaining count when it changed. Making the whole task list a live region would read out every changed row; a second live region on the count would announce the same change twice.

Screen readers and browsers differ in when and how they read live regions, and repeating identical text may not be announced again. Keep the region in the page from the start and only change its text, then listen to what's actually announced before adding anything more complicated.

## Edit a task in a modal dialog

In the composition article, the editor was part of the page, and you could keep changing the filter while it was open. That's a **non-modal** editor. This one is **modal**: while it's open, the rest of the page can't be used until it closes. That shows off focus entering and leaving the editor, but it isn't automatically better; an inline editor is a fine choice too.

### What showModal() gives you

Calling `showModal()` on a `<dialog>` element that's in the page does three things:

- It draws the dialog above everything else, in a browser-managed layer called the **top layer**.
- It makes the rest of the document **inert**: nothing behind the dialog can be clicked, focused, or found in the accessibility tree. Tab and Shift+Tab stay inside the dialog and the browser's own controls.
- It moves focus into the dialog. If an element inside has the `autofocus` attribute, that element gets focus. A short title editor should start in its title field; a long dialog might start at its heading, so the introduction isn't skipped.

When the dialog closes, the browser puts focus back on the element that had it when `showModal()` ran.

Pressing Escape also closes a modal dialog. Before closing it, the browser fires a `cancel` event on the dialog. Calling `event.preventDefault()` inside the handler for that event tells the browser to skip its own close. The editor uses that to send Escape through the same code as its Cancel button, which closes the dialog and also tells the page that editing ended.

`show()` and the `open` attribute also display a dialog, but non-modally: the page behind stays usable and nothing becomes inert. Only `showModal()` does all of the above. And the `aria-modal="true"` attribute only tells the accessibility tree that a dialog is modal; it doesn't make anything inert or move focus. `showModal()` already reports the dialog as modal, so the editor doesn't need `role="dialog"` or `aria-modal`.

`showModal()` handles the inert background and returning focus. You still have to give the dialog a name, choose which control gets focus first, give it a visible Cancel button, and try it with a screen reader.

### The editor component

The editor uses the same `Task` interface as the previous articles, in `task.ts`:

```ts
export interface Task {
  id: number;
  title: string;
  done: boolean;
}
```

The editor goes in `task-editor.ts`. It keeps the unfinished title and the native dialog. The page keeps the accepted tasks and decides whether an editor exists. Here it is in three pieces, with the styling classes left out; the complete file comes after them.

First, the dialog and its title field, from the editor's template:

```html
<dialog #dialogElement aria-labelledby="editor-heading" (cancel)="cancelFromBrowser($event)">
  <h2 id="editor-heading">Edit task title</h2>
  <form novalidate (submit)="submitTitle($event, titleInput)">
    <label for="draft-title">New task title (required)</label>
    <p id="draft-hint">Save accepts the title. Cancel discards this edit.</p>
    <input
      #titleInput
      id="draft-title"
      name="title"
      type="text"
      required
      autofocus
      aria-describedby="draft-hint draft-error"
      [attr.aria-invalid]="error() !== ''"
      [value]="draftTitle()"
      (input)="draftTitle.set(titleInput.value); error.set('')"
    />
    <p id="draft-error" aria-live="polite">{{ error() }}</p>
    <!-- Save, Cancel, and Delete buttons -->
  </form>
</dialog>
```

What to notice:

- **Names and descriptions.** The heading names the dialog through `aria-labelledby`. The field gets its own name from its label, and the hint and error paragraphs as its description, as in the previous section.
- **Initial focus.** `autofocus` makes the title field the control that gets focus when the dialog opens.
- **Escape.** `(cancel)` runs `cancelFromBrowser` when the browser fires the `cancel` event.

The buttons at the end of the form:

```html
<button type="submit">Save title</button>
<button type="button" (click)="dismiss()">Cancel</button>
<button type="button" (click)="dialogElement.close(); deleteRequested.emit()">
  Delete edited task
</button>
```

Next, the class's inputs, outputs, and state, and the code that opens the dialog:

```ts
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
```

What to notice:

- **Opening.** `viewChild.required(...)` finds the `<dialog>` in the editor's template. `afterNextRender` runs its callback once Angular has put the template in the page, so `showModal()` runs on an element that exists. It doesn't run during server-side rendering, which is fine for a dialog that only opens after a click.
- **The draft.** `linkedSignal` creates a signal you can write to, like `signal`, that also recalculates when its `source` changes. Typing writes to `draftTitle`. When the page passes in a new `task` object, Angular calls `computation` with the new task and `previous`, the last task and draft. If the ID is the same, the page only replaced the object (for example, because `done` changed), so the draft keeps what was typed. A different task starts a fresh draft from its title.

Last, the methods that close the dialog:

```ts
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
```

What to notice:

- **Errors.** A title made only of spaces sets `error`, which fills the error paragraph and sets `aria-invalid`, and focus goes back to the field.
- **Closing before telling the page.** Save, Cancel, and Delete each call `close()` first and only then emit an output. While the dialog is still in the page, closing it lets the browser end the modal state and return focus to the Edit button. Then the page removes the editor. If the page removed the dialog while it was still open, that close step wouldn't run, and focus wouldn't go back to the Edit button.
- **Escape.** `cancelFromBrowser` stops the browser's own close and calls `dismiss()` instead, so Escape closes the dialog and the page hears `cancelled`. Escape still always closes the editor, and it never saves the draft.
- **Delete.** Deleting closes the dialog first too, but its focus destination is the filter, because `removeTask` removes the row with the Edit button in it.

<details>
<summary>The complete <code>task-editor.ts</code></summary>

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


</details>

If you've seen older modal code, you may remember a keydown listener for Escape, a loop that sets `aria-hidden` on everything behind the modal, and code that catches Tab on the last button and jumps back to the first. `showModal()` does all three, so none of it appears here.

## Contrast, target size, and zoom

Accessibility covers more than screen readers. A keyboard user needs to see where focus is. Someone using larger text needs controls that still fit. Someone with limited hand precision needs targets big enough to hit.

The example keeps the styling article's dark and light colors and checks these:

- Text, the borders that show where a control is, and focus outlines need enough contrast in **both** themes. A color named `muted` still has to pass a contrast check.
- The checkbox and the "Completed" text show completion without relying on color or strike-through alone.
- `focus-visible:outline-*` classes draw a visible outline around whatever has keyboard focus.
- Wrapping, `min-w-0`, and `break-words` let long task titles wrap on narrow screens instead of pushing the layout sideways.
- `min-h-11` makes buttons at least 2.75rem tall. Each checkbox sits inside its label, so the whole label is clickable, not just the small box.
- The dialog has a maximum width and scrolls vertically when its content doesn't fit, so Save and Cancel stay reachable with large text.

The Web Content Accessibility Guidelines (WCAG) 2.2 set a minimum target size of 24 × 24 CSS pixels, with some exceptions, and a stricter enhanced level of 44 × 44 CSS pixels. Those are two different criteria, and the minimum is a floor rather than a design goal, so aim for targets that are comfortable to use.

CSS pixels are layout units. Their physical size depends on the screen, so test on real devices if they're part of what you support.

Test with browser zoom and larger text settings, not only a narrower window. Look for clipped labels, buttons you can't reach, and sideways scrolling. The [CSS layout article](/dump/blog/css-layout-fundamentals/) explains the sizing behind those failures.

## Put the page together

The page component, `TaskPage`, holds the accepted tasks, the filter, which task is being edited, and the status message. It renders the add form, the filter, the list, and the editor when one is open. It includes the three focus methods from earlier. Save it in `task-page.ts`, next to `task.ts` and `task-editor.ts`.

<details>
<summary>The complete <code>task-page.ts</code></summary>

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

</details>

What to notice in the parts you haven't seen yet:

- The editor only exists while `editingTask()` returns a task. Setting `editingId` to `undefined` removes it, after the editor has already closed its dialog.
- The list keeps `role="list"` because Tailwind removes list bullets, and Safari deliberately stops reporting an unstyled `<ul>` as a list in some cases. An explicit role keeps it a list.
- `addTask` and `setFilter` write to the same `status` signal as the focus methods, so every action produces one message in the one status region.

Start the page from `main.ts`:

```ts
import { bootstrapApplication } from "@angular/platform-browser";
import { TaskPage } from "./task-page";

bootstrapApplication(TaskPage);
```

The host `index.html` needs a `<task-page></task-page>` element, plus the styling article's CSS entry, dark-default document attributes, and body classes. Inside an Angular template you can write `<task-editor />`, but in the HTML file the browser reads directly, a custom element needs its closing tag. Tasks live in memory, so reloading the page resets them.

## Walk the whole task with a keyboard

Put the mouse away and go through every action:

1. Tab to the title field. Submit an empty title, then one made of spaces. Check that the error appears, the field reports itself as invalid, the error is read as part of its description, and focus stays on the field.
2. Type a title and press Enter. Check that the task appears, the status message says so, and focus stays in the title field.
3. Tab to a checkbox and press Space. Check that it's checked, the row says "Completed", and the remaining count went down.
4. Tab to a task's Edit button and press Enter. Check that the dialog is announced by name and focus is in its title field. Tab and Shift+Tab through it; nothing behind the dialog should get focus.
5. Change the title and press Escape. Check that the title didn't change, the dialog is gone, and focus is back on the Edit button. Open it again: the draft should start from the saved title.
6. Change the title and save it. Check that the title changed and focus is back on the same row's Edit button.
7. Open the editor and delete its task. Check that focus is on the filter, not lost, and that the rest of the page works again.
8. Select the Active filter and complete a task. Check that its row disappears, the status message reports it, and focus moves to the filter. Then do the opposite under Completed: uncheck a completed task.

### Inspect more than the screenshot

Open your browser's accessibility inspector (in Chromium and Firefox, it's part of the developer tools) and check what the browser actually computed: each control's role, name, state, and description. Check that every ID in `aria-labelledby` and `aria-describedby` exists, that the open dialog is named and modal, and that the controls behind it are missing from the accessibility tree while it's open.

Automated checkers can find unnamed controls, references to missing IDs, and some contrast problems. They can't tell whether a message is helpful, whether focus lands somewhere sensible, or whether the whole task makes sense. A clean report is a good sign, not proof.

A keyboard walkthrough and the accessibility inspector don't show what a screen reader actually says, so repeat the walkthrough with a screen reader and the browser your users have.

## Closing check

1. Why doesn't `role="button"` turn a clickable `<div>` into a button?
2. Why does the page focus the Edit button before it opens the editor?
3. Why does deleting the edited task send focus to the filter, when Cancel sends it back to the Edit button?

Check your reasoning:

- The role only changes what the accessibility tree reports. The `<div>` still can't be reached with Tab or pressed with Enter or Space until you write that behavior yourself.
- The dialog returns focus to whatever had focus when it opened. Not every browser focuses a button on click, so focusing it first makes the Edit button the return destination everywhere.
- Cancel leaves the Edit button in place, so focus can go back to it. Deleting removes the row and its Edit button, so the person needs another place to continue, and the filter is always there.

That brings it back to the question from the start: can someone complete the task, understand the result, and continue from a sensible place without using a mouse?

## Sources and further reading

- [WAI: introduction to web accessibility](https://www.w3.org/WAI/fundamentals/accessibility-intro/)
- [WAI-ARIA APG: accessible names and descriptions](https://www.w3.org/WAI/ARIA/apg/practices/names-and-descriptions/)
- [WAI-ARIA APG: developing a keyboard interface](https://www.w3.org/WAI/ARIA/apg/practices/keyboard-interface/)
- [WAI-ARIA APG: modal dialog pattern](https://www.w3.org/WAI/ARIA/apg/patterns/dialog-modal/)
- [HTML Standard: the dialog element](https://html.spec.whatwg.org/multipage/interactive-elements.html#the-dialog-element)
- [MDN: the dialog element](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/dialog)
- [MDN: the button element, including clicking and focus](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/button#clicking_and_focus)
- [WAI-ARIA: status role](https://www.w3.org/TR/wai-aria-1.2/#status)
- [WCAG: understanding status messages](https://www.w3.org/WAI/WCAG22/Understanding/status-messages.html)
- [WCAG: understanding label in name](https://www.w3.org/WAI/WCAG22/Understanding/label-in-name.html)
- [WCAG: understanding focus visible](https://www.w3.org/WAI/WCAG22/Understanding/focus-visible.html)
- [WCAG: understanding reflow](https://www.w3.org/WAI/WCAG22/Understanding/reflow.html)
- [WCAG: understanding target size minimum](https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html)
- [WCAG: associating validation errors and invalid state](https://www.w3.org/WAI/WCAG22/Techniques/aria/ARIA21)
- [Angular: dependent writable state with linkedSignal](https://angular.dev/guide/signals/linked-signal)
- [Angular: using DOM APIs and render callbacks](https://angular.dev/guide/components/dom-apis)
