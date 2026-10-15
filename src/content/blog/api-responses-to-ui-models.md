---
title: "One task, different models: from database rows to the interface"
description: "Follow one task from database rows through a JSON response, a checked frontend model, and the row and editor that display it, then send an edit back and check the server's reply."
pubDate: "2026-10-06"
updatedDate: "2026-10-15"
tags:
  - typescript
  - angular
  - api
  - frontend
---

The task row on screen reads "Assigned to Mina Patel". The database row behind it doesn't contain that name at all, just `assignee_id: 7`. The editor for the same task doesn't show the name either; it offers a choice to keep or clear the assignment. So which of these is the task?

It's tempting to write one `Task` interface and use it everywhere, from the database to the template. This article follows one task from the database to the screen and back again, shows the shape it takes at each step, and shows what goes wrong when one step's shape leaks into the next.

You'll need the [component composition article](/dump/blog/angular-component-composition/) for `input`, `signal`, `computed` and `linkedSignal`, the [forms article](/dump/blog/forms-and-validation/) for the idea of an edit draft kept apart from accepted data and for a first look at Zod schemas, and basic `async` and `await`.

The client code uses Angular 22.2.1, TypeScript 6.0.3 and Zod 4.6.5. The database and backend records are sketches for explanation, not code to run. The client talks to a fake server that lives in memory, so nothing goes over the network and nothing is saved.

## Contents

1. [Follow one task from the database to the screen](#follow-one-task-from-the-database-to-the-screen)
2. [What arrives: JSON text](#what-arrives-json-text)
3. [Two kinds of dates](#two-kinds-of-dates)
4. [Checking the response at runtime](#checking-the-response-at-runtime)
5. [`null`, missing, and empty mean different things](#null-missing-and-empty-mean-different-things)
6. [Mapping the response into the frontend `Task`](#mapping-the-response-into-the-frontend-task)
7. [Shaping the task for the row](#shaping-the-task-for-the-row)
8. [Sending an edit back](#sending-an-edit-back)
9. [The Angular components](#the-angular-components)

## Follow one task from the database to the screen

Start where the task is stored. A database keeps tasks in one table and users in another, so the task row holds only the assignee's ID:

```text
Task row:
  task_id:       41
  title_text:    "Review the CSS layout"
  completed:     false
  assignee_id:   7
  due_date:      2026-10-06                 (calendar date)
  created_at:    2026-10-06 00:30:00 UTC    (instant)

User row:
  user_id:       7
  display_name:  "Mina Patel"
```

Two things to notice. First, `assignee_id: 7` points at the user row whose `user_id` is 7. A stored pointer like that is called a **foreign key**: the task refers to the user instead of copying the user's name into every task. Second, the task has two different kinds of date. `due_date` is a day on the calendar: the task is due on October 6, wherever you are. `created_at` is an **instant**, one exact moment in time. The [dates section](#two-kinds-of-dates) shows why that difference matters.

Backend code reads those rows and builds something closer to how people talk about the task: "task 41, assigned to Mina Patel, due October 6".

```text
Task record in the backend:
  id:          41
  title:       "Review the CSS layout"
  completion:  "open"
  assignee:    { id: 7, name: "Mina Patel" }
  dueDate:     CalendarDate(2026, 10, 6)
  createdAt:   Instant(2026-10-06T00:30:00Z)
```

`CalendarDate(...)` and `Instant(...)` are notation for "a calendar day" and "a moment", not a particular library. The assignee is now a nested object with a name instead of a bare ID. A shape like this, built around the application's own ideas instead of the database's tables, is often called the **domain model**. "Domain" means the subject the application deals with, here tasks and the people assigned to them. It's usually plain data, and it's also where backend rules live, such as what has to be true before a task can be completed.

Building one shape from another like this is called **mapping**. A mapper can pick fields, rename them, combine them and convert their types. It doesn't have to copy every property. That's also why the database's column names don't have to reach the frontend: if someone renames `title_text`, only the backend's mapper changes, and the frontend keeps receiving `title`.

From the backend record, the task travels on:

```text
Database rows
        ↕  backend code maps rows to records
Backend domain model
        ↕  backend code builds the response
JSON response (a DTO)
        ↓  frontend checks it, then maps it
Frontend Task
        ↓  each component derives what it shows
Row view model and editor draft
```

An edit travels back up the same route: the editor's draft becomes an update request, the server applies it, and its reply is another JSON response that the frontend checks the same way. The rest of the article builds the frontend half of that route, and each of the names in the diagram gets explained at the step where it appears.

## What arrives: JSON text

Here's the response body the frontend receives when it asks for task 41:

```json
{
  "task_id": 41,
  "title": "Review the CSS layout",
  "status": "open",
  "assignee": {
    "user_id": 7,
    "display_name": "Mina Patel"
  },
  "due_on": "2026-10-06",
  "created_at": "2026-10-06T00:30:00Z"
}
```

This is text, a string of characters in the body of an HTTP response. It's shaped for this one request: snake_case field names, a status word instead of a boolean, and the assignee's name included so the frontend doesn't need a second request to look it up. Data shaped for one exchange between two programs is called a **data transfer object**, or **DTO**. The update request later in the article is a different DTO with different fields, because it does a different job.

The backend and the frontend agree on what each field means. In this example:

- `task_id`, `title`, `status`, `due_on` and `created_at` are always present.
- `status` is either `"open"` or `"completed"`.
- `due_on` is a calendar date, or `null` when the task has no due date.
- `created_at` is an instant with an explicit time reference, like the `Z` here.
- `assignee` can be an object, `null`, or missing entirely. Those three mean different things, covered in [their own section](#null-missing-and-empty-mean-different-things).

Turning values into text so they can be sent or stored is called **serialization**, and reading the text back into values is called **parsing**. JSON has objects, arrays, strings, numbers, booleans and `null`, and nothing else. It has no date type, so a date has to travel as a string, and nothing in the JSON says which strings are dates.

You can see that in JavaScript. Save this check as `wire-check.ts` and run it with `node wire-check.ts`. Node.js 22.18 and later can run TypeScript files directly by removing the types first.

```ts
const encoded = JSON.stringify({
  created_at: new Date("2026-10-06T00:30:00Z"),
  assignee_id: undefined,
});

const decoded: unknown = JSON.parse(encoded);

console.log(encoded);
// {"created_at":"2026-10-06T00:30:00.000Z"}
console.log(decoded);
// { created_at: '2026-10-06T00:30:00.000Z' }
console.log(JSON.stringify({ assignee_id: null }));
// {"assignee_id":null}
```

Notice three things in the output:

- `JSON.stringify` turned the `Date` into a string. It does that by calling the date's `toJSON()` method, which writes the instant in ISO format.
- `JSON.parse` gave back a plain object whose `created_at` is a string. Parsing never turns strings back into `Date` objects on its own.
- `assignee_id: undefined` disappeared. `undefined` isn't a JSON value, so `JSON.stringify` leaves out any object property that holds it. Inside an array it would write `null` instead. A property set to `null` survives, as the last line shows.

The `decoded: unknown` annotation matters too. `JSON.parse` returns `any`, a type that lets you read any property without complaint. **`unknown`** is the opposite: TypeScript lets the value exist, but it won't let you read `decoded.created_at` until your code has checked what the value actually is. That's the right type for anything that comes from outside your program.

## Two kinds of dates

The task is due on October 6. It isn't due at midnight in some particular city; it's due on that day for everyone. Its creation time is different: it happened at one exact moment, and people in different places write that moment down as different clock times.

Three terms describe instants:

- **UTC** is the reference clock that time zones are measured from. The `Z` at the end of `2026-10-06T00:30:00Z` means "this clock time is in UTC".
- A **time-zone offset** such as `+09:00` says the written clock time is nine hours ahead of UTC. So `2026-10-06T09:30:00+09:00` and `2026-10-06T00:30:00Z` are the same instant.
- A **time zone** such as `America/Los_Angeles` or `Asia/Tokyo` is a place's full set of rules, including daylight-saving changes, for turning an instant into a local clock time and calendar day. An offset only tells you the difference from UTC at one moment.

A JavaScript `Date` holds an instant and nothing else: a count of milliseconds since the start of 1970 in UTC. It can't hold "October 6" without picking a moment, and it doesn't remember which offset the original string used. That's where a classic due-date bug comes from. Save this as `dates-check.ts` and run it the same way:

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

For a date-only string like `"2026-10-06"`, JavaScript picks UTC midnight as the moment. Los Angeles is seven hours behind UTC in October, so at that moment it's still the evening of October 5 there, and the formatter prints Oct 5. Tokyo is ahead of UTC, so it prints Oct 6 and hides the bug. If you left out `timeZone`, the formatter would use whatever zone the computer is set to, so the bug would show up for some people and not for others.

So this example keeps the due date as its `YYYY-MM-DD` string in the frontend task, in the editor and in the update request. Only the creation time becomes a `Date`. When the row needs a readable due date, it formats the string in UTC, the same zone JavaScript used to parse it, so the day can't shift. You'll see that helper in the [row section](#shaping-the-task-for-the-row).

## Checking the response at runtime

Suppose the server starts sending `"status": "waiting"`, but the frontend only knows `"open"` and `"completed"`. A TypeScript interface won't catch that. Types exist only while your code compiles. The JavaScript that runs in the browser has no trace of them, so nothing compares the response against your interface.

Angular's `HttpClient` works the same way. When you write

```ts
this.http.get<TaskDto>("/api/tasks/41");
```

the `<TaskDto>` part is a generic type argument, and it's you telling TypeScript "trust me, this response is a `TaskDto`". Angular's documentation calls it a type assertion: `HttpClient` parses the JSON, but it doesn't check that the result matches the type. If the server sends `"waiting"`, your code receives `"waiting"`, typed as if that couldn't happen. The example in this article uses a fake server instead of `HttpClient`, so you can run it without RxJS or an HTTP setup, but it treats the fake server's reply exactly the way it would treat a reply from `HttpClient`: as `unknown` until it's checked.

To actually check a value, you need code that runs. A **schema** is an object that describes the shape you expect and can test a value against that description at runtime. This example uses [Zod](https://zod.dev/), the schema library from the forms article.

Create `task-models.ts` and start with the schema for the response:

```ts
import { z } from "zod";

const idSchema = z.number().int().positive().max(Number.MAX_SAFE_INTEGER);

export const nonBlankTextSchema = z.string().refine((value) => {
  return value.trim() !== "";
});

export const calendarDateSchema = z.iso.date().brand<"CalendarDate">();

export const taskResponseSchema = z.object({
  task_id: idSchema,
  title: nonBlankTextSchema,
  status: z.enum(["open", "completed"]),
  assignee: z
    .object({
      user_id: idSchema,
      display_name: nonBlankTextSchema,
    })
    .nullable()
    .optional(),
  due_on: calendarDateSchema.nullable(),
  created_at: z.iso.datetime({ offset: true }),
});

export type TaskDto = z.infer<typeof taskResponseSchema>;
export type CalendarDate = z.infer<typeof calendarDateSchema>;
```

What to notice:

- `idSchema` accepts only whole positive numbers up to `Number.MAX_SAFE_INTEGER`, which is 2^53 − 1. Above that, JavaScript numbers can't represent every integer exactly, so two different IDs could turn into the same number.
- `.refine` adds a condition of your own to a schema. Here the string must contain something other than spaces, so `"   "` fails.
- `z.enum(["open", "completed"])` accepts exactly those two strings. `"waiting"` fails.
- `.nullable()` allows `null`, and `.optional()` allows the property to be missing. `assignee` uses both, because both cases mean something.
- `z.iso.date()` accepts a real `YYYY-MM-DD` calendar date, so `2026-02-30` fails. `z.iso.datetime({ offset: true })` accepts a date and time that ends in `Z` or an offset like `+09:00`. It rejects one with no time reference at all, such as `2026-10-06T00:30:00`, which JavaScript would otherwise read as local time on whatever computer runs the code.
- `.brand<"CalendarDate">()` gives checked calendar strings their own TypeScript type, `CalendarDate`. At runtime the value is still a plain string, but TypeScript won't accept an ordinary string where a `CalendarDate` is expected. So the way to get one is to run a string through the schema.
- `z.infer` builds the TypeScript type from the schema. Because `TaskDto` comes from the same object that does the checking, the type and the checks can't drift apart.

If the server adds a field this frontend doesn't know about, `z.object` leaves it out of the checked result. So new fields don't break the frontend, and they don't sneak into it either.

## `null`, missing, and empty mean different things

The `assignee` field can arrive in three valid ways, plus one invalid one:

| In the response        | What it means in this example      | What the frontend keeps           |
| ---------------------- | ---------------------------------- | --------------------------------- |
| No `assignee` property | The server didn't say              | `{ kind: "omitted" }`             |
| `"assignee": null`     | The task has no assignee           | `{ kind: "unassigned" }`          |
| An assignee object     | This person is assigned            | `{ kind: "assigned", user: ... }` |
| `"assignee": ""`       | Not a valid response               | The schema rejects it             |

Say `dto` holds a response that passed the schema. The tempting way to turn its `assignee` into a label is one line:

```ts
const assigneeLabel = dto.assignee?.display_name ?? "Unassigned";
```

`?.`, called optional chaining, gives back `undefined` instead of throwing when `dto.assignee` is `null` or `undefined`. `??`, called nullish coalescing, then replaces `null` or `undefined` with `"Unassigned"`. The line never crashes, which is why it looks right. But it turns both `null` and a missing property into "Unassigned", and a missing `assignee` doesn't mean the task is unassigned. It means the server didn't include that information. A server might, for example, leave assignments out for people who aren't allowed to see them. Showing "Unassigned" then tells the person something that might be false.

So the frontend keeps all three cases, and the row shows "Assignment not included" when the field is missing. `?.` and `??` are useful operators, but they can't know what a missing value means. That has to be decided first, and then written down in the types.

Empty strings need the same care. An empty title is invalid, and the schema rejects it. But later, in the editor, an empty due-date field is how a person says "no due date". The same `""` means different things in different fields, so each field's meaning has to be decided on its own.

## Mapping the response into the frontend `Task`

Now give the frontend its own task type. Add the assignment type to `task-models.ts`, below the schema:

```ts
export type Assignment =
  | { kind: "omitted" }
  | { kind: "unassigned" }
  | { kind: "assigned"; user: { id: number; name: string } };
```

This is a **tagged union**: a type that's one of several object shapes, where each shape carries a `kind` property with its own fixed string. When code checks `assignment.kind === "assigned"`, TypeScript knows that inside that branch the object is the third shape, so `assignment.user` exists. Outside that branch, reading `user` is a compile error, which is exactly what stops you from reading a name from an unassigned task.

Next, add the task itself and the function that maps a checked response into it:

```ts
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
```

What to notice:

- `toTask` renames `task_id` to `id` and turns the status word into the boolean `done`. The rest of the frontend can ask `task.done` without knowing which words the server uses.
- The `if` chain checks for a missing property before `null`, so the three cases from the table stay apart.
- `dueDate` stays the checked calendar string. `createdAt` becomes a `Date` because `toTask` calls `new Date(...)`; JSON never does that for you.
- `Task` is the frontend's own **application model**: the shape the rest of the frontend works with. It isn't a copy of the backend's domain model. It holds only what this client needs.

Finally, add the one function every response goes through:

```ts
export type DecodedTask = { kind: "valid"; task: Task } | { kind: "invalid" };

export function decodeTask(incoming: unknown): DecodedTask {
  const checked = taskResponseSchema.safeParse(incoming);

  if (!checked.success) {
    return { kind: "invalid" };
  }

  return { kind: "valid", task: toTask(checked.data) };
}
```

`safeParse` returns a result object instead of throwing when the data fails validation. It's either `{ success: true, data }` with the checked, typed data, or `{ success: false, error }` with a list of what failed. `decodeTask` takes `unknown`, so you can hand it the raw parsed JSON, and it gives back another tagged union: a `Task`, or a plain "invalid". An invalid response doesn't become an empty title, "Unassigned" or today's date; the page shows that something went wrong. A real application would also log `checked.error` somewhere useful for debugging, without showing those details on the page.

For the response at the top of the article, `decodeTask` gives back this task:

```text
Frontend Task:
  id:          41
  title:       "Review the CSS layout"
  done:        false
  assignment:  { kind: "assigned", user: { id: 7, name: "Mina Patel" } }
  dueDate:     "2026-10-06"               (checked calendar string)
  createdAt:   Date for 2026-10-06T00:30:00Z
```

## Shaping the task for the row

The row on screen needs text: "Active", "Assigned to Mina Patel", "Due Oct 6, 2026". Data prepared for one piece of the screen like this is called a **view model**. It's derived from the `Task`, and it's only useful to the component that displays it.

You'll build `task-presentation.ts` over this section and the next one; each slice goes into the same file. Start with the due-date formatter promised in the dates section:

```ts
import type { CalendarDate, Task } from "./task-models";

export function formatCalendarDate(value: CalendarDate, locale: string): string {
  // A date-only string parses as UTC midnight, so format it in UTC too.
  const utcMidnight = new Date(value);

  return new Intl.DateTimeFormat(locale, {
    timeZone: "UTC",
    dateStyle: "medium",
  }).format(utcMidnight);
}
```

The `Date` here exists only for formatting. It's parsed and formatted in the same zone, so the calendar day comes back unchanged. The function has no time-zone parameter on purpose: a due date is the same day for everyone, so the viewer's zone mustn't change it.

Then add the row's view model and the function that derives it:

```ts
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
```

What to notice:

- Every label is decided here, so the row's template only displays strings. Changing the wording or the date format means changing this function, not the task data.
- The `kind` checks are the tagged union at work. In the last branch, TypeScript knows `task.assignment.user` exists.
- The labels use `en-US`, and the creation time is shown in Los Angeles with the zone named on screen, so the output is the same wherever you run it. A real product picks its own locale, and usually shows the viewer's own zone by leaving out `timeZone`.
- The creation instant can fall on different days for different viewers. 00:30 UTC on October 6 is 17:30 on October 5 in Los Angeles and 09:30 on October 6 in Tokyo. That's the same moment, not a moved deadline, so a `Date` is the right type for it.

## Sending an edit back

The editor needs yet another shape. The row needs finished labels; the editor needs the person's unfinished text, which can be invalid for a while, plus a choice about what to change. That's the **draft**, which the [forms article](/dump/blog/forms-and-validation/) keeps apart from the accepted task. Add it to `task-presentation.ts`:

```ts
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
```

`dueText` is a plain `string` because, while someone types, it can be `"2026-10-"`. An empty `dueText` means "no due date". `assigneeAction` is a choice instead of a person: this editor can keep the assignee or clear it, but it can't pick someone else.

The update request is a different DTO from the response. It doesn't carry the assignee's name or the creation time; it carries only the changes the server should make. In this example, a missing property and `null` mean different things again:

| In the update request                 | What it means in this example      |
| ------------------------------------- | ---------------------------------- |
| A property is missing                 | Leave that field alone             |
| `"assignee_id": null`                 | Clear the assignment               |
| `"due_on": null`                      | Clear the due date                 |
| A new title, status, or calendar date | Replace that field                 |
| `"title": null` or `"title": ""`      | Invalid; a task always has a title |

So these two requests do different things:

```json
{ "title": "Review the mapping" }
```

```json
{ "title": "Review the mapping", "assignee_id": null }
```

The first changes the title and leaves the assignment alone. The second also clears the assignment.

Now add the draft check and the function that builds the request. These imports go at the top of `task-presentation.ts`, next to the existing one:

```ts
import { z } from "zod";
import { calendarDateSchema, nonBlankTextSchema } from "./task-models";
```

And this goes at the bottom of the file:

```ts
export const draftSchema = z.object({
  title: nonBlankTextSchema,
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

What to notice:

- `draftSchema` checks the draft before anything is sent: the title isn't blank, and `dueText` is either empty or a real calendar date. Its result type, `CheckedDraft`, has `dueText: "" | CalendarDate`, so `toTaskUpdate` can't receive an unchecked date.
- `toTaskUpdate` lists exactly what gets sent: title, status and due date every time, and `assignee_id: null` only when the person chose Clear. For Keep, the property is never added, so it's missing from the JSON.
- An empty `dueText` becomes `due_on: null`, which clears the due date.
- The task ID isn't in the body; a real server would take it from the request URL. The creation time can't be edited, so it's never sent. Row labels and the row's open or closed details never come near the request.

This is where one shared shape everywhere would hurt. If the API exposed the database columns directly, renaming `title_text` would break every client. If components read `status === "completed"` all over the frontend, a change in the server's status words would touch all of them. If labels like "Due Oct 6, 2026" were stored in the task, changing the date format would mean changing the data. And if the editor sent its whole state, help text and screen flags would turn up as request fields.

### The server's reply is another response to check

The server might not store the request exactly as sent. It could trim the title or apply one of its own rules. So the page only replaces its task with what the server sends back, and that reply is JSON from outside the program again. It goes through `decodeTask`, exactly like the first response.

To try this without a backend, save a fake server in `fake-server.ts`:

```ts
import { taskResponseSchema } from "./task-models";
import type { UpdateTaskDto } from "./task-presentation";

const initialResponse = `{
  "task_id": 41,
  "title": "Review the CSS layout",
  "status": "open",
  "assignee": { "user_id": 7, "display_name": "Mina Patel" },
  "due_on": "2026-10-06",
  "created_at": "2026-10-06T00:30:00Z"
}`;

let responseText = initialResponse;

export function fetchTask(): unknown {
  return JSON.parse(responseText);
}

export async function sendUpdate(request: UpdateTaskDto): Promise<unknown> {
  await new Promise<void>((resolve) => {
    setTimeout(resolve, 300);
  });

  const current = taskResponseSchema.parse(fetchTask());
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

  return fetchTask();
}
```

What to notice:

- The fake server keeps the task as JSON text in memory, so reloading the page resets it.
- `sendUpdate` waits 300 milliseconds to imitate a network delay, applies the request field by field, and trims the title the way a real server might.
- It returns freshly parsed JSON typed as `unknown`, so the page has to check the reply before using it.
- It reads its own stored text with `parse`, which throws on invalid data instead of returning a result. That's fine for data the fake server wrote itself.

It skips everything a real server does, such as checking permissions, validating the request, or saving to a database.

## The Angular components

Three components display and edit the task: the row, the editor, and the page that holds both. They use `input`, `signal`, `computed` and `linkedSignal` as in the [composition article](/dump/blog/angular-component-composition/). The examples leave out styling classes, so they render with the browser's default styles.

### The row

Save the row in `task-row.ts`:

```ts
import { Component, computed, input, signal } from "@angular/core";
import type { Task } from "./task-models";
import { toTaskRow } from "./task-presentation";

@Component({
  selector: "task-row",
  template: `
    <article aria-labelledby="task-title">
      <h3 id="task-title">{{ row().title }}</h3>
      <p>{{ row().completionLabel }}</p>
      <p>{{ row().assigneeLabel }}</p>
      <p>{{ row().dueLabel }}</p>
      <button
        type="button"
        [attr.aria-expanded]="detailsOpen()"
        aria-controls="task-created"
        (click)="detailsOpen.set(!detailsOpen())"
      >
        Creation details
      </button>
      <p id="task-created" [hidden]="!detailsOpen()">{{ row().createdLabel }}</p>
    </article>
  `,
})
export class TaskRow {
  readonly task = input.required<Task>();
  readonly row = computed(() => toTaskRow(this.task()));
  readonly detailsOpen = signal(false);
}
```

What to notice:

- The row receives a checked `Task`, never the JSON, so it can't see the server's field names or status words.
- `row` is a computed signal over `toTaskRow`, so the labels recalculate whenever the page hands the row a new task.
- `detailsOpen` belongs only to this row. It isn't part of the `Task`, and it never goes into a request.

### The editor

The editor is deliberately simpler than the one in the forms article: it checks the draft when you press Save, and clears a field's error message when that field changes. It doesn't track which fields you've visited, and it doesn't use the Signal Forms API from that article.

The due date uses a plain text field. A date picker, `<input type="date">`, is friendlier, but it reports a half-typed date as an empty string, the same value as a cleared field. Telling those two apart takes extra code that's outside this article's topic. With a text field, the string in the field and the string in the draft are always the same.

The editor lives in two files: the class in `task-editor.ts`, and its template in `task-editor.html`, which the class points at with `templateUrl`. The template is long enough that a separate file is easier to read. The slices below show the parts that matter for this article; the full files follow them.

#### Binding the draft to the fields

The draft starts from the task and changes as you type:

```ts
  readonly task = input.required<Task>();
  readonly draft = linkedSignal(() => toTaskDraft(this.task()));

  setTitle(title: string) {
    this.draft.update((draft) => ({ ...draft, title }));
    this.titleError.set("");
    this.status.set("");
  }
```

Each field in the template reads its value from the draft and writes back to it:

```html
  <input
    #titleInput
    id="draft-title"
    name="title"
    type="text"
    required
    [value]="draft().title"
    [readonly]="busy()"
    aria-describedby="title-help title-error"
    [attr.aria-invalid]="titleError() !== ''"
    (input)="setTitle(titleInput.value)"
  />
```

What to notice:

- `draft` is a `linkedSignal`: a signal you can write to, which resets to `toTaskDraft(this.task())` whenever the page passes in a new task. Here the page replaces the task only after a confirmed save, which is exactly when the draft should reset to the confirmed values, so this simple form is enough. The composition article shows a stricter reset rule for pages where the task can change while someone is still editing.
- `[value]` shows the draft's title, and `(input)` sends every keystroke to `setTitle`, which updates the draft and clears the title's old error message. The row keeps showing the accepted task, because typing only ever writes to the draft.
- The checkbox, due-date field and assignment select follow the same pattern with `setDone`, `setDue` and `setAssignment`. A `<select>` always gives you a string, so `setAssignment` checks it's `"keep"` or `"clear"` before storing it.
- `aria-describedby` connects the field to its help and error text, and `aria-invalid` marks it while an error is showing. The [accessibility article](/dump/blog/accessibility-in-practice/) explains those attributes.

#### Checking the draft on Save

`save` starts by running the draft through `draftSchema`:

```ts
    const checked = draftSchema.safeParse(this.draft());

    this.titleError.set("");
    this.dueError.set("");

    if (!checked.success) {
      for (const issue of checked.error.issues) {
        if (issue.path[0] === "title") {
          this.titleError.set("Enter a task title, not just spaces.");
        }

        if (issue.path[0] === "dueText") {
          this.dueError.set("Write a real date as YYYY-MM-DD, or leave it blank.");
        }
      }

      this.status.set("Check the fields. Nothing was sent.");
      afterNextRender(
        () => {
          if (this.titleError() !== "") {
            titleInput.focus();

            return;
          }

          dueInput.focus();
        },
        { injector: this.injector },
      );

      return;
    }
```

What to notice:

- Nothing is sent until the draft passes. Each issue's `path` names the field that failed, so the editor can put a message next to the right input.
- `afterNextRender` runs its callback after Angular next updates the page, so focus moves to the first field with a problem once the error text is on screen. It normally finds Angular's injector by itself, but only while the component is being created, and `save` runs much later. That's why the component keeps its injector from `inject(Injector)` and passes it in.

#### Sending the draft to the page

When the draft passes, the editor hands it to the page:

```ts
  readonly submitDraft = input.required<(draft: CheckedDraft) => Promise<DecodedTask>>();
```

```ts
    this.busy.set(true);
    this.status.set("Saving…");

    try {
      const result = await this.submitDraft()(checked.data);

      if (result.kind === "invalid") {
        this.status.set("The server's reply failed its checks. The task wasn't updated; your draft is kept.");

        return;
      }

      this.status.set("Saved. The form now shows what the server confirmed.");
    } finally {
      this.busy.set(false);
      afterNextRender(
        () => {
          titleInput.focus();
        },
        { injector: this.injector },
      );
    }
```

What to notice:

- `submitDraft` is an input that holds a function. In `this.submitDraft()(checked.data)`, the first `()` reads the input, which gives back the function; the second `(checked.data)` calls it. The page decides what saving means, and the editor only calls it and reads the result.
- `checked.data` is a `CheckedDraft`, so the page can only ever receive a draft that passed the schema.
- An invalid reply leaves the draft alone, so nothing you typed is lost. A valid reply makes the page replace its task, and the `linkedSignal` resets the draft to the confirmed values.
- While `busy` is true, the text fields are `readonly` and the checkbox, select and buttons are disabled. An early `if (this.busy())` return at the top of `save` blocks a second save, and `finally` unlocks the form even if `submitDraft` throws. An unexpected error isn't reported as an invalid reply.

Discard copies the page's current task back into the draft, so after a successful save it restores the saved values, not the task the page started with. Pressing Enter in the title field submits the form, like any native form.

Here are the full editor files:

<details>
<summary>Full <code>task-editor.ts</code></summary>

```ts
import {
  Component,
  Injector,
  afterNextRender,
  inject,
  input,
  linkedSignal,
  signal,
} from "@angular/core";
import type { DecodedTask, Task } from "./task-models";
import { draftSchema, toTaskDraft } from "./task-presentation";
import type { CheckedDraft } from "./task-presentation";

@Component({
  selector: "task-editor",
  templateUrl: "./task-editor.html",
})
export class TaskEditor {
  readonly task = input.required<Task>();
  readonly submitDraft = input.required<(draft: CheckedDraft) => Promise<DecodedTask>>();
  readonly busy = signal(false);
  readonly titleError = signal("");
  readonly dueError = signal("");
  readonly status = signal("");
  private readonly injector = inject(Injector);

  readonly draft = linkedSignal(() => toTaskDraft(this.task()));

  setTitle(title: string) {
    this.draft.update((draft) => ({ ...draft, title }));
    this.titleError.set("");
    this.status.set("");
  }

  setDone(done: boolean) {
    this.draft.update((draft) => ({ ...draft, done }));
    this.status.set("");
  }

  setDue(dueText: string) {
    this.draft.update((draft) => ({ ...draft, dueText }));
    this.dueError.set("");
    this.status.set("");
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

    const checked = draftSchema.safeParse(this.draft());

    this.titleError.set("");
    this.dueError.set("");

    if (!checked.success) {
      for (const issue of checked.error.issues) {
        if (issue.path[0] === "title") {
          this.titleError.set("Enter a task title, not just spaces.");
        }

        if (issue.path[0] === "dueText") {
          this.dueError.set("Write a real date as YYYY-MM-DD, or leave it blank.");
        }
      }

      this.status.set("Check the fields. Nothing was sent.");
      afterNextRender(
        () => {
          if (this.titleError() !== "") {
            titleInput.focus();

            return;
          }

          dueInput.focus();
        },
        { injector: this.injector },
      );

      return;
    }

    this.busy.set(true);
    this.status.set("Saving…");

    try {
      const result = await this.submitDraft()(checked.data);

      if (result.kind === "invalid") {
        this.status.set("The server's reply failed its checks. The task wasn't updated; your draft is kept.");

        return;
      }

      this.status.set("Saved. The form now shows what the server confirmed.");
    } finally {
      this.busy.set(false);
      afterNextRender(
        () => {
          titleInput.focus();
        },
        { injector: this.injector },
      );
    }
  }

  discard(titleInput: HTMLInputElement) {
    this.draft.set(toTaskDraft(this.task()));
    this.titleError.set("");
    this.dueError.set("");
    this.status.set("Draft restored to the current task.");
    titleInput.focus();
  }
}
```

</details>

<details>
<summary>Full <code>task-editor.html</code></summary>

```html
<form novalidate (submit)="save($event, titleInput, dueInput)">
  <label for="draft-title">Task title (required)</label>
  <p id="title-help">Use more than spaces. The server trims spaces from the ends.</p>
  <input
    #titleInput
    id="draft-title"
    name="title"
    type="text"
    required
    [value]="draft().title"
    [readonly]="busy()"
    aria-describedby="title-help title-error"
    [attr.aria-invalid]="titleError() !== ''"
    (input)="setTitle(titleInput.value)"
  />
  <p id="title-error" aria-live="polite">{{ titleError() }}</p>

  <label>
    <input
      #doneInput
      type="checkbox"
      name="done"
      [checked]="draft().done"
      [disabled]="busy()"
      (change)="setDone(doneInput.checked)"
    />
    Completed
  </label>

  <label for="draft-due">Due date (optional)</label>
  <p id="due-help">Write it as YYYY-MM-DD, for example 2026-10-06. Leave it blank to clear it.</p>
  <input
    #dueInput
    id="draft-due"
    name="due"
    type="text"
    [value]="draft().dueText"
    [readonly]="busy()"
    aria-describedby="due-help due-error"
    [attr.aria-invalid]="dueError() !== ''"
    (input)="setDue(dueInput.value)"
  />
  <p id="due-error" aria-live="polite">{{ dueError() }}</p>

  <label for="draft-assignment">Assignment change</label>
  <p id="assignment-help">Keep leaves the assignee alone. Clear removes the assignee.</p>
  <select
    #assignmentInput
    id="draft-assignment"
    name="assignment"
    aria-describedby="assignment-help"
    [value]="draft().assigneeAction"
    [disabled]="busy()"
    (change)="setAssignment(assignmentInput.value)"
  >
    <option value="keep">Keep</option>
    <option value="clear">Clear</option>
  </select>

  <p>
    <button type="submit" [disabled]="busy()">Save task</button>
    <button type="button" [disabled]="busy()" (click)="discard(titleInput)">Discard edits</button>
  </p>
  <p role="status" aria-atomic="true">{{ status() }}</p>
</form>
```

</details>

### The page

Save the page in `task-page.ts`:

```ts
import { Component, signal } from "@angular/core";
import { fetchTask, sendUpdate } from "./fake-server";
import { decodeTask } from "./task-models";
import type { DecodedTask, Task } from "./task-models";
import { toTaskUpdate } from "./task-presentation";
import type { CheckedDraft } from "./task-presentation";
import { TaskEditor } from "./task-editor";
import { TaskRow } from "./task-row";

@Component({
  selector: "task-page",
  imports: [TaskRow, TaskEditor],
  template: `
    <main>
      <h1>One task, different models</h1>
      @if (task(); as accepted) {
        <section aria-labelledby="accepted-heading">
          <h2 id="accepted-heading">Accepted task</h2>
          <task-row [task]="accepted" />
        </section>
        <section aria-labelledby="editor-heading">
          <h2 id="editor-heading">Edit draft</h2>
          <task-editor [task]="accepted" [submitDraft]="submitDraft" />
        </section>
      } @else {
        <p role="alert">The server's first response failed its checks, so no task was loaded.</p>
      }
    </main>
  `,
})
export class TaskPage {
  readonly task = signal<Task | undefined>(undefined);

  constructor() {
    const result = decodeTask(fetchTask());

    if (result.kind === "valid") {
      this.task.set(result.task);
    }
  }

  readonly submitDraft = async (draft: CheckedDraft): Promise<DecodedTask> => {
    const request = toTaskUpdate(draft);
    const incoming = await sendUpdate(request);
    const result = decodeTask(incoming);

    if (result.kind === "valid") {
      this.task.set(result.task);
    }

    return result;
  };
}
```

What to notice:

- The page stores a checked `Task`, not the JSON and not the labels. It's the only place that replaces the accepted task.
- The first response goes through `decodeTask` in the constructor. If it's invalid, the page shows an error instead of a half-filled task.
- `submitDraft` builds the request, sends it, checks the reply with the same `decodeTask`, and replaces the task only when the reply is valid. It's an arrow function so that `this` still means the page when the editor calls it.
- There's one task and nothing else changing it, and the fake server never fails to answer. A real `HttpClient` call also needs handling for network errors.

### Save and run the client

Create an Angular 22.2.1 app with `ng new`, install Zod with `npm install zod@4.6.5`, and save these files in `src/` next to each other:

1. `task-models.ts`
2. `task-presentation.ts`
3. `fake-server.ts`
4. `task-row.ts`
5. `task-editor.ts` and `task-editor.html`
6. `task-page.ts`
7. `main.ts`, replacing the generated one with this:

```ts
import { bootstrapApplication } from "@angular/platform-browser";
import { TaskPage } from "./task-page";

bootstrapApplication(TaskPage);
```

In `src/index.html`, replace the generated `<app-root></app-root>` with `<task-page></task-page>`. Then run `npx ng serve` and open the address it prints.

The two checks from earlier, `wire-check.ts` and `dates-check.ts`, aren't part of the app, so keep them outside `src/`.

### Trace one edit

```text
Typing        → editor draft changes; the row still shows the accepted task
Save          → check the draft → build the update request
              → fake server applies it and replies with JSON
              → check the reply → map it to a frontend Task
              → page replaces the accepted Task
              → row recalculates its labels; editor resets to the confirmed values
```

Try a title with spaces at both ends, a different due date, Completed checked, and Clear assignment. Before you save, the row still describes the old task. After the save, it shows the trimmed title, the new day, "Completed" and "Unassigned", and the editor's assignment choice is back on Keep.

A few more things to try:

- Open Creation details, then edit and save. The details stay open, because that state belongs to the row, and it never appears in a request.
- Save with a blank title, or with `2026-02-30` as the due date. You get a message and focus on the field, and the row doesn't change.
- In `fake-server.ts`, change the last line of `sendUpdate` to `return { ...next, status: "waiting" };` and save. The editor says the reply failed its checks, the row keeps the old task, and your draft stays. The fake server did store the change, though, so a bad reply doesn't tell you the save failed; it tells you the page can't safely use what came back.
- In `initialResponse`, remove the `assignee` property, then set it to `null`. The row shows "Assignment not included" and then "Unassigned".

## Closing check

1. Why doesn't `http.get<TaskDto>(...)` protect you from `"status": "waiting"`?
2. Why does the frontend keep three assignment cases instead of writing `dto.assignee?.display_name ?? "Unassigned"`?
3. Why does the due date stay a string while `createdAt` becomes a `Date`?
4. Why does the page run `decodeTask` on the reply to an update, when it built the request itself?

Check your reasoning:

1. The type argument is an assertion that exists only at compile time. `HttpClient` parses the JSON without checking it, so only runtime code such as a Zod schema can reject `"waiting"`.
2. A missing `assignee` means the server didn't say, and `null` means nobody is assigned. The one-liner turns both into "Unassigned", which can be false.
3. A due date is a calendar day, the same for everyone. Turning it into a `Date` picks a moment, and formatting that moment in another zone can show the wrong day. The creation time really is one moment, so a `Date` fits it.
4. The reply is JSON from outside the program, and the server may have changed the data, for example by trimming the title. Only a checked reply should replace the accepted task.

So which shape is the task? Each of them, for the code that reads it: the database row for storage, the response DTO for the trip to the frontend, the frontend `Task` for the app's logic, and the row view model and draft for the screen. **The database tables don't have to become the API response, and the API response doesn't have to become the frontend's model.** When two steps happen to need the same fields, sharing a shape is fine. Keep the checks and the mapping at the point where data enters the frontend, and each shape can change without dragging the others along.

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
- [Node.js: running TypeScript files](https://nodejs.org/api/typescript.html)
