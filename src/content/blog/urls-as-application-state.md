---
title: "The URL is part of your application's state"
description: "Choose which view settings belong in a URL, interpret external query values, and keep task controls, results, refresh, sharing, and browser history coherent."
pubDate: "2026-10-07"
tags:
  - angular
  - typescript
  - frontend
---

A task list can remember a filter while the page is open, yet forget it on refresh. A copied link can open the right application but show a different list. Back can change the address while leaving the controls untouched.

These failures have a common cause: the address describes one view, while another independently writable model describes the screen. The useful goal is not merely to put some values in the address bar. It is to make opening that address restore the committed view.

This article builds one small consumer: a **fixed, in-memory task list** with search, completion status, sorting, and pagination. Opening `/tasks?status=open&q=report&sort=due&page=2` selects open tasks whose titles contain “report,” sorts them by due day, and shows page 2. There is no backend, network request, editing, or persistence. The URL restores settings, not saved records.

The complete example uses Angular 22.2.1, TypeScript 6.0.3, and Tailwind CSS 4.3.3. It continues the task examples' [shared dark/light palette](/dump/blog/frontend-evolution-styling/#define-the-shared-palette-once), [native controls and accessible feedback](/dump/blog/accessibility-in-practice/), [separate form drafts](/dump/blog/forms-and-validation/), and [external-value validation](/dump/blog/api-responses-to-ui-models/). No RxJS code is needed in the consumer.

## Contents

1. [Resolve three small mysteries](#resolve-three-small-mysteries)
2. [Read the parts of an address](#read-the-parts-of-an-address)
3. [Choose an owner for each kind of state](#choose-an-owner-for-each-kind-of-state)
4. [Interpret external text deliberately](#interpret-external-text-deliberately)
5. [Let navigation commit the view](#let-navigation-commit-the-view)
6. [Make history describe meaningful steps](#make-history-describe-meaningful-steps)
7. [Connect the consumer to Angular Router](#connect-the-consumer-to-angular-router)
8. [Verify entry, reuse, and recovery](#verify-entry-reuse-and-recovery)

## Resolve three small mysteries

Start with what the browser and application actually do:

- **Why does refresh lose the filter?** A reload starts the application again. A variable in the old page's memory is not automatically available in the new one. The address remains available, but code must read and interpret it.
- **Why does a copied link show different results?** Copying an address copies its text, not the sender's variables, unfinished input, or task records. The receiving application needs enough information in that text to select the intended view.
- **Why does Back change only the address?** The browser moves to an earlier history entry. If controls and results still read a separate filter model that never responds to that entry, the screen keeps describing the newer view.

The repair is one direction of ownership:

```text
Address → interpret supported values → committed view → controls and results
                                           ↑
User commits a choice → navigate to its address

Typing unfinished search → local draft only
```

Rendering controls is still necessary. An address containing `status=open` does not itself select an HTML option. The application must interpret that text and bind the resulting value to the control. State ownership and updating the document are separate jobs.

## Read the parts of an address

Consider this illustrative full address:

```text
https://example.test/tasks?status=open&q=report&sort=due&page=2#results
                     └─┬─┘└──────────────────┬─────────────────┘└──┬───┘
                      path                query                fragment
```

- The **path**, `/tasks`, identifies the task-list resource or application route. A detail route such as `/tasks/41` could identify one selected task.
- The **query**, after `?`, contains named values separated by `&`. Here they select a view of the list. `page=2` arrives as text, not as a JavaScript number.
- The **fragment**, after `#`, identifies a location within the document in the ordinary browser model. For example, `#results` can target an element with `id="results"`. The fragment is not sent in the HTTP request. Some applications instead assign fragment text their own routing meaning; this example uses path-based routing and does not implement fragment navigation.

These are conventions with application-defined meaning. The browser can parse the address, but it does not know that “open” is a task status or that changing a filter should reset pagination.

**Serialization** writes values into a transportable representation. **Interpretation** checks that representation and assigns application meaning. Spaces, literal `+`, `&`, and Unicode characters need encoding so they remain part of one value rather than become separators. URL builders do that work; hand-built concatenation does not.

A shared address means **“use these settings against the data available now.”** It does not freeze the underlying records. In a real application, task changes, permissions, or deletion can change the results for the same URL. This demonstration uses fixed fixtures solely to make the result reproducible.

## Choose an owner for each kind of state

Ask three concrete questions: should copying this address preserve the choice, should bookmarking it restore the choice later, and should Back undo the choice?

| Kind of state                                             | Owner in a task application                     | Why                                                  |
| --------------------------------------------------------- | ----------------------------------------------- | ---------------------------------------------------- |
| Selected task, committed search, filter, sort, page       | URL, interpreted by the application             | Opening the address should restore the selection     |
| Unsubmitted search, unsaved editor text, open menu, hover | Local interaction/draft state                   | These are unfinished or temporary, not a shared view |
| Accepted task records                                     | Application data, usually confirmed by a server | A filter does not become the owner of records        |
| Theme or preferred density across sessions                | A deliberate preference store                   | It should usually outlive one URL/history step       |

These are decisions, not a universal list. An expanded section may belong in the URL if linking directly to it is useful. A sensitive search may need a different workflow rather than becoming shareable URL state.

**URLs are exposed text.** They can appear in browser history, server/proxy logs, analytics, screenshots, bookmarks, and copied messages. Do not put secrets, credentials, or sensitive unfinished drafts there. Encoding is not encryption.

The browser also associates a separate `history.state` value with a history entry. Routers can use it for navigation metadata. It is **not part of the copied URL**: a fresh tab or another person's session cannot reconstruct it from the address. Do not make shareable filters depend on it.

## Interpret external text deliberately

Someone can edit the address, open an old bookmark, or send repeated query keys. Treat route values as external input, even when an application usually builds its own links.

Choose the contract before writing a parser:

| Key      | Missing value | Supported supplied value                                                                                        | Malformed supplied value                                                  |
| -------- | ------------- | --------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| `status` | `all`         | `all`, `open`, `completed`                                                                                      | Blank or another word                                                     |
| `q`      | Empty search  | One string, trimmed at both ends, with no remaining carriage return (CR) or line feed (LF); blank becomes empty | A non-string, repeated key, or CR/LF remaining after trimming             |
| `sort`   | `due`         | `due`, `title`                                                                                                  | Blank or another word                                                     |
| `page`   | `1`           | Positive decimal integer, no leading zeros, within JavaScript's safe integer range                              | Blank, `0`, negative, fraction, exponent, leading zero, or unsafe integer |

A **safe integer** is a whole number JavaScript can represent exactly; the positive limit is `Number.MAX_SAFE_INTEGER`. Every repeated supported key is malformed, even if the repeated values agree. Angular's router can supply repeated query values as a string array. A TypeScript assertion would not turn that array into a checked string.

The policy here is forgiving but visible: **use the default only for the malformed field, retain other supported settings, and explain the correction.** Missing values are normal and produce no warning. Unknown query keys do not affect this consumer; its next generated URL drops them. The consumer does not automatically correct/drop parameter values or call `viewQuery` on entry. Angular Router can still normalize encoding and parameter order during initial navigation: `report+outline` can become `report%20outline`, `page=%30` can become `page=0`, and interleaved repeated keys can be grouped together. This preserves the parsed values, not the address's exact original spelling. There is no consumer-driven automatic correction loop.

Save `task-view.ts`:

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

The search control below is a native single-line `<input type="text">`. When code assigns its value, the browser removes carriage returns (`\r`, CR) and line feeds (`\n`, LF) without firing a user input event. If committed search still contained `re\nport`, the field would display `report` while the draft and filtering used different text. Trim outer whitespace first, then reject any remaining CR/LF before binding the search. Blank text and line breaks only at the ends still follow the ordinary trimming policy.

`singleText` distinguishes absence from an invalid supplied type. The page regular expression checks decimal spelling; `Number.isSafeInteger` checks representability. `Number(page)` alone would also accept values such as an empty string or exponent notation, so conversion is not validation.

`viewQuery` constructs **only the four supported settings**, intentionally omitting defaults. It accepts application-owned `ViewState`, not unknown route data. It returns values for the router to encode, not a manually concatenated URL. Pass the literal search text; pre-encoding it would encode it twice.

This is the same boundary described in the [API-model article](/dump/blog/api-responses-to-ui-models/#typescript-describes-expectations-validation-checks-values): external representation → validation → application meaning → screen projection. Query text is not JSON, but neither becomes trusted application data merely because a type was declared.

## Let navigation commit the view

The interaction should have one clear sequence:

```text
Apply search / choose status / choose sort / follow a page link
  → construct the intended supported settings
  → ask the router to navigate
  → interpret the route's new values
  → derive controls and visible tasks from that interpretation
```

Do not first write a second filter model and then try to keep it synchronized with the address through opposing effects. There are several writers to the route: controls, links, direct entry, Back, and Forward. The interpreted URL owns the committed view for all of them.

The search field needs a separate **unfinished draft**. Typing changes that draft without navigating. Apply, including native Enter submission, trims and commits it. Changing status, sort, or page uses the **committed** search, not the unfinished field. The example preserves unfinished text while committed `q` remains the same; when committed `q` changes, including through Back or removal, it resets the draft to that new search. Drafts are not stored per history entry.

Changing search, status, or sort resets page to 1. Page 2 of a different filtered/sorted collection is usually not the same place. Page links change only page. Build the full intended supported query instead of blindly merging raw parameters: preserve committed search/status/sort deliberately, but do not retain a stale page or an unsupported key.

### Derive results without altering the records

Save `tasks.ts`. All records below are synthetic and fixed. ISO-shaped calendar strings sort by day here; no time-zone conversion is involved.

```ts
import type { ViewState } from "./task-view";

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

The loop selects records into a new array; sorting that array does not mutate the fixture. Title matching is a simple case-insensitive substring check, not fuzzy or accent-insensitive search. The ID breaks sorting ties. Results are paginated **after** filtering and sorting.

A valid page number can still be beyond the last page. The projection leaves that page selected and returns an empty list with a first-page recovery link. It does not secretly show page 1 while the address says page 500. Checking the page count first also avoids calculating an enormous slice offset for a safe but very large page number.

## Make history describe meaningful steps

The browser keeps a sequence of history entries for a tab. Back and Forward move through that sequence. With ordinary document navigation, the browser may load or restore another document. A client-side router can instead update the address and screen within the current document.

Two browser operations explain the distinction:

- **Push** adds a new history entry. Use it for a meaningful committed view change, so Back can restore the previous selection.
- **Replace** changes the current entry rather than adding another. Use it for a correction or normalized spelling of the same intended view.

Angular's default navigation uses the normal history behavior; `replaceUrl: true` requests replacement. Its router also responds to browser history traversal. The consumer must continue interpreting the restored route, not keep values copied only at startup.

This list commits on Apply and native select changes. Keystrokes do not navigate. Otherwise, typing “report” could create a chain of entries for “r,” “re,” “rep,” and so on, and Back would undo typing instead of meaningful view choices. Applying the already committed trimmed search does not create an entry either.

The explicit “Use interpreted URL” action replaces the malformed or non-default spelling with `viewQuery(view)`. It retains the interpretation currently shown, including a valid out-of-range page, but removes bad/unknown values and redundant defaults. “First page” is a separate view change and therefore a normal link, not a correction of malformed text.

**Client navigation is not automatically another HTML download.** Here the loaded Angular application handles internal links and control changes in the existing document. Opening a link in a new tab or reloading still loads a document. Applications may also fetch records during client navigation; this fixture does not.

## Connect the consumer to Angular Router

Angular's router matches an address to a configured route and renders its consumer inside a `RouterOutlet`. `withComponentInputBinding()` supplies matching route values to inputs of that routed consumer. Query names `status`, `q`, `sort`, and `page` will therefore feed four raw signal inputs.

A **signal** exposes a value through a function call and lets Angular track changes. `input<unknown>()` exposes externally supplied data. `computed(...)` derives readonly values; it is not another writable view model. `linkedSignal(...)` creates writable local state with an explicit dependency: here, unfinished search starts from committed `q` and resets when that value changes.

Keep the route's data/path keys distinct from these query keys. Component input binding can also read path parameters and route data; when keys collide, higher-priority sources can override query values. This route defines no competing keys or resolvers.

Save `task-list.ts`:

```ts
import { Component, computed, inject, input, linkedSignal, signal } from "@angular/core";
import { Router, RouterLink } from "@angular/router";
import { interpretView, viewQuery } from "./task-view";
import type { ViewState } from "./task-view";
import { projectTasks, tasks } from "./tasks";

@Component({
  selector: "task-list",
  host: { class: "block min-w-0" },
  imports: [RouterLink],
  template: `
    <main class="mx-auto max-w-2xl space-y-6 px-4 py-8 [overflow-wrap:anywhere]">
      <h1 class="text-3xl font-semibold">Task list</h1>
      <p class="text-muted">Fixed demonstration data. The URL selects a view, not saved tasks.</p>

      <form class="space-y-2" (submit)="applySearch($event)">
        <label for="task-search" class="block font-medium">Search task titles</label>
        <p id="search-help" class="text-muted">
          Apply commits the search. Other controls use the committed search below. Unfinished text
          stays while that search is unchanged.
        </p>
        <div class="flex flex-wrap gap-2">
          <input
            #searchInput
            id="task-search"
            name="q"
            type="text"
            aria-describedby="search-help"
            class="min-h-11 min-w-0 grow basis-48 rounded-lg border border-muted bg-surface px-3 py-2 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
            [value]="searchDraft()"
            (input)="searchDraft.set(searchInput.value)"
          />
          <button
            type="submit"
            class="min-h-11 max-w-full rounded-lg bg-accent px-4 py-2 font-medium text-page focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
          >
            Apply search
          </button>
        </div>
      </form>

      <div class="space-y-4">
        <div>
          <label for="task-status" class="mb-2 block font-medium">Completion status</label>
          <select
            #statusSelect
            id="task-status"
            class="block min-h-11 w-full min-w-0 max-w-full rounded-lg border border-muted bg-surface px-3 py-2 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
            [value]="view().status"
            (change)="changeStatus(statusSelect.value)"
          >
            <option value="all">All</option>
            <option value="open">Open</option>
            <option value="completed">Completed</option>
          </select>
        </div>
        <div>
          <label for="task-sort" class="mb-2 block font-medium">Sort tasks</label>
          <select
            #sortSelect
            id="task-sort"
            class="block min-h-11 w-full min-w-0 max-w-full rounded-lg border border-muted bg-surface px-3 py-2 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
            [value]="view().sort"
            (change)="changeSort(sortSelect.value)"
          >
            <option value="due">Due day</option>
            <option value="title">Title</option>
          </select>
        </div>
      </div>

      <section aria-labelledby="url-heading" class="space-y-3">
        <h2 id="url-heading" class="text-xl font-semibold">URL interpretation</h2>
        <div role="status" aria-atomic="true">
          @for (issue of interpreted().issues; track issue) {
            <p>{{ issue }}</p>
          }
          <p>{{ navigationMessage() }}</p>
        </div>
        <button
          type="button"
          (click)="navigate(view(), true)"
          class="min-h-11 max-w-full rounded-lg border border-line px-3 py-2 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
        >
          Use interpreted URL
        </button>
        <p class="text-muted">
          Replaces this history entry; removes defaults and unsupported values.
        </p>
      </section>

      <section id="results" aria-labelledby="results-heading" class="space-y-3">
        <h2 id="results-heading" class="text-xl font-semibold">Results</h2>
        <p id="result-summary" role="status" aria-atomic="true">
          Committed search: “{{ view().q }}”. {{ results().total }} matching tasks. Page
          {{ view().page }}; {{ results().pageCount }} available pages.
        </p>
        <ul class="space-y-3" role="list">
          @for (task of results().visible; track task.id) {
            <li class="space-y-2 rounded-lg border border-line bg-surface p-4">
              <h3 class="font-semibold">{{ task.title }}</h3>
              @if (task.done) {
                <p class="text-muted">Completed</p>
              } @else {
                <p>Open</p>
              }
              <p>
                Due <time [attr.datetime]="task.due">{{ task.due }}</time>
              </p>
            </li>
          }
        </ul>
        @if (results().total === 0) {
          <p>No matching tasks. Change the search or status, or show all tasks.</p>
          <a
            routerLink="/tasks"
            class="inline-block min-h-11 max-w-full rounded-lg border border-line px-3 py-2 underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
            >Show all tasks</a
          >
        } @else if (view().page > results().pageCount) {
          <p>This page is beyond the available results. Return to the first page.</p>
        }
        <nav aria-label="Task result pages" class="flex flex-wrap gap-2">
          @if (view().page > 1) {
            <a
              routerLink="/tasks"
              [queryParams]="pageQuery(1)"
              class="inline-block min-h-11 max-w-full rounded-lg border border-line px-3 py-2 underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
              >First page</a
            >
          }
          @if (view().page > 1 && view().page <= results().pageCount) {
            <a
              routerLink="/tasks"
              [queryParams]="pageQuery(view().page - 1)"
              class="inline-block min-h-11 max-w-full rounded-lg border border-line px-3 py-2 underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
              >Previous page</a
            >
          }
          @if (view().page < results().pageCount) {
            <a
              routerLink="/tasks"
              [queryParams]="pageQuery(view().page + 1)"
              class="inline-block min-h-11 max-w-full rounded-lg border border-line px-3 py-2 underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
              >Next page</a
            >
          }
        </nav>
      </section>
      <a
        routerLink="/tasks"
        class="inline-block min-h-11 max-w-full rounded-lg border border-line px-3 py-2 underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
        >Reset view</a
      >
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
      this.navigationMessage.set("No navigation completed. The committed view is unchanged.");
    }
  }
}
```

The input field owns browser editing, the input event copies its current text into the local draft, and `[value]` renders deliberate draft resets. The native form's `submit` event includes Enter from its text input. `preventDefault()` stops ordinary form document navigation; it does not validate or navigate through Angular by itself.

`Router.navigate` returns a **Promise**: an object representing a result that may arrive later. `await` pauses that handler until navigation completes without blocking browser interaction. A `true` result means navigation succeeded; `false` means it did not complete, for example an ignored same-URL navigation. No committed view is changed optimistically. Unexpected rejected navigation is not relabeled as a malformed URL; the demonstration has no guards, resolvers, or network operations.

The native selects render interpreted values and commit on change. Their value checks reject an unexpected control string rather than pretending a type assertion validated it. Pagination uses actual `<a>` elements with `RouterLink`: Angular supplies real destination `href` values and handles ordinary internal activation. The links still support copying, keyboard Enter, and opening a new tab. A clickable `<div>` would not supply those link behaviors.

Labels name controls, `focus-visible` outlines show keyboard focus, and status text identifies both the **committed** search and selected page. Malformed input has visible default explanations and an explicit correction action; no matches and out-of-range pages have distinct useful recovery. Interpolation renders search/title text as text, not HTML. No `[innerHTML]` binding is needed.

### Supply the route and host

Save `task-app.ts`:

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

Save `main.ts`:

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

These are the five application files: `task-view.ts`, `tasks.ts`, `task-list.ts`, `task-app.ts`, and `main.ts`. Use them in an Angular application with its usual build setup and the styling article's Tailwind entry. Replace the earlier bootstrap rather than running both examples. The browser-parsed host document should have this shape; keep the application's generated script/stylesheet setup:

```html
<!doctype html>
<html lang="en" data-theme="dark">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <base href="/" />
    <title>Task list</title>
  </head>
  <body class="bg-page font-sans text-foreground">
    <task-app></task-app>
  </body>
</html>
```

`<base href="/">` establishes the base for this root-mounted application's relative URLs. An application deployed under a subpath needs a matching base. The actual browser HTML pairs the custom root's opening and closing tags; Angular's template parser can self-close the empty outlet as shown.

### Reuse and removed values are part of the contract

Navigating between query variants of the same route normally **reuses the routed component instance**. A constructor or one-time initialization is therefore insufficient to keep a view current.

With the default `withComponentInputBinding()` behavior used here, removing a matching value sets its input to `undefined`. It can overwrite an input's initializer too: an initializer such as `input("all")` is not a route-default policy. Defaults belong in the interpretation of every update. Opening `/tasks` after a filtered URL must restore all tasks, empty committed search, due sorting, and page 1 on the same instance.

The draft's linked computation receives the committed `q` string and its previous source/value. Other route changes can recompute the view even when `q` is equal; the explicit equality check preserves the unfinished value in that case. A changed or removed committed search returns the new `q` and resets the draft. This is deliberate unfinished-work behavior, not a second writable committed model or an effect that copies filters in both directions.

An `ActivatedRoute.snapshot` is a point-in-time route value. A snapshot captured during construction does not become an ongoing subscription when query parameters change. Reading the route's latest snapshot again can answer a one-off question; keeping the captured snapshot cannot drive this reused screen. The running consumer uses bound signal inputs instead.

## Verify entry, reuse, and recovery

A view is not shareable merely because clicking Apply changes the address. Exercise every way the address can become current:

1. **Direct entry:** open `/tasks?status=open&q=report&sort=due&page=2`. Check Open, Due day, the committed search, page 2, and the three middle report tasks. This fixture has eight open report matches, so page 2 is meaningful.
2. **New tab, reload, copied fresh session:** open the address independently and reload. The same settings/results should appear without relying on the old page's memory or `history.state`.
3. **Draft and Apply:** type without submitting. Check unchanged address, results, and history. Press Enter to Apply; commit trimmed search and page 1. Applying the unchanged trimmed search must not add a history entry.
4. **Selects and page links:** change status/sort from page 2. Reset page to 1, preserve committed search, and deliberately drop unsupported raw keys. Follow Next, Previous, and First page; inspect/copy their real destinations.
5. **Back and Forward:** traverse those committed choices. Address, raw inputs, interpreted controls, result summary, and rows must agree. Unfinished search follows the stated policy, not a hidden per-entry draft cache.
6. **Removed values on the same instance:** follow Reset view from a non-default URL. Confirm all four defaults and an empty draft when the committed search changes. This specifically catches stale initializers and startup-only snapshot reads.
7. **Malformed supplied values:** try bad/blank enums, repeated supported keys, and pages `0`, `-1`, `1.5`, `01`, `1e2`, or `9007199254740992`. Also try `q=re%0Aport`, `q=re%0Dport`, and `q=re%0D%0Aport`: internal LF, CR, and CRLF are malformed; the visible field, local draft, and committed search must all be empty. Use the documented per-field defaults and feedback; keep the other supported values. Then choose Use interpreted URL: replace the entry, clear issues, remove malformed `q`, and do not add another history step.
8. **Literal text:** Apply `A&B + café ✓ <strong>report</strong>`. Confirm one literal `q` survives the builder, reload, and copied link. The fixture title and committed summary should contain literal angle-bracket text, not create a `<strong>` element. Spaces at the ends are trimmed, not internal symbols.
9. **Empty and beyond-last pages:** try a nonmatching search and a valid page 500. Distinguish no matches from a page beyond existing matches. Recovery must navigate rather than quietly show different data under the same page address.
10. **Document and layout behavior:** observe document requests while following internal links/select changes; they should not download another HTML document. At a true 320 CSS-pixel viewport, inspect dark mode with a 16px root font and light mode with a 32px root font. Read the long fixture title, scroll to every control/link, and check visible keyboard focus and no horizontal body overflow.

The stylesheet stays the shared Tailwind 4 palette, defaulting to dark mode; `data-theme="light"` selects the alternate values. Wrapping layout, full-width selects, shrinking input, and breakable text are intentional, but classes alone do not prove usable narrow/larger-text rendering. State correctness, template compilation, and rendered document checks provide different evidence.

A path-based single-page application also needs its **host to serve the application document for a direct request to `/tasks`**, not only for `/`. Otherwise an internal link can work while reload or direct entry returns a host-level 404 before Angular starts. This is a serving requirement, not a reason to add hosting configuration to the example.

The example is deliberately bounded: fixed data, one route, no backend/network/persistence, no RxJS consumer, custom codec system, guards, resolvers, cache, or deployment configuration. Compiler, contract, and Chromium checks do not establish screen-reader speech, touch usability, browser zoom, cross-browser equivalence, real-server behavior, or WCAG conformance.

## Closing check

1. Why can the same URL produce different task records next week?
2. Which search belongs in the URL: each unfinished keystroke or the committed choice?
3. Why are missing `page` and supplied `page=0` different cases?
4. Why construct supported query values rather than concatenate text or blindly merge raw parameters?
5. What must change together when Back restores an earlier entry?
6. Why does removing a query value need testing on a reused component?
7. When should a correction replace history, and when should navigation push?

Check your reasoning:

- The URL selects a view over available data; it does not snapshot the underlying records or permissions.
- The committed search is shareable view state. Unfinished text remains a deliberately separate local draft until Apply.
- Missing uses an ordinary default. Zero violates the positive-page contract, so the same default needs visible malformed-input feedback.
- Builders encode values safely; explicit selection retains intended supported settings, omits defaults, resets stale pages, and excludes unsupported raw keys.
- Address, interpreted controls, summary, and results must all describe the restored committed view. Draft behavior has its own explicit policy.
- The same instance can receive new or removed route inputs. Default input binding writes `undefined` for absent values; startup-only reads or initializer-based defaults can leave stale state.
- Replace corrects the representation of the current intended view. Push records a meaningful new view choice that Back should undo. Neither belongs on every keystroke in this consumer.

## Sources and further reading

- [HTML Standard: single-line text inputs and value sanitization](<https://html.spec.whatwg.org/multipage/input.html#text-(type=text)-state-and-search-state-(type=search)>)
- [MDN: URL parts and safe construction](https://developer.mozilla.org/en-US/docs/Web/API/URL)
- [MDN: fragments and document locations](https://developer.mozilla.org/en-US/docs/Web/URI/Reference/Fragment)
- [MDN: URLSearchParams, duplicate values, and preserving plus signs](https://developer.mozilla.org/en-US/docs/Web/API/URLSearchParams)
- [MDN: session history, push, replace, and traversal](https://developer.mozilla.org/en-US/docs/Web/API/History_API/Working_with_the_History_API)
- [Angular: navigate with links and Router](https://angular.dev/guide/routing/navigate-to-routes)
- [Angular: read route state and point-in-time snapshots](https://angular.dev/guide/routing/read-route-state)
- [Angular: component input binding and removed-value behavior](https://angular.dev/api/router/withComponentInputBinding)
- [Angular: RouterLink and real link destinations](https://angular.dev/api/router/RouterLink)
- [Angular: navigation extras, replaceUrl, and history state](https://angular.dev/api/router/NavigationExtras)
- [Angular: Router navigation results](https://angular.dev/api/router/Router)
- [Angular: serving the host document for deep links](https://angular.dev/tools/cli/deployment#routed-apps-must-fall-back-to-indexhtml)
- [Angular: signals and derived values](https://angular.dev/guide/signals)
- [Angular: dependent writable state with linkedSignal](https://angular.dev/guide/signals/linked-signal)
