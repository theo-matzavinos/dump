---
title: "What actually changes when you change a variable?"
description: "Follow a task through assignment, mutation, copying, and callbacks to understand which values are independent and which objects are still shared."
pubDate: "2026-10-02"
tags:
  - javascript
  - typescript
  - frontend
  - angular
---

Selecting a task seems to make a second copy, but editing the selection changes the original. Spreading a task into an editable draft fixes its title, yet changing the draft's owner still changes the saved task. A callback created for one selection later reads a different selection.

These situations become easier to predict when we separate three things:

1. **The name:** which variable is being read or assigned?
2. **The value:** what does that variable currently give us?
3. **The object:** if the value gives access to an object, who else has access to that same object?

We will follow the task data behind the interface from [HTML, the DOM, and events](/dump/blog/html-dom-and-events/). There is no new interface to build here: we are investigating the relationships between its values.

Each JavaScript code block is an independent example. To try one, open your browser's developer tools, select **Console**, paste the block, and run it. Reload the page between examples to start from a fresh context. `console.log(...)` prints the values passed to it; comments beginning with `//` show expected results. The deliberately failing example is marked. TypeScript and Angular examples are labeled separately.

## Contents

1. [Separate the name from the value](#separate-the-name-from-the-value)
2. [Assignment does not clone an object](#assignment-does-not-clone-an-object)
3. [Follow the value through a function call](#follow-the-value-through-a-function-call)
4. [Same contents do not mean the same object](#same-contents-do-not-mean-the-same-object)
5. [A shallow copy still shares nested objects](#a-shallow-copy-still-shares-nested-objects)
6. [Functions retain access, not automatic snapshots](#functions-retain-access-not-automatic-snapshots)
7. [Connect the model to Angular](#connect-the-model-to-angular)

## Separate the name from the value

A variable is a name that JavaScript connects to a value. That connection is called a **binding**. The name is not the value itself.

```js
let title = "Read the DOM article";
console.log(title); // Read the DOM article

title = "Read the CSS article";
console.log(title); // Read the CSS article
```

`let` creates a binding that we can assign a different value to. The second assignment changes which string `title` gives us; it does not edit the text of the first string.

### Some values cannot be edited in place

Numbers, strings, and booleans such as `true` and `false` are examples of **primitive values**. Primitive values are immutable: you cannot change an existing primitive value's contents.

For example, asking a string for an uppercase version produces another string:

```js
const title = "read the dom article";
const uppercaseTitle = title.toUpperCase();

console.log(title); // read the dom article
console.log(uppercaseTitle); // READ THE DOM ARTICLE
```

`toUpperCase()` does not rewrite the original text. We can keep the new result in another variable, as here, or assign a new result to a variable declared with `let`.

Objects are different. An object can hold named **properties**, and those properties can be mutable. The braces below create an object; `title` is a property name, and the string after the colon is its value.

### const fixes the binding, not the object's properties

```js
const task = { title: "Read the DOM article" };

task.title = "Read the CSS article";
console.log(task.title); // Read the CSS article
```

The dot in `task.title` selects the object's `title` property. That assignment changes a property on the object. It does not assign a different value to the variable `task`, so `const` permits it.

Replacing the variable's value is a different operation. This example deliberately fails:

```js
const task = { title: "Read the DOM article" };

task = { title: "Read the CSS article" }; // TypeError: cannot reassign const
```

`const` prevents that reassignment. It does not protect the object's properties or any nested objects.

An array holds values in numbered positions and is an object too: its elements can change. A function is also an object, although it has the additional ability to be called. We will see why their object identity matters shortly.

## Assignment does not clone an object

Start with numbers:

```js
let count = 1;
let savedCount = count;

count = 2;

console.log(count); // 2
console.log(savedCount); // 1
```

When we assigned `savedCount`, it received the value `1`. It did not become a standing instruction to reread the variable `count`. Assigning `2` to `count` does not change the other binding.

Now assign an object value:

```js
const task = { title: "Read the DOM article" };
const selectedTask = task;

selectedTask.title = "Read the CSS article";

console.log(task.title); // Read the CSS article
console.log(selectedTask.title); // Read the CSS article
```

The assignment did not create a second task object. Both variables give us access to the same one.

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

Changing an existing object is called **mutation**. There was one object before the mutation and one afterward. Reading its title through either variable reaches the edited property.

We often describe this as a **shared reference**: two values provide access to the same object. The arrows show that relationship, not a required memory layout or a promise about physical addresses.

Importantly, `selectedTask` does not point to the variable `task`. It gives access to the object that `task` also gives access to.

### Reassignment changes one relationship

Compare mutation with replacing the selection:

```js
const task = { title: "Read the DOM article" };
let selectedTask = task;

selectedTask = { title: "Write the values article" };

console.log(task.title); // Read the DOM article
console.log(selectedTask.title); // Write the values article
```

This time we created another object and assigned it to `selectedTask`:

```text
task ───────────→ object A { title: "Read the DOM article" }

selectedTask ───→ object B { title: "Write the values article" }
```

We redirected one binding. We did not redirect `task`, and we did not change object A.

**Assignment copies a value; it does not clone an object.** If that value gives access to an object, the receiver gets access to the same object unless we explicitly create another one.

## Follow the value through a function call

A function call follows the same distinction. The value we supply is an **argument**. The function's local name that receives it is a **parameter**.

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
3. Both names now provide access to the same object.
4. Assign `true` to that object's `done` property.
5. After the call, reading `task.done` reaches the changed property.

During the call, the relationship is:

```text
caller's task ───────────────┐
                             ├──→ object A { id: 1, done: true }
parameter taskToComplete ───┘
```

The function does not need access to the caller's variable to edit their shared object.

### Replacing the parameter does not replace the caller's variable

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

`taskToReplace` is a local binding. Assigning another object to it changes only that binding:

```text
caller's task ──────────────→ object A { id: 1, done: false }

parameter taskToReplace ────→ object B { id: 2, done: true }
```

This is why **JavaScript passes arguments by value**, including object values. The parameter receives a value, not the ability to redirect the caller's binding. That value can still provide access to an object the caller also uses.

“Objects are passed by reference” is misleading if it suggests that replacing a parameter replaces the caller's variable. It does not.

### Let the caller choose a replacement

If a function should produce a replacement, return that value and let the caller assign it:

```js
function makeCompletedTask(taskToRead) {
  return { id: taskToRead.id, done: true };
}

let task = { id: 1, done: false };
task = makeCompletedTask(task);

console.log(task.id); // 1
console.log(task.done); // true
```

Here, `return` supplies the new object as the call's result. The assignment outside the function replaces the caller's value.

Neither mutation nor replacement is inherently wrong. At a function boundary, make the promise clear: may this function edit the object it receives, or does it produce another value for the caller to use? Unexpected edits are the problem, not the mere existence of mutation.

## Same contents do not mean the same object

Two objects can look identical without being the same object:

```js
const task = { id: 1, title: "Read the DOM article" };
const selectedTask = task;
const fetchedTask = { id: 1, title: "Read the DOM article" };

console.log(task === selectedTask); // true
console.log(task === fetchedTask); // false
console.log(task.id === fetchedTask.id); // true
console.log(task.title === fetchedTask.title); // true
```

`===` is JavaScript's strict equality operator. For objects, it asks whether the two values identify the **same object**, not whether their properties match.

The two object expressions created separate objects. Assigning `selectedTask = task` did not create another one.

```text
task ──────────┐
               ├──→ object A { id: 1, title: "Read the DOM article" }
selectedTask ──┘

fetchedTask ───────→ object B { id: 1, title: "Read the DOM article" }
```

Keep three questions separate:

- **Object identity:** is this the same JavaScript object? Here, `task === fetchedTask` is false.
- **Domain identity:** do these values represent the same task in our application? If the task ID defines that identity, their matching `id` values say yes.
- **Content equality:** do the fields we care about match? Here, both shown fields match. A real comparison needs to specify which fields count and how nested values are compared.

A freshly loaded task can represent the same task without being the same JavaScript object. Its domain ID does not make `===` compare its fields.

### Functions have identity too

An arrow function is one way to write a function. In the example below, `() => { ... }` creates a function with no parameters; `return` supplies its result when called.

```js
const makeLabel = () => {
  return "Tasks";
};

const sameFunction = makeLabel;

const anotherFunction = () => {
  return "Tasks";
};

console.log(makeLabel === sameFunction); // true
console.log(makeLabel === anotherFunction); // false
console.log(makeLabel() === anotherFunction()); // true
```

The first two comparisons concern the function objects. The last calls both functions and compares their returned strings.

Identical-looking function bodies do not make separate function creations equal. If other code needs the original function object, writing the same function expression again does not recreate its identity.

### Object.is is another equality test

For objects, `Object.is(task, selectedTask)` uses the same identity distinction as `task === selectedTask`. It does not compare the objects' fields either. Angular uses this test for signals by default.

There are two notable number differences from `===`: `Object.is(NaN, NaN)` is true, and `Object.is(0, -0)` is false. `NaN` is the special number value used for an invalid numeric result. JavaScript also has positive and negative zero, which `===` treats as equal. Those details are not needed to predict the task-object examples; the important point here is **identity, not matching fields**.

## A shallow copy still shares nested objects

Suppose a task has an owner, and we want an editable draft:

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

For this plain data object, `{ ...task }` builds a new outer object from the task's property values. That operation is called **object spread**.

It copies the value of `owner`; it does not construct another owner object. The relationships are:

```text
task  ───→ object A ── owner ──┐
                              ├──→ owner object { name: "Alex" }
draft ───→ object B ── owner ──┘
```

This is a **shallow copy**: the outer object is new, but object values inside it still provide access to the original nested objects.

Editing `draft.title` would replace a string property on object B. Editing `draft.owner.name` follows the shared owner value and changes the owner object. That is why the first edit can be isolated while the second is not.

### A new array can still contain the original task objects

Array spread has the same sharing consequence for its elements:

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

The brackets create an array. `[0]` accesses its first element, `push(...)` adds an element, and `length` reports the number of elements.

The arrays are separate objects, so adding another element to one does not add it to the other. But their first elements still identify the same task object. Editing that task is visible through both arrays.

**Copying the container and copying its contents are different operations.**

### Copy the path that must be independent

If editing the owner's name must leave the original task alone, create both a new task object and a new owner object:

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

1. `{ ...task.owner, name: "Sam" }` creates a new owner. The later `name` property overrides the copied name.
2. `{ ...task, owner: ... }` creates a new task-shaped object. The later `owner` property overrides the copied owner value.
3. The original task still leads to the original owner.

```text
task  ───→ object A ── owner ───→ owner A { name: "Alex" }
draft ───→ object B ── owner ───→ owner B { name: "Sam" }

object A ── labels ──┐
                     ├──→ one labels array ["frontend"]
object B ── labels ──┘
```

We copied the path to the property we needed to change. We did not make everything independent: `labels` is still shared. If the draft should also permit isolated label edits, that array needs its own copy too.

Decide which edits must be isolated rather than treating spread as a promise that no sharing remains. A deliberate shared object can be useful; an unexpectedly shared editable draft is a bug.

### TypeScript readonly is a checking rule

TypeScript checks code before it runs as JavaScript. A property marked `readonly` cannot be reassigned through that type, but the modifier does not install a runtime lock.

This TypeScript example defines a task with an owner property that cannot be replaced through `Task`. The owner's `name` property is still writable:

```ts
interface Task {
  readonly owner: { name: string };
}

const task: Task = { owner: { name: "Alex" } };

task.owner.name = "Sam"; // Allowed: name is not readonly.
console.log(task.owner.name); // Sam

// task.owner = { name: "Taylor" }; // TypeScript error if uncommented.
```

`interface Task` describes the allowed shape; `: Task` asks the checker to use that description. It does not copy or freeze the object. Other code with a writable view of a shared object can still change it.

JavaScript's `Object.freeze()` is a runtime operation, but it is shallow too:

```js
const task = Object.freeze({
  owner: { name: "Alex" },
});

task.owner.name = "Sam";
console.log(task.owner.name); // Sam
```

The outer task's own properties are protected. The separate owner object is not automatically frozen. `const`, TypeScript `readonly`, freezing, and copying address different things; none should be mistaken for a promise that every nested value is independent and immutable.

## Functions retain access, not automatic snapshots

A function can use names from the code surrounding its creation. Preparing the function does not necessarily read those values yet.

### Read the selection when the function runs

```js
let selectedTask = { title: "Read the DOM article" };

const readSelectedTitle = () => {
  return selectedTask.title;
};

console.log(readSelectedTitle()); // Read the DOM article

selectedTask = { title: "Read the CSS article" };

console.log(readSelectedTitle()); // Read the CSS article
```

There are two different moments:

1. Creating the function gives it access to the surrounding `selectedTask` binding.
2. Calling the function runs its body, reads that binding's current value, then reads the object's title.

We reassigned `selectedTask` between calls. The second call therefore reaches the new object.

**Scope** describes where names are accessible. JavaScript's **lexical scope** resolves those names according to where the function was written, not according to whichever function happens to call it. A function retaining access to its surrounding bindings is a **closure**.

A **callback** is a function supplied to other code to call, such as an event listener. If we use `readSelectedTitle` as a callback, the lookup still happens when its body runs. Nothing about calling it a callback automatically snapshots the selection.

We are calling these functions directly to make the order explicit. We do not need a timer or an event-loop explanation to see the relationship.

### Capture a particular task deliberately

Sometimes the requirement is different: an operation prepared for task A should still use task A even after the selection changes.

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

The three reads have deliberately different meanings:

- `selectedTask.title` follows the current selection.
- `taskForLater.title` follows the particular object saved earlier. Reassigning the selection does not redirect `taskForLater`, but editing that saved object is still visible.
- `titleForLater` is the earlier string value. Editing the object's title does not change that string.

```text
selectedTask ───→ task B { title: "Read the CSS article" }

taskForLater ───→ task A { title: "Read the revised DOM article" }

titleForLater ──→ "Read the DOM article"
```

Capturing an object is not cloning or freezing it. If an operation needs historical data, decide which values must represent that earlier moment; keeping the object alone does not provide that guarantee.

Neither behavior is universally correct. “Use whatever is selected when this runs” and “finish the operation for the task it started with” are different product requirements.

### Access can outlive the outer function call

A returned function can retain access to its outer function's parameter:

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

`makeTaskReader` has finished by the time we call `readTitle`. Its returned function still has access to that call's `taskToRead` binding, which provides access to the shared task object.

Returning the function did not copy the object or save its title as a string. Each call to the returned function reads the object's current title.

## Connect the model to Angular

Angular does not change these JavaScript relationships. A parent and child can share one task object, and a new outer object can still share an owner with an old one.

At an input boundary, mutating a property does not provide a new object value to the child. Replacing that object provides a different value, but the application still needs the appropriate Angular update path to evaluate and deliver it. “Create another object” is not a complete explanation of scheduling or view checking.

Signals give us a small way to observe the distinction without building another component:

- `signal(...)` creates an Angular value holder; calling it, such as `task()`, reads its current value.
- `.set(...)` supplies a next value.
- `.update(...)` calls a function with the current value and uses its returned value as the next one.
- `computed(...)` creates a derived value. It caches a calculation based on the signals it reads and recalculates when a recognized dependency change invalidates that cache and the result is read again.

In an Angular project, run this example with the default equality behavior:

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

Follow the operations separately:

1. The first `title()` read calculates and caches the original string.
2. Editing `task().title` mutates the stored object without a signal write. The direct property read sees the edit, but that mutation does not invalidate the computed value.
3. `task.set(task())` writes the same object value back. Signals use `Object.is` by default, so this does not count as a change and still does not invalidate the computed value.
4. The update returns a new outer object. Under default equality, it counts as a signal change; the next `title()` read recalculates.

Custom equality can change which writes count as changes; this example deliberately uses the default. Also notice that the update still copies the existing `owner` value. The new outer task does not get an independent owner automatically.

This is not a prescription to replace every object everywhere. It is a distinction between **changing data** and **notifying a consumer that its input changed**.

A template reading `task().title` directly may display the mutated property during a later check triggered for another reason. That does not mean the mutation notified Angular, and it does not invalidate the cached `title()` computation above. Direct property reads and cached derived values need to be considered separately.

For notification, input checks, and template updates, continue with [Angular change detection, from notifications to DOM updates](/dump/blog/angular-change-detection/). Here, the foundation is knowing which value changed and which objects remain shared.

## Closing check

Before changing state, can you predict these results?

1. `selectedTask = task`, followed by `selectedTask.title = "Edited"`: what does `task.title` read?
2. A function assigns a new object to its task parameter: has it replaced the caller's variable?
3. Two separately created tasks have the same ID and fields: are they equal with `===`?
4. `draft = { ...task }`, followed by an edit to `draft.owner.name`: is the original owner isolated?
5. A function reads `selectedTask` after the selection changes: does it use the old selection automatically?
6. A signal's task object is mutated, then passed unchanged to `.set()`: does default equality recognize another object?

Check your reasoning:

- The first assignment shares one object. The property mutation is visible through `task`, so its title is `"Edited"`.
- Replacing a parameter redirects a local binding, not the caller's binding. The caller must assign a returned replacement if that is the intended operation.
- Matching IDs can establish domain identity, and matching fields can establish the chosen content comparison. Neither makes separate objects identical with `===`.
- Object spread creates a new outer task but shares its owner. Isolating that edit requires a new owner along that path too.
- The function reads the binding's current value when it runs. Saving a particular task separately changes which object it follows, but does not freeze that object.
- Passing the same object back to the signal does not change its identity. Under default equality, it does not notify consumers of the earlier property mutation.

Draw the relationships before and after an operation. That small diagram often answers the question more clearly than calling all of it “changing state.”

## Sources and further reading

- [MDN: JavaScript data types and structures](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Guide/Data_structures)
- [MDN: functions and argument passing](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Guide/Functions)
- [MDN: equality comparisons and sameness](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Guide/Equality_comparisons_and_sameness)
- [MDN: spread syntax and shallow copies](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Operators/Spread_syntax)
- [MDN: closures](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Guide/Closures)
- [TypeScript Handbook: readonly properties](https://www.typescriptlang.org/docs/handbook/2/objects.html#readonly-properties)
- [Angular: signals, computed values, and equality](https://angular.dev/guide/signals)
- [ECMAScript: argument evaluation](https://tc39.es/ecma262/#sec-runtime-semantics-argumentlistevaluation)
- [ECMAScript: copying property values](https://tc39.es/ecma262/#sec-copydataproperties)
- [ECMAScript: function creation and its surrounding scope](https://tc39.es/ecma262/#sec-runtime-semantics-instantiatearrowfunctionexpression)
