---
title: "Why a saved edit can vanish: transactions, isolation, and concurrent edits in PostgreSQL"
description: "Make database changes all-or-nothing, see what concurrent transactions can see, stop lost updates with atomic updates, row locks, or retries, and turn a stale edit into 412 Precondition Failed with a version column and ETags."
pubDate: "2026-10-19"
tags:
  - postgresql
  - ef-core
  - http
  - concurrency
audience:
  - backend
---

Alice and Bob both open task 41 in the task board's editor. The title is "Write the API docs #41", due on 17 January. Alice renames it to "Write the API reference" and saves. Bob, who still has the editor open, changes only the due date to 1 February and saves. Both get `204 No Content`. Then anyone who loads the task sees this:

```text
{"id":41,"title":"Write the API docs #41","done":false,"dueOn":"2027-02-01"}
```

Bob's due date, and the old title. Alice's rename is gone. Nothing failed: no exception, no error status, and the log shows two successful updates:

```sql
UPDATE tasks SET title = @p0
WHERE id = @p1;

UPDATE tasks SET due_on = @p0, title = @p1
WHERE id = @p2;
```

The editor sends the whole task on every save, title and due date included, the way `toTaskUpdate` does in [One task, different models](/dump/blog/api-responses-to-ui-models/). Bob's request carried the title as it was when he loaded it, and compared with the row after Alice's save, that old title counts as a change. So which part of the stack should have stopped this: the database, EF Core, or HTTP? Answering that means first understanding what databases do when several pieces of work run at the same time, which is what this article is about.

You'll need [the SQL article](/dump/blog/sql-indexes-and-parameters/) for psql, the task board's database, and parameters; [the EF Core article](/dump/blog/ef-core-behind-the-scenes/) for change tracking, what `SaveChanges` sends, and `ExecuteUpdate`; [Waiting without blocking](/dump/blog/aspnet-core-async-and-the-thread-pool/) for `await`; and [the caching article](/dump/blog/caching-static-files-and-requests/) for ETags. [HTTP from TCP to fetch](/dump/blog/http-from-tcp-to-fetch/) covers status codes and CORS, and [Forms and validation](/dump/blog/forms-and-validation/) covers the editor's side of a failed save.

## Contents

1. [Set up the example](#set-up-the-example)
2. [A transaction: all of it or none of it](#a-transaction-all-of-it-or-none-of-it)
3. [Transactions from C#](#transactions-from-c)
4. [What other transactions see](#what-other-transactions-see)
5. [Lost updates inside one request](#lost-updates-inside-one-request)
6. [Four ways to stop a lost update](#four-ways-to-stop-a-lost-update)
7. [Serializable, when the rule covers several rows](#serializable-when-the-rule-covers-several-rows)
8. [Keep transactions short](#keep-transactions-short)
9. [Edits that span two requests](#edits-that-span-two-requests)
10. [Optimistic concurrency with EF Core](#optimistic-concurrency-with-ef-core)
11. [The version reaches the client as an ETag](#the-version-reaches-the-client-as-an-etag)
12. [Back to the vanished title](#back-to-the-vanished-title)

## Set up the example

The examples use the .NET 10 SDK, Npgsql.EntityFrameworkCore.PostgreSQL 10.0.3 (which brings EF Core 10.0.4), EFCore.NamingConventions 10.0.1, Npgsql.DependencyInjection 10.0.3, and PostgreSQL 18.6 with the SQL article's database, seed, and `(assignee_id, due_on)` index. The API is the EF Core article's, with the same `TaskBoardDb`. Notes about SQL Server and MySQL come from their documentation. Changing the schema of a live database, retries in general, and authentication are outside this article's scope.

Tasks need one more column, which later sections explain. It's added once with:

```sql
alter table tasks add column version integer not null default 1;
```

On a million rows that took about a millisecond, because PostgreSQL stores the default once instead of rewriting every row. The `TaskItem` entity gets a matching property, `public int Version { get; set; }`.

Several demonstrations need two database sessions running side by side. Open two terminal windows, run psql in each, and call them **A** and **B**. Timelines in the article show what each window does, in order, top to bottom.

## A transaction: all of it or none of it

Deactivating a user hands their open tasks to someone else. That's two statements: mark the user inactive, then reassign their tasks. Run them in psql, with a typo in the second one, user 5000, who doesn't exist:

```sql
update users set active = false where id = 13;
update tasks set assignee_id = 5000 where assignee_id = 13 and not done;
```

```text
UPDATE 1
ERROR:  insert or update on table "tasks" violates foreign key constraint "tasks_assignee_id_fkey"
DETAIL:  Key (assignee_id)=(5000) is not present in table "users".
```

The second statement failed, but the first had already been saved. User 13 is now inactive and still owns 192 open tasks, which is exactly the state deactivation was meant to prevent. In psql, and in most database drivers, each statement you send on its own is saved as soon as it succeeds. This is called **autocommit**.

Put the same statements between `begin` and `commit`:

```sql
begin;
update users set active = false where id = 13;
update tasks set assignee_id = 5000 where assignee_id = 13 and not done;
select active from users where id = 13;
commit;
```

```text
BEGIN
UPDATE 1
ERROR:  insert or update on table "tasks" violates foreign key constraint "tasks_assignee_id_fkey"
DETAIL:  Key (assignee_id)=(5000) is not present in table "users".
ERROR:  current transaction is aborted, commands ignored until end of transaction block
ROLLBACK
```

After the error, PostgreSQL refuses every further statement, and `commit` answers `ROLLBACK`. User 13 is still active, and nothing changed.

That's a **transaction**: a group of statements that the database applies completely or not at all. `begin` starts one. **`commit`** makes all of its changes permanent at once, and **`rollback`** throws all of them away. Other sessions never see half a transaction. This all-or-nothing property is called **atomicity**.

## Transactions from C#

With Npgsql, a transaction belongs to one connection: you open a connection, begin a transaction on it, and run every command on that same connection.

```csharp
app.MapPost("/users/{id:int}/deactivate", async (int id, int moveTo, NpgsqlDataSource dataSource, CancellationToken cancellationToken) =>
{
    await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
    await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

    await using var deactivate = new NpgsqlCommand("update users set active = false where id = $1", connection, transaction);
    deactivate.Parameters.Add(new() { Value = id });
    await deactivate.ExecuteNonQueryAsync(cancellationToken);

    await using var move = new NpgsqlCommand("update tasks set assignee_id = $1 where assignee_id = $2 and not done", connection, transaction);
    move.Parameters.Add(new() { Value = moveTo });
    move.Parameters.Add(new() { Value = id });
    var moved = await move.ExecuteNonQueryAsync(cancellationToken);

    await transaction.CommitAsync(cancellationToken);
    return Results.Ok(new { moved });
});
```

What to notice:

- **Both commands use the same `connection` and `transaction`.** `dataSource.CreateCommand`, used in the SQL article, borrows a different connection from the pool for each command, so commands created that way can't share a transaction.
- **There's no `catch`.** With `moveTo=5000`, the second command throws, the exception leaves the handler before `CommitAsync`, and `await using` disposes the transaction. Disposing a transaction that wasn't committed sends `ROLLBACK`; PostgreSQL's log shows it. The request gets `500`, and user 13 stays active.
- **Npgsql starts it with `BEGIN TRANSACTION ISOLATION LEVEL READ COMMITTED`**, even though the code didn't choose a level. The next section explains what that means.

Without the transaction, the same code with `moveTo=5000` also returns `500`, but leaves user 13 inactive with 192 open tasks, like the psql example.

If a connection goes back to the pool with a transaction still open, Npgsql rolls it back. But until the connection is closed or returned, the transaction stays open, holding any rows it locked, which [Keep transactions short](#keep-transactions-short) shows. Always dispose connections and transactions with `await using`.

### Transactions with EF Core

The EF Core article showed that `SaveChanges` already wraps several statements in one transaction. But `ExecuteUpdate` runs immediately, in its own statement, outside any `SaveChanges`. Here's deactivation with EF Core:

```csharp
var user = await db.Users.SingleAsync(u => u.Id == id, cancellationToken);
user.Active = false;
await db.SaveChangesAsync(cancellationToken);

var moved = await db.Tasks
    .Where(t => t.AssigneeId == id && !t.Done)
    .ExecuteUpdateAsync(s => s.SetProperty(t => t.AssigneeId, moveTo), cancellationToken);
```

With `moveTo=5000`, the user is saved as inactive and the move fails: the same half-done state. To make them one unit, start a transaction on the context yourself:

```csharp
await using var transaction = await db.Database.BeginTransactionAsync(cancellationToken);

var user = await db.Users.SingleAsync(u => u.Id == id, cancellationToken);
user.Active = false;
await db.SaveChangesAsync(cancellationToken);

var moved = await db.Tasks
    .Where(t => t.AssigneeId == id && !t.Done)
    .ExecuteUpdateAsync(s => s.SetProperty(t => t.AssigneeId, moveTo), cancellationToken);

await transaction.CommitAsync(cancellationToken);
```

Now a failure in the move rolls back the deactivation too, and with a real user to move to, all 192 tasks move and the user is deactivated together. Everything the context sends between `BeginTransactionAsync` and `CommitAsync` belongs to that transaction. Inside it, EF Core wraps each `SaveChanges` in a `SAVEPOINT "__EFSavePoint"`, a marker it can roll back to; you'll see that in PostgreSQL's log.

## What other transactions see

Transactions running at the same time can't all see each other's unfinished work, or nothing would be all-or-nothing. PostgreSQL handles this with **multiversion concurrency control**, usually shortened to **MVCC**: an `UPDATE` doesn't overwrite a row in place, it writes a new version of it. Each transaction reads the versions that were committed when its current **snapshot**, its view of the data, was taken. In the words of PostgreSQL's documentation, "reading never blocks writing and writing never blocks reading."

Watch it happen. Window A changes task 41's title and doesn't commit yet:

| Window A | Window B |
|---|---|
| `begin;` | |
| `update tasks set title = 'Write the API docs, part 2' where id = 41;` | |
| | `select title from tasks where id = 41;` → `Write the API docs #41`, at once |
| | `update tasks set due_on = due_on + 7 where id = 41;` … waits |
| `commit;` | … `UPDATE 1`, after 2.6 s |
| | `select title, due_on from tasks where id = 41;` → `Write the API docs, part 2 \| 2027-01-24` |

What to notice:

- **B's `select` didn't wait.** It saw the last committed version of the row, with the old title, because A's change wasn't committed.
- **B's `update` did wait.** A transaction that changes a row takes a **row lock** on it, held until the transaction ends. A second writer to the same row waits for that lock. B's update finished 2.6 seconds later, as soon as A committed.
- **B's update kept A's title.** `due_on = due_on + 7` was applied to the row as A left it, not to the version B could see before.

### When a transaction takes its snapshot

A transaction often runs more than one statement, and between those statements, other transactions keep committing. So a question follows: does your second statement see what others committed after your first one? The answer depends on when your transaction takes its snapshot, and that's what its **isolation level** decides.

Here's a case where it matters. A summary for user 7 shows a heading, "160 open tasks", and then lists them. That's two queries:

```sql
select count(*) from tasks where assignee_id = 7 and not done;
select id, title from tasks where assignee_id = 7 and not done order by due_on;
```

Meanwhile, someone else marks one of user 7's tasks as done.

### Read Committed: a fresh snapshot for every statement

At **Read Committed**, every statement takes a new snapshot when it starts, so it sees everything committed before that moment. It's PostgreSQL's default, and the level Npgsql asks for.

| Window A | Window B |
|---|---|
| `begin;` | |
| `select count(*) … and not done;` → `160` | |
| | `update tasks set done = true where id = 4869;` → `UPDATE 1` |
| `select id, title … and not done order by due_on;` → `(159 rows)` | |
| `commit;` | |

The heading says 160, and the list has 159. Each query was correct for the moment it ran; they just ran at different moments, with B's commit in between. Reading the same data twice in one transaction and getting different answers is called a **non-repeatable read**.

That's usually acceptable, which is why Read Committed is the default: a request that runs one statement, or whose statements don't need to agree with each other, always sees the newest committed data.

### Repeatable Read: one snapshot for the whole transaction

At **Repeatable Read**, the transaction takes its snapshot at its first statement and keeps it until it ends. Every statement sees the data as it was at that moment, plus the transaction's own changes:

| Window A | Window B |
|---|---|
| `begin isolation level repeatable read;` | |
| `select count(*) … and not done;` → `160` | |
| | `update tasks set done = true where id = 4869;` → `UPDATE 1` |
| `select id, title … and not done order by due_on;` → `(160 rows)` | |
| `commit;` | |

The count and the list agree, because both read the same snapshot. B's change isn't lost: A sees it in its next transaction. In C#, ask for the level when you start the transaction:

```csharp
await using var transaction = await db.Database.BeginTransactionAsync(IsolationLevel.RepeatableRead, cancellationToken);
var openCount = await db.Tasks.CountAsync(t => t.AssigneeId == userId && !t.Done, cancellationToken);
var openTasks = await db.Tasks
    .Where(t => t.AssigneeId == userId && !t.Done)
    .OrderBy(t => t.DueOn)
    .Select(t => new OpenTask(t.Id, t.Title, t.DueOn))
    .ToListAsync(cancellationToken);
await transaction.CommitAsync(cancellationToken);
```

`IsolationLevel` comes from `System.Data`.

The price shows up when a Repeatable Read transaction writes. Its snapshot can be out of date by then, and if it tries to update a row that another transaction changed and committed after the snapshot was taken, PostgreSQL refuses rather than overwrite a change the transaction never saw. [Repeatable Read, and retry](#repeatable-read-and-retry) shows that error and how to handle it. A transaction that only reads never gets it.

| | Read Committed | Repeatable Read |
|---|---|---|
| Snapshot taken | at the start of each statement | at the first statement of the transaction |
| Two queries in one transaction | can see different data | see the same data |
| Updating a row another transaction changed and committed in the meantime | waits for its lock, then updates the newest version | waits for its lock, then fails with `40001` |
| Default in | PostgreSQL, SQL Server | MySQL |

PostgreSQL also accepts the name Read Uncommitted, but treats it as Read Committed: it never shows uncommitted changes. The strictest level, Serializable, gets [its own section](#serializable-when-the-rule-covers-several-rows).

**SQL Server:** its Read Committed uses locks for reading by default, so a reader waits for an uncommitted writer instead of seeing the old version. With the `READ_COMMITTED_SNAPSHOT` database option on, it behaves like PostgreSQL. That option is on by default in Azure SQL Database and off by default in SQL Server itself. **MySQL**'s InnoDB engine defaults to Repeatable Read, and its Repeatable Read behaves differently when writing, as the lost-update fixes show.

## Lost updates inside one request

The board has a "postpone" button that moves a task's due date a week later:

```csharp
app.MapPost("/tasks/{id:int}/postpone", async (int id, TaskBoardDb db, CancellationToken cancellationToken) =>
{
    var task = await db.Tasks.SingleAsync(t => t.Id == id, cancellationToken);
    await Task.Delay(TimeSpan.FromSeconds(2), cancellationToken); // stands in for slow work
    task.DueOn = task.DueOn!.Value.AddDays(7);
    await db.SaveChangesAsync(cancellationToken);
    return Results.Ok(new { task.DueOn });
});
```

The `Task.Delay` stands in for anything slow between reading and writing, so the problem is easy to see. Click postpone twice, quickly, with two requests sent at once:

```text
{"dueOn":"2027-01-24"} [200] after 2.03s
{"dueOn":"2027-01-24"} [200] after 2.03s
```

Two postponements, and the task moved one week, not two. Both requests read 17 January, both added seven days, and both wrote 24 January. The second write replaced the first. That's a **lost update**: two read-change-write sequences overlap, and one of them silently disappears.

A common belief is that putting the work in a transaction prevents this. Wrap the handler's body in `BeginTransactionAsync` and `CommitAsync` and try again: both requests still return `2027-01-24`, and the task still moved one week. In psql the timeline is plain:

| Window A | Window B |
|---|---|
| `begin;` | `begin;` |
| `select due_on …` → `2027-01-17` | `select due_on …` → `2027-01-17` |
| `update tasks set due_on = '2027-01-24' …` | |
| `commit;` | |
| | `update tasks set due_on = '2027-01-24' …` → `UPDATE 1` |
| | `commit;` |

At Read Committed, reading a row doesn't lock it, and nothing compares the value B read with the value it overwrites. Each transaction was perfectly atomic; they just both computed their answer from the same old value.

A C# `lock` around the handler, like the one `TaskStore` used in the [dependency injection article](/dump/blog/aspnet-core-dependency-injection/), would serialize the two requests inside one process. But a real API often runs on several servers sharing one database, and a lock in one process can't see requests handled by another.

## Four ways to stop a lost update

### Let the database do the arithmetic

The postpone doesn't need to read the date into C# at all. One statement can compute the new value from the current one:

```sql
update tasks set due_on = due_on + 7 where id = 41;
```

With EF Core, `ExecuteUpdate` can refer to the column's current value:

```csharp
var changed = await db.Tasks
    .Where(t => t.Id == id)
    .ExecuteUpdateAsync(s => s.SetProperty(t => t.DueOn, t => t.DueOn!.Value.AddDays(7)), cancellationToken);
```

which sends `SET due_on = t.due_on + 7`. Two of these at once end on 31 January, two weeks later. In psql, the second update waits for the first's row lock, and then:

| Window A | Window B |
|---|---|
| `begin;` | |
| `update … set due_on = due_on + 7 … returning due_on;` → `2027-01-24` | |
| | `update … set due_on = due_on + 7 … returning due_on;` … waits |
| `commit;` | … → `2027-01-31` |

When B's update gets the lock, PostgreSQL re-reads the row as A committed it and applies `+ 7` to that. This is the simplest fix whenever the change can be written as one statement.

### Lock the row while reading

When the logic has to happen in C#, take the row lock when reading instead of when writing. `select … for update` reads the row and locks it as if it were about to be updated:

| Window A | Window B |
|---|---|
| `begin;` | `begin;` |
| `select due_on … for update;` → `2027-01-17` | |
| | `select due_on … for update;` … waits |
| `update … set due_on = '2027-01-24' …` | |
| `commit;` | … → `2027-01-24`, after 2.9 s |
| | `update … set due_on = '2027-01-31' …` |
| | `commit;` |

B's read waited until A finished, so B started from A's result. With EF Core, read the task through `FromSql` inside a transaction:

```csharp
await using var transaction = await db.Database.BeginTransactionAsync(cancellationToken);
var task = await db.Tasks
    .FromSql($"select * from tasks where id = {id} for update")
    .SingleAsync(cancellationToken);
await Task.Delay(TimeSpan.FromSeconds(2), cancellationToken); // stands in for slow work
task.DueOn = task.DueOn!.Value.AddDays(7);
await db.SaveChangesAsync(cancellationToken);
await transaction.CommitAsync(cancellationToken);
```

Two requests at once: the first returns `2027-01-24` after 2 seconds, the second `2027-01-31` after 4, because it waited for the first's lock. Locking only affects other locking reads and writes: a plain `select` of the same row still doesn't wait. Locking this way, before you know whether anyone else will touch the row, is called **pessimistic locking**.

**MySQL** has the same `select … for update`. **SQL Server** has no `for update` on `select`; it uses the `UPDLOCK` table hint instead.

### Repeatable Read, and retry

At Repeatable Read, PostgreSQL refuses to let a transaction overwrite a row that changed after its snapshot was taken:

| Window A | Window B |
|---|---|
| `begin isolation level repeatable read;` | `begin isolation level repeatable read;` |
| `select due_on …` → `2027-01-17` | `select due_on …` → `2027-01-17` |
| `update … set due_on = '2027-01-24' …` | |
| | `update … set due_on = '2027-01-24' …` … waits |
| `commit;` | `ERROR:  40001: could not serialize access due to concurrent update` |

B's transaction is dead and must be rolled back. The error code, `40001`, means **serialization failure**: the transaction can't be applied without breaking its isolation level, and running it again from the start will usually succeed. So this fix needs a retry loop.

With EF Core 10 and Npgsql provider 10.0.3, the `40001` doesn't arrive as itself. `SaveChangesAsync` throws an `InvalidOperationException`, "An exception has been raised that is likely due to a transient failure," wrapping a `DbUpdateException`, wrapping the `PostgresException` with `SqlState` `40001`. `GetBaseException()` reaches the innermost one:

```csharp
static bool IsSerializationFailure(Exception exception)
{
    return exception.GetBaseException() is PostgresException { SqlState: PostgresErrorCodes.SerializationFailure };
}
```

```csharp
for (var attempt = 1; ; attempt++)
{
    try
    {
        await using var transaction = await db.Database.BeginTransactionAsync(IsolationLevel.RepeatableRead, cancellationToken);
        var task = await db.Tasks.SingleAsync(t => t.Id == id, cancellationToken);
        await Task.Delay(TimeSpan.FromSeconds(2), cancellationToken); // stands in for slow work
        task.DueOn = task.DueOn!.Value.AddDays(7);
        await db.SaveChangesAsync(cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return Results.Ok(new { task.DueOn, attempt });
    }
    catch (Exception exception) when (IsSerializationFailure(exception) && attempt < 3)
    {
        db.ChangeTracker.Clear();
    }
}
```

What to notice:

- **The whole transaction runs again**, including the read. Retrying only the `SaveChanges` would write the same stale value.
- **`ChangeTracker.Clear()`** forgets the stale entity. Without it, the identity map from the EF Core article would hand back the old object on the next read.
- **`attempt < 3`** stops after three tries; the third failure reaches the caller as a `500`.

Two requests at once: the first returns `{"dueOn":"2027-01-24","attempt":1}` after 2 seconds, and the second `{"dueOn":"2027-01-31","attempt":2}` after 4.

**MySQL**'s Repeatable Read doesn't raise this error: its `UPDATE` works on the latest committed row, so the lost update goes through silently. **SQL Server**'s Repeatable Read uses locks instead of snapshots, and two transactions that read and then update the same row can deadlock, which SQL Server resolves by failing one of them with error 1205.

### Check a version when writing

The fourth fix doesn't lock or wait: it records which version of the row a change was based on, and writes only if the row is still at that version. It's the one that also fixes the opening, so it gets its own sections, starting with [Edits that span two requests](#edits-that-span-two-requests).

| Fix | What the second request experiences | Needs a retry |
|---|---|---|
| Atomic `UPDATE` | waits for the row lock, then builds on the first change | No |
| `select … for update` | its read waits, then sees the first change | No |
| Repeatable Read | fails with `40001`, succeeds on the next attempt | Yes |
| Version check | updates zero rows | The caller decides |

## Serializable, when the rule covers several rows

The board has a rule: nobody gets more than three open tasks. The endpoint that assigns a new task counts first:

```csharp
await using var transaction = await db.Database.BeginTransactionAsync(cancellationToken);
var open = await db.Tasks.CountAsync(t => t.AssigneeId == id && !t.Done, cancellationToken);
if (open >= 3)
{
    return Results.Conflict("This person already has three open tasks.");
}

await Task.Delay(TimeSpan.FromSeconds(2), cancellationToken); // stands in for slow work
db.Tasks.Add(new TaskItem { Title = title, AssigneeId = id, Version = 1 });
await db.SaveChangesAsync(cancellationToken);
await transaction.CommitAsync(cancellationToken);
return Results.Ok();
```

User 1001 has two open tasks. Two requests at once both count two, both insert, both return `200`, and user 1001 now has four. No row was updated twice, so there's no row lock to wait for and nothing for Repeatable Read to catch: in psql, two Repeatable Read transactions doing the same also both commit, leaving four.

The highest isolation level, **Serializable**, catches it. PostgreSQL tracks what each transaction read, and if the result couldn't have come from running the transactions one after the other, it fails one of them. Start the transaction with `BeginTransactionAsync(IsolationLevel.Serializable, cancellationToken)`, and the second request gets a `500`, with this in the log:

```text
Npgsql.PostgresException (0x80004005): 40001: could not serialize access due to read/write dependencies among transactions
```

In psql, the error comes at the second `commit`, with a hint: "The transaction might succeed if retried." Run again, the transaction counts the three tasks that now exist and refuses, which is the rule working.

Some think Serializable is just a slower Read Committed. What it changes is which transactions fail. Every transaction at that level can get a `40001` and needs the retry loop from the previous section. PostgreSQL also has to be cautious about which rows a transaction depends on: in psql, two Serializable transactions counting and inserting for different users, 1001 and 1002, still conflicted, and one failed. Use it where a rule spans several rows, and keep those transactions small.

## Keep transactions short

A transaction holds its connection, and every row lock it takes, until it commits or rolls back. Put the locking postpone's two-second delay inside the transaction, where a call to another service might sit in real code, and send three requests at once:

```text
request 2: 200 after 2.00s
request 3: 200 after 4.01s
request 1: 200 after 6.01s
```

They ran one after another, each waiting for the previous one's lock. One second in, PostgreSQL's `pg_stat_activity` view, which lists every session, showed this:

```text
        state        | wait_event_type |  wait_event
---------------------+-----------------+---------------
 active              | Lock            | transactionid
 active              | Lock            | tuple
 idle in transaction | Client          | ClientRead
```

One session holds the lock and sits **idle in transaction**: PostgreSQL is waiting for the application to send the next statement, while the application is waiting for its slow call. The other two wait for its lock. As the [async article](/dump/blog/aspnet-core-async-and-the-thread-pool/) showed, an `await` gives the thread back, but it doesn't give back the connection or the lock.

So inside a transaction, do only database work. Call other services, send emails, and do slow computation before `BeginTransactionAsync` or after `CommitAsync`, and never wait for a person while a transaction is open.

## Edits that span two requests

Back to Alice and Bob. Their edit isn't a read and a write inside one request: Bob's request loaded the task when he opened the editor, and his save is a separate request, possibly minutes later. That rules out the earlier fixes.

You might think the editor could lock the row when it opens. But a `GET` and a `PATCH` are separate requests, with separate connections and transactions, and the previous section showed why a transaction must never wait for a person to finish typing. Others assume EF Core already protects against this, since `SaveChanges` only sends changed columns. It does compare, but with the row as it is now: Bob's stale title differs from Alice's new title, so it counts as a change and gets sent.

What's needed is a way to tell, at save time, that the data Bob's edit was based on has changed since he loaded it. That's what the `version` column is for. Every write increases it, and every edit says which version it started from:

```sql
update tasks set title = $1, due_on = $2, version = version + 1
where id = $3 and version = $4
returning version;
```

If the task is still at the version the editor loaded, the update matches one row and `returning` sends back the new version. If anyone saved in between, `version = $4` matches nothing, and the update changes zero rows. Zero rows can also mean the task was deleted, so check whether it still exists to tell "not found" from "changed".

This approach is called **optimistic concurrency**: it doesn't lock anything and assumes conflicts are rare, but it checks at the last moment and refuses the write when one happened. It's still safe when two version-checked updates arrive at the same moment:

| Window A | Window B |
|---|---|
| `begin;` | |
| `update tasks set title = 'Write the API docs, part 2', version = version + 1 where id = 41 and version = 1;` → `UPDATE 1` | |
| | `update tasks set title = 'Document the API', version = version + 1 where id = 41 and version = 1;` … waits |
| `commit;` | … → `UPDATE 0`, after 2.6 s |

B waited for A's row lock, then re-checked its `where` against the row A committed, found version 2, and updated nothing, all at Read Committed.

**SQL Server** checks the condition the same way: an `UPDATE` there selects its rows from the latest committed data, even with `READ_COMMITTED_SNAPSHOT` on, so a version-checked update works without a stricter isolation level.

## Optimistic concurrency with EF Core

EF Core does the version check for you once you mark the property as a **concurrency token**:

```csharp
protected override void OnModelCreating(ModelBuilder modelBuilder)
{
    modelBuilder.Entity<TaskItem>().Property(t => t.CreatedAt).HasDefaultValueSql("now()");
    modelBuilder.Entity<TaskItem>().Property(t => t.Version).IsConcurrencyToken();
}
```

Putting `[ConcurrencyCheck]` on the property does the same. From then on, every `UPDATE` EF Core sends for a task includes the version it loaded in the `WHERE`:

```sql
UPDATE tasks SET due_on = @p0, title = @p1, version = @p2
WHERE id = @p3 AND version = @p4;
```

EF Core compares but doesn't increase the version for you; that's your code's job, `task.Version++` before saving. If the `UPDATE` changes no rows, `SaveChanges` throws `DbUpdateConcurrencyException`:

```text
The database operation was expected to affect 1 row(s), but actually affected 0 row(s); data may have been modified or deleted since entities were loaded.
```

A natural assumption is that loading the task and comparing its version in C# is check enough. Put a two-second pause between that comparison and `SaveChanges`, and send Alice's and Bob's saves at the same moment, both based on version 1: both pass the C# comparison, because both loaded version 1. Alice's `UPDATE` runs first and gets `204`. Bob's `UPDATE`, with `WHERE … AND version = 1`, matches nothing, and EF Core throws. Only the check inside the `UPDATE` is reliable, because only there do the check and the write happen as one step.

### Every write must increase the version

The version only works if every change to the row increases it, including writes that don't go through change tracking. The atomic postpone from earlier doesn't. So: an editor loads task 44 at version 1, the postpone runs with `ExecuteUpdate`, moving the due date to 24 January without touching the version, and then the editor saves its title with "version 1":

```text
editor saves the title with If-Match "1": 204
{"id":44,"title":"Plan the release notes properly","done":true,"dueOn":"2027-01-17","version":2}
```

The check passed, and the editor's stale due date undid the postponement. Increase the version in the bulk update too:

```csharp
var changed = await db.Tasks
    .Where(t => t.Id == id)
    .ExecuteUpdateAsync(s => s
        .SetProperty(t => t.DueOn, t => t.DueOn!.Value.AddDays(7))
        .SetProperty(t => t.Version, t => t.Version + 1), cancellationToken);
```

With that, the same stale save is refused, and the postponement stays.

PostgreSQL also has a hidden system column, `xmin`, that changes on every write by itself, and Npgsql can use it as a concurrency token instead of a column you maintain. It exists only in PostgreSQL, so it doesn't carry over to other databases; **SQL Server**'s equivalent is a `rowversion` column. An ordinary integer column you maintain works the same on every engine.

## The version reaches the client as an ETag

The editor has to send back the version it loaded. HTTP already has a place for this. The [caching article](/dump/blog/caching-static-files-and-requests/) used an **ETag**, a tag for one version of a response, so the browser could ask "send it only if it changed" with `If-None-Match`. The same tag works in the other direction: a request with **`If-Match`** says "do this only if the current ETag is still this one."

The `GET` endpoint sends the version as the ETag:

```csharp
app.MapGet("/tasks/{id:int}", async (int id, TaskBoardDb db, HttpContext context, CancellationToken cancellationToken) =>
{
    var task = await db.Tasks
        .Where(t => t.Id == id)
        .Select(t => new TaskDetails(t.Id, t.Title, t.Done, t.DueOn, t.Version))
        .SingleOrDefaultAsync(cancellationToken);
    if (task is null)
    {
        return Results.NotFound();
    }

    context.Response.Headers.ETag = $"\"{task.Version}\"";
    return Results.Ok(task);
});
```

An ETag is written in double quotes, so version 3 becomes `"3"`. The version is also in the JSON body here, which is harmless; the header is what HTTP uses.

The `PATCH` endpoint requires `If-Match`, checks it, and lets the concurrency token catch anything that happens after the check:

```csharp
app.MapPatch("/tasks/{id:int}", async (int id, TaskEdit edit, HttpContext context, TaskBoardDb db, CancellationToken cancellationToken) =>
{
    var ifMatch = context.Request.GetTypedHeaders().IfMatch;
    if (ifMatch.Count == 0)
    {
        return Results.Problem("Send the task's ETag in an If-Match header.", statusCode: StatusCodes.Status428PreconditionRequired);
    }

    var task = await db.Tasks.SingleOrDefaultAsync(t => t.Id == id, cancellationToken);
    if (task is null)
    {
        return Results.NotFound();
    }

    var current = new EntityTagHeaderValue($"\"{task.Version}\"");
    if (!Matches(ifMatch, current))
    {
        return Results.Problem("The task changed after you loaded it. Load it again and reapply your edit.", statusCode: StatusCodes.Status412PreconditionFailed);
    }

    task.Title = edit.Title;
    task.DueOn = edit.DueOn;
    task.Version++;

    try
    {
        await db.SaveChangesAsync(cancellationToken);
    }
    catch (DbUpdateConcurrencyException)
    {
        return Results.Problem("The task changed after you loaded it. Load it again and reapply your edit.", statusCode: StatusCodes.Status412PreconditionFailed);
    }

    context.Response.Headers.ETag = $"\"{task.Version}\"";
    return Results.NoContent();
});

static bool Matches(IList<EntityTagHeaderValue> ifMatch, EntityTagHeaderValue current)
{
    foreach (var tag in ifMatch)
    {
        if (tag.Equals(EntityTagHeaderValue.Any) || tag.Compare(current, useStrongComparison: true))
        {
            return true;
        }
    }

    return false;
}
```

`TaskEdit` is `public record TaskEdit(string Title, DateOnly? DueOn);`, and `EntityTagHeaderValue` comes from `Microsoft.Net.Http.Headers`. What to notice:

- **`GetTypedHeaders().IfMatch`** parses the header into a list, because `If-Match` can carry several tags.
- **No `If-Match` gets `428 Precondition Required`.** Accepting a save without one would bring back last-write-wins for any client that forgets the header.
- **A mismatch gets `412 Precondition Failed`,** before anything is written. The `DbUpdateConcurrencyException` catch covers a save that arrives between this check and the `UPDATE`.
- **`Results.Problem`** sends a short JSON explanation, so the client can tell the two cases apart.
- **The response carries the new ETag**, so the editor can keep editing without reloading.

Here's the opening, replayed against this endpoint:

```bash
curl -i http://localhost:5000/tasks/41
```

```text
HTTP/1.1 200 OK
ETag: "1"
```

Alice saves with `If-Match: "1"`:

```bash
curl -i -X PATCH -H 'Content-Type: application/json' -H 'If-Match: "1"' \
  -d '{"title":"Write the API reference","dueOn":"2027-01-17"}' http://localhost:5000/tasks/41
```

```text
HTTP/1.1 204 No Content
ETag: "2"
```

Bob saves his due date, still with the `"1"` he loaded:

```text
HTTP/1.1 412 Precondition Failed
Content-Type: application/problem+json

{"type":"https://tools.ietf.org/html/rfc9110#section-15.5.13","title":"Precondition Failed","status":412,"detail":"The task changed after you loaded it. Load it again and reapply your edit."}
```

Without `If-Match` at all:

```text
HTTP/1.1 428 Precondition Required
Content-Type: application/problem+json

{"title":"Precondition Required","status":428,"detail":"Send the task's ETag in an If-Match header."}
```

Bob's editor reloads, gets Alice's title and `ETag: "2"`, and saves his due date again with `If-Match: "2"`: `204`, `ETag: "3"`, and the task has both changes.

A few details of `If-Match` that the endpoint handles through `Matches`:

| `If-Match` value | Result | Why |
|---|---|---|
| `"3"` at version 3 | matches | the same tag |
| `W/"3"` | `412` | `W/` marks a **weak** tag, and `If-Match` only accepts exact, strong matches |
| `"1", "3"` | matches | a list matches if any tag does |
| `*` | matches | "whatever the current version is", so it only guards against a missing task |
| `3`, without quotes | `428` | not a valid tag, so the header parses as empty |

### From the browser

If the editor runs on another origin, CORS applies, as [HTTP from TCP to fetch](/dump/blog/http-from-tcp-to-fetch/) explains. Two parts of the policy matter here. `ETag` isn't one of the response headers a script may read by default, so the API has to expose it; without that, `response.headers.get("ETag")` returns `null` in the browser. And `If-Match` isn't one of the request headers allowed without asking, so a `PATCH` carrying it triggers a preflight that must allow it; without that, the browser never sends the `PATCH`. In ASP.NET Core:

```csharp
builder.Services.AddCors(options => options.AddDefaultPolicy(policy =>
    policy.WithOrigins("http://localhost:4200")
        .WithMethods("GET", "PATCH")
        .WithHeaders("Content-Type", "If-Match")
        .WithExposedHeaders("ETag")));
```

and `app.UseCors();` after `builder.Build()`.

### What the client does on 412

A `412` means someone else saved first. The editor shouldn't throw the person's work away, and it shouldn't resend automatically with the new ETag either, because that's exactly the overwrite the check exists to prevent. Keep the draft, as the editor in [Forms and validation](/dump/blog/forms-and-validation/) does when a save fails, load the current task, show what changed, and let the person apply their change again.

## Back to the vanished title

Alice's title vanished because Bob's save was built on data that was already out of date before his request started. Each `UPDATE` was correct, so no transaction or isolation level could have seen the problem: transactions protect work inside one request, and this conflict spanned two requests and two people. What stops it is a version on the row, sent to the editor as an ETag, sent back as `If-Match`, and checked in the same statement that writes. Bob's save then gets `412`, his editor reloads, and both changes survive.

1. **Group statements that must succeed together** in one transaction, on one connection, and dispose it with `await using`.
2. **Don't read, compute, and write** when one `UPDATE` can do the arithmetic.
3. **When the logic must run in C#,** lock the row with `for update`, or use Repeatable Read with a retry loop.
4. **Keep transactions to database work only**, and keep them short.
5. **For edits that span requests,** give the row a version, increase it on every write, send it as an ETag, and require `If-Match`.

## Check your understanding

1. **Two requests each load task 41 at Read Committed, add seven days to its due date, and save, at the same time. What's the final date, and why?** One week later, not two. Both read the same date, and reading doesn't lock at Read Committed, so the second write replaces the first: a lost update.
2. **Which of these fixes needs a retry loop: an atomic `UPDATE`, `select … for update`, Repeatable Read, Serializable?** Repeatable Read and Serializable. They detect the conflict by failing a transaction with `40001`. The other two make the second transaction wait instead.
3. **Why can't a row lock taken while handling the `GET` protect the `PATCH` that comes later?** The lock belongs to a transaction, and the `GET`'s transaction ends with its request. Holding it open until the person saves would keep a connection and a lock for minutes and block everyone else.
4. **A client sends `If-Match: "4"`, and the task is at version 5. What should the server do, and what should the client do?** The server answers `412 Precondition Failed` without saving. The client keeps the person's draft, reloads the task, shows what changed, and lets them apply their edit again.

## Sources and further reading

- PostgreSQL 18 documentation: [transactions](https://www.postgresql.org/docs/18/tutorial-transactions.html), [MVCC introduction](https://www.postgresql.org/docs/18/mvcc-intro.html), [transaction isolation](https://www.postgresql.org/docs/18/transaction-iso.html), [explicit locking](https://www.postgresql.org/docs/18/explicit-locking.html), [serialization failure handling](https://www.postgresql.org/docs/18/mvcc-serialization-failure-handling.html).
- [Npgsql: transactions](https://www.npgsql.org/doc/basic-usage.html#basic-transactions) and [concurrency tokens in the EF Core provider](https://www.npgsql.org/efcore/modeling/concurrency.html).
- EF Core documentation: [transactions](https://learn.microsoft.com/en-us/ef/core/saving/transactions) and [handling concurrency conflicts](https://learn.microsoft.com/en-us/ef/core/saving/concurrency).
- [RFC 9110](https://www.rfc-editor.org/rfc/rfc9110.html): ETag, `If-Match`, and `412 Precondition Failed`. [RFC 6585](https://www.rfc-editor.org/rfc/rfc6585.html#section-3): `428 Precondition Required`.
- SQL Server: [transaction locking and row versioning guide](https://learn.microsoft.com/en-us/sql/relational-databases/sql-server-transaction-locking-and-row-versioning-guide?view=sql-server-ver17). MySQL 8.4: [transaction isolation levels](https://dev.mysql.com/doc/refman/8.4/en/innodb-transaction-isolation-levels.html) and [locking reads](https://dev.mysql.com/doc/refman/8.4/en/innodb-locking-reads.html).
