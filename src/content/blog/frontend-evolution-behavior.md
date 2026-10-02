---
title: "From changing elements to managing application state"
description: "Follow the same task interface through native JavaScript, jQuery, and Angular to see what each simplifies, who coordinates updates, and what an SPA adds."
pubDate: "2026-10-02"
tags:
  - javascript
  - jquery
  - angular
  - frontend
---

A task's checkbox is checked, but the remaining count still includes it. The Active filter still shows it too. The individual operations worked; the interface as a whole disagrees with itself.

This is a useful way to understand frontend evolution. The question is not just “How do we make clicking work?” It is also:

> When one action affects several parts of the interface, who keeps them consistent?

We will reuse the task interface from [HTML, the DOM, and events](/dump/blog/html-dom-and-events/). First we will change elements directly, then use jQuery, then describe the interface with Angular. The [values and identity article](/dump/blog/values-references-and-identity/) explains the shared objects behind these updates.

Here, **native** means using operations provided directly by the browser, without adding a DOM library. This is not a replacement ladder: native JavaScript is not inherently disorganized, jQuery is not an application-state framework, and using Angular does not automatically mean building a single-page application.

## Contents

1. [The browser already provides behavior](#the-browser-already-provides-behavior)
2. [Direct DOM code gives concrete instructions](#direct-dom-code-gives-concrete-instructions)
3. [jQuery simplifies browser operations](#jquery-simplifies-browser-operations)
4. [More behavior creates a coordination problem](#more-behavior-creates-a-coordination-problem)
5. [Describe the relationship between state and view](#describe-the-relationship-between-state-and-view)
6. [An SPA expands what the client owns](#an-spa-expands-what-the-client-owns)
7. [Compare responsibilities, not winners](#compare-responsibilities-not-winners)

## The browser already provides behavior

Before an application framework runs, the browser already knows how to do many things:

- Follow a link to another document.
- Let someone type into an input and operate it with the keyboard.
- Change a checkbox's checked state when it is activated.
- Validate and submit a form according to its HTML.

A server can send a page containing links and forms, receive a submitted request, save data, and respond with another page. That is an interactive application, even without client-side Angular, React, or jQuery.

**Server-generated** means that the server produces the HTML before sending it. It does not mean that the resulting page cannot respond to interaction.

JavaScript can enhance one part of that arrangement. For example, it can handle a task form without replacing the document. It need not take responsibility for navigation or every other element on the page.

### One interface, several related results

Our example will support four operations:

1. Add a task.
2. Mark a task complete or active again.
3. Show all, active, or completed tasks.
4. Display how many tasks remain active, regardless of the selected filter.

Here is the shared HTML for the native JavaScript and jQuery versions. The Angular version will describe the equivalent structure in its template.

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Task notes</title>
  </head>
  <body>
    <main>
      <h1>Task notes</h1>

      <form id="task-form" method="get">
        <label for="task-title">Task title</label>
        <input id="task-title" name="title" type="text" required />
        <button type="submit">Add task</button>
      </form>

      <label for="task-filter">Show tasks</label>
      <select id="task-filter">
        <option value="all">All</option>
        <option value="active">Active</option>
        <option value="completed">Completed</option>
      </select>

      <p id="remaining-count" aria-live="polite"></p>
      <ul id="task-list" role="list"></ul>
      <p id="empty-message">No tasks to show.</p>
    </main>
    <!-- Load one implementation here, after the controls. -->
  </body>
</html>
```

The labels name the controls. Each generated row will contain a checkbox inside a label with the task title. The remaining count is a polite live region: assistive tools can announce its changes without interrupting the current announcement.

The examples have no backend and do not save across reloads. Without their submit handler, this form can make a normal GET request, but there is no server here implementing task creation. Native form submission is a browser capability, not proof that a particular endpoint saves data.

The first two short scripts below intentionally implement only one row. The complete versions follow later. Try each script separately with fresh HTML; do not load all implementations into one page.

## Direct DOM code gives concrete instructions

To create one task row, we can ask the browser to make the elements and attach a listener:

```js
const task = { title: "Read the DOM article", done: false };
const list = document.querySelector("#task-list");
const remainingCount = document.querySelector("#remaining-count");

const row = document.createElement("li");
const label = document.createElement("label");
const checkbox = document.createElement("input");
checkbox.type = "checkbox";

const title = document.createElement("span");
title.textContent = task.title;

label.append(checkbox, " ", title);
row.append(label);
list.append(row);
remainingCount.textContent = "Remaining tasks: 1";

checkbox.addEventListener("change", () => {
  task.done = checkbox.checked;
});
```

Follow the operations:

1. `querySelector` finds existing elements.
2. `createElement` creates new DOM elements that are not yet in the page.
3. Assigning `textContent` puts the title into a text node, not an HTML fragment.
4. `append` connects the new elements to each other and to the list. The space string becomes text between the checkbox and title.
5. The listener reads the checkbox's current `checked` property and writes it into the task object.

The browser itself changes the checkbox when activated. Our handler copies that choice into application data.

These are **imperative** instructions: create this element, put this text in it, attach this handler, and insert this row. Imperative means that the code specifies operations to perform.

There is nothing inherently wrong with this. A small enhancement can be easy to read and maintain using ordinary browser APIs.

But this script already has a deliberate omission: checking the task changes `task.done`, yet the count still says one task remains. The filter and empty message are not wired up either. Creating the row is not the same as implementing the complete interaction.

## jQuery simplifies browser operations

Historically, developers faced differences in browser APIs and behavior as well as repetitive DOM work. jQuery offered a common, convenient way to select elements, change them, handle events, and make background requests.

An **API** is the set of operations a library exposes for other code to call. jQuery's `$` function is an entry point into its API. A selector such as `$("#task-list")` returns a jQuery object wrapping the matched DOM elements, with methods for operating on them.

Here is the same intentionally incomplete row example using jQuery:

```js
const task = { title: "Read the DOM article", done: false };
const $list = $("#task-list");
const $remainingCount = $("#remaining-count");

const $row = $("<li>");
const $label = $("<label>");
const $checkbox = $("<input>").prop("type", "checkbox");
const $title = $("<span>").text(task.title);

$label.append($checkbox, " ", $title);
$row.append($label);
$list.append($row);
$remainingCount.text("Remaining tasks: 1");

$checkbox.on("change", () => {
  task.done = $checkbox.prop("checked");
});
```

Here, `$` followed by an HTML string such as `"<li>"` creates an element rather than selecting an existing one. The `$` at the start of a variable name is only a naming convention reminding us that the value is a jQuery wrapper.

The methods express familiar operations:

- `.text(...)` sets text content.
- `.prop(...)` reads or writes a DOM property, such as the checkbox's current checked state.
- `.on(...)` registers an event handler.
- `.append(...)` inserts content.

The shorter element-creation and manipulation calls reduce some repetitive work. They do not create a new relationship between `task.done` and the count. The count is still wrong after completion because our application never told jQuery to change it.

### Convenience is not application-state ownership

jQuery's capabilities also include Ajax and an extension mechanism. **Ajax** refers to background requests made by JavaScript without a full document navigation; it does not require the response to be XML despite the historical name.

Plugins can build extra behavior around jQuery. A date picker supplied by another library is not the same thing as jQuery itself. Its state and cleanup rules depend on that library.

Neither convenient selection nor a request helper decides:

- Which object represents a task.
- Whether completing it changes the count.
- Whether it remains visible under the Active filter.
- How to handle an unsuccessful save.

Those are application responsibilities. jQuery can help carry out the operations, but it does not automatically observe our task object and maintain all related DOM values.

For the runnable examples, the checked baseline is jQuery 4.0.0. Older applications may use other versions with different browser support and available APIs. A historical compatibility benefit is not a promise that today's release supports every old browser.

## More behavior creates a coordination problem

Return to the checkbox. A completed task affects at least three visible results:

```text
checkbox activation
       ↓
task.done changes
       ├──→ row checkbox reflects completion
       ├──→ remaining count excludes this task
       └──→ Active filter no longer shows this row
```

Updating only one result leaves the interface inconsistent. As adding, deleting, or editing gains more entry points, scattered update instructions become easier to miss.

This is a coordination problem, not necessarily a DOM-API problem. Writing the same incomplete handler with fewer characters does not repair it.

### Give each value an owner

A **source of truth** is the representation we treat as authoritative for a particular value. Other representations are derived from it rather than competing with it.

Different arrangements can work:

- A small interface can derive its count from the checkbox states in the DOM.
- Another can keep task data in JavaScript and derive rows and counts from that data.
- A form can keep its unsaved input text in a native control while accepted tasks live in application data.

The last is an intentional combination, not automatically a design flaw. Ownership must be clear for each value; it need not mean putting every bit of browser interaction state into one global store.

Our complete examples use task records and the selected filter as application state. The text being entered remains in the input until submitted. Completing a checkbox updates its task record before rendering the related results.

### Centralize rendering without a framework

We can solve the missing-update problem in plain JavaScript. Let handlers change state and call one `render()` function that applies the relevant rules.

A **Map** stores values under keys. Here, a map connects each task ID to its existing row and checkbox. It is a cache of DOM references, not a competing copy of the task data.

This complete native implementation replaces the earlier short script:

```js
const form = document.querySelector("#task-form");
const titleInput = document.querySelector("#task-title");
const filterSelect = document.querySelector("#task-filter");
const list = document.querySelector("#task-list");
const remainingCount = document.querySelector("#remaining-count");
const emptyMessage = document.querySelector("#empty-message");

const tasks = [];
const rows = new Map();
let nextId = 1;
let filter = "all";

function createRow(task) {
  const element = document.createElement("li");
  const label = document.createElement("label");
  const checkbox = document.createElement("input");
  checkbox.type = "checkbox";
  const title = document.createElement("span");
  title.textContent = task.title;

  label.append(checkbox, " ", title);
  element.append(label);

  checkbox.addEventListener("change", () => {
    task.done = checkbox.checked;
    render();

    if (element.hidden) {
      filterSelect.focus();
    }
  });

  return { element, checkbox };
}

function render() {
  let remaining = 0;
  let visibleCount = 0;
  filterSelect.value = filter;

  for (const task of tasks) {
    let row = rows.get(task.id);
    if (row === undefined) {
      row = createRow(task);
      rows.set(task.id, row);
      list.append(row.element);
    }

    if (!task.done) {
      remaining += 1;
    }

    let visible = true;
    if (filter === "active") {
      visible = !task.done;
    } else if (filter === "completed") {
      visible = task.done;
    }

    row.checkbox.checked = task.done;
    row.element.hidden = !visible;
    if (visible) {
      visibleCount += 1;
    }
  }

  remainingCount.textContent = "Remaining tasks: " + remaining;
  emptyMessage.hidden = visibleCount > 0;
}

titleInput.addEventListener("input", () => {
  titleInput.setCustomValidity("");
});

form.addEventListener("submit", (event) => {
  event.preventDefault();
  const title = titleInput.value.trim();

  if (title === "") {
    titleInput.setCustomValidity("Enter a task title, not just spaces.");
    titleInput.reportValidity();
    return;
  }

  const task = { id: nextId, title, done: false };
  nextId += 1;
  tasks.push(task);
  render();

  titleInput.value = "";
  titleInput.focus();
});

filterSelect.addEventListener("change", () => {
  const value = filterSelect.value;
  if (value !== "all" && value !== "active" && value !== "completed") {
    throw new Error("Unknown task filter");
  }

  filter = value;
  render();
});

render();
```

The renderer recalculates the remaining count from **all** tasks, then decides which rows the filter shows. Switching filters does not change how many tasks remain to be done.

Rows are created once and reused. Updating their properties avoids replacing the whole list after every interaction. In particular, a checkbox keeps its DOM identity while its row remains visible.

When completing a task hides its focused row, the handler moves focus to the filter rather than leaving someone on a disappearing control. This is part of the interaction, not a styling choice.

The form still uses browser validation. `trim()` removes surrounding whitespace. A spaces-only title is rejected through the browser's `setCustomValidity` and `reportValidity` operations; editing the input clears that custom error so the next attempt can be validated again.

Task titles go through `textContent`, so a title containing `<em>text</em>` is displayed as that text rather than treated as new HTML. State coordination does not remove the need to handle user input safely.

The native renderer hides rows through `hidden` using the default HTML layout. If you later add CSS that explicitly sets a row's `display`, preserve the hiding behavior too; an author style can override the browser's default `[hidden]` styling.

This is a small renderer owned by our application, not a new general-purpose rendering framework. It handles the operations we implemented. Adding task deletion would require removing the corresponding rows and references; adding title editing would require refreshing the title text.

### The same coordination with jQuery

jQuery can implement the same arrangement. Save this complete version as `tasks.js` and use it instead of the native script:

```js
const $form = $("#task-form");
const $titleInput = $("#task-title");
const $filterSelect = $("#task-filter");
const $list = $("#task-list");
const $remainingCount = $("#remaining-count");
const $emptyMessage = $("#empty-message");

const tasks = [];
const rows = new Map();
let nextId = 1;
let filter = "all";

function createRow(task) {
  const $element = $("<li>");
  const $label = $("<label>");
  const $checkbox = $("<input>").prop("type", "checkbox");
  const $title = $("<span>").text(task.title);

  $label.append($checkbox, " ", $title);
  $element.append($label);

  $checkbox.on("change", () => {
    task.done = $checkbox.prop("checked");
    render();

    const rowHidden = $element.prop("hidden");
    if (rowHidden) {
      $filterSelect[0].focus();
    }
  });

  return { $element, $checkbox };
}

function render() {
  let remaining = 0;
  let visibleCount = 0;
  $filterSelect.val(filter);

  for (const task of tasks) {
    let row = rows.get(task.id);
    if (row === undefined) {
      row = createRow(task);
      rows.set(task.id, row);
      $list.append(row.$element);
    }

    if (!task.done) {
      remaining += 1;
    }

    let visible = true;
    if (filter === "active") {
      visible = !task.done;
    } else if (filter === "completed") {
      visible = task.done;
    }

    row.$checkbox.prop("checked", task.done);
    row.$element.prop("hidden", !visible);
    if (visible) {
      visibleCount += 1;
    }
  }

  $remainingCount.text("Remaining tasks: " + remaining);
  $emptyMessage.prop("hidden", visibleCount > 0);
}

$titleInput.on("input", () => {
  $titleInput[0].setCustomValidity("");
});

$form.on("submit", (event) => {
  event.preventDefault();
  const title = $titleInput.val().trim();

  if (title === "") {
    $titleInput[0].setCustomValidity("Enter a task title, not just spaces.");
    $titleInput[0].reportValidity();
    return;
  }

  const task = { id: nextId, title, done: false };
  nextId += 1;
  tasks.push(task);
  render();

  $titleInput.val("");
  $titleInput[0].focus();
});

$filterSelect.on("change", () => {
  const value = $filterSelect.val();
  if (value !== "all" && value !== "active" && value !== "completed") {
    throw new Error("Unknown task filter");
  }

  filter = value;
  render();
});

render();
```

`.val()` reads or writes the input's value. `[0]` accesses the first native element wrapped by a jQuery object; we use it for native focus and validation operations. The wrapper and the DOM element are related, but are not the same object.

For the native version, save its script as `tasks.js` and load it at the marked position with `<script type="module" src="./tasks.js"></script>`.

For the jQuery version, place a downloaded jQuery 4.0.0 browser distribution beside the page as `jquery.min.js`. At the marked position, load `<script src="./jquery.min.js"></script>` before `<script type="module" src="./tasks.js"></script>`. The library must be available before code calls `$`.

The data model, update rules, and renderer still belong to our application. jQuery changes how we carry out browser operations, not who defines the relationship between completion, count, and visibility.

## Describe the relationship between state and view

Now consider what we want the interface to show:

- One row for each task matching the selected filter.
- A checkbox whose state matches that task's `done` value.
- A count derived from tasks that are not done.
- An empty message when there are no visible tasks.

Those descriptions can become rendering rules instead of being repeated as DOM writes in each event handler.

This is **declarative rendering**: describe the desired view for a given state, and let the rendering system carry out the DOM operations needed to produce it.

The **view** is the interface produced from that state. A **template** is a description of its structure and dynamic values. A **component** groups a piece of that description with its behavior and state behind a named boundary.

Declarative rendering does not mean that no imperative code runs. Angular still performs DOM operations, and our event handlers still contain ordinary instructions. The difference is who maintains the declared state-to-view relationships.

### An Angular task board

Before the full example, here is the template syntax we will use:

- `{{ remaining() }}` places a calculated value into text.
- `[checked]="task.done"` binds the checkbox's DOM property to a value.
- `(change)="..."` runs a handler when Angular receives that event.
- `@for (...; track task.id)` describes repeated rows and identifies them by task ID.
- `#titleInput` names a template reference to the native input, which a handler can use.

A **signal** holds a value and notifies consumers when a recognized change is written. `computed(...)` derives and caches a value from the signals it reads. Calling a signal, such as `tasks()`, reads its value; `.update(...)` uses a function's returned value as the next value. The previous article explains why these writes must respect [value identity](/dump/blog/values-references-and-identity/#connect-the-model-to-angular).

Here is the complete component, checked with Angular 22.2.1. Put it in `task-board.ts` in an Angular application:

```ts
import { Component, computed, signal } from "@angular/core";

type TaskFilter = "all" | "active" | "completed";

interface Task {
  id: number;
  title: string;
  done: boolean;
}

@Component({
  selector: "task-board",
  template: `
    <main>
      <h1>Task notes</h1>

      <form id="task-form" (submit)="addTask($event, titleInput)">
        <label for="task-title">Task title</label>
        <input
          #titleInput
          id="task-title"
          name="title"
          type="text"
          required
          (input)="titleInput.setCustomValidity('')"
        />
        <button type="submit">Add task</button>
      </form>

      <label for="task-filter">Show tasks</label>
      <select
        #filterSelect
        id="task-filter"
        [value]="filter()"
        (change)="setFilter(filterSelect.value)"
      >
        <option value="all">All</option>
        <option value="active">Active</option>
        <option value="completed">Completed</option>
      </select>

      <p id="remaining-count" aria-live="polite">Remaining tasks: {{ remaining() }}</p>
      <ul id="task-list" role="list">
        @for (task of visibleTasks(); track task.id) {
          <li>
            <label>
              <input
                #checkbox
                type="checkbox"
                [checked]="task.done"
                (change)="setDone(task, checkbox.checked, filterSelect)"
              />
              <span>{{ task.title }}</span>
            </label>
          </li>
        }
      </ul>
      <p id="empty-message" [hidden]="visibleTasks().length > 0">No tasks to show.</p>
    </main>
  `,
})
export class TaskBoard {
  readonly tasks = signal<Task[]>([]);
  readonly filter = signal<TaskFilter>("all");
  private nextId = 1;

  readonly remaining = computed(() => {
    let count = 0;
    for (const task of this.tasks()) {
      if (!task.done) {
        count += 1;
      }
    }
    return count;
  });

  readonly visibleTasks = computed(() => {
    const visible: Task[] = [];
    const filter = this.filter();

    for (const task of this.tasks()) {
      if (filter === "active" && task.done) {
        continue;
      }
      if (filter === "completed" && !task.done) {
        continue;
      }
      visible.push(task);
    }

    return visible;
  });

  addTask(event: Event, titleInput: HTMLInputElement): void {
    event.preventDefault();
    const title = titleInput.value.trim();

    if (title === "") {
      titleInput.setCustomValidity("Enter a task title, not just spaces.");
      titleInput.reportValidity();
      return;
    }

    const task: Task = { id: this.nextId, title, done: false };
    this.nextId += 1;
    this.tasks.update((current) => {
      return [...current, task];
    });

    titleInput.value = "";
    titleInput.focus();
  }

  setFilter(value: string): void {
    if (value !== "all" && value !== "active" && value !== "completed") {
      throw new Error("Unknown task filter");
    }
    this.filter.set(value);
  }

  setDone(taskToChange: Task, done: boolean, filterSelect: HTMLSelectElement): void {
    this.tasks.update((current) => {
      const next: Task[] = [];
      for (const task of current) {
        if (task.id === taskToChange.id) {
          next.push({ ...task, done });
        } else {
          next.push(task);
        }
      }
      return next;
    });

    const hideActiveTask = this.filter() === "active" && done;
    const hideCompletedTask = this.filter() === "completed" && !done;
    if (hideActiveTask || hideCompletedTask) {
      filterSelect.focus();
    }
  }
}
```

Here, `interface Task` describes each task's fields for TypeScript, and `TaskFilter` limits the filter's accepted values. `this` accesses the current component instance. `@Component` supplies Angular with the selector and template for that class.

To use this as an application's root component, import `bootstrapApplication` from `@angular/platform-browser` and `TaskBoard` from `./task-board` in its entry point, then call `await bootstrapApplication(TaskBoard);`. Bootstrapping means asking Angular to start the application and create its root component. The host page must contain `<task-board></task-board>`.

An existing application can instead import the component into its parent and use that element in the parent's template. This is component code for an Angular project, not a script to paste directly into the browser console.

### Follow one completion through the rules

When a checkbox changes:

1. The template's event binding calls `setDone` with the task and the checkbox's choice.
2. The method creates a new task array, replacing the changed task object while retaining the other task objects.
3. The signal write makes its derived values eligible to recalculate.
4. Angular evaluates the relevant template work and updates the count and rendered rows.

We did not write a selector to find the remaining-count paragraph or maintain a map of row elements. We declared the count in the template and identified the repeated rows with `track task.id`.

The ID connects a task to its rendered row even when the task is represented by a new object. That is the distinction between domain identity and object identity from the previous article. Angular can reuse a matching row rather than rebuilding the entire list.

The implementations need not retain the same hidden DOM. The native and jQuery examples keep filtered rows and hide them; Angular renders the matching collection and removes rows that leave it. The observable task behavior is the same, but the DOM bookkeeping differs.

Our handlers still decide which task changes, validate input, and move focus when the edited row disappears. Native focus and validation operations are legitimate browser integration. Declarative rendering is not a ban on every direct DOM operation; the important boundary is not manually rewriting the task rows and counts that Angular's template owns.

### Frameworks relocate work; they do not erase it

Angular takes responsibility for maintaining its declared text, property, event, and repeated-view relationships. The application still defines the task model, the filter rules, and what completion means.

Older approaches also separated data from presentation. In **Model–View–Controller (MVC)** arrangements, a controller coordinates input and changes between the data model and view. **Model–View–ViewModel (MVVM)** arrangements expose view-oriented values and actions through a view model—for example, a remaining count and an add-task action. The detailed patterns differ; the need to organize state and presentation did not begin with current Angular.

A component also has a **lifecycle**: it is created, updated, and eventually destroyed. Angular manages its own template-bound listeners and provides integration points for setup and destruction. Resources we create ourselves—such as timers or listeners on `window`—still need intentional cleanup.

That differs from our native and jQuery examples, whose handlers and caches live for the page's lifetime. If we turn them into widgets that are repeatedly mounted and removed within one document, we must design that lifecycle ourselves. Merely hiding a row does not release its listener or remove its map entry.

The framework's coordination comes with costs: dependencies, a build process, template syntax, lifecycle rules, and update semantics that the team must understand. Incorrect notification or shared-object handling can still produce stale views. See [Angular change detection](/dump/blog/angular-change-detection/) for those mechanics rather than treating a framework as a general-purpose observer of every assignment.

## An SPA expands what the client owns

So far, every version enhances one page. None needs a client router to add or complete a task.

A **single-page application (SPA)** keeps an application running in a document while application code handles navigation between its views. Instead of a normal link always replacing the document, a client router can interpret the destination and change the displayed application view.

These are separate choices:

- A **rendering library or framework** helps produce and update the interface.
- An **SPA architecture** gives the running client application responsibility for navigation and related behavior.

A framework can be used for one widget on an otherwise ordinary page. Conversely, client-side navigation can be implemented without Angular. “Framework,” “SPA,” and “client-side rendering” are not interchangeable names.

### Navigation creates more coordination work

Suppose the task board becomes one view among several. The application now needs decisions about:

- **URLs and history:** which state belongs in the address, and what Back or Forward should restore.
- **Loading and errors:** what happens while a destination's data is unavailable, or its request fails.
- **State lifetime:** what stays when leaving the board, and what starts fresh when returning.
- **Resources:** which listeners, subscriptions, and background operations must stop when their owner disappears.
- **Focus and page meaning:** where keyboard focus moves and how the title or navigation change is communicated.

These are not reasons to reject SPAs. They are responsibilities to own deliberately rather than assuming a rendering framework settles them automatically.

An SPA can also receive server-rendered initial HTML. Server rendering describes how that initial content is produced; client navigation describes what happens afterward. For static delivery, SSR, hydration, and hybrid arrangements, see [Where HTML comes from](/dump/blog/html-rendering-methods/).

## Compare responsibilities, not winners

The examples now implement the same task contract. Evaluate them by tracing responsibility.

### Native JavaScript

Our application owns the task records, filter rules, DOM-reference map, and renderer. Browser APIs perform the operations we request. A teammate can follow those ordinary instructions without learning a framework, but must maintain the relationships and any lifecycle we add.

Modern native selection and event APIs reduce some historical reasons for adding jQuery just to find elements and attach handlers. This does not make native code automatically simpler at every scale; the application's organization still matters.

### jQuery

The application owns the same model and coordination rules. jQuery supplies convenient browser operations and event handling. A teammate must understand both those methods and the application's renderer.

Existing plugins, integrations, and team knowledge can justify keeping it. Rewriting working code solely to remove a library is a different decision from selecting dependencies for a new feature. Shorter DOM statements are useful, but they do not replace a state-ownership design.

### Angular

The application owns the model, actions, and derived rules. Angular maintains the template's relationships to the DOM and manages the lifetime of its views and bindings.

A teammate must understand the component boundary, template syntax, signal updates, and the framework's integration rules. Those costs can pay off when the interface has enough repeated, interacting behavior. They do not make every isolated enhancement require a client application framework.

The important change is not “manual DOM became forbidden.” It is that rendering relationships and their maintenance acquired a different owner.

## Closing check

Can you explain these cases without ranking the tools?

1. A jQuery handler changes a task object, but the remaining count stays stale. What is missing?
2. A native JavaScript app has one renderer called after each state change. Does it need a framework merely to stay consistent?
3. Angular receives a new task array, but unchanged tasks reuse their IDs. Why does tracking IDs matter?
4. An Angular task widget sits inside an ordinary server-generated page. Does that make the whole site an SPA?
5. A client router removes a view with a running timer. Who must arrange the timer's cleanup?

Check your reasoning:

- A DOM convenience library does not automatically derive the count from our object. The application needs an update rule and a path that runs it.
- No. Centralized native rendering can be a sufficient coordination strategy; judge its maintenance cost for the actual feature.
- IDs connect domain tasks to their existing rendered rows even when object values change. They are not instructions to compare all fields.
- No. Framework rendering and client-side navigation are separate responsibilities.
- The resource's owner must integrate cleanup with the view's lifetime. A router transition does not make every arbitrary timer disappear automatically.

For the next feature, ask where its state lives, which outputs depend on it, and who keeps those outputs consistent. That explains more than a technology's age or a shorter code sample.

## Sources and further reading

- [jQuery: library overview](https://jquery.com/)
- [jQuery: event handlers with on](https://api.jquery.com/on/)
- [jQuery: DOM properties with prop](https://api.jquery.com/prop/)
- [jQuery: text content](https://api.jquery.com/text/)
- [jQuery: input values](https://api.jquery.com/val/)
- [jQuery: upgrading to 4.0 and its browser-support changes](https://jquery.com/upgrade-guide/4.0/)
- [Angular: template bindings](https://angular.dev/guide/templates/binding)
- [Angular: repeated views and tracking](https://angular.dev/guide/templates/control-flow)
- [Angular: signals and derived values](https://angular.dev/guide/signals)
- [Angular: component lifecycle and destruction](https://angular.dev/guide/components/lifecycle)
- [MDN: constraint validation](https://developer.mozilla.org/en-US/docs/Web/HTML/Guides/Constraint_validation)
- [MDN: the hidden attribute and display](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Global_attributes/hidden)
