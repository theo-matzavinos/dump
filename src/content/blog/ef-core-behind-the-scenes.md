---
title: "Why the same LINQ filter can read a million rows: what EF Core sends to PostgreSQL, and when to write SQL yourself"
description: "Read the SQL EF Core sends, learn where a LINQ filter actually runs, what change tracking and SaveChanges do, how to avoid N+1 queries, and when FromSql, ExecuteUpdate, or Dapper is the better tool."
pubDate: "2026-10-19T13:00:00Z"
tags:
  - ef-core
  - dotnet
  - postgresql
  - performance
audience:
  - backend
---

The task board's "my open tasks" endpoint, written with EF Core, sends exactly the query from [the SQL article](/dump/blog/sql-indexes-and-parameters/) and uses its `(assignee_id, due_on)` index. Then someone tidies it up. The open-tasks filter is useful elsewhere, so it moves into a helper:

```csharp
static IEnumerable<TaskItem> OpenTasksOf(IEnumerable<TaskItem> tasks, int userId)
{
    return tasks.Where(t => t.AssigneeId == userId && !t.Done);
}
```

The endpoint still returns the same 20 tasks. But it now takes two to three seconds instead of a few milliseconds, allocates about 970 MB of memory, and creates a million task objects to find those 20. The log shows the query EF Core sent:

```sql
SELECT t.id, t.assignee_id, t.created_at, t.done, t.due_on, t.title
FROM tasks AS t
```

There's no `WHERE`. The C# still says `Where(t => t.AssigneeId == userId && !t.Done)`, so where did the filter go? Answering that takes knowing what EF Core actually does with your LINQ, and that's what this article is about: how EF Core maps your classes to tables, how to read the SQL it sends, what it remembers about the objects it gives you, and when writing the SQL yourself is the better choice.

You'll need C# lambdas and LINQ methods such as `Where`, `OrderBy`, and `Select`. You'll also need [the SQL article](/dump/blog/sql-indexes-and-parameters/) for tables, indexes, `explain analyze`, parameters, and SQL injection; [Who creates your services](/dump/blog/aspnet-core-dependency-injection/) for scoped services; and [Waiting without blocking](/dump/blog/aspnet-core-async-and-the-thread-pool/) for `await`, cancellation tokens, and why one unit of work runs one operation at a time.

## Contents

1. [Set up the example](#set-up-the-example)
2. [Mapping the existing tables](#mapping-the-existing-tables)
3. [Seeing the SQL EF Core sends](#seeing-the-sql-ef-core-sends)
4. [IQueryable and IEnumerable: where the filter runs](#iqueryable-and-ienumerable-where-the-filter-runs)
5. [Change tracking and what SaveChanges sends](#change-tracking-and-what-savechanges-sends)
6. [One instance per row](#one-instance-per-row)
7. [Reads that don't need tracking](#reads-that-dont-need-tracking)
8. [One context per request, one operation at a time](#one-context-per-request-one-operation-at-a-time)
9. [Loading related data and the N+1 problem](#loading-related-data-and-the-n1-problem)
10. [Writing SQL yourself: FromSql and SqlQuery](#writing-sql-yourself-fromsql-and-sqlquery)
11. [Bulk changes: ExecuteUpdate and ExecuteDelete](#bulk-changes-executeupdate-and-executedelete)
12. [Dapper next to EF Core](#dapper-next-to-ef-core)
13. [Back to the missing WHERE](#back-to-the-missing-where)

## Set up the example

The examples use the .NET 10 SDK, the Npgsql EF Core provider 10.0.3 (which brings EF Core 10.0.4), EFCore.NamingConventions 10.0.1, Dapper 2.1.89, and PostgreSQL 18.6 with the SQL article's database: its `seed.sql` plus the index `create index on tasks (assignee_id, due_on);`. The numbers come from one laptop with the database on the same machine, so every query's round trip is far cheaper than it would be over a network. Memory figures and some timings come from running the same queries in a small console program built in Release mode. Transactions, concurrency, schema changes, and migrations are outside this article's scope.

Create the API and add the packages:

```bash
dotnet new web -o TaskBoard
cd TaskBoard
dotnet add package Npgsql.EntityFrameworkCore.PostgreSQL --version 10.0.3
dotnet add package Npgsql.DependencyInjection --version 10.0.3
dotnet add package EFCore.NamingConventions --version 10.0.1
dotnet add package Dapper --version 2.1.89
```

## Mapping the existing tables

**EF Core** is an object-relational mapper: it turns C# objects into rows and back, and LINQ queries into SQL. It needs to know which classes go with which tables.

A class whose objects stand for rows is called an **entity**. Here are the two the task board needs, in `Entities.cs`:

```csharp
public class User
{
    public int Id { get; set; }
    public string Name { get; set; } = "";
    public string Email { get; set; } = "";
    public bool Active { get; set; }
    public List<TaskItem> Tasks { get; set; } = [];
}

public class TaskItem
{
    public int Id { get; set; }
    public string Title { get; set; } = "";
    public bool Done { get; set; }
    public int? AssigneeId { get; set; }
    public User? Assignee { get; set; }
    public DateOnly? DueOn { get; set; }
    public DateTime CreatedAt { get; set; }
}
```

What to notice:

- `TaskItem` is now a class with settable properties instead of the earlier articles' record, because EF Core changes these objects after creating them.
- `Assignee` and `Tasks` are **navigation properties**: they point at related entities instead of holding a column's value. EF Core sees that `AssigneeId` sits next to `Assignee` and treats it as the foreign key, and it treats `Id` as the primary key. These are its **conventions**: rules it applies unless you configure something else.
- The nullable types match the table: `assignee_id` and `due_on` allow null, so their properties are `int?` and `DateOnly?`.

A **`DbContext`** is the object you query through and save through. Each **`DbSet<T>`** property on it stands for one table:

```csharp
using Microsoft.EntityFrameworkCore;

public class TaskBoardDb(DbContextOptions<TaskBoardDb> options) : DbContext(options)
{
    public DbSet<TaskItem> Tasks => Set<TaskItem>();
    public DbSet<User> Users => Set<User>();
}
```

Register it in `Program.cs`:

```csharp
using Microsoft.EntityFrameworkCore;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddNpgsqlDataSource("Host=localhost;Port=5432;Username=postgres;Password=taskboard;Database=taskboard");
builder.Services.AddDbContext<TaskBoardDb>(options => options.UseNpgsql());
```

Ask it for one task, and PostgreSQL refuses:

```text
Npgsql.PostgresException: 42P01: relation "Tasks" does not exist
```

The log shows what EF Core sent:

```sql
SELECT t."Id", t."AssigneeId", t."CreatedAt", t."Done", t."DueOn", t."Title"
FROM "Tasks" AS t
```

EF Core took the names from your C#: the `DbSet` property for the table, the property names for the columns. It also put them in double quotes, because PostgreSQL turns unquoted names into lowercase, and quoting keeps the capital letters. But the tables were created as `tasks` and `assignee_id`. You could name each one explicitly:

```csharp
modelBuilder.Entity<TaskItem>().Property(t => t.AssigneeId).HasColumnName("assignee_id");
```

for every table and column. Npgsql's documentation recommends the EFCore.NamingConventions package instead, which converts every name to lowercase with underscores, called **snake case**, in one line:

```csharp
builder.Services.AddDbContext<TaskBoardDb>(options => options.UseNpgsql().UseSnakeCaseNamingConvention());
```

Two details about this registration:

- **`AddDbContext` registers the context as scoped**, so each request gets its own, disposed at the end of the request. The [dependency injection article](/dump/blog/aspnet-core-dependency-injection/) explains what that means.
- **`UseNpgsql()` with no connection string uses the data source registered by `AddNpgsqlDataSource`.** That's how the provider's source code behaves, though its documentation doesn't spell it out. EF Core and any SQL you write by hand then share one pool of connections.

Endpoints return small records, such as `public record OpenTask(int Id, string Title, DateOnly? DueOn);`, instead of entities. [One task, different models](/dump/blog/api-responses-to-ui-models/) explains why a row and a response deserve different shapes.

**SQL Server:** tables there are usually named in PascalCase already, so no naming convention is needed.

## Seeing the SQL EF Core sends

Here's the endpoint the opening started from:

```csharp
app.MapGet("/users/{userId:int}/open-tasks", async (int userId, TaskBoardDb db, CancellationToken cancellationToken) =>
{
    return await db.Tasks
        .Where(t => t.AssigneeId == userId && !t.Done)
        .OrderBy(t => t.DueOn)
        .Take(20)
        .Select(t => new OpenTask(t.Id, t.Title, t.DueOn))
        .ToListAsync(cancellationToken);
});
```

You don't need to turn anything on to see its SQL. The `web` template's `appsettings.json` logs at the `Information` level, and EF Core logs every command at that level under the category `Microsoft.EntityFrameworkCore.Database.Command`:

```text
info: Microsoft.EntityFrameworkCore.Database.Command[20101]
      Executed DbCommand (2ms) [Parameters=[@userId='?' (DbType = Int32), @p='?' (DbType = Int32)], CommandType='Text', CommandTimeout='30']
      SELECT t.id, t.title, t.due_on
      FROM tasks AS t
      WHERE t.assignee_id = @userId AND NOT (t.done)
      ORDER BY t.due_on
      LIMIT @p
```

What to notice:

- **The SQL matches the LINQ** step by step: `Where` became `WHERE`, `OrderBy` became `ORDER BY`, `Take(20)` became `LIMIT`, and `Select` asked for only three columns.
- **`userId` became a parameter, `@userId`.** EF Core turns variables into parameters. A constant written directly in the lambda, such as `t.AssigneeId == 7`, appears in the SQL as the literal `7` instead.
- **The values show as `'?'`.** EF Core hides parameter values by default, because they can contain personal data. Adding `.EnableSensitiveDataLogging()` to the options shows `@userId='7'`; use it only in `Development`.
- **`Executed DbCommand (2ms)`** is the time until PostgreSQL started returning rows, not the time to read all of them. The opening's million-row read logged 16 ms and took seconds.

Right below it, Npgsql logs the same command the way PostgreSQL receives it, with `$1` and `$2` instead of names. That's the parameter mechanism from the SQL article. Once you've seen it, set `"Npgsql": "Warning"` under `Logging:LogLevel` in `appsettings.json` so each query isn't logged twice. The rest of the article shows only the SQL from these log entries.

To see a query's SQL without running it, call `ToQueryString()` on it.

## IQueryable and IEnumerable: where the filter runs

`db.Tasks` is an `IQueryable<TaskItem>`. Calling `Where` on it picks the method `Queryable.Where`, which takes an `Expression<Func<TaskItem, bool>>`. For a parameter of that type, the C# compiler doesn't compile your lambda into code. It builds a data structure describing it, called an **expression tree**: "compare property `AssigneeId` with variable `userId`, and check that `Done` is false". EF Core reads that structure and translates it to SQL.

`IEnumerable<TaskItem>` has its own `Where`, `Enumerable.Where`, which takes a plain `Func<TaskItem, bool>`. There, the compiler compiles the lambda into ordinary code, and `Where` runs it on each object, one at a time, in memory.

The lambda looks identical in both cases. The type of the variable you call `Where` on decides which one you get. Nothing is sent to the database until you **enumerate** the query, by calling something like `ToListAsync`, `FirstAsync`, or `CountAsync`, or looping over it.

That explains the opening. The helper's parameter is `IEnumerable<TaskItem>`, so inside it `tasks.Where(...)` is `Enumerable.Where`. Passing `db.Tasks` in is allowed, because every `IQueryable` is also an `IEnumerable`, but EF Core never sees the filter. When `ToList()` finally enumerates, EF Core is asked for every task, sends a `SELECT` with no `WHERE`, and creates a million objects for `Enumerable.Where` to check:

| The helper takes | SQL sent | Endpoint time | Allocated | Entities tracked |
|---|---|---|---|---|
| `IEnumerable<TaskItem>` | no `WHERE`, every column, every row | 1.8 to 3 s | about 970 MB | 1,000,000 |
| `IQueryable<TaskItem>` | `WHERE`, `ORDER BY`, `LIMIT`, three columns | 2 to 23 ms | 141 KB | 0 |

The fix is the parameter type, and it lets the endpoint stay asynchronous too:

```csharp
static IQueryable<TaskItem> OpenTasksOf(IQueryable<TaskItem> tasks, int userId)
{
    return tasks.Where(t => t.AssigneeId == userId && !t.Done);
}
```

A related belief is that `ToList()` or `ToListAsync()` is harmless as long as it comes at the end. It is, but "the end" means the end of everything you want the database to do. `ToListAsync` runs the query, so every operator after it works on a `List<TaskItem>` in memory. Here's the same open-tasks query with `ToListAsync` in three places.

**First,** with everything else applied to the list:

```csharp
var all = await db.Tasks.ToListAsync(cancellationToken);
var tasks = all
    .Where(t => t.AssigneeId == userId && !t.Done)
    .OrderBy(t => t.DueOn)
    .Take(20)
    .Select(t => new OpenTask(t.Id, t.Title, t.DueOn))
    .ToList();
```

```sql
SELECT t.id, t.assignee_id, t.created_at, t.done, t.due_on, t.title
FROM tasks AS t
```

This is the opening's mistake in a different form: every row, every column, and a million tracked entities, taking 3.2 to 3.8 seconds.

**In the middle,** after the filter but before the sorting and paging:

```csharp
var open = await db.Tasks
    .Where(t => t.AssigneeId == userId && !t.Done)
    .ToListAsync(cancellationToken);
var tasks = open
    .OrderBy(t => t.DueOn)
    .Take(20)
    .Select(t => new OpenTask(t.Id, t.Title, t.DueOn))
    .ToList();
```

```sql
SELECT t.id, t.assignee_id, t.created_at, t.done, t.due_on, t.title
FROM tasks AS t
WHERE t.assignee_id = @userId AND NOT (t.done)
```

The `WHERE` made it into the SQL, but `ORDER BY` and `LIMIT` didn't. PostgreSQL returns all 160 of user 7's open tasks, with every column, EF Core creates and tracks 160 entities, and C# sorts them to keep 20. For user 7 that's still fast, about 5 ms, but the work grows with every task a user has, where the paged query's doesn't.

**Last,** after every operator the database can do:

```csharp
var tasks = await db.Tasks
    .Where(t => t.AssigneeId == userId && !t.Done)
    .OrderBy(t => t.DueOn)
    .Take(20)
    .Select(t => new OpenTask(t.Id, t.Title, t.DueOn))
    .ToListAsync(cancellationToken);
```

```sql
SELECT t.id, t.title, t.due_on
FROM tasks AS t
WHERE t.assignee_id = @userId AND NOT (t.done)
ORDER BY t.due_on
LIMIT @p
```

Everything is in the SQL: PostgreSQL uses the index, stops after 20 rows, and sends three columns, and EF Core tracks nothing because of the projection. So put `ToListAsync` after the last `Where`, `OrderBy`, `Take`, and `Select`, and check the log: anything missing from the SQL happened in memory.

### What EF Core can't translate

Your own C# methods have no SQL equivalent. Here's one that formats a due date:

```csharp
public static class Labels
{
    public static string DueLabel(DateOnly? dueOn)
    {
        if (dueOn is null)
        {
            return "no due date";
        }

        return $"due {dueOn:yyyy-MM-dd}";
    }
}
```

Use it in a `Where`, `db.Tasks.Where(t => Labels.DueLabel(t.DueOn) == "no due date")`, and EF Core refuses instead of quietly loading everything:

```text
System.InvalidOperationException: The LINQ expression 'DbSet<TaskItem>()
    .Where(t => Labels.DueLabel(t.DueOn) == "no due date")' could not be translated. Additional information: Translation of method 'Labels.DueLabel' failed. … Either rewrite the query in a form that can be translated, or switch to client evaluation explicitly by inserting a call to 'AsEnumerable', 'AsAsyncEnumerable', 'ToList', or 'ToListAsync'.
```

In the final `Select`, the same method works:

```csharp
.Select(t => new { t.Title, Due = Labels.DueLabel(t.DueOn) })
```

EF Core sends `SELECT t.title, t.due_on …` and calls `DueLabel` in memory on each row it reads. Running C# on the results is called **client evaluation**, and EF Core allows it only in that last projection, where it can't change which rows come back. Sort by the method's result afterwards, and you get the same exception again.

**Engine note:** `t.Title.Contains(term)` becomes `title LIKE @term_contains`, and `LIKE` is case-sensitive in PostgreSQL. Searching for "audit" with `Contains` found 0 tasks; `EF.Functions.ILike(t.Title, $"%{term}%")` found all 20 "Audit" tasks. SQL Server and MySQL usually use case-insensitive collations by default, so the same LINQ can give different results there.

## Change tracking and what SaveChanges sends

When a query returns entities, EF Core doesn't just hand them over. It keeps a record of each one: a copy of its values as loaded, and a **state** such as `Unchanged`, `Modified`, `Added`, or `Deleted`. That's **change tracking**. When you call `SaveChanges`, EF Core compares each tracked entity with its copy, a step called **`DetectChanges`**, and sends SQL for the differences.

Change one title and look at what the context knows:

```csharp
var task = await db.Tasks.SingleAsync(t => t.Id == 41);
task.Title = "Write the API docs, again";
db.ChangeTracker.DetectChanges();
Console.WriteLine(db.ChangeTracker.DebugView.LongView);
```

```text
TaskItem {Id: 41} Modified
    Id: 41 PK
    AssigneeId: 451 FK
    CreatedAt: '07/13/2026 23:36:03'
    Done: 'False'
    DueOn: '01/17/2027'
    Title: 'Write the API docs, again' Modified Originally 'Write the API docs #41'
  Assignee: <null>
```

`await db.SaveChangesAsync()` then sends exactly one statement, for exactly one column:

```sql
UPDATE tasks SET title = @p0
WHERE id = @p1;
```

It returns `1`, the number of rows written, and the entity's state goes back to `Unchanged`. Assign the same title again and call `SaveChangesAsync()` once more, and nothing is sent at all: it returns `0`, because the value didn't change.

Before adding rows, tell EF Core about the table's column defaults. Without that, EF Core assumes it should send every mapped column, so an insert includes `created_at` with the C# default of `CreatedAt`, `0001-01-01`. The table's `default now()` never applies, and Npgsql stores that minimum date as PostgreSQL's `-infinity`. Add this to `TaskBoardDb`:

```csharp
protected override void OnModelCreating(ModelBuilder modelBuilder)
{
    modelBuilder.Entity<TaskItem>().Property(t => t.CreatedAt).HasDefaultValueSql("now()");
}
```

When you map a table that already exists, tell EF Core about every column the database fills in.

Several changes travel together. Change one task's due date and another's title, and add a new task:

```csharp
var added = new TaskItem { Title = "Learn change tracking", AssigneeId = 7 };
db.Tasks.Add(added);
await db.SaveChangesAsync();
```

```sql
UPDATE tasks SET due_on = @p0
WHERE id = @p1;
UPDATE tasks SET title = @p2
WHERE id = @p3;
INSERT INTO tasks (assignee_id, done, due_on, title)
VALUES (@p4, @p5, @p6, @p7)
RETURNING id, created_at;
```

All three statements go to PostgreSQL in one round trip. The `INSERT` leaves out `created_at` so the table's default applies, and `RETURNING id, created_at` sends back the values PostgreSQL generated, so `added.Id` is `0` before saving and `1000001` after. Because this save sends several statements, EF Core wraps them in a transaction and logs "Began transaction" and "Committed transaction" around them: either all three are written or none is. A save that sends a single statement doesn't start one.

## One instance per row

Within one context, each row gets exactly one object. Load task 44, change its title without saving, and load it again:

```csharp
var first = await db.Tasks.SingleAsync(t => t.Id == 44);
first.Title = "Changed in memory";
var second = await db.Tasks.SingleAsync(t => t.Id == 44);
```

The second query really runs; the log shows the same `SELECT` twice. But `second` is the same object as `first`, and its title is still "Changed in memory". When a query returns a row the context already tracks, EF Core gives you the tracked object and doesn't overwrite it with the database's values. This is called the **identity map**.

`await db.Tasks.FindAsync(44)` goes one step further: it looks in the identity map first, finds task 44, and returns it without sending any query.

Because each request gets its own context, each request starts with an empty identity map.

## Reads that don't need tracking

It's tempting to dismiss `AsNoTracking()` as a micro-optimization. Here's what tracking costs when reading 100,000 tasks, the same query three ways:

| Query | Time | Allocated | Entities tracked |
|---|---|---|---|
| Plain tracking query | about 240 ms | 99 MB | 100,000 |
| `.AsNoTracking()` | 58 to 64 ms | 37 MB | 0 |
| `.Select(t => new OpenTask(…))` | 54 to 63 ms | 35 MB | 0 |

Times varied between runs on this machine, and the first run of the tracking query took much longer; the allocations stayed the same. Tracking keeps a copy of every row and an entry for every object, and that's most of the cost.

`AsNoTracking` gives that up, and with it the things tracking provides. Two no-tracking queries for the same row return two separate objects. And a change to a no-tracking entity goes nowhere:

```csharp
var task = await db.Tasks.AsNoTracking().SingleAsync(t => t.Id == 45);
task.Title = "This change is ignored";
var saved = await db.SaveChangesAsync();
```

`saved` is `0`, and `db.Entry(task).State` is `Detached`: the context doesn't know the object exists.

A **projection**, a `Select` into a type that isn't an entity, never tracks anything, and it also asks only for the columns you name. That's why the open-tasks endpoint's `Select` sent `SELECT t.id, t.title, t.due_on`. It's the same query as in the SQL article, so it gets the same plan:

```text
 Limit
   ->  Index Scan using tasks_assignee_id_due_on_idx on tasks
         Index Cond: (assignee_id = 7)
         Filter: (NOT done)
```

Whether an index helps depends only on the SQL that reaches PostgreSQL, not on whether you or EF Core wrote it. So for endpoints that only read, project into the response type. Load tracked entities when you're going to change them.

## One context per request, one operation at a time

EF Core's API documentation describes the class this way: "DbContext is a combination of the Unit Of Work and Repository patterns." Its configuration guide adds that "a DbContext instance is designed to be used for a single unit-of-work." A **unit of work** gathers the changes one piece of work makes and saves them together, the role `TaskChanges` played in the [dependency injection article](/dump/blog/aspnet-core-dependency-injection/), and in a web API, one piece of work is usually one request.

A common idea is to make the context a singleton, to avoid creating one per request. Register it that way, `AddDbContext<TaskBoardDb>(…, ServiceLifetime.Singleton)`, and two things happen. Every request now shares one identity map, so it keeps growing: three requests in a row reported 2, 3, and then 4 tracked entities. And requests that arrive together collide. Sending 200 requests, 50 at a time:

| Context lifetime | Succeeded | Failed with `500` |
|---|---|---|
| Singleton | 48 | 152 |
| Scoped, the default | 200 | 0 |

The failures logged this exception:

```text
System.InvalidOperationException: A second operation was started on this context instance before a previous operation completed. This is usually caused by different threads concurrently using the same instance of DbContext.
```

A context isn't thread-safe: it handles one query at a time. You can hit the same exception within a single request, by starting two queries on one context at once:

```csharp
var openTask = db.Tasks.CountAsync(t => t.AssigneeId == userId && !t.Done);
var doneTask = db.Tasks.CountAsync(t => t.AssigneeId == userId && t.Done);
await Task.WhenAll(openTask, doneTask);
```

This is the case the [async article](/dump/blog/aspnet-core-async-and-the-thread-pool/) warned about when it introduced `Task.WhenAll`. Await the queries one after the other, or give each its own context.

## Loading related data and the N+1 problem

The board shows each task with its assignee's name. Many developers expect EF Core to fill in `Assignee` automatically. It doesn't:

```csharp
var task = await db.Tasks.SingleAsync(t => t.Id == 46);
```

`task.AssigneeId` is `995`, but `task.Assignee` is null, because the query only read the tasks table. Code like `task.Assignee?.Name ?? "Unassigned"` then shows "Unassigned" for a task that has an assignee, without any error.

The first fix that comes to mind is a loop:

```csharp
var tasks = await db.Tasks.OrderBy(t => t.Id).Take(50).ToListAsync(cancellationToken);
var rows = new List<BoardRow>();
foreach (var task in tasks)
{
    string? assigneeName = null;
    if (task.AssigneeId is not null)
    {
        var user = await db.Users.SingleAsync(u => u.Id == task.AssigneeId, cancellationToken);
        assigneeName = user.Name;
    }

    rows.Add(new BoardRow(task.Id, task.Title, assigneeName));
}
```

`BoardRow` is a record, `public record BoardRow(int Id, string Title, string? AssigneeName);`. For 50 tasks, three of them unassigned, this sends 48 queries: one for the tasks, then one for each assigned task's user. That pattern, one query plus one more per row, is called the **N+1 problem**. Each query is quick, but each also costs a round trip to the database.

EF Core can also do this for you, which hides it better. With **lazy loading** switched on, through the `Microsoft.EntityFrameworkCore.Proxies` package, simply reading `task.Assignee` sends a query for that user. The same N+1 queries happen behind a property access, which is why Microsoft's documentation warns that lazy loading makes the problem easy to create.

There are two ways to get everything in one query. **`Include`** tells EF Core to load a navigation property with the entities:

```csharp
var tasks = await db.Tasks
    .Include(t => t.Assignee)
    .OrderBy(t => t.Id)
    .Take(50)
    .ToListAsync(cancellationToken);
```

```sql
SELECT t0.id, t0.assignee_id, t0.created_at, t0.done, t0.due_on, t0.title, u.id, u.active, u.email, u.name
FROM (
    SELECT t.id, t.assignee_id, t.created_at, t.done, t.due_on, t.title
    FROM tasks AS t
    ORDER BY t.id
    LIMIT @p
) AS t0
LEFT JOIN users AS u ON t0.assignee_id = u.id
ORDER BY t0.id
```

A **projection** asks for exactly the columns the board needs:

```csharp
var rows = await db.Tasks
    .OrderBy(t => t.Id)
    .Take(50)
    .Select(t => new BoardRow(t.Id, t.Title, t.Assignee!.Name))
    .ToListAsync(cancellationToken);
```

```sql
SELECT t0.id, t0.title, u.name
FROM (
    SELECT t.id, t.assignee_id, t.title
    FROM tasks AS t
    ORDER BY t.id
    LIMIT @p
) AS t0
LEFT JOIN users AS u ON t0.assignee_id = u.id
ORDER BY t0.id
```

`t.Assignee!.Name` would throw in ordinary C# for an unassigned task. Here it never runs as C#: it becomes `u.name` in a `LEFT JOIN`, and unassigned tasks simply get a null name.

| Approach | Queries | Time, warm, database on the same machine |
|---|---|---|
| Loop | 48 | 20 to 22 ms |
| `Include` | 1 | 6 to 10 ms |
| Projection | 1 | 6 to 7 ms |

On this machine a round trip costs a fraction of a millisecond. Over a network, where it's typically a millisecond or more, the loop's 47 extra queries add 47 round trips, and the difference grows with every row.

Including a collection, such as a user's tasks with `Include(u => u.Tasks)`, uses the same kind of join, so the user's columns repeat on every one of their task rows. When that gets expensive, `AsSplitQuery()` makes EF Core send one query per table instead.

## Writing SQL yourself: FromSql and SqlQuery

LINQ covers most queries, but sometimes you want to write the SQL. **`FromSql`** runs your SQL and maps the results to entities:

```csharp
var tasks = await db.Tasks
    .FromSql($"select * from tasks where title ilike '%' || {term} || '%'")
    .OrderBy(t => t.Id)
    .Take(20)
    .ToListAsync(cancellationToken);
```

```sql
SELECT t.id, t.assignee_id, t.created_at, t.done, t.due_on, t.title
FROM (
    select * from tasks where title ilike '%' || @p0 || '%'
) AS t
ORDER BY t.id
LIMIT @p1
```

What to notice:

- **`{term}` became the parameter `@p0`.** `FromSql` takes an interpolated string, a `$"…"` string, and turns each value inside braces into a database parameter, not into text.
- **EF Core wrapped your SQL as a subquery** so it could add the `ORDER BY` and `LIMIT` from LINQ.
- **Your SQL has to return every column the entity maps,** with the mapped names, and the results are tracked like any other query.

Many developers assume an interpolated string in SQL must be injectable. With `FromSql` it isn't: the `union` attack from the SQL article, sent as the term, comes back as zero rows, because the whole text is one parameter value.

`FromSqlRaw` takes a plain string, and if you build that string by concatenation, it's injectable exactly as the SQL article showed:

```csharp
db.Tasks.FromSqlRaw("select * from tasks where title ilike '%" + term + "%'")
```

The same attack, adjusted to return every column the entity needs, comes back with user emails where task titles should be. The compiler warns about this line with **EF1003**: "Method 'FromSqlRaw' inserts concatenated strings directly into the SQL, without any protection against SQL injection." But the warning only catches concatenation written right there in the call. Build the string in a variable first, and there's no warning, so treat the analyzer as a safety net, not a guarantee. If you need `FromSqlRaw`, pass values as arguments: `FromSqlRaw("… {0} …", term)` sends `term` as a parameter.

### Results that aren't entities

`Database.SqlQuery<T>` returns any type, such as a count per user:

```csharp
public record OpenCount(int AssigneeId, long OpenTasks);
```

```csharp
var counts = await db.Database
    .SqlQuery<OpenCount>($"select assignee_id, count(*) as open_tasks from tasks where not done and assignee_id is not null group by assignee_id")
    .OrderByDescending(c => c.OpenTasks)
    .Take(3)
    .ToListAsync(cancellationToken);
```

Two things here aren't obvious:

- **The naming convention applies to these types too.** EF Core expects columns named `assignee_id` and `open_tasks`. Alias them `AssigneeId` and `OpenTasks` instead, and it fails with "The required column 'assignee_id' was not present in the results of a 'FromSql' operation."
- **`count(*)` returns a `bigint`** in PostgreSQL, so the property has to be a `long`.

## Bulk changes: ExecuteUpdate and ExecuteDelete

Marking all of one user's open tasks as done through change tracking means loading every one of them, changing each, and saving. **`ExecuteUpdate`** sends one statement instead:

```csharp
var changed = await db.Tasks
    .Where(t => t.AssigneeId == userId && !t.Done)
    .ExecuteUpdateAsync(s => s.SetProperty(t => t.Done, true), cancellationToken);
```

```sql
UPDATE tasks AS t
SET done = @p
WHERE t.assignee_id = @userId AND NOT (t.done)
```

It changed 178 rows without loading any of them, and it runs immediately, not at `SaveChanges`. **`ExecuteDelete`** does the same for deleting:

```csharp
var cutoff = new DateOnly(2026, 2, 1);
var deleted = await db.Tasks
    .Where(t => t.Done && t.DueOn < cutoff)
    .ExecuteDeleteAsync(cancellationToken);
```

```sql
DELETE FROM tasks AS t
WHERE t.done AND t.due_on < @cutoff
```

A natural assumption is that `ExecuteUpdate` also updates the entities you've already loaded. It doesn't touch them. Load one of user 9's open tasks, run the `ExecuteUpdate` above for user 9, then query that task again:

```text
tracked instance Done: False, queried again: False, same instance: True, AsNoTracking: True
```

The database says `true`, as the no-tracking query shows. But the tracked object still says `false`, and querying again returned that same stale object, because of the identity map. If anything later saves that entity, it can write the old values back. Avoid mixing bulk statements and tracked entities in one context, or call `db.ChangeTracker.Clear()` before loading again.

## Dapper next to EF Core

**Dapper** is a small library of extension methods on a database connection. You write all the SQL, and Dapper maps each row to an object by matching column names to property names. Here's the open-tasks query with it, using the same data source that EF Core uses:

```csharp
app.MapGet("/users/{userId:int}/open-tasks-dapper", async (int userId, NpgsqlDataSource dataSource, CancellationToken cancellationToken) =>
{
    await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
    var sql = """
        select id, title, due_on as DueOn
        from tasks
        where assignee_id = @userId and not done
        order by due_on
        limit 20
        """;
    var command = new CommandDefinition(sql, new { userId }, cancellationToken: cancellationToken);
    return await connection.QueryAsync<OpenTask>(command);
});
```

What to notice:

- **`new { userId }`** supplies the parameters: each property of the anonymous object fills the `@` placeholder with the same name, and Npgsql sends it as `$1`.
- **`CommandDefinition`** is how the cancellation token gets to the query. The simpler `QueryAsync<T>(sql, parameters)` overload has no token parameter.
- **`due_on as DueOn`** is there because Dapper matches names exactly, apart from letter case. Without the alias, `due_on` doesn't match `DueOn`. A class with settable properties silently gets `null` for every due date. A record fails instead: "A parameterless default constructor or one matching signature (System.Int32 id, System.String title, System.DateOnly due_on) is required for OpenTask materialization". Setting `DefaultTypeMap.MatchNamesWithUnderscores = true` once at startup also makes `due_on` match `DueOn`.

Each tool fits a different job:

- **LINQ with projections** for most reads, and **tracked entities** for changing a few rows. The mapping is in one place, and the compiler checks the property names.
- **`FromSql` and `SqlQuery`** when you need exact SQL but want to stay in the context.
- **`ExecuteUpdate` and `ExecuteDelete`** for changes to many rows at once.
- **Dapper** when the SQL itself is the point: hand-tuned queries, or ones LINQ can't express well. You give up change tracking, and names are only checked when the query runs.

**MySQL:** the popular community provider, Pomelo, has no release for EF Core 10 at the time of writing; its latest is 9.0.0. Oracle's `MySql.EntityFrameworkCore` provider has 10.0 releases.

## Back to the missing WHERE

The helper's parameter type, `IEnumerable<TaskItem>`, made `tasks.Where` mean `Enumerable.Where`, compiled C# that filters objects in memory. EF Core never received the filter. When `ToList()` enumerated the query, EF Core was asked for every task, sent a `SELECT` with no `WHERE`, and built and tracked a million objects so that C# could keep 20 of them. The log showed exactly that. Changing the parameter to `IQueryable<TaskItem>` put the filter back into the SQL, and with it the index.

The habits that prevent this, and the other surprises in this article:

1. **Read the log for every new query.** The SQL is right there.
2. **Keep queries as `IQueryable` until the last call**, and make that call `ToListAsync` or another method that runs the query.
3. **Read without tracking:** project into the response type, or use `AsNoTracking`.
4. **Load related data with `Include` or a projection**, never with a query per row.
5. **Write SQL with interpolated `FromSql`**, or `FromSqlRaw` with arguments, never with concatenation.
6. **One context per request, one operation at a time.**

## Check your understanding

1. **You pass `db.Tasks` to a method whose parameter is `IEnumerable<TaskItem>`, and it calls `Where` on it. What SQL does EF Core send?** A `SELECT` with no `WHERE` that reads every row, because the `Where` is `Enumerable.Where` and runs in memory after EF Core has returned everything.
2. **You load a task, change its title, and call `SaveChangesAsync`. What's sent? What if the new title equals the old one?** One `UPDATE` that sets only the `title` column for that id. If the value didn't change, nothing is sent and `SaveChangesAsync` returns 0.
3. **A loop over 50 tasks logs 48 queries. Why, and what are two fixes?** It queries each assigned task's user separately: one query plus one per row, the N+1 problem. Load the users with `Include`, or project the names with `Select`, so it's one query.
4. **Which of these is safe from SQL injection: `FromSql($"… {term}")`, `FromSqlRaw("…" + term)`, or `FromSqlRaw("… {0}", term)`?** The first and the third. Both send `term` as a parameter. The second puts it into the SQL text.

## Sources and further reading

- EF Core documentation: [DbContext lifetime and configuration](https://learn.microsoft.com/en-us/ef/core/dbcontext-configuration/), [client and server evaluation](https://learn.microsoft.com/en-us/ef/core/querying/client-eval), [tracking and no-tracking queries](https://learn.microsoft.com/en-us/ef/core/querying/tracking), [change tracking](https://learn.microsoft.com/en-us/ef/core/change-tracking/).
- EF Core documentation: [loading related data](https://learn.microsoft.com/en-us/ef/core/querying/related-data/), [single and split queries](https://learn.microsoft.com/en-us/ef/core/querying/single-split-queries), [SQL queries](https://learn.microsoft.com/en-us/ef/core/querying/sql-queries), [ExecuteUpdate and ExecuteDelete](https://learn.microsoft.com/en-us/ef/core/saving/execute-insert-update-delete), [efficient querying](https://learn.microsoft.com/en-us/ef/core/performance/efficient-querying).
- [The DbContext class](https://learn.microsoft.com/en-us/dotnet/api/microsoft.entityframeworkcore.dbcontext?view=efcore-10.0) in the EF Core API reference.
- [Npgsql EF Core provider documentation](https://www.npgsql.org/efcore/), and [EFCore.NamingConventions](https://github.com/efcore/EFCore.NamingConventions).
- [Dapper](https://github.com/DapperLib/Dapper) on GitHub.
