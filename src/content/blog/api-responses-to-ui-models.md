---
title: "One task, different models: from database rows to the interface"
description: "Follow a task through storage, backend application data, JSON, frontend state, and a row/editor. Give validation, mapping, dates, and confirmed updates clear owners."
pubDate: "2026-10-06"
tags:
  - typescript
  - angular
  - api
  - frontend
---

A database stores an assignee's identifier. An API response includes that person's name. A task row displays “Assigned to Mina Patel,” while an editor offers “Keep assignment” or “Clear assignment.” These describe the same task, but they are not interchangeable data.

This article follows **one task** through five representations, then traces an edit back out. The task has an assignee, a completion state, a calendar due date, and a creation timestamp. The goal is to understand why each shape exists—not to prescribe a backend architecture or teach JSON in isolation.

The runnable client uses Angular 22.2.1, TypeScript 6.0.3, and Zod 4.6.5. It builds on [component ownership](/dump/blog/angular-component-composition/), [accepted data and form drafts](/dump/blog/forms-and-validation/), [accessible correction](/dump/blog/accessibility-in-practice/), and the [Tailwind 4 setup and shared palette](/dump/blog/frontend-evolution-styling/#define-the-shared-palette-once). The storage and backend records below are **illustrations**, not executable backend code. The client uses an explicitly labelled, in-memory response simulation; nothing is sent to a server or persisted.

## Contents

1. [Start with four small mysteries](#start-with-four-small-mysteries)
2. [Different models serve different owners](#different-models-serve-different-owners)
3. [Trace one task through the boundaries](#trace-one-task-through-the-boundaries)
4. [The wire carries representations, not application objects](#the-wire-carries-representations-not-application-objects)
5. [TypeScript describes expectations; validation checks values](#typescript-describes-expectations-validation-checks-values)
6. [Missing, null, and empty have contract meanings](#missing-null-and-empty-have-contract-meanings)
7. [Dates need meaning before conversion](#dates-need-meaning-before-conversion)
8. [Give mapping an owner, and follow edits back out](#give-mapping-an-owner-and-follow-edits-back-out)
9. [Connect the model to Angular without imposing machinery](#connect-the-model-to-angular-without-imposing-machinery)

## Start with four small mysteries

Consider the operations, before choosing any library:

- **Why should renaming a database column not necessarily change the API?** The backend can read the new column and still construct the response fields its clients already understand.
- **Why does a property declared as `Date` arrive as a string?** Sending JSON turns values into text. Parsing that text does not reconstruct a JavaScript `Date` automatically.
- **Why does the editor need different data from the row?** The row needs readable labels. The editor needs unfinished values and explicit choices about what to change.
- **Why can a typed response contain an unexpected value?** A TypeScript declaration describes an expectation during development. It does not inspect bytes returned by another process.

There are three separate jobs here: **check what arrived, choose the application's representation, and derive what the screen needs**. Giving them separate owners makes changes easier to trace.

## Different models serve different owners

A model is a representation chosen for some work. It can be an ordinary record; it does not have to be a class or a file of its own.

A **domain model** represents application concepts and rules: a task, its assignee, and what completing it means. Here, “domain” means the subject the application works with. An application model can cover only the concepts needed by a particular use case. Neither term requires a prescribed collection of classes.

A **data transfer object**, abbreviated **DTO**, is the data exchanged for an operation. A response that reads a task and a request that changes a task have different jobs, so they can have different fields.

A **view model** is data and state selected for a particular interface. A row might need formatted text and an expanded-details flag. An editor might need editable text and an assignment-change choice. These are not necessarily useful elsewhere in the application.

| Model                            | Represents                       | Shaped by                          |
| -------------------------------- | -------------------------------- | ---------------------------------- |
| Persistence model                | Stored data and relationships    | Columns, keys, and queries         |
| Backend domain/application model | Application concepts and rules   | Business meaning and use cases     |
| DTO                              | Data exchanged for one operation | The communication contract         |
| Frontend application model       | Concepts the client works with   | Client behavior and accepted state |
| UI view model                    | Data and state for one interface | Presentation and interaction       |

The frontend need not reproduce the backend's entire domain. This client only needs to read one task and edit its title, completion, due date, and whether to clear its assignment. It does not need a user-management model or every task rule enforced by a real server.

## Trace one task through the boundaries

First, imagine these stored rows. A calendar date identifies a day; an instant identifies a particular moment. These are explanatory records, not database queries or mapper configuration:

```text
Task row:
  task_id:       41
  title_text:    "Review the task contract"
  completed:     false
  assignee_id:   7
  due_date:      2026-10-06                 (calendar date)
  created_at:    2026-10-06 00:30:00 UTC    (instant)

User row:
  user_id:       7
  display_name:  "Mina Patel"
```

The task's `assignee_id` points to the user row's `user_id`. A **foreign key** is a stored reference from one record to another, normally enforced by the database. It represents the relationship without copying all the user's fields into every task row.

An **object-relational mapper**, or **ORM**, is software that maps relational database data to programming-language objects and back. It can help retrieve that relationship. Its resulting objects may still follow storage columns and relationships; an ORM does not automatically design the application's domain model.

The backend could then work with this application-shaped record:

```text
Task application record:
  id:          41
  title:       "Review the task contract"
  completion:  "open"
  assignee:    { id: 7, name: "Mina Patel" }
  dueDate:     CalendarDate(2026, 10, 6)
  createdAt:   Instant(2026-10-06T00:30:00Z)
```

`CalendarDate(...)` and `Instant(...)` are explanatory notation for meanings, not selected backend APIs. The assignee is now a nested application concept rather than just a foreign key. A domain model could also express rules for completing or assigning tasks; showing a record here does not imply those rules are absent or that they must be methods.

The complete route is:

```text
Database / persistence model
        ↕ ORM and application mapping
Backend application/domain model
        ↕ request/response mapping
DTOs — serialized across the wire
        ↕ validation and frontend mapping
Frontend application model
        ↓ screen-specific projection
UI view models: row and editor
```

**Mapping** constructs one representation from another. It can select fields, rename them, combine or split them, and convert types. It need not be a copy of every property.

The rest of the article makes the last three steps concrete: actual response JSON, a checked frontend task, and a row/editor consuming that task.

## The wire carries representations, not application objects

Here is the actual response body chosen for this example, **before any TypeScript transport type**:

```json
{
  "task_id": 41,
  "title": "Review the task contract",
  "status": "open",
  "assignee": {
    "user_id": 7,
    "display_name": "Mina Patel"
  },
  "due_on": "2026-10-06",
  "created_at": "2026-10-06T00:30:00Z"
}
```

The operation promises a task ID, title, completion status, due date, and creation instant. Assignee information may be omitted; when present it is either `null` or an object. We will preserve that distinction rather than guess.

**Serialization** converts values into a representation suitable for storage or communication—here, JSON text. **Parsing** reads that text into values again. “Across the wire” means exchanged between processes, commonly in an HTTP response body.

JSON represents objects, arrays, strings, numbers, booleans, and `null`. It has no date value, class identity, or methods. A backend serializer must choose how to represent an instant; this contract chooses a string with an explicit time reference.

In JavaScript, `JSON.stringify` uses a valid `Date` object's `toJSON()` method, which produces an ISO-formatted string. `JSON.parse` does not know that this particular string should become a `Date`. This independent runnable check, saved as `wire-check.ts`, shows both that and object-property omission. Its `unknown` type means the parsed value has no trusted shape yet; TypeScript requires checking before reading its properties:

```ts
const encoded = JSON.stringify({
  created_at: new Date("2026-10-06T00:30:00Z"),
  assignee_id: undefined,
});

const decoded: unknown = JSON.parse(encoded);

console.log(encoded);
// {"created_at":"2026-10-06T00:30:00.000Z"}
console.log(decoded);
// An ordinary object whose created_at value is a string, not a Date.
console.log(JSON.stringify({ assignee_id: null }));
// {"assignee_id":null}
```

`undefined` is not a JSON value. For an **object property**, `JSON.stringify` omits it. In an array, an `undefined` entry becomes `null` instead. Neither behavior tells us what a receiver should do with omission; that is a contract decision.

Reading and changing also need different representations. A read response includes an assignee's name and the creation instant. An update request need not send either. It should send deliberate changes, not a serialized copy of everything visible on the page.

## TypeScript describes expectations; validation checks values

Suppose a server returns `"status": "waiting"` when the client only understands `"open"` and `"completed"`. Declaring an interface does not reject that value at runtime. TypeScript types do not survive as automatic JSON checks in the running JavaScript.

Angular's `http.get<TaskDto>(...)` has the same limitation: **the generic type asserts an expected response type; `HttpClient` does not validate that the response matches it**. That expression alone is also not a complete request workflow. The runnable example below uses fixtures so it needs no RxJS knowledge or HTTP setup.

At an external boundary, use **`unknown`**: a TypeScript type that allows a value to arrive without granting permission to read it as a task. It makes code establish the value's shape before using its properties. It does not perform validation itself.

A schema supplies the checks. A **refinement** adds a condition to an already described kind of value—for example, requiring a string to contain more than spaces. This example uses Zod, as in the forms article.

The date checks have an explicit, narrow contract:

- IDs are positive safe integers; titles and names must contain non-whitespace text.
- `status` is exactly `open` or `completed`.
- Calendar dates use `YYYY-MM-DD`, are real dates including leap-day rules, and have years **2000–2099**.
- Creation timestamps have those same year bounds, hours/minutes/seconds, and either `Z` or a numeric offset. This contract allows no fractional seconds.

An **instant** is a particular moment on the timeline. **UTC** is the time reference represented by `Z`. A **time-zone offset** such as `+09:00` says that the written clock time is nine hours ahead of UTC. `2026-10-06T09:30:00+09:00` and `2026-10-06T00:30:00Z` describe the same instant. An offset is not a complete time zone with its historical and daylight-saving rules.

Save the response checks and application mapping together in `task-models.ts`:

```ts
import { z } from "zod";

const idSchema = z.number().int().positive().max(Number.MAX_SAFE_INTEGER);
export const titleSchema = z.string().refine(
  (value) => {
    return value.trim() !== "";
  },
  { error: "Enter a task title, not just spaces." },
);

export const calendarDateSchema = z.iso
  .date()
  .refine(
    (value) => {
      const year = Number(value.slice(0, 4));

      return year >= 2000 && year <= 2099;
    },
    { error: "Use a real calendar date in 2000–2099." },
  )
  .brand<"CalendarDate">();

const instantSchema = z.iso.datetime({ offset: true, precision: 0 }).refine(
  (value) => {
    const year = Number(value.slice(0, 4));

    return year >= 2000 && year <= 2099 && Number.isFinite(Date.parse(value));
  },
  { error: "Use an instant in 2000–2099 with seconds and Z or an offset." },
);

export const taskResponseSchema = z.object({
  task_id: idSchema,
  title: titleSchema,
  status: z.enum(["open", "completed"]),
  assignee: z
    .object({
      user_id: idSchema,
      display_name: z.string().refine((name) => {
        return name.trim() !== "";
      }),
    })
    .nullable()
    .optional(),
  due_on: calendarDateSchema.nullable(),
  created_at: instantSchema,
});

export type TaskDto = z.infer<typeof taskResponseSchema>;
export type CalendarDate = z.infer<typeof calendarDateSchema>;

export type Assignment =
  | { kind: "omitted" }
  | { kind: "unassigned" }
  | { kind: "assigned"; user: { id: number; name: string } };

export interface Task {
  id: number;
  title: string;
  done: boolean;
  assignment: Assignment;
  dueDate: CalendarDate | null;
  createdAt: Date;
}

export function toTask(dto: TaskDto): Task {
  let assignment: Assignment;

  if (dto.assignee === undefined) {
    assignment = { kind: "omitted" };
  } else if (dto.assignee === null) {
    assignment = { kind: "unassigned" };
  } else {
    assignment = {
      kind: "assigned",
      user: { id: dto.assignee.user_id, name: dto.assignee.display_name },
    };
  }

  return {
    id: dto.task_id,
    title: dto.title,
    done: dto.status === "completed",
    assignment,
    dueDate: dto.due_on,
    createdAt: new Date(dto.created_at),
  };
}

export type Confirmation = { kind: "confirmed"; task: Task } | { kind: "invalid-response" };

export function decodeTask(incoming: unknown): Confirmation {
  const checked = taskResponseSchema.safeParse(incoming);

  if (!checked.success) {
    return { kind: "invalid-response" };
  }

  return { kind: "confirmed", task: toTask(checked.data) };
}
```

`safeParse` returns either checked data or validation issues. `z.infer` obtains the TypeScript type from the schema, rather than maintaining a separate interface that might drift from it. `.nullable()` allows `null`; `.optional()` allows an absent property or `undefined` in JavaScript. JSON itself cannot transmit `undefined`.

The `CalendarDate` **brand** is a TypeScript marker distinguishing a checked calendar string from arbitrary text. It does not change the runtime string or validate a type assertion. Obtain it by parsing the schema, not by casting an unchecked string.

Zod's ISO checks inspect format and calendar validity before conversion. `Number.isFinite(Date.parse(...))` is an additional representability check, not permission to accept arbitrary date-shaped strings. The exact checks reject February 30 and a creation timestamp without a zone. The 2000–2099 bounds are a chosen demonstration contract, not the universal range of calendar dates.

**Validation checks the contract; mapping chooses the client shape.** Here mapping renames `task_id`, converts the status into a boolean, selects nested assignee fields, preserves the calendar string, and explicitly constructs a `Date` for the instant. Zod's ordinary object schema strips unrecognized keys; they do not become application fields automatically. This policy accepts additive response fields while checking the fields this client uses.

For the response shown earlier, the resulting frontend record has this shape. This is an illustration of the mapped values, not another file to run:

```text
Frontend Task:
  id:          41
  title:       "Review the task contract"
  done:        false
  assignment:  { kind: "assigned", user: { id: 7, name: "Mina Patel" } }
  dueDate:     "2026-10-06"               (checked calendar string)
  createdAt:   Date representing 2026-10-06T00:30:00Z
```

The client can now ask `task.done` without knowing the wire's status words, while still distinguishing omitted assignment information from no assignment. Its `createdAt` is a JavaScript `Date` because the mapper constructed one—not because JSON reconstructed it.

An invalid response returns a visible failure path. It does not become an empty title, “Unassigned,” or today's date. For this small interface, `Confirmation` does not expose schema issues to the person; a real application's diagnostics can retain those issues without displaying raw internals in the page.

## Missing, null, and empty have contract meanings

The assignment alternatives are chosen meanings, not a JavaScript trick:

| Read response          | Meaning in this contract           | Frontend representation           |
| ---------------------- | ---------------------------------- | --------------------------------- |
| No `assignee` property | Assignment information was omitted | `{ kind: "omitted" }`             |
| `"assignee": null`     | The task has no assignee           | `{ kind: "unassigned" }`          |
| Assignee object        | This person is assigned            | `{ kind: "assigned", user: ... }` |
| `"assignee": ""`       | Invalid response                   | Reject it                         |

“Omitted” does not mean “definitely unassigned.” The row will say “Assignment not included” rather than silently present incorrect knowledge.

The update contract is different:

| Update representation                 | Meaning in this contract        |
| ------------------------------------- | ------------------------------- |
| A property is omitted                 | Leave that field alone          |
| `"assignee_id": null`                 | Clear the assignment            |
| `"due_on": null`                      | Clear the due date              |
| A new title, status, or calendar date | Replace that field              |
| `"title": null` or `"title": ""`      | Invalid; title is not clearable |

This bounded editor offers only **keep or clear** for assignment, not selecting another user. Its update type will describe that subset. A larger assignment operation could accept a user ID, but this consumer does not need it.

For example, these actual JSON requests do different things:

```json
{ "title": "Review the mapping" }
```

```json
{ "title": "Review the mapping", "assignee_id": null }
```

The first changes the title without touching assignment. The second also clears assignment. Assigning `undefined` to an object property would cause `JSON.stringify` to omit it, as the earlier runnable check demonstrates; the mapper below simply does not add it for “keep.”

An editor's genuinely empty date string has yet another role: this editor deliberately interprets `""` as “clear the due date” and maps it to request `null`, after ruling out incomplete native input. An empty title is invalid. Empty is not a universal synonym for optional.

Optional chaining avoids some property-access failures. `??` chooses a replacement for `null` or `undefined`. Neither can decide whether omitted information means “unknown” or “none,” or whether an omitted request means “leave alone.” Those meanings must come from the contract first.

## Dates need meaning before conversion

The task is due **on October 6**, not at midnight in a particular city. Its creation timestamp, however, identifies one instant.

A JavaScript `Date` stores an instant as a number of milliseconds relative to the start of 1970 in UTC. It does not store a standalone calendar date or retain the original offset. Formatting that instant needs a **display time zone**: rules for turning the moment into the clock and calendar readings at a location. `America/Los_Angeles` and `Asia/Tokyo` are examples.

Here is the calendar bug, reproduced with an explicit zone instead of depending on the machine running the check. Save this independent example as `dates-check.ts`:

```ts
const naiveDue = new Date("2026-10-06");

console.log(
  new Intl.DateTimeFormat("en-US", {
    timeZone: "America/Los_Angeles",
    dateStyle: "medium",
  }).format(naiveDue),
);
// Oct 5, 2026 — wrong for a task due on October 6.

console.log(
  new Intl.DateTimeFormat("en-US", {
    timeZone: "Asia/Tokyo",
    dateStyle: "medium",
  }).format(naiveDue),
);
// Oct 6, 2026 — the bug can be hidden in another zone.
```

For this date-only format, JavaScript interprets the string as **UTC midnight**. Los Angeles is behind UTC at this time, so formatting that invented instant gives the previous day. Omitting `timeZone` would use the environment's local zone and make the bug depend on the person's environment.

Instead, keep the calendar string in application state, the editor, and the request. For localized presentation only, we can construct a temporary UTC value and format it **in UTC too**. That is a formatting bridge, not a new claim that the due date is an instant. The helper below accepts only our checked 2000–2099 calendar contract, avoiding the `Date.UTC` behavior that interprets years 0–99 as 1900–1999.

Save the projections and outgoing mapper in `task-presentation.ts`:

```ts
import { z } from "zod";
import { calendarDateSchema, titleSchema } from "./task-models";
import type { CalendarDate, Task } from "./task-models";

export function formatCalendarDate(value: CalendarDate, locale: string): string {
  const year = Number(value.slice(0, 4));
  const month = Number(value.slice(5, 7));
  const day = Number(value.slice(8, 10));
  const bridge = new Date(Date.UTC(year, month - 1, day));

  return new Intl.DateTimeFormat(locale, {
    timeZone: "UTC",
    dateStyle: "medium",
  }).format(bridge);
}

export interface TaskRowModel {
  title: string;
  completionLabel: string;
  assigneeLabel: string;
  dueLabel: string;
  createdLabel: string;
}

export function toTaskRow(task: Task): TaskRowModel {
  let completionLabel = "Active";
  let assigneeLabel: string;
  let dueLabel = "No due date";

  if (task.done) {
    completionLabel = "Completed";
  }

  if (task.assignment.kind === "omitted") {
    assigneeLabel = "Assignment not included";
  } else if (task.assignment.kind === "unassigned") {
    assigneeLabel = "Unassigned";
  } else {
    assigneeLabel = `Assigned to ${task.assignment.user.name}`;
  }

  if (task.dueDate !== null) {
    dueLabel = `Due ${formatCalendarDate(task.dueDate, "en-US")}`;
  }

  const created = new Intl.DateTimeFormat("en-US", {
    timeZone: "America/Los_Angeles",
    dateStyle: "medium",
    timeStyle: "short",
  }).format(task.createdAt);

  return {
    title: task.title,
    completionLabel,
    assigneeLabel,
    dueLabel,
    createdLabel: `Created ${created} (America/Los_Angeles)`,
  };
}

export interface TaskDraft {
  title: string;
  done: boolean;
  dueText: string;
  assigneeAction: "keep" | "clear";
}

export function toTaskDraft(task: Task): TaskDraft {
  let dueText = "";

  if (task.dueDate !== null) {
    dueText = task.dueDate;
  }

  return { title: task.title, done: task.done, dueText, assigneeAction: "keep" };
}

export const draftSchema = z.object({
  title: titleSchema,
  done: z.boolean(),
  dueText: z.union([z.literal(""), calendarDateSchema]),
  assigneeAction: z.enum(["keep", "clear"]),
});

export type CheckedDraft = z.infer<typeof draftSchema>;

export interface UpdateTaskDto {
  title?: string;
  status?: "open" | "completed";
  due_on?: CalendarDate | null;
  assignee_id?: null;
}

export function toTaskUpdate(draft: CheckedDraft): UpdateTaskDto {
  let status: "open" | "completed" = "open";
  let dueOn: CalendarDate | null = null;

  if (draft.done) {
    status = "completed";
  }

  if (draft.dueText !== "") {
    dueOn = draft.dueText;
  }

  const request: UpdateTaskDto = {
    title: draft.title,
    status,
    due_on: dueOn,
  };

  if (draft.assigneeAction === "clear") {
    request.assignee_id = null;
  }

  return request;
}
```

The row deliberately uses `en-US` labels and displays creation in Los Angeles, naming that zone on screen. A product would choose its own locale and display-zone policy. The due-date formatter has **no viewer-zone parameter** because changing the viewer's zone must not change this calendar day.

The creation instant may legitimately display on different days. This task was created at October 6, 00:30 UTC: October 5, 17:30 in Los Angeles, and October 6, 09:30 in Tokyo. That is the same moment, not a shifted deadline.

The editor reads the native date input's string `value`, not `valueAsDate`. A browser may display a localized date in the control, but a complete nonempty value is normalized to `YYYY-MM-DD`.

An empty `value` alone does **not** prove that the person cleared the date. For example, deleting only the month can leave a day and year on screen while `value` is `""`. The browser reports that incomplete or unparseable entry through `validity.badInput`: it cannot turn the current entry into a valid date string.

The editor therefore distinguishes three cases:

- A complete nonempty value can enter the draft and undergo the calendar schema checks.
- A genuinely empty control has `value === ""` and `badInput === false`; its draft string can deliberately map to request `null`.
- Incomplete input has `badInput === true`, even though `value` may be `""`. It needs correction, not a clear request.

On input, the editor leaves the draft's last usable date string unchanged when `badInput` is true. Copying that incomplete `""` into the draft could make Angular write it back into the control and erase the remaining date parts and bad-input state. On submit, it reads the control's current `value` and `badInput` together, and validates that date value alongside the other draft fields. An incomplete entry cannot submit the old draft date either. Reading the current value also handles clearing the remaining parts: the serialized value can stay `""` throughout that edit, without another input event. No extra synchronized flag is needed.

## Give mapping an owner, and follow edits back out

Each boundary has work of its own:

| Owner                                | Work                                                                       |
| ------------------------------------ | -------------------------------------------------------------------------- |
| Backend storage/application boundary | Translate stored rows and relationships into application concepts          |
| Backend API boundary                 | Validate real requests, enforce permissions/rules, construct response DTOs |
| Frontend API boundary                | Validate unknown responses and map them into usable frontend tasks         |
| Row/editor                           | Derive display data, hold a draft, construct deliberate edits              |
| Page                                 | Keep the confirmed frontend task used by the rest of the interface         |

Mixing these jobs creates concrete coupling. Exposing storage columns directly makes schema changes into public API changes. Reading `status === "completed"` throughout client logic spreads a transport convention. Storing localized labels as task data mixes display policy with meaning. Serializing the entire editor or row can send help text and expansion state as accidental request fields.

`toTaskUpdate` instead lists the data this operation sends. It includes title, completion, and due date every time, and includes assignment only for an explicit clear. The task ID would identify the resource in a real endpoint URL; the creation timestamp is read-only. Row labels and `detailsOpen` never enter the request.

Do not assume that a receiver stored the draft unchanged. It might normalize the title or apply a business rule. Only its confirmed response should replace accepted data, and that response is **another external value** needing the same validation and mapping as the first read.

To make that visible without introducing a backend, save this bounded simulation in `demo-exchange.ts`:

```ts
import { taskResponseSchema } from "./task-models";
import type { UpdateTaskDto } from "./task-presentation";

const initialResponse = `{
  "task_id": 41,
  "title": "Review the task contract",
  "status": "open",
  "assignee": { "user_id": 7, "display_name": "Mina Patel" },
  "due_on": "2026-10-06",
  "created_at": "2026-10-06T00:30:00Z"
}`;

let responseText = initialResponse;

export function loadDemoTask(): unknown {
  return JSON.parse(responseText);
}

export async function simulateUpdate(request: UpdateTaskDto): Promise<unknown> {
  // In-memory response simulation only. No HTTP, database, or backend implementation.
  await new Promise<void>((resolve) => {
    setTimeout(resolve, 300);
  });

  const current = taskResponseSchema.parse(loadDemoTask());
  const next = { ...current };

  if (request.title !== undefined) {
    next.title = request.title.trim();
  }

  if (request.status !== undefined) {
    next.status = request.status;
  }

  if (request.due_on !== undefined) {
    next.due_on = request.due_on;
  }

  if (request.assignee_id === null) {
    next.assignee = null;
  }

  responseText = JSON.stringify(next);

  return loadDemoTask();
}
```

This holds only JSON fixture text in memory and trims the returned title. Reloading resets it. It accepts the typed requests this demo constructs; it is **not** a real server's validation, authorization, persistence, or error-handling implementation. Its JSON string also demonstrates that the next response still needs interpretation.

The page will run `decodeTask` on that returned `unknown` before changing its accepted task. If validation fails, the editor keeps its draft and shows “Nothing accepted.” A malformed confirmation does not prove that a real server stored nothing; it means the client cannot safely accept that response. Reconciling such a real server operation is outside this fixture's scope.

## Connect the model to Angular without imposing machinery

A **signal** holds a value and notifies Angular when it changes. A **computed** signal derives a value from other signals rather than holding another independently writable copy. Calling a signal, such as `task()`, reads it.

The row receives an application `Task`, not raw JSON. Its computed projection supplies labels; its local `detailsOpen` signal belongs only to that row. The editor holds a separate `TaskDraft`. Its `linkedSignal` starts from the supplied task and deliberately preserves unfinished edits when the same task ID receives a replacement record.

Save these three consumers together in `task-page.ts`. They have real ownership boundaries, but need no class for every model or generic mapping framework:

```ts
import {
  Component,
  Injector,
  afterNextRender,
  computed,
  inject,
  input,
  linkedSignal,
  signal,
} from "@angular/core";
import { loadDemoTask, simulateUpdate } from "./demo-exchange";
import { decodeTask } from "./task-models";
import type { Confirmation, Task } from "./task-models";
import { draftSchema, toTaskDraft, toTaskRow, toTaskUpdate } from "./task-presentation";
import type { CheckedDraft, TaskDraft } from "./task-presentation";

@Component({
  selector: "task-row",
  host: { class: "block min-w-0" },
  template: `
    <article
      class="space-y-3 rounded-lg border border-line bg-surface p-4"
      aria-labelledby="task-title"
    >
      <h3 id="task-title" class="font-semibold [overflow-wrap:anywhere]">{{ row().title }}</h3>
      <p>{{ row().completionLabel }}</p>
      <p class="[overflow-wrap:anywhere]">{{ row().assigneeLabel }}</p>
      <p>{{ row().dueLabel }}</p>
      <button
        type="button"
        class="min-h-11 max-w-full rounded-lg border border-line px-3 py-2 [overflow-wrap:anywhere] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
        [attr.aria-expanded]="detailsOpen()"
        aria-controls="task-created"
        (click)="detailsOpen.set(!detailsOpen())"
      >
        Creation details
      </button>
      <p id="task-created" class="[overflow-wrap:anywhere]" [hidden]="!detailsOpen()">
        {{ row().createdLabel }}
      </p>
    </article>
  `,
})
export class TaskRow {
  readonly task = input.required<Task>();
  readonly row = computed(() => toTaskRow(this.task()));
  readonly detailsOpen = signal(false);
}

@Component({
  selector: "task-editor",
  host: { class: "block min-w-0" },
  template: `
    <form class="space-y-3" novalidate (submit)="save($event, titleInput, dueInput)">
      <label for="draft-title" class="block font-medium">Task title (required)</label>
      <p id="title-help" class="text-muted">
        Use more than whitespace. Confirmation trims the ends.
      </p>
      <input
        #titleInput
        id="draft-title"
        name="title"
        type="text"
        required
        class="block min-h-11 w-full min-w-0 rounded-lg border border-muted bg-surface px-3 py-2 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
        [value]="draft().title"
        [readonly]="busy()"
        aria-describedby="title-help title-error"
        [attr.aria-invalid]="titleError() !== ''"
        (input)="setTitle(titleInput.value)"
      />
      <p id="title-error" class="min-h-6 [overflow-wrap:anywhere] text-accent" aria-live="polite">
        {{ titleError() }}
      </p>

      <label class="flex min-h-11 items-start gap-3 py-2">
        <input
          #doneInput
          type="checkbox"
          name="done"
          class="mt-1 size-5 shrink-0 accent-accent focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
          [checked]="draft().done"
          [disabled]="busy()"
          (change)="setDone(doneInput.checked)"
        />
        <span>Completed</span>
      </label>

      <label for="draft-due" class="block font-medium">Due date (optional)</label>
      <p id="due-help" class="text-muted">A calendar day in 2000–2099. Leave blank to clear it.</p>
      <input
        #dueInput
        id="draft-due"
        name="due"
        type="date"
        min="2000-01-01"
        max="2099-12-31"
        class="block min-h-11 w-full min-w-0 max-w-full rounded-lg border border-muted bg-surface px-3 py-2 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
        [value]="draft().dueText"
        [readonly]="busy()"
        aria-describedby="due-help due-error"
        [attr.aria-invalid]="dueError() !== ''"
        (input)="setDue(dueInput)"
      />
      <p id="due-error" class="min-h-6 [overflow-wrap:anywhere] text-accent" aria-live="polite">
        {{ dueError() }}
      </p>

      <label for="draft-assignment" class="block font-medium">Assignment change</label>
      <p id="assignment-help" class="text-muted">
        Keep sends no assignment change; clear sends an explicit null.
      </p>
      <select
        #assignmentInput
        id="draft-assignment"
        name="assignment"
        class="block min-h-11 w-full min-w-0 max-w-full rounded-lg border border-muted bg-surface px-3 py-2 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
        aria-describedby="assignment-help"
        [value]="draft().assigneeAction"
        [disabled]="busy()"
        (change)="setAssignment(assignmentInput.value)"
      >
        <option value="keep">Keep</option>
        <option value="clear">Clear</option>
      </select>

      <div class="flex flex-wrap gap-2">
        <button
          type="submit"
          [disabled]="busy()"
          class="min-h-11 min-w-0 max-w-full rounded-lg bg-accent px-4 py-2 font-medium text-page [overflow-wrap:anywhere] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent disabled:opacity-60"
        >
          Save task
        </button>
        <button
          type="button"
          [disabled]="busy()"
          (click)="discard(titleInput, dueInput)"
          class="min-h-11 min-w-0 max-w-full rounded-lg border border-line px-4 py-2 [overflow-wrap:anywhere] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent disabled:opacity-60"
        >
          Discard edits
        </button>
      </div>
      <p class="min-h-6 [overflow-wrap:anywhere]" role="status" aria-atomic="true">
        {{ status() }}
      </p>
    </form>
  `,
})
export class TaskEditor {
  readonly task = input.required<Task>();
  readonly confirm = input.required<(draft: CheckedDraft) => Promise<Confirmation>>();
  readonly busy = signal(false);
  readonly titleError = signal("");
  readonly dueError = signal("");
  readonly status = signal("");
  readonly #injector = inject(Injector);

  readonly draft = linkedSignal<Task, TaskDraft>({
    source: this.task,
    computation: (task, previous) => {
      if (previous?.source.id === task.id) {
        return previous.value;
      }

      return toTaskDraft(task);
    },
  });

  setTitle(title: string) {
    this.draft.update((draft) => ({ ...draft, title }));
    this.titleError.set("");
    this.status.set("");
  }

  setDone(done: boolean) {
    this.draft.update((draft) => ({ ...draft, done }));
    this.status.set("");
  }

  setDue(inputElement: HTMLInputElement) {
    const incompleteDate = inputElement.validity.badInput;
    const dueText = inputElement.value;

    this.dueError.set("");
    this.status.set("");

    if (incompleteDate) {
      return;
    }

    this.draft.update((draft) => ({ ...draft, dueText }));
  }

  setAssignment(value: string) {
    if (value !== "keep" && value !== "clear") {
      throw new Error("Unknown assignment action.");
    }

    this.draft.update((draft) => ({ ...draft, assigneeAction: value }));
    this.status.set("");
  }

  async save(event: SubmitEvent, titleInput: HTMLInputElement, dueInput: HTMLInputElement) {
    event.preventDefault();

    if (this.busy()) {
      return;
    }

    const incompleteDate = dueInput.validity.badInput;
    const dueText = dueInput.value;
    const checked = draftSchema.safeParse({ ...this.draft(), dueText });

    this.titleError.set("");
    this.dueError.set("");

    if (!checked.success || incompleteDate) {
      if (!checked.success) {
        for (const issue of checked.error.issues) {
          if (issue.path[0] === "title") {
            this.titleError.set("Enter a task title, not just spaces.");
          }

          if (issue.path[0] === "dueText") {
            this.dueError.set("Choose a real date in 2000–2099, or leave it blank.");
          }
        }
      }

      if (incompleteDate) {
        this.dueError.set("Complete the date, or clear all its parts.");
      }

      this.status.set("Check the fields. Nothing accepted.");
      afterNextRender(
        () => {
          if (this.titleError() !== "") {
            titleInput.focus();

            return;
          }

          dueInput.focus();
        },
        { injector: this.#injector },
      );

      return;
    }

    this.busy.set(true);
    this.status.set("Waiting for the simulated confirmation…");

    try {
      const result = await this.confirm()(checked.data);

      if (result.kind === "invalid-response") {
        this.status.set("Invalid confirmation. Nothing accepted; your draft is kept.");

        return;
      }

      this.draft.set(toTaskDraft(result.task));
      this.status.set("Confirmed response accepted. The draft now matches it.");
    } finally {
      this.busy.set(false);
      afterNextRender(() => titleInput.focus(), { injector: this.#injector });
    }
  }

  discard(titleInput: HTMLInputElement, dueInput: HTMLInputElement) {
    const restored = toTaskDraft(this.task());

    this.draft.set(restored);
    dueInput.value = restored.dueText;
    this.titleError.set("");
    this.dueError.set("");
    this.status.set("Draft restored to the current accepted task.");
    titleInput.focus();
  }
}

@Component({
  selector: "task-page",
  imports: [TaskRow, TaskEditor],
  template: `
    <main class="mx-auto max-w-2xl space-y-6 px-4 py-8">
      <h1 class="text-3xl font-semibold [overflow-wrap:anywhere]">One task, different models</h1>
      <p class="text-muted">
        In-memory simulation: no HTTP, backend, or persistence. Reload resets it.
      </p>
      @if (task(); as accepted) {
        <section aria-labelledby="accepted-heading" class="space-y-3">
          <h2 id="accepted-heading" class="text-xl font-semibold">Accepted task</h2>
          <task-row [task]="accepted" />
        </section>
        <section aria-labelledby="editor-heading" class="space-y-3">
          <h2 id="editor-heading" class="text-xl font-semibold">Edit draft</h2>
          <task-editor [task]="accepted" [confirm]="confirm" />
        </section>
      } @else {
        <p role="alert">Invalid initial response. No task was loaded.</p>
      }
    </main>
  `,
})
export class TaskPage {
  readonly task = signal<Task | undefined>(undefined);

  constructor() {
    const result = decodeTask(loadDemoTask());

    if (result.kind === "confirmed") {
      this.task.set(result.task);
    }
  }

  readonly confirm = async (draft: CheckedDraft): Promise<Confirmation> => {
    const request = toTaskUpdate(draft);
    const incoming = await simulateUpdate(request);
    const result = decodeTask(incoming);

    if (result.kind === "confirmed") {
      this.task.set(result.task);
    }

    return result;
  };
}
```

The page stores a confirmed `Task`, not a response DTO or formatted labels. Its `confirm` function maps checked edits to a request and validates/maps the response before replacing that task. Passing this function as an input gives the editor the concrete operation it needs; it does not introduce an API-service hierarchy.

The editor's linked signal receives the input function without eagerly reading the required input during construction. Its first rendered read initializes the draft after Angular supplies the task. For this one task, success explicitly replaces the draft with confirmed values; Discard copies the **current accepted task**, not the original fixture. A replacement with the same ID does not implicitly discard unfinished edits.

The native form includes Enter submission from the title input. While waiting for the bounded simulation, text/date inputs are readonly and the checkbox, assignment select, and buttons are disabled. There is no competing writer, task switching, request-race policy, or network-failure simulation. Unexpected exceptions are not mislabeled as invalid responses; `finally` unlocks controls. A real HTTP workflow needs its own transport-failure handling.

The date input handler preserves incomplete native entry instead of treating its empty string as a draft value. Submit snapshots the date control's current value, rejects `badInput` through the existing date error and focus path, and validates the snapshot before mapping it. Discard explicitly writes the restored date string to the native control: if that string already equals the draft, Angular's unchanged value binding would otherwise leave the partial entry in place. This is a deliberate control reset, not a second state owner. Correcting the entry supplies a usable value again; successful confirmation resets the draft to confirmed values as before.

This is intentionally smaller than the forms article: it checks on submit and clears a field's old message when that field changes. It does not reproduce touched/dirty history or Signal Forms. Native labels name the controls; help/error IDs supply descriptions; `aria-invalid` reports a shown field failure. Visible status and post-render focus provide a correction/continuation path, without promising particular screen-reader speech.

### Save and run the client

In an Angular 22.2.1 application with Zod 4.6.5 and the styling article's Tailwind 4 integration, save these five files beside one another:

1. `task-models.ts`
2. `task-presentation.ts`
3. `demo-exchange.ts`
4. `task-page.ts`
5. `main.ts`, containing this bootstrap:

```ts
import { bootstrapApplication } from "@angular/platform-browser";
import { TaskPage } from "./task-page";

bootstrapApplication(TaskPage);
```

Replace the application's earlier bootstrap/host rather than bootstrap both examples. In its browser-parsed host document use `<task-page></task-page>`, not a self-closing host. Keep `data-theme="dark"` on `<html>`, the styling article's CSS entry, and `class="bg-page font-sans text-foreground"` on `<body>`. Angular templates can self-close the empty row/editor usages as shown.

Run that application's development command; in a standard Angular CLI workspace it is `npx ng serve`. This article does not supply a workspace, backend, or another Tailwind configuration. The two independent checks, `wire-check.ts` and `dates-check.ts`, do not belong in the app bootstrap. From the directory containing those two check files, with TypeScript 6.0.3 installed, run `npx tsc --ignoreConfig --strict --target ES2022 --module ES2022 --outDir checks wire-check.ts dates-check.ts`, then `node checks/wire-check.js` and `node checks/dates-check.js`. `--ignoreConfig` makes this an independent compilation rather than loading the Angular workspace's configuration.

### Trace one actual edit

```text
Input events → editor draft changes; accepted row stays unchanged
Submit       → validate draft → explicit update DTO
             → simulate a normalized JSON response
             → validate response → map to frontend Task
             → page replaces accepted Task
             → row recomputes labels; editor resets to confirmed values
```

Try a title with spaces at its ends, a different due day, completion checked, and Clear assignment. Before Save, the accepted row must still describe the old task. After confirmation, it must show the trimmed title, chosen calendar day, completion, and “Unassigned.” The draft should contain those confirmed values and return its assignment action to Keep.

Also check these boundaries:

- Open Creation details, edit, and save. Its expansion is row-only state and should survive replacement of the same task; it must never appear in a request.
- Save an empty or whitespace-only title using Enter. Check the visible message, associated error, unchanged accepted data, and title focus. Try a date outside 2000–2099 too; date failure should focus that field.
- Delete only the month of a filled date using Backspace, then Save. Check that no request runs, the accepted due date stays unchanged, the useful date error is associated with the control, and focus returns there. Correct the month and save; then try clearing **all** date parts and saving. Only the genuinely empty case should clear the accepted due date.
- Discard after a successful save and further edits, including an incomplete date. Restore the latest accepted values, not the original sample. Also try incomplete entry when the accepted task has no due date: Discard must restore a genuinely empty control, not leave `badInput` behind.
- Feed a missing, null, and assigned `assignee` through `decodeTask`. They must produce three different labels. Feed a bad status, February 30, or a zone-less instant: reject the response rather than invent data.
- At the response boundary, test a malformed confirmation. Keep accepted data unchanged, retain the draft, and show the failure. Client-valid input alone is not acceptance.
- Try long names/titles and literal text such as `<strong>Review</strong>`. Interpolation should display text, not create markup. Requests must contain only the explicit update fields, never display labels.
- Use Tab, Shift+Tab, Space, and Enter. Check focus visibility and useful focus after invalid submission, confirmation, and Discard.
- Check a true 320 CSS-pixel viewport in dark mode with a 16px root font and light mode with a 32px root font. Allow vertical scrolling; controls and long text must fit without horizontal page overflow.

Strict TypeScript and Angular template compilation, schema/mapping contract checks, browser interactions, and narrow/larger-text inspection test different things. They do not establish screen-reader speech, browser zoom behavior, real-device usability, a working backend, or WCAG conformance.

## Closing check

Can you trace this task through all five representations and explain why each exists?

- The stored foreign key represents a relationship; the backend application can work with a nested assignee concept.
- The response DTO promises data for reading. JSON carries strings and records, not the backend's behavior or reconstructed dates.
- Validation proves that incoming values fit the chosen contract. Mapping selects the frontend representation; neither replaces the other.
- The frontend retains omitted versus unassigned, a completion boolean, a calendar string, and an explicitly interpreted creation instant.
- The row derives localized labels. The editor holds unfinished values and an assignment-change choice. Neither shape is the accepted task or the read response.
- The outgoing mapper constructs only deliberate update fields. A confirmed response passes through the same validation/mapping boundary before changing accepted data.

**The database schema does not have to become the API contract, and the API contract does not have to become the frontend's internal model.** Shapes may coincide when their consumers need the same things. That is a choice—not an obligation, and not a reason to invent an abstraction for every arrow.

## Sources and further reading

- [Angular: making HTTP requests and the generic-type warning](https://angular.dev/guide/http/making-requests)
- [Angular: signals and computed values](https://angular.dev/guide/signals)
- [Angular: dependent state with linkedSignal](https://angular.dev/guide/signals/linked-signal)
- [Angular: DOM APIs and render callbacks](https://angular.dev/guide/components/dom-apis)
- [Zod: parsing, safeParse, and inferred types](https://zod.dev/basics)
- [Zod: schema API, ISO checks, refinements, and brands](https://zod.dev/api)
- [MDN: JSON.stringify and object-property omission](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/JSON/stringify)
- [MDN: JSON.parse](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/JSON/parse)
- [MDN: Date, instants, and date-only parsing](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Date)
- [MDN: Intl.DateTimeFormat](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Intl/DateTimeFormat)
- [HTML Standard: date inputs, values, and bad input](<https://html.spec.whatwg.org/multipage/input.html#date-state-(type=date)>)
- [MDN: ValidityState.badInput](https://developer.mozilla.org/en-US/docs/Web/API/ValidityState/badInput)
