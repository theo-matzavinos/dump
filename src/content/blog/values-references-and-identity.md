---
title: "What actually changes when you change a variable?"
description: "Follow a task through assignment, mutation, copying, and callbacks to understand which values are independent and which objects are still shared."
pubDate: "2026-10-02"
updatedDate: "2026-10-15"
tags:
  - javascript
  - typescript
  - angular
audience:
  - frontend
---

You click a task in a list to select it. A side panel opens, and you change the task's title there. Then you click Cancel, and the list already shows the new title, even though you never saved anything.

Selecting the task didn't make a copy. The list and the panel were holding the same object the whole time, so an edit through one was an edit for both. This article is about telling those situations apart: when a variable gives you your own copy of something, and when it gives you access to something other code is using too.

You'll need basic JavaScript to follow along: variables, objects, and functions. The examples use the task data behind the task form from [HTML, the DOM, and events](/dump/blog/html-dom-and-events/), but there's no new page to build. The last section connects the same rules to Angular signals and component inputs, using Angular 22.2.

To try a JavaScript example, open your browser's developer tools, select **Console**, paste the block, and run it. Reload the page between examples so each one starts fresh. `console.log(...)` prints the values you pass it, and comments starting with `//` show what you should see. The Angular section's examples are TypeScript for an Angular project instead, and that section says how to run them.

## Contents

1. [Separate the name from the value](#separate-the-name-from-the-value)
2. [Assigning an object shares it](#assigning-an-object-shares-it)
3. [Follow the value through a function call](#follow-the-value-through-a-function-call)
4. [Compare objects by identity or by contents](#compare-objects-by-identity-or-by-contents)
5. [A shallow copy still shares nested objects](#a-shallow-copy-still-shares-nested-objects)
6. [Functions read variables when they run](#functions-read-variables-when-they-run)
7. [Connect the model to Angular](#connect-the-model-to-angular)
8. [Back to the Cancel button](#back-to-the-cancel-button)

## Separate the name from the value

A variable is a name that JavaScript connects to a value. That connection is called a **binding**.

```js
let title = "Read the DOM article";
console.log(title); // Read the DOM article

title = "Read the CSS article";
console.log(title); // Read the CSS article
```

`let` creates a binding you can assign a different value to later. The second assignment changes which string `title` gives you. The first string still exists, unchanged; `title` just doesn't lead to it anymore.

### Some values can't be edited in place

Numbers, strings, and the booleans `true` and `false` are **primitive values**. Primitive values are immutable: once one exists, its contents never change.

For example, asking a string for an uppercase version gives you a second string:

```js
const title = "read the dom article";
const uppercaseTitle = title.toUpperCase();

console.log(title); // read the dom article
console.log(uppercaseTitle); // READ THE DOM ARTICLE
```

`toUpperCase()` returns new text and leaves the original alone. You can keep the result in another variable, as here, or assign it to a variable declared with `let`.

Objects work differently. An object holds named **properties**, and you can change them. The braces below create an object: `title` is a property name, and the string after the colon is its value.

### What const protects

```js
const task = { title: "Read the DOM article" };

task.title = "Read the CSS article";
console.log(task.title); // Read the CSS article
```

The dot in `task.title` selects the object's `title` property, and the assignment changes that property. The variable `task` still leads to the same object, so `const` allows it.

Giving the variable a different value is another operation. This example fails on purpose:

```js
const task = { title: "Read the DOM article" };

task = { title: "Read the CSS article" }; // TypeError: cannot reassign const
```

So `const` stops you from reassigning the variable, and that's all it does. The object's properties stay editable.

Arrays are objects too. An array holds values in numbered positions, and you can change those positions, add to them, and remove them.

## Assigning an object shares it

Start with numbers:

```js
let count = 1;
let savedCount = count;

count = 2;

console.log(count); // 2
console.log(savedCount); // 1
```

When you assigned `savedCount`, it received the value `1`. It doesn't keep watching `count`, so assigning `2` to `count` later leaves `savedCount` at `1`.

Now do the same with an object:

```js
const task = { title: "Read the DOM article" };
const selectedTask = task;

selectedTask.title = "Read the CSS article";

console.log(task.title); // Read the CSS article
console.log(selectedTask.title); // Read the CSS article
```

The assignment didn't create a second task. Both variables give you access to the same object.

Before the edit:

```text
task ──────────┐
               ├──→ object A { title: "Read the DOM article" }
selectedTask ──┘
```

After the edit:

```text
task ──────────┐
               ├──→ object A { title: "Read the CSS article" }
selectedTask ──┘
```

Changing an existing object is called **mutation**. There's one object before the mutation and the same one after it, so reading the title through either variable shows the edit. That's exactly what happened with the side panel in the opening.

People describe this as a **shared reference**: two values that lead to the same object. The arrows show that relationship, not how the browser lays things out in memory.

Notice that `selectedTask` leads to the object, not to the variable `task`. That difference shows up in the next example.

### Reassigning changes only one variable

Compare mutation with replacing the selection:

```js
const task = { title: "Read the DOM article" };
let selectedTask = task;

selectedTask = { title: "Write the values article" };

console.log(task.title); // Read the DOM article
console.log(selectedTask.title); // Write the values article
```

This time the code created a second object and assigned it to `selectedTask`:

```text
task ───────────→ object A { title: "Read the DOM article" }

selectedTask ───→ object B { title: "Write the values article" }
```

Only `selectedTask` changed where it leads. `task` still leads to object A, and object A wasn't edited.

**Assignment copies the value, and for an object that value is access to the same object.** You only get a second object when some code creates one.

## Follow the value through a function call

A function call works the same way. The value you pass in is an **argument**. The name the function uses for it is a **parameter**.

### A parameter can reach the caller's object

```js
function completeTask(taskToComplete) {
  taskToComplete.done = true;
}

const task = { id: 1, done: false };
completeTask(task);

console.log(task.done); // true
```

Follow the call step by step:

1. Evaluate `task` to get its current value.
2. Give that value to the function's parameter, `taskToComplete`.
3. Both names now lead to the same object.
4. Assign `true` to that object's `done` property.
5. After the call, reading `task.done` shows the changed property.

During the call, the relationship is:

```text
caller's task ───────────────┐
                             ├──→ object A { id: 1, done: true }
parameter taskToComplete ───┘
```

The function never touched the caller's variable. It edited the object both names lead to.

### Reassigning a parameter stays inside the function

```js
function replaceTask(taskToReplace) {
  taskToReplace = { id: 2, done: true };
  console.log(taskToReplace.id); // 2
}

const task = { id: 1, done: false };
replaceTask(task);

console.log(task.id); // 1
console.log(task.done); // false
```

`taskToReplace` is the function's own binding. Assigning another object to it changes only that binding:

```text
caller's task ──────────────→ object A { id: 1, done: false }

parameter taskToReplace ────→ object B { id: 2, done: true }
```

You may have heard that JavaScript passes objects "by reference". It's more accurate to say **JavaScript passes every argument by value**, objects included. The parameter gets a copy of the value. For an object, that value leads to the caller's object, so the function can edit it. But reassigning the parameter only redirects the parameter.

### Return a replacement instead

If a function should produce a new task, return it and let the caller assign it:

```js
function makeCompletedTask(taskToRead) {
  return { id: taskToRead.id, done: true };
}

let task = { id: 1, done: false };
task = makeCompletedTask(task);

console.log(task.id); // 1
console.log(task.done); // true
```

`return` hands the new object back as the call's result, and the assignment outside the function replaces the caller's value.

Both styles are fine; the bug is surprise. If a function edits the object you hand it, its name should say so, like `completeTask(task)`. If it returns a new one, like `makeCompletedTask(task)`, the caller has to use the result.

## Compare objects by identity or by contents

Two objects can look identical and still be two separate objects:

```js
const task = { id: 1, title: "Read the DOM article" };
const selectedTask = task;
const fetchedTask = { id: 1, title: "Read the DOM article" };

console.log(task === selectedTask); // true
console.log(task === fetchedTask); // false
console.log(task.id === fetchedTask.id); // true
console.log(task.title === fetchedTask.title); // true
```

`===` is JavaScript's strict equality operator. For two objects, it asks whether both values lead to the **same object**. It doesn't look at their properties.

Each `{ ... }` expression creates its own object, and `selectedTask = task` didn't create one:

```text
task ──────────┐
               ├──→ object A { id: 1, title: "Read the DOM article" }
selectedTask ──┘

fetchedTask ───────→ object B { id: 1, title: "Read the DOM article" }
```

So there are three different questions you might be asking:

- **Is it the same object?** That's what `===` answers. Here, `task === fetchedTask` is false.
- **Is it the same task in the app?** If tasks are identified by `id`, the matching `id` values say yes.
- **Do the contents match?** Compare the fields you care about. Here, both fields match. A real comparison has to decide which fields count and how to compare nested objects.

A task freshly loaded from a server can be the same task in the app without being the same JavaScript object. A matching `id` doesn't make `===` true.

## A shallow copy still shares nested objects

Suppose a task has an owner, and you want a draft of it to edit. The syntax `{ ...task }` is called **object spread**: it creates a new object and copies each of `task`'s properties into it.

```js
const task = {
  id: 1,
  title: "Read the DOM article",
  owner: { name: "Alex" },
};

const draft = { ...task };

console.log(task === draft); // false
console.log(task.owner === draft.owner); // true

draft.owner.name = "Sam";

console.log(task.owner.name); // Sam
console.log(draft.owner.name); // Sam
```

The draft is a new object, but the value it copied for `owner` is access to the same owner object:

```text
task  ───→ object A ── owner ──┐
                              ├──→ owner object { name: "Alex" }
draft ───→ object B ── owner ──┘
```

This is a **shallow copy**: the outer object is new, but objects inside it are still shared with the original.

So setting `draft.title` changes a property on object B, and the original task keeps its title. Setting `draft.owner.name` follows the shared `owner` value and changes the one owner object that both tasks lead to.

### A new array can still contain the original task objects

Array spread, `[...tasks]`, creates a new array with the same elements, and it shares in the same way:

```js
const task = { id: 1, done: false };
const tasks = [task];
const copiedTasks = [...tasks];

copiedTasks[0].done = true;

console.log(tasks === copiedTasks); // false
console.log(tasks[0] === copiedTasks[0]); // true
console.log(tasks[0].done); // true

copiedTasks.push({ id: 2, done: false });

console.log(tasks.length); // 1
console.log(copiedTasks.length); // 2
```

The brackets create an array. `[0]` reads its first element, `push(...)` adds an element to the end, and `length` is the number of elements.

The two arrays are separate objects, so pushing onto one leaves the other at one element. But their first elements are the same task object, so editing that task shows up through both arrays. Copying an array copies its list of values; it doesn't copy the objects those values lead to.

### Copy the path that must be independent

If editing the owner's name has to leave the original task alone, create a new task object and a new owner object:

```js
const task = {
  id: 1,
  title: "Read the DOM article",
  owner: { name: "Alex" },
  labels: ["frontend"],
};

const draft = {
  ...task,
  owner: { ...task.owner, name: "Sam" },
};

console.log(task.owner.name); // Alex
console.log(draft.owner.name); // Sam
console.log(task === draft); // false
console.log(task.owner === draft.owner); // false
console.log(task.labels === draft.labels); // true
```

Read the construction from the inside out:

1. `{ ...task.owner, name: "Sam" }` creates a new owner. The `name` written after the spread replaces the copied name.
2. `{ ...task, owner: ... }` creates a new task object. The `owner` written after the spread replaces the copied owner.
3. The original task still leads to the original owner.

```text
task  ───→ object A ── owner ───→ owner A { name: "Alex" }
draft ───→ object B ── owner ───→ owner B { name: "Sam" }

object A ── labels ──┐
                     ├──→ one labels array ["frontend"]
object B ── labels ──┘
```

This copied only the path to the property being changed. `labels` is still shared. If the draft should allow label edits too, that array needs its own copy as well.

Sharing isn't a problem by itself. Shared data that nobody edits is fine, and it saves copying. The bug is an editable draft that turns out to share something with the saved task.

### What const, readonly, and Object.freeze protect

You might hope one of these keywords would stop the accidental edits. Each one protects less than its name suggests:

- **`const`** stops you from reassigning the variable. The object's properties stay editable.
- **TypeScript's `readonly`**, as in `readonly owner: Owner`, makes the type checker reject code that reassigns that property. It's a compile-time check only; the running JavaScript has no lock, and `task.owner.name` is still writable.
- **`Object.freeze(task)`** blocks changes to the task's own properties while the code runs: assignments are ignored, or throw an error in strict-mode code such as modules. But it's shallow, so `task.owner` is a separate object and stays editable.
- **Spreading** gives you a new object, one level deep.

None of them reach nested objects automatically. If an edit has to stay isolated, copy the path to it.

## Functions read variables when they run

A function can use variables from the code around where it was written. It reads them when it runs, not when it's created.

### Read the selection when the function runs

The function below is an **arrow function**, a short way to write a function. `() => { ... }` creates a function with no parameters, and `return` gives back its result when it's called.

```js
let selectedTask = { title: "Read the DOM article" };

const readSelectedTitle = () => {
  return selectedTask.title;
};

console.log(readSelectedTitle()); // Read the DOM article

selectedTask = { title: "Read the CSS article" };

console.log(readSelectedTitle()); // Read the CSS article
```

There are two separate moments:

1. Creating the function gives it access to the surrounding `selectedTask` variable.
2. Calling the function runs its body, reads that variable's current value, and then reads that object's title.

`selectedTask` was reassigned between the calls, so the second call reaches the new object.

**Scope** is where a name can be used. JavaScript decides which variable a name refers to by where the function was written, not by who calls it; that rule is called **lexical scope**. A function that keeps access to the variables around where it was written is called a **closure**.

A **callback** is a function you hand to other code to call later, such as an event listener. Passing `readSelectedTitle` as a callback changes nothing: it still reads `selectedTask` when its body runs, whenever that is. These examples call the functions directly so the order is easy to follow.

### Save a particular task on purpose

Sometimes you need the opposite: an operation that started for task A should keep using task A, even after the selection moves on.

```js
const firstTask = { title: "Read the DOM article" };
const secondTask = { title: "Read the CSS article" };
let selectedTask = firstTask;

const taskForLater = selectedTask;
const titleForLater = selectedTask.title;

const readCapturedTitle = () => {
  return taskForLater.title;
};

selectedTask = secondTask;
firstTask.title = "Read the revised DOM article";

console.log(selectedTask.title); // Read the CSS article
console.log(readCapturedTitle()); // Read the revised DOM article
console.log(titleForLater); // Read the DOM article
```

The three reads mean different things:

- `selectedTask.title` follows the current selection.
- `taskForLater.title` follows the particular object saved earlier. Changing the selection doesn't move `taskForLater`, but edits to that saved object still show up.
- `titleForLater` is the string as it was. Editing the object's title later doesn't change it.

```text
selectedTask ───→ task B { title: "Read the CSS article" }

taskForLater ───→ task A { title: "Read the revised DOM article" }

titleForLater ──→ "Read the DOM article"
```

Saving the object isn't the same as saving what it looked like. If you need the title as it was when the user clicked, save the title, or a copy of the task, at that moment.

Neither behavior is right in general. "Use whatever is selected when this runs" and "finish the job for the task it started with" are two different requirements, and the code should match the one you have.

### A returned function keeps its variables

A function returned from another function keeps access to the outer function's parameter:

```js
function makeTaskReader(taskToRead) {
  return () => {
    return taskToRead.title;
  };
}

const task = { title: "Read the DOM article" };
const readTitle = makeTaskReader(task);

console.log(readTitle()); // Read the DOM article

task.title = "Read the CSS article";
console.log(readTitle()); // Read the CSS article
```

`makeTaskReader` has already finished by the time you call `readTitle`. The returned function still has access to that call's `taskToRead`, which leads to the shared task object. Nothing was copied, so each call reads the object's current title.

## Connect the model to Angular

Angular runs on the same JavaScript, so everything above still applies: a parent component and a child component can share one task object, and a spread copy still shares its owner.

You'll need to know what a component and its template are for this section. A **signal** is an Angular object that holds one value and notices when you give it a new one:

- `signal(...)` creates one with a starting value. Calling it, such as `task()`, reads the current value.
- `.set(...)` gives it a new value.
- `.update(...)` calls your function with the current value and stores whatever the function returns.
- `computed(...)` creates a value calculated from other signals. It remembers its last answer, and only reruns when a signal it read gets a new value.

### Signals compare values with Object.is

When you give a signal a value, it checks whether that value is different from the one it holds. By default it uses `Object.is(oldValue, newValue)`, a JavaScript equality test that works like `===` for objects: it asks whether both values lead to the same object, and ignores their properties. (It only differs from `===` for two special numbers: `Object.is(NaN, NaN)` is true, and `Object.is(0, -0)` is false.)

So writing the same object back into a signal doesn't count as a change, even if you edited the object in between. To see it, paste this at the top of `src/main.ts` in an Angular project and check the browser console. `signal` and `computed` work anywhere, not just inside components.

```ts
import { computed, signal } from "@angular/core";

const task = signal({
  title: "Read the DOM article",
  owner: { name: "Alex" },
});

const title = computed(() => {
  return task().title;
});

console.log(title()); // Read the DOM article: calculate and cache it.

task().title = "Read the CSS article";

console.log(task().title); // Read the CSS article: the object changed.
console.log(title()); // Read the DOM article: the cached result remains.

task.set(task());
console.log(title()); // Read the DOM article: same object value.

task.update((current) => {
  return { ...current, title: "Read the CSS article" };
});

console.log(title()); // Read the CSS article: recomputed after replacement.
```

Follow the operations one by one:

1. The first `title()` read runs the calculation and remembers the original string.
2. `task().title = ...` mutates the object inside the signal without giving the signal a new value. Reading `task().title` directly shows the edit, but `title` has no reason to rerun, so it returns its remembered answer.
3. `task.set(task())` writes the same object back. `Object.is` says it's the same value, so this isn't a change either, and `title` still doesn't rerun.
4. `update` returns a new object. That's a different value, so the signal counts it as a change, and the next `title()` read recalculates.

The new object from step 4 still shares its `owner` with the old one, exactly like the shallow copy earlier. Signals can also be given a custom equality function, but this article sticks to the default.

So editing an object changes the data, but only giving the signal a new value tells the things that read it, like `title`, to recalculate.

### Inputs receive the same object

Component inputs follow the same rule. Here's a child component that receives a task through an input and shows a summary of it. `input.required<Task>()` declares an input the parent must supply, and the child reads it like a signal, with `task()`. The backticks in `summary` make a template literal: a string where `${...}` inserts a value.

```ts
import { Component, computed, input } from "@angular/core";

export interface Task {
  id: number;
  title: string;
  done: boolean;
}

@Component({
  selector: "task-summary",
  template: `<p>{{ summary() }}</p>`,
})
export class TaskSummary {
  readonly task = input.required<Task>();

  readonly summary = computed(() => {
    return `Selected: ${this.task().title}`;
  });
}
```

The parent holds the selected task in a signal and has two ways to rename it. `imports: [TaskSummary]` lets its template use `<task-summary>`, and `[task]="selectedTask()"` sets the child's `task` input to whatever `selectedTask()` returns:

```ts
import { Component, signal } from "@angular/core";

import { Task, TaskSummary } from "./task-summary";

@Component({
  selector: "task-details",
  imports: [TaskSummary],
  template: `
    <task-summary [task]="selectedTask()" />
    <button type="button" (click)="renameInPlace()">Rename in place</button>
    <button type="button" (click)="renameWithCopy()">Rename with a copy</button>
  `,
})
export class TaskDetails {
  readonly selectedTask = signal<Task>({ id: 1, title: "Read the DOM article", done: false });

  renameInPlace(): void {
    this.selectedTask().title = "Read the CSS article";
  }

  renameWithCopy(): void {
    this.selectedTask.update((task) => {
      return { ...task, title: "Read the CSS article" };
    });
  }
}
```

To try it, save the child as `task-summary.ts` and the parent next to it, then render `<task-details />` from a component in an Angular project, such as the root component that `ng new` generates (add `TaskDetails` to its `imports`).

Click **Rename in place** and the summary still says "Selected: Read the DOM article". The parent edited the object, but `selectedTask()` still returns the same object, so when Angular evaluates `[task]="selectedTask()"` it compares the old and new values with `Object.is`, finds them equal, and doesn't update the child's input. The child's `summary` never reruns.

Reload and click **Rename with a copy**. `update` stores a new object, the binding sees a different value, the child's `task` input gets it, and `summary` reruns: "Selected: Read the CSS article".

When and how Angular checks bindings and updates the page is covered in [Angular change detection, from notifications to DOM updates](/dump/blog/angular-change-detection/). The rule this article adds is that replacing an object is what Angular can see; editing it in place usually isn't.

## Back to the Cancel button

In the opening, selecting a task and editing it in a side panel changed the list, and Cancel couldn't undo it. Now you can say why: selecting assigned the same task object to the panel, so the panel's edits were mutations of the task the list was showing.

The fix is to give the panel its own copy when editing starts, such as `const draft = { ...task };`. Edits change the draft. Cancel throws the draft away. Save replaces the task in the list with the draft. If the panel can also edit nested objects, like the owner, copy those too.

Check yourself:

1. `selectedTask = task`, followed by `selectedTask.title = "Edited"`: what does `task.title` read?
2. A function assigns a new object to its task parameter: has the caller's variable changed?
3. `draft = { ...task }`, followed by an edit to `draft.owner.name`: does the original task's owner change?
4. A task inside a signal is mutated, then passed unchanged to `.set()`: does a `computed` that reads it recalculate?

Answers:

1. `"Edited"`. Both variables lead to one object, and the edit changed that object.
2. No. Reassigning the parameter only redirects the function's own binding. If the caller should get a new task, the function returns it and the caller assigns it.
3. Yes. Spread made a new outer object, but `owner` is still shared. Copy the owner too to keep the edit separate.
4. No. It's the same object, and `Object.is` treats it as unchanged, so the `computed` keeps its remembered answer. Give the signal a new object instead.

When you're not sure what an operation will change, draw the arrows before and after it, as in the diagrams above. That small diagram usually answers the question faster than thinking of it all as "changing state".

## Sources and further reading

- [MDN: JavaScript data types and structures](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Guide/Data_structures)
- [MDN: functions and argument passing](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Guide/Functions)
- [MDN: equality comparisons and sameness](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Guide/Equality_comparisons_and_sameness)
- [MDN: spread syntax and shallow copies](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Operators/Spread_syntax)
- [MDN: closures](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Guide/Closures)
- [MDN: `Object.freeze()`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Object/freeze)
- [TypeScript Handbook: readonly properties](https://www.typescriptlang.org/docs/handbook/2/objects.html#readonly-properties)
- [Angular: signals, computed values, and equality](https://angular.dev/guide/signals)
- [Angular: accepting data with input properties](https://angular.dev/guide/components/inputs)
- [ECMAScript: argument evaluation](https://tc39.es/ecma262/#sec-runtime-semantics-argumentlistevaluation)
- [ECMAScript: copying property values](https://tc39.es/ecma262/#sec-copydataproperties)
- [ECMAScript: function creation and its surrounding scope](https://tc39.es/ecma262/#sec-runtime-semantics-instantiatearrowfunctionexpression)
