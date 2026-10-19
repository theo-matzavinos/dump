---
title: "Forms and validation: drafts, errors, and saving"
description: "Build a task editor that keeps an edit draft apart from saved data, shows errors at the right moment, and handles a save that can fail, starting from a plain HTML form and ending with Zod and Angular Signal Forms."
pubDate: "2026-10-06"
updatedDate: "2026-10-15"
tags:
  - angular
  - forms
audience:
  - frontend
---

Someone opens the task editor to fix a typo in a title. While they're still typing, no red error should appear under the field. If they clear the title and press Tab, an error should show up and tell them what to write. If the title is fine but the network drops in the middle of saving, the editor should keep their text, say the save failed, and let them try again without retyping anything. And if they click Discard, the title should go back to what was saved, even though they've been typing for a while.

Each of those moments depends on a different piece of information: the text being edited, whether that text passes the rules, how the person has interacted with the field so far, and what happened on the last save. Forms get confusing when those pieces are mixed up, for example when "the title is invalid" is treated as "show the error now", or "the request finished" as "the task was saved".

This article builds that editor step by step. It starts with what a plain HTML form does on its own, then adds an edit draft, field state, validation rules, and a save that can fail, and finishes by wiring everything together with Angular's Signal Forms.

You'll need basic HTML and DOM events (the [DOM article](/dump/blog/html-dom-and-events/) covers the default actions this article relies on), promises with `async` and `await`, and the task editor from [Splitting a task page into Angular components](/dump/blog/angular-component-composition/), which this article extends. That article explains signals, `input`, `output`, and the `linkedSignal` draft used here.

The code uses Angular 22.2.1 with Signal Forms, Zod 4.6.5, and the [styling article's Tailwind setup and palette](/dump/blog/frontend-evolution-styling/#define-the-shared-palette-once). The code slices leave out the Tailwind classes; the full files include them, and you can ignore the `class="…"` strings there. To keep things focused, there's one task, no real server (a short simulated save stands in for it), and no handling for two saves racing each other. Reloading the page starts over.

## Contents

1. [What a plain HTML form does](#what-a-plain-html-form-does)
2. [The draft and the accepted task](#the-draft-and-the-accepted-task)
3. [What a form tracks for each field](#what-a-form-tracks-for-each-field)
4. [Describing the rules with a schema](#describing-the-rules-with-a-schema)
5. [Checking on the client and on the server](#checking-on-the-client-and-on-the-server)
6. [The save workflow](#the-save-workflow)
7. [Building the editor with Signal Forms](#building-the-editor-with-signal-forms)
8. [Focus after saving and discarding](#focus-after-saving-and-discarding)
9. [Trying the editor](#trying-the-editor)
10. [Going further](#going-further)

## What a plain HTML form does

Here's the smallest form that asks for a task title:

```html
<form>
  <label for="native-title">Task title (required)</label>
  <input id="native-title" name="title" type="text" required />
  <button type="submit">Save task</button>
</form>
```

Clicking Save, or pressing Enter while the text input has focus, **submits** the form. Submitting has a built-in default action, so the browser does all of this without any JavaScript:

1. It checks the built-in constraints, such as `required`. If one fails, it stops, shows a small message bubble next to the field, and moves focus there.
2. Otherwise it collects every field that has a `name` into pairs like `title=Read+the+DOM+article`.
3. It sends those pairs to the URL in the form's `action` attribute and loads the response as a new page. With no `action`, it uses the current page's URL, so the page reloads with `?title=…` added to the address.

Many websites still save data this way, with a full page load for every save. An Angular editor saves with JavaScript and stays on the same page, so the browser's navigation has to be switched off.

There's a second problem. For a text input, `required` only rejects an empty string. A title made of three spaces isn't empty, so `required` accepts it. The task needs a stronger rule: some text must remain after removing the whitespace at both ends. And you'll want to decide yourself when messages appear and what they look like, instead of getting the browser's bubbles.

So the editor in this article changes the form in two ways, and each one does a separate job:

```html
<form novalidate>
```

```js
const form = document.querySelector("form");

form.addEventListener("submit", (event) => {
  event.preventDefault();
  console.log("Save with JavaScript:", form.elements.title.value);
});
```

- `novalidate` turns off the browser's automatic checks and message bubbles when the form submits, because the editor will run its own rules and show its own messages.
- `event.preventDefault()` cancels the default action of the `submit` event, so the browser doesn't send the data or load a new page. Your JavaScript decides what saving means.

With `novalidate` alone, the page would still navigate. With `preventDefault()` alone, the browser would still check `required` before firing `submit`, so for an empty title it would show its bubble and your handler wouldn't run at all. So the editor uses both.

Listening to the form's `submit` event, instead of the button's `click` event, also catches Enter from the title input. Enter in a multi-line `<textarea>` still inserts a new line, which is what you want for a description.

Once the browser's checks are off, the editor has to replace everything they did: run the rules, show useful messages next to the right fields, and move focus to the problem. The rest of the article builds those pieces.

## The draft and the accepted task

When someone types into the title input, the browser first changes the input's text. Application code then reads that text and stores it somewhere. Where it stores it matters.

The page component holds the **accepted task**: the version that's been saved and that the rest of the page displays. If every keystroke wrote straight into that task, the page would show half-typed titles, and Discard would have nothing to go back to.

So the editor keeps a separate **draft**: a copy of the editable values that typing changes. Only a confirmed save copies the draft's values into the accepted task.

```text
TaskPage holds the accepted Task
  │
  └── task input → TaskEditor holds a { title, description } draft
                      ↑ typing updates this draft only
                      │
                      └── saved output, after a confirmed save → page replaces its accepted values

Discard → copy the current accepted values back into the draft
          clear the field history; leave the accepted task alone
```

Save the shared types in `task.ts`:

```ts
export interface Task {
  id: number;
  title: string;
  description: string;
  done: boolean;
}

export interface TaskDraft {
  title: string;
  description: string;
}

export interface TaskEdits extends TaskDraft {
  id: number;
}
```

What to notice:

- `TaskDraft` holds only what the editor lets you change. There's no `id` or `done`, so the editor can't accidentally change them.
- `TaskEdits` adds the `id` back. The editor's `saved` output sends one of these after a successful save, and the page uses it to update its task while keeping `done` as it was.
- The description is optional in the sense that the person may leave it blank. The draft still has a `description` property; a blank description is the empty string `""`.

The editor stays on the page after Save and after Discard. So Discard can't rely on Angular destroying the component to throw away its state. It has to put the accepted values back into the draft and reset the field history on purpose. The next section explains what that history is.

## What a form tracks for each field

A form library keeps a few flags for every field, next to its value. Follow one person through the title field to see what each one means.

Say the accepted title is "Read the DOM article":

```text
Open the editor:        Read the DOM article      valid, untouched, not dirty
Click in, select all,
type "Review the DOM article":                    valid, dirty
Type the original back: Read the DOM article      valid, still dirty
Press Tab to leave:                               valid, dirty, touched
Clear the field:        (empty)                   invalid, dirty, touched
```

Here's what changed at each step:

- **Valid** and **invalid** describe the current value. The form re-checks the rules every time the value changes, so the answer is always up to date.
- **Dirty** becomes true when the person changes the value through the input. Typing the original text back doesn't clear it. Dirty means "was edited at some point", and it stays true until code resets the field. A field that isn't dirty is called **pristine**.
- **Touched** becomes true when the person leaves the field. Moving focus away from an element is called **blur**, so touched usually means "this field has been blurred at least once".

The flags are independent, so a field can be in any combination. An empty title in a brand-new task is invalid before anyone has clicked into it: the rule already fails, but the field is untouched. That's why "invalid" can't be the signal to show an error, and the next part of this section handles that timing.

Dirty is history in the same way. If you need to know "would saving change this task?", compare the draft's values with the accepted task's values. Dirty can't answer that question, because it only records that an edit happened.

Two more pieces of state come up while saving:

- **Submitting** is true while a save is running. It turns false when the save ends, whether it worked or not, so the editor also needs a separate message that says which one happened.
- **Pending** is true while an asynchronous rule, such as "ask the server whether this name is taken", is still waiting for an answer. While a check is pending, the field isn't valid yet. If no other check has failed, it isn't invalid either. This editor's rules are all synchronous, so its fields are never pending.

**Resetting** a field clears its touched and dirty flags, and can also replace its value. The editor resets after a confirmed save and after Discard, and leaves everything as it is after a failed save.

### When to show an error

Whether a rule fails and when its message appears are two separate decisions. If you mix them, you end up changing the rules just to hide a message too early. This editor uses this policy:

- Check the values every time they change.
- Show a field's errors once the field is touched.
- When the person submits, mark every field touched, so errors appear even for fields they never visited.
- Show a title rejection from the server right away, and keep it until the title changes.

So in the walkthrough above, the error for the empty title appears at the last step, because the field was already touched. In a brand-new task, it would appear when the person leaves the field or presses Save.

## Describing the rules with a schema

The task's rules are short: the title must contain more than whitespace, and the description may be blank or left out, but if it's there it must be text. A **schema** is an object that describes the expected shape of some data and the checks it must pass. This article uses the Zod library to write one, in `task-schema.ts`:

```ts
import { z } from "zod";

export const taskSchema = z.object({
  title: z.string({ error: "Enter a task title as text." }).refine(
    (title) => {
      return title.trim() !== "";
    },
    { error: "Enter a task title, not just spaces." },
  ),
  description: z.string({ error: "Enter the description as text." }).optional(),
});
```

What to notice:

- `z.object(...)` checks an object's properties, and `z.string(...)` checks that a value is text. The `error` option sets the message for that check.
- `.refine(...)` adds a custom check. Here it fails when `title.trim()` is an empty string. `trim()` returns a new string without whitespace at the ends; it doesn't change `title` itself.
- `.optional()` also allows the description to be missing or `undefined`. An empty string is already valid text, so the editor can keep sending `""`.

You can run the schema on its own to see what it accepts. Save these checks in `check-schema.ts`:

```ts
import { taskSchema } from "./task-schema";

const blankDescription = taskSchema.safeParse({ title: "Read the DOM article", description: "" });
const absentDescription = taskSchema.safeParse({ title: "Read the DOM article" });
const blankTitle = taskSchema.safeParse({ title: "   ", description: "" });
const nonTextDescription = taskSchema.safeParse({ title: "Read the DOM article", description: 42 });

console.log(blankDescription.success); // true
console.log(absentDescription.success); // true
console.log(blankTitle.success); // false
console.log(nonTextDescription.success); // false
```

`safeParse` returns a result object instead of throwing when the data fails. When `success` is false, the result's `error` holds a list of **issues**: each one has a message and a path such as `["title"]` that says which property failed.

### How Angular reads a Zod schema

Angular's forms code needs to ask a schema for its issues. There are several schema libraries, each with its own API, and Angular can't write an adapter for every one. **Standard Schema** solves that: it's a small shared interface that Zod and other libraries implement. Every compatible schema exposes the same validate function, and it returns either the checked value or a list of issues with messages and paths.

Angular's `validateStandardSchema` function calls that interface and attaches each issue to the matching form field. You'll see it in the editor later. Zod does the checking; Standard Schema is only the shape of the conversation between Zod and Angular.

## Checking on the client and on the server

The editor's checks run in the browser, on the person's device, which is called the **client**. That makes them fast and helpful, but anyone can skip them: they can change the page with developer tools, or send a request with another program. The page's copy of the rules can also be out of date. So a real server checks every incoming request again, along with permissions and anything else only it knows, before it accepts the data.

That's why a title can pass every check in the browser and still fail to save. The editor has to handle two kinds of failure:

- The server answered and rejected the title. The person needs to change the title.
- The request never got an answer, for example because the network dropped. The title may be fine; the person needs to try again.

This article has no server, so `demo-save.ts` simulates one. It waits a moment, checks the same schema, and then picks one of three outcomes based on a demo-only select on the page: success, a title rejection, or a network failure.

```ts
import type { TaskDraft } from "./task";
import { taskSchema } from "./task-schema";

export type SaveOutcome = "success" | "field-error" | "network-error";

export type SaveResult =
  { kind: "saved"; value: TaskDraft } | { kind: "field-error"; message: string };

export class DemoNetworkError extends Error {}

export async function saveTaskDraft(payload: TaskDraft, outcome: SaveOutcome): Promise<SaveResult> {
  // Simulation only: no HTTP request or persistence.
  await new Promise<void>((resolve) => {
    setTimeout(resolve, 600);
  });

  const checked = taskSchema.safeParse(payload);
  if (!checked.success) {
    return {
      kind: "field-error",
      message: "The simulated receiver rejected the task. Enter a nonblank title.",
    };
  }

  if (outcome === "network-error") {
    throw new DemoNetworkError("The simulated request could not reach the receiver.");
  }

  if (outcome === "field-error") {
    return {
      kind: "field-error",
      message: "The simulated receiver rejected this title. Change it, then save again.",
    };
  }

  return {
    kind: "saved",
    value: { title: payload.title.trim(), description: payload.description },
  };
}
```

What to notice:

- The `await new Promise(...)` line just waits 600 milliseconds, like a slow request would. `setTimeout` calls `resolve` after the delay, and that finishes the promise.
- A rejection is **returned** as `{ kind: "field-error", message }`, because the server did answer: it said no. A network failure is **thrown** as a `DemoNetworkError`, because there's no answer at all, the same way `fetch` rejects when it can't reach the server. `class DemoNetworkError extends Error {}` creates a named error type, so the editor can recognize this exact failure with `instanceof` later.
- On success, the simulated server trims the title before accepting it and returns the accepted values. The schema only checks; changing the data into the form you store, such as trimming, is a separate step that the server does here.
- A real server would receive unknown data from the network and would need to validate all of it. This helper only takes the editor's typed two-string draft, because it exists to demonstrate the editor's side.

In both failure cases the editor keeps the draft. After a rejection, the person changes the title and saves again. After a network failure, they can press Save again with the same text.

## The save workflow

Here's everything that happens after the form submits:

```text
Submit
  → mark every field touched and check the rules
  → if a rule fails: skip saving and focus the first field with an error
  → otherwise: capture the payload and the selected simulated outcome
  → lock the fields, Discard, and Save while the request runs
  → wait for the result
       ├── title rejection: keep the draft, show the message on the title, focus the title
       ├── network failure: keep the draft, show retry guidance, focus the title
       └── success: send the confirmed edits to the page, reset the draft to them
  → unlock everything and leave focus somewhere useful
```

A few steps need explaining.

**Capture the payload.** The **payload** is the data sent with one request. The editor copies the draft into a new object before it starts waiting. If it read the draft again after the wait, it could pick up text typed in the meantime and treat it as what was sent.

**Lock the form while saving.** The title and description become read-only while the request runs, and Save and Discard are disabled. That keeps the draft and the payload the same and prevents a second save from starting. The save code also returns early if a save is already running. The button only becomes disabled after Angular updates the page, so that check stops a second submit that arrives first.

**Keep Save clickable when there are errors.** Many forms grey out Save until everything is valid. This one doesn't, because a disabled button can't tell anyone *what's* wrong. Clicking Save reveals the errors and moves focus to the first one. The save code still refuses invalid data, so nothing invalid reaches the server.

**Reset only after success.** On success, the confirmed values become both the page's accepted task and the editor's fresh draft. On failure, neither changes. "The request finished" isn't enough to reset the form; only "the request succeeded" is.

## Building the editor with Signal Forms

Angular has three form APIs: reactive forms, template-driven forms, and Signal Forms. This article uses **Signal Forms**, from `@angular/forms/signals`, because it builds the form directly on top of a signal that holds the draft.

Before the API names, here's what happens when someone types "R" into the title input once everything is wired up:

```text
You type "R" in the title input
  → the FormField directive hears the input's "input" event
  → it writes the new text into draft().title and marks the title dirty
  → editorForm.title().errors() re-runs the schema check on the new value
  → Angular re-renders the template, showing or hiding the error
```

The rest of this section builds each piece of that chain in `task-editor.ts`. The full file is at the end of the section.

### The draft and the form

```ts
export class TaskEditor {
  readonly task = input.required<Task>();
  readonly saveOutcome = input.required<SaveOutcome>();
  readonly saved = output<TaskEdits>();
  readonly status = signal("");
  private readonly injector = inject(Injector);

  readonly draft = linkedSignal<Task, TaskDraft>({
    source: this.task,
    computation: (task, previous) => {
      if (previous?.source.id === task.id) {
        return previous.value;
      }

      return { title: task.title, description: task.description };
    },
  });
```

What to notice:

- `task` is the accepted task from the page, `saveOutcome` is the demo select's value, and `saved` reports confirmed edits back. `status` holds the message shown under the buttons.
- `draft` is a `linkedSignal`: a writable signal that recalculates when its `source` changes. When the page sends a task with a new ID, the draft starts over from that task. When the page replaces the task but the ID is the same, the draft keeps the current text. The [composition article](/dump/blog/angular-component-composition/) explains this same-ID rule in detail.
- `this.task` is passed without calling it. Angular creates the component class first and sets its inputs afterwards, so calling `this.task()` while the class is being created would throw an error for a required input. `linkedSignal` reads it later, when something first reads the draft.

Next comes the form itself:

```ts
  readonly editorForm = form(this.draft, (path) => {
    validateStandardSchema(path, taskSchema);
    metadata(path.title, REQUIRED, () => true);
    readonly(path.title, { when: ({ stateOf }) => stateOf(path).submitting() });
    readonly(path.description, { when: ({ stateOf }) => stateOf(path).submitting() });
  });
```

`form(this.draft, rules)` returns a **field tree**: an object with the same shape as the draft, where every property is a field. `editorForm.title` is the title field, and calling it, `editorForm.title()`, gives you that field's state: `value()`, `errors()`, `valid()`, `invalid()`, `touched()`, `dirty()`, and more. Calling `editorForm()` gives you the state of the whole form, including `submitting()`. Each of these is a signal, so you read it by calling it. Writing to a field writes into the `draft` signal, so the draft and the form always agree.

The second argument lists the rules, using `path` to point at fields:

- `validateStandardSchema(path, taskSchema)` runs the Zod schema on the whole draft and attaches each issue to its field.
- `metadata(path.title, REQUIRED, () => true)` marks the title as required, so Angular adds the native `required` attribute to the input. Screen readers announce that attribute. The schema does all the checking; Zod schemas don't carry this kind of metadata, which is why it's declared separately.
- The two `readonly(...)` calls make both fields read-only whenever the form is submitting. That's the lock from the workflow.

### Connecting the inputs

Here's the title part of the template, without styling classes:

```html
<form novalidate (submit)="save($event)">
  <label for="draft-title">Task title (required)</label>
  <p id="title-help">Use a title containing more than whitespace.</p>
  <input
    id="draft-title"
    type="text"
    [formField]="editorForm.title"
    aria-describedby="title-help title-error"
    [attr.aria-invalid]="showTitleErrors() && editorForm.title().invalid()"
  />
  <p id="title-error" aria-live="polite">
    @if (showTitleErrors()) {
      @for (error of editorForm.title().errors(); track error) {
        <span>{{ error.message }}</span>
      }
    }
  </p>
```

What to notice:

- The `<form>` has `novalidate` and calls `save($event)` on `submit`, the same two pieces from the plain HTML section.
- `[formField]="editorForm.title"` uses the `FormField` directive to connect the input to the title field. It writes typed text into the field, marks the field dirty and touched at the right moments, and sets the input's value, `required`, and `readonly` attributes from the field state. Because it handles all of those, you don't add your own `[value]`, `(input)`, `[readonly]`, or `required` to the same input.
- The error paragraph lists the field's messages only when `showTitleErrors()` is true. That's the display policy, and it's defined in the next slice.
- `aria-describedby`, `aria-invalid`, and `aria-live` connect the help text and the error to the input for screen readers. The [accessibility article](/dump/blog/accessibility-in-practice/) explains that pattern. The only new part is that `aria-invalid` follows the same `showTitleErrors()` check, so the accessible invalid state follows the same condition as the visible error.

The description field uses the same pattern with `[formField]="editorForm.description"`, and it shows its errors once `editorForm.description().touched()` is true. The buttons and status message finish the form:

```html
  <button type="submit" [disabled]="editorForm().submitting()">Save task</button>
  <button type="button" [disabled]="editorForm().submitting()" (click)="discard()">
    Discard edits
  </button>
  <p id="save-status" role="status" aria-atomic="true">{{ status() }}</p>
</form>
```

Both buttons are disabled only while a save is running. Discard is `type="button"`, so clicking it doesn't submit the form.

### When the title shows its errors

```ts
  readonly showTitleErrors = computed(() => {
    const field = this.editorForm.title();
    if (field.touched()) {
      return true;
    }

    for (const error of field.errors()) {
      if (error.kind === "server") {
        return true;
      }
    }
    return false;
  });
```

This `computed` signal is the display policy for the title. It's true once the field is touched, which covers both "left the field" and "pressed Save", because submitting marks every field touched. It's also true while the title carries an error of kind `"server"`, which is the kind the editor gives to the simulated server's rejection. That keeps a rejection visible even after a reset clears the touched flag, a case covered in [Going further](#going-further).

### Saving

The `save` method uses Signal Forms' `submit` function. You give `submit` the form and two callbacks, and it runs the checks for you:

1. It marks every editable field touched.
2. If the form is invalid, it calls your `onInvalid` callback and stops.
3. Otherwise it sets `submitting()` to true, calls your `action` callback, and waits for it.
4. If `action` returns an error object, `submit` attaches that error to the field it names. When `action` finishes or throws, `submitting()` goes back to false.

```ts
  async save(event: SubmitEvent) {
    event.preventDefault();
    if (this.editorForm().submitting()) {
      return;
    }

    let confirmed: TaskDraft | undefined;
    this.status.set("");
    try {
      await submit(this.editorForm, {
        ignoreValidators: "none",
        onInvalid: () => {
          this.status.set("Check the fields below. Nothing was saved.");
        },
        action: async (fields) => {
          const payload = { ...this.draft() };
          const taskId = this.task().id;
          const outcome = this.saveOutcome();
          this.status.set("Saving… Editing is paused.");

          const result = await saveTaskDraft(payload, outcome);
          if (result.kind === "field-error") {
            this.status.set("Not saved. Correct the title, then save again.");
            return { kind: "server", message: result.message, fieldTree: fields.title };
          }

          this.saved.emit({ id: taskId, ...result.value });
          confirmed = result.value;
          this.status.set("Task saved. The accepted title has been trimmed.");
          return undefined;
        },
      });
```

What to notice:

- `event.preventDefault()` stops the browser's navigation, and the early return ignores a second submit while one is running. Signal Forms also refuses to start a second `submit` for the same form, but returning early keeps the status message and focus from being replaced.
- `ignoreValidators: "none"` tells `submit` to run `action` only when every rule has passed. By default it would also run while some rules are still pending. This editor has no pending rules, but the stricter setting matches the workflow: save only data that's known to be valid.
- Inside `action`, the first three lines capture the payload, the task ID, and the outcome before the `await`. That's the capture step from the workflow.
- A rejection returns `{ kind: "server", message, fieldTree: fields.title }`. `submit` adds it to the title's `errors()`, so the template shows it like any other title error. Signal Forms removes that error automatically as soon as the title's value changes.
- On success, `saved.emit(...)` sends the confirmed edits to the page, and `confirmed` remembers them for the reset below. Returning `undefined` tells `submit` that there are no errors to attach.

A network failure is a thrown `DemoNetworkError`, so it passes through `submit` and lands in the `catch` block:

```ts
    } catch (error: unknown) {
      if (!(error instanceof DemoNetworkError)) {
        throw error;
      }
      this.status.set("Not saved: simulated network failure. Your draft is kept. Try Save again.");
    } finally {
      afterNextRender(
        () => {
          if (confirmed !== undefined) {
            this.editorForm.title().focusBoundControl();
            this.editorForm().reset(confirmed);
            return;
          }

          const errors = this.editorForm().errorSummary();
          if (errors.length > 0) {
            errors[0].fieldTree().focusBoundControl();
            return;
          }
          this.editorForm.title().focusBoundControl();
        },
        { injector: this.injector },
      );
    }
  }
```

What to notice:

- The network failure becomes a status message for the whole form, and the title gets no error, because nothing is wrong with the title. The person can press Save again with the same text.
- Any other error is thrown again. A bug in the code shouldn't be shown to the person as "network failure".
- The `finally` block runs in every case. `afterNextRender` waits until Angular has updated the page, so the fields are unlocked and any error messages are rendered before focus moves. It needs the `injector` because Angular functions like this one can find the component's injector on their own only while the class is being created, and `save` runs much later. The next section explains where focus goes.
- On success, `reset(confirmed)` puts the confirmed values into the draft and clears touched and dirty. It runs after focus moves to the title: moving focus out of the description blurs it, and if the reset ran first, that blur would mark the description touched again right away.

### Discarding

```ts
  discard() {
    if (this.editorForm().submitting()) {
      return;
    }

    const accepted = this.task();
    this.editorForm().reset({ title: accepted.title, description: accepted.description });
    this.status.set("Draft restored to the current accepted values.");
    this.editorForm.title().focusBoundControl();
  }
}
```

Discard reads the page's **current** accepted task, so after a successful save it restores the saved values, not the sample task the page started with. `reset(...)` replaces the draft and clears the field history in one step. The accepted task never changes, because typing only ever wrote to the draft.

Here are the full files for the editor and the page:

<details>
<summary>Full <code>task-editor.ts</code></summary>

```ts
import {
  Component,
  Injector,
  afterNextRender,
  computed,
  inject,
  input,
  linkedSignal,
  output,
  signal,
} from "@angular/core";
import {
  FormField,
  REQUIRED,
  form,
  metadata,
  readonly,
  submit,
  validateStandardSchema,
} from "@angular/forms/signals";
import { DemoNetworkError, saveTaskDraft } from "./demo-save";
import type { SaveOutcome } from "./demo-save";
import type { Task, TaskDraft, TaskEdits } from "./task";
import { taskSchema } from "./task-schema";

@Component({
  selector: "task-editor",
  host: { class: "block min-w-0" },
  imports: [FormField],
  template: `
    <form class="space-y-3" novalidate (submit)="save($event)">
      <label for="draft-title" class="block font-medium">Task title (required)</label>
      <p id="title-help" class="text-muted">Use a title containing more than whitespace.</p>
      <input
        id="draft-title"
        type="text"
        [formField]="editorForm.title"
        aria-describedby="title-help title-error"
        [attr.aria-invalid]="showTitleErrors() && editorForm.title().invalid()"
        class="block min-h-11 w-full min-w-0 rounded-lg border border-muted bg-surface px-3 py-2 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
      />
      <p id="title-error" class="min-h-6 break-words text-accent" aria-live="polite">
        @if (showTitleErrors()) {
          @for (error of editorForm.title().errors(); track error) {
            <span class="block">{{ error.message }}</span>
          }
        }
      </p>

      <label for="draft-description" class="block font-medium">Description (optional)</label>
      <p id="description-help" class="text-muted">Leave this blank if the task needs no notes.</p>
      <textarea
        id="draft-description"
        rows="3"
        [formField]="editorForm.description"
        aria-describedby="description-help description-error"
        [attr.aria-invalid]="
          editorForm.description().touched() && editorForm.description().invalid()
        "
        class="block min-h-11 w-full min-w-0 resize-y rounded-lg border border-muted bg-surface px-3 py-2 [overflow-wrap:anywhere] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
      ></textarea>
      <p id="description-error" class="min-h-6 break-words text-accent" aria-live="polite">
        @if (editorForm.description().touched()) {
          @for (error of editorForm.description().errors(); track error) {
            <span class="block">{{ error.message }}</span>
          }
        }
      </p>

      <div class="flex flex-wrap gap-2">
        <button
          type="submit"
          [disabled]="editorForm().submitting()"
          class="min-h-11 min-w-0 max-w-full rounded-lg bg-accent px-4 py-2 font-medium text-page [overflow-wrap:anywhere] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent disabled:opacity-60"
        >
          Save task
        </button>
        <button
          type="button"
          [disabled]="editorForm().submitting()"
          (click)="discard()"
          class="min-h-11 min-w-0 max-w-full rounded-lg border border-line px-4 py-2 [overflow-wrap:anywhere] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent disabled:opacity-60"
        >
          Discard edits
        </button>
      </div>
      <p id="save-status" class="min-h-6 break-words" role="status" aria-atomic="true">
        {{ status() }}
      </p>
    </form>
  `,
})
export class TaskEditor {
  readonly task = input.required<Task>();
  readonly saveOutcome = input.required<SaveOutcome>();
  readonly saved = output<TaskEdits>();
  readonly status = signal("");
  private readonly injector = inject(Injector);

  readonly draft = linkedSignal<Task, TaskDraft>({
    source: this.task,
    computation: (task, previous) => {
      if (previous?.source.id === task.id) {
        return previous.value;
      }

      return { title: task.title, description: task.description };
    },
  });

  readonly editorForm = form(this.draft, (path) => {
    validateStandardSchema(path, taskSchema);
    metadata(path.title, REQUIRED, () => true);
    readonly(path.title, { when: ({ stateOf }) => stateOf(path).submitting() });
    readonly(path.description, { when: ({ stateOf }) => stateOf(path).submitting() });
  });

  readonly showTitleErrors = computed(() => {
    const field = this.editorForm.title();
    if (field.touched()) {
      return true;
    }

    for (const error of field.errors()) {
      if (error.kind === "server") {
        return true;
      }
    }
    return false;
  });

  async save(event: SubmitEvent) {
    event.preventDefault();
    if (this.editorForm().submitting()) {
      return;
    }

    let confirmed: TaskDraft | undefined;
    this.status.set("");
    try {
      await submit(this.editorForm, {
        ignoreValidators: "none",
        onInvalid: () => {
          this.status.set("Check the fields below. Nothing was saved.");
        },
        action: async (fields) => {
          const payload = { ...this.draft() };
          const taskId = this.task().id;
          const outcome = this.saveOutcome();
          this.status.set("Saving… Editing is paused.");

          const result = await saveTaskDraft(payload, outcome);
          if (result.kind === "field-error") {
            this.status.set("Not saved. Correct the title, then save again.");
            return { kind: "server", message: result.message, fieldTree: fields.title };
          }

          this.saved.emit({ id: taskId, ...result.value });
          confirmed = result.value;
          this.status.set("Task saved. The accepted title has been trimmed.");
          return undefined;
        },
      });
    } catch (error: unknown) {
      if (!(error instanceof DemoNetworkError)) {
        throw error;
      }
      this.status.set("Not saved: simulated network failure. Your draft is kept. Try Save again.");
    } finally {
      afterNextRender(
        () => {
          if (confirmed !== undefined) {
            this.editorForm.title().focusBoundControl();
            this.editorForm().reset(confirmed);
            return;
          }

          const errors = this.editorForm().errorSummary();
          if (errors.length > 0) {
            errors[0].fieldTree().focusBoundControl();
            return;
          }
          this.editorForm.title().focusBoundControl();
        },
        { injector: this.injector },
      );
    }
  }

  discard() {
    if (this.editorForm().submitting()) {
      return;
    }

    const accepted = this.task();
    this.editorForm().reset({ title: accepted.title, description: accepted.description });
    this.status.set("Draft restored to the current accepted values.");
    this.editorForm.title().focusBoundControl();
  }
}
```

</details>

### The page component

The page component holds the accepted task and the demo select. These are the parts that matter here:

```ts
export class TaskPage {
  readonly task = signal<Task>({
    id: 1,
    title: "Read the DOM article",
    description: "Note how a native form submits.",
    done: false,
  });
  readonly saveOutcome = signal<SaveOutcome>("success");

  setSaveOutcome(value: string) {
    if (value !== "success" && value !== "field-error" && value !== "network-error") {
      throw new Error("Unknown simulated save outcome.");
    }
    this.saveOutcome.set(value);
  }

  acceptEdits(edits: TaskEdits) {
    this.task.update((current) => {
      return { ...current, title: edits.title, description: edits.description };
    });
  }
}
```

What to notice:

- The template uses the editor as `<task-editor [task]="task()" [saveOutcome]="saveOutcome()" (saved)="acceptEdits($event)" />`, so the page hears about confirmed saves only, never single keystrokes.
- `acceptEdits` builds a new task object from the current one, so `id` and `done` stay as they were.
- A `<select>` element always gives you a string. `setSaveOutcome` checks the string before storing it as a `SaveOutcome`. A type assertion such as `value as SaveOutcome` would only silence TypeScript; it wouldn't check anything.
- The editor captures the outcome when a save starts, so changing the select during a save affects the next save only.

<details>
<summary>Full <code>task-page.ts</code></summary>

```ts
import { Component, signal } from "@angular/core";
import type { SaveOutcome } from "./demo-save";
import type { Task, TaskEdits } from "./task";
import { TaskEditor } from "./task-editor";

@Component({
  selector: "task-page",
  imports: [TaskEditor],
  template: `
    <main class="mx-auto max-w-2xl px-4 py-8">
      <h1 class="mb-6 text-3xl font-semibold [overflow-wrap:anywhere]">Task notes</h1>
      <section
        aria-labelledby="accepted-heading"
        class="mb-6 rounded-lg border border-line bg-surface p-4"
      >
        <h2 id="accepted-heading" class="mb-3 text-xl font-semibold [overflow-wrap:anywhere]">
          Accepted task
        </h2>
        <p id="accepted-title" class="font-medium [overflow-wrap:anywhere]">{{ task().title }}</p>
        <p id="accepted-description" class="mt-2 whitespace-pre-wrap [overflow-wrap:anywhere]">
          {{ task().description }}
        </p>
        @if (task().done) {
          <p class="mt-2 text-muted">Completed</p>
        } @else {
          <p class="mt-2 text-muted">Active</p>
        }
      </section>

      <label for="demo-outcome" class="mb-2 block font-medium">Next save result (demo only)</label>
      <select
        #outcomeSelect
        id="demo-outcome"
        aria-describedby="demo-help"
        [value]="saveOutcome()"
        (change)="setSaveOutcome(outcomeSelect.value)"
        class="mb-2 block min-h-11 w-full min-w-0 max-w-full rounded-lg border border-muted bg-surface px-3 py-2 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
      >
        <option value="success">Success</option>
        <option value="field-error">Title rejection</option>
        <option value="network-error">Network failure</option>
      </select>
      <p id="demo-help" class="mb-6 text-muted">
        Simulates a 600 ms request. Nothing is sent or stored.
      </p>

      <section aria-labelledby="editor-heading">
        <h2 id="editor-heading" class="mb-4 text-xl font-semibold">Edit task {{ task().id }}</h2>
        <task-editor [task]="task()" [saveOutcome]="saveOutcome()" (saved)="acceptEdits($event)" />
      </section>
    </main>
  `,
})
export class TaskPage {
  readonly task = signal<Task>({
    id: 1,
    title: "Read the DOM article",
    description: "Note how a native form submits.",
    done: false,
  });
  readonly saveOutcome = signal<SaveOutcome>("success");

  setSaveOutcome(value: string) {
    if (value !== "success" && value !== "field-error" && value !== "network-error") {
      throw new Error("Unknown simulated save outcome.");
    }
    this.saveOutcome.set(value);
  }

  acceptEdits(edits: TaskEdits) {
    this.task.update((current) => {
      return { ...current, title: edits.title, description: edits.description };
    });
  }
}
```

</details>

Bootstrap it in `main.ts`:

```ts
import { bootstrapApplication } from "@angular/platform-browser";
import { TaskPage } from "./task-page";

bootstrapApplication(TaskPage);
```

In the host HTML page, replace the earlier page element with `<task-page></task-page>`, and keep the styling article's CSS file, `data-theme="dark"` on `<html>`, and `class="bg-page font-sans text-foreground"` on `<body>`. The app is made of `task.ts`, `task-schema.ts`, `demo-save.ts`, `task-editor.ts`, `task-page.ts`, and `main.ts`. `check-schema.ts` is only for trying the schema on its own.

## Focus after saving and discarding

The [accessibility article](/dump/blog/accessibility-in-practice/) covers labels, help text, error associations, and live regions in depth. Two things are specific to this editor: where focus goes after each action, and what the read-only lock does while saving.

**Focus.** `focusBoundControl()` moves keyboard focus to the input connected to a field. The editor uses it so that, after every action, focus lands on the input the person most likely needs next:

| After…                      | Focus goes to                                         |
| --------------------------- | ----------------------------------------------------- |
| A submit with failing rules | The first field with an error, from `errorSummary()` |
| A title rejection           | The title, which now shows the server's message       |
| A network failure           | The title, so pressing Enter saves again              |
| A successful save           | The title, ready for the next edit                    |
| Discard                     | The title                                             |

`errorSummary()` lists the errors of a field and everything inside it, in field order, so `errors[0]` belongs to the first field that needs fixing. This is an inline editor, so focus stays in the normal page order; there's no dialog and no focus trap.

**The read-only lock.** While saving, both fields are read-only. The person can still focus them, select text, and read them, but can't change them. One detail can surprise you: in Signal Forms, a read-only field doesn't count toward its parent's state, so while a save is running, the form's `valid()` ignores both fields. That's fine here, because the editor checked validity before the save started and doesn't look at it again until the save ends.

## Trying the editor

Run the app and go through these steps. Each one checks one idea from the article.

1. Open the page. The draft matches the accepted task, and no error is shown.
2. Type a different title, then type the original back. The accepted task never changes, and the title stays dirty until a reset.
3. Clear the title, or type only spaces, and press Tab. The error appears. Then reload, clear the title without leaving it, and press Enter: the error appears and nothing is saved.
4. Leave the description blank and save a title with spaces at both ends. The accepted title is trimmed, the description stays blank, and the draft resets to the trimmed values.
5. Choose "Title rejection" and save. The draft is kept, the accepted task doesn't change, and the title shows the server's message. Pressing Save again with the same title doesn't start a save; the status asks you to check the fields. Change the title and the message disappears.
6. Choose "Network failure" and save. The status message offers a retry, the title shows no error, and pressing Save again with the same text runs another save.
7. While a save is running, try typing, pressing Discard, and pressing Save again. Nothing changes until the save finishes, and only one save runs.
8. Change both fields, then press Discard. The draft goes back to the current accepted task, including any title saved in step 4.
9. Repeat a few steps with the keyboard only: Enter in the title to save, Tab and Shift+Tab to move, and Space to press the buttons.

## Going further

These details didn't fit the main path, but you'll run into them in larger forms.

- **Rules that compare fields.** Some rules depend on more than one field, such as "a description is required when the task is marked urgent". The schema can express those with a refinement on the whole object that names a field in its issue `path`, and `validateStandardSchema` then shows the error on that field.
- **Schema transforms.** Zod can transform values, for example trimming a string while it parses. `validateStandardSchema` only reads the issues from the schema and never writes the transformed value back into the draft. That's why the simulated server trims the title in its own code.
- **Reset and server errors.** `reset(value)` clears touched and dirty but leaves a server error in place. The server error disappears only when the field's value changes. So if Discard restores a title that's different from the rejected one, the error goes away. If it restores the same rejected title, the error stays, and `showTitleErrors` keeps it visible even though touched is false again.
- **`FormRoot`.** Signal Forms also has a `FormRoot` directive. When you write `<form [formRoot]="editorForm">`, it adds `novalidate`, calls `preventDefault()`, and runs `submit` with options you pass to `form()` when creating the form. This editor handles `submit` itself so that the whole save, including focus, is visible in one method. Use one approach per form, never both.

## Closing check

The opening asked for an editor that waits to show errors, survives a failed save, and can throw away edits. It does that by keeping the text, the rules, the interaction history, and the save result apart. Typing changes only the draft, so Discard and failed saves leave the accepted task alone. The rules check the value all the time, while touched decides when the person sees the result. And each save ends with an explicit result, so a rejection, a network failure, and a success each get their own response.

1. A new task's title is empty and invalid, but no error is visible. Why, and what makes the error appear?
2. Why does Discard work even though the person typed for a while, and why does dirty stay true after they type the original title back?
3. A title passes every check in the browser, but the save fails. What should the editor keep, and how should a title rejection differ from a network failure?

Check your reasoning:

- Invalid describes the value; touched describes what the person has done. The rule fails immediately, but the editor shows errors only once the field is touched, which happens when the person leaves the field or presses Save.
- Typing only changes the draft, so the accepted task is still there to copy back. Dirty records that an edit happened, and only a reset clears it; it never compares values.
- The server makes the final decision, so client checks can't promise success. The editor keeps the draft in both cases. A rejection attaches the server's message to the title until the title changes; a network failure shows a form-level message and lets the person retry with the same text.

## Sources and further reading

- [Angular: Signal Forms overview](https://angular.dev/guide/forms/signals/overview)
- [Angular: form models and field trees](https://angular.dev/guide/forms/signals/models)
- [Angular: field state management](https://angular.dev/guide/forms/signals/field-state-management)
- [Angular: validation and schema integration](https://angular.dev/guide/forms/signals/validation)
- [Angular: form submission](https://angular.dev/guide/forms/signals/form-submission)
- [Angular: field metadata](https://angular.dev/guide/forms/signals/field-metadata)
- [Zod: schema API](https://zod.dev/api)
- [Standard Schema: shared interfaces](https://standardschema.dev/)
- [MDN: the form element](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/form)
- [MDN: client-side form validation](https://developer.mozilla.org/en-US/docs/Learn_web_development/Extensions/Forms/Form_validation)
- [WCAG: associating validation errors and invalid state](https://www.w3.org/WAI/WCAG22/Techniques/aria/ARIA21)
