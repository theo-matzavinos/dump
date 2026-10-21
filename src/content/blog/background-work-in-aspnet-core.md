---
title: "Saved, answered, never sent: background work in ASP.NET Core"
description: "Why a task board's completion waits for its email, how sending the email after the response with Task.Run loses it without a trace, how a BackgroundService fed by a Channel<T> sends it from a worker the host runs, what a stop or a crash does to emails queued in memory, and how a table row saved with the task keeps the email until it's sent, once."
pubDate: "2026-10-21T11:00:00Z"
tags:
  - aspnet-core
  - dotnet
  - ef-core
  - postgresql
audience:
  - backend
---

The mail service is down again, answering every request with `503 Service Unavailable`, and Ada and Grace complete their tasks at the same moment:

```text
ada    POST /tasks/1/complete    500 Internal Server Error    9.07 s
grace  POST /tasks/2/complete    500 Internal Server Error    6.25 s
```

Both tasks are done in the database. The mail service received 8 requests, four for each email, and sent nothing. So Ada waited 9 seconds for an error about a change that was saved, and her email is gone: when the mail service comes back, nothing tries again.

Her task was saved within the first fifth of a second. Why does the response wait for the email at all, and how does the email still reach Ada once the mail service is back?

You'll need [the dependency injection article](/dump/blog/aspnet-core-dependency-injection/) for scopes and `IServiceScopeFactory`, [the async article](/dump/blog/aspnet-core-async-and-the-thread-pool/) for tasks and cancellation tokens, [the transactions article](/dump/blog/transactions-and-concurrent-edits/) for transactions with EF Core, [the idempotency keys article](/dump/blog/idempotency-keys-and-repeated-requests/) for the mail service, its retries, and idempotency keys, and [the logs and traces article](/dump/blog/following-one-request-with-logs-and-traces/) for the JSON log and `jq`.

## Contents

1. [Set up the example](#set-up-the-example)
2. [What Ada's completion waits for](#what-adas-completion-waits-for)
3. [Sending the email after the response](#sending-the-email-after-the-response)
4. [A worker the host runs](#a-worker-the-host-runs)
5. [Passing the task ID through a channel](#passing-the-task-id-through-a-channel)
6. [When the app stops](#when-the-app-stops)
7. [Keeping the email in a table](#keeping-the-email-in-a-table)
8. [Sending it once](#sending-it-once)
9. [Back to Ada's completion](#back-to-adas-completion)

## Set up the example

The examples use the .NET 10 SDK (ASP.NET Core 10.0.13), EF Core 10.0.4, Npgsql 10.0.3, Microsoft.Extensions.Http.Resilience 10.11.0, PostgreSQL 18.6, Keycloak 26.8.1, and Jaeger 2.22.0, with the API in the `Production` environment. Nothing new needs installing: `BackgroundService`, `Channel<T>`, and `PeriodicTimer` are part of .NET.

The code starts from the task board at the end of [the logs and traces article](/dump/blog/following-one-request-with-logs-and-traces/). [The layered and sliced article](/dump/blog/layered-and-sliced-code-organization/) and [the endpoints article](/dump/blog/resource-style-and-action-style-endpoints/) compare its layout and endpoint style with the alternatives. The API runs as before:

```bash
Mail__ApiKey=mail-local-only Auth__RequireHttpsMetadata=false dotnet run --project TaskBoard
```

The stand-in mail service can answer `503` to every request, take a second to answer, or remember the `Idempotency-Key` of each email it sent and answer a repeat without sending it again. Ada and Grace complete their tasks at the same moment, as in the logs article:

```bash
curl -s -X POST -H "Authorization: Bearer $ADA" http://localhost:5000/tasks/1/complete &
curl -s -X POST -H "Authorization: Bearer $GRACE" http://localhost:5000/tasks/2/complete
```

Running more than one copy of the app, retry schedules and giving up on an email, carrying a trace into background work, job libraries such as Hangfire and Quartz, and message brokers are outside this article's scope.

## What Ada's completion waits for

Here's the end of `CompleteTask.Handle`, after the `UPDATE` that marks the task done:

```csharp
if (changed == 1)
{
    loggerFactory.CreateLogger(nameof(CompleteTask)).LogInformation("Task {TaskId} completed by user {UserId}", id, callerId);
    await CompletionMail.SendAsync(id, db, mailSender, cancellationToken);
    return TypedResults.NoContent();
}
```

`CompletionMail.SendAsync` reads the task's title and the assignee's address, then calls the mail service through the resilience handler. The handler awaits it, so `return TypedResults.NoContent()` runs only after the email is sent or has failed for good. With the mail service down, that's four attempts and the waits between them, and the last `503` becomes the exception behind Ada's `500`. Her trace showed the split: the `UPDATE` finished 169 ms after the request started, and the other 8.9 seconds were the email.

A healthy mail service costs time too. Measured one completion at a time, each on a different task, in two runs:

| Mail service | Median completion time |
|---|---|
| Answers at once | 11 to 14 ms |
| Takes 1 s to answer | 1,007 to 1,010 ms |

Ada doesn't need the email before her response. She needs the task done, and the email to arrive at some point. Can the response stop waiting for it?

## Sending the email after the response

The quickest change starts the email on the thread pool and doesn't await it:

```csharp
_ = Task.Run(() => CompletionMail.SendAsync(id, db, mailSender, cancellationToken));
return TypedResults.NoContent();
```

`Task.Run` queues the work to run on a pool thread and returns a task for it at once. `_ =` throws that task away, so nothing waits for it. Starting work this way and never looking at it again is called **fire and forget**.

With the mail service healthy, 30 completions in a row all answered `204 No Content`, with a median of 4.3 ms. The mail service received nothing, and the log had no error, and no entry at all after each `Task 1 completed by user 1001`. Printing each discarded task's exception to the console explained it, 30 times out of 30:

```text
ObjectDisposedException: Cannot access a disposed context instance. A common cause of this error is disposing a context instance that was resolved from dependency injection and then later trying to use the same context instance elsewhere in your application. …
Object name: 'TaskBoardDb'.
```

`db` is the request's database context, a scoped service, and [ASP.NET Core disposes the request's scoped services](/dump/blog/aspnet-core-dependency-injection/#who-disposes-what) once the response is sent. The email's work starts on another thread a moment after `Task.Run` returns, and by the time it reads the task, its context is gone. The exception ends up in the task that `_ =` threw away, and, as [the async article](/dump/blog/aspnet-core-async-and-the-thread-pool/#async-void-can-crash-the-server) showed, nothing logs an exception in a task nobody awaits.

Discarding the call without `Task.Run`, as `_ = CompletionMail.SendAsync(...)`, fails less predictably. The email's first query starts on the request's database connection before the handler returns, and the request's scope closes that connection under it. In 90 such completions, no email went out, and Kestrel logged errors from Npgsql such as `Received backend message BindComplete while expecting ReadyForQueryMessage. Please file a bug.`

So the email's work needs services of its own. A scope created inside the work, with `IServiceScopeFactory` as in [the fixes for captive dependencies](/dump/blog/aspnet-core-dependency-injection/#three-fixes-simplest-first), lasts as long as the work instead of the request:

```csharp
_ = Task.Run(async () =>
{
    await using var scope = scopes.CreateAsyncScope();
    var db = scope.ServiceProvider.GetRequiredService<TaskBoardDb>();
    var mailSender = scope.ServiceProvider.GetRequiredService<IMailSender>();
    await CompletionMail.SendAsync(id, db, mailSender, CancellationToken.None);
});
```

What to notice:

- `scopes` is an `IServiceScopeFactory` parameter of the handler. It's a singleton, so it's still usable after the request ends.
- The send gets `CancellationToken.None`, because the request's token belongs to the request too.

Now the completion answered `204`, and the email went out within about a second. But nothing in the app knows the work exists:

- With the mail service down, the four attempts failed after the response, and the only error in the log was the resilience handler's line for its last attempt, `Execution attempt. … Result: '503', Handled: 'True', Attempt: '3'`. No entry said that the email for task 1 was given up, and no exception was logged.
- A stop signal sent right after the response ended the process in 0.1 s, and the email never went out. When the signal came while the mail call was already running, the process lived on until that call ended, but only because the resilience handler waits for its own calls when it's disposed. The app itself doesn't wait for work it doesn't know about.

How do you run work that the app starts, watches, and stops?

## A worker the host runs

An ASP.NET Core app runs inside a **host**, the object `builder.Build()` creates, which starts the web server and everything else when the app starts and stops them when it stops. Code that the host starts and stops this way is a **hosted service**, and `BackgroundService` is the base class for a hosted service that runs a loop for the app's whole life. You override one method:

- **`ExecuteAsync(CancellationToken stoppingToken)`** is called once, when the app starts, and runs on the thread pool. It usually loops until the app stops.
- **`stoppingToken`** fires when the app starts stopping, so the loop knows to end.

Here's the task board's email worker. `completedTasks` is a queue that the handlers add task IDs to, which the next section builds:

```csharp
public class CompletionMailSender(Channel<int> completedTasks, IServiceScopeFactory scopes, ILogger<CompletionMailSender> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await foreach (var taskId in completedTasks.Reader.ReadAllAsync(stoppingToken))
        {
            try
            {
                await using var scope = scopes.CreateAsyncScope();
                var db = scope.ServiceProvider.GetRequiredService<TaskBoardDb>();
                var mailSender = scope.ServiceProvider.GetRequiredService<IMailSender>();
                await CompletionMail.SendAsync(taskId, db, mailSender, stoppingToken);
            }
            catch (Exception exception) when (!stoppingToken.IsCancellationRequested)
            {
                logger.LogError(exception, "Completion email for task {TaskId} failed", taskId);
            }
        }
    }
}
```

```csharp
builder.Services.AddHostedService<CompletionMailSender>();
```

What to notice:

- Each email gets its own scope, so its own `TaskBoardDb`, disposed when the email is done.
- The `catch` logs a failure with the task ID and moves on to the next email. Its `when` filter lets the exception through only once the app is stopping, when a send cancelled by `stoppingToken` isn't a failure to report.

Why not take `TaskBoardDb` in the constructor? `AddHostedService` registers the worker as a singleton. Microsoft's hosted-services page says so directly: "A hosted service is registered as a singleton, so it can't receive scoped services, such as an Entity Framework Core DbContext, by constructor injection." With `TaskBoardDb` and `IMailSender` in the constructor, the app refused to start in `Development`:

```text
Unhandled exception. System.AggregateException: Some services are not able to be constructed (Error while validating the service descriptor 'ServiceType: Microsoft.Extensions.Hosting.IHostedService Lifetime: Singleton ImplementationType: CompletionMailSender': Cannot consume scoped service 'TaskBoardDb' from singleton 'Microsoft.Extensions.Hosting.IHostedService'.)
```

In `Production` it started, and the worker kept one context for the app's whole life. That's the [captive dependency](/dump/blog/aspnet-core-dependency-injection/#captive-dependencies-and-scope-validation) from the dependency injection article.

The `catch` matters more than it looks. Without it, the first failed email with the mail service down ended `ExecuteAsync` with an exception, and the host logged two entries, shown here by level, category, event ID, and message:

```text
Error     Microsoft.Extensions.Hosting.Internal.Host  9   BackgroundService failed
Critical  Microsoft.Extensions.Hosting.Internal.Host  10  The HostOptions.BackgroundServiceExceptionBehavior is configured to StopHost. A BackgroundService has thrown an unhandled exception, and the IHost instance is stopping. To avoid this behavior, configure this to Ignore; however the BackgroundService will not be restarted.
```

Both carry the exception, `HttpRequestException: Response status code does not indicate success: 503 (Service Unavailable).`

Then the whole API stopped, 7 to 10 seconds after the completion, and `curl` couldn't connect. The process exited with code 0, as if it had been asked to stop. In a container started with Docker's `restart: on-failure` policy, that matters: the policy restarts the container "if it exits due to an error, which manifests as a non-zero exit code," so an API stopped by its worker stays down. Catching each item's failure inside the loop keeps one bad email from stopping everything.

The worker reads task IDs from `completedTasks`. How does a handler put them there?

## Passing the task ID through a channel

A **`Channel<T>`** is a queue from `System.Threading.Channels` that's safe to use from many threads at once. It has two ends: `Writer`, which adds items, and `Reader`, which takes them out in order. Reading from an empty channel doesn't hold a thread: the read waits like any other `await` until an item arrives.

The handlers and the worker must share one channel, so it's registered as a singleton next to the worker:

```csharp
builder.Services.AddSingleton(Channel.CreateUnbounded<int>());
builder.Services.AddHostedService<CompletionMailSender>();
```

`CompleteTask.Handle` takes a `Channel<int> completedTasks` parameter instead of `IMailSender`, and writes the task ID where it used to send:

```csharp
if (changed == 1)
{
    loggerFactory.CreateLogger(nameof(CompleteTask)).LogInformation("Task {TaskId} completed by user {UserId}", id, callerId);
    await completedTasks.Writer.WriteAsync(id, cancellationToken);
    return TypedResults.NoContent();
}
```

What to notice:

- The channel holds only the task ID. The worker reads the title and address when it sends, in its own scope.
- `EditTask`'s `PUT` and `PATCH` handlers, which also send the email when an edit marks a task done, write to the channel the same way.
- In the worker, `ReadAllAsync` returns each item as it's written and waits while the channel is empty, so the `await foreach` runs once per completed task, for as long as the app runs.

`CreateUnbounded` makes a channel with no size limit. A bounded channel, made with `Channel.CreateBounded<int>(capacity)`, handles a full queue in one of two ways: by default `WriteAsync` waits for space, so a handler would wait again, and with `BoundedChannelFullMode.DropWrite` the item being written is dropped without an error.

With the mail service down, Ada and Grace both got `204` in 0.095 s, and both tasks were done. The worker then sent the two emails one after the other, four attempts each, and logged each failure:

```json
{"Timestamp":"2026-10-21T14:59:20.788Z","LogLevel":"Error","EventId":0,"Category":"CompletionMailSender","Message":"Completion email for task 1 failed","Exception":"System.Net.Http.HttpRequestException: Response status code does not indicate success: 503 (Service Unavailable). …","State":{"TaskId":1,"{OriginalFormat}":"Completion email for task {TaskId} failed"},"Scopes":[]}
```

With the mail service healthy and the app warmed up, the email reached it 23 to 71 ms after the completion.

`"Scopes":[]` is new. The worker isn't handling a request, so its log entries have no trace ID, and in Jaeger each of its SQL statements and mail attempts became a separate trace with a single span: 10 traces for the two emails, apart from the two requests' traces. The task ID still connects them in the log:

```bash
jq -c 'select(.State.TaskId == 1) | {Category, Message}' taskboard.log
```

```text
{"Category":"CompleteTask","Message":"Task 1 completed by user 1001"}
{"Category":"CompletionMailSender","Message":"Completion email for task 1 failed"}
```

The failure is logged now, but the email is still dropped after its four attempts. And every email waiting in the channel lives only in the app's memory. What happens to those when the app stops?

## When the app stops

Apps stop all the time: `docker stop`, `docker compose up` with a new image, or a deployment replacing a container all send the process the signal `SIGTERM`, and Ctrl+C in a terminal sends `SIGINT`, which the host handles the same way. The host then:

1. logs `Application is shutting down...` and fires every hosted service's `stoppingToken`;
2. waits for each `ExecuteAsync` to finish, for at most `HostOptions.ShutdownTimeout`, 30 seconds by default;
3. disposes the services and lets the process exit.

To see what happens to queued emails, the mail service took 1 s to answer each one, Ada completed five tasks in a row, and the app got `SIGTERM` half a second later. With the worker as written, passing `stoppingToken` to the send:

```text
exited after 0.09 s    reached the mail service: 1 of 5    logged: Application is shutting down...
```

The token cancelled the email in progress, the `when` filter let that cancellation end the loop, and the four emails still in the channel disappeared with the process. Nothing in the log says they existed.

Passing `CancellationToken.None` to the send instead lets the worker finish what's queued. `ReadAllAsync` checks its token only when the channel is empty, so it kept handing out the queued IDs:

| Emails queued | Exited after | Reached the mail service |
|---|---|---|
| 5 | 4.7 s | 5 |
| 20 | 19.6 s | 20 |
| 40 | 31.05 s | 31 |

At 30 seconds the host stopped waiting. It disposed the services while the worker was still running, the worker's next `CreateAsyncScope` threw `ObjectDisposedException`, and 9 emails were lost. Microsoft's hosted-services page says "The host blocks in StopAsync(CancellationToken) waiting for ExecuteAsync to complete"; the wait ends at the timeout, because `BackgroundService.StopAsync` waits for `ExecuteAsync` only until the token the host passes it fires.

Docker allows less. `docker stop` sends `SIGTERM` and, per its documentation, "after a grace period, SIGKILL", a signal the process can't handle, and the grace period "is 10 seconds for Linux containers". The same build in a container built from the Dockerfile in [the configuration article](/dump/blog/configuration-and-secrets/#the-key-in-production), with 20 emails queued:

```text
docker stop returned after 10.2 s    exit code 137    reached the mail service: 11 of 20
```

Exit code 137 means the process was killed by `SIGKILL`. A crash, the system running out of memory, or `kill -9` ends the process the same way, with no warning at all: with five emails queued, `kill -9` ended the app in 0.02 s, and only the email already in flight reached the mail service.

A longer timeout and grace period would save more emails per stop, but no setting saves them from a crash. An email in memory lives exactly as long as the process. How do you keep one across a stop?

## Keeping the email in a table

Put it where the task is. A row in a new `pending_emails` table says "this task's email still has to go out", and it's saved in the same transaction as the change that completes the task. Either both are saved or neither is, and the row stays until the email is sent, through any number of stops and crashes.

The entity holds the task's ID and an idempotency key for the email, which [the next section](#sending-it-once) uses:

```csharp
public class PendingEmail
{
    public long Id { get; set; }
    public int TaskId { get; set; }
    public Guid IdempotencyKey { get; set; }
}
```

```csharp
public DbSet<PendingEmail> PendingEmails => Set<PendingEmail>();
```

```bash
dotnet ef migrations add AddPendingEmails --project TaskBoard
```

The migration creates `pending_emails` with `id`, `task_id`, and `idempotency_key` columns, as [the schema changes article](/dump/blog/changing-the-schema-without-breaking-the-app/) describes.

`CompleteTask` marks the task done with `ExecuteUpdateAsync`, which sends its `UPDATE` at once. EF Core's documentation warns that "ExecuteUpdate and ExecuteDelete do not implicitly start a transaction when they're invoked", so the `UPDATE` and the row's `INSERT` need a transaction of their own, as in [the transactions article](/dump/blog/transactions-and-concurrent-edits/#transactions-with-ef-core):

```csharp
await using var transaction = await db.Database.BeginTransactionAsync(cancellationToken);
var changed = await db.Tasks
    .Where(t => t.Id == id && t.Status != TaskItemStatus.Done)
    .Where(t => isEditor || (callerId != null && t.AssigneeId == callerId))
    .ExecuteUpdateAsync(s => s
        .SetProperty(t => t.Status, TaskItemStatus.Done)
        .SetProperty(t => t.CompletedAt, now)
        .SetProperty(t => t.Version, t => t.Version + 1), cancellationToken);
if (changed == 1)
{
    loggerFactory.CreateLogger(nameof(CompleteTask)).LogInformation("Task {TaskId} completed by user {UserId}", id, callerId);
    db.PendingEmails.Add(new PendingEmail { TaskId = id, IdempotencyKey = Guid.CreateVersion7() });
    await db.SaveChangesAsync(cancellationToken);
    await transaction.CommitAsync(cancellationToken);
    return TypedResults.NoContent();
}
```

What to notice:

- The handler no longer takes the channel. The table replaces it.
- If anything fails before `CommitAsync`, disposing the transaction rolls back the `UPDATE` too. With an exception thrown right after the `UPDATE`, Ada got `500` and her task was still open, so she could simply try again. Without the transaction, the same exception left the task done with no row, so no email would ever be sent.
- Ada's trace shows the statements: `SELECT`, `UPDATE`, `SAVEPOINT "__EFSavePoint"`, `INSERT INTO pending_emails`, `RELEASE SAVEPOINT`. The savepoint is EF Core's marker for `SaveChanges` inside your own transaction.

`EditTask` already saves with one `SaveChangesAsync`, and "all changes in a single call to SaveChanges are applied in a transaction", so it only adds the row before that call:

```csharp
if (Apply(task, edit, clock.GetUtcNow().UtcDateTime))
{
    db.PendingEmails.Add(new PendingEmail { TaskId = task.Id, IdempotencyKey = Guid.CreateVersion7() });
}
```

The worker no longer has a channel to wait on, so it checks the table. A **`PeriodicTimer`** ticks at a fixed interval, and `WaitForNextTickAsync` waits for the next tick without holding a thread:

```csharp
public class PendingEmailSender(IServiceScopeFactory scopes, ILogger<PendingEmailSender> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(5));
        do
        {
            try
            {
                await SendPendingAsync(stoppingToken);
            }
            catch (Exception exception) when (!stoppingToken.IsCancellationRequested)
            {
                logger.LogError(exception, "Reading pending emails failed");
            }
        }
        while (await timer.WaitForNextTickAsync(stoppingToken));
    }

    async Task SendPendingAsync(CancellationToken stoppingToken)
    {
        await using var scope = scopes.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<TaskBoardDb>();
        var mailSender = scope.ServiceProvider.GetRequiredService<IMailSender>();
        var emails = await db.PendingEmails.OrderBy(e => e.Id).Take(20).ToListAsync(stoppingToken);
        foreach (var email in emails)
        {
            try
            {
                await CompletionMail.SendAsync(email, db, mailSender, stoppingToken);
                db.PendingEmails.Remove(email);
                await db.SaveChangesAsync(stoppingToken);
            }
            catch (Exception exception) when (!stoppingToken.IsCancellationRequested)
            {
                logger.LogError(exception, "Completion email for task {TaskId} failed", email.TaskId);
            }
        }
    }
}
```

```csharp
builder.Services.AddHostedService<PendingEmailSender>();
```

What to notice:

- Every 5 seconds, the worker reads up to 20 rows, oldest first, in one scope.
- A row is deleted only after its email was sent. A failed email keeps its row, so the next check tries it again.
- `CompletionMail.SendAsync` now takes the row instead of the task ID.
- The outer `catch` covers a failure to read the table, such as the database being unreachable, so that doesn't stop the host either.

Back to the outage. Ada and Grace both got `204` in about 0.2 s, and the table held their emails:

```text
 id | task_id |           idempotency_key
----+---------+--------------------------------------
 85 |       1 | 01a15f00-a842-7613-94bf-c11b3c3b818d
 86 |       2 | 01a15f00-a842-71ba-8db6-86f3dea9ed52
```

Every check failed and logged `Completion email for task 1 failed` and the same for task 2. When the mail service came back, both emails went out within 2.3 seconds in three runs, and the table was empty.

Stops lose nothing now. A `SIGTERM` with three rows left ended the app in 0.1 s, and `kill -9` ended it at once. In both cases the rows were still there, and the next start sent them. With the mail service healthy, an email now arrives 0.3 to 4.5 seconds after the completion, depending on when the next check comes. And an idle worker isn't silent: each check is a `SELECT` that EF Core and Npgsql both log, 12 entries every 30 seconds, and a one-span trace in Jaeger.

The worker's test runs it without the web app. It starts `PendingEmailSender` with a `ServiceCollection` holding the test database and a mail sender whose first send fails, saves two rows, and waits until only the first row is left. Then it checks that only the second email was sent, with its row's key, and that the failed one kept its row. With the inner `catch` removed, the test fails: nothing was sent.

<details>
<summary>The complete <code>PendingEmailSenderTests.cs</code></summary>

```csharp
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;

public class PendingEmailSenderTests(TestDatabase database) : IClassFixture<TestDatabase>
{
    [Fact]
    public async Task Sends_pending_emails_with_their_keys_and_keeps_the_ones_that_failed()
    {
        var mailSender = new FlakyMailSender(failFirst: 1);
        var services = new ServiceCollection()
            .AddScoped(_ => database.CreateContext())
            .AddSingleton<IMailSender>(mailSender)
            .BuildServiceProvider();
        var first = await AddPendingEmail("First");
        var second = await AddPendingEmail("Second");
        var worker = new PendingEmailSender(services.GetRequiredService<IServiceScopeFactory>(), NullLogger<PendingEmailSender>.Instance);

        await worker.StartAsync(TestContext.Current.CancellationToken);
        var left = await WaitForPendingEmails([first.Id, second.Id], count: 1, TimeSpan.FromSeconds(5));
        await worker.StopAsync(TestContext.Current.CancellationToken);

        var sent = Assert.Single(mailSender.Sent);
        Assert.Equal(("Completed: Second", second.IdempotencyKey), (sent.Message.Subject, sent.Key));
        Assert.Equal([first.Id], left);
    }

    async Task<List<long>> WaitForPendingEmails(long[] ids, int count, TimeSpan timeout)
    {
        var deadline = DateTime.UtcNow + timeout;
        while (true)
        {
            await using var db = database.CreateContext();
            var left = await db.PendingEmails.Where(e => ids.Contains(e.Id)).Select(e => e.Id).ToListAsync(TestContext.Current.CancellationToken);
            if (left.Count <= count || DateTime.UtcNow >= deadline)
            {
                return left;
            }

            await Task.Delay(20, TestContext.Current.CancellationToken);
        }
    }

    async Task<PendingEmail> AddPendingEmail(string title)
    {
        await using var db = database.CreateContext();
        var task = new TaskItem { Title = title, Assignee = new User { Name = "Ada", Email = $"ada-{Guid.NewGuid()}@example.com", Active = true }, Version = 1 };
        db.Tasks.Add(task);
        await db.SaveChangesAsync(TestContext.Current.CancellationToken);
        var email = new PendingEmail { TaskId = task.Id, IdempotencyKey = Guid.CreateVersion7() };
        db.PendingEmails.Add(email);
        await db.SaveChangesAsync(TestContext.Current.CancellationToken);
        return email;
    }
}

public class FlakyMailSender(int failFirst) : IMailSender
{
    int calls;
    public List<(OutgoingMail Message, Guid Key)> Sent { get; } = [];

    public Task SendAsync(OutgoingMail message, Guid idempotencyKey, CancellationToken cancellationToken)
    {
        if (Interlocked.Increment(ref calls) <= failFirst)
        {
            throw new HttpRequestException("Response status code does not indicate success: 503 (Service Unavailable).");
        }

        lock (Sent) Sent.Add((message, idempotencyKey));
        return Task.CompletedTask;
    }
}
```

</details>

The test waits for the row to disappear, not for the send, because there's a moment between the two. What if the app stops right there, after the mail service accepted the email but before the row was deleted?

## Sending it once

Then the row survives, and the next start sends the email again. The worker sends each email at least once, and sometimes twice. That's the price of never losing one, and it's the same problem [the idempotency keys article](/dump/blog/idempotency-keys-and-repeated-requests/) solved for retried requests: the mail service can skip a repeat if both sends carry the same `Idempotency-Key`.

Until now, `HttpMailSender` made a new key for every send, with `Guid.CreateVersion7()`. The key has to come from the row instead, so it's the same on every attempt, before and after a restart. `IMailSender.SendAsync` takes it as a parameter:

```csharp
public interface IMailSender
{
    Task SendAsync(OutgoingMail message, Guid idempotencyKey, CancellationToken cancellationToken);
}
```

```csharp
request.Headers.Add("Idempotency-Key", idempotencyKey.ToString());
```

and `CompletionMail.SendAsync` passes `email.IdempotencyKey`. The key is a separate parameter rather than a property of `OutgoingMail` because it isn't part of the message: it's how this particular delivery is identified to the mail service.

To catch the moment between send and delete, the mail service took 1 s to answer, five rows were queued, and the app got `kill -9` while the third email was being sent. After a restart, the mail service, set to remember keys, reported:

| Key | Task 13's email after the restart | Emails Ada received for task 13 |
|---|---|---|
| Stored in the row | `DUPLICATE`, the same key seen again | 1 |
| New for every send | a second email, with a new key | 2 |

With the stored key, every task got exactly one email in both runs. A mail service that doesn't accept keys would send the repeat, so the guarantee is only as good as the receiver's support for keys.

The same goes for two copies of the app. Both would read the same rows: with 10 rows queued and two copies started together, the mail service received 20 emails, and the copy that lost each `DELETE` logged a failure for an email it had in fact sent. PostgreSQL's `SELECT … FOR UPDATE SKIP LOCKED` lets each copy claim rows the other hasn't locked, "to avoid lock contention with multiple consumers accessing a queue-like table"; with it, the same test sent 10.

## Back to Ada's completion

Ada's completion waited for the email because the handler awaited it. Every attempt and every wait between them came before her response, and when the last attempt failed, she got the `500` even though her task was saved.

Now her completion answers `204` in about 0.2 seconds. The same transaction that marks her task done saves a row in `pending_emails` with a key for her email. While the mail service is down, the worker tries every 5 seconds and logs `Completion email for task 1 failed` each time, with the task ID to find it by. When the mail service is back, the email goes out with the row's key, the row is deleted, and a repeat after a crash is recognized as one.

Each step on the way kept the email somewhere that lasts longer:

| Where the email waits | What loses it |
|---|---|
| A `Task.Run` in the handler | the request ending, or the app stopping, with nothing logged |
| A `Channel<T>` read by a `BackgroundService` | the app stopping or crashing |
| A row in `pending_emails` | nothing, until it's sent |

So a channel suits work you can afford to lose, such as refreshing a cache that the next request would rebuild anyway, and a table suits work that must happen.

## Check your understanding

1. **`_ = Task.Run(() => CompletionMail.SendAsync(id, db, mailSender, cancellationToken))` answered `204` and sent nothing, with nothing in the log. Why?** `db` belongs to the request's scope, which ASP.NET Core disposes once the response is sent, so the work found its context disposed. The `ObjectDisposedException` ended a task nobody awaited, so nothing logged it.
2. **A `BackgroundService` lets an exception escape `ExecuteAsync`. What happens to the API, and why doesn't `restart: on-failure` bring it back?** The host logs the failure and stops the whole app. The process exits with code 0, and Docker's `on-failure` policy only restarts a container that exits with a non-zero code.
3. **Twenty emails are queued in a channel when `docker stop` runs. Which ones go out?** Only those the worker sends before the process ends: within 10 seconds, when Docker sends `SIGKILL`, or sooner if the send's token cancels the work. The rest are lost, and after a crash all of them are.
4. **Why is the `pending_emails` row saved in the same transaction as the task's `UPDATE`, and why does it store an idempotency key?** The transaction makes the task change and the row all-or-nothing, so a completed task always has its email row. The stored key makes a resend after a crash between sending and deleting recognizable to the mail service, so Ada gets one email.

## Sources and further reading

- Microsoft, [Background tasks with hosted services in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/host/hosted-services?view=aspnetcore-10.0), [ASP.NET Core best practices](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/best-practices?view=aspnetcore-10.0), [Unhandled exceptions from a BackgroundService](https://learn.microsoft.com/en-us/dotnet/core/compatibility/core-libraries/6.0/hosting-exception-handling), and [HostOptions.BackgroundServiceExceptionBehavior](https://learn.microsoft.com/en-us/dotnet/api/microsoft.extensions.hosting.hostoptions.backgroundserviceexceptionbehavior?view=net-10.0).
- Microsoft, [.NET Generic Host](https://learn.microsoft.com/en-us/dotnet/core/extensions/generic-host), for the stop signals the host handles.
- Microsoft, [Channels](https://learn.microsoft.com/en-us/dotnet/core/extensions/channels) and [PeriodicTimer](https://learn.microsoft.com/en-us/dotnet/api/system.threading.periodictimer?view=net-10.0).
- Microsoft, [Transactions](https://learn.microsoft.com/en-us/ef/core/saving/transactions) and [ExecuteUpdate and ExecuteDelete](https://learn.microsoft.com/en-us/ef/core/saving/execute-insert-update-delete) in EF Core.
- .NET source at v10.0.13: [BackgroundService.cs](https://github.com/dotnet/runtime/blob/v10.0.13/src/libraries/Microsoft.Extensions.Hosting.Abstractions/src/BackgroundService.cs), [HostOptions.cs](https://github.com/dotnet/runtime/blob/v10.0.13/src/libraries/Microsoft.Extensions.Hosting/src/HostOptions.cs), [ChannelReader.cs](https://github.com/dotnet/runtime/blob/v10.0.13/src/libraries/System.Threading.Channels/src/System/Threading/Channels/ChannelReader.cs), and ASP.NET Core's [RequestServicesFeature.cs](https://github.com/dotnet/aspnetcore/blob/v10.0.13/src/Http/Http/src/Features/RequestServicesFeature.cs).
- Docker, [docker container stop](https://docs.docker.com/reference/cli/docker/container/stop/), [Compose stop_grace_period](https://docs.docker.com/reference/compose-file/services/#stop_grace_period), and [Start containers automatically](https://docs.docker.com/engine/containers/start-containers-automatically/).
- PostgreSQL, [The locking clause in SELECT](https://www.postgresql.org/docs/18/sql-select.html#SQL-FOR-UPDATE-SHARE).
