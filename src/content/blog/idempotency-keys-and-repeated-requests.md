---
title: "Sent twice, saved twice: idempotency keys in ASP.NET Core"
description: "Why a timeout after the save turns a retry into a duplicate task, what sends a request twice without your code deciding to, and how an idempotency key saved in PostgreSQL lets the task board recognize the repeat, both for its own POST /tasks and for its calls to the mail service."
pubDate: "2026-10-20T11:00:00Z"
tags:
  - aspnet-core
  - dotnet
  - http
  - postgresql
audience:
  - backend
---

Someone on a slow connection saves a task called "Write the release notes". The client waits two seconds, gives up, and tries again. The second attempt times out too. As far as the client knows, nothing was saved. But the task board now has two tasks called "Write the release notes", and the server's log shows two `INSERT` statements, each followed by a line saying the request finished.

The server did the work both times. So why did the client think it failed, and how do you make that second attempt harmless? This article follows the request through the client, the server, and the database to answer both questions, then applies the same fix to the task board's own calls to its mail service.

You'll need [the resource-style and action-style endpoints article](/dump/blog/resource-style-and-action-style-endpoints/), which defines safe and idempotent methods and built `POST /tasks/{id}/complete`, and [the transactions article](/dump/blog/transactions-and-concurrent-edits/) for transactions, the version column, and `If-Match`. [async, await, and the thread pool](/dump/blog/aspnet-core-async-and-the-thread-pool/) explains `CancellationToken`, [EF Core behind the scenes](/dump/blog/ef-core-behind-the-scenes/) explains what `SaveChanges` sends, and [the layered and sliced article](/dump/blog/layered-and-sliced-code-organization/) added the mail service call.

## Contents

1. [Set up the example](#set-up-the-example)
2. [What a timeout tells the client](#what-a-timeout-tells-the-client)
3. [Repeats you don't control](#repeats-you-dont-control)
4. [Which requests are safe to repeat](#which-requests-are-safe-to-repeat)
5. [Idempotency keys](#idempotency-keys)
6. [Reused keys, simultaneous requests, and old keys](#reused-keys-simultaneous-requests-and-old-keys)
7. [Other ways to make creation safe to repeat](#other-ways-to-make-creation-safe-to-repeat)
8. [When the task board sends the request](#when-the-task-board-sends-the-request)
9. [Back to the duplicate task](#back-to-the-duplicate-task)

## Set up the example

The examples use the .NET 10 SDK (ASP.NET Core 10.0.13), EF Core 10.0.4 through Npgsql.EntityFrameworkCore.PostgreSQL 10.0.3, Microsoft.Extensions.Http.Resilience 10.11.0, PostgreSQL 18.6, and Chromium 152, in the `Production` environment. The code starts from the sliced task board at the end of [the layered and sliced article](/dump/blog/layered-and-sliced-code-organization/), which, along with [the endpoints article](/dump/blog/resource-style-and-action-style-endpoints/), compares its layout and endpoint style with the alternatives. Background jobs, delivering email reliably, authentication, distributed locks, and tuning timeouts and retry policies are outside this article's scope.

To make the problem easy to see, `CreateTask` waits three seconds after saving:

```csharp
await db.SaveChangesAsync(cancellationToken);
await Task.Delay(TimeSpan.FromSeconds(3), cancellationToken); // stands in for slow work after the save
```

The delay stands in for anything slow that happens after the save: another service call, a busy server, or a slow network on the way back to the client. It widens a window that always exists, so you don't have to wait for bad luck to see what happens in it.

## What a timeout tells the client

The client in the opening is a .NET console app with a two-second timeout that tries twice:

```csharp
var http = new HttpClient { BaseAddress = new Uri("http://localhost:5080"), Timeout = TimeSpan.FromSeconds(2) };
for (var attempt = 1; attempt <= 2; attempt++)
{
    try
    {
        var response = await http.PostAsJsonAsync("/tasks", new { title });
        Console.WriteLine($"attempt {attempt}: {(int)response.StatusCode}");
        break;
    }
    catch (TaskCanceledException exception)
    {
        Console.WriteLine($"attempt {attempt}: {exception.Message}");
    }
}
```

```text
2.04s attempt 1: The request was canceled due to the configured HttpClient.Timeout of 2 seconds elapsing.
4.04s attempt 2: The request was canceled due to the configured HttpClient.Timeout of 2 seconds elapsing.
```

The database has two rows with that title. The app's log shows each request finishing, once you turn `Microsoft.AspNetCore.Hosting.Diagnostics` up to `Information` (the `dotnet new` templates hide it by setting `Microsoft.AspNetCore` to `Warning`):

```text
INSERT INTO tasks (assignee_id, completed_at, done, due_on, priority, tags, title, version) …
Request finished HTTP/1.1 POST http://localhost:5080/tasks - 499 - - 1959.0454ms
INSERT INTO tasks (assignee_id, completed_at, done, due_on, priority, tags, title, version) …
Request finished HTTP/1.1 POST http://localhost:5080/tasks - 499 - - 1999.6807ms
```

Step by step, for each attempt:

1. The request reaches the server, and `SaveChangesAsync` sends the `INSERT` and commits it. The row is saved.
2. The handler starts its three-second delay.
3. After two seconds, `HttpClient` gives up. It cancels the request and closes the connection, and your code gets a `TaskCanceledException`.
4. Kestrel, ASP.NET Core's web server, notices the closed connection and cancels the request's `CancellationToken`, which ends the delay early.
5. No response was sent, so Kestrel logs status `499`. That's not a real HTTP status; Kestrel's source says it uses `499` "for logging" when "the request was aborted and no response was sent". Nothing is logged as a warning or an error.

What to notice:

- Cancelling a request stops the code that's still running. It doesn't undo what already happened, and the commit happened in step 1.
- From the client's side, three different situations look the same: the request never reached the server, the server did the work but the response was lost, or the server is still working. A timeout only tells the client that it stopped waiting.
- So retrying after a timeout is a guess. For `POST /tasks`, a wrong guess creates a second task.

## Repeats you don't control

Removing the retry loop doesn't make the problem go away, because your code isn't the only thing that sends a request twice.

**The user.** Clicking Save twice sends two requests at once, and both succeed:

```text
201 /tasks/10003
201 /tasks/10004
```

**The browser.** When a browser sends a request on a connection it has used before, and that connection closes before any response arrives, Chromium sends the same request again on a new connection, whatever the method. In a test against a server that closes a reused connection when a `POST` arrives, a page's `fetch` `POST` went out twice, and the page's code saw a single `201` and never knew about the first attempt. Firefox's networking code has a similar rule. RFC 9110, the HTTP specification, allows this: "a client might automatically retry a POST request if the underlying transport connection closed before any part of a response is received, particularly if an idle persistent connection was used."

.NET's `HttpClient` has the same kind of rule but applies it only to requests without a body, so against the same server a JSON `POST` failed with `HttpRequestException: An error occurred while sending the request. (ResponseEnded)` instead of being resent.

**Angular.** The `retry()` operator from RxJS resends a request when it fails. Angular's HTTP guide describes it as attempting "to re-subscribe a specified number of times", and it retries every error, including a `400` or `422` that will never succeed.

**Resilience handlers.** `AddStandardResilienceHandler` from `Microsoft.Extensions.Http.Resilience` adds retries to an `HttpClient`, and by default it retries every method, including `POST`. [The last section](#when-the-task-board-sends-the-request) shows what that does to the task board's emails.

So a `POST` can arrive twice even if your code never retries. Whether that does any harm depends on the request.

## Which requests are safe to repeat

[The endpoints article](/dump/blog/resource-style-and-action-style-endpoints/#what-http-and-fielding-say-about-post) covered the two RFC 9110 terms for this: a safe request is essentially read-only, like `GET`, and an idempotent request has the same intended effect whether it's sent once or several times. Sending some task board requests twice in a row:

| Request | First | Second | Result |
|---|---|---|---|
| `GET /tasks/42` | `200` | `200` | nothing changes |
| `POST /tasks/42/complete` | `204` | `204` | done once, one email |
| `PUT /tasks/43` with `If-Match: "1"` | `204` | `412` | renamed once |
| `POST /tasks` | `201` | `201` | two tasks |

What to notice:

- `complete` is idempotent because of how it's written: its `UPDATE` only matches a task that isn't done yet, so the second request changes nothing and still answers `204`.
- The repeated `PUT` doesn't apply the change twice, because the version check rejects it. It answers `412`, so a client that retried has to reload the task, where it finds its own edit already saved.
- `POST /tasks` creates a new row every time. Nothing in the request tells the server it has seen this one before.

RFC 9110 sets the rule for clients that retry on their own: "A client SHOULD NOT automatically retry a request with a non-idempotent method unless it has some means to know that the request semantics are actually idempotent, regardless of the method, or some means to detect that the original request was never applied." `POST` isn't idempotent by definition, but a particular `POST`, such as `complete`, can be. So the way out for `POST /tasks` is to give the server something that tells it a request is a repeat.

## Idempotency keys

An **idempotency key** is a random value the client creates once for each thing the user means to do, such as "create this task", and sends with every attempt. The server saves the key in the same transaction as the task. When a request arrives with a key the server has already saved, the server knows the work is done and returns the existing task instead of creating another one.

The client sends the key in an `Idempotency-Key` request header. The name comes from a proposal to the IETF, the group that writes the HTTP standards. The proposal expired without becoming a standard, but Stripe's API and other public APIs use the header the way it describes. ASP.NET Core has nothing built in for it, so the code below is the whole implementation.

### The server side

A table records which key created which task:

```sql
create table idempotency_keys (
    key text primary key,
    task_id integer not null references tasks (id),
    created_at timestamptz not null default now()
);
```

with an entity and two lines of model configuration:

```csharp
public class IdempotencyKey
{
    public string Key { get; set; } = "";
    public int TaskId { get; set; }
    public TaskItem? Task { get; set; }
    public DateTime CreatedAt { get; set; }
}

modelBuilder.Entity<IdempotencyKey>().HasKey(k => k.Key);
modelBuilder.Entity<IdempotencyKey>().Property(k => k.CreatedAt).HasDefaultValueSql("now()");
```

`CreateTask` reads the key from the header and adds a key row next to the task:

```csharp
public static async Task<Created<TaskDetails>> Handle(
    NewTask newTask,
    [FromHeader(Name = "Idempotency-Key")] string? idempotencyKey,
    TaskBoardDb db,
    CancellationToken cancellationToken)
{
    var task = new TaskItem { Title = newTask.Title, AssigneeId = newTask.AssigneeId, DueOn = newTask.DueOn, Priority = newTask.Priority, Version = 1 };
    db.Tasks.Add(task);

    if (idempotencyKey is not null)
    {
        db.IdempotencyKeys.Add(new IdempotencyKey { Key = idempotencyKey, Task = task });
    }

    try
    {
        await db.SaveChangesAsync(cancellationToken);
    }
    catch (DbUpdateException exception) when (exception.InnerException is PostgresException { SqlState: PostgresErrorCodes.UniqueViolation })
    {
        db.ChangeTracker.Clear();
        var saved = await db.IdempotencyKeys
            .Where(k => k.Key == idempotencyKey)
            .Select(k => new TaskDetails(k.Task!.Id, k.Task.Title, k.Task.Done, k.Task.DueOn, k.Task.Priority, k.Task.CompletedAt, k.Task.Tags, k.Task.Version))
            .SingleAsync(cancellationToken);
        return TypedResults.Created($"/tasks/{saved.Id}", saved);
    }

    await Task.Delay(TimeSpan.FromSeconds(3), cancellationToken); // stands in for slow work after the save
    return TypedResults.Created($"/tasks/{task.Id}", new TaskDetails(task.Id, task.Title, task.Done, task.DueOn, task.Priority, task.CompletedAt, task.Tags, task.Version));
}
```

What to notice:

- `SaveChangesAsync` inserts the task, then the key row, in one transaction. Either both are saved or neither is, so a saved key always points to a saved task.
- The key is the table's primary key, so PostgreSQL refuses a second row with the same key. That refusal is error `23505`, a unique violation, which EF Core wraps in a `DbUpdateException`. On SQL Server the same refusal is error `2627` or `2601`, and on MySQL it's `1062`, so the `catch` filter checks those numbers instead.
- `ChangeTracker.Clear()` drops the task and key that failed to save, so the context doesn't try to insert them again. Then the handler reads the task the key points to and returns it.
- The only unique constraint this insert can violate is the key's, since task ids come from the database. A table with other unique columns would also check which constraint failed, through `PostgresException.ConstraintName`.
- The response is the task as it is now. If someone renamed it in between, a replay shows the new title; AWS's guidance on retries asks only for a "semantically equivalent response". Stripe's API stores the original status code and body instead and replays them exactly, at the cost of more columns.
- The key is optional. Without one, the handler works as before and isn't protected. An API can also require it and answer `400` when it's missing.

### The client side

The key belongs to the user's action, not to the HTTP attempt, so the client creates it once, before its first attempt, and sends the same value every time. The opening's client, changed to do that:

```csharp
var key = Guid.CreateVersion7().ToString();
for (var attempt = 1; attempt <= 3; attempt++)
{
    var request = new HttpRequestMessage(HttpMethod.Post, "/tasks");
    request.Content = JsonContent.Create(new { title });
    request.Headers.Add("Idempotency-Key", key);
    // …send, and stop on success
}
```

Creating the key inside the loop would give each attempt its own key, and the server would treat every retry as new.

In an Angular component, the key can live as long as the form's current task. It's replaced only after a save succeeds, so pressing Save again after a timeout resends the same key:

```ts
private idempotencyKey = crypto.randomUUID();
protected saving = signal(false);

save(newTask: NewTask) {
  this.saving.set(true);
  const headers = { "Idempotency-Key": this.idempotencyKey };
  this.http.post<TaskDetails>("/tasks", newTask, { headers }).subscribe({
    next: () => {
      this.idempotencyKey = crypto.randomUUID();
      this.saving.set(false);
    },
    error: () => {
      this.saving.set(false);
    },
  });
}
```

What to notice:

- Binding the Save button's `disabled` property to `saving()` stops the double click before it becomes two requests.
- `crypto.randomUUID()` only exists in secure contexts: pages served over HTTPS, or from `localhost`.

### The opening again

With the key, the opening's client gets one task:

```text
2.03s attempt 1: TaskCanceledException
2.19s attempt 2: 201 /tasks/10005
```

The first attempt saved the task and its key, then timed out during the delay. The second attempt's insert hit the saved key, so the handler returned the same task immediately. There's one row.

The same thing with `curl`, sending one key three times:

```text
first request                                201 /tasks/10007   3.00 s
same request again                           201 /tasks/10007   0.01 s
same task, other spacing and field order     201 /tasks/10007   0.01 s
```

The repeats are fast because they return before the delay.

## Reused keys, simultaneous requests, and old keys

The smallest version handles a plain retry. A few other cases need a closer look.

### A key reused for a different request

Sending the same key with a different title gets the first task back:

```text
same key, title "Fix the login form"         201 /tasks/10007   {"title":"Plan the sprint"}
```

The client asked for "Fix the login form", got a `201`, and no such task exists. Reusing a key for something else is a bug in the client, and replaying the wrong task hides it. So the server also saves a **fingerprint** of the request, a hash of its content, and compares it on a replay. The table gets one more column:

```sql
create table idempotency_keys (
    key text primary key,
    fingerprint text not null,
    task_id integer not null references tasks (id),
    created_at timestamptz not null default now()
);
```

and the entity a matching `Fingerprint` property. The handler computes the fingerprint before saving, stores it with the key, and checks it in the `catch`:

```csharp
public static async Task<Results<Created<TaskDetails>, ProblemHttpResult>> Handle(
    NewTask newTask,
    [FromHeader(Name = "Idempotency-Key"), StringLength(100)] string? idempotencyKey,
    TaskBoardDb db,
    CancellationToken cancellationToken)
{
    // …
    var fingerprint = Convert.ToHexString(SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(newTask)));
    if (idempotencyKey is not null)
    {
        db.IdempotencyKeys.Add(new IdempotencyKey { Key = idempotencyKey, Fingerprint = fingerprint, Task = task });
    }

    try
    {
        await db.SaveChangesAsync(cancellationToken);
    }
    catch (DbUpdateException exception) when (exception.InnerException is PostgresException { SqlState: PostgresErrorCodes.UniqueViolation })
    {
        db.ChangeTracker.Clear();
        var saved = await db.IdempotencyKeys
            .Where(k => k.Key == idempotencyKey)
            .Select(k => new { k.Fingerprint, Task = new TaskDetails(k.Task!.Id, k.Task.Title, k.Task.Done, k.Task.DueOn, k.Task.Priority, k.Task.CompletedAt, k.Task.Tags, k.Task.Version) })
            .SingleAsync(cancellationToken);
        if (saved.Fingerprint != fingerprint)
        {
            return TypedResults.Problem("This Idempotency-Key was already used with a different request.", statusCode: StatusCodes.Status422UnprocessableEntity);
        }

        return TypedResults.Created($"/tasks/{saved.Task.Id}", saved.Task);
    }
    // …
}
```

```text
first request                                201 /tasks/10014   3.01 s
same request again                           201 /tasks/10014   0.03 s
same task, other spacing and field order     201 /tasks/10014   0.02 s
same key, title "Fix the login form"         422
no key                                       201 /tasks/10018
```

What to notice:

- The fingerprint is a SHA-256 hash of the bound `NewTask` record rather than the raw body. Extra spaces, a different property order, or spelling out a default value such as `"priority":"Normal"` give the same fingerprint.
- The return type now lists `ProblemHttpResult` next to `Created<TaskDetails>`, since the handler can answer either.
- In the Angular form, the key survives a failed save. If the user edits the form after a timeout and saves again, the same key arrives with a different body. If the first attempt was saved, the `422` tells the user it went through.
- `StringLength(100)` validates the header like any other parameter: a 101-character key answers `400` with a validation error for `idempotencyKey`.
- The jump from 10014 to 10018 is expected. Each insert that failed on the key had already taken an id from the sequence before the unique violation rolled it back, and PostgreSQL doesn't reuse those ids.

The IETF proposal suggests the same status codes: `422` for a key reused with a different payload, and `400` when an API requires a key and it's missing. It leaves the fingerprint optional and recommends a UUID "or a similar random identifier" as the key. Stripe's API accepts keys up to 255 characters.

### Two requests with the same key at once

Eight requests with the same key, sent at the same moment, five times:

```text
8 × 201 /tasks/10011   tasks: 1
8 × 201 /tasks/10020   tasks: 1
8 × 201 /tasks/10027   tasks: 1
8 × 201 /tasks/10036   tasks: 1
8 × 201 /tasks/10043   tasks: 1
```

Every request gets the same task. That works because of how PostgreSQL handles a unique index: "If a conflicting row has been inserted by an as-yet-uncommitted transaction, the would-be inserter must wait to see if that transaction commits." The first request's insert holds the key. The others wait inside `SaveChangesAsync` until it commits, or, if they arrive after the commit, find the key at once. Either way they fail with the unique violation and replay.

To see the wait on its own, a `psql` session inserts a key and keeps its transaction open for three seconds while the API receives a request with the same key. `pg_stat_activity` shows the request waiting on a `Lock` of type `transactionid`. When `psql` rolls back, the request goes ahead and creates its task; when `psql` commits, the request finds the key and, since `psql` saved a different fingerprint, answers `422`.

So a duplicate that arrives while the first request is still saving waits for it rather than failing. The cost is a lock held for the length of the save. The IETF proposal takes the other approach and answers `409 Conflict` while the first request is still running, which needs an "in progress" row and a way to clean it up if that request crashes.

### Removing old keys

The table grows with every keyed request. Keys only need to outlive the client's retries, so deleting old ones is enough:

```sql
delete from idempotency_keys where created_at < now() - interval '24 hours';
```

After the delete, a request with that old key creates a new task. Stripe documents removing keys once they're "at least 24 hours old", and the IETF proposal leaves the expiry to each API. Running the delete on a schedule is background work that this article leaves out.

## Other ways to make creation safe to repeat

An idempotency key is one of several ways for a server to recognize a repeat.

**A client-generated id.** The client creates the task's id itself, for example with `Guid.CreateVersion7()` in .NET 9 and later, and the table uses a `uuid` primary key. A repeat inserts the same id, and PostgreSQL's `on conflict do nothing` turns the second insert into a no-op:

```sql
insert into client_tasks (id, title) values ('0199f5a8-6a51-7c2e-9a44-1d2f3b4c5d6e', 'Write the release notes')
on conflict (id) do nothing returning id;
```

The first run returns the id (`INSERT 0 1`); the second returns no rows (`INSERT 0 0`). A third run with the same id and the title "Fix the login form" also returns `INSERT 0 0`, silently: without a fingerprint, a different request with the same id goes unnoticed. The task board's ids are integers the database generates, so switching would change the table and the API.

**A natural unique constraint.** If the data has something that must be unique, such as an order number from another system, a unique index on it rejects the repeat. Tasks have nothing like that: two tasks can share a title.

**An idempotent action.** `POST /tasks/{id}/complete` is safe to repeat because its rule is "make it done", not "flip it". Designing an operation so that repeating it has no further effect removes the problem for that operation.

| | Idempotency key | Client-generated id | Natural unique constraint |
|---|---|---|---|
| Schema change | one extra table | id column becomes a `uuid` | a unique index |
| Detects a different request with the same value | yes, with a fingerprint | no | no |
| Old values | deleted after a while | kept with the row | kept with the row |
| Works when the data has no natural key | yes | yes | no |

## When the task board sends the request

The task board also makes requests of its own: `HttpMailSender` posts each completion email to the mail service. Adding the standard resilience handler to its `HttpClient` is one line:

```csharp
builder.Services.AddHttpClient<IMailSender, HttpMailSender>(client => client.BaseAddress = new Uri(builder.Configuration["Mail:BaseUrl"]!))
    .AddStandardResilienceHandler();
```

By default, the handler retries up to three times, waiting a little longer each time, after a connection failure, an attempt that runs longer than 10 seconds, or a `408`, `429`, or any `5xx` response. Microsoft's documentation states the risk directly: "By default, the standard resilience handler is configured to make retries for all HTTP methods. … if a POST request inserts a new record to a database, then making retries for such a request could lead to data duplication." For the mail service, duplication means a second email.

A stand-in mail service shows it. It sends the email and then answers `503`, as a service might when it fails after doing the work:

```text
no handler      complete: 500    emails sent: 1
with handler    complete: 204    emails sent: 2
```

What to notice:

- This is the opening with the roles swapped. The task board is now the client, the mail service did the work, and the `503` told the task board it failed.
- Without the handler, completing the task answered `500` even though the task was saved as done before the email was sent.
- With the handler, the retry hid the `503` from the person completing the task, and sent the assignee a second email.

The fix is the same as for `POST /tasks`. If the mail service accepts an idempotency key, `HttpMailSender` creates one per email, before the handler's retries:

```csharp
public async Task SendAsync(OutgoingMail message, CancellationToken cancellationToken)
{
    var request = new HttpRequestMessage(HttpMethod.Post, "/messages");
    request.Content = JsonContent.Create(message);
    request.Headers.Add("Idempotency-Key", Guid.CreateVersion7().ToString());

    var response = await http.SendAsync(request, cancellationToken);
    response.EnsureSuccessStatusCode();
}
```

The handler resends the same request, header included. With a stand-in mail service that remembers keys:

```text
with handler and key    complete: 204    emails sent: 1, then a duplicate key ignored
```

If the mail service doesn't accept keys, turn retries off for requests that change something:

```csharp
using Microsoft.Extensions.Http.Resilience;

builder.Services.AddHttpClient<IMailSender, HttpMailSender>(client => client.BaseAddress = new Uri(builder.Configuration["Mail:BaseUrl"]!))
    .AddStandardResilienceHandler(options => options.Retry.DisableForUnsafeHttpMethods());
```

That run sends one email and answers `500`, like having no handler. `DisableForUnsafeHttpMethods` stops retries for `POST`, `PATCH`, `PUT`, `DELETE`, and `CONNECT`, which includes `PUT` and `DELETE` even though RFC 9110 defines them as idempotent. It's marked experimental in the package source, although calling it as above produces no warning.

Neither fix gets the email out when the mail service is down for longer than the retries last. That needs the email to be stored and sent later by background work, which is outside this article.

## Back to the duplicate task

So why did the client think the save failed? Because a timeout only means the client stopped waiting. The `INSERT` had already committed when the client gave up, and cancelling the request couldn't undo it. Each retry did the same thing, and the client saw two failures for two saved tasks.

The fix is to let the server recognize the retry. With an idempotency key created once per action and saved in the same transaction as the task, the retry finds the key and gets the first task back: one row, whatever happened to the first response. The same holds when the task board is the client: the mail service can only ignore a retried email if the email carries a key it can recognize.

| Request | Safe to repeat? | What makes it safe |
|---|---|---|
| `GET /tasks`, `GET /tasks/{id}` | yes | reads change nothing |
| `POST /tasks/{id}/complete` | yes | the `UPDATE` only matches a task that isn't done |
| `PUT` and `PATCH /tasks/{id}` | the change applies once | `If-Match`; a repeat answers `412` |
| `POST /tasks` without a key | no | nothing |
| `POST /tasks` with `Idempotency-Key` | yes | the key row, saved in the task's transaction |
| `HttpMailSender` with the resilience handler | only if the mail service checks keys | `Idempotency-Key`, or `DisableForUnsafeHttpMethods` |

## Check your understanding

1. **A request to `POST /tasks` timed out on the client, and the log shows `499`. Can the task have been saved, and why?** Yes. The client's timeout and the `499` only mean nobody received a response. If `SaveChangesAsync` had committed before the client gave up, cancelling the request stopped the remaining work but didn't undo the commit.
2. **A client creates a new idempotency key inside its retry loop. Why doesn't that prevent duplicates?** Each attempt carries a different key, so the server finds no saved key for the retry and creates another task. The key has to be created once per action, before the first attempt.
3. **A second request with the same key arrives while the first is still inside `SaveChangesAsync`. What happens?** Its insert into `idempotency_keys` waits, because PostgreSQL makes an insert wait for an uncommitted row with the same unique key. When the first transaction commits, the second gets a unique violation, finds the saved key, and returns the same task. If the first transaction rolls back instead, the second goes ahead and creates the task.
4. **Why can `AddStandardResilienceHandler` on `HttpMailSender` send an email twice, and what are the two fixes?** It retries every method, including `POST`, after a `5xx`, even when the mail service already sent the email. Send an `Idempotency-Key` created once per email so the mail service can ignore repeats, or call `DisableForUnsafeHttpMethods` so `POST` isn't retried.

## Sources and further reading

- [RFC 9110: HTTP Semantics](https://www.rfc-editor.org/rfc/rfc9110): safe and idempotent methods and automatic retries (§9.2).
- [The Idempotency-Key HTTP Header Field](https://datatracker.ietf.org/doc/draft-ietf-httpapi-idempotency-key-header/), the expired Internet-Draft, version -07.
- Stripe, [Idempotent requests](https://docs.stripe.com/api/idempotent_requests).
- AWS Builders' Library, [Making retries safe with idempotent APIs](https://aws.amazon.com/builders-library/making-retries-safe-with-idempotent-apis/).
- Microsoft, [Build resilient HTTP apps](https://learn.microsoft.com/en-us/dotnet/core/resilience/http-resilience).
- PostgreSQL 18, [Index uniqueness checks](https://www.postgresql.org/docs/18/index-unique-checks.html).
