---
title: "The URL is part of your application's state"
description: "Keep a task list's search, filter, sort, and page in the URL so refresh, copied links, and the Back button all show the same view, using Angular Router input binding and signals."
pubDate: "2026-10-07T09:00:00Z"
updatedDate: "2026-10-15"
tags:
  - angular
  - typescript
audience:
  - frontend
---

You choose "Open" in a task list's status filter, and the address changes to `/tasks?status=open`. Then you press Back. The address goes back to `/tasks`, but the list still shows only open tasks, and the filter still says Open. A reload or a link sent to a colleague can go wrong in a similar way and show a different list from the one you were looking at.

This article builds a task list where the address and the screen can't disagree. The finished example is a fixed, in-memory list with a search box, a status filter, sorting, and pages. Opening `/tasks?status=open&q=report&sort=due&page=2` shows page 2 of the open tasks whose titles contain "report", sorted by due day. The task records are hard-coded and there's no backend, so the URL restores settings, not saved records. Loading data from a server, route guards, and deployment configuration are out of scope.

The code uses Angular 22.2.1 and TypeScript 6.0.3 with strict template checking. You'll need basic TypeScript and an Angular CLI project to run it; signals and the router APIs are explained where they first appear. Styling is left out of the examples. The [styling article's shared palette](/dump/blog/frontend-evolution-styling/#define-the-shared-palette-once) shows how to make the list match the rest of the series, the [accessibility article](/dump/blog/accessibility-in-practice/) covers the native controls and status messages used here, and the [forms article](/dump/blog/forms-and-validation/) explains why a form keeps a separate draft.

## Contents

1. [Why the old filter stays on screen](#why-the-old-filter-stays-on-screen)
2. [Read the parts of an address](#read-the-parts-of-an-address)
3. [Decide what belongs in the URL](#decide-what-belongs-in-the-url)
4. [Build the smallest working loop](#build-the-smallest-working-loop)
5. [Check every value the URL supplies](#check-every-value-the-url-supplies)
6. [Filter, sort, and paginate the tasks](#filter-sort-and-paginate-the-tasks)
7. [Keep a search draft next to the applied search](#keep-a-search-draft-next-to-the-applied-search)
8. [Build the full task list](#build-the-full-task-list)
9. [Make history describe meaningful steps](#make-history-describe-meaningful-steps)
10. [Check refresh, Back, and copied links](#check-refresh-back-and-copied-links)
11. [What fixed the three bugs](#what-fixed-the-three-bugs)

## Why the old filter stays on screen

A common first version keeps the filter in a component field (a property on the component class) and reads the address once, when the component starts:

```ts
export class TaskList {
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  status = "all";

  ngOnInit() {
    this.status = this.route.snapshot.queryParamMap.get("status") ?? "all";
  }

  changeStatus(status: string) {
    this.status = status;
    this.router.navigate(["/tasks"], { queryParams: { status } });
  }
}
```

`inject(ActivatedRoute)` asks Angular for an object describing the current route, and `inject(Router)` asks for the router, which changes the address. `ngOnInit` is a method Angular calls once after it creates the component. `get("status")` returns `null` when the address has no `status`, and `??` then falls back to `"all"`.

It looks right, and most of it works. Choosing Open sets the field and changes the address to `/tasks?status=open`. Opening that address in a new tab runs `ngOnInit`, which reads `status=open`, so the new tab shows open tasks too.

Back is where it breaks:

1. The browser changes the address back to `/tasks`.
2. Angular's router sees that `/tasks` and `/tasks?status=open` use the same route. Only the part after `?` differs, so it keeps the same `TaskList` object on screen instead of creating a new one.
3. `ngOnInit` runs once per component object, so it doesn't run again.
4. `snapshot` is a copy of the route's values taken at the moment you read it. It doesn't update later.
5. Nothing reads the address again, so `status` stays `"open"`.

Earlier versions of the same component often have two more bugs. If `changeStatus` only sets the field and never navigates, the address never contains the filter. A reload starts the application from scratch, so the field's old value is gone. A copied link copies only the address text, not the variables in your browser's memory, so the person who opens it sees all tasks.

All three bugs have the same cause: two places each claim to know the current filter. The address says one thing, and a component field says another. When they disagree, the screen is wrong. The fix is to remove the second place. The URL becomes the only place the filter lives, and the screen reads from it every time the URL changes, whether the change came from a select, a link, a reload, or Back:

```text
URL → check the values → controls and visible tasks
 ↑
user picks an option → ask the router to navigate to the new URL
```

The arrow only goes one way. Picking an option doesn't change the screen directly; it changes the URL, and the screen follows the URL.

## Read the parts of an address

Here's a full address split into its parts:

```text
https://example.test/tasks?status=open&q=report&sort=due&page=2#results
                    └─┬──┘└─────────────────┬─────────────────┘└──┬───┘
                     path                 query                fragment
```

- The **path**, `/tasks`, says which page of the application to show. A route such as `/tasks/41` could show one task.
- The **query** starts after `?`. It holds **query parameters**: `name=value` pairs separated by `&`. Here they choose which tasks the list shows. Every value arrives as text, so `page=2` gives you the string `"2"`, not the number 2.
- The **fragment** starts after `#`. Browsers use it to scroll to an element on the page, such as one with `id="results"`. The browser doesn't send the fragment to the server. This example doesn't use it.

The browser can split an address into these parts, but it doesn't know what they mean to your application. It doesn't know that "open" is a task status or that changing the filter should send you back to page 1. Your code decides that.

Characters such as `&`, `=`, `#`, and spaces have special meaning in an address, so values that contain them need **encoding**: replacing the character with a percent sign and its character code. Suppose the search text is `A&B`. If you glue it onto the address yourself, you get `?q=A&B`, and the browser reads two parameters: `q` with the value `A`, and an empty parameter named `B`. A URL builder writes `?q=A%26B` instead, where `%26` is the encoded `&`. When the application reads the address, it decodes `%26` back to `&`. Angular's router does this encoding and decoding for you as long as you pass values to it as values instead of building the address string yourself.

A shared address means "use these settings on the data available now". It doesn't freeze the records. In a real application, someone can complete or delete a task, and the same URL then shows different results.

## Decide what belongs in the URL

For each piece of state, ask three questions. Should copying the address keep this choice? Should a bookmark restore it next week? Should Back undo it? If the answers are yes, it belongs in the URL.

That works for choices the user has finished. Call those **applied** choices: the user picked an option in a select, followed a page link, or pressed Apply on the search. Text the user is still typing into the search box isn't applied yet.

| Kind of state                                            | Where it lives                                 | Why                                                          |
| -------------------------------------------------------- | ---------------------------------------------- | ------------------------------------------------------------ |
| Applied search, status filter, sort, page, selected task | The URL                                        | Opening the address should restore it                        |
| Search text still being typed, open menu, hover          | The component                                  | It's unfinished or temporary, not a view anyone would share  |
| Task records                                             | Application data, usually loaded from a server | A filter chooses which records to show; it doesn't hold them |
| Theme or preferred density                               | A preference store such as `localStorage`      | It should last across many addresses and visits              |

These are judgment calls, not a fixed list. An expanded section can belong in the URL if linking straight to it is useful.

URLs are also visible text. They end up in browser history, server logs, analytics tools, screenshots, and chat messages. Keep secrets, credentials, and sensitive searches out of them. Encoding only makes characters safe to transport; anyone can decode them.

## Build the smallest working loop

Start with only the status filter. You need four small files: the task data, the task-list component, a root component, and the bootstrap file.

Save `tasks.ts`. All records are made up and fixed. Due days are written as `YYYY-MM-DD` text, so comparing them as text also sorts them by date.

```ts
export interface Task {
  readonly id: number;
  readonly title: string;
  readonly done: boolean;
  readonly due: string;
}

export const tasks: readonly Task[] = [
  { id: 1, title: "Prepare report outline", done: false, due: "2026-10-01" },
  { id: 2, title: "Check report figures", done: false, due: "2026-10-02" },
  { id: 3, title: "Review report citations", done: false, due: "2026-10-03" },
  { id: 4, title: "Write report summary", done: false, due: "2026-10-04" },
  {
    id: 5,
    title:
      "Review the quarterly report with the accessibility and customer-support teams before approval",
    done: false,
    due: "2026-10-05",
  },
  { id: 6, title: "Proofread report appendix", done: false, due: "2026-10-06" },
  { id: 7, title: "Share report agenda", done: false, due: "2026-10-07" },
  { id: 8, title: "Archive previous report", done: true, due: "2026-09-30" },
  { id: 9, title: "Read the DOM article", done: false, due: "2026-10-08" },
  { id: 10, title: "Check A&B + café ✓ <strong>report</strong>", done: false, due: "2026-10-09" },
];
```

Task 10's title contains characters that need encoding and text that looks like HTML. It's there to check the search later.

### Let the router set component inputs

The component needs the `status` value from the URL. Angular's router can hand it over directly. Save `main.ts`:

```ts
import { bootstrapApplication } from "@angular/platform-browser";
import { provideRouter, withComponentInputBinding } from "@angular/router";
import type { Routes } from "@angular/router";
import { TaskApp } from "./task-app";
import { TaskList } from "./task-list";

const routes: Routes = [
  { path: "tasks", component: TaskList },
  { path: "", pathMatch: "full", redirectTo: "tasks" },
];

bootstrapApplication(TaskApp, {
  providers: [provideRouter(routes, withComponentInputBinding())],
});
```

What to notice:

- The route for `/tasks` shows `TaskList`. The empty path redirects to `/tasks`.
- `withComponentInputBinding()` tells the router to copy route values, including query parameters, into the routed component's inputs with matching names. With it, `?status=open` sets an input called `status` to `"open"`. When the address has no `status`, the router sets that input to `undefined`. It does this on every navigation, including Back, and including when it keeps the same component object.

Save `task-app.ts`. Its `<router-outlet />` is the spot where the router places the component for the current route:

```ts
import { Component } from "@angular/core";
import { RouterOutlet } from "@angular/router";

@Component({
  selector: "task-app",
  imports: [RouterOutlet],
  template: `<router-outlet />`,
})
export class TaskApp {}
```

In the CLI's generated `src/index.html`, replace the root element in `<body>` with `<task-app></task-app>`. Keep its `<base href="/">`; the router uses it to resolve addresses. An application served from a subfolder needs a matching base.

### Read the URL through signals

The component uses two signal functions. A **signal** is a value you read by calling it like a function, for example `this.status()`. When a template or a `computed` reads a signal, Angular remembers that, and when the signal changes, it recalculates the `computed` and updates the template.

`input()` creates a read-only signal that something outside the component sets. Here the router sets it:

```ts
readonly status = input<string>();
```

`computed()` creates a read-only signal whose value comes from other signals. It recalculates when they change:

```ts
readonly selectedStatus = computed(() => {
  const status = this.status();
  if (status === "open" || status === "completed") {
    return status;
  }
  return "all";
});
```

`selectedStatus` turns the raw text into one of three known values. A missing or unknown status shows all tasks.

### Save the minimal component

Save `task-list.ts`:

```ts
import { Component, computed, inject, input } from "@angular/core";
import { Router } from "@angular/router";
import { tasks } from "./tasks";
import type { Task } from "./tasks";

@Component({
  selector: "task-list",
  template: `
    <label for="task-status">Completion status</label>
    <select
      #statusSelect
      id="task-status"
      [value]="selectedStatus()"
      (change)="changeStatus(statusSelect.value)"
    >
      <option value="all">All</option>
      <option value="open">Open</option>
      <option value="completed">Completed</option>
    </select>

    <ul>
      @for (task of visibleTasks(); track task.id) {
        <li>{{ task.title }}</li>
      }
    </ul>
  `,
})
export class TaskList {
  private readonly router = inject(Router);
  readonly status = input<string>();

  readonly selectedStatus = computed(() => {
    const status = this.status();
    if (status === "open" || status === "completed") {
      return status;
    }
    return "all";
  });

  readonly visibleTasks = computed(() => {
    const status = this.selectedStatus();
    const visible: Task[] = [];
    for (const task of tasks) {
      const matches =
        status === "all" || (status === "open" && !task.done) || (status === "completed" && task.done);
      if (matches) {
        visible.push(task);
      }
    }
    return visible;
  });

  changeStatus(status: string) {
    this.router.navigate(["/tasks"], { queryParams: { status } });
  }
}
```

What to notice:

- `[value]="selectedStatus()"` sets the select from the URL. The select never decides its own value.
- `#statusSelect` names the select element, so `(change)` can pass its current value to `changeStatus`.
- `changeStatus` only asks the router to navigate. It doesn't set any field. `navigate` passes `status` as a value, so the router encodes it.
- `visibleTasks` loops over the fixed records and keeps the ones that match. `@for` repeats the `<li>` for each of them, and `track task.id` tells Angular how to tell tasks apart.

Follow one change through the loop:

1. You choose Open. `changeStatus("open")` asks the router to go to `/tasks?status=open`.
2. The router updates the address, adds a history entry, keeps the same `TaskList`, and sets its `status` input to `"open"`.
3. `selectedStatus` and `visibleTasks` recalculate, and Angular updates the select and the list.
4. You press Back. The browser restores `/tasks`. The router sets `status` to `undefined` on the same component, `selectedStatus` becomes `"all"`, and the list shows every task.
5. You press Forward to return to `/tasks?status=open`, then reload, or paste that address into a new tab. The application starts, the router matches `/tasks?status=open`, creates `TaskList`, and sets `status` to `"open"`.

That's the whole idea. The component never stores the filter itself, so there's nothing that can go stale.

It's also why the default lives in `selectedStatus` instead of `input("all")`. When the address drops `status`, the router sets the input to `undefined`, which replaces any starting value you gave it. A default has to be applied each time the value is read.

If you'd rather read the route yourself, `ActivatedRoute` also has `queryParamMap`, an RxJS Observable that sends a new value on every change. Input binding gives the same updates without subscription code.

## Check every value the URL supplies

The minimal loop trusts the URL more than it should. Anyone can edit an address, open a bookmark from an older version of the app, or paste a link with a typo. Treat query values the way you'd treat a server response: as outside input that needs checking.

One surprise is repeated keys. `?status=open&status=all` arrives as the array `["open", "all"]`, not a string. The minimal component declared `input<string>()`, but TypeScript can't check what the router puts there at runtime. Writing `this.status() as string` wouldn't help either: `as` only tells the compiler to stop complaining, and at runtime you'd still have an array. That's why the parser below types every raw value as `unknown`. TypeScript then refuses to let you use the value until the code has checked what it is.

### Choose the rules first

The policy is forgiving but visible:

- A missing value isn't an error. It quietly uses the default.
- A broken value uses the default for that one field only. The other fields keep their values, and a short message says what was changed.
- Keys the app doesn't know are ignored, and they disappear the next time the app builds a URL.

Here's what counts as broken for each key:

| Key      | Default when missing | Accepted values                                         | Broken values                                                                      |
| -------- | -------------------- | ------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| `status` | `all`                | `all`, `open`, `completed`                              | Blank or any other word                                                            |
| `q`      | Empty search         | One line of text; spaces at both ends are trimmed       | A line break inside the text                                                       |
| `sort`   | `due`                | `due`, `title`                                          | Blank or any other word                                                            |
| `page`   | `1`                  | A whole number from 1 up, written without leading zeros | Blank, `0`, negative, fraction, exponent such as `1e2`, leading zero, or too large |

Any key that appears more than once is broken too, even if the values agree.

"Too large" means beyond JavaScript's **safe integers**: the whole numbers a JavaScript number can store exactly. The largest is `Number.MAX_SAFE_INTEGER`, 9,007,199,254,740,991. Past it, nearby numbers can't be told apart, so `9007199254740992` and `9007199254740993` become the same number.

The search rule needs encoding to explain. `q=re%0Aport` decodes to "re", a line break, and "port": `%0A` is the encoded line feed, and `%0D` is the encoded carriage return. The search box is a single-line text input, and when code sets its value, the browser removes line breaks. So the box would show `report` while the filter searched for text with a line break in it. Rejecting line breaks keeps the box and the filter in agreement.

### Write the parser

Save `task-view.ts`. These four slices, in order, make up the file. First the types:

```ts
export type Status = "all" | "open" | "completed";
export type Sort = "due" | "title";

export interface ViewState {
  status: Status;
  q: string;
  sort: Sort;
  page: number;
}

export interface RawView {
  status: unknown;
  q: unknown;
  sort: unknown;
  page: unknown;
}

export interface InterpretedView {
  view: ViewState;
  issues: string[];
}
```

`ViewState` is what the list needs: four checked values. `RawView` is what the router supplies: four values of unknown type. `InterpretedView` pairs the checked view with the messages to show.

Next, a helper that accepts one string:

```ts
function singleText(value: unknown, key: string, issues: string[]): string | undefined {
  if (value === undefined) {
    return undefined;
  }

  if (typeof value !== "string") {
    issues.push(`${key}: use one text value; the default is shown.`);
    return undefined;
  }

  return value;
}
```

`singleText` tells a missing value apart from a broken one. A missing value returns `undefined` silently. Anything that isn't a string, such as the array from a repeated key, adds a message first.

Then the parser itself:

```ts
export function interpretView(raw: RawView): InterpretedView {
  const issues: string[] = [];
  const view: ViewState = { status: "all", q: "", sort: "due", page: 1 };
  const status = singleText(raw.status, "status", issues);
  const q = singleText(raw.q, "q", issues);
  const sort = singleText(raw.sort, "sort", issues);
  const page = singleText(raw.page, "page", issues);

  if (status !== undefined) {
    if (status === "all" || status === "open" || status === "completed") {
      view.status = status;
    } else {
      issues.push("status: choose all, open, or completed; all is shown.");
    }
  }

  if (q !== undefined) {
    const search = q.trim();
    if (/[\r\n]/.test(search)) {
      issues.push("q: use a single-line search; the empty search is shown.");
    } else {
      view.q = search;
    }
  }

  if (sort !== undefined) {
    if (sort === "due" || sort === "title") {
      view.sort = sort;
    } else {
      issues.push("sort: choose due or title; due is shown.");
    }
  }

  if (page !== undefined) {
    const number = Number(page);
    const positiveDecimal = /^[1-9]\d*$/.test(page);
    if (positiveDecimal && Number.isSafeInteger(number)) {
      view.page = number;
    } else {
      issues.push("page: use a positive safe whole number without leading zeros; page 1 is shown.");
    }
  }

  return { view, issues };
}
```

What to notice:

- `view` starts with every default, and each field only changes when its value passes.
- The search is trimmed first, so line breaks at the very ends are simply removed. `/[\r\n]/` then looks for a carriage return or line feed left inside the text.
- `/^[1-9]\d*$/` means "a digit from 1 to 9, then any number of digits, and nothing else". It rejects `0`, `01`, `-1`, `1.5`, and `1e2`.
- `Number(page)` alone isn't enough. `Number("")` is `0`, and `Number("1e2")` is `100`, so converting text to a number isn't the same as checking it. `Number.isSafeInteger` then rejects numbers that are too large.

Last, the function that turns a view back into query values:

```ts
export function viewQuery(view: ViewState): Record<string, string> {
  const query: Record<string, string> = {};

  if (view.status !== "all") {
    query["status"] = view.status;
  }
  if (view.q !== "") {
    query["q"] = view.q;
  }
  if (view.sort !== "due") {
    query["sort"] = view.sort;
  }
  if (view.page !== 1) {
    query["page"] = String(view.page);
  }

  return query;
}
```

`viewQuery` takes a checked `ViewState`, so it only ever writes the four supported keys. It leaves out defaults, which keeps addresses short: the default view is plain `/tasks`. It returns values for the router to encode. Pass the search text as it is. If you encode it yourself first, the router encodes it again, and `A%26B` becomes `A%2526B`.

The router can also change how an address is spelled without changing its values. On the first navigation, for example, it rewrites `page=%30` as `page=0` (`%30` is the encoded `0`) and `q=report+outline` as `q=report%20outline`, because a `+` in a query means a space. The parser sees the same decoded values either way.

The [API-responses article](/dump/blog/api-responses-to-ui-models/#checking-the-response-at-runtime) applies the same idea to JSON from a server: declaring a type doesn't check the data, so outside values go through a check before the app uses them.

## Filter, sort, and paginate the tasks

With a checked `ViewState`, picking the visible tasks is plain data work. Add this to `tasks.ts`:

```ts
import type { ViewState } from "./task-view";

export interface TaskResults {
  total: number;
  pageCount: number;
  visible: readonly Task[];
}

export function projectTasks(records: readonly Task[], view: ViewState): TaskResults {
  const matching: Task[] = [];
  const search = view.q.toLowerCase();

  for (const task of records) {
    const matchesStatus =
      view.status === "all" ||
      (view.status === "open" && !task.done) ||
      (view.status === "completed" && task.done);
    const matchesSearch = task.title.toLowerCase().includes(search);

    if (matchesStatus && matchesSearch) {
      matching.push(task);
    }
  }

  matching.sort((left, right) => {
    if (view.sort === "title") {
      return left.title.localeCompare(right.title, "en") || left.id - right.id;
    }
    return left.due.localeCompare(right.due) || left.id - right.id;
  });

  const pageSize = 3;
  const pageCount = Math.max(1, Math.ceil(matching.length / pageSize));
  if (view.page > pageCount) {
    return { total: matching.length, pageCount, visible: [] };
  }

  const start = (view.page - 1) * pageSize;
  return {
    total: matching.length,
    pageCount,
    visible: matching.slice(start, start + pageSize),
  };
}
```

Put the `import` line at the top of the file, above `Task`.

What to notice:

- The loop copies matching records into a new array, so sorting that array leaves the fixed `tasks` list alone.
- The search is a simple case-insensitive "title contains this text" check.
- `localeCompare` returns `0` when two titles or dates are equal. `||` then falls back to the ID difference, so ties always sort the same way.
- Pages are cut **after** filtering and sorting, three tasks per page.
- A valid page can still be past the last page, such as `page=500`. The function keeps that page and returns an empty list, so the screen can say so and offer a link back to page 1. It doesn't quietly show page 1 while the address says 500.

## Keep a search draft next to the applied search

The status select applies a choice as soon as you pick it. The search box can't work that way. If every keystroke navigated, typing "report" would create history entries for "r", "re", "rep", and so on. So the box holds a **draft**, and only Apply puts the search into the URL.

The draft needs to follow the applied search: when Back changes the URL's `q`, the box should show the restored search. But it shouldn't lose what you're typing when only the status or sort changes. `linkedSignal` handles both. In this snippet, `this.view()` is the checked `ViewState` that the full component builds from the URL in the next section:

```ts
readonly searchDraft = linkedSignal<string, string>({
  source: () => this.view().q,
  computation: (q, previous) => {
    if (previous?.source === q) {
      return previous.value;
    }
    return q;
  },
});
```

A `linkedSignal` is a signal you can write with `.set()`, like a variable, that also recalculates when its `source` changes. Here `source` is the applied search from the URL. Each time it recalculates, `computation` receives the new `q` and `previous`, which holds the old source in `previous.source` and the signal's current value in `previous.value`. The first time, there's no previous value, so `previous` is `undefined`. `previous?.source` handles that: `?.` reads `source` only when `previous` exists, and gives `undefined` otherwise instead of throwing an error.

The equality check matters because the computation can run even when `q` didn't change. `view()` recalculates whenever any query value changes, so picking a new status reruns the computation with the same `q`. In that case the function returns `previous.value`, which is your unfinished text.

Here's the policy as one walk-through, starting from `/tasks?q=report`:

1. The box shows "report".
2. You type until the box says "report fig", without pressing Apply. The URL and the list don't change.
3. You pick Open. The URL gets `status=open`, but `q` is still `report`, so the box keeps "report fig".
4. You press Apply. The URL's `q` becomes `report fig`, and the box keeps showing it.
5. You press Back. The URL's `q` is `report` again, so the box resets to "report".

The box keeps unfinished text while the applied search stays the same, and it resets to the applied search whenever that changes. Drafts aren't saved per history entry, so going Forward again doesn't bring back text you never applied.

## Build the full task list

The full component combines the pieces: the parser, the task results, and the search draft. It's long, so it's shown in slices here, with the complete file at the end of this section.

### Read the URL into one checked view

```ts
export class TaskList {
  readonly status = input<unknown>();
  readonly q = input<unknown>();
  readonly sort = input<unknown>();
  readonly page = input<unknown>();
  private readonly router = inject(Router);

  readonly interpreted = computed(() =>
    interpretView({
      status: this.status(),
      q: this.q(),
      sort: this.sort(),
      page: this.page(),
    }),
  );
  readonly view = computed(() => this.interpreted().view);
  readonly results = computed(() => projectTasks(tasks, this.view()));
```

What to notice:

- There's one input per query key, typed `unknown`, because the router can put anything there.
- `interpreted` runs the parser whenever any input changes. `view` and `results` follow from it.
- Nothing here can be written. The only way to change the view is to change the URL.

### Navigate instead of setting fields

```ts
  async applySearch(event: SubmitEvent) {
    event.preventDefault();
    const q = this.searchDraft().trim();
    const current = this.view();
    if (q === current.q) {
      this.searchDraft.set(q);
      return;
    }

    await this.navigate({ ...current, q, page: 1 });
  }

  async changeStatus(status: string) {
    if (status !== "all" && status !== "open" && status !== "completed") {
      throw new Error("Unknown task status from control.");
    }
    await this.navigate({ ...this.view(), status, page: 1 });
  }

  async changeSort(sort: string) {
    if (sort !== "due" && sort !== "title") {
      throw new Error("Unknown task sort from control.");
    }
    await this.navigate({ ...this.view(), sort, page: 1 });
  }

  pageQuery(page: number) {
    return viewQuery({ ...this.view(), page });
  }
```

What to notice:

- `{ ...current, q, page: 1 }` uses **object spread**. It copies every field of `current` into a new object, then sets `q` and `page`, overriding the copied values. The other fields stay as they were.
- Changing the search, status, or sort sends you to page 1, because page 2 of a different list isn't the same place. Page links change only the page.
- Every handler builds a full `ViewState` from the current checked view, never from the raw URL. That's how unknown keys and broken values drop out of the next address.
- Applying the same search that's already applied doesn't navigate. It only tidies the box, for example by removing spaces you added at the ends.
- A select's value is typed as `string`. The `if` checks narrow it to `Status` or `Sort` without an `as` assertion. Any other value means the template has a bug, so the handler throws.

All navigation goes through one method:

```ts
  readonly navigationMessage = signal("");

  async navigate(view: ViewState, replaceUrl = false) {
    this.navigationMessage.set("");
    const navigated = await this.router.navigate(["/tasks"], {
      queryParams: viewQuery(view),
      replaceUrl,
    });
    if (!navigated) {
      this.navigationMessage.set("The address didn't change, so the list is the same.");
    }
  }
}
```

`signal("")` creates a writable signal with a starting value; `.set()` changes it.

`router.navigate` returns a **Promise**: an object that delivers its result later. `await` pauses this method until the router finishes, while the page stays responsive. The result is `true` when navigation succeeded and `false` when it didn't happen, for example when the new address is the same as the current one. Nothing on screen changes until the router sets the new inputs, because the screen only ever reads the URL. `replaceUrl` is covered in the [history section](#make-history-describe-meaningful-steps).

### Bind the controls

The template's search form:

```html
<form (submit)="applySearch($event)">
  <label for="task-search">Search task titles</label>
  <input
    #searchInput
    id="task-search"
    name="q"
    type="text"
    [value]="searchDraft()"
    (input)="searchDraft.set(searchInput.value)"
  />
  <button type="submit">Apply search</button>
</form>
```

What to notice:

- Typing fires `input`, which copies the box's text into the draft. `[value]` puts the draft back into the box when it resets.
- Pressing Enter in the box submits the form, so Enter and the button both call `applySearch`.
- `event.preventDefault()` in `applySearch` stops the browser's own form submission, which would load a new page.

The two selects follow the same pattern as the minimal loop, now reading from `view()`:

```html
<label for="task-status">Completion status</label>
<select
  #statusSelect
  id="task-status"
  [value]="view().status"
  (change)="changeStatus(statusSelect.value)"
>
  <option value="all">All</option>
  <option value="open">Open</option>
  <option value="completed">Completed</option>
</select>

<label for="task-sort">Sort tasks</label>
<select
  #sortSelect
  id="task-sort"
  [value]="view().sort"
  (change)="changeSort(sortSelect.value)"
>
  <option value="due">Due day</option>
  <option value="title">Title</option>
</select>
```

### Show what the URL contained

```html
<section aria-labelledby="url-heading">
  <h2 id="url-heading">URL check</h2>
  <div role="status" aria-atomic="true">
    @for (issue of interpreted().issues; track issue) {
      <p>{{ issue }}</p>
    }
    <p>{{ navigationMessage() }}</p>
  </div>
  <button type="button" (click)="navigate(view(), true)">Clean up URL</button>
  <p>Replaces this history entry with the address of the view shown above.</p>
</section>
```

The parser's messages appear here. `role="status"` makes screen readers announce new text in the element without moving focus, and `aria-atomic="true"` makes them read the whole element instead of only the changed part. "Clean up URL" navigates to the address of the checked view, which drops broken values, unknown keys, and defaults. Its second argument, `true`, sets `replaceUrl`.

### Show the results and page links

```html
<section id="results" aria-labelledby="results-heading">
  <h2 id="results-heading">Results</h2>
  <p role="status" aria-atomic="true">
    Applied search: "{{ view().q }}". {{ results().total }} matching tasks. Page
    {{ view().page }} of {{ results().pageCount }}.
  </p>
  <ul>
    @for (task of results().visible; track task.id) {
      <li>
        <h3>{{ task.title }}</h3>
        @if (task.done) {
          <p>Completed</p>
        } @else {
          <p>Open</p>
        }
        <p>Due <time [attr.datetime]="task.due">{{ task.due }}</time></p>
      </li>
    }
  </ul>
  @if (results().total === 0) {
    <p>No matching tasks. Change the search or status, or show all tasks.</p>
    <a routerLink="/tasks">Show all tasks</a>
  } @else if (view().page > results().pageCount) {
    <p>This page is past the last page of results.</p>
  }
  <nav aria-label="Task result pages">
    @if (view().page > 1) {
      <a routerLink="/tasks" [queryParams]="pageQuery(1)">First page</a>
    }
    @if (view().page > 1 && view().page <= results().pageCount) {
      <a routerLink="/tasks" [queryParams]="pageQuery(view().page - 1)">Previous page</a>
    }
    @if (view().page < results().pageCount) {
      <a routerLink="/tasks" [queryParams]="pageQuery(view().page + 1)">Next page</a>
    }
  </nav>
</section>
<a routerLink="/tasks">Reset view</a>
```

What to notice:

- `{{ task.title }}` and `{{ view().q }}` insert text, not HTML. Task 10's `<strong>` shows up as literal angle brackets.
- An empty search result and a page past the end get different messages. A page past the end offers "First page", which navigates to page 1 instead of quietly showing it.
- `[attr.datetime]` sets the `<time>` element's `datetime` attribute, which gives the due day in a machine-readable form.
- The page links are real `<a>` elements with `RouterLink`, and `[queryParams]` supplies each link's query values from `pageQuery`. Angular fills in their `href` and handles clicks inside the app, so people can still copy them, open them in a new tab, or follow them with the Enter key. A clickable `<div>` can't do any of that.
- "Reset view" goes to plain `/tasks`. The router sets all four inputs to `undefined`, and the parser falls back to every default.

<details>
<summary>The complete <code>task-list.ts</code></summary>

```ts
import { Component, computed, inject, input, linkedSignal, signal } from "@angular/core";
import { Router, RouterLink } from "@angular/router";
import { interpretView, viewQuery } from "./task-view";
import type { ViewState } from "./task-view";
import { projectTasks, tasks } from "./tasks";

@Component({
  selector: "task-list",
  imports: [RouterLink],
  template: `
    <main>
      <h1>Task list</h1>

      <form (submit)="applySearch($event)">
        <label for="task-search">Search task titles</label>
        <input
          #searchInput
          id="task-search"
          name="q"
          type="text"
          [value]="searchDraft()"
          (input)="searchDraft.set(searchInput.value)"
        />
        <button type="submit">Apply search</button>
      </form>

      <label for="task-status">Completion status</label>
      <select
        #statusSelect
        id="task-status"
        [value]="view().status"
        (change)="changeStatus(statusSelect.value)"
      >
        <option value="all">All</option>
        <option value="open">Open</option>
        <option value="completed">Completed</option>
      </select>

      <label for="task-sort">Sort tasks</label>
      <select
        #sortSelect
        id="task-sort"
        [value]="view().sort"
        (change)="changeSort(sortSelect.value)"
      >
        <option value="due">Due day</option>
        <option value="title">Title</option>
      </select>

      <section aria-labelledby="url-heading">
        <h2 id="url-heading">URL check</h2>
        <div role="status" aria-atomic="true">
          @for (issue of interpreted().issues; track issue) {
            <p>{{ issue }}</p>
          }
          <p>{{ navigationMessage() }}</p>
        </div>
        <button type="button" (click)="navigate(view(), true)">Clean up URL</button>
        <p>Replaces this history entry with the address of the view shown above.</p>
      </section>

      <section id="results" aria-labelledby="results-heading">
        <h2 id="results-heading">Results</h2>
        <p role="status" aria-atomic="true">
          Applied search: "{{ view().q }}". {{ results().total }} matching tasks. Page
          {{ view().page }} of {{ results().pageCount }}.
        </p>
        <ul>
          @for (task of results().visible; track task.id) {
            <li>
              <h3>{{ task.title }}</h3>
              @if (task.done) {
                <p>Completed</p>
              } @else {
                <p>Open</p>
              }
              <p>Due <time [attr.datetime]="task.due">{{ task.due }}</time></p>
            </li>
          }
        </ul>
        @if (results().total === 0) {
          <p>No matching tasks. Change the search or status, or show all tasks.</p>
          <a routerLink="/tasks">Show all tasks</a>
        } @else if (view().page > results().pageCount) {
          <p>This page is past the last page of results.</p>
        }
        <nav aria-label="Task result pages">
          @if (view().page > 1) {
            <a routerLink="/tasks" [queryParams]="pageQuery(1)">First page</a>
          }
          @if (view().page > 1 && view().page <= results().pageCount) {
            <a routerLink="/tasks" [queryParams]="pageQuery(view().page - 1)">Previous page</a>
          }
          @if (view().page < results().pageCount) {
            <a routerLink="/tasks" [queryParams]="pageQuery(view().page + 1)">Next page</a>
          }
        </nav>
      </section>
      <a routerLink="/tasks">Reset view</a>
    </main>
  `,
})
export class TaskList {
  readonly status = input<unknown>();
  readonly q = input<unknown>();
  readonly sort = input<unknown>();
  readonly page = input<unknown>();
  private readonly router = inject(Router);

  readonly interpreted = computed(() =>
    interpretView({
      status: this.status(),
      q: this.q(),
      sort: this.sort(),
      page: this.page(),
    }),
  );
  readonly view = computed(() => this.interpreted().view);
  readonly results = computed(() => projectTasks(tasks, this.view()));
  readonly searchDraft = linkedSignal<string, string>({
    source: () => this.view().q,
    computation: (q, previous) => {
      if (previous?.source === q) {
        return previous.value;
      }
      return q;
    },
  });
  readonly navigationMessage = signal("");

  async applySearch(event: SubmitEvent) {
    event.preventDefault();
    const q = this.searchDraft().trim();
    const current = this.view();
    if (q === current.q) {
      this.searchDraft.set(q);
      return;
    }

    await this.navigate({ ...current, q, page: 1 });
  }

  async changeStatus(status: string) {
    if (status !== "all" && status !== "open" && status !== "completed") {
      throw new Error("Unknown task status from control.");
    }
    await this.navigate({ ...this.view(), status, page: 1 });
  }

  async changeSort(sort: string) {
    if (sort !== "due" && sort !== "title") {
      throw new Error("Unknown task sort from control.");
    }
    await this.navigate({ ...this.view(), sort, page: 1 });
  }

  pageQuery(page: number) {
    return viewQuery({ ...this.view(), page });
  }

  async navigate(view: ViewState, replaceUrl = false) {
    this.navigationMessage.set("");
    const navigated = await this.router.navigate(["/tasks"], {
      queryParams: viewQuery(view),
      replaceUrl,
    });
    if (!navigated) {
      this.navigationMessage.set("The address didn't change, so the list is the same.");
    }
  }
}
```

</details>

`main.ts` and `task-app.ts` stay as they were in the minimal loop.

## Make history describe meaningful steps

The browser keeps a list of **history entries** for each tab, one per address you've visited. Back and Forward move through that list. When you follow an ordinary link, the browser loads a new document from the server. A client-side router such as Angular's changes the address and the screen inside the already-loaded page instead, so internal links and select changes here don't download another HTML document. Opening a link in a new tab, or reloading, still loads the document.

A router can change history in two ways:

- **Push** adds a new entry. Use it for a choice the user would want Back to undo, such as a new filter.
- **Replace** overwrites the current entry. Use it when the address changes but the view doesn't, such as cleaning up a misspelled address.

`router.navigate` pushes by default. `replaceUrl: true` makes it replace. That's why "Clean up URL" passes `true`: it changes `?status=open&page=01&color=red` into `?status=open`, which shows the same list, so Back shouldn't stop at the misspelled version. "First page" is a normal link that pushes, because moving from page 500 to page 1 is a real change of view.

When you press Back or Forward, Angular's router notices the address change and runs the same steps as any other navigation, including setting the component's inputs. So the component needs no extra code for history.

The browser can also store a value with each history entry, called `history.state`, and routers use it for extra navigation details. It isn't part of the address. A copied link, a bookmark, or a new tab can't bring it back, so shareable choices such as filters shouldn't depend on it.

One more requirement sits outside the app. When you reload `/tasks?status=open`, the browser asks the server for `/tasks`, not for `/`. The server has to answer that request with the application's `index.html`, or the reload shows the server's 404 page before Angular even starts, while links inside the app keep working. The [Angular deployment guide](https://angular.dev/tools/cli/deployment#routed-apps-must-fall-back-to-indexhtml) shows how to configure common servers. `ng serve` already does this during development.

## Check refresh, Back, and copied links

An address is only shareable if every way of reaching it shows the same view. Run the app and check each one:

1. **Direct entry:** open `/tasks?status=open&q=report&sort=due&page=2`. The status says Open, the sort says Due day, the summary shows the applied search "report", and the list shows tasks 4, 5, and 6. Eight open tasks contain "report", so there are three pages.
2. **New tab and reload:** open the same address in a new tab, then reload. The same settings and tasks appear.
3. **Draft and Apply:** type in the search box without applying. The address, list, and history don't change. Press Enter: the address gets the trimmed search and loses `page`. Pressing Enter again with the same text doesn't add a history entry.
4. **Selects and page links:** from page 2, change the status or sort. The page resets to 1 and the applied search stays. Follow Next, Previous, and First page, and check that each link's address, shown when you hover or copy it, matches where it goes.
5. **Back and Forward:** step back through those changes. At every step, the address, the selects, the summary, and the list agree. The search box follows the draft policy from the walk-through.
6. **Removed values:** from a filtered address, follow Reset view. All four settings return to their defaults without a page reload.
7. **Broken values:** try `status=Open`, `status=open&status=all`, and pages `0`, `01`, `1e2`, and `9007199254740992`. Each broken field shows its default and a message, and the other fields keep their values. Try `q=re%0Aport`: the search box and the applied search in the summary are both empty. Then press Clean up URL. The address loses the broken values, the messages disappear, and Back skips the old version.
8. **Special characters:** apply the search `A&B + café ✓ <strong>report</strong>`. The address encodes it as one `q` value, and reloading or copying the link brings back the same text. Task 10 matches, and its title shows the literal `<strong>` tags.
9. **Empty and past-the-end pages:** search for `zzz` and open `page=500`. The first says no tasks match; the second says the page is past the end and offers First page.

## What fixed the three bugs

The opening bugs all came from a component field that held its own copy of the filter.

- **Back** now works because the router sets the component's inputs on every navigation, even when it keeps the same component. Nothing reads the address only once in `ngOnInit`, so nothing goes stale.
- **Reload** works because the filter lives in the address, and the address survives a reload. The router reads it again when the application starts.
- **Copied links** work because the address holds every applied choice, encoded by the router so it arrives intact.

The rest makes that loop safe to rely on: a parser that treats query values as outside input, a page reset when the filter changes, a search draft that never navigates on its own, and replace instead of push when only the spelling of the address changes.

## Closing check

1. Why does pressing Back leave a stale filter when the component reads `snapshot` in `ngOnInit`?
2. Why does the search box keep a draft instead of navigating on every keystroke?
3. Why is a missing `page` treated differently from `page=0`?
4. When should a navigation replace the history entry instead of pushing a new one?

Check your reasoning:

- The router keeps the same component object when only the query changes, so `ngOnInit` doesn't run again, and a snapshot is a copy that never updates.
- Unfinished text isn't an applied choice. Navigating per keystroke would fill history with partial searches, so Back would undo typing instead of view changes.
- A missing value is normal and uses the default quietly. `page=0` is a value someone supplied that breaks the rules, so it gets the default plus a message.
- Replace when the view stays the same and only the address changes, such as cleaning up a misspelled URL. Push when the user makes a choice that Back should undo.

## Sources and further reading

- [HTML Standard: single-line text inputs remove line breaks from their value](<https://html.spec.whatwg.org/multipage/input.html#text-(type=text)-state-and-search-state-(type=search)>)
- [MDN: URL parts and safe construction](https://developer.mozilla.org/en-US/docs/Web/API/URL)
- [MDN: fragments](https://developer.mozilla.org/en-US/docs/Web/URI/Reference/Fragment)
- [MDN: URLSearchParams and repeated keys](https://developer.mozilla.org/en-US/docs/Web/API/URLSearchParams)
- [MDN: session history, push, and replace](https://developer.mozilla.org/en-US/docs/Web/API/History_API/Working_with_the_History_API)
- [Angular: navigate with links and the Router](https://angular.dev/guide/routing/navigate-to-routes)
- [Angular: read route state and snapshots](https://angular.dev/guide/routing/read-route-state)
- [Angular: component input binding](https://angular.dev/api/router/withComponentInputBinding)
- [Angular: RouterLink](https://angular.dev/api/router/RouterLink)
- [Angular: navigation extras and replaceUrl](https://angular.dev/api/router/NavigationExtras)
- [Angular: Router.navigate results](https://angular.dev/api/router/Router)
- [Angular: serving the app for deep links](https://angular.dev/tools/cli/deployment#routed-apps-must-fall-back-to-indexhtml)
- [Angular: signals and computed values](https://angular.dev/guide/signals)
- [Angular: linkedSignal](https://angular.dev/guide/signals/linked-signal)
