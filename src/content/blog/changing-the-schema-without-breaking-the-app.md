---
title: "Two versions, one database: changing the schema without breaking the running app"
description: "Why a migration that's correct for the new code breaks the version that's still running, how to split a breaking change into expand, migrate, and contract releases with EF Core migrations, and how to run each migration against a live PostgreSQL database without stalling the API."
pubDate: "2026-10-20"
tags:
  - aspnet-core
  - dotnet
  - ef-core
  - postgresql
audience:
  - backend
---

The task board is getting an "In progress" column. Until now a task has been either open or done, stored in a `done` boolean, so the change replaces `done` with a `status`: to do, in progress, or done. You change the entity, EF Core generates a migration, and the deployment applies it a few seconds before the new version of the app starts, while the current version is still answering requests.

From that moment, every task request to the current version fails with `500`. The new version starts and works, but every task that was done now says "To do": all 799,521 of them.

The migration did exactly what the new code needed. So why did it break the running app and lose the data, and how should the change have been made?

You'll need [EF Core behind the scenes](/dump/blog/ef-core-behind-the-scenes/) for `DbContext`, change tracking, and what `SaveChanges` sends, and [the transactions article](/dump/blog/transactions-and-concurrent-edits/) for transactions, locks, the version column, and the `412` it produces. [The SQL article](/dump/blog/sql-indexes-and-parameters/) built the database and explains tables and indexes.

## Contents

1. [Set up the example](#set-up-the-example)
2. [Migrations: schema changes as code](#migrations-schema-changes-as-code)
3. [The change that breaks the running version](#the-change-that-breaks-the-running-version)
4. [Expand, migrate, contract](#expand-migrate-contract)
5. [Release 1: add the status and write both columns](#release-1-add-the-status-and-write-both-columns)
6. [Release 2: copy the data and switch reads](#release-2-copy-the-data-and-switch-reads)
7. [Releases 3 and 4: stop using done, then drop it](#releases-3-and-4-stop-using-done-then-drop-it)
8. [Running a migration against the live app](#running-a-migration-against-the-live-app)
9. [Without EF Core migrations](#without-ef-core-migrations)
10. [Back to the "In progress" column](#back-to-the-in-progress-column)

## Set up the example

The examples use the .NET 10 SDK (ASP.NET Core 10.0.13), EF Core 10.0.4 through Npgsql.EntityFrameworkCore.PostgreSQL 10.0.3, EFCore.NamingConventions 10.0.1, the `dotnet-ef` tool 10.0.4, and PostgreSQL 18.6, in the `Production` environment. The code is the sliced task board at the end of [the idempotency keys article](/dump/blog/idempotency-keys-and-repeated-requests/), without its three-second stand-in delay. [The layered and sliced article](/dump/blog/layered-and-sliced-code-organization/) and [the endpoints article](/dump/blog/resource-style-and-action-style-endpoints/) compare its layout and endpoint style with the alternatives.

The database is the SQL article's million tasks plus the columns later articles added. Until now, each of those changes was a SQL script in the repository's `db/` folder, such as `db/002-add-priority.sql`, that someone ran by hand.

To stand in for a deployment, two copies of the app run at once against the same database, one on port 5080 and one on port 5081, so you can see what happens while the old and the new version both serve requests. Removing fields from the API, deployment platforms, tools for rewriting very large tables online, and runnable SQL Server or MySQL examples are outside this article's scope.

## Migrations: schema changes as code

A **migration** is a C# class with two methods: `Up` changes the schema, and `Down` undoes the change. EF Core generates it by comparing your current model, meaning the entity classes and their configuration, with a snapshot of the model saved when the previous migration was created. Each database records the migrations already applied in a table called `__EFMigrationsHistory`, so EF Core knows which ones are still pending.

The `dotnet ef` command creates and applies migrations. Install it as a local tool, so the version is pinned in the repository, and add the design-time package to the project:

```bash
dotnet new tool-manifest
dotnet tool install dotnet-ef --version 10.0.4
dotnet add TaskBoard package Microsoft.EntityFrameworkCore.Design --version 10.0.4
```

The first migration describes the database as it already is. It's usually called the **baseline**:

```bash
dotnet ef migrations add Baseline --project TaskBoard
```

That writes three files to `TaskBoard/Migrations/`:

- `20261020133632_Baseline.cs`, 100 lines, whose `Up` creates every table.
- `20261020133632_Baseline.Designer.cs`, the model as it was when this migration was created.
- `TaskBoardDbModelSnapshot.cs`, the latest model, which the next `migrations add` compares against.

A slice of `Up`:

```csharp
migrationBuilder.CreateTable(
    name: "tasks",
    columns: table => new
    {
        id = table.Column<int>(type: "integer", nullable: false)
            .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
        title = table.Column<string>(type: "text", nullable: false),
        done = table.Column<bool>(type: "boolean", nullable: false),
        // …
```

What to notice:

- The timestamp in the file name orders the migrations, and the class name follows it.
- The column names are snake_case because the model uses EFCore.NamingConventions.
- `Up` creates the tables, which is right for an empty database and wrong for this one. `dotnet ef database update` against the existing database fails with `42P07: relation "users" already exists`.

So the baseline has to be recorded as applied without running it. EF Core's documentation has no procedure for this; the closest is a step in its advice on squashing migrations: "Insert a single row into the migrations history". The table's columns are also snake_case here:

```sql
create table if not exists "__EFMigrationsHistory" (
    migration_id character varying(150) not null,
    product_version character varying(32) not null,
    constraint pk___ef_migrations_history primary key (migration_id)
);

insert into "__EFMigrationsHistory" (migration_id, product_version)
values ('20261020133632_Baseline', '10.0.4');
```

After that, `dotnet ef migrations list` shows the baseline as applied, and the next migration is the first one that runs.

### When the model and the database disagree

The baseline describes what the model says, which isn't exactly what the hand-written scripts created. Building a database from the migrations and comparing it with the real one, using `pg_dump --schema-only` on both, shows the differences:

| | Real database | Built from the baseline |
|---|---|---|
| Primary key names | `tasks_pkey` | `pk_tasks` |
| Defaults on `done`, `version`, `tags`, `priority`, `active` | yes | none |
| Identity columns | `generated always` | `generated by default` |
| Unique email | `users_email_key` | missing |
| Index for one person's tasks | `(assignee_id, due_on)` | `ix_tasks_assignee_id` on `assignee_id` only |

Two consequences. A test database or a new environment built from the migrations isn't the production database. And a later migration that refers to something by EF Core's name fails on production: changing the assignee's foreign key to `ON DELETE SET NULL` generated `ALTER TABLE tasks DROP CONSTRAINT fk_tasks_users_assignee_id;`, which worked on the database built from migrations and failed on the real one with `42704: constraint "fk_tasks_users_assignee_id" of relation "tasks" does not exist`. Comparing the two `pg_dump` outputs before relying on the baseline shows what to fix, either by configuring the model to match or by editing the generated migrations.

## The change that breaks the running version

The new code replaces the entity's `bool Done` with a status:

```csharp
public enum TaskItemStatus
{
    Todo,
    InProgress,
    Done,
}

public class TaskItem
{
    public int Id { get; set; }
    public string Title { get; set; } = "";
    public TaskItemStatus Status { get; set; }
    // …
}
```

The enum is called `TaskItemStatus` for the same reason the entity is called `TaskItem`: .NET already has a `System.Threading.Tasks.TaskStatus`. EF Core stores the enum as an integer, like `priority`. The endpoints read and write `Status`, and a new `POST /tasks/{id}/start` moves a task to "In progress".

Generating the migration prints a warning:

```bash
dotnet ef migrations add ReplaceDoneWithStatus --project TaskBoard
```

```text
An operation was scaffolded that may result in the loss of data. Please review the migration for accuracy.
```

```csharp
protected override void Up(MigrationBuilder migrationBuilder)
{
    migrationBuilder.DropColumn(
        name: "done",
        table: "tasks");

    migrationBuilder.AddColumn<int>(
        name: "status",
        table: "tasks",
        type: "integer",
        nullable: false,
        defaultValue: 0);
}
```

EF Core sees a property removed and a property added. It can't know that one replaces the other, so it drops `done` and adds `status` with the default `0`, which is `Todo`, for every row.

Applied while the current version runs on port 5080 and the new one is starting on port 5081, with one request of each kind before and after:

| | `GET /tasks/{id}` | `GET /tasks?done=false` | `POST /tasks` | `POST /tasks/{id}/complete` |
|---|---|---|---|---|
| Current version, before | `200` | `200` | `201` | `204` |
| New version, before | `500` | `500` | `500` | `500` |
| Current version, after | `500` | `500` | `500` | `500` |
| New version, after | `200` | `200` | `201` | `204` |

The current version's log shows why:

```text
fail: Microsoft.EntityFrameworkCore.Query[10100]
      Npgsql.PostgresException (0x80004005): 42703: column t.done does not exist
```

What to notice:

- Before the migration, the new version fails because `status` doesn't exist yet. After it, the current version fails because `done` doesn't exist anymore. No order of "migrate" and "start" avoids a window where one of them is broken.
- Task 4 was done. After the migration it reads `{"done":false,"status":"Todo"}`, like every other task. The data is gone, not hidden.
- Renaming a column has the same problem without the data loss. Renaming `Done` to `IsDone` generates `ALTER TABLE tasks RENAME COLUMN done TO is_done;` with no warning, and the current version fails with the same `42703`.

The old and new versions run at the same time in almost every deployment:

- A **rolling deployment** replaces the app's instances one at a time, so some run the old version while others run the new one.
- A **blue-green deployment** starts the new version next to the old one and switches traffic once it's ready.
- Even with a single instance, the migration runs first and the old version keeps serving requests until it's restarted.

So the schema after each migration has to work with two versions of the code: the one that's still running and the one that's about to start.

## Expand, migrate, contract

The way out is to never make a change that the running version can't handle. Danilo Sato's description on Martin Fowler's site gives it a name: "Parallel change, also known as expand and contract, is a pattern to implement backward-incompatible changes to an interface in a safe manner, by breaking the change into three distinct phases: expand, migrate, and contract." Pramod Sadalage's article on evolutionary database design describes the middle part as "a transition phase", "a period of time when the database supports both the old access pattern and the new ones simultaneously".

For the task board, that's four releases:

| Release | Migration, run before the release starts | The code reads | The code writes | Runs next to |
|---|---|---|---|---|
| 1 | add `status` | `done` | `done` and `status` | the current version |
| 2 | copy `done` into `status` | `status` | `done` and `status` | release 1 |
| 3 | give `done` a default | `status` | `status` | release 2 |
| 4 | drop `done` | `status` | `status` | release 3 |

One rule decides the timing: a release's migration runs after the previous release has fully rolled out, and before the new release starts. So each migration only has to work with two versions of the code, the one before it and its own.

## Release 1: add the status and write both columns

Release 1 adds `Status` to the entity and keeps `Done`. The generated migration is just the new column, and it's safe to apply while the current version runs:

```csharp
migrationBuilder.AddColumn<int>(
    name: "status",
    table: "tasks",
    type: "integer",
    nullable: false,
    defaultValue: 0);
```

The current version doesn't know about `status`, so it ignores it. When it inserts a task, PostgreSQL fills in the default.

The code keeps reading `done` and starts writing both columns. Completing a task sets both:

```csharp
.ExecuteUpdateAsync(s => s
    .SetProperty(t => t.Done, true)
    .SetProperty(t => t.Status, TaskItemStatus.Done)
    .SetProperty(t => t.CompletedAt, now)
    .SetProperty(t => t.Version, t => t.Version + 1), cancellationToken);
```

and editing sets `Status` whenever it completes or reopens a task:

```csharp
if (completing)
{
    task.Status = TaskItemStatus.Done;
    task.CompletedAt = now;
}

if (reopening)
{
    task.Status = TaskItemStatus.Todo;
    task.CompletedAt = null;
}
```

With release 1's migration applied and both versions running:

```text
current version completes task 1    done=true   status=0
release 1 completes task 6          done=true   status=2
current version reopens task 6      done=false  status=2
tasks where done and status disagree: 799,522
```

What to notice:

- The current version still changes `done` without touching `status`, so new disagreements appear for as long as it runs.
- That's why release 1 keeps reading `done`: the status isn't trustworthy yet.
- Copying the data now would be pointless for the same reason. It has to wait until no instance of the current version is left.

## Release 2: copy the data and switch reads

Once release 1 has fully rolled out, every running instance writes both columns. Release 2's migration copies the old values over. The model doesn't change, so `dotnet ef migrations add BackfillTaskStatus` generates an empty `Up`, and you write the statement yourself:

```csharp
protected override void Up(MigrationBuilder migrationBuilder)
{
    // status: 0 = Todo, 2 = Done
    migrationBuilder.Sql("""
        update tasks
        set status = case when done then 2 else 0 end, version = version + 1
        where status <> case when done then 2 else 0 end;
        """);
}
```

What to notice:

- The statement uses literal numbers instead of `TaskItemStatus`. EF Core's documentation says: "Don't use the current DbContext or entity CLR types to move data in a migration." The enum could change later, and the migration has to do the same thing whenever it runs.
- The `where` clause skips the rows release 1 already got right.
- The statement ends with a semicolon. `dotnet ef database update` and bundles work without it, but an idempotent script, described later, wraps each statement in a block and failed with `syntax error at or near "END"` without it.
- It also adds one to `version`. The next subsection shows why.

### The edit that lands during the copy

Release 1 is still running while the copy runs. On a fresh copy of the database, the `update` took between 8 and 15 seconds for 799,522 rows, and each row it changes stays locked until it commits.

Suppose someone using release 1 reopens task 3, which is done, during the copy. Release 1 loaded the task before the copy reached it, so it saw `done=true, status=0`. Reopening sets `Done = false` and `Status = Todo`, but `Status` already is `Todo` in what release 1 loaded, so [EF Core's change tracking](/dump/blog/ef-core-behind-the-scenes/#change-tracking-and-what-savechanges-sends) leaves it out of the `UPDATE`. That `UPDATE` waits for the copy's lock on the row, and then runs:

```text
copy without the version bump    PUT /tasks/3: 204 after 2.26 s    done=false  status=2
copy with the version bump       PUT /tasks/3: 412 after 2.33 s    done=true   status=2
```

Without the bump, the copy set `status=2` and the reopen then set `done=false`: one task is half done. With the bump, the edit's `UPDATE … WHERE version = 1` no longer matches the row, so EF Core reports [a concurrency conflict](/dump/blog/transactions-and-concurrent-edits/#optimistic-concurrency-with-ef-core) and the endpoint answers `412`. The person reloads and reopens the task again. The cost is that every task's `ETag` changes once, so anyone with a task open during the copy gets one `412` on their next save.

A query confirms the copy:

```sql
select count(*) from tasks where done <> (status = 2);
```

It returned `0` after the copy.

### Reading the status

Release 2's code reads `Status` and still writes `Done`, since release 1 reads it. Responses keep `done`, now computed from the status, and add `status`, so API clients built for the earlier responses keep working:

```csharp
public record TaskDetails(int Id, string Title, bool Done, TaskItemStatus Status, DateOnly? DueOn, TaskPriority Priority, DateTime? CompletedAt, string[] Tags, int Version);

.Select(t => new TaskDetails(t.Id, t.Title, t.Status == TaskItemStatus.Done, t.Status, t.DueOn, t.Priority, t.CompletedAt, t.Tags, t.Version))
```

The new action only writes the status:

```csharp
var changed = await db.Tasks
    .Where(t => t.Id == id && t.Status == TaskItemStatus.Todo)
    .ExecuteUpdateAsync(s => s
        .SetProperty(t => t.Status, TaskItemStatus.InProgress)
        .SetProperty(t => t.Version, t => t.Version + 1), cancellationToken);
```

With both versions running:

```text
release 2 starts task 13       done=false  status=1    release 1 reads done: false
release 1 completes task 22    done=true   status=2    release 2 reads status: Done
release 2 completes task 13    done=true   status=2    release 1 reads done: true
```

A task in progress isn't done, so release 1 shows it as open, which is right for a version that doesn't know about "In progress".

### Copying in batches

On a much bigger table, the single `update` can run into the migration's command timeout, which is Npgsql's default of 30 seconds. With `Command Timeout=5` in the connection string, the copy failed after five seconds, the transaction rolled back, and the history table didn't record the migration, so the next run started over. Setting `Command Timeout=0` in the bundle's connection string, explained later, removes the limit. The alternative is a procedure that copies 10,000 rows at a time and commits after each batch: it took 3.5 seconds here and holds each row's lock only for its batch. EF Core wraps each migration in a transaction, though, and a procedure that commits fails inside one with `invalid transaction termination`, so its `migrationBuilder.Sql` call needs `suppressTransaction: true`.

## Releases 3 and 4: stop using done, then drop it

Release 3 removes `Done` from the entity and stops writing it. Generating the migration produces `DropColumn("done")`, but release 2 is still running and still writes `done`, so the column has to stay. Replace the generated `Up` with:

```csharp
protected override void Up(MigrationBuilder migrationBuilder)
{
    // The code no longer writes done, so new rows need the column's default.
    // The column itself is dropped by the next release, once no running version reads it.
    migrationBuilder.Sql("alter table tasks alter column done set default false;");
}
```

What to notice:

- Release 3 inserts tasks without `done`, and the column is `NOT NULL`. On a database built from the migrations, which has no default, release 3's `POST /tasks` answered `500` with `23502: null value in column "done" of relation "tasks" violates not-null constraint` until this migration ran, then `201`.
- The real database already has `default false` from the original script, which is the drift from the baseline section again. Writing the migration for the database the migrations build keeps both kinds of database working.

With both running, release 3 creates and completes a task: `done=false, status=2`. Release 2 reads the status, so it shows the task as done.

Release 4 changes no code. Its migration drops the column, and since the model no longer has `Done`, `dotnet ef migrations add DropTaskDone` generates an empty migration that you fill in:

```csharp
protected override void Up(MigrationBuilder migrationBuilder)
{
    migrationBuilder.DropColumn(name: "done", table: "tasks");
}

protected override void Down(MigrationBuilder migrationBuilder)
{
    migrationBuilder.AddColumn<bool>(name: "done", table: "tasks", type: "boolean", nullable: false, defaultValue: false);
}
```

Applied while release 3 runs, nothing changes for it: `GET 200`, `start 204`, `create 201`. But if release 2 were still running, its reads would keep working and completing a task would answer `500` with `42703: column "done" of relation "tasks" does not exist`, because release 2 still writes `done`. That's what the one rule protects: release 4's migration waits until release 3 has fully replaced release 2.

`Down` puts the column back but not the data. Reverting release 4 left all 799,520 done tasks with `done=false`. A down migration restores the schema's shape, so the only safe way back from a contract step is forward.

Four releases is the plainest version, not the only one. A **trigger**, a function the database runs on every insert or update, can keep `done` and `status` in sync, which Scott Ambler's catalog of database refactorings describes as using "a trigger to copy data from one column to the other during the transition period". The trigger removes the need for the application to write both columns, but it's PL/pgSQL code that looks different on SQL Server and MySQL. And release 4 needs no code, so its migration can ship with whatever feature release comes next.

## Running a migration against the live app

Each release's migration has to run once, after the previous release has rolled out and before the new one starts. That's a step in the deployment pipeline, and it needs something to run.

### A bundle per release

A **migration bundle** is an executable that applies the pending migrations, built from the release's commit:

```bash
dotnet ef migrations bundle --project TaskBoard -o efbundle
./efbundle --connection "Host=db;Username=…;Database=taskboard;Options=-c lock_timeout=2s"
```

EF Core's documentation recommends it: "For automated deployment, use a migration bundle. … Use a SQL script instead when the SQL must be reviewed, modified, archived, or handed to a DBA before it is applied."

What to notice:

- The bundle is 35 MB and needs the .NET runtime on the machine that runs it.
- It starts the app's host to create the `DbContext`, so it needs the app's `appsettings.json` in its working directory even with `--connection`. Without it, it failed with `Unable to create a 'DbContext' of type 'TaskBoardDb'. The exception 'Value cannot be null. (Parameter 'Host')' was thrown`.
- The `lock_timeout` option is explained below.

The other options:

- `dotnet ef migrations script --idempotent` writes one SQL file that checks the history table before each migration, for a person to review and run. It ran twice in a row without errors here, with the semicolon caveat above.
- `dotnet ef database update` in the pipeline needs the SDK and the source code there.
- `Database.Migrate()` at startup makes every instance of the app a migration runner.

### One runner

EF Core's documentation warns: "don't make every application replica run migrations from its entrypoint." EF Core 9 added a lock for this, which the documentation says "is held for the duration of the migration execution". With Npgsql 10.0.3, it's taken for each migration separately, and a runner reads the list of pending migrations only once, after it takes the lock the first time. Two bundles started a second apart against three migrations that each take two seconds:

```text
runner 1    applied SlowA, SlowB, then failed: 42P07: relation "slowc" already exists
runner 2    applied SlowC
```

The second runner got the lock between two of the first runner's migrations and applied the last one, so the first runner tried to apply it again. Started three seconds apart, both succeeded. That depends on timing, so the pipeline runs one bundle, once.

The pipeline can also stop a release that forgot a migration. `dotnet ef migrations has-pending-model-changes` exits with `1` and prints `Changes have been made to the model since the last migration. Add a new migration.` when the model differs from the snapshot, and `0` otherwise. Tests that build their database should use the migrations too; EF Core's documentation says "If you're using Migrations, don't use EnsureCreatedAsync to initialize the schema."

### When a 1 ms migration stalls the API

Release 1's migration is one `ALTER TABLE … ADD COLUMN` with a constant default, which PostgreSQL applies without rewriting the table. It takes about a millisecond. But every `ALTER TABLE` needs an `ACCESS EXCLUSIVE` lock on the table first, the one lock that conflicts with plain reads, and PostgreSQL grants locks in the order they're requested.

So the order of events matters:

1. A transaction reads from `tasks` and stays open for eight seconds. It could be a report, a slow request, or someone's `psql` session.
2. One second later, the migration's `ALTER TABLE` asks for its lock and waits for that transaction.
3. One second after that, the app receives two ordinary `GET /tasks/{id}` requests. Their `SELECT`s queue behind the waiting `ALTER`.

```text
GET /tasks/1 answered 200 after 6.03s
GET /tasks/2 answered 200 after 6.03s
```

`pg_stat_activity` showed the `ALTER` and both `SELECT`s waiting on `Lock:relation`. Every request that touches `tasks` waits until the long transaction ends and the `ALTER` finishes.

**`lock_timeout`** limits how long a statement waits for a lock. With `set lock_timeout = '2s'` before the `ALTER`, the `ALTER` gave up with `canceling statement due to lock timeout`, and the reads answered after 1.00 s instead of 6.03 s. For a bundle, `Options=-c lock_timeout=2s` in the connection string sets it for every statement. Against the same open transaction, the bundle exited with `1` after 2.7 s and `55P03`, the history table unchanged, and a rerun after the transaction ended applied the migration. A failed migration that can simply be retried is better than an API that stops answering.

How long each kind of change holds its lock on the million-task table:

| Change | Lock | Time on 1,000,000 rows |
|---|---|---|
| Add a column with a constant default | `ACCESS EXCLUSIVE` | about 2 ms |
| Rename or drop a column | `ACCESS EXCLUSIVE` | under 1 ms |
| Add a column with a volatile default such as `clock_timestamp()` | `ACCESS EXCLUSIVE`, rewrites the table | 2.9 to 3.9 s |
| Change a column from `integer` to `bigint` | `ACCESS EXCLUSIVE`, rewrites the table | 3.4 to 4.0 s |
| `SET NOT NULL` | `ACCESS EXCLUSIVE`, reads every row | 0.7 to 0.9 s |
| Add a foreign key | `SHARE ROW EXCLUSIVE`, blocks writes | 0.1 to 0.5 s |
| Add it `NOT VALID`, then `VALIDATE CONSTRAINT` | `VALIDATE` takes `SHARE UPDATE EXCLUSIVE`, which allows reads and writes | under 1 ms, then 0.1 to 0.6 s |
| `CREATE INDEX` | `SHARE`, blocks writes | 0.2 to 0.8 s |
| `CREATE INDEX CONCURRENTLY` | allows reads and writes | 0.4 to 1.4 s, can't run inside a transaction |

What to notice:

- A change that rewrites the table blocks every request for as long as the rewrite takes, on top of the lock queue.
- `NOT VALID` adds a constraint without checking existing rows, and `VALIDATE CONSTRAINT` checks them later under a lock that doesn't block the app.
- EF Core runs each migration in a transaction, so a concurrent index needs special handling. Npgsql's `IsCreatedConcurrently()` runs it outside the transaction, but an idempotent script failed with `CREATE INDEX CONCURRENTLY cannot be executed from a function`.

Other databases differ in ways that matter here:

- **SQL Server** can roll back DDL inside a transaction, like PostgreSQL. Its `ALTER TABLE` documentation states the same queueing problem: "the Sch-M lock blocks all other transactions that wait behind this lock when accessing the same table". `SET LOCK_TIMEOUT` defaults to `-1`, which "indicates no time-out period (that is, wait forever)", and online index operations aren't available in every edition.
- **MySQL** DDL statements "implicitly end any transaction active in the current session, as if you had done a COMMIT", so a migration with several statements that fails halfway stays half applied. Its `lock_wait_timeout` for metadata locks defaults to 31,536,000 seconds, one year. For EF Core 10, Oracle's `MySql.EntityFrameworkCore` has a release, while Pomelo's latest is 9.0.0.

## Without EF Core migrations

Some teams keep their schema in SQL scripts and generate their entity classes from the database with `dotnet ef dbcontext scaffold`, often called database-first. The four releases work the same way; only the tools change.

### SQL scripts with a runner

DbUp is a library that runs the SQL scripts in a folder in name order and records each one in a journal table, `schemaversions`, so it only runs new ones. A small console app runs it in the pipeline:

```csharp
var upgrader = DeployChanges.To
    .PostgresqlDatabase(connectionString)
    .WithScriptsFromFileSystem(scriptsFolder)
    .WithTransactionPerScript()
    .LogToConsole()
    .Build();

var result = upgrader.PerformUpgrade();
```

The scripts that were already run by hand have to be recorded without running them, which `upgrader.MarkAsExecuted()` does once. After that, each release adds its script:

```sql
-- 004-add-task-status.sql
set local lock_timeout = '2s';
alter table tasks add column status integer not null default 0; -- 0 = Todo, 1 = InProgress, 2 = Done
```

```sql
-- 005-copy-done-into-status.sql
update tasks
set status = case when done then 2 else 0 end, version = version + 1
where status <> case when done then 2 else 0 end;
```

```sql
-- 007-drop-done.sql
set local lock_timeout = '2s';
alter table tasks drop column done;
```

What to notice:

- Release 3 needs no script here: the real table already has `default false` on `done`.
- `set local` applies to the script's transaction only. Against an open transaction, script 004 failed after 2.8 s with `55P03`, and DbUp didn't record it.
- Running the release 4 folder a second time printed `No new scripts need to be executed`.

### Scaffolded entity classes

Scaffolding regenerates the entity classes from the tables. During release 3, `done` still exists, so re-scaffolding puts `public bool Done { get; set; }` back into the generated `Task` class, and EF Core selects and writes the column again. Once release 4 drops it, that code fails like the current version did in the opening.

The scaffolded context calls a partial method, `OnModelCreatingPartial`, that you can implement in a file of your own, which scaffolding doesn't overwrite:

```csharp
public partial class ScaffoldedDb
{
    partial void OnModelCreatingPartial(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Task>().Ignore(t => t.Done);
    }
}
```

The query for one task before and after, both from the database during release 2:

```text
SELECT t.id, t.assignee_id, t.completed_at, t.created_at, t.done, t.due_on, t.priority, t.status, t.tags, t.title, t.version
SELECT t.id, t.assignee_id, t.completed_at, t.created_at, t.due_on, t.priority, t.status, t.tags, t.title, t.version
```

Scaffolding again with `--force` brought the `Done` property back into `Task`, and the query still left out `done`.

## Back to the "In progress" column

So why did one correct migration break the running app and lose the data? Because the migration ran while the current version was still serving requests, and that version still read `done`. And because EF Core saw a property removed and another added, it generated a drop and an add, so nothing carried the old values over.

Spread over four releases, the same change never leaves a running version without the columns it uses:

| Release | Migration | Old version still running | Works because |
|---|---|---|---|
| 1 | add `status` | the current version | it ignores the new column |
| 2 | copy `done` into `status` | release 1 | it reads `done`, which is untouched |
| 3 | give `done` a default | release 2 | it reads `status` and still writes `done` |
| 4 | drop `done` | release 3 | it never uses `done` |

Each migration runs once, from one pipeline step, after the previous release has fully rolled out, with a `lock_timeout` so that waiting for a lock fails the migration instead of stalling the API.

## Check your understanding

1. **Why did dropping `done` break the current version, when the new code didn't need the column?** The migration runs before the new version starts, and the current version keeps serving requests until it's replaced. It still selects `done`, so every query fails with `42703`.
2. **Why does release 2, not release 1, copy `done` into `status`?** While the version before release 1 runs, it changes `done` without touching `status`, so a copy made then would go stale. Once release 1 has fully rolled out, every running instance writes both columns, and the copy stays correct.
3. **Release 1's `ALTER TABLE` takes a millisecond, yet API reads waited six seconds. What happened, and what prevents it?** The `ALTER` needs an `ACCESS EXCLUSIVE` lock and waited behind a long-running transaction, and the reads queued behind the `ALTER`. A `lock_timeout` makes the `ALTER` give up instead, so the reads go ahead and the migration can be retried.
4. **Why can't release 3 drop `done`, even though its code no longer uses it?** Release 2 is still running while release 3's migration runs, and release 2 writes `done`. The drop waits for release 4, after release 3 has replaced release 2.

## Sources and further reading

- EF Core, [Migrations overview](https://learn.microsoft.com/en-us/ef/core/managing-schemas/migrations/), [Managing migrations](https://learn.microsoft.com/en-us/ef/core/managing-schemas/migrations/managing), and [Applying migrations](https://learn.microsoft.com/en-us/ef/core/managing-schemas/migrations/applying), including bundles and the migration lock.
- EF Core, [Create and drop APIs](https://learn.microsoft.com/en-us/ef/core/managing-schemas/ensure-created) and [Reverse engineering](https://learn.microsoft.com/en-us/ef/core/managing-schemas/scaffolding/).
- Danilo Sato, [ParallelChange](https://martinfowler.com/bliki/ParallelChange.html); Pramod Sadalage and Martin Fowler, [Evolutionary Database Design](https://martinfowler.com/articles/evodb.html); Scott Ambler, [Rename Column](https://agiledata.org/essays/renameColumn.html).
- PostgreSQL 18, [ALTER TABLE](https://www.postgresql.org/docs/18/sql-altertable.html), [Explicit locking](https://www.postgresql.org/docs/18/explicit-locking.html), [CREATE INDEX](https://www.postgresql.org/docs/18/sql-createindex.html), and [`lock_timeout`](https://www.postgresql.org/docs/18/runtime-config-client.html).
- SQL Server, [ALTER TABLE](https://learn.microsoft.com/en-us/sql/t-sql/statements/alter-table-transact-sql) and [SET LOCK_TIMEOUT](https://learn.microsoft.com/en-us/sql/t-sql/statements/set-lock-timeout-transact-sql).
- MySQL 8.4, [Statements that cause an implicit commit](https://dev.mysql.com/doc/refman/8.4/en/implicit-commit.html) and [`lock_wait_timeout`](https://dev.mysql.com/doc/refman/8.4/en/server-system-variables.html).
- [DbUp documentation](https://dbup.readthedocs.io/en/latest/).
