---
title: "Valid token, wrong task: checking who may change a task in ASP.NET Core"
description: "Why a role on an endpoint can't decide whether a user may change a particular task, how to find the caller's own row from a Keycloak token, and why the per-task check belongs in the UPDATE that changes the task, with the race that slips past a check made first and two EF Core traps in the fix."
pubDate: "2026-10-20"
tags:
  - aspnet-core
  - dotnet
  - ef-core
  - postgresql
audience:
  - backend
---

Grace has no role on the task board. She can sign in, read tasks, and work on the tasks assigned to her. Ada's task "Write the release notes" isn't one of them, but this request works:

```text
POST /tasks/1/complete    Authorization: Bearer <Grace's token>
204 No Content
```

Task 1 is now done, and Ada gets an email: "Completed: Write the release notes". The API checked Grace's token, so it knew exactly who sent the request. So why did it let her?

You'll need [the token article](/dump/blog/what-an-api-must-check-in-a-token/) for how the API checks a Keycloak token and reads its roles, [EF Core behind the scenes](/dump/blog/ef-core-behind-the-scenes/) for `ExecuteUpdate`, and [the transactions article](/dump/blog/transactions-and-concurrent-edits/) for row locks and what PostgreSQL's Read Committed level lets a statement see.

## Contents

1. [Set up the example](#set-up-the-example)
2. [Who may do what on the task board](#who-may-do-what-on-the-task-board)
3. [What a policy can see](#what-a-policy-can-see)
4. [Which users row is the caller](#which-users-row-is-the-caller)
5. [Checking after loading the task](#checking-after-loading-the-task)
6. [Checking in the statement that changes the task](#checking-in-the-statement-that-changes-the-task)
7. [Missing, not yours, or already done](#missing-not-yours-or-already-done)
8. [Testing the rules](#testing-the-rules)
9. [Back to Grace's request](#back-to-graces-request)

## Set up the example

The examples use the .NET 10 SDK (ASP.NET Core 10.0.13), EF Core 10.0.4 with Npgsql 10.0.3, Keycloak 26.8.1 in a container run with Podman 6.1.1, and PostgreSQL 18.6, with the API in the `Production` environment.

The code starts from the task board at the end of [the token article](/dump/blog/what-an-api-must-check-in-a-token/): JwtBearer checks Keycloak's tokens, realm roles are mapped from `realm_access`, the `/tasks` group requires a signed-in user, and `POST /tasks` requires the `editor` policy. [The layered and sliced article](/dump/blog/layered-and-sliced-code-organization/) and [the endpoints article](/dump/blog/resource-style-and-action-style-endpoints/) compare its layout and endpoint style with the alternatives. Completing a task still mails the assignee through the mail service from [the idempotency keys article](/dump/blog/idempotency-keys-and-repeated-requests/).

Two setup changes. In `keycloak/taskboard-realm.json`, Ada and Grace get fixed IDs, so that the SQL later in the article can refer to them:

```json
"id": "8a0e6f0e-4b8e-4c55-9f4a-2d3c1b7a0001", "username": "ada", …
"id": "8a0e6f0e-4b8e-4c55-9f4a-2d3c1b7a0002", "username": "grace", …
```

Keycloak uses that ID as the user's `sub` claim. The import skips a realm that already exists, so start a new container after the change. And the database gets rows for Ada and Grace, with one task each:

```sql
INSERT INTO users (name, email) VALUES ('Ada', 'ada@example.com'), ('Grace', 'grace@example.com') RETURNING id;
UPDATE tasks SET title = 'Write the release notes', status = 0, assignee_id = 1001 WHERE id = 1;
UPDATE tasks SET title = 'Check the search filters', status = 0, assignee_id = 1002 WHERE id = 2;
```

The insert returns `1001` and `1002`, after the 1,000 generated users, and status `0` is "To do".

Restricting which tasks someone may read, endpoints that assign tasks, creating users when they first sign in, Keycloak's own authorization services and external policy engines, OAuth scopes as permissions, audit logs, and runnable SQL Server or MySQL examples are outside this article's scope.

## Who may do what on the task board

Before fixing anything, write the rules down:

| Action | Who may do it |
|---|---|
| Read and search tasks | anyone signed in |
| Create or edit a task (`POST /tasks`, `PUT`, `PATCH`) | editors |
| Start or complete a task | the task's assignee, or any editor |

So an unassigned task can only be started or completed by an editor.

The rows answer two different kinds of question. "May this user edit tasks?" depends only on who's calling, and the token answers it: Ada's token carries the `editor` role and Grace's doesn't. "May this user complete task 1?" depends on the task too: which one it is and whom it's assigned to. The token can't answer that, because it says nothing about tasks.

OWASP's list of API security risks has a name for missing each kind. Reaching an operation your role shouldn't is "Broken Function Level Authorization" (API5). Acting on an object that isn't yours is "Broken Object Level Authorization" (API1), first on the list. OWASP's authorization cheat sheet puts the second one this way: "Just because a user has access to an object of a particular type does not mean they should have access to every object of that particular type."

Grace completing Ada's task is the second kind. But the task board has a gap of the first kind too. The edit endpoints have no policy, so Grace can reopen Ada's task:

```text
PUT /tasks/1    If-Match: "2"    {"title":"Write the release notes","done":false}    (Grace)
204 No Content
```

That one needs only the role, so it takes one line per endpoint in `EditTask.cs`:

```csharp
tasks.MapPut("/{id:int}", Replace).RequireAuthorization("editor");
tasks.MapPatch("/{id:int}", Patch).RequireAuthorization("editor");
```

Grace now gets `403` for both, and Ada still gets `204`.

ASP.NET Core also has a setting aimed at forgotten endpoints, the **fallback policy**. Microsoft's policy documentation explains when it applies: "The fallback policy, not the default policy, applies to endpoints that don't specify authorization metadata." It wouldn't have caught this gap, though. `PUT` inherits the group's `RequireAuthorization()`, so it already required a signed-in user, just not an editor. And it covers everything that has no metadata: with a fallback policy that requires a signed-in user, `/openapi/v1.json` answered `401` without a token until `MapOpenApi()` got `.AllowAnonymous()`, and an unknown path answered `401` instead of `404`. The task board keeps its `RequireAuthorization()` on the route group instead.

That leaves the start and complete rule. Can a policy express "the task's assignee"?

## What a policy can see

A **policy** is a list of requirements. Each requirement is checked by one or more **handlers**, classes that look at the request's user and decide whether the requirement is met. `RequireRole("editor")` adds one requirement, and ASP.NET Core brings the handler that checks it.

The `editor` policy on `complete` would stop Grace on Ada's task, but it stops her on her own task too:

```csharp
tasks.MapPost("/{id:int}/complete", Handle).RequireAuthorization("editor");
```

```text
Grace  POST /tasks/2/complete    403   (task 2 is Grace's)
```

The log says why: `RolesAuthorizationRequirement:User.IsInRole must be true for one of the following roles: (editor)`. The rule needs "or the assignee", and nothing in a role knows whose task this is.

A custom handler can't find out either, because of when it runs. The authorization middleware runs the endpoint's policies after routing has picked the endpoint and before the endpoint's handler runs, as [the request pipeline article](/dump/blog/aspnet-core-request-pipeline/#routing-picks-an-endpoint-and-a-later-step-runs-it) describes. At that point nothing has loaded the task. Microsoft's resource-based authorization page says the same about the `[Authorize]` attribute: "Attribute evaluation occurs before data binding and before execution of any method that loads a resource."

Besides the user, a handler receives a **resource**, the thing being accessed. For an endpoint's policy, the middleware passes the request's `HttpContext` as the resource. A handler can declare the type of resource it checks. One declared as `AuthorizationHandler<ChangeTaskRequirement, TaskAssignee>` checks a requirement named `ChangeTaskRequirement`, and ASP.NET Core calls it only when the resource is a `TaskAssignee`, a small record holding a task's assignee. In an endpoint's policy it never is. With such a handler in a policy on `complete`, Grace got `403` on her own task, the handler never ran, and nothing warned about it.

A handler can instead read the task ID from the route and load the task itself. That works for tasks that exist, but it answers `403` for a task that doesn't, because the endpoint, which would answer `404`, never runs. And since it uses `TaskBoardDb`, it has to be registered as scoped. Registered as a singleton, one handler, and so one `DbContext`, served 40 concurrent requests, and 39 of them failed with `500`; in `Development`, scope validation refused to start the app, as [the dependency injection article](/dump/blog/aspnet-core-dependency-injection/#captive-dependencies-and-scope-validation) explains.

So the per-task check belongs in the endpoint, which has the task's ID and loads its row anyway. It has to compare the task's assignee with the caller. But the task stores `assignee_id`, an ID from the `users` table, and the token carries `sub`, Keycloak's ID. Which `users` row is Grace?

## Which users row is the caller

Grace's token says `"sub": "8a0e6f0e-4b8e-4c55-9f4a-2d3c1b7a0002"`. In the `users` table she's `1002`. Nothing connects the two yet.

Other claims look like they could. The token has `email`, and `users` has an `email` column. But OpenID Connect, the protocol Keycloak issues these tokens with, rules that out: "the claimed email address for a given End-User MAY change over time. Therefore, other Claims such as email, phone_number, preferred_username, and name MUST NOT be used as unique identifiers for the End-User". In Keycloak, users can edit their own email by default. Grace changed hers to `user876@example.com` through Keycloak's account API, the one its account page uses, and her next token carried it with `"email_verified": false`. A build that matched the assignee by email then let her complete user 876's task with `204`.

A custom claim that carries the `users` ID is the other tempting shortcut. Keycloak ignores user attributes its user profile doesn't declare: setting one through the admin API answered `204` and stored nothing. Declared as editable by users, Grace set hers to `1001` and her next token said `1001`. Declared as editable by admins only, it's safe, but someone has to set it in Keycloak for every user.

OpenID Connect names the identifier that stays put: "the only guaranteed unique identifier for a given End-User is the combination of the iss Claim and the sub Claim." The task board trusts one issuer, so `sub` is enough. Store it on the user's row, in `Data/Entities.cs` and `Data/TaskBoardDb.cs`:

```csharp
public string? KeycloakId { get; set; }

modelBuilder.Entity<User>().HasIndex(u => u.KeycloakId).IsUnique();
```

`dotnet ef migrations add LinkUsersToKeycloak` turns that into:

```sql
ALTER TABLE users ADD keycloak_id text;
CREATE UNIQUE INDEX ix_users_keycloak_id ON users (keycloak_id);
```

What to notice:

- The column is `text`, not `uuid`. Keycloak's IDs look like UUIDs here, but users that a user storage provider serves without copying them into Keycloak's own database get IDs of the form `f:<provider>:<id>`.
- It allows null, because the 1,000 existing users aren't linked to anyone in Keycloak. PostgreSQL's unique index allows any number of nulls.
- The migration only adds, so the build that's still running keeps working, which is the expand step from [the schema changes article](/dump/blog/changing-the-schema-without-breaking-the-app/#expand-migrate-contract). After applying it, the previous build still answered `200` to `GET /tasks/2` and `204` to Grace's `start`. Apply it with the release's bundle before the new build starts, as that article does.

Then link Ada's and Grace's rows:

```sql
UPDATE users SET keycloak_id = '8a0e6f0e-4b8e-4c55-9f4a-2d3c1b7a0001' WHERE email = 'ada@example.com';
UPDATE users SET keycloak_id = '8a0e6f0e-4b8e-4c55-9f4a-2d3c1b7a0002' WHERE email = 'grace@example.com';
```

Matching by email is fine here: it runs once, and a person checks the result. In a real system, an admin tool links rows, or the API links a user the first time they sign in; both need the same care about which claims to trust.

So Grace is the row whose `keycloak_id` equals her token's `sub`, and task 2 is hers because its `assignee_id` is that row. Now the endpoint can check it.

## Checking after loading the task

The most direct version loads the assignee, compares, and only then changes the task. In `CompleteTask.cs`:

```csharp
public static async Task<Results<NoContent, NotFound, ForbidHttpResult>> Handle(int id, ClaimsPrincipal user, TaskBoardDb db, TimeProvider clock, IMailSender mailSender, CancellationToken cancellationToken)
{
    var task = await db.Tasks
        .Where(t => t.Id == id)
        .Select(t => new { AssigneeKeycloakId = t.Assignee!.KeycloakId })
        .SingleOrDefaultAsync(cancellationToken);
    if (task is null)
    {
        return TypedResults.NotFound();
    }

    var isAssignee = task.AssigneeKeycloakId == user.FindFirstValue("sub");
    if (!isAssignee && !user.IsInRole("editor"))
    {
        return TypedResults.Forbid();
    }

    // the UPDATE from before, then the email if it changed a row
}
```

What to notice:

- A `ClaimsPrincipal` parameter gets the request's user, the same one the policies see.
- The query reads one column, the assignee's Keycloak ID, through a join: `SELECT u.keycloak_id FROM tasks AS t LEFT JOIN users AS u ON t.assignee_id = u.id WHERE t.id = @id`. An unassigned task gives `null`.
- `TypedResults.Forbid()` asks JwtBearer to answer `403`, the same empty response a failed policy gets. Its type, `ForbidHttpResult`, joins the `Results<…>` list.
- `StartTask` gets the same check.

The answers are right:

| Request | Answer |
|---|---|
| Grace completes Ada's task 1 | `403` |
| Grace completes her own task 2 | `204` |
| Grace starts a task assigned to user 876 | `403` |
| Grace starts an unassigned task | `403` |
| Ada (editor) starts the task assigned to user 876 | `204` |
| Anyone completes task 99999999 | `404` |

### A token without sub

The comparison assumes the token has a `sub`. JwtBearer doesn't require one, and Keycloak leaves it out if a client loses its `basic` scope. `FindFirstValue("sub")` is then `null`, and in C#, `null == null` is `true`, so the comparison matches every task whose assignee has no `keycloak_id`, and every unassigned task. With `basic` removed from `taskboard-cli`, Grace's token had no `sub`, and she completed user 876's task and started an unassigned one, both with `204`.

Require the claim in the **default policy**, the one `RequireAuthorization()` without a name uses, in `Program.cs`:

```csharp
builder.Services.AddAuthorizationBuilder()
    .SetDefaultPolicy(new AuthorizationPolicyBuilder().RequireAuthenticatedUser().RequireClaim("sub").Build())
    .AddPolicy("editor", policy => policy.RequireRole("editor"));
```

Every endpoint in the `/tasks` group and `/me` now answers `403` to a token without `sub`.

### The same check through IAuthorizationService

Microsoft's resource-based authorization pages package this check as a requirement with handlers, called through `IAuthorizationService` once the endpoint has loaded the resource. Their examples use Razor components and MVC controllers; with a minimal API, it looks like this:

```csharp
public record TaskAssignee(string? KeycloakId);

public class ChangeTaskRequirement : IAuthorizationRequirement;

public class AssigneeHandler : AuthorizationHandler<ChangeTaskRequirement, TaskAssignee>
{
    protected override Task HandleRequirementAsync(AuthorizationHandlerContext context, ChangeTaskRequirement requirement, TaskAssignee assignee)
    {
        if (assignee.KeycloakId == context.User.FindFirstValue("sub"))
        {
            context.Succeed(requirement);
        }

        return Task.CompletedTask;
    }
}

public class EditorHandler : AuthorizationHandler<ChangeTaskRequirement>
{
    protected override Task HandleRequirementAsync(AuthorizationHandlerContext context, ChangeTaskRequirement requirement)
    {
        if (context.User.IsInRole("editor"))
        {
            context.Succeed(requirement);
        }

        return Task.CompletedTask;
    }
}
```

The handlers are registered in `Program.cs`:

```csharp
builder.Services.AddSingleton<IAuthorizationHandler, AssigneeHandler>();
builder.Services.AddSingleton<IAuthorizationHandler, EditorHandler>();
```

and the endpoint takes an `IAuthorizationService authorization` parameter and passes the loaded task to it:

```csharp
var task = await db.Tasks
    .Where(t => t.Id == id)
    .Select(t => new TaskAssignee(t.Assignee!.KeycloakId))
    .SingleOrDefaultAsync(cancellationToken);
// 404 if null, as before
var allowed = await authorization.AuthorizeAsync(user, task, new ChangeTaskRequirement());
if (!allowed.Succeeded)
{
    return TypedResults.Forbid();
}
```

What to notice:

- This is the `TaskAssignee` handler that never ran in an endpoint's policy. Here the resource is a `TaskAssignee`, so it runs.
- One requirement with two handlers means "either is enough": a requirement is met when any of its handlers succeeds.
- The handlers use no other services, so singletons are fine.
- Microsoft's examples compare `context.User.Identity?.Name` with the document's author. With Keycloak's tokens, the name is `preferred_username`, which OpenID Connect rules out as an identifier for the same reason as email.

The answers match the table above. The difference is where the rule lives: in named classes that several endpoints can share, instead of an `if` in each endpoint.

Both versions answer correctly when requests arrive one at a time. But the check and the change are two separate statements. What if the task changes between them?

## Checking in the statement that changes the task

Say an editor reassigns task 2 from Grace to user 876 at the moment Grace completes it. The task board has no endpoint for assigning tasks, so `psql` plays the editor. Holding its transaction open makes the timing reproducible:

| psql (the editor) | Grace |
|---|---|
| `begin;` | |
| `update tasks set assignee_id = 876, version = version + 1 where id = 2;` | |
| | `POST /tasks/2/complete` … waits |
| `commit;` | … `204 No Content` |

Task 2 ended up done and assigned to user 876, and the email went to `user876@example.com`. Step by step:

1. Grace's `SELECT` reads the last committed version of the row, where she's still the assignee, so the check passes.
2. Her `UPDATE` reaches the row and waits, because the editor's uncommitted update holds the row's lock.
3. When the editor commits, PostgreSQL takes the new version of the row and rechecks the `UPDATE`'s `WHERE`. PostgreSQL's documentation describes it: "The search condition of the command (the WHERE clause) is re-evaluated to see if the updated version of the row still matches the search condition."
4. That `WHERE` is `id = 2 AND status <> 2`. It still matches, so the task is completed, and the email goes to whoever is the assignee now.

The `IAuthorizationService` version did the same: `204`, and the email to user 876. Without `psql` holding the lock, the window is the few milliseconds between the two statements, which makes the race rare, not impossible.

Step 3 also shows the fix. PostgreSQL rechecks the `UPDATE`'s own `WHERE` against the row as it is when the update applies, so put the rule there. It's the same idea as [letting the database do the arithmetic](/dump/blog/transactions-and-concurrent-edits/#let-the-database-do-the-arithmetic) in the transactions article: one statement that both decides and writes. For that, the comparison has to use a column of the task row itself, `assignee_id`, so the endpoint first looks up the caller's own `users.id`:

```csharp
var keycloakId = user.FindFirstValue("sub");
var callerId = await db.Users
    .Where(u => u.KeycloakId == keycloakId)
    .Select(u => (int?)u.Id)
    .SingleOrDefaultAsync(cancellationToken);
var isEditor = user.IsInRole("editor");

var now = clock.GetUtcNow().UtcDateTime;
var changed = await db.Tasks
    .Where(t => t.Id == id && t.Status != TaskItemStatus.Done)
    .Where(t => isEditor || (callerId != null && t.AssigneeId == callerId))
    .ExecuteUpdateAsync(s => s
        .SetProperty(t => t.Status, TaskItemStatus.Done)
        .SetProperty(t => t.CompletedAt, now)
        .SetProperty(t => t.Version, t => t.Version + 1), cancellationToken);
```

For Grace, EF Core sends:

```sql
UPDATE tasks AS t
SET status = @p, completed_at = @p3, version = t.version + 1
WHERE t.id = @id AND t.status <> 2 AND t.assignee_id = @callerId
```

and for Ada, an editor, the same statement without the last condition. `isEditor` and `callerId` are C# variables, so EF Core works out `isEditor || (callerId != null && …)` before sending and keeps only the part that depends on the row. `StartTask` gets the same lookup and condition.

The same race now gives Grace `403`. Task 2 stays "To do", assigned to user 876, and no email goes out. When PostgreSQL rechecked the `WHERE` against the reassigned row, `assignee_id = 1002` no longer matched, so the `UPDATE` changed nothing.

### Why callerId != null

The guard looks redundant, but it isn't. A user who can sign in to Keycloak but has no `users` row gets `callerId == null`. In C#, `t.AssigneeId == callerId` is then true for an unassigned task, and EF Core keeps C#'s meaning in SQL. It doesn't send `assignee_id = NULL`, which [the SQL article](/dump/blog/sql-indexes-and-parameters/#tables-rows-and-the-first-queries) showed is never true. It sends `t.assignee_id IS NULL`. Without the guard, a Keycloak user created without a `users` row started an unassigned task with `204`, and the log showed `WHERE t.id = $2 AND t.status = 0 AND t.assignee_id IS NULL`. There are 99,825 unassigned tasks. With the guard, that user gets `403`.

### Why not compare through the navigation

Comparing through the navigation property, `t.Assignee!.KeycloakId == keycloakId`, would skip the lookup. But the condition then needs the `users` table, and EF Core with Npgsql can't put that join in the `UPDATE` directly, so it sends:

```sql
UPDATE tasks AS t0
SET status = @p, completed_at = @p3, version = s.version + 1
FROM (
    SELECT t.id, t.version
    FROM tasks AS t
    LEFT JOIN users AS u ON t.assignee_id = u.id
    WHERE t.id = @id AND t.status <> 2 AND u.keycloak_id = @keycloakId
) AS s
WHERE t0.id = s.id
```

The check now sits in a subquery that has already run. After the lock is released, PostgreSQL rechecks the outer `WHERE`, `t0.id = s.id`, against the new version of the task row, but the subquery's row `s` is a copy taken before the reassignment. In the race, Grace got `204`, the task was completed under user 876, and `version` stayed at `3`, because `s.version + 1` used the old copy's version. So the rule has to compare a column of the row being updated, and anything else has to be looked up first.

Endpoints that load the whole task anyway have another option. `PUT` saves with the version it loaded, so in the same race, Ada's edit got `412` instead of overwriting the reassignment, as in [the transactions article](/dump/blog/transactions-and-concurrent-edits/#optimistic-concurrency-with-ef-core).

## Missing, not yours, or already done

When the `UPDATE` changes no row, the endpoint still has to answer, and zero rows can mean three things: the task doesn't exist, it isn't the caller's, or it's already done. One more query tells them apart:

```csharp
if (changed == 1)
{
    await CompletionMail.SendAsync(id, db, mailSender, cancellationToken);
    return TypedResults.NoContent();
}

var task = await db.Tasks
    .Where(t => t.Id == id)
    .Select(t => new { t.AssigneeId })
    .SingleOrDefaultAsync(cancellationToken);
if (task is null)
{
    return TypedResults.NotFound();
}

var isAssignee = callerId != null && task.AssigneeId == callerId;
if (!isEditor && !isAssignee)
{
    return TypedResults.Forbid();
}

return TypedResults.NoContent();
```

What to notice:

- A missing task gets `404`, a task that isn't the caller's gets `403`, and a done task that the caller may complete gets `204`, as before: completing it again changes nothing and isn't an error.
- The follow-up query runs after the `UPDATE`, so the task could change between them too. That's harmless: the `UPDATE` already decided whether anything changed, and the follow-up only picks the status code.

Should Grace get `403` or `404` for Ada's task? RFC 9110, which defines HTTP's status codes, allows either: "An origin server that wishes to "hide" the current existence of a forbidden target resource MAY instead respond with a status code of 404 (Not Found)." On the task board, Grace can `GET /tasks/1` and see that it's Ada's, so `404` would hide nothing. `404` is the right choice when reads are restricted too, so that a `403` doesn't confirm that a task exists.

`ForbidHttpResult` adds nothing to the OpenAPI document, so `start` and `complete` still list only `204` and `404`. A transformer like the one in [the OpenAPI article](/dump/blog/openapi-spec-that-matches-the-code/#one-transformer-for-responses-that-follow-from-metadata) can add `403`.

## Testing the rules

The tests from [the token article](/dump/blog/what-an-api-must-check-in-a-token/#testing-protected-endpoints) sign their own tokens. To act as a linked user, a test token needs that user's `sub`, so `TestTokens.For` gets one more parameter:

```csharp
public static string For(string username, string[] roles, string audience = "taskboard-api", string? keycloakId = null)
{
    var claims = new Dictionary<string, object>
    {
        ["sub"] = keycloakId ?? Guid.NewGuid().ToString(),
        ["preferred_username"] = username,
    };
    // the rest as before
}
```

Each test adds its own users with a fresh `KeycloakId` and a task, then sends a request as one of them:

```csharp
[Fact]
public async Task Someone_else_cannot_complete_the_task()
{
    var ada = await AddUser("ada");
    var grace = await AddUser("grace");
    var task = await AddTask(ada);

    var response = await ClientFor(grace).PostAsync($"/tasks/{task.Id}/complete", null, TestContext.Current.CancellationToken);

    Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    Assert.Equal(TaskItemStatus.Todo, await StatusOf(task));
}
```

<details>
<summary>The complete <code>TaskRulesTests.cs</code></summary>

```csharp
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using Microsoft.EntityFrameworkCore;

public class TaskRulesTests(TaskBoardApp app, TestDatabase database) : IClassFixture<TestDatabase>, IClassFixture<TaskBoardApp>
{
    async Task<User> AddUser(string name)
    {
        await using var db = database.CreateContext();
        var user = new User { Name = name, Email = $"{name}-{Guid.NewGuid()}@example.com", Active = true, KeycloakId = Guid.NewGuid().ToString() };
        db.Users.Add(user);
        await db.SaveChangesAsync(TestContext.Current.CancellationToken);
        return user;
    }

    async Task<TaskItem> AddTask(User? assignee)
    {
        await using var db = database.CreateContext();
        var task = new TaskItem { Title = "Write the release notes", AssigneeId = assignee?.Id, Version = 1 };
        db.Tasks.Add(task);
        await db.SaveChangesAsync(TestContext.Current.CancellationToken);
        return task;
    }

    HttpClient ClientFor(User user, params string[] roles)
    {
        var client = app.CreateClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", TestTokens.For(user.Name, roles, keycloakId: user.KeycloakId));
        return client;
    }

    async Task<TaskItemStatus> StatusOf(TaskItem task)
    {
        await using var db = database.CreateContext();
        return await db.Tasks.Where(t => t.Id == task.Id).Select(t => t.Status).SingleAsync(TestContext.Current.CancellationToken);
    }

    [Fact]
    public async Task The_assignee_can_complete_their_task()
    {
        var grace = await AddUser("grace");
        var task = await AddTask(grace);

        var response = await ClientFor(grace).PostAsync($"/tasks/{task.Id}/complete", null, TestContext.Current.CancellationToken);

        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);
        Assert.Equal(TaskItemStatus.Done, await StatusOf(task));
    }

    [Fact]
    public async Task Someone_else_cannot_complete_the_task()
    {
        var ada = await AddUser("ada");
        var grace = await AddUser("grace");
        var task = await AddTask(ada);

        var response = await ClientFor(grace).PostAsync($"/tasks/{task.Id}/complete", null, TestContext.Current.CancellationToken);

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
        Assert.Equal(TaskItemStatus.Todo, await StatusOf(task));
    }

    [Fact]
    public async Task An_editor_can_complete_any_task()
    {
        var ada = await AddUser("ada");
        var grace = await AddUser("grace");
        var task = await AddTask(grace);

        var response = await ClientFor(ada, "editor").PostAsync($"/tasks/{task.Id}/complete", null, TestContext.Current.CancellationToken);

        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);
    }

    [Fact]
    public async Task A_missing_task_is_not_found()
    {
        var grace = await AddUser("grace");

        var response = await ClientFor(grace).PostAsync("/tasks/999999/complete", null, TestContext.Current.CancellationToken);

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task A_caller_without_a_users_row_cannot_start_an_unassigned_task()
    {
        var task = await AddTask(null);
        var client = app.CreateClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", TestTokens.For("hedy", []));

        var response = await client.PostAsync($"/tasks/{task.Id}/start", null, TestContext.Current.CancellationToken);

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
        Assert.Equal(TaskItemStatus.Todo, await StatusOf(task));
    }

    [Fact]
    public async Task Only_editors_can_edit_a_task()
    {
        var grace = await AddUser("grace");
        var task = await AddTask(grace);
        var request = new HttpRequestMessage(HttpMethod.Put, $"/tasks/{task.Id}") { Content = JsonContent.Create(new { title = "Renamed", done = false }) };
        request.Headers.IfMatch.Add(new EntityTagHeaderValue("\"1\""));

        var response = await ClientFor(grace).SendAsync(request, TestContext.Current.CancellationToken);

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }
}
```

</details>

The six tests cover the assignee, someone else, an editor, a missing task, a caller whose token has a `sub` but who has no `users` row, and `PUT` without the role. The older `CompleteTaskTests` call `CompleteTask.Handle` directly, so they now pass a signed-in editor:

```csharp
readonly ClaimsPrincipal editor = new(new ClaimsIdentity([new Claim("sub", Guid.NewGuid().ToString()), new Claim("roles", "editor")], "Test", "preferred_username", "roles"));
```

All 16 tests passed. Without the `callerId != null` guard, exactly one failed: the caller without a row. But the load-then-check version from earlier passed all 16 too. Tests that send one request at a time can't produce the race; that takes two sessions, like the `psql` run above.

## Back to Grace's request

Grace's request got `204` because the API asked who was calling and never asked whose task it was. A role on the endpoint can only say what kind of thing a user may do. Whether Grace may complete task 1 depends on that task's row, and the row can change while her request runs. So the endpoint finds Grace's own `users` row from her token's `sub`, and compares it with the task in the same `UPDATE` that changes the task.

The same request now gets `403`. Task 1 stays "To do", its version doesn't change, and Ada gets no email.

## Check your understanding

1. **Why can't the `editor` policy on `complete` express "the assignee or any editor"?** The policy runs before the endpoint loads anything, with the request as its resource, and a role says nothing about whom a task is assigned to. Requiring `editor` there also locked Grace out of her own task.
2. **Why does the task board store Keycloak's `sub` instead of matching users by email?** Email can change, and in Keycloak users can change their own. Grace changed hers to another user's address and completed that user's task. `sub`, together with the issuer, is the identifier OpenID Connect guarantees.
3. **The load-then-check version answered every request correctly in the table. What goes wrong, and why does moving the rule into the `UPDATE` fix it?** An editor can reassign the task between the check and the `UPDATE`. PostgreSQL rechecks only the `UPDATE`'s `WHERE` against the new version of the row, so the rule has to be in that `WHERE`, comparing a column of the task row itself.
4. **When would `404` be a better answer than `403` for someone else's task?** When the caller can't read the task either. Then `403` would confirm that the task exists, and RFC 9110 allows `404` to hide that.

## Sources and further reading

- Microsoft, [Resource-based authorization](https://learn.microsoft.com/en-us/aspnet/core/security/authorization/resource-based?view=aspnetcore-10.0), [Policy-based authorization](https://learn.microsoft.com/en-us/aspnet/core/security/authorization/policies?view=aspnetcore-10.0), and [Dependency injection in requirement handlers](https://learn.microsoft.com/en-us/aspnet/core/security/authorization/dependencyinjection?view=aspnetcore-10.0).
- ASP.NET Core source, [AuthorizationMiddleware.cs at v10.0.13](https://github.com/dotnet/aspnetcore/blob/v10.0.13/src/Security/Authorization/Policy/src/AuthorizationMiddleware.cs).
- OWASP, [API1:2023 Broken Object Level Authorization](https://owasp.org/API-Security/editions/2023/en/0xa1-broken-object-level-authorization/), [API5:2023 Broken Function Level Authorization](https://owasp.org/API-Security/editions/2023/en/0xa5-broken-function-level-authorization/), and the [Authorization Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Authorization_Cheat_Sheet.html).
- [OpenID Connect Core 1.0, section 5.7, Claim Stability and Uniqueness](https://openid.net/specs/openid-connect-core-1_0.html#ClaimStability).
- Keycloak, [Server Administration Guide: user profile](https://www.keycloak.org/docs/latest/server_admin/index.html#user-profile).
- EF Core, [ExecuteUpdate and ExecuteDelete](https://learn.microsoft.com/en-us/ef/core/saving/execute-insert-update-delete) and [Comparisons with null values in queries](https://learn.microsoft.com/en-us/ef/core/querying/null-comparisons).
- PostgreSQL 18, [Read Committed isolation level](https://www.postgresql.org/docs/18/transaction-iso.html#XACT-READ-COMMITTED).
- RFC 9110, [section 15.5.4, 403 Forbidden](https://www.rfc-editor.org/rfc/rfc9110#section-15.5.4).
