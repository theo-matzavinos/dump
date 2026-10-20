---
title: "Same task board, two layouts: layered and sliced code organization in ASP.NET Core"
description: "Build the task board's Tasks feature as an Application project and an Adapter project joined by ports, and as one file per use case, then compare what three everyday changes touch, what the compiler checks, how you find and test the code, and where ports and adapters belong in both."
pubDate: "2026-10-20"
tags:
  - aspnet-core
  - dotnet
  - architecture
  - testing
audience:
  - backend
---

A new request arrives for the task board: when someone completes a task, email the person it's assigned to. Before writing any code, you have to decide where it goes.

In one codebase, the answer is a single file. `Tasks/CompleteTask.cs` already holds everything the completion endpoint does, from reading the route value to updating the database, so the email goes there too. In another codebase, the answer is spread across two projects: the rule "completing a task mails the assignee" goes into a service class in an Application project, the code that talks to the mail service goes into an Adapter project, and an interface connects the two.

Both are common ways to organize an ASP.NET Core API, and both work. This article builds the same task board both ways, applies three everyday changes to each, including the email, and compares what each change touches, what the compiler checks, how you find a feature's code, and how you test it.

You'll need [the resource-style and action-style endpoints article](/dump/blog/resource-style-and-action-style-endpoints/), whose task board both builds start from, and [Controllers and minimal APIs compared](/dump/blog/controllers-and-minimal-apis/) for the minimal API endpoint style. [Dependency injection and service lifetimes](/dump/blog/aspnet-core-dependency-injection/) explains registering a class under an interface, [EF Core behind the scenes](/dump/blog/ef-core-behind-the-scenes/) covers change tracking and `ExecuteUpdate`, and [the transactions article](/dump/blog/transactions-and-concurrent-edits/) built the version column that both builds use to detect concurrent edits.

## Contents

1. [Set up the example](#set-up-the-example)
2. [Two ways to arrange one feature](#two-ways-to-arrange-one-feature)
3. [Ports and adapters](#ports-and-adapters)
4. [What the compiler enforces](#what-the-compiler-enforces)
5. [Change 1: completing a task](#change-1-completing-a-task)
6. [Change 2: adding a priority](#change-2-adding-a-priority)
7. [Change 3: mailing the assignee](#change-3-mailing-the-assignee)
8. [Finding a feature's code](#finding-a-features-code)
9. [Testing the completion rule](#testing-the-completion-rule)
10. [Startup registrations](#startup-registrations)
11. [When each fits](#when-each-fits)
12. [Back to the email](#back-to-the-email)

## Set up the example

The examples use the .NET 10 SDK (ASP.NET Core 10.0.13), EF Core 10.0.4 through Npgsql.EntityFrameworkCore.PostgreSQL 10.0.3 with EFCore.NamingConventions 10.0.1, Microsoft.AspNetCore.OpenApi 10.0.13, Microsoft.AspNetCore.JsonPatch.SystemTextJson 10.0.13, and PostgreSQL 18.6, in the `Production` environment. Tests use xunit.v3 3.2.2 and Microsoft.Extensions.TimeProvider.Testing 10.11.0. Mediator libraries such as MediatR, mapping libraries, domain events, microservices, controllers, and delivering email reliably are outside this article's scope.

Both builds start from the endpoints article's code, with minimal API endpoints in both: `GET /tasks` and `POST /tasks/search`, `GET /tasks/{id}` with an ETag, `POST /tasks`, and `PUT` and JSON Patch `PATCH` on `/tasks/{id}`, both requiring `If-Match`. To show what adding an endpoint touches, both start without `POST /tasks/{id}/complete`; the first change adds it back. Both talk to the same PostgreSQL database.

Each change is one git commit in each build, so "what a change touches" is what `git show --stat` reports for that commit. The second change adds a column:

```sql
alter table tasks add column priority integer not null default 1;
```

## Two ways to arrange one feature

A **layered** layout splits code by technical job: code that handles HTTP, code that holds the business rules, and code that talks to the database each live in their own place. A **sliced** layout splits code by use case: each request the API handles, such as "complete a task", gets its own file containing everything that request needs.

Here are both builds after all three changes. The layered build has two projects for the Tasks feature:

```text
TaskBoard.Tasks.Application/          class library with no package references
  Model/
    TaskItem.cs                       the task entity: properties only
    TaskSummary.cs  TaskDraft.cs  TaskChanges.cs  TaskFilter.cs  TaskPriority.cs
  Ports/In/
    ITaskService.cs                   what the endpoints can ask the application to do
  Ports/Out/
    ITaskRepository.cs                what the application needs from storage
    IMailSender.cs                    what the application needs to send mail
    ConcurrencyConflictException.cs
  Services/
    TaskService.cs                    the rules
TaskBoard.Tasks.Adapter/              web project that references the Application project
  In/
    TaskEndpoints.cs                  minimal API endpoints
    TaskContracts.cs                  request and response records
    TaskMapping.cs                    converts between those records and Model
    ETags.cs
  Out/
    TaskBoardDb.cs  UserRow.cs        EF Core
    TaskRepository.cs                 implements ITaskRepository
    HttpMailSender.cs                 implements IMailSender
  Program.cs
```

The sliced build is one project:

```text
TaskBoard/
  Tasks/
    TaskRoutes.cs                     maps every slice under /tasks
    SearchTasks.cs                    GET /tasks and POST /tasks/search
    GetTask.cs
    CreateTask.cs
    EditTask.cs                       PUT and PATCH
    CompleteTask.cs
    CompletionMail.cs                 used by CompleteTask and EditTask
  Data/
    Entities.cs  TaskBoardDb.cs  TaskPriority.cs
  Mail/
    IMailSender.cs  HttpMailSender.cs
  Http/
    ETags.cs
  Program.cs
```

What to notice:

- Both are grouped by feature at the top. Everything about tasks sits under one name, and a second feature, such as user accounts, would get its own pair of projects on the left and its own folder on the right. The difference is inside the feature.
- In the layered build, one request passes through several files, each doing one technical job: an endpoint in `In/` calls `TaskService`, which calls `TaskRepository` in `Out/`. In the sliced build, one file does every job for one request: `CompleteTask.cs` reads the route value, updates the database, sends the email, and picks the response.
- The layered build has 20 C# files with 524 lines across two projects; the sliced build has 14 files with 398 lines in one project.
- An **entity** is a class EF Core maps to a table, one object per row. `TaskItem` here has only properties and no methods, which is often called an **anemic** entity: the rules that change it live in `TaskService` instead.

Martin Fowler describes the first layout in "PresentationDomainDataLayering": splitting presentation, domain logic, and data access is useful because "it allows me to reduce the scope of my attention", but "it should only be applied at a relatively small granularity", and "once any of these layers gets too big you should split your top level into domain oriented modules which are internally layered." The layered build is that last sentence: a Tasks module, layered inside.

Jimmy Bogard describes the second in "Vertical Slice Architecture": "my architecture is built around distinct requests, encapsulating and grouping all concerns from front-end to back." His rule for it is "Minimize coupling between slices, and maximize coupling in a slice."

The layered layout goes by several names. Microsoft's architecture e-book puts it this way: "One of the first names was Hexagonal Architecture, followed by Ports-and-Adapters. More recently, it's been cited as the Onion Architecture or Clean Architecture." Templates differ in how many projects they use and where the entity lives, but they all keep the business rules in a center that references neither the database code nor the web code. This article calls that family layered.

Templates for both layouts often send every request through a mediator library such as MediatR. Neither build here uses one, and neither layout needs one. (MediatR itself moved from the Apache 2.0 license to a choice of RPL 1.5 or a commercial license with version 13, in July 2025.)

One difference shows up in the OpenAPI document. When you pass a method as a minimal API handler, ASP.NET Core tags the endpoint with the name of the class that declares the method, so the sliced build's document shows a group per slice (`SearchTasks`, `GetTask`, `EditTask`, `CompleteTask`, `CreateTask`) and the layered build's shows one group called `TaskEndpoints`. Both builds call `.WithTags("Tasks")` on the route group, so both documents show one `Tasks` group. [The OpenAPI article](/dump/blog/openapi-spec-that-matches-the-code/) covers the rest of the document.

## Ports and adapters

Alistair Cockburn named the layered family's core idea in 2005, in "Hexagonal Architecture". His stated goal: "Allow an application to equally be driven by users, programs, automated test or batch scripts, and to be developed and tested in isolation from its eventual run-time devices and databases."

He describes two parts. A **port** is a point where the application talks to something outside it: "A port identifies a purposeful conversation." In C#, that's an interface describing what the application offers or needs. An **adapter** connects a port to a real technology: "For each external device there is an adapter that converts the API definition to the signals needed by that device and vice versa." In C#, that's a class that calls or implements the interface.

In the layered build:

| | Port, in the Application project | Adapter, in the Adapter project |
|---|---|---|
| Something drives the application | `ITaskService` | `TaskEndpoints` turns HTTP requests into calls to it |
| The application drives storage | `ITaskRepository` | `TaskRepository`, with EF Core and PostgreSQL |
| The application sends mail (change 3) | `IMailSender` | `HttpMailSender`, an HTTP call |

The search shows how a request passes through them. The endpoint converts the request record and calls the service:

```csharp
public static async Task<Ok<List<TaskSummary>>> Search(TaskSearch search, ITaskService taskService, CancellationToken cancellationToken)
{
    var tasks = await taskService.SearchAsync(search.ToFilter(), cancellationToken);
    return TypedResults.Ok(tasks);
}
```

The service applies the page size and asks the repository port:

```csharp
public Task<List<TaskSummary>> SearchAsync(TaskFilter filter, CancellationToken cancellationToken) =>
    tasks.SearchAsync(filter, limit: 20, cancellationToken);
```

And the port says what storage must provide, in the Application's own types:

```csharp
public interface ITaskRepository
{
    Task<TaskItem?> GetAsync(int id, CancellationToken cancellationToken);
    Task<List<TaskSummary>> SearchAsync(TaskFilter filter, int limit, CancellationToken cancellationToken);
    Task<string?> FindAssigneeEmailAsync(int assigneeId, CancellationToken cancellationToken);
    void Add(TaskItem task);
    Task SaveAsync(CancellationToken cancellationToken);
}
```

What to notice:

- The port mentions no EF Core types: no `DbSet`, no `IQueryable`. `TaskRepository` implements it with EF Core; another class could implement it with anything else.
- `SearchAsync` returns `TaskSummary` records, not entities, so `TaskRepository` can select only the columns a summary needs. Both builds send the same SQL for a search, `SELECT t.id, t.title, t.done, t.due_on, t.priority, t.tags FROM tasks AS t …`. A port that returned `TaskItem` instead would load all ten columns and leave the trimming to the endpoint.
- The endpoint returns the Application's `TaskSummary` as the response body, because it's already the shape the client wants. `TaskDetails`, the single-task response, is a separate record in `In/`, converted from the entity by `TaskMapping`.

Robert C. Martin's "The Clean Architecture" (2012) adds the rule that makes this hold together: "source code dependencies can only point inwards. Nothing in an inner circle can know anything at all about something in an outer circle." Here, the Adapter project knows the Application project; the Application project knows nothing about the Adapter.

A common belief is that this style requires four projects, often named Domain, Application, Infrastructure, and Web. Martin's article draws four circles and then says "There's no rule that says you must always have just these four. However, The Dependency Rule always applies." The layered build here has two.

Another is that ports and adapters means an interface for every class. Cockburn writes: "My selection tends to favor a small number, two, three or four ports." This build has three. `TaskMapping` and `ETags` have no interfaces, because they don't talk to anything outside the process, and neither does `TaskBoardDb`, because it's already part of the adapter that implements `ITaskRepository`.

## What the compiler enforces

The Application project is a plain class library with no package references:

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
  </PropertyGroup>
</Project>
```

The Adapter project uses the Web SDK, references EF Core and the other packages, and has a `ProjectReference` to the Application project. So code in the Application project can't see EF Core, ASP.NET Core, or the Adapter's classes. Trying each one:

```text
Application code uses DbSet<TaskItem>:
  error CS0234: The type or namespace name 'EntityFrameworkCore' does not exist in the namespace 'Microsoft'
  error CS0246: The type or namespace name 'DbSet<>' could not be found

Application code returns IResult:
  error CS0234: The type or namespace name 'AspNetCore' does not exist in the namespace 'Microsoft'
  error CS0246: The type or namespace name 'IResult' could not be found

TaskService adds using TaskBoard.Tasks.Adapter.Out:
  error CS0234: The type or namespace name 'Adapter' does not exist in the namespace 'TaskBoard.Tasks'
```

Adding a reference from the Application project back to the Adapter project with `dotnet add reference` succeeds, but the next build fails with `error MSB4006: There is a circular dependency in the target dependency graph`. The dependency rule is checked on every build.

Two things still compile:

- `In/` and `Out/` are folders in one project, so an endpoint in `In/` can take a `TaskBoardDb` and query it directly, skipping the service and the repository. The build succeeds.
- Anything in the .NET base library is available everywhere. A class in the Application project that takes an `HttpClient` and posts to the mail service compiles. The compiler keeps EF Core and ASP.NET Core out, but it can't tell a mail service call from any other code; going through `IMailSender` is a convention.

The sliced build is one project, so the compiler checks only access modifiers. If `CompleteTask` calls the `private` method that `EditTask` uses to apply an edit, the build fails:

```text
error CS0122: 'EditTask.Apply(TaskItem, TaskEdit, DateTime)' is inaccessible due to its protection level
```

Anything `public` can be called from any slice, and `TaskBoardDb` can be used anywhere. Teams that want rules such as "slices don't call each other" write them as tests with a library such as NetArchTest, which inspects the compiled assembly.

## Change 1: completing a task

### Sliced: a new file

The sliced change adds `Tasks/CompleteTask.cs`, the same handler the endpoints article built, in its own class:

```csharp
public static class CompleteTask
{
    public static void Map(RouteGroupBuilder tasks) => tasks.MapPost("/{id:int}/complete", Handle);

    public static async Task<Results<NoContent, NotFound>> Handle(int id, TaskBoardDb db, CancellationToken cancellationToken)
    {
        var changed = await db.Tasks
            .Where(t => t.Id == id && !t.Done)
            .ExecuteUpdateAsync(s => s
                .SetProperty(t => t.Done, true)
                .SetProperty(t => t.CompletedAt, DateTime.UtcNow)
                .SetProperty(t => t.Version, t => t.Version + 1), cancellationToken);
        if (changed == 1)
        {
            return TypedResults.NoContent();
        }

        var exists = await db.Tasks.AnyAsync(t => t.Id == id, cancellationToken);
        if (!exists)
        {
            return TypedResults.NotFound();
        }

        return TypedResults.NoContent();
    }
}
```

and one line in `TaskRoutes.cs`:

```csharp
CompleteTask.Map(tasks);
```

That's 2 files in 1 project, 30 lines added.

### Layered: endpoint, port, and service

The layered change adds an endpoint that calls the service:

```csharp
tasks.MapPost("/{id:int}/complete", Complete);

public static async Task<Results<NoContent, NotFound>> Complete(int id, ITaskService taskService, CancellationToken cancellationToken)
{
    var found = await taskService.CompleteAsync(id, cancellationToken);
    if (!found)
    {
        return TypedResults.NotFound();
    }

    return TypedResults.NoContent();
}
```

a method on the port, in `Ports/In/ITaskService.cs`:

```csharp
Task<bool> CompleteAsync(int id, CancellationToken cancellationToken);
```

and the rule, in `TaskService`:

```csharp
public async Task<bool> CompleteAsync(int id, CancellationToken cancellationToken)
{
    for (var attempt = 1; ; attempt++)
    {
        var task = await tasks.GetAsync(id, cancellationToken);
        if (task is null)
        {
            return false;
        }

        if (task.Done)
        {
            return true;
        }

        task.Done = true;
        task.CompletedAt = DateTime.UtcNow;
        task.Version++;

        try
        {
            await tasks.SaveAsync(cancellationToken);
            return true;
        }
        catch (ConcurrencyConflictException) when (attempt < 3)
        {
            // Someone else changed the task first; load it again and recheck.
        }
    }
}
```

That's 3 files in 2 projects, 44 lines added. Both builds answer the same way: `204` for a completed task, `204` again with nothing changed when it's already done, and `404` for a missing one.

What to notice:

- The service can't send SQL, because the port has no method for it. It loads the task, changes it, and saves it, so EF Core sends two statements: a `SELECT` of the whole row, then `UPDATE tasks SET completed_at = @p0, done = @p1, version = @p2 WHERE id = @p3 AND version = @p4`.
- The sliced handler sends one: `UPDATE tasks AS t SET done = @p, completed_at = @p2, version = t.version + 1 WHERE t.id = @id AND NOT (t.done)`. The database decides who completes the task, which is the atomic update from the transactions article.
- The `for` loop and the `catch` in `CompleteAsync` retry the completion. The next section shows why they're there.

### Two people completing the same task

The layered `UPDATE` includes `version = @p4` because `Version` is configured as a concurrency token, as in [optimistic concurrency with EF Core](/dump/blog/transactions-and-concurrent-edits/#optimistic-concurrency-with-ef-core). If someone else saved the task after this request loaded it, the version no longer matches, the `UPDATE` changes no rows, and EF Core throws `DbUpdateConcurrencyException`.

`TaskService` can't catch that exception: its type lives in EF Core, which the Application project can't reference (`CS0246`). So the repository adapter translates it into an exception the Application project declares:

```csharp
public async Task SaveAsync(CancellationToken cancellationToken)
{
    try
    {
        await db.SaveChangesAsync(cancellationToken);
    }
    catch (DbUpdateConcurrencyException exception)
    {
        db.ChangeTracker.Clear();
        throw new ConcurrencyConflictException(exception);
    }
}
```

Clearing the change tracker matters for the retry: EF Core keeps [one instance per row](/dump/blog/ef-core-behind-the-scenes/#one-instance-per-row), so without it, the next `GetAsync` would hand back the same stale object instead of the row's current values.

To see what the retry is for, send eight completions for one new task at the same time, five times over, first with the `try` and `catch` removed from `CompleteAsync`:

```text
500 500 500 500 500 500 500 204
204 500 500 500 500 204 500 204
204 204 204 204 204 500 500 204
204 204 204 500 500 500 500 204
204 204 204 500 500 500 204 500
```

Every run ends with the task done and its version at 2, so the data is fine. The `500` responses are requests that loaded the task before the winner saved it; the log shows `ConcurrencyConflictException: The task changed after it was loaded`, wrapping EF Core's "expected to affect 1 row(s), but actually affected 0 row(s)". The `204` responses after the first are requests that loaded the task after it was saved and saw it already done. With the retry, all five runs answer `204` eight times, and so does the sliced build without any retry.

The repository could instead offer an atomic method, such as `TryCompleteAsync(id, now)`, running the same `ExecuteUpdate` as the sliced handler: one statement, and no conflict to handle. The tradeoff is that the rule itself, which fields change and only when the task isn't done, then lives in the Adapter's query, where a unit test of `TaskService` with a fake repository no longer checks it.

## Change 2: adding a priority

A priority is a `Low`, `Normal`, or `High` value on every task, which clients can set when creating or editing a task and see in every response. Both builds need the same core changes: the SQL column, a `TaskPriority` enum, a property on the entity, and `JsonStringEnumConverter` in `Program.cs` so the JSON carries `"High"` instead of `2`.

| Sliced: 8 files, 1 project, +20 −9 | Layered: 11 files, 2 projects, +26 −12 |
|---|---|
| `db/002-add-priority.sql` | `db/002-add-priority.sql` |
| `Data/TaskPriority.cs` (new) | `Model/TaskPriority.cs` (new) |
| `Data/Entities.cs` | `Model/TaskItem.cs` |
| `Program.cs` | `Program.cs` |
| `Tasks/CreateTask.cs` | `In/TaskContracts.cs` |
| `Tasks/EditTask.cs` | `In/TaskMapping.cs` |
| `Tasks/GetTask.cs` | `Model/TaskDraft.cs` |
| `Tasks/SearchTasks.cs` | `Model/TaskChanges.cs` |
| | `Model/TaskSummary.cs` |
| | `Out/TaskRepository.cs` |
| | `Services/TaskService.cs` |

The sliced build adds the field to each slice's own request and response records, and to the queries that fill them. The layered build has two kinds of extra places. The Application project has its own records, `TaskDraft` for creating and `TaskChanges` for editing, so the priority travels from the request record to the Application record to the entity. And `TaskMapping` converts between them by hand, so each conversion gains a field:

```csharp
public static TaskDraft ToDraft(this NewTask newTask) =>
    new(newTask.Title, newTask.AssigneeId, newTask.DueOn, newTask.Priority);

public static TaskChanges ToChanges(this TaskEdit edit) =>
    new(edit.Title, edit.DueOn, edit.Done, edit.Priority);
```

Libraries such as Mapperly generate methods like these at compile time from the records' properties, so you add the field to each record but not to each conversion. The Adapter's records use the Application's `TaskPriority` enum directly; a separate enum in the Adapter would add one more conversion.

Both builds then behave the same: a new task with `"priority":"High"` comes back with `"priority":"High"`, one without a priority gets `"Normal"`, and `"Urgent"` answers `400`.

## Change 3: mailing the assignee

The opening's request has two parts in either layout. The rule: when a task is completed, through `POST …/complete` or through a `PUT` or `PATCH` that sets `done`, mail its assignee. And the call to the mail service, a separate HTTP service in this example.

Both builds put the mail service behind a port, the same one in both:

```csharp
public record OutgoingMail(string To, string Subject, string Body);

public interface IMailSender
{
    Task SendAsync(OutgoingMail message, CancellationToken cancellationToken);
}
```

with an adapter that posts the message:

```csharp
public class HttpMailSender(HttpClient http) : IMailSender
{
    public async Task SendAsync(OutgoingMail message, CancellationToken cancellationToken)
    {
        var response = await http.PostAsJsonAsync("/messages", message, cancellationToken);
        response.EnsureSuccessStatusCode();
    }
}
```

What to notice:

- The sliced build has a port and an adapter too. Cockburn's reason applies whatever the layout: the mail service is outside the process, and tests should be able to run without it. A test passes a fake `IMailSender` that records messages instead of sending them.
- The name `IMailSender` avoids a clash with `IEmailSender`, an interface ASP.NET Core Identity already defines.
- Both builds also switch from `DateTime.UtcNow` to `TimeProvider`, .NET's built-in source of the current time. Its documentation says "By using TimeProvider, you ensure that your code is testable and predictable": the app registers `TimeProvider.System`, and a test passes a `FakeTimeProvider` set to a fixed time. `TimeProvider` is in the base library, so the Application project can use it without a package reference.

The rest differs in where the rule goes. In the sliced build, `CompleteTask` and `EditTask` each call a shared helper after saving:

```csharp
if (changed == 1)
{
    await CompletionMail.SendAsync(id, db, mailSender, cancellationToken);
    return TypedResults.NoContent();
}
```

`CompletionMail` reads the title and the assignee's email in one query and sends the message. In the layered build, `TaskService` gains `TimeProvider` and `IMailSender` as constructor parameters, `CompleteAsync` and `EditAsync` each call a private `MailAssigneeAsync` after saving, and the repository port gains `FindAssigneeEmailAsync` so the service can look up the address:

```csharp
try
{
    await tasks.SaveAsync(cancellationToken);
    await MailAssigneeAsync(task, cancellationToken);
    return true;
}
```

| Sliced: 7 production files | Layered: 7 production files |
|---|---|
| `Mail/IMailSender.cs` (new) | `Ports/Out/IMailSender.cs` (new) |
| `Mail/HttpMailSender.cs` (new) | `Out/HttpMailSender.cs` (new) |
| `Tasks/CompletionMail.cs` (new) | `Ports/Out/ITaskRepository.cs` |
| `Tasks/CompleteTask.cs` | `Out/TaskRepository.cs` |
| `Tasks/EditTask.cs` | `Services/TaskService.cs` |
| `Program.cs` | `Program.cs` |
| `appsettings.json` | `appsettings.json` |

With the tests updated, the commits are 10 files with +84 −14 lines in the sliced build and 11 files with +96 −9 in the layered build. In both, completing a task through any of the three endpoints sent exactly one email, and eight simultaneous completions of one task sent one email between them.

One behavior is the same in both, and it isn't what you'd want. With the mail service stopped, completing a task answers `500`, but the task is already saved as done, because the save happens before the email. Retrying answers `204`, since the task is done, and the email is never sent. Saving the task and calling another service can't happen in one transaction; making sure the email eventually goes out takes extra machinery that's outside this article's scope, and neither layout provides it.

## Finding a feature's code

Ask each codebase: what happens when a task is completed?

In the sliced build, you open `Tasks/CompleteTask.cs`. It has the route, the SQL, and the call to `CompletionMail`, which is one more file in the same folder. Completing through an edit is in `Tasks/EditTask.cs`.

In the layered build, you start at the `Complete` endpoint in `In/TaskEndpoints.cs`, follow `ITaskService` to its implementation in `Services/TaskService.cs`, and read `CompleteAsync`. For the SQL, you follow `ITaskRepository` to `Out/TaskRepository.cs`; for the email, `IMailSender` to `Out/HttpMailSender.cs`. That's more files, but each one answers one kind of question, and your editor's "go to implementation" command jumps from each interface to its class.

In both builds, the completion rule is written twice. The sliced build has the `ExecuteUpdate` in `CompleteTask` and the `Apply` method in `EditTask`; the layered build has `CompleteAsync` and `EditAsync`. Putting the rule in a service doesn't give it one home by itself. Moving it onto the entity would: a `Complete(DateTime now)` method on `TaskItem` that sets `Done`, `CompletedAt`, and the version, called by every path that completes a task. Jason Taylor's Clean Architecture template does something similar, raising an event from the `Done` property's setter. That's a design choice inside the layered layout, and this build keeps the anemic entity.

A sliced codebase faces the same question from the other direction. Bogard recommends starting each slice as a **transaction script**, one procedure that does everything a request needs: "start simple (Transaction Script) and simply refactor to the patterns that emerges from code smells we see in the business logic." He's direct about the condition: "If your team does not understand when a "service" is doing too much to push logic to the domain, this pattern is likely not for you."

A common belief is that slices share no code. Bogard writes "we keep our cross-slice logic sharing to a minimum", which is a minimum, not zero. The sliced build shares `CompletionMail`, `ETags`, and `TaskBoardDb`. Neither build has a shared `Common` project, because there's only one feature; when a second feature needs `ETags`, moving it to a shared project or folder is the usual step.

## Testing the completion rule

A **unit test** here means a test that runs the code in memory, with no database or network. A **test double** is an object that stands in for a real one in a test; a **fake** is a test double with a simple working implementation, such as a list instead of a table.

### Layered: the service with fakes

Because `TaskService` only knows ports, a test can construct it with fakes: a `FakeTaskRepository` that keeps tasks in a `List<TaskItem>` and counts saves, a `FakeMailSender` that records messages, and a `FakeTimeProvider` fixed at one moment.

```csharp
[Fact]
public async Task Completing_an_open_task_sets_done_and_completed_at_and_mails_the_assignee()
{
    var task = new TaskItem { Id = 1, Title = "Write the tests", AssigneeId = 7, Version = 1 };
    repository.Tasks.Add(task);
    repository.AssigneeEmails[7] = "ada@example.com";
    var service = new TaskService(repository, clock, mailSender);

    var found = await service.CompleteAsync(1, TestContext.Current.CancellationToken);

    Assert.True(found);
    Assert.True(task.Done);
    Assert.Equal(clock.GetUtcNow().UtcDateTime, task.CompletedAt);
    Assert.Equal(2, task.Version);
    Assert.Equal(1, repository.Saves);
    var mail = Assert.Single(mailSender.Sent);
    Assert.Equal("ada@example.com", mail.To);
}
```

This test, plus one for an already-done task and one for a missing task, ran in 100 ms with no database. The test project references only the Application project.

The fake can't check SQL. It doesn't know whether `TaskRepository` maps the columns correctly, sends the version check, or translates EF Core's exception. Those need tests of the adapter against a real database:

```csharp
[Fact]
public async Task Saving_a_stale_task_throws_the_application_exception()
{
    // …two contexts load the same task; the first one saves a change
    stale!.Title = "Second edit";
    stale.Version++;

    await Assert.ThrowsAsync<ConcurrencyConflictException>(() => secondRepository.SaveAsync(TestContext.Current.CancellationToken));
}
```

That test and a save-and-reload round trip ran in 630 ms against PostgreSQL. The fake repository's `SearchAsync` throws `NotSupportedException`, because a list can't tell you whether a query works; searches get database tests too.

### Sliced: the handler against PostgreSQL

`CompleteTask.Handle` is a static method, so a test calls it directly, as in [the controllers article's testing section](/dump/blog/controllers-and-minimal-apis/#testing), with a real `TaskBoardDb` pointed at a test database and the same two fakes:

```csharp
[Fact]
public async Task Completing_an_open_task_sets_done_and_completed_at_and_mails_the_assignee()
{
    await using var db = database.CreateContext();
    var assignee = new User { Name = "Ada", Email = $"ada-{Guid.NewGuid()}@example.com", Active = true };
    var task = new TaskItem { Title = "Write the tests", Assignee = assignee, Version = 1 };
    db.Tasks.Add(task);
    await db.SaveChangesAsync(TestContext.Current.CancellationToken);

    var result = await CompleteTask.Handle(task.Id, db, clock, mailSender, TestContext.Current.CancellationToken);

    Assert.IsType<NoContent>(result.Result);
    await db.Entry(task).ReloadAsync(TestContext.Current.CancellationToken);
    Assert.True(task.Done);
    Assert.Equal(clock.GetUtcNow().UtcDateTime, task.CompletedAt);
    Assert.Equal(2, task.Version);
    var email = Assert.Single(mailSender.Sent);
    Assert.Equal(assignee.Email, email.To);
}
```

The same three cases ran in 769 ms, and they check the rule and the SQL together, including the `NOT (t.done)` condition.

### What the EF Core docs recommend

Two beliefs come up here. One is that a handler using `DbContext` can't be tested; the test above does it by giving the handler a real database. The other is that EF Core needs a repository to be testable. EF Core's testing guide starts with the database: "We recommend that developers have good test coverage of their application running against their actual production database system." It recommends a repository only as a choice you make for test doubles: "If you've decided to use a test double, we recommend implementing the repository pattern, which allows you to stub or mock out your data access layer above EF Core, rather than using a fake EF Core provider (Sqlite/in-memory) or by mocking DbSet." It adds two conditions that the layered build follows: "your repository cannot expose any IQueryable-returning methods", and "tests against the real database are still likely to be needed for the queries exposed by the repository."

So the layered build buys fast tests of its rules, and pays with a repository port, a fake, and adapter tests against the database anyway. The sliced build has fewer, slower tests that cover the rule and the SQL at once. Microsoft's architecture e-book makes the layered case: "Because the Application Core doesn't depend on Infrastructure, it's very easy to write automated unit tests for this layer."

## Startup registrations

The two `Program.cs` files register the same services, with two extra lines in the layered build:

```csharp
builder.Services.AddNpgsqlDataSource(builder.Configuration.GetConnectionString("TaskBoard")!);
builder.Services.AddDbContext<TaskBoardDb>(options => options.UseNpgsql().UseSnakeCaseNamingConvention());
builder.Services.AddScoped<ITaskRepository, TaskRepository>(); // layered only
builder.Services.AddScoped<ITaskService, TaskService>();       // layered only
builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddHttpClient<IMailSender, HttpMailSender>(client => client.BaseAddress = new Uri(builder.Configuration["Mail:BaseUrl"]!));
builder.Services.ConfigureHttpJsonOptions(options => options.SerializerOptions.Converters.Add(new JsonStringEnumConverter()));
builder.Services.AddValidation();
builder.Services.AddProblemDetails();
builder.Services.AddOpenApi();
```

What to notice:

- Each extra line registers a class under the interface it implements, as [the dependency injection article](/dump/blog/aspnet-core-dependency-injection/#a-container-that-does-the-wiring) showed, so asking for `ITaskService` gets a `TaskService`.
- Both are scoped because `TaskRepository` uses the scoped `TaskBoardDb`; a singleton repository would be a [captive dependency](/dump/blog/aspnet-core-dependency-injection/#captive-dependencies-and-scope-validation).
- `AddHttpClient<IMailSender, HttpMailSender>` registers the mail adapter in both builds and gives it an `HttpClient` with the configured base address.
- Templates with more projects often move these lines into one extension method per project, such as `AddApplicationServices()` and `AddInfrastructureServices()` in Jason Taylor's template.

## When each fits

**Layered fits** when:

- Several entry points drive the same rules: HTTP endpoints, but also a queue listener, a scheduled job, or a command-line tool, all calling `ITaskService`. That's Cockburn's "driven by users, programs, automated test or batch scripts."
- You want the compiler to keep business code free of EF Core and ASP.NET Core, and you're willing to translate exceptions and records in the Adapter project to get that.
- The rules are involved enough that fast unit tests without a database pay for the repository port and its fake.
- An outside system really has several implementations, Cockburn's "multiple adapters for any one port", such as two payment providers. Swapping the database is the classic example, but Fowler notes "I rarely hear of someone actually doing it."

**Sliced fits** when:

- Features change independently, and most changes are "add a field to this endpoint" or "add an endpoint", where one file per request keeps each change in one place.
- Many endpoints mostly read and write rows. `TaskService.SearchAsync` is a one-line method that passes the call on; a sliced layout doesn't need it.
- An operation is best written as one SQL statement next to its rule, like the atomic completion.
- The team refactors shared logic out of slices when it starts repeating, which is Bogard's condition.

Most codebases mix them. The sliced build here still has a port and an adapter for the mail service, the one thing outside the process besides the database. Jason Taylor's Clean Architecture template goes the other way: its documentation says "Features are organised as vertical slices inside each layer." Microsoft's eShop reference app builds its Ordering service as layered projects with repositories and its Catalog service as one project whose endpoints use the `DbContext` directly. Steve Smith (Ardalis) maintains templates for both, a layered Clean Architecture template and a sliced one called Minimal Clean, and suggests "Start with Minimal Clean and migrate to Full Clean Architecture if your application grows in complexity."

## Back to the email

So where did "mail the assignee" go? In the sliced build, into the two slices that complete tasks, through one shared helper, with the mail service behind `IMailSender` in a `Mail` folder. In the layered build, into `TaskService`, with `IMailSender` as a port in the Application project, `HttpMailSender` as the adapter in `Out/`, and one more method on the repository port to look up the address.

Both builds ended up with the same port and adapter for the mail service, because it's outside the process and tests need to replace it. That's where adapters belong in either layout. What the layouts disagree on is everything inside the process: whether the endpoints and the database code also sit behind ports, so the rules can be compiled and tested without them.

| | Layered | Sliced |
|---|---|---|
| Projects for the Tasks feature | 2 | 1 |
| C# files and lines after three changes | 20 files, 524 lines | 14 files, 398 lines |
| Completing a task | 3 files in 2 projects | 2 files in 1 project |
| Adding a priority | 11 files in 2 projects | 8 files in 1 project |
| Mailing the assignee | 7 production files | 7 production files |
| Completion SQL | load, then `UPDATE … WHERE version = …` | one `UPDATE … WHERE NOT (t.done)` |
| Simultaneous completions | `500`s without a retry in the service | atomic in the database |
| Compiler keeps EF Core and ASP.NET Core out of the rules | yes | no |
| Testing the completion rule | fakes and no database, plus adapter tests against PostgreSQL | handler against PostgreSQL |
| Extra startup registrations | 2 | none |
| Mail service | port and adapter | port and adapter |

## Check your understanding

1. **The sliced build has no Application project. Why does it still put the mail service behind `IMailSender`?** The mail service is outside the process. Tests pass a fake that records messages, so they run without it, and the rest of the code doesn't depend on how mail is sent. That reason doesn't depend on the layout, which is why both builds have the same port and adapter.
2. **`TaskService` needs to know when a save lost to a concurrent edit, but EF Core reports that with `DbUpdateConcurrencyException`. Why can't the service catch it, and what does the build do instead?** The exception's type is in EF Core, and the Application project has no reference to EF Core, so naming it fails with `CS0246`. The repository adapter catches it, clears the change tracker, and throws the Application's own `ConcurrencyConflictException`, which the service catches to reload and retry.
3. **A teammate says you can't test `CompleteTask.Handle` because it takes a `TaskBoardDb`. What does the article show, and what do the EF Core docs recommend?** The test calls the handler directly with a `TaskBoardDb` pointed at a real test database, plus a fake clock and mail sender. EF Core's docs recommend testing against your production database system first, and a repository only if you choose test doubles, with no `IQueryable` methods and database tests still needed for its queries.
4. **Adding a priority touched 11 files in the layered build and 8 in the sliced one. Where did the extra changes go, and what do those places buy?** Into the Application's own records (`TaskDraft`, `TaskChanges`, `TaskSummary`), the hand-written conversions in `TaskMapping`, and the repository's query. They keep the Application project free of request records and EF Core, so the compiler can enforce the dependency rule and the service can be tested without a database.

## Sources and further reading

- Alistair Cockburn, [Hexagonal Architecture](https://alistair.cockburn.us/hexagonal-architecture) (2005).
- Robert C. Martin, [The Clean Architecture](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html) (2012).
- Jimmy Bogard, [Vertical Slice Architecture](https://www.jimmybogard.com/vertical-slice-architecture/) (2018).
- Martin Fowler, [PresentationDomainDataLayering](https://martinfowler.com/bliki/PresentationDomainDataLayering.html) (2015).
- Microsoft, [Common web application architectures](https://learn.microsoft.com/en-us/dotnet/architecture/modern-web-apps-azure/common-web-application-architectures), from the "Architect Modern Web Applications with ASP.NET Core and Azure" e-book. Its testing chapter still uses EF Core's in-memory provider, which EF Core's own testing guide now advises against, and its index points to a newer guide.
- EF Core, [Choosing a testing strategy](https://learn.microsoft.com/en-us/ef/core/testing/choosing-a-testing-strategy) and [Testing without your production database system](https://learn.microsoft.com/en-us/ef/core/testing/testing-without-the-database).
- .NET, [What is TimeProvider?](https://learn.microsoft.com/en-us/dotnet/standard/datetime/timeprovider-overview) and [FakeTimeProvider](https://learn.microsoft.com/en-us/dotnet/api/microsoft.extensions.time.testing.faketimeprovider).
- Templates, read at the commits given: [jasontaylordev/CleanArchitecture](https://github.com/jasontaylordev/CleanArchitecture/tree/1bc2b07ce75864b0c399e8e3d481de5e17aad509), [ardalis/CleanArchitecture](https://github.com/ardalis/CleanArchitecture/tree/e7c79be54ba0b001a5b332c1efe935f520b9db4b), [SSWConsulting/SSW.VerticalSliceArchitecture](https://github.com/SSWConsulting/SSW.VerticalSliceArchitecture/tree/42e7a70804d550f53a1a4a1c4159f8d457bafaba), and [dotnet/eShop](https://github.com/dotnet/eShop/tree/913acea66708a59595351174cee9b29f37179d29).
