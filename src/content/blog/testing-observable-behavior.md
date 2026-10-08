---
title: "Test what the consumer can observe"
description: "Choose useful test boundaries, exercise public contracts, and catch Angular UI regressions without making harmless refactoring expensive."
pubDate: "2026-10-08"
tags:
  - angular
  - testing
  - frontend
---

A private method gets a clearer name, and several tests fail. The Save button stops submitting, and every test still passes. A test passes locally but sometimes fails in continuous integration, where the same checks run automatically after a change.

These are three different problems with the same useful starting question: **what promise is this test protecting, and who depends on it?**

A test can check the steps an implementation happens to take, or it can protect the result its consumer needs. The latter gives us room to change those steps while still catching broken behavior.

Here, **observable** means visible from outside the chosen boundary. It does not mean an RxJS `Observable`. A consumer might be a person using the screen, another function calling an API, or a component supplying inputs and listening for outputs.

The running example edits one task title. Save accepts a confirmed result; invalid input sends no request; failure keeps the draft with retry guidance; Cancel restores accepted data without changing it. It builds on [component ownership](/dump/blog/angular-component-composition/) and [accepted data versus form drafts](/dump/blog/forms-and-validation/), but uses a smaller editor so the testing decisions stay visible.

## Contents

1. [Start with the promise, not the tool](#start-with-the-promise-not-the-tool)
2. [Separate scope from purpose](#separate-scope-from-purpose)
3. [Choose the smallest boundary that proves the behavior](#choose-the-smallest-boundary-that-proves-the-behavior)
4. [Give the example a real consumer](#give-the-example-a-real-consumer)
5. [Exercise the interface instead of bypassing it](#exercise-the-interface-instead-of-bypassing-it)
6. [Control the dependency, not the whole behavior](#control-the-dependency-not-the-whole-behavior)
7. [Check the HTTP boundary separately](#check-the-http-boundary-separately)
8. [Wait for the result you actually inspect](#wait-for-the-result-you-actually-inspect)
9. [Use the browser where the browser matters](#use-the-browser-where-the-browser-matters)
10. [Judge a test by its future feedback](#judge-a-test-by-its-future-feedback)

## Start with the promise, not the tool

Suppose someone enters “Review the task contract,” presses Save, and the request fails. The useful promise is not “the error handler ran.” It is:

> The accepted task stays unchanged, the entered title remains available, and the page explains that saving failed and can be retried.

That sentence identifies both the result and the failure alternative. It can guide a test before we choose a framework.

A **contract** is the agreement a consumer relies on at an interface. It includes relevant failures, not just successful values:

| Consumer boundary | What can be part of the contract?                                                |
| ----------------- | -------------------------------------------------------------------------------- |
| Public function   | Inputs, returned value, thrown errors, relevant effects such as writing a record |
| Component         | Supplied inputs, rendered content, interactions, reported outputs                |
| HTTP operation    | Method, URL, request data, accepted response shape, failure handling             |
| Complete workflow | An outcome reached through several steps, including what remains after failure   |

An **assertion** compares an actual result with an expected one and fails the test if the expectation is not met. “A request happened” is weaker than “the intended title was sent and its confirmation became the accepted title.”

The boundary determines what counts as internal. A helper's name may be internal to a component, while an HTTP request body is public to its receiver. Observing a side effect is appropriate when that effect is the promise; checking every helper call usually is not.

## Separate scope from purpose

Imagine checking a title function alone, then an editor with its page, then a browser workflow that reaches a server. These involve different amounts of real collaborating code.

That is one dimension: **scope**, or what participates in the test. Common labels describe it imperfectly, so state the actual boundary as well:

| Label              | Concrete meaning                                                                                                                                                   |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Unit               | A small, cohesive behavior tested independently. It need not be exactly one method or one class.                                                                   |
| Component          | A rendered UI contract: supplied data, controls, displayed results, and outputs. It can also be an integration test.                                               |
| Integration        | Real pieces working together, such as the page, editor, validation, and response mapping.                                                                          |
| Contract           | Agreement across a boundary, such as a client's request matching what a provider accepts. A client test with a mock alone does not prove the real provider agrees. |
| End-to-end, or E2E | A workflow through an assembled system. Name its starting and ending points, and which parts are real or substituted.                                              |

A browser test with substituted HTTP responses exercises the real frontend, not the backend. Calling it E2E does not add server coverage. Likewise, moving a component test from an emulated DOM into a browser does not automatically turn its scope into an end-to-end workflow.

The **environment** is where the test runs. Scope is which pieces it exercises. Those are separate choices.

Purpose is another dimension:

- A **smoke test** asks whether a build is basically usable through an essential path.
- A **regression test** protects behavior, often after a particular bug has been fixed, so that the bug does not return unnoticed.
- An **acceptance test** checks an agreed outcome. It can be automated or a deliberate manual check.

One browser save check can be integration, regression, and acceptance evidence at once. These labels do not require separate collections, a fixed number of tests, or a prescribed ratio between levels.

Performance, security, accessibility, and visual appearance ask additional questions. They are not extra rungs above E2E. A small function can have a security contract; a rendered component can need a visual or keyboard check.

## Choose the smallest boundary that proves the behavior

Start from what could go wrong:

- **Whitespace-only titles are accepted:** a public validation function can prove its rule quickly.
- **The title is sent under the wrong property:** exercise the outgoing request boundary.
- **Save is disconnected from the form:** render the actual UI and use its controls.
- **Enter, focus, or a narrow layout fails:** use the browser's real behavior.
- **The deployed server rejects the client's request:** a substituted response cannot answer that; exercise or otherwise verify the real provider agreement.

“Smallest” does not mean “fewest classes.” A page and editor together may be the smallest useful boundary for proving that an emitted confirmation updates accepted data.

Nor does it mean testing every behavior at every level. Check a detailed title rule close to its public function. Keep a UI check that proves invalid submission reaches that rule and sends nothing. They protect different risks; copying the whole validation matrix into browser tests would add cost without necessarily adding evidence.

For this example, save `task.ts`:

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

`trim()` produces a new string without whitespace at either end. `===` compares values without converting their types; `""` is an empty string. `undefined` here deliberately means “no acceptable title,” not a title to store.

A public function's consumers call it directly, so a direct call is exactly the right interface in `task.spec.ts`:

```ts
import { expect, it } from "vitest";
import { normalizeTitle } from "./task";

it("rejects a title made only of whitespace", () => {
  const result = normalizeTitle("   ");

  expect(result).toBeUndefined();
});

it("returns meaningful text without surrounding whitespace", () => {
  const result = normalizeTitle("  Review the task contract  ");

  expect(result).toBe("Review the task contract");
});
```

The expected string is chosen independently. Computing it by calling `normalizeTitle` again would make the test agree with the same bug twice.

## Give the example a real consumer

The page owns the accepted task. The editor owns unfinished text. Only a confirmed save crosses back into accepted state:

```text
Page's accepted Task → editor input → separate title draft
                                        │
Native input event → update draft       │
Native submit → validate → save operation
                              ├── failure: keep draft and accepted task
                              └── confirmation → saved output → page accepts Task
Cancel → restore draft from accepted Task; do not save
```

The examples use Angular's current signal APIs and Vitest-style tests. New Angular CLI projects use Vitest with jsdom by default; existing projects can have a different supported setup. **jsdom** supplies DOM objects in Node.js without a browser layout engine. This article assumes an already configured Angular test workspace, plus `@testing-library/dom` for role/label queries, and a separate configured Playwright project for browser checks. It is not a runner installation or migration guide.

A **signal** holds a value and notifies Angular when it changes. Calling it, as in `busy()`, reads the value. An input supplies data or an operation to a component; an output reports an event to its consumer.

Save this smaller editor in `task-editor.ts`:

Saving may finish later, rather than during the initial submit event. A **Promise** represents that operation's eventual success value or rejection (failure). An `async` function also returns a promise for its eventual result. Here, `await` pauses only the save function until the operation succeeds or fails; it does not freeze the browser. A rejected promise makes `await` throw into the surrounding `catch`, which shows failure feedback. The `finally` block runs after either outcome and restores the paused controls.

```ts
import {
  Component,
  Injector,
  afterNextRender,
  inject,
  input,
  linkedSignal,
  output,
  signal,
} from "@angular/core";
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
        name="title"
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
      <p role="status" aria-atomic="true">{{ status() }}</p>
    </form>
  `,
})
export class TaskEditor {
  readonly task = input.required<Task>();
  readonly persist = input.required<(id: number, title: string) => Promise<Task>>();
  readonly saved = output<Task>();
  readonly busy = signal(false);
  readonly titleError = signal("");
  readonly status = signal("");
  private readonly injector = inject(Injector);

  readonly draftTitle = linkedSignal<Task, string>({
    source: this.task,
    computation: (task, previous) => {
      if (previous?.source.id === task.id) {
        return previous.value;
      }

      return task.title;
    },
  });

  async save(event: SubmitEvent, titleInput: HTMLInputElement) {
    event.preventDefault();
    if (this.busy()) {
      return;
    }

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
      afterNextRender(() => titleInput.focus(), { injector: this.injector });
    }
  }

  cancel(titleInput: HTMLInputElement) {
    if (this.busy()) {
      return;
    }

    this.draftTitle.set(this.task().title);
    this.titleError.set("");
    this.status.set("Edits cancelled. Saved task unchanged.");
    titleInput.focus();
  }
}
```

The draft starts after Angular supplies the required task input. `previous?.source.id` reads the prior ID only when a prior value exists. For the same ID, the computation keeps unfinished text. Save and Cancel explicitly reset that text instead of relying on an input replacement to erase it.

`novalidate` turns off automatic native validation feedback; it does not stop navigation. `preventDefault()` does that separately. The application then supplies its nonblank rule, error, association, and correction path. A native form with a submit button also supports Enter from the title input. Cancel is `type="button"` so it does not accidentally submit.

The label gives the input its name. `aria-describedby` supplies additional help/error descriptions. `aria-invalid` reports a shown failure, while the status region provides changing save feedback. These jobs are distinct; an error message must not replace the label. See [accessibility in practice](/dump/blog/accessibility-in-practice/) for the broader checks.

The editor stays mounted. Cancel means restoring the **current accepted title**, not closing a dialog. While saving, edits and Cancel are paused; a second submission is blocked. The callback promises a confirmed task or a rejected promise. This small example presents any save-operation rejection as “not saved,” without diagnosing a network cause. It has no competing writer, task switching during a request, or automatic retry.

## Exercise the interface instead of bypassing it

For a UI contract, calling `fixture.componentInstance.save(...)` skips the question “Can the consumer reach this operation?” The handler could work perfectly while its template binding is missing.

Likewise, manually emitting `saved` bypasses the path that should produce the confirmation. Such a test may check a parent's output listener, but it cannot prove that Save reaches it.

Instead, supply the public inputs, enter text through the rendered control, submit, and inspect consumer-visible results. Prefer a control's role and name, its associated label, or an explicit testing contract over selectors tied to CSS nesting. An accessible name is the identifying text exposed with a control; “Save task” is this button's name.

The page uses the HTTP operation below. Save `task-page.ts`:

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
      <section aria-labelledby="accepted-heading">
        <h2 id="accepted-heading">Accepted task</h2>
        <p data-testid="saved-title">{{ task().title }}</p>
      </section>
      <h2>Edit task</h2>
      <task-editor [task]="task()" [persist]="persist" (saved)="task.set($event)"></task-editor>
    </main>
  `,
})
export class TaskPage {
  readonly task = signal<Task>({ id: 41, title: "Read the DOM article" });
  readonly persist = inject(TaskGateway).save;
}
```

The `saved-title` test ID names a deliberate inspection point for accepted data. It is not a substitute for a label or accessible name. Moving that paragraph into a harmless wrapper should not break the test.

## Control the dependency, not the whole behavior

To test save failure, we need a save operation that reliably fails. We do not need a failing live server. A small replacement can accept the same arguments and return a rejected promise. The real page, editor, validation, input events, and output binding still run.

This is a **test double**: a substitute for a dependency. People use terms such as fake, stub, mock, and spy with different conventions. Here the replacement controls the answer; `vi.fn` also records its calls so the test can inspect the public save request. It does not replace the UI behavior we want to prove.

Save this component/integration check in `task-page.spec.ts`:

```ts
import { TestBed } from "@angular/core/testing";
import { getByLabelText, getByRole, getByTestId, waitFor } from "@testing-library/dom";
import { expect, it, vi } from "vitest";
import { TaskGateway } from "./task-gateway";
import { TaskPage } from "./task-page";

it("keeps the entered title and accepted task when saving fails", async () => {
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
  const acceptedTitle = getByTestId(view, "saved-title");
  const feedback = getByRole(view, "status");

  titleInput.value = "Review the task contract";
  titleInput.dispatchEvent(new Event("input", { bubbles: true }));
  saveButton.click();
  await waitFor(
    () => {
      expect(feedback.textContent).toBe("Not saved. Your draft is kept. Try Save again.");
    },
    { container: view },
  );

  expect(save).toHaveBeenCalledExactlyOnceWith(41, "Review the task contract");
  expect(titleInput.value).toBe("Review the task contract");
  expect(acceptedTitle.textContent).toBe("Read the DOM article");
});
```

`TestBed` creates Angular components with their real templates in the test environment. A **fixture** gives the test access to that rendered instance and its view. `whenStable()` waits for Angular's tracked work and scheduled rendering; it is not a promise that every unrelated external operation has finished. After submission, Testing Library's `waitFor` reruns the assertion until the rendered failure message appears or its deadline is reached. Waiting does not weaken the expected result.

The input's `value` property changes the DOM control. Assigning it alone does not run Angular's input listener. Dispatching the `input` event supplies that missing step. Clicking the submit button then exercises the form binding instead of calling its handler.

The call assertion protects the data leaving the UI, not private helper choreography. The other assertions protect the person's draft, accepted state, and actionable feedback. Checking only the call would miss a regression that sends the right data and then clears the draft on failure.

This substitute proves how the client behaves **given that answer**. It cannot prove a real server will produce the same answer.

### Choose meaningful alternatives

For this editor, keep these risks explicit:

| Situation                         | Contract to protect                                                                                 |
| --------------------------------- | --------------------------------------------------------------------------------------------------- |
| Save succeeds                     | Send the normalized title; display the returned confirmation as accepted data and as the new draft. |
| Title is blank or whitespace-only | Show correction guidance; send no save request; keep accepted data.                                 |
| Save fails                        | Keep entered text and accepted data; show retry guidance and unlock the controls.                   |
| Cancel after editing              | Restore the latest accepted title; send no request and do not mutate the saved task.                |

For success, return a deliberately different confirmed title, such as “Review the confirmed contract.” That catches code which assumes the receiver accepted the draft unchanged. For Cancel, test after a successful save too: restoring the original sample instead of the latest accepted value would be wrong.

These alternatives are selected because they distinguish useful promises, not because four is a required test count.

## Check the HTTP boundary separately

The UI replacement hides how the save operation constructs an HTTP request. We need another boundary to protect that agreement.

Save `task-gateway.ts`:

```ts
import { HttpClient } from "@angular/common/http";
import { Injectable, inject } from "@angular/core";
import { firstValueFrom } from "rxjs";
import type { Task } from "./task";

@Injectable({ providedIn: "root" })
export class TaskGateway {
  private readonly http = inject(HttpClient);

  readonly save = async (id: number, title: string): Promise<Task> => {
    const response = this.http.put<unknown>(`/api/tasks/${id}`, { title });
    const incoming = await firstValueFrom(response);

    const isRecord = typeof incoming === "object" && incoming !== null;
    if (!isRecord) {
      throw new Error("Invalid task confirmation");
    }
    if (!("id" in incoming) || !("title" in incoming)) {
      throw new Error("Invalid task confirmation");
    }
    if (typeof incoming.title !== "string") {
      throw new Error("Invalid task confirmation");
    }
    const matchesTask = incoming.id === id;
    const hasTitle = incoming.title.trim() !== "";
    if (!matchesTask || !hasTitle) {
      throw new Error("Invalid task confirmation");
    }

    return { id, title: incoming.title };
  };
}
```

`HttpClient` describes a response-producing operation; the request starts when something subscribes to it. `firstValueFrom` does that subscription and gives us a promise for the first response, which `await` can read. A failed HTTP operation rejects that promise. No stream-processing knowledge is needed here.

`unknown` means the incoming value has no trusted shape yet. `typeof` asks what kind of JavaScript value arrived; `in` checks whether a property exists. The checks establish an object, the required properties, the matching ID, and a nonblank string. The type check runs before calling `trim()`. `!==` means unequal without type conversion. `&&` requires both conditions and skips its right side when the left side is false. `||` accepts either condition, and `!` negates a boolean. These are literal JavaScript operators, not special testing syntax.

A TypeScript response type alone would not validate external JSON. This bounded confirmation contract accepts additional properties and preserves the receiver's title exactly. A malformed confirmation rejects client acceptance; it does **not** prove that a real receiver stored nothing.

Angular's `HttpTestingController` captures actual `HttpClient` requests and supplies controlled responses without sending them to a server. In `task-gateway.spec.ts`:

```ts
import { provideHttpClient } from "@angular/common/http";
import { HttpTestingController, provideHttpClientTesting } from "@angular/common/http/testing";
import { TestBed } from "@angular/core/testing";
import { expect, it } from "vitest";
import { TaskGateway } from "./task-gateway";

it("sends the edit and returns the confirmed title", async () => {
  TestBed.configureTestingModule({
    providers: [provideHttpClient(), provideHttpClientTesting()],
  });
  const gateway = TestBed.inject(TaskGateway);
  const http = TestBed.inject(HttpTestingController);

  const saving = gateway.save(41, "Review the task contract");
  const request = http.expectOne({ method: "PUT", url: "/api/tasks/41" });
  expect(request.request.body).toEqual({ title: "Review the task contract" });

  request.flush({ id: 41, title: "Review the confirmed contract" });
  const confirmed = await saving;
  expect(confirmed).toEqual({ id: 41, title: "Review the confirmed contract" });
  http.verify();
});
```

`provideHttpClient()` comes before `provideHttpClientTesting()` so the testing backend overrides the normal backend, not the other way around. `expectOne` requires one matching request; `flush` supplies its response. `verify` checks that no unmatched requests remain. In a suite, put that verification in `afterEach` so it runs even when another assertion fails.

Do not await `saving` before supplying the response: the operation is waiting for the very answer the test controls. Add failure and malformed-response checks where they protect the real contract. A component test using this backend can also prove the path from Save through the real gateway and back to the rendered result.

None of this proves deployed compatibility, authorization, or storage. Real-provider contract evidence needs the provider to participate—for example, exercising the supported request against a controlled server and checking its actual response.

## Wait for the result you actually inspect

A click can finish before a request does. A response can arrive before Angular updates the screen. Inspecting too early can produce intermittent failures, or a false pass against old content.

Use synchronization appropriate to the operation:

1. Trigger the public interaction.
2. If the test owns the response, observe the pending request and supply that response.
3. Await the operation or the framework's supported stabilization as appropriate.
4. Inspect the rendered outcome, not merely the start of the operation.

A promise created outside Angular's tracking may need to be explicitly resolved and awaited before waiting for the fixture. An assertion against a browser view should use the runner's retrying view assertions, shown next.

Do not replace that relationship with “sleep for 500 ms.” A fast machine wastes time; a slower machine can still be unfinished. A condition-based wait has a deadline but finishes as soon as the required result appears. Blindly retrying an entire failing test also does not explain why it was unreliable.

Isolation matters too. Each test needs its own initial task, dependency behavior, and pending operations. Angular's normal test-environment teardown disposes fixtures between tests. Playwright supplies a fresh browser context—separate cookies and browser storage—for each test. Neither automatically resets data in a real shared server. Arrange that data explicitly; do not require the success test to run before the Cancel test.

## Use the browser where the browser matters

An emulated DOM can test bindings, events, and text. It cannot demonstrate actual layout, native keyboard submission, visible focus, or whether a person can reach controls at a narrow viewport.

A real browser test adds those mechanisms. It still needs a declared boundary. Here the actual Angular frontend runs, while Playwright substitutes **only** the save response. The page starts from its local sample task; there is no backend or persistence evidence.

To run the consumer in an existing Angular application, bootstrap `TaskPage` with `provideHttpClient()` in the application's providers. Use `<task-page></task-page>` in the browser-parsed host document; custom-element hosts need closing tags. Apply the existing application's styling and dark/light palette. The examples intentionally add no new CSS framework or test platform.

With that page served at `/tasks` and a Playwright `baseURL` pointing to the application's test server, save `task-workflow.spec.ts`:

```ts
import { expect, test } from "@playwright/test";

test("Save accepts the response, not an assumed copy of the draft", async ({ page }) => {
  await page.route("**/api/tasks/41", async (route) => {
    const request = route.request();
    const payload: unknown = request.postDataJSON();
    expect(request.method()).toBe("PUT");
    expect(payload).toEqual({ title: "Review the task contract" });
    await route.fulfill({
      status: 200,
      json: { id: 41, title: "Review the confirmed contract" },
    });
  });
  await page.goto("/tasks");

  const titleInput = page.getByLabel("Task title (required)");
  const saveButton = page.getByRole("button", { name: "Save task", exact: true });
  const acceptedTitle = page.getByTestId("saved-title");
  const feedback = page.getByRole("status");

  await titleInput.fill("  Review the task contract  ");
  await saveButton.click();

  await expect(feedback).toHaveText("Task saved.");
  await expect(acceptedTitle).toHaveText("Review the confirmed contract");
  await expect(titleInput).toHaveValue("Review the confirmed contract");
});
```

`fill` changes the control and sends input events. The locator identifies what to interact with without fixing a CSS path. `await expect(...).toHaveText(...)` retries until the view has the expected text or the assertion's deadline is reached. Awaiting only `click()` would not wait for the saved result.

For failure, substitute an error response and assert the preserved draft after visible failure feedback. For invalid input and Cancel, assert no save request alongside their completed visible outcomes. A no-request check made before the interaction has finished says little.

Use native keyboard checks as well: Enter from the title should submit; Tab should reach the buttons; Space on Cancel should cancel without submitting. Test real focus after validation, failure, and completion. A role query finding a button is useful evidence about that control's semantics, not proof that the whole feature is accessible.

Where appearance matters, inspect long titles, both themes, a measured 320 CSS-pixel viewport, and larger text separately from browser zoom. Accessibility automation can find some problems, but does not establish useful announcements, all keyboard behavior, or conformance. A screenshot alone also cannot prove the save contract.

## Judge a test by its future feedback

A passing test says that its assertions held for its inputs, dependencies, and environment. To learn whether it detects the intended regression, deliberately break that promise in a temporary copy:

- Disconnect the form's Save binding. The public-control test should fail because no save occurs or no result appears.
- Apply the draft instead of the returned confirmation. The success test should report the wrong accepted title.
- Clear the draft on failure. The failure test should report the lost text.
- Rename an internal field without changing behavior. These tests should still pass.

This deliberate-breakage check is often called **mutation testing**: change the implementation and see whether a test detects it. You do not need an all-purpose mutation framework to check a concrete suspicion.

**Coverage** measures which code was executed during tests. Executing a failure branch without asserting draft preservation can produce coverage while missing the very bug we care about. Coverage can identify unvisited areas to investigate; it cannot choose the contract or prove that assertions are adequate.

Useful failures should explain the missing promise. Keep setup small enough to understand the initial state, use independent expected values, and name tests after outcomes. Prefer “keeps the entered title when saving fails” to “calls helper three times.” Remove or rewrite tests whose maintenance cost exceeds their regression protection; more passing tests is not automatically better feedback.

## Closing check

Before keeping a test, answer three questions:

1. **Which consumer contract is protected?** Name the input, interaction, result, and relevant failure alternative.
2. **What change should make this test fail?** A broken binding, wrong payload, lost draft, or incorrect confirmation—not a harmless internal rename.
3. **What does a pass prove, and what can't it prove?** A controlled HTTP answer proves client behavior under that answer, not a working backend; an emulated DOM proves neither layout nor native browser usability.

Choose the boundary that makes those answers concrete. Exercise its real interface, control only the dependencies you need to control, and let harmless implementation changes remain harmless.

## Sources and further reading

- [Angular: testing overview and supported environments](https://angular.dev/guide/testing)
- [Angular: basics of testing components](https://angular.dev/guide/testing/components-basics)
- [Angular: component testing scenarios](https://angular.dev/guide/testing/components-scenarios)
- [Angular: testing HTTP requests](https://angular.dev/guide/http/testing)
- [Testing Library: waiting for asynchronous results](https://testing-library.com/docs/dom-testing-library/api-async/)
- [Playwright: test user-visible behavior](https://playwright.dev/docs/best-practices)
- [Playwright: locators and their limits](https://playwright.dev/docs/locators)
- [Playwright: retrying assertions](https://playwright.dev/docs/test-assertions)
- [Playwright: browser-context isolation](https://playwright.dev/docs/browser-contexts)
- [Playwright: network substitution](https://playwright.dev/docs/network)
