---
title: "Testing what your code does from the outside"
description: "Write Angular tests that fail when the Save button breaks and keep passing when you rename a private method: test a function, a component, an HTTP request and a real browser through what each one exposes."
pubDate: "2026-10-08"
updatedDate: "2026-10-15"
tags:
  - angular
  - testing
  - frontend
---

Here's a quick way to find out whether your tests protect anything: break the code on purpose and run them. Unhook the Save button from its form, so clicking it does nothing. If every test still passes, none of them was watching the Save button. Then try the opposite: give a private method a clearer name without changing what the page does. If tests fail now, they were checking how the code is written instead of what it does.

Useful tests fail after the first change and pass after the second. They manage that by checking only what can be seen from outside the code being tested: what a function returns, what a person sees on the screen, which request goes out to the server. That's what _observable behavior_ means in this article. It has nothing to do with RxJS's `Observable` type.

The example is a small Angular editor that changes one task's title. You'll test it at four levels: a plain function, a rendered component, the HTTP request it sends, and a real browser. At the end, you'll break the code on purpose and see which tests notice.

You'll need basic TypeScript and Angular components, meaning inputs, outputs and signals; the [components article](/dump/blog/angular-component-composition/) covers them. The examples use Angular 22.2.1, `@testing-library/dom` 10.4.2 and Playwright 1.64.1. These are the testing tools involved:

- **Vitest** is the test runner. It finds your `*.spec.ts` files, runs each test and reports which ones failed. New Angular CLI projects include it, and `ng test` runs it.
- **jsdom** gives Vitest a simulated browser `document` inside Node.js, so components can render without a real browser. It doesn't calculate layout, so it can't tell you where anything appears on screen. New Angular projects use it by default.
- **Testing Library** (`@testing-library/dom`) finds elements the way a person does: by their label, by their role, such as "button", or by their text. Install it with `npm install --save-dev @testing-library/dom`.
- **Playwright** opens a real browser and controls it from a test. It's a separate tool with its own configuration; `npm init playwright@latest` adds it to a project.

Every test file uses two functions from the runner. `it(name, fn)` registers one test: the runner calls `fn` and marks the test as failed if anything inside it throws. `expect(actual)` starts a check, so `expect(result).toBe("Done")` throws when `result` isn't `"Done"`. A check like that is called an **assertion**. Playwright names its version `test` instead of `it`, and it works the same way.

## Contents

1. [What the editor should do](#what-the-editor-should-do)
2. [Testing a function directly](#testing-a-function-directly)
3. [The example: a task page and editor](#the-example-a-task-page-and-editor)
4. [Testing through the UI](#testing-through-the-ui)
5. [Testing the HTTP request](#testing-the-http-request)
6. [Checking in a real browser](#checking-in-a-real-browser)
7. [What to call these tests](#what-to-call-these-tests)
8. [Does the test catch the bug?](#does-the-test-catch-the-bug)

## What the editor should do

The editor shows one task's title in a text field, with Save and Cancel buttons. The page around it shows the **saved title**, the version the server has confirmed. This table is everything the editor has to get right, and it's what the tests will check:

| Situation                     | What should happen                                                                                                      |
| ----------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| Save succeeds                 | The title goes to the server without surrounding spaces. The page and the field both show the title the server returns. |
| Title is empty or only spaces | An error message appears, no request is sent, and the saved title stays the same.                                       |
| Save fails                    | The typed text stays in the field, the saved title stays the same, and a message says to try again.                     |
| Cancel                        | The field goes back to the latest saved title, and no request is sent.                                                  |

The success row says "the title the server returns" on purpose. A server can change what it stores, for example by fixing capitalization, so the page has to show the server's version instead of assuming its own text was kept.

Each kind of mistake is cheapest to catch at a different level:

- **Spaces aren't trimmed:** call the function that trims them.
- **The Save button isn't connected to anything:** render the component and click the button.
- **The title is sent under the wrong property name:** inspect the HTTP request.
- **Enter doesn't submit, focus gets lost, or the layout breaks:** use a real browser.

The rest of the article takes these one at a time.

## Testing a function directly

Start with the smallest piece. Save `task.ts`:

```ts
export interface Task {
  id: number;
  title: string;
}

export function normalizeTitle(value: string): string | undefined {
  const title = value.trim();

  if (title === "") {
    return undefined;
  }

  return title;
}
```

The editor only needs a task's ID and title, so this `Task` leaves out the `done` flag that other articles in the series use. `normalizeTitle` removes spaces from both ends. If nothing is left, it returns `undefined`, meaning "no usable title".

Code that uses `normalizeTitle` calls it directly, so the test does the same. Save `task.spec.ts`:

```ts
import { expect, it } from "vitest";
import { normalizeTitle } from "./task";

it("rejects a title made only of whitespace", () => {
  const result = normalizeTitle("   ");

  expect(result).toBeUndefined();
});

it("returns the text without surrounding whitespace", () => {
  const result = normalizeTitle("  Review the pull request  ");

  expect(result).toBe("Review the pull request");
});
```

Each test calls the function the way real code does and checks only what comes back. How `normalizeTitle` works inside can change freely without breaking either test.

The expected string is typed out by hand. Computing it by calling `normalizeTitle` again would make the test agree with the same bug twice.

## The example: a task page and editor

Two components share the work. The page owns the saved task. The editor owns the text being typed, called the **draft**. Only a confirmed save turns the draft into the new saved task:

```text
TaskPage
  owns the saved task
      │                          ▲
      │ [task], [persist]        │ (saved) with the server's task
      ▼                          │
TaskEditor
  owns the draft title
  Save   → persist(id, title) → succeeds → report (saved)
                              → fails    → keep the draft
  Cancel → put the saved title back in the draft
```

Save the editor in `task-editor.ts`:

```ts
import { Component, input, linkedSignal, output, signal } from "@angular/core";
import { normalizeTitle } from "./task";
import type { Task } from "./task";

@Component({
  selector: "task-editor",
  template: `
    <form novalidate (submit)="save($event, titleInput)">
      <label for="draft-title">Task title (required)</label>
      <p id="title-help">Use more than whitespace.</p>
      <input
        #titleInput
        id="draft-title"
        type="text"
        required
        [value]="draftTitle()"
        [readonly]="busy()"
        aria-describedby="title-help title-error"
        [attr.aria-invalid]="titleError() !== ''"
        (input)="draftTitle.set(titleInput.value); titleError.set(''); status.set('')"
      />
      <p id="title-error" aria-live="polite">{{ titleError() }}</p>
      <button type="submit" [disabled]="busy()">Save task</button>
      <button type="button" [disabled]="busy()" (click)="cancel(titleInput)">Cancel</button>
      <p role="status">{{ status() }}</p>
    </form>
  `,
})
export class TaskEditor {
  readonly task = input.required<Task>();
  readonly persist = input.required<(id: number, title: string) => Promise<Task>>();
  readonly saved = output<Task>();

  readonly draftTitle = linkedSignal(() => this.task().title);
  readonly titleError = signal("");
  readonly status = signal("");
  readonly busy = signal(false);

  async save(event: SubmitEvent, titleInput: HTMLInputElement) {
    event.preventDefault();

    const title = normalizeTitle(this.draftTitle());
    if (title === undefined) {
      this.titleError.set("Enter a task title, not just spaces.");
      this.status.set("Nothing saved. Correct the title.");
      titleInput.focus();
      return;
    }

    this.busy.set(true);
    this.status.set("Saving…");
    try {
      const confirmed = await this.persist()(this.task().id, title);
      this.saved.emit(confirmed);
      this.draftTitle.set(confirmed.title);
      this.status.set("Task saved.");
    } catch {
      this.status.set("Not saved. Your draft is kept. Try Save again.");
    } finally {
      this.busy.set(false);
      titleInput.focus();
    }
  }

  cancel(titleInput: HTMLInputElement) {
    this.draftTitle.set(this.task().title);
    this.titleError.set("");
    this.status.set("Edits cancelled. Saved task unchanged.");
    titleInput.focus();
  }
}
```

If the template syntax is new to you: `[value]="draftTitle()"` sets the input's `value` property, and `[attr.aria-invalid]` sets an HTML attribute instead. `(input)="…"` runs code on every `input` event. `#titleInput` names the `<input>` element so the template can pass it to `save` and `cancel`. `{{ status() }}` shows text.

In the class:

- A **signal** holds a value and tells Angular when it changes. You call it to read it, as in `busy()`, and use `.set()` to change it.
- `input.required<Task>()` is data the page must pass in. `output<Task>()` is an event the editor reports back to the page.
- `persist` is an input whose value is a function: the save operation. `this.persist()` reads the input and gives you that function, and the second pair of parentheses calls it with the ID and title. The editor doesn't know whether that function talks to a server, so a test can hand it a fake one.
- `linkedSignal(() => this.task().title)` creates a signal that starts as the task's title and starts over whenever the page passes in a different task. In between, typing changes it with `.set()`.

Saving takes time, because the request has to reach the server and come back. A **Promise** is an object for a result that isn't ready yet: later, it either _resolves_ with a value or _rejects_ with an error. `persist` returns one. Inside an `async` function, `await` pauses that function until the Promise settles, while the rest of the page keeps working. If the Promise rejects, `await` throws, so `save` jumps into `catch` and shows the failure message. `finally` runs after either outcome, so the field and buttons always unlock.

A few form details matter for the tests later:

- `preventDefault()` stops the browser's normal form submission, which would load a new page. `novalidate` turns off the browser's own validation popups, so the editor can show its own error message.
- Because the form has a submit button, pressing Enter in the title field submits it. Cancel is `type="button"`, so it never submits.
- While a save is running, both buttons are disabled. A disabled submit button also stops Enter from submitting the form, so a second save can't start.
- After every outcome, the editor moves focus back to the title field, so keyboard users stay where they were working.
- The label gives the field its name. `aria-describedby` connects the help and error text, so screen readers read them along with the field. `aria-invalid` marks the field while an error is shown. `aria-live="polite"` on the error paragraph and `role="status"` on the status paragraph make screen readers announce those messages when they change. The [accessibility article](/dump/blog/accessibility-in-practice/) covers these in more depth. They also give tests something stable to search for: the field by its label, the message by its role.

The page holds the saved task and gives the editor the real save operation. Save `task-page.ts`:

```ts
import { Component, inject, signal } from "@angular/core";
import type { Task } from "./task";
import { TaskEditor } from "./task-editor";
import { TaskGateway } from "./task-gateway";

@Component({
  selector: "task-page",
  imports: [TaskEditor],
  template: `
    <main>
      <h1>Task notes</h1>
      <h2>Saved task</h2>
      <p data-testid="saved-title">{{ task().title }}</p>
      <h2>Edit task</h2>
      <task-editor [task]="task()" [persist]="persist" (saved)="task.set($event)" />
    </main>
  `,
})
export class TaskPage {
  readonly task = signal<Task>({ id: 41, title: "Read the DOM article" });
  readonly persist = inject(TaskGateway).save;
}
```

`inject(TaskGateway)` asks Angular for the `TaskGateway` service, the class that sends the HTTP request. Its code comes in [Testing the HTTP request](#testing-the-http-request); for now, all that matters is that its `save(id, title)` returns a `Promise<Task>`. Because Angular hands the page its service instead of the page creating one, a test can tell Angular to hand over something else. The [dependency injection article](/dump/blog/angular-dependency-injection/) explains how that works.

`data-testid="saved-title"` marks the paragraph that shows the saved title. A plain paragraph has no label or role to search by, so the test ID gives tests a way to find it that won't break if the markup around it changes. People never see it, and it doesn't replace a label.

## Testing through the UI

A component test could reach into the editor and call `save()` directly. That test would pass even if the Save button weren't connected to `save` at all, which is exactly the bug from the opening. So a UI test does what a person does: types into the field, presses the button, and reads what's on the screen.

The test still needs control over one thing: whether saving succeeds. A live server can't be made to fail on demand, and the server isn't what this test is about. So the test replaces only the save operation. The page, the editor, the validation, the template bindings and the `saved` output all stay real.

A stand-in like that is called a **test double**. You'll also hear fake, stub, mock and spy; teams use those words slightly differently, but each one means something that takes the place of a piece the code depends on.

Save `task-page.spec.ts`:

```ts
import { TestBed } from "@angular/core/testing";
import { getByLabelText, getByRole, getByTestId, getByText, waitFor } from "@testing-library/dom";
import { expect, it, vi } from "vitest";
import { TaskGateway } from "./task-gateway";
import { TaskPage } from "./task-page";

it("keeps the typed title and the saved title when saving fails", async () => {
  const save = vi.fn(async (_id: number, _title: string) => {
    throw new Error("Controlled save failure");
  });
  TestBed.configureTestingModule({
    providers: [{ provide: TaskGateway, useValue: { save } }],
  });

  const fixture = TestBed.createComponent(TaskPage);
  await fixture.whenStable();
  const view: HTMLElement = fixture.nativeElement;
  const titleInput = getByLabelText<HTMLInputElement>(view, "Task title (required)");
  const saveButton = getByRole(view, "button", { name: "Save task" });
  const savedTitle = getByTestId(view, "saved-title");
  const feedback = getByRole(view, "status");

  titleInput.value = "Review the pull request";
  titleInput.dispatchEvent(new Event("input", { bubbles: true }));
  await fixture.whenStable();
  saveButton.click();
  await waitFor(() => {
    expect(feedback.textContent).toBe("Not saved. Your draft is kept. Try Save again.");
  });

  expect(save).toHaveBeenCalledExactlyOnceWith(41, "Review the pull request");
  expect(titleInput.value).toBe("Review the pull request");
  expect(savedTitle.textContent).toBe("Read the DOM article");
});
```

Here's what the setup does:

- `vi.fn(...)` creates the test double. Vitest wraps the function you give it and records every call, so the test can check them later. Because the wrapped function is `async`, throwing inside it makes its Promise reject, which is exactly what a failed request looks like to the editor. The underscored parameters are ignored; they give the fake the same shape as the real `save`.
- `providers` tells Angular: whenever something asks for `TaskGateway`, hand over `{ save }` instead. So the page's `inject(TaskGateway).save` gets the fake.
- `TestBed.createComponent(TaskPage)` renders the page with its real template inside jsdom. The **fixture** it returns gives the test the rendered element as `fixture.nativeElement`. `await fixture.whenStable()` waits until Angular has finished its pending work, including rendering.
- `getByLabelText`, `getByRole` and `getByTestId` come from Testing Library. They find the field by its label, the button by its role and name, and the saved title by its test ID. Nothing depends on CSS classes or on how the elements are nested.

Then the test acts like a person:

- Setting `titleInput.value` changes the field, but it doesn't fire an event, so Angular's `(input)` listener never hears about it. Dispatching an `input` event does what a keystroke would. `bubbles: true` makes it travel up through parent elements, like a real input event.
- The second `await fixture.whenStable()` lets Angular render the typed draft before the click, and that closes a gap a bug could hide in. Angular remembers the last value it wrote through `[value]` and writes to the field again only when the bound value differs from that remembered one. The test changed the field directly, so without this wait Angular still remembers `Read the DOM article`. Now picture a broken editor that resets the draft to `Read the DOM article` when saving fails. Angular would see the same value it remembers, skip the write, and leave the typed text in the field, so the test would pass despite the bug. After the wait, Angular remembers the typed draft, and a reset is a real change that reaches the field.
- `saveButton.click()` submits the form through the real `(submit)` binding.

After the click, the test has to wait. The fake's rejection and Angular's re-render happen a moment later, so checking right away would see the old screen. Pausing for a fixed time, such as 500 ms, is a common mistake: on a fast machine it wastes time, and on a slower one it might not be long enough. That's how a test ends up failing now and then in CI (continuous integration), the server that runs your tests automatically on every push.

`waitFor` from Testing Library waits for a condition instead of a fixed time. It runs the callback, and if the callback throws, it tries again shortly after, until the callback passes or a deadline runs out (one second by default). So it finishes as soon as the failure message appears, and if the message never appears, it fails with the assertion's own error. The expected text stays exact; waiting only changes _when_ the check runs.

The last three lines check the rest of the failure row from [the table](#what-the-editor-should-do):

- `toHaveBeenCalledExactlyOnceWith` checks the data that left the UI: one call, with ID 41 and the typed title. That's what the server would receive, so it's worth checking. Which private helper ran inside `save` isn't.
- The field still holds the typed text, and the saved title hasn't changed. Checking only the call would miss an editor that sends the right data and then clears the draft when saving fails.

This test shows how the UI behaves _when_ saving fails. It can't show that a real server fails or succeeds the way the fake does.

The blank-title and Cancel rows get one test each, in the same file below the first one:

```ts
it("shows an error and sends nothing when the title is only spaces", async () => {
  const save = vi.fn(async (id: number, title: string) => ({ id, title }));
  TestBed.configureTestingModule({
    providers: [{ provide: TaskGateway, useValue: { save } }],
  });

  const fixture = TestBed.createComponent(TaskPage);
  await fixture.whenStable();
  const view: HTMLElement = fixture.nativeElement;
  const titleInput = getByLabelText<HTMLInputElement>(view, "Task title (required)");
  const feedback = getByRole(view, "status");

  titleInput.value = "   ";
  titleInput.dispatchEvent(new Event("input", { bubbles: true }));
  await fixture.whenStable();
  getByRole(view, "button", { name: "Save task" }).click();
  await waitFor(() => {
    expect(feedback.textContent).toBe("Nothing saved. Correct the title.");
  });

  getByText(view, "Enter a task title, not just spaces.");
  expect(titleInput.getAttribute("aria-invalid")).toBe("true");
  expect(save).not.toHaveBeenCalled();
  expect(getByTestId(view, "saved-title").textContent).toBe("Read the DOM article");
});

it("puts the saved title back on Cancel without saving", async () => {
  const save = vi.fn(async (id: number, title: string) => ({ id, title }));
  TestBed.configureTestingModule({
    providers: [{ provide: TaskGateway, useValue: { save } }],
  });

  const fixture = TestBed.createComponent(TaskPage);
  await fixture.whenStable();
  const view: HTMLElement = fixture.nativeElement;
  const titleInput = getByLabelText<HTMLInputElement>(view, "Task title (required)");
  const feedback = getByRole(view, "status");

  titleInput.value = "Half-typed title";
  titleInput.dispatchEvent(new Event("input", { bubbles: true }));
  await fixture.whenStable();
  getByRole(view, "button", { name: "Cancel" }).click();
  await waitFor(() => {
    expect(feedback.textContent).toBe("Edits cancelled. Saved task unchanged.");
  });

  expect(titleInput.value).toBe("Read the DOM article");
  expect(save).not.toHaveBeenCalled();
});
```

Both follow the same steps as the failure test, so here's only what's new:

- The fake succeeds this time, like a working server would. Neither test expects it to be called.
- `getByText` throws when no element shows that exact text, so that line is a check of its own: the error message is on the screen.
- `not.toHaveBeenCalled()` checks that no save started. It runs after the status message has appeared, so the editor has already finished reacting to the click.

## Testing the HTTP request

The fake in the UI test skipped the HTTP request entirely, so a separate test checks what `TaskGateway` sends and how it reads the answer. Save `task-gateway.ts`:

```ts
import { HttpClient } from "@angular/common/http";
import { Injectable, inject } from "@angular/core";
import { firstValueFrom } from "rxjs";
import type { Task } from "./task";

@Injectable({ providedIn: "root" })
export class TaskGateway {
  private readonly http = inject(HttpClient);

  readonly save = async (id: number, title: string): Promise<Task> => {
    const request = this.http.put<unknown>(`/api/tasks/${id}`, { title });
    const incoming = await firstValueFrom(request);

    // typeof null is also "object", so null needs its own check.
    const isObject = typeof incoming === "object" && incoming !== null;
    if (!isObject || !("id" in incoming) || !("title" in incoming)) {
      throw new Error("Invalid task confirmation");
    }

    // Check the type first: trim() only exists on strings.
    if (typeof incoming.title !== "string" || incoming.title.trim() === "") {
      throw new Error("Invalid task confirmation");
    }

    if (incoming.id !== id) {
      throw new Error("Invalid task confirmation");
    }

    return { id, title: incoming.title };
  };
}
```

What to notice:

- `save` is an arrow function stored in a property instead of a regular method. That's why the page can take `inject(TaskGateway).save` on its own and call it later: an arrow function keeps `this` pointing at the gateway. A regular method passed around like that would lose `this` and fail when it reaches `this.http`.
- `this.http.put(...)` doesn't send anything yet. It returns an RxJS Observable, a description of a request that runs once something starts listening to it. `firstValueFrom` starts listening and gives you a Promise for the first response. If the request fails, that Promise rejects.
- `unknown` says nothing about the response is trusted yet. The checks make sure the server sent an object with the right `id` and a title that's a nonblank string. Anything else throws, and the editor shows it as "Not saved". A TypeScript type on its own wouldn't check anything while the app runs; the [article on API responses and UI models](/dump/blog/api-responses-to-ui-models/) explains why.

Angular's `HttpTestingController` catches requests made with `HttpClient` and lets the test answer them, with no network involved. Save `task-gateway.spec.ts`:

```ts
import { provideHttpClient } from "@angular/common/http";
import { HttpTestingController, provideHttpClientTesting } from "@angular/common/http/testing";
import { TestBed } from "@angular/core/testing";
import { expect, it } from "vitest";
import { TaskGateway } from "./task-gateway";

it("sends the title and returns the server's confirmed task", async () => {
  TestBed.configureTestingModule({
    providers: [provideHttpClient(), provideHttpClientTesting()],
  });
  const gateway = TestBed.inject(TaskGateway);
  const http = TestBed.inject(HttpTestingController);

  const saving = gateway.save(41, "review the pull request");
  const request = http.expectOne({ method: "PUT", url: "/api/tasks/41" });
  expect(request.request.body).toEqual({ title: "review the pull request" });

  request.flush({ id: 41, title: "Review the pull request" });
  const confirmed = await saving;
  expect(confirmed).toEqual({ id: 41, title: "Review the pull request" });
  http.verify();
});
```

What to notice:

- `provideHttpClient()` sets up `HttpClient`, and `provideHttpClientTesting()` replaces the part that would use the network. Keep them in this order: the testing provider overrides parts of the normal one, so it has to come second.
- `expectOne` finds the single request with that method and URL, and fails if there isn't exactly one. The test then checks the body. The server reads `{ title: ... }`, so renaming that property would break the server even though the UI would look fine.
- `flush` sends the fake response. Here the server answers with a capitalized title, and the test checks that the gateway returns the server's version.
- `saving` is awaited only after `flush`. Awaiting it earlier would hang, because the request is waiting for the very answer the test hasn't sent yet.
- `verify()` fails if a request is still waiting that no `expectOne` ever matched, such as an extra request the test didn't expect. A matched request that never got a `flush` doesn't count. In a file with several tests, put it in `afterEach` so it runs even when an earlier assertion fails.

Failure responses and malformed responses get tests in the same style, where they matter to you.

This test shows that the gateway sends what it's meant to send. It can't show that the deployed server accepts that body. Only a test that talks to a real server can.

## Checking in a real browser

jsdom handles bindings, events and text well, but it doesn't calculate layout and it skips some native browser behavior. It can't show whether the form fits a narrow screen, where focus visibly lands, or whether pressing Enter really submits. For those, run the actual app in a real browser with Playwright.

This test still fakes one thing: the server's answer. Playwright's `page.route` catches the save request inside the browser and answers it itself. Everything else is real, including the Angular app, `HttpClient` and the gateway's checks.

The test assumes three things: the app shows `TaskPage` at `/tasks`, the app's providers include `provideHttpClient()` because `TaskGateway` needs `HttpClient`, and Playwright's `baseURL` setting points at your development server. Save `task-workflow.spec.ts`:

```ts
import { expect, test } from "@playwright/test";

test("shows the title the server confirmed, not the typed draft", async ({ page }) => {
  await page.route("**/api/tasks/41", async (route) => {
    const request = route.request();
    const payload: unknown = request.postDataJSON();
    expect(request.method()).toBe("PUT");
    expect(payload).toEqual({ title: "review the pull request" });
    await route.fulfill({
      status: 200,
      json: { id: 41, title: "Review the pull request" },
    });
  });
  await page.goto("/tasks");

  const titleInput = page.getByLabel("Task title (required)");
  const saveButton = page.getByRole("button", { name: "Save task", exact: true });
  const savedTitle = page.getByTestId("saved-title");
  const feedback = page.getByRole("status");

  await titleInput.fill("  review the pull request  ");
  await saveButton.click();

  await expect(feedback).toHaveText("Task saved.");
  await expect(savedTitle).toHaveText("Review the pull request");
  await expect(titleInput).toHaveValue("Review the pull request");
});
```

What to notice:

- The `page.route` callback runs for each matching request. It checks the method and body, then `fulfill` sends back a response with a capitalized title. If one of its checks fails, Playwright reports that failure and the test fails.
- `fill` types the text, spaces included, and fires the input events Angular listens for. The route then confirms that the spaces were trimmed before sending.
- `getByLabel`, `getByRole` and `getByTestId` are Playwright's versions of the Testing Library queries from earlier.
- `await expect(locator).toHaveText(...)` retries until the element has that text or the default five-second timeout runs out. That's the same condition-based waiting as `waitFor`, built into the assertion. Awaiting `saveButton.click()` only waits for the click itself, not for the save to finish.

The last two checks are the success row of the table: the page and the field both show `Review the pull request`, the server's version, instead of the typed `review the pull request`.

Browser versions of the other rows follow the same pattern. For the failure case, answer with an error status and check that the typed text is still there once the failure message appears. For a blank title and for Cancel, count the requests the route sees, and check the count only after the visible result has appeared; a count taken before the interaction has finished proves very little.

A real browser also lets you check the keyboard: Enter in the title field should submit, Tab should reach both buttons, Space on Cancel should cancel without saving, and focus should return to the field after each outcome. Layout needs its own checks, such as long titles, a 320-pixel-wide viewport and enlarged text. A screenshot can reveal a layout problem, but it can't tell you whether the save worked.

## What to call these tests

You've now seen four test files, so here's the vocabulary people use for them. The labels describe how much real code runs in a test, and they're fuzzy, so when it matters, say exactly what's real and what's faked.

| Label                 | Meaning                                                                | In this article                                                                  |
| --------------------- | ---------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| Unit test             | One small piece, tested on its own                                     | `task.spec.ts` calls `normalizeTitle` directly                                   |
| Component test        | A rendered component, driven through its template                      | `task-page.spec.ts`                                                              |
| Integration test      | Several real pieces working together                                   | `task-page.spec.ts` again: page, editor and validation are real; saving is faked |
| End-to-end (E2E) test | A whole workflow through the full running system, real server included | None of these                                                                    |

`task-gateway.spec.ts` sits between unit and integration: the gateway and Angular's real `HttpClient` run, with the network replaced. `task-workflow.spec.ts` runs in a real browser but fakes the server, so it tests the whole frontend and nothing behind it. Playwright is often called an E2E tool, yet a test only becomes end-to-end when the real server takes part. Where a test runs, in jsdom or a real browser, and how much of the system is real are separate choices.

A **contract test** checks that a client and a real server agree on the format of requests and responses. `task-gateway.spec.ts` checks only the client's side, so it can't notice the server changing what it accepts.

Some labels describe a test's purpose instead:

- A **smoke test** is a quick check that the most important path works at all, usually right after a build or a deployment. The browser save test could serve as one.
- A **regression test** keeps a fixed bug from coming back. If someone once shipped an editor that wiped the draft when saving failed, the UI test above would be the regression test for that bug.

One test can be several of these at once, and there's no required number or ratio of each.

## Does the test catch the bug?

A passing test only tells you that its checks held this time. To find out whether it would catch the bug it's meant to catch, do what the opening suggested: break the code on purpose in a scratch copy and run the tests. Here's what happens with this article's four test files:

| Change to the code                                             | What happens                                                        |
| -------------------------------------------------------------- | ------------------------------------------------------------------- |
| Remove `(submit)="save($event, titleInput)"` from the form     | The save-failure and blank-title UI tests and the browser test fail |
| Emit the typed title instead of the server's confirmed task    | The browser test fails: the page shows `review the pull request`    |
| Reset the draft to the saved title inside `catch`              | The save-failure UI test fails, because the typed text is gone      |
| Send `{ name: title }` instead of `{ title }`                  | The gateway test and the browser test fail                          |
| Rename `draftTitle`, `busy` and `titleError` inside the editor | Every test still passes                                             |

The last row matters as much as the others. A rename that changes nothing a person or a caller can see shouldn't break anything.

Tools that automate this idea are called **mutation testing** tools; Stryker is one for JavaScript and TypeScript. They make many small changes on their own, such as flipping `===` to `!==`, run your tests against each changed version, and report every change that no test caught. Breaking the code by hand, as in the table, is the same idea aimed at one specific worry, and it needs no extra tool.

**Coverage** is a different measurement: it reports which lines ran during the tests. A test that reaches the `catch` block but never checks the draft still covers that block, and it still misses the draft-wiping bug. Coverage is good for finding code no test touches, but it can't tell you whether the checks are any good.

Two habits keep tests dependable:

- Each test sets up its own state: its own task, its own fake and its own responses. Angular resets `TestBed` between tests, and Playwright gives each test a fresh browser context with its own cookies and storage. Neither one resets data on a real shared server, so a test that relies on another test running first will break as soon as the order changes.
- Name tests after the outcome. When "keeps the typed title and the saved title when saving fails" goes red, its name tells you what broke; "calls save once" doesn't.

Delete or rewrite a test when keeping it up costs more than the bugs it would catch. More passing tests aren't automatically better feedback.

## Closing check

Back to the two changes from the start. Unhooking the Save button made three tests fail, and renaming the editor's internals broke none. That's the result to aim for, and three questions get you there:

1. **What can someone outside the code see?** Name the input, the action and the visible result, including what should happen when something fails.
2. **Which change should make this test fail?** A broken binding, a wrong request body, a lost draft or the wrong title on screen should. A renamed private method shouldn't.
3. **What does a pass prove, and what doesn't it?** A faked server response proves how the frontend handles that response, not that the server works. jsdom proves that bindings and events work, not that the layout or native keyboard behavior does.

## Sources and further reading

- [Angular: testing overview](https://angular.dev/guide/testing)
- [Angular: basics of testing components](https://angular.dev/guide/testing/components-basics)
- [Angular: testing HTTP requests](https://angular.dev/guide/http/testing)
- [Vitest: mock functions](https://vitest.dev/api/mock)
- [Testing Library: queries](https://testing-library.com/docs/queries/about)
- [Testing Library: waiting for asynchronous results](https://testing-library.com/docs/dom-testing-library/api-async/)
- [Playwright: installation](https://playwright.dev/docs/intro)
- [Playwright: best practices](https://playwright.dev/docs/best-practices)
- [Playwright: retrying assertions](https://playwright.dev/docs/test-assertions)
- [Playwright: browser contexts](https://playwright.dev/docs/browser-contexts)
- [Playwright: network routing](https://playwright.dev/docs/network)
- [Stryker: what mutation testing is](https://stryker-mutator.io/docs/)
