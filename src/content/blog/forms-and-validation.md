---
title: "A form is more than its values"
description: "Separate accepted data from an edit draft, distinguish validation from interaction and submission, and build a task editor with useful errors and a deliberate save workflow."
pubDate: "2026-10-06"
tags:
  - angular
  - forms
  - frontend
---

An empty title can be invalid before anyone has visited its field. A title can pass every client-side rule and still fail to save. Someone can change a title, put the original text back, and leave a field marked dirty.

These are not contradictions. The text, the checks applied to it, the person's interaction history, and the result of saving answer different questions.

This article extends the task editor from [Building components with clear ownership](/dump/blog/angular-component-composition/). It keeps one accepted task and one permanent inline editor, adds an optional description, and gives saving a visible asynchronous result. There is no list, dialog, backend, or persistence layer. Reloading starts the demonstration again.

The complete example uses Angular 22.2.1 Signal Forms, Zod 4.6.5, and the [styling article's Tailwind 4 setup and dark/light palette](/dump/blog/frontend-evolution-styling/#define-the-shared-palette-once). The [accessibility article](/dump/blog/accessibility-in-practice/) explains names, descriptions, live feedback, and keyboard focus in more depth.

## Contents

1. [Resolve three apparent contradictions](#resolve-three-apparent-contradictions)
2. [Separate controls, the draft, and accepted data](#separate-controls-the-draft-and-accepted-data)
3. [Track independent questions independently](#track-independent-questions-independently)
4. [Separate validation rules from message visibility](#separate-validation-rules-from-message-visibility)
5. [Describe the task rules once](#describe-the-task-rules-once)
6. [Treat client validation as guidance, not acceptance](#treat-client-validation-as-guidance-not-acceptance)
7. [Make submission a complete workflow](#make-submission-a-complete-workflow)
8. [Connect the workflow to Signal Forms](#connect-the-workflow-to-signal-forms)
9. [Make correction accessible](#make-correction-accessible)

## Resolve three apparent contradictions

### Invalid does not mean already visited

An empty title fails a rule that requires meaningful text. That fact can be known immediately. It does not mean someone has focused the input, finished typing, or attempted to save.

Displaying an error as soon as the editor appears would treat an unfinished starting point as a failed interaction. Instead, the form can know the rule failed while waiting until the person leaves the field or submits before showing its message.

### Passing client rules does not mean saved

The browser can check that a title contains text. It cannot guarantee that a later request will reach a server, that the server will accept the title, or that the server's data has not changed since the page loaded.

“Valid under these checks” and “accepted by the save operation” are separate results. A failed save must not erase a usable draft or display success merely because client validation passed.

### Dirty does not mean different now

Suppose the accepted title is “Read the DOM article”:

```text
Start:                 Read the DOM article
Type a different title: Review the DOM article
Type the original back: Read the DOM article
```

The current text equals the accepted text again. The history still includes an edit. A dirty flag records that history until it is explicitly cleared; it is not a continuously recomputed comparison with accepted data.

If a feature needs the precise question “Would saving change this record?”, compare the relevant draft values with the accepted values under an explicit comparison policy. Do not use `dirty` as an equality test.

## Separate controls, the draft, and accepted data

When someone types, the browser first changes the input's current text. Application code then reads that value and updates an edit draft. Only a confirmed save should update the accepted task used elsewhere on the page.

A **control** is the interactive element, such as an input or textarea. The **draft** is application data representing the unfinished edit. The **accepted task** is the application's current accepted record, also called canonical state.

```text
TaskPage owns the accepted Task
  │
  └── task input → TaskEditor owns { title, description } draft
                      ↑ typing updates this draft only
                      │
                      └── confirmed saved output → page replaces accepted values

Discard → copy current accepted values back into the draft
          reset interaction history; do not change the accepted task
```

The form library will attach validation and interaction state to the draft. It does not create an ownership boundary automatically: wrapping the page's accepted task directly would make each keystroke change accepted data.

Save the shared contracts in `task.ts`:

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

The editor does not edit `id` or `done`. Its typed `saved` output reports confirmed edits with an ID; the page applies them to its current record, preserving completion state.

Here “optional description” means the person may leave it blank. The form model still has a `description` property containing a string. A blank string and an absent JavaScript property are different representations; this editor deliberately uses the former.

The editor remains mounted after Save or Discard. Discard therefore cannot rely on destroying a component to remove its local state. It must restore data and interaction metadata deliberately. A Cancel action in an editor that closes would need the same ownership rule: do not apply its draft to accepted data.

## Track independent questions independently

Consider the actual mechanism before choosing flag names:

| Question                                           | State commonly used to answer it       |
| -------------------------------------------------- | -------------------------------------- |
| What is currently being edited?                    | Value                                  |
| Which checks have failed?                          | Validation errors; valid/invalid state |
| Has the person visited and left the field?         | Touched                                |
| Has the person changed it through the control?     | Dirty                                  |
| Is a validation check still waiting for an answer? | Pending validation                     |
| Is a save action currently running?                | Submitting                             |
| What happened when saving finished?                | Success or failure feedback            |

These states can coexist. A field may be invalid and untouched. It may be valid and dirty. An asynchronous validation check may be pending without having failed. A save request can be running even though no validation check is pending.

**Touched** normally becomes true after the field loses focus, an event called blur. Submitting can also mark fields touched so errors become visible. Code can mark a field touched without a blur event.

**Dirty** normally becomes true after a user edit. Programmatically changing a model is not necessarily a user edit, and putting an old value back does not clear the history. APIs also allow code to mark fields dirty or pristine. **Pristine** means dirty is false; it does not prove equality with an accepted record.

**Pending validation** means an answer is not yet known. It is not another spelling of invalid. In Signal Forms, neither `valid()` nor `invalid()` has to be true while the answer is unknown. This example has only synchronous rules, so it does not need an asynchronous validator.

**Submitting** covers the awaited save action. It ends on success or failure; its ending does not tell the interface which outcome occurred. Keep an explicit visible result too.

Resetting is also an operation, not a comparison: it clears interaction history, and can optionally replace the draft values. Reset after a confirmed save or an explicit Discard—not after every submit attempt.

## Separate validation rules from message visibility

A title rule asks whether the value is acceptable. A display policy asks when its error should be presented. Keeping them separate avoids changing validation merely to hide a premature message.

A useful policy for this editor is:

- Check values whenever they change.
- Show ordinary field errors after blur.
- On submission, reveal errors even for fields that have not been visited.
- Keep a returned title rejection visible until that title changes.

### Native required is a narrower rule

This independent HTML form demonstrates the browser's built-in behavior:

```html
<form>
  <label for="native-title">Task title (required)</label>
  <input id="native-title" name="title" type="text" required />
  <button type="submit">Save task</button>
</form>
```

For this text input, `required` rejects an empty string. A string containing spaces is not empty, so `required` alone accepts it. The task needs a stronger rule: at least some text must remain after removing whitespace from the ends.

Without custom handling, the browser checks native constraints before submission, presents its own feedback, and normally navigates when the form submits. The snapshot above is not a save implementation.

The complete editor uses `novalidate` to turn off automatic browser validation feedback. Its submit handler also calls `preventDefault()` to stop navigation. Those are different jobs: `novalidate` does not prevent navigation, and `preventDefault()` does not validate a value.

Application rules can also relate fields—for example, requiring a description when a particular task type is selected. That rule depends on more than one value, so checking each control in isolation is insufficient. This small editor needs only the nonblank-title rule; it does not introduce a cross-field validator.

Once native feedback is turned off, the application must provide its replacement: actual rules, visible useful messages, field associations, and a correction path. Keeping a native `required` attribute still expresses the requirement to the browser and accessibility APIs, but it does not make a schema's custom rules run.

Native constraint validity and the form library's validation state are separate mechanisms. Do not assume that adding an HTML attribute defines a Signal Forms rule, or that importing a schema automatically supplies every native constraint attribute.

## Describe the task rules once

The task requires a nonblank title. A description may be blank or omitted by another consumer. If a description is supplied, it must be text.

A **schema** describes the expected data and its checks. This example uses Zod to express those rules in `task-schema.ts`:

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

`z.object(...)` checks properties of an object. `z.string(...)` checks that a value is text. The refinement adds the nonblank condition and its message. `trim()` returns a new string without whitespace at its ends; using that string in the check does not change the original title.

`.optional()` allows an absent description or `undefined`. It does not require the editor to remove a property when its textarea is empty. An empty string is already valid text.

These independent checks can be saved in `check-schema.ts` beside the schema:

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

`safeParse` returns a result with either checked data or issues instead of throwing for a validation failure. An issue identifies what failed, with a message and a property path such as `title`.

### Standard Schema connects producer and consumer

A form library needs a way to ask a schema for its validation result. Otherwise it needs a different adapter for each validation library's API.

**Standard Schema** defines a shared interface for that conversation. Compatible schemas expose a validation function whose result contains checked data or issues with messages and paths. Zod supplies the validator; Standard Schema is the interface, not another validator library.

Angular's `validateStandardSchema` consumes that interface and routes issues to the corresponding fields. It does **not** write a schema's transformed output back into the form model. Adding a Zod trimming transform would therefore not silently normalize this editor's draft.

Here the schema only checks. The simulated save operation separately chooses to trim the **accepted title** and leave the description unchanged. Validation and normalization—changing data into the representation to store—are explicit, separate decisions.

## Treat client validation as guidance, not acceptance

Client code runs on the user's device. Someone can bypass the page, modify it, or send a request using another tool. Even an unmodified page can use rules or data that have become stale.

A real server must independently validate incoming data and enforce its own permissions and current business rules before accepting it. Sharing a schema can reduce duplicated rules; it does not remove that server boundary or guarantee acceptance.

The demonstration has no server. Its helper waits briefly, checks the same schema independently, and simulates one of three outcomes chosen by a labelled demo-only select:

- **Success:** return confirmed edits, with the title trimmed.
- **Field rejection:** return a useful title message even though the basic client rules passed.
- **Network failure:** throw a known demonstration error, without claiming that a particular field is wrong.

Save this in `demo-save.ts`:

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

The typed helper is a simulation of this editor's two-string payload, not a general server endpoint. Its schema-failure branch is deliberately limited to that contract; a real receiver must validate unknown request data and return the appropriate field or form errors. No backend implementation is needed to demonstrate the client workflow.

A field rejection tells the person what to correct. A network failure says the operation could not complete, not that their title became invalid. Preserve the draft in both cases. For the network case, allow another attempt without forcing an unrelated text edit.

## Make submission a complete workflow

Use a native `<form>` and a submit button. Listening to the form's `submit` event includes the ordinary Enter submission path from its text input, not only mouse clicks on Save. Enter in the multiline description still inserts a newline.

The workflow is:

```text
Native submit
  → reveal field errors and check validation
  → if invalid: skip saving and focus the first rejected field
  → otherwise: capture one payload and the selected simulated outcome
  → pause draft edits, Discard, and repeated saves during the request
  → await the save result
       ├── field rejection: keep draft, associate error, focus title
       ├── network failure: keep draft, show retry guidance, focus title
       └── success: report confirmed edits, reset to confirmed values
  → unlock controls and leave a useful focus destination
```

Capturing a **payload** means taking the data for this particular request before waiting. Do not reread an editable draft after `await` and accidentally treat newer text as the value that was sent.

This example uses a simple edit policy: title and description are temporarily readonly during the bounded simulated request. Save and Discard are disabled only while submitting. There is no cancellation, timeout, retry loop, or background race-management system.

A disabled-invalid Save button is not the only feedback. Here Save remains available when a rule fails so submission can reveal what needs correction. The handler still blocks invalid data. Duplicate prevention belongs in the submission operation as well as the button's presentation.

On success, the returned values become the new accepted record and the clean draft. On failure, neither happens. “Request finished” alone is not permission to reset the form.

## Connect the workflow to Signal Forms

Angular also has reactive forms and template-driven forms. They solve form work through different APIs; this article uses Signal Forms for the signal-owned draft, not a three-way tutorial.

The relevant pieces map directly to the questions already established:

| Mechanism                   | Signal Forms API in this editor            |
| --------------------------- | ------------------------------------------ |
| Writable draft data         | `linkedSignal<Task, TaskDraft>`            |
| Fields mirroring that data  | `form(draft, rules)` returns a field tree  |
| Control-to-draft connection | `[formField]` with `FormField`             |
| Schema checks               | `validateStandardSchema(path, taskSchema)` |
| Field errors and history    | `errors()`, `touched()`, `dirty()`         |
| Request lifecycle           | `submit(...)` and `submitting()`           |
| Restore data and history    | `reset(value)`                             |

A **field tree** follows the model's shape. `editorForm.title` identifies the title field; calling `editorForm.title()` accesses its state. Calling `editorForm()` accesses root state for the whole draft. Signals such as `touched()` and `submitting()` are read by calling them.

`FormField` connects a native control's value and interaction events to its field. It also owns native constraint attributes and applies readonly state. Do not add competing `[value]`, `(input)`, `[readonly]`, or literal `required` bindings to those same controls.

The Zod schema does not supply Angular's native constraint metadata. `metadata(path.title, REQUIRED, () => true)` supplies the field's required metadata so `FormField` exposes the native requirement. It adds no second validation rule; the Zod schema still performs the checks.

Save the complete editor in `task-editor.ts`:

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

### Initialization and draft lifetime

The required `task` input is not available during class initialization. The linked signal receives a source function; it does not eagerly call `task()` there. `form` receives that writable signal rather than an already-read input value. The first rendered field reads the draft after Angular supplies the input.

For the same task ID, the linked computation preserves the current draft when the page replaces its accepted record. That is the intentional same-ID lifetime from the ownership article. Success explicitly resets it to confirmed values; Discard explicitly reads the **current** accepted values. Neither relies on changing the input object to overwrite unfinished text.

This page has one task and no competing writer. Supporting concurrent external edits or switching tasks while a save runs would require another explicit policy; those are not hidden features of this example.

### Validation, submission errors, and readonly are different mechanisms

`submit` marks interactive fields touched and checks the form before running `action`. `onInvalid` handles that pre-action failure; it does not run for a rejection returned by the action.

`ignoreValidators: "none"` requires a known-valid result. Signal Forms otherwise ignores pending validators by default when no validator has failed. There are no asynchronous validation rules here, but the distinction prevents “not currently invalid” from being taught as “all checks have passed.”

Returning `{ kind, message, fieldTree }` from the action routes a submission error to the title field. Changing that title automatically clears the returned error. Schema errors instead recompute from the new value and can fail again. Changing only the description does not clear a title rejection; a retry with the identical rejected title remains blocked until the title changes.

The known network exception is handled outside `submit`. It becomes form-level status feedback, not a title validation error, so the unchanged draft can be retried. Unexpected exceptions are rethrown rather than mislabeled as connection problems. Signal Forms releases its submitting state in its own `finally` path.

Readonly is not just a visual lock. In Signal Forms, readonly fields do not contribute to their parent's aggregate validation and interaction state. Here it becomes active **after** the validation gate, while `action` is running. The captured payload is already fixed; the code does not read apparent aggregate validity during that temporary exclusion as a save result. Returned errors are shown after submitting ends and the fields become interactive again.

Signal Forms also prevents another concurrent submission of the same form or a descendant from running the action. The handler's early return additionally avoids replacing feedback or scheduling focus for a repeated native event. Disabled buttons alone would not protect the operation.

`reset(value)` clears touched/dirty history and sets the supplied draft values. In Angular 22.2.1 it does not explicitly erase every submission error: those clear when their targeted value changes. If Discard restores a different title, that change clears its rejection. If it restores the identical previously rejected title, the rejection remains visible through `showTitleErrors`, even though interaction history has reset. Resetting history should not pretend that a known rejection never happened.

The render callback in `finally` moves focus after the controls have unlocked and errors have rendered. It uses the first error's bound control, or the title for success/network feedback. On success, it resets to the confirmed values **after** moving focus: leaving the description can cause blur, so resetting first could immediately make that field touched again. This is an inline editor, not a dialog with a focus trap.

### The page remains the accepted-data owner

Save the consumer in `task-page.ts`:

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

The native select supplies a string. `setSaveOutcome` checks that external control value before storing it in the narrower union type. A type assertion would not validate the string.

The page receives confirmed edits, not each keystroke. Its immutable replacement preserves the current `id` and `done`. There is only one permanently rendered task here, so no collection search or deletion workflow is needed. The selector affects the next captured outcome; changing it during a request does not change the outcome already captured for that request.

Bootstrap it in `main.ts`:

```ts
import { bootstrapApplication } from "@angular/platform-browser";
import { TaskPage } from "./task-page";

bootstrapApplication(TaskPage);
```

Use `<task-page></task-page>` in the host document, replacing the earlier page host. Keep the styling article's CSS entry, `data-theme="dark"` on `<html>`, and `class="bg-page font-sans text-foreground"` on `<body>`. The six running-example files are `task.ts`, `task-schema.ts`, `demo-save.ts`, `task-editor.ts`, `task-page.ts`, and `main.ts`; `check-schema.ts` is an independent check, not another application component.

This example handles the native submit event explicitly so the awaited result and post-render focus path are visible in one method. Signal Forms also offers `FormRoot`: binding it to a native form supplies `novalidate`, prevents navigation, and calls `submit` using submission options configured on `form`. Choose one event owner, not both handlers for the same form.

## Make correction accessible

A message is useful only if the person can discover it, understand what to change, and reach the control needed to change it.

Each field keeps a visible native label. The label gives the control its name. Help and errors have separate IDs, and the field references **both** through `aria-describedby`:

```text
Title name:        label for="draft-title"
Title description: aria-describedby="title-help title-error"
Title state:       aria-invalid becomes true when a shown error exists
```

`aria-invalid` reports the failed state. It supplies neither the error message nor the control's name. Putting an error paragraph nearby also does not create an association unless the field references it.

The help/error elements remain present, with initially empty error text. Error changes use polite live feedback; the form-level busy/success/failure paragraph uses `role="status"`. Association makes information available with a field; a live region requests notification when text changes. Those are different jobs, not a promise of exact spoken output or announcement order.

A failed submit focuses the first rejected field after its message is rendered. Save failure retains the draft. Success and Discard leave focus at the unlocked title field so another edit can begin. Native Tab and Shift+Tab follow the DOM order; Space activates the buttons. There are no positive `tabindex` values or custom button keyboard handlers.

The interface is a narrow extension of the existing task editor: the same palette, readable muted help, visible `focus-visible` outlines, and comfortably sized controls. Buttons wrap, fields can shrink, and accepted titles/descriptions can break even when a value has no spaces. Check both themes at narrow widths and larger text; a class name is not evidence that overflow or contrast is correct.

### Walk the actual interaction

1. Open the page. Confirm the draft matches accepted data, touched/dirty are false, and no early error is shown.
2. Type a different title, then put the original back. Confirm accepted data never changed and dirty stays true until reset.
3. Blur an empty or whitespace-only title. Confirm its useful message, invalid state, and associated help/error text. Submit an invalid draft with unvisited fields too; no save action should run.
4. Leave the description blank and save a nonblank title containing spaces at its ends. Confirm the accepted title is trimmed, the description stays blank, and the draft is reset to those confirmed values with clean interaction history.
5. Choose Title rejection. Save, confirm the draft is kept and accepted data is unchanged, then change the title to clear its returned error. A retry without correcting that title should not run another save.
6. Choose Network failure. Confirm visible form-level retry guidance, no false title error, preserved draft, and an unchanged-value retry. Unexpected programming failures must not be presented as network failures.
7. During the simulated request, try typing, Discard, and repeated submission. Confirm one captured payload and one save operation, then editable controls and deliberate focus after completion.
8. Change both fields, then Discard. Confirm restoration from the current accepted record rather than the page's original sample values.
9. Repeat using Enter from the title, Tab/Shift+Tab, and Space on buttons. Try literal HTML-looking text and long unbroken values; they should remain text, not markup, and not widen the page.
10. At a real 320 CSS-pixel viewport, check dark mode with a 16px root font and light mode with a 32px root font. Scroll vertically to reach every control; no horizontal page overflow should be needed.

Strict compilation, browser interactions, and accessibility-tree inspection provide different evidence. Automated accessibility checks can help, but cannot establish useful speech behavior or that the whole workflow makes sense. See the [accessibility article's verification approach](/dump/blog/accessibility-in-practice/#inspect-more-than-the-screenshot) rather than treating a clean automated result as a certificate.

## Closing check

1. How can a field be invalid and untouched at the same time?
2. Why does Discard need a separate draft rather than direct edits to the accepted task?
3. Why can dirty remain true after restoring the original text?
4. What does `required` on a native text input miss about a title made only of spaces?
5. What does Standard Schema supply, and what still comes from Zod and Angular?
6. Why can a client-valid title fail to save, and why are field rejection and network failure handled differently?
7. What should reset after success, and what should remain after failure?
8. Why does a field reference the error ID alongside its help ID?

Check your reasoning:

- Validation describes the current value; touched describes interaction history. A rule can fail before any interaction.
- Typing changes only the draft. Discard can restore accepted values because they were never overwritten by those keystrokes.
- Dirty records an edit until explicitly cleared; it does not compare current values with accepted data.
- Native `required` rejects an empty string, not every nonblank-policy failure. The custom refinement checks meaningful text after trimming for comparison.
- Standard Schema defines the shared validation-result interface. Zod performs the checks; Angular connects their issues to form fields and manages interaction/submission state.
- The client is bypassable and may be stale; the receiver independently decides acceptance. A field rejection needs correction, while a network failure needs retry guidance without blaming a field.
- Success applies confirmed edits and resets draft values/history. Failure keeps accepted data unchanged and retains the person's draft with an actionable result.
- The label supplies the name, `aria-invalid` supplies state, and `aria-describedby` associates the help and error explanation. None replaces the others.

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
