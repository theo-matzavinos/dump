---
title: "From changing elements to managing application state"
description: "Build the same task list with native JavaScript, jQuery, and Angular to see who keeps the count, the rows, and the filter in agreement."
pubDate: "2026-10-02"
updatedDate: "2026-10-15"
tags:
  - javascript
  - jquery
  - angular
audience:
  - frontend
---

You check a task's checkbox, but the line above the list still says "Remaining tasks: 2". You switch the filter to Active, and the finished task is still there. Each piece of code did its own job: the checkbox changed, and the task object was updated. But nothing updated the count or the filtered list, so the page now disagrees with itself.

That bug runs through this whole article:

> When one action affects several parts of the interface, who keeps them consistent?

You'll build the same small task list three times: with the browser's own DOM methods, with jQuery, and with Angular. Each version fixes the bug, and each one puts the fixing code in a different place.

You'll need the basics from [HTML, the DOM, and events](/dump/blog/html-dom-and-events/): what an element, a property, and an event listener are. The Angular part also leans on [values, references, and identity](/dump/blog/values-references-and-identity/), and the text explains the one idea it borrows.

One note before you start. The three versions aren't a ladder where each tool replaces the last. Plenty of good code today is plain JavaScript, and plenty of working apps still run jQuery. The comparison shows what each tool takes off your plate and what it leaves on it. Here, **native** means using only what the browser provides, with no library added. The examples have no server, so nothing survives a reload. They were checked with jQuery 4.0.0 and Angular 22.2.1 in Chromium.

## Contents

1. [What the browser already does](#what-the-browser-already-does)
2. [Build one task row with DOM methods](#build-one-task-row-with-dom-methods)
3. [The same row with jQuery](#the-same-row-with-jquery)
4. [Keep the count, rows, and filter in agreement](#keep-the-count-rows-and-filter-in-agreement)
5. [Describe the view with Angular](#describe-the-view-with-angular)
6. [What Angular takes over, and what it doesn't](#what-angular-takes-over-and-what-it-doesnt)
7. [Where single-page applications fit](#where-single-page-applications-fit)
8. [Compare the three versions](#compare-the-three-versions)

## What the browser already does

Before you write any JavaScript, the browser already knows how to:

- Follow a link to another page.
- Let someone type into an input and move between controls with the keyboard.
- Check and uncheck a checkbox.
- Check a form's required fields and submit it.

A server can build a whole application from those pieces alone. It sends HTML with links and forms, receives each submitted form, saves the data, and answers with a new page. JavaScript can then improve one part of that page, for example by adding a task without loading a new page. It doesn't have to take over everything else.

### The task list you'll build

The example supports four operations:

1. Add a task.
2. Mark a task complete, or active again.
3. Show all, active, or completed tasks.
4. Show how many tasks are still active, whichever filter is selected.

Here's the HTML that the native and jQuery versions share. The Angular version describes the same structure in its template.

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
      <ul id="task-list"></ul>
      <p id="empty-message">No tasks to show.</p>
    </main>
    <!-- Load one implementation here, after the controls. -->
  </body>
</html>
```

What to notice:

- Each `<label>` names its control, so a screen reader says "Task title, edit text" instead of just "edit text".
- `aria-live="polite"` on the count asks screen readers to read out its new text when it changes, without interrupting what they're already reading. The [accessibility article](/dump/blog/accessibility-in-practice/) covers these live regions.
- Without any JavaScript, submitting this form reloads the same page with `?title=…` added to the address. No server here saves tasks, so each script below stops that submission and handles the new task itself.

## Build one task row with DOM methods

To create one task row, you ask the browser to make the elements and attach a listener:

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

1. `querySelector` finds an element that's already in the page.
2. `createElement` creates a new element that isn't in the page yet.
3. Assigning `textContent` puts the title in as plain text. If a title contains `<em>`, the page shows those characters instead of turning them into HTML.
4. `append` puts the new elements inside each other and finally inside the list. The `" "` string becomes a space between the checkbox and the title.
5. The listener reads the checkbox's `checked` property and copies it into the task object.

The browser checks and unchecks the box by itself. Your handler only copies that choice into your data.

Code like this is **imperative**: it lists the steps to perform. Create this element, put this text in it, attach this handler, insert this row. For a small enhancement, that's easy to read and maintain.

To try it, save the script as `tasks.js` next to the HTML file and replace the comment at the end of `<body>` with:

```html
<script type="module" src="./tasks.js"></script>
```

`type="module"` loads the file as a JavaScript module. A module runs after the browser has read the whole HTML document, so the elements the script looks for already exist, and its top-level variables stay inside that file instead of becoming globals. Chromium-based browsers refuse to load a module script into a page opened straight from disk (a `file://` address), so serve the folder with a small local server, such as `python3 -m http.server`, and open the address it prints.

Now check the box. `task.done` changes, but the count still says one task remains, and the filter does nothing yet. That gap is deliberate: creating a row isn't the same as implementing the whole interaction.

## The same row with jQuery

For years, browsers disagreed on DOM details, and the standard DOM methods were long-winded. jQuery gave developers one short, consistent way to find elements, change them, and handle events.

Everything goes through the `$` function. `$("#task-list")` finds the matching elements and returns a **jQuery object**: a wrapper around those elements with methods for changing them.

Here's the same incomplete row with jQuery:

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

What to notice:

- `$` with an HTML string such as `"<li>"` creates a new element instead of finding one.
- The `$` at the start of a variable name is only a naming habit. It reminds you that the value is a jQuery wrapper.
- `.text(...)` sets text content, `.prop(...)` reads or writes a DOM property such as `checked`, `.on(...)` adds an event handler, and `.append(...)` inserts content.

The code is shorter, but the count is still wrong after you check the box. Nothing told jQuery to change it. jQuery makes each DOM operation easier, but it doesn't decide:

- Which object represents a task.
- Whether completing a task changes the count.
- Whether the task stays visible under the Active filter.
- What happens when saving a task fails.

Those decisions belong to your application code, whichever tool carries out the DOM operations.

## Keep the count, rows, and filter in agreement

Go back to the checkbox. Completing one task affects at least three things on the page:

```text
checkbox activation
       ↓
task.done changes
       ├──→ row checkbox reflects completion
       ├──→ remaining count excludes this task
       └──→ Active filter no longer shows this row
```

Update only one of them and the page disagrees with itself. As you add more ways to change a task, such as deleting or renaming, you get more places where one of those updates can be forgotten. That's a coordination problem. Shorter DOM calls don't fix it.

### Pick one place to store each value

Right now, "is this task done?" lives in two places: the checkbox's `checked` property and `task.done`. If they can disagree, you have to decide which one to believe. The one you believe is the **source of truth**. Everything else, like the count or whether a row is visible, gets calculated from it.

Different choices can work. A tiny page could count the checked boxes in the DOM and skip the task objects entirely. What matters is that each value has exactly one place you read it from.

In the full examples:

- The task records and the selected filter live in JavaScript variables. They're the source of truth.
- The checkboxes, the rows' visibility, and the count text are calculated from them.
- The title someone is still typing stays in the input until they submit it. Only then does it become a task record.

### One render function for the whole list

You can fix the bug in plain JavaScript. Each handler changes the data, then calls one `render()` function that brings every affected part of the page up to date.

The complete native version replaces the short script. It comes in three pieces; put them in `tasks.js` in this order.

First, the elements, the state, and a function that creates one row:

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
```

What to notice:

- `tasks` and `filter` are the source of truth.
- A **Map** stores values under keys. `rows` maps each task ID to that task's `<li>` and checkbox, so `render()` can find an existing row instead of building a new one. It only remembers elements; it doesn't hold its own copy of the task data.
- The checkbox handler changes `task.done`, then calls `render()`. It doesn't touch the count or the filter itself.
- If completing a task hides its row (say the Active filter is selected), the checkbox that had keyboard focus disappears. The handler moves focus to the filter, so a keyboard user isn't left on a control that's gone.

Next, the function that brings the page up to date:

```js
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
```

What to notice:

- The count is calculated from **all** tasks, before the filter is applied. Switching filters doesn't change how many tasks remain.
- Each row is created once, the first time `render()` sees its task, and reused afterwards. So a checkbox stays the same element, and keeps keyboard focus, while its row is visible.
- Rows that the filter excludes stay in the list with the `hidden` attribute set, which the browser displays as `display: none`. If you later write CSS that sets `display` on the rows, that rule wins over `hidden`, so make sure hidden rows still disappear.

Last, the handlers for the form and the filter:

```js
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

What to notice:

- `event.preventDefault()` stops the browser's own form submission, the page reload described earlier.
- `required` already rejects an empty title, but a title of only spaces passes it. `trim()` removes the spaces around the text. If nothing is left, `setCustomValidity` marks the input invalid with that message and `reportValidity` shows the browser's usual validation bubble. Typing clears the message again, so the next attempt is checked from scratch.
- Every handler follows the same pattern: change `tasks` or `filter`, then call `render()`.

That pattern is the fix for the opening bug. `render()` is the only code that writes the count, the checkboxes, and which rows are visible, so they can't drift apart.

It's a small renderer written for these three operations, though. Deleting a task would need code that removes its row and its `rows` entry. Renaming one would need code that refreshes the title text.

### The jQuery version

jQuery can follow the same plan. The data, the `rows` map, and the order of operations stay identical. Here's `createRow` with jQuery:

```js
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
```

The rest of the script makes the same swaps:

| Native                                         | jQuery                                          |
| ---------------------------------------------- | ----------------------------------------------- |
| `document.querySelector("#task-list")`         | `$("#task-list")`                               |
| `row.checkbox.checked = task.done`             | `row.$checkbox.prop("checked", task.done)`      |
| `row.element.hidden = !visible`                | `row.$element.prop("hidden", !visible)`         |
| `remainingCount.textContent = text`            | `$remainingCount.text(text)`                    |
| `filterSelect.value` and `titleInput.value`    | `$filterSelect.val()` and `$titleInput.val()`   |
| `form.addEventListener("submit", handler)`     | `$form.on("submit", handler)`                   |
| `titleInput.reportValidity()`                  | `$titleInput[0].reportValidity()`               |

`.val()` reads an input's or select's value, and `.val(newValue)` writes it. jQuery has no methods for `setCustomValidity` and `reportValidity`, so the code calls them, and `focus()`, on the DOM element itself. `[0]` gets that element: the first DOM element inside the jQuery wrapper. The wrapper and the element are two different objects.

<details>
<summary>The complete jQuery <code>tasks.js</code></summary>

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

</details>

To run it, download the jQuery 4.0.0 browser build, save it next to the page as `jquery.min.js`, and load it before your script, because your code calls `$` as soon as it runs:

```html
<script src="./jquery.min.js"></script>
<script type="module" src="./tasks.js"></script>
```

So jQuery changes how each line talks to the browser. The data, the update rules, and `render()` are still your code, and you're still the one keeping the count, the checkboxes, and the visible rows in agreement.

## Describe the view with Angular

Look at what the page should show for any list of tasks:

- One row for each task that matches the selected filter.
- A checkbox that's checked when that task's `done` is `true`.
- A count of the tasks that aren't done.
- An empty message when no rows are visible.

In the native version, those rules are spread across `render()` as DOM writes. Angular lets you write them down once, as a description of the page, and does the DOM writes for you. That's **declarative rendering**: you describe what the page should look like for the current data, and the framework works out which DOM operations get it there.

Three Angular words come up from here on. A **template** is the HTML-like text that describes the page, with placeholders for data. A **component** is a TypeScript class plus its template; below, it's the `TaskBoard` class. The **view** is the actual DOM that Angular builds from the template.

Declarative rendering doesn't mean no step-by-step code runs. Angular still calls DOM methods like `createElement` behind the scenes, and your event handlers are still ordinary step-by-step code. What changes is who writes the code that keeps the page matching the data.

### Template syntax you'll see

- `{{ remaining() }}` puts a value into text.
- `[checked]="task.done"` keeps the checkbox's `checked` property equal to `task.done`.
- `(change)="..."` runs the code in quotes when the element fires a `change` event.
- `@for (task of visibleTasks(); track task.id)` repeats a row for each task. `track task.id` tells Angular which row belongs to which task.
- `#titleInput` gives the input element a name that other code in the template can use, for example to pass the element to a method.

### Signals

The component stores its data in signals. A **signal** is a box holding a value. You read it by calling it, as in `tasks()`, and change it with `.set(newValue)` or `.update(fn)`, where `fn` receives the current value and returns the next one. Angular remembers which parts of the template read each signal and updates those parts when the signal changes.

`computed(...)` creates a read-only signal whose value is calculated from other signals. `remaining` below reads `tasks()`, so Angular recalculates it when `tasks` changes, and reuses the last result otherwise.

### What you'll see in the TypeScript

- `type TaskFilter = "all" | "active" | "completed"` is a **union type**: a `TaskFilter` can only be one of those three strings.
- `interface Task { ... }` lists the fields every task object has. Types like these only exist for the TypeScript compiler; they're removed from the JavaScript the browser runs.
- `signal<Task[]>([])` creates a signal that holds an array of tasks and starts empty. The type in angle brackets says what the signal holds.
- `@Component({ ... })` is a **decorator**: it attaches the selector and template to the class that follows it.
- `this` inside a method means the component instance, so `this.tasks` is the component's `tasks` signal.
- `...` is **spread syntax**. `[...current, task]` builds a new array with every item of `current` followed by `task`. `{ ...task, done }` builds a new object with all of `task`'s properties, then sets `done` to the new value.

Spread matters here because a signal decides whether its value changed by comparing the old and new value with `Object.is`, which checks for the same object, not the same contents. A new array counts as a change. If you pushed into the existing array instead, the signal would still hold the same array, and Angular wouldn't update anything. The [values article](/dump/blog/values-references-and-identity/#connect-the-model-to-angular) walks through why.

### The task board component

The component lives in one file, `task-board.ts`. Here it is in three pieces, each followed by what to notice. The complete file comes after them.

First, the data. These are members of the `TaskBoard` class:

```ts
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
```

What to notice:

- `tasks` and `filter` are the source of truth, just like the `tasks` array and `filter` variable in the native version.
- `remaining` and `visibleTasks` hold the same rules as the native `render()`: count the tasks that aren't done, then pick the tasks the filter shows. But they only calculate values. Neither one touches the DOM.

Next, the part of the template that shows the filter and the list:

```html
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
<ul id="task-list">
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
```

What to notice:

- This is the same HTML as before, plus bindings. In the file, it sits in the `template` string of `@Component({ ... })`.
- The count, the rows, each checkbox's `checked`, and the empty message are written once, as expressions that read signals. Nothing in the component writes them again.
- The checkbox's `(change)` passes three things to `setDone`: the task, the checkbox's new `checked` value, and the `<select>` element, through its `#filterSelect` name.

Last, the method that runs when a checkbox changes:

```ts
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
```

What to notice:

- `setDone` builds a new array and replaces the changed task with a new object made by `{ ...task, done }`. That new array is what tells the `tasks` signal something changed.
- If the current filter is about to remove the row, it moves focus to the filter, as the native handler did. Angular hasn't updated the page yet when this runs, so the row is still on screen, and there's no `hidden` flag to check the way the native code did. The method works it out from the filter and the new `done` value instead.
- `addTask` and `setFilter` follow the same idea: `addTask` stores `[...current, task]`, and `setFilter` calls `this.filter.set(value)`. Neither one updates the page itself.

<details>
<summary>The complete <code>task-board.ts</code></summary>

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
      <ul id="task-list">
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

</details>

To make it the application's root component, start it from `main.ts`. **Bootstrapping** means asking Angular to start the application and create that first component:

```ts
import { bootstrapApplication } from "@angular/platform-browser";
import { TaskBoard } from "./task-board";

bootstrapApplication(TaskBoard);
```

The page's `index.html` needs a `<task-board></task-board>` element; Angular renders the component inside it. In an existing application, import `TaskBoard` into a parent component instead and use `<task-board />` in the parent's template.

### Follow one completion through the code

Here's what happens when you check a task's box:

1. The `(change)` binding calls `setDone(task, checkbox.checked, filterSelect)`.
2. `setDone` builds a new array. The changed task becomes a new object with the new `done` value; every other task is the same object as before.
3. `this.tasks.update(...)` stores that array. It's a different array from the old one, so the signal records a change, and Angular marks `remaining` and `visibleTasks`, which both read `tasks()`, as out of date.
4. Angular then updates the page. It recalculates `remaining` and `visibleTasks`, rewrites the "Remaining tasks" text, and updates the list. Under the Active filter, it removes the completed task's `<li>`.

Notice what isn't in the component: no `querySelector` for the count paragraph, and no map of row elements. The count is written once in the template, and `track task.id` does the job the `rows` map did. Even when a task is replaced by a new object, its ID stays the same, so Angular keeps that task's existing row and updates it instead of rebuilding the list.

The DOM ends up a little different from the native version. The native and jQuery versions keep filtered-out rows in the list and hide them; Angular removes them and creates them again when the filter changes back. What the user sees is the same.

The handlers still call DOM methods directly: `focus()`, `setCustomValidity()`, and `reportValidity()`. That's fine. Angular has no template syntax for moving focus or showing the browser's validation bubble. The rule of thumb is to leave alone the parts the template describes: the rows, the checkboxes, and the count text. If you edit those by hand, Angular doesn't know about the change, and the page and the signals can disagree again.

## What Angular takes over, and what it doesn't

Angular keeps the template's text, properties, event listeners, and `@for` rows matching the signals. Your code still defines what a task is, how the filter works, and what completing a task means.

Angular also handles cleanup for what the template creates. A component is created when it appears on the page and destroyed when it's removed, and Angular removes its template's event listeners at that point. Anything you start yourself, such as a `setInterval` timer or a listener on `window`, keeps running until you stop it. Angular gives you `DestroyRef` to run that cleanup when the component is destroyed; the [lifecycle guide](https://angular.dev/guide/components/lifecycle) shows how.

The native and jQuery versions never need cleanup, because their rows and listeners live as long as the page. If you turned them into widgets that get added and removed many times on one page, you'd have to remove their listeners and `rows` entries yourself. Hiding a row doesn't do either.

Angular's help has a price: a dependency, a build step, template syntax, and rules about how signals notice changes. Break those rules, for example by changing an object inside a signal instead of replacing it, and the page goes stale again. [Angular change detection](/dump/blog/angular-change-detection/) covers how Angular decides what to update.

## Where single-page applications fit

All three versions add behavior to one page. None of them needs to change what's in the address bar.

A **single-page application (SPA)** goes further: the browser loads one document, and your JavaScript handles moving between screens. When someone clicks a link inside the app, a **router**, code that maps addresses to screens, swaps the screen in place instead of letting the browser load a new page.

That hands your code more decisions. Suppose the task board becomes one screen at `/tasks`, next to a settings screen at `/settings`. Someone picks the Completed filter, opens Settings, then presses the browser's Back button. Should the board come back showing Completed? With ordinary pages, the browser and the server answer that between them. In an SPA, your code has to answer it, for example by putting the filter in the address as `/tasks?filter=completed`. [URLs as application state](/dump/blog/urls-as-application-state/) covers that choice. The same goes for loading states, where focus goes after a screen change, and which timers stop when a screen goes away.

Using Angular doesn't make a site an SPA. You can put an Angular component on one ordinary server-rendered page, and you can build client-side navigation without Angular. For how the first HTML of a page gets produced, see [Where HTML comes from](/dump/blog/html-rendering-methods/).

## Compare the three versions

|                                           | Native JavaScript                     | jQuery                                    | Angular                                         |
| ----------------------------------------- | ------------------------------------- | ----------------------------------------- | ----------------------------------------------- |
| Where the tasks live                      | A `tasks` array in your script        | A `tasks` array in your script            | A `tasks` signal in the component               |
| Who writes the count and rows to the page | Your `render()`, with DOM methods     | Your `render()`, with jQuery methods      | Angular, from the template                      |
| What a teammate has to learn              | DOM methods and your `render()`       | jQuery's methods and your `render()`      | Templates, signals, and how components start    |
| What adding "delete task" takes           | Remove the row and its `rows` entry too | Remove the row and its `rows` entry too | Remove the task from the `tasks` array          |

So, back to the opening question: who keeps the count, the rows, and the filter consistent? With native JavaScript and jQuery, your `render()` function does, and you write it. With Angular, you describe those relationships once in the template, and Angular keeps them current. You still touch the DOM in all three, and jQuery and native code can stay perfectly consistent with one well-placed `render()`. The difference is where that coordinating code lives and who maintains it.

## Closing check

1. A jQuery handler changes a task object, but the remaining count stays stale. What's missing?
2. A native app calls one `render()` function after every change. Does it need a framework to stay consistent?
3. Why does the Angular `setDone` build a new array instead of changing `task.done` on the existing object?

Check your reasoning:

- A rule that calculates the count from the tasks, and code that runs it after the change. jQuery only carries out the DOM operations you ask for.
- No. One renderer that every handler calls keeps it consistent. A framework becomes worth its cost when there's enough repeated, interacting UI that writing and maintaining `render()` by hand gets expensive.
- The signal compares the old and new value by identity. A new array tells Angular that `tasks` changed; changing a property inside the same array wouldn't.

## Sources and further reading

- [jQuery: library overview](https://jquery.com/)
- [jQuery: event handlers with on](https://api.jquery.com/on/)
- [jQuery: DOM properties with prop](https://api.jquery.com/prop/)
- [jQuery: text content](https://api.jquery.com/text/)
- [jQuery: input values](https://api.jquery.com/val/)
- [jQuery: upgrading to 4.0 and its browser-support changes](https://jquery.com/upgrade-guide/4.0/)
- [MDN: JavaScript modules](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Guide/Modules)
- [MDN: spread syntax](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Operators/Spread_syntax)
- [Angular: template bindings](https://angular.dev/guide/templates/binding)
- [Angular: repeated views and tracking](https://angular.dev/guide/templates/control-flow)
- [Angular: signals and derived values](https://angular.dev/guide/signals)
- [Angular: component lifecycle and destruction](https://angular.dev/guide/components/lifecycle)
- [MDN: constraint validation](https://developer.mozilla.org/en-US/docs/Web/HTML/Guides/Constraint_validation)
- [MDN: the hidden attribute and display](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Global_attributes/hidden)
