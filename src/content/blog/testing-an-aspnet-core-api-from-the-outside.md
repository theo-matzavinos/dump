---
title: "Two tasks, one key, every test green: testing an ASP.NET Core API from the outside"
description: "Why a test that called the handler directly missed a broken Idempotency-Key header, what WebApplicationFactory runs when a test sends a real request, how Testcontainers gives each test run its own PostgreSQL built by the production migrations, and how tests sharing that database stay out of each other's way."
pubDate: "2026-10-21T12:00:00Z"
tags:
  - aspnet-core
  - dotnet
  - ef-core
  - postgresql
  - testing
  - docker
audience:
  - backend
---

`CreateTask` reads the client's idempotency key with this parameter:

```csharp
[FromHeader(Name = "Idempotency-Key"), StringLength(100)] string? idempotencyKey,
```

A cleanup shortens it. `[FromHeader]` already says the value comes from a header, and the name looks like it only repeats the parameter's:

```csharp
[FromHeader, StringLength(100)] string? idempotencyKey,
```

All 18 tests pass, including one named `Repeating_a_request_with_the_same_key_returns_the_first_task`. Then Ada's client sends the same request twice with the same key, as it does when a response gets lost:

```text
POST /tasks    Idempotency-Key: 6f1c2a9e-release-notes    201 Created    Location: /tasks/1
POST /tasks    Idempotency-Key: 6f1c2a9e-release-notes    201 Created    Location: /tasks/2
```

Two tasks, and no row in `idempotency_keys`. Without a name, `[FromHeader]` looks for a header named after the parameter, `idempotencyKey`, so the API never saw Ada's key. Two requests that sent an `idempotencyKey` header instead got the same task back.

So the test written for exactly this case passed while the case failed. Why, and what kind of test would have failed?

You'll need [the idempotency keys article](/dump/blog/idempotency-keys-and-repeated-requests/) for the key and the `idempotency_keys` table, [the token article](/dump/blog/what-an-api-must-check-in-a-token/) for `TaskBoardApp` and the test tokens, [the configuration article](/dump/blog/configuration-and-secrets/) for configuration sources, [the schema changes article](/dump/blog/changing-the-schema-without-breaking-the-app/) for migrations, [the background work article](/dump/blog/background-work-in-aspnet-core/) for `pending_emails` and its worker, and [the Docker article](/dump/blog/docker-behind-the-scenes/) for images and containers.

## Contents

1. [Set up the example](#set-up-the-example)
2. [What the handler tests skip](#what-the-handler-tests-skip)
3. [Sending the request instead](#sending-the-request-instead)
4. [What WebApplicationFactory runs](#what-webapplicationfactory-runs)
5. [A database the test run starts](#a-database-the-test-run-starts)
6. [Building the schema with migrations](#building-the-schema-with-migrations)
7. [Keeping tests out of each other's way](#keeping-tests-out-of-each-others-way)
8. [Back to the key](#back-to-the-key)

## Set up the example

The examples use the .NET 10 SDK (ASP.NET Core 10.0.13), EF Core 10.0.4, Npgsql 10.0.3, xUnit v3 3.2.2, Microsoft.AspNetCore.Mvc.Testing 10.0.13, Testcontainers.PostgreSql 4.16.0, and PostgreSQL 18.6. From the database section on, the tests need Docker running, and the one new package is Testcontainers:

```bash
dotnet add TaskBoard.Tests package Testcontainers.PostgreSql --version 4.16.0
```

The code starts from the task board at the end of [the background work article](/dump/blog/background-work-in-aspnet-core/), with its 18 tests. [The layered and sliced article](/dump/blog/layered-and-sliced-code-organization/) and [the endpoints article](/dump/blog/resource-style-and-action-style-endpoints/) compare its layout and endpoint style with the alternatives. The tests run with:

```bash
dotnet test
```

Browser end-to-end tests, contract and load tests, coverage, testing the mail client against a stand-in mail service, Aspire's testing tools, and CI pipeline files are outside this article's scope.

## What the handler tests skip

Here's the test that passed:

```csharp
[Fact]
public async Task Repeating_a_request_with_the_same_key_returns_the_first_task()
{
    var key = Guid.NewGuid().ToString();
    var newTask = new NewTask("Write the release notes", null, null);

    await using var first = database.CreateContext();
    var created = await CreateTask.Handle(newTask, key, first, TestContext.Current.CancellationToken);
    await using var second = database.CreateContext();
    var repeated = await CreateTask.Handle(newTask, key, second, TestContext.Current.CancellationToken);

    var original = Assert.IsType<Created<TaskDetails>>(created.Result);
    var replay = Assert.IsType<Created<TaskDetails>>(repeated.Result);
    Assert.Equal(original.Value!.Id, replay.Value!.Id);
}
```

What to notice:

- The test passes the key as the second argument of `CreateTask.Handle`. In an ordinary C# call, nothing reads the attributes on that parameter.
- `[FromHeader]` and `[StringLength]` are instructions for ASP.NET Core. `MapPost` reads them when it builds the endpoint's code that turns a request into arguments, as [the request pipeline article](/dump/blog/aspnet-core-request-pipeline/#where-parameters-come-from) showed.

When a client sends `POST /tasks`, these steps run before and after the method body:

1. Routing matches `POST /tasks` to the `CreateTask` endpoint.
2. Authentication checks the bearer token, and the `editor` policy from `RequireAuthorization("editor")` checks the role.
3. Binding reads `NewTask` from the JSON body and the key from the header that `[FromHeader]` names.
4. Validation checks the title's `[Required]` and `[StringLength(200)]` and the key's `[StringLength(100)]`.
5. The `Created` result writes status `201`, the `Location` header, and the JSON body.

A direct call runs only the method body: the insert, the unique key, the fingerprint comparison. It tests those well, with less setup and no server. The cleanup broke step 3, which a direct call never runs.

The test project already has both kinds of test:

| Test class | Tests | How it reaches the code |
| --- | --- | --- |
| `AuthenticationTests` | 4 | HTTP requests through `TaskBoardApp` |
| `TaskRulesTests` | 6 | HTTP requests through `TaskBoardApp` |
| `ConfigurationTests` | 1 | starts the app through `TaskBoardApp` |
| `CreateTaskTests` | 3 | calls `CreateTask.Handle` |
| `CompleteTaskTests` | 3 | calls `CompleteTask.Handle` |
| `PendingEmailSenderTests` | 1 | runs `PendingEmailSender` without the app |

All three tests about the key sat in the bottom half, so the key had never arrived in a header in any test.

## Sending the request instead

`TaskBoardApp`, from [the token article](/dump/blog/what-an-api-must-check-in-a-token/#testing-protected-endpoints), already starts the whole app for `AuthenticationTests` and `TaskRulesTests`. The key test can send its requests through it the same way:

```csharp
public class CreateTaskTests(TaskBoardApp app, TestDatabase database) : IClassFixture<TestDatabase>, IClassFixture<TaskBoardApp>
{
    HttpClient EditorClient()
    {
        var client = app.CreateClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", TestTokens.For("ada", ["editor"]));
        return client;
    }

    static HttpRequestMessage NewTaskRequest(string title, string key)
    {
        var request = new HttpRequestMessage(HttpMethod.Post, "/tasks") { Content = JsonContent.Create(new { title }) };
        request.Headers.Add("Idempotency-Key", key);
        return request;
    }

    [Fact]
    public async Task Repeating_a_request_with_the_same_key_returns_the_first_task()
    {
        var client = EditorClient();
        var key = Guid.NewGuid().ToString();

        var first = await client.SendAsync(NewTaskRequest("Write the release notes", key), TestContext.Current.CancellationToken);
        var repeated = await client.SendAsync(NewTaskRequest("Write the release notes", key), TestContext.Current.CancellationToken);

        Assert.Equal(HttpStatusCode.Created, first.StatusCode);
        Assert.Equal(HttpStatusCode.Created, repeated.StatusCode);
        Assert.Equal(first.Headers.Location, repeated.Headers.Location);
    }
}
```

What to notice:

- The key travels the way a client sends it, in an `Idempotency-Key` header, and the test checks what a client sees: the status and the `Location` header.
- `NewTaskRequest` builds a new `HttpRequestMessage` for each send, because `HttpClient` throws if you send the same message twice.
- The class keeps `TestDatabase` because the third test counts the tasks in the database after eight simultaneous requests.

The other two tests change the same way. Reusing the key with a different title expects `422`, and eight simultaneous requests with one key expect a single task, with `201` for every request.

<details>
<summary>The other two tests in <code>CreateTaskTests.cs</code></summary>

```csharp
[Fact]
public async Task Reusing_a_key_for_a_different_task_is_refused()
{
    var client = EditorClient();
    var key = Guid.NewGuid().ToString();

    await client.SendAsync(NewTaskRequest("Write the release notes", key), TestContext.Current.CancellationToken);
    var response = await client.SendAsync(NewTaskRequest("Fix the login form", key), TestContext.Current.CancellationToken);

    Assert.Equal(HttpStatusCode.UnprocessableEntity, response.StatusCode);
}

[Fact]
public async Task Simultaneous_requests_with_the_same_key_create_one_task()
{
    var client = EditorClient();
    var key = Guid.NewGuid().ToString();
    var title = $"Race {key}";

    var requests = new List<Task<HttpResponseMessage>>();
    for (var i = 0; i < 8; i++)
    {
        requests.Add(client.SendAsync(NewTaskRequest(title, key), TestContext.Current.CancellationToken));
    }

    var responses = await Task.WhenAll(requests);
    await using var db = database.CreateContext();
    var count = await db.Tasks.CountAsync(t => t.Title == title, TestContext.Current.CancellationToken);
    Assert.Equal(1, count);
    foreach (var response in responses)
    {
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
    }
}
```

</details>

With the cleanup applied, all three fail:

```text
CreateTaskTests.Repeating_a_request_with_the_same_key_returns_the_first_task [FAIL]
  Expected: /tasks/1
  Actual:   /tasks/2
CreateTaskTests.Reusing_a_key_for_a_different_task_is_refused [FAIL]
  Expected: UnprocessableEntity
  Actual:   Created
CreateTaskTests.Simultaneous_requests_with_the_same_key_create_one_task [FAIL]
  Expected: 1
  Actual:   8
Failed!  - Failed:     3, Passed:    15, Skipped:     0, Total:    18
```

With the header name back, all 18 pass. The tests now go through steps 1 to 5. But the app they reach isn't quite the one in production: it runs inside the test process, with a test signing key and a fake mail sender. So what exactly does `app.CreateClient()` start?

## What WebApplicationFactory runs

Here's `TaskBoardApp` as the token and configuration articles left it:

```csharp
public class TaskBoardApp : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseSetting("ConnectionStrings:TaskBoard", TestDatabase.ConnectionString);
        builder.UseSetting("Mail:ApiKey", "test-key");
        builder.ConfigureTestServices(services =>
        {
            services.Configure<JwtBearerOptions>(JwtBearerDefaults.AuthenticationScheme, options =>
            {
                var configuration = new OpenIdConnectConfiguration { Issuer = TestTokens.Issuer };
                configuration.SigningKeys.Add(TestTokens.Key);
                options.Configuration = configuration;
            });
            services.AddSingleton<IMailSender, FakeMailSender>();
        });
    }
}
```

The first `CreateClient()` starts the app in four steps:

1. The factory looks up the assembly that contains `Program` and runs its entry point, `Program.cs`'s top-level code, on a thread of its own inside the test process, with the environment set to `Development`. (The test project can name `Program` because `Program.cs` ends with `public partial class Program;`.)
2. `Program.cs` runs line by line, as with `dotnet run`. `WebApplication.CreateBuilder(args)` loads configuration, and the lines after it register services, reading settings such as the connection string along the way.
3. When `Program.cs` calls `builder.Build()`, the factory steps in just before the app is built. It runs `ConfigureWebHost`, replaces Kestrel with `TestServer`, an in-memory server with no port, and adds the `ConfigureTestServices` registrations after the ones in `Program.cs`.
4. `Program.cs` reaches `app.Run()`, which starts the app on the test server. The factory waits for the start, then returns an `HttpClient` that hands each request to `TestServer` directly. No socket or port is involved, but the request runs through the same middleware, routing, binding, and handlers as in production.

Steps 2 and 3 explain the two ways settings reach the app. `Program.cs` reads the connection string in step 2:

```csharp
builder.Services.AddNpgsqlDataSource(builder.Configuration.GetConnectionString("TaskBoard")
    ?? throw new InvalidOperationException("ConnectionStrings:TaskBoard is missing."));
```

`UseSetting` values arrive as command-line arguments. The factory turns each into an argument such as `--ConnectionStrings:TaskBoard=Host=…` and passes it to `Program.cs`, and `CreateBuilder(args)` adds command-line arguments as the last configuration source. So the test's connection string is in place, and wins, before that line runs.

`WebApplicationFactory` also has `ConfigureAppConfiguration`, which looks like the obvious way to add a setting. Its callbacks run in step 3, after the line above has already read the connection string from `appsettings.json`. With the connection string passed that way instead:

- On a machine with no `taskboard` database, 9 of the 18 tests failed, eight of them with `Actual: InternalServerError`, and PostgreSQL logged `database "taskboard" does not exist`.
- On a machine with the `taskboard` database from `appsettings.json`, 3 to 5 tests failed per run, and each run left 4 test tasks in that database.

So a setting that `Program.cs` reads before `Build()` has to arrive through `UseSetting`.

`ConfigureTestServices` runs in step 3 as well, after every registration in `Program.cs`. When the app asks for one `IMailSender`, the service container returns the last registration, `FakeMailSender`. The JwtBearer callback runs after `Program.cs`'s own JwtBearer setup, so its issuer and key replace what JwtBearer would otherwise download from Keycloak.

Those two replacements are what these tests don't prove. The test key shows that the app checks the signature, the issuer, the audience, the lifetime, and the roles. It can't show that Keycloak issues tokens with the `taskboard-api` audience and the realm roles the app expects, because Keycloak's realm settings decide what goes into its tokens, and no test asks Keycloak. Keycloak can run in a container during the tests too, but it took about 23 seconds to start with the realm imported, against about 3 seconds for PostgreSQL. In the same way, `FakeMailSender` shows what the app asks to send, not that `HttpMailSender` talks to the mail service correctly.

ASP.NET Core 10 also added `UseKestrel()` to `WebApplicationFactory`, which runs the app on a real port instead of `TestServer`, for clients that need one, such as a browser.

So the tests run the whole app. What they still need is a database, and that comes from `TestDatabase.ConnectionString`.

## A database the test run starts

`TestDatabase` connects to a fixed address:

```csharp
public const string ConnectionString = "Host=localhost;Port=55460;Username=postgres;Database=taskboard_bg_test";
```

So the tests pass only on a machine where someone has started PostgreSQL on port 55460 with no password. On a fresh clone without it, 17 of the 18 tests fail with the same error:

```text
Class fixture type 'TestDatabase' threw in InitializeAsync
---- System.InvalidOperationException : An exception has been raised that is likely due to a transient failure.
-------- Npgsql.NpgsqlException : Failed to connect to 127.0.0.1:55460
------------ System.Net.Sockets.SocketException : Connection refused
```

The fixed name causes a second problem. Each test class's `TestDatabase` drops and recreates `taskboard_bg_test`, so two test runs on one machine at the same moment, from two checkouts, drop each other's database. Three rounds of two runs at once gave 6 to 13 failures in every run, such as `3D000: database "taskboard_bg_test" does not exist`.

### Starting PostgreSQL from the tests

Testcontainers is a library that starts containers from test code through Docker. Its PostgreSQL module pulls the image if it's missing, starts a container, maps PostgreSQL's port 5432 to a random free port on your machine, and waits until `pg_isready` inside the container reports the server ready. `GetConnectionString()` then returns a connection string with that port and the module's default user, password, and database.

The container has to start before the app, because the app needs its connection string. xUnit's documentation says fixtures can't depend on other fixtures, and advises one class that creates both objects itself. So `TaskBoardApp` takes over from `TestDatabase` and owns the container:

```csharp
[assembly: AssemblyFixture(typeof(TaskBoardApp))]
[assembly: CollectionBehavior(DisableTestParallelization = true)]

public class TaskBoardApp : WebApplicationFactory<Program>, IAsyncLifetime
{
    readonly PostgreSqlContainer database = new PostgreSqlBuilder("postgres:18.6-trixie").Build();

    public async ValueTask InitializeAsync()
    {
        await database.StartAsync();
        await using var db = CreateContext();
        await db.Database.EnsureCreatedAsync();
    }

    public TaskBoardDb CreateContext()
    {
        var options = new DbContextOptionsBuilder<TaskBoardDb>()
            .UseNpgsql(database.GetConnectionString())
            .UseSnakeCaseNamingConvention()
            .Options;
        return new TaskBoardDb(options);
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseSetting("ConnectionStrings:TaskBoard", database.GetConnectionString());
        // …the mail key and ConfigureTestServices, as before
    }

    public override async ValueTask DisposeAsync()
    {
        await base.DisposeAsync();
        await database.DisposeAsync();
    }
}
```

What to notice:

- `[assembly: AssemblyFixture(typeof(TaskBoardApp))]` tells xUnit v3 to create one `TaskBoardApp` for the whole test run. Any test class gets it by taking it as a constructor parameter, without `IClassFixture`.
- xUnit calls `InitializeAsync` before the first test, from the `IAsyncLifetime` interface, and `DisposeAsync` after the last one. `DisposeAsync` stops the app first, then removes the container.
- The image is `postgres:18.6-trixie`, the same PostgreSQL version the task board runs on.
- `CreateContext()` moves over from `TestDatabase`, so the tests that call handlers directly use the same database. `TestDatabase.cs` is gone, and every test class now starts like `public class CreateTaskTests(TaskBoardApp app)`.
- `DisableTestParallelization` moved over from `TestDatabase.cs` unchanged. [Keeping tests out of each other's way](#keeping-tests-out-of-each-others-way) explains why it stays.

The first run on a machine without the images pulls PostgreSQL and Ryuk, the container described below, and that first `dotnet test` took about 19 seconds. With the images present, a fresh clone passed all 18 tests in about 8 seconds, build included, and later runs took about 7 seconds, against about 3 seconds with the hand-started database. Starting the containers is most of the difference: about 3.3 seconds per run. Two runs at once each got a container of its own and passed in all three rounds.

Without Docker, every test fails before any test code runs:

```text
Assembly fixture type 'TaskBoardApp' threw in its constructor
---- DotNet.Testcontainers.Builders.DockerUnavailableException : Docker is either not running or misconfigured. Please ensure that Docker is running and that the endpoint is properly configured.
```

### When a test run doesn't finish

`DisposeAsync` removes the container only if the test run gets that far. When the test process is killed, a second container cleans up. Before the first container, Testcontainers starts Ryuk (`testcontainers/ryuk`), labels every container it starts with the run's session ID, and keeps a connection open to Ryuk. When that connection closes and stays closed for 10 seconds, Ryuk removes everything with the label, then itself.

Killing the test process with `kill -9` during a run showed it: `dotnet test` reported `Test process crashed with exit code 137`, and the PostgreSQL container was gone 10 to 12 seconds later. With Ryuk turned off through `TESTCONTAINERS_RYUK_DISABLED=true`, the container was still running 30 seconds later and stayed until it was removed by hand. Testcontainers' documentation advises keeping Ryuk on, except on CI machines that are thrown away after each build anyway.

In CI, the tests need the same thing as on your machine: Docker. GitHub's hosted Ubuntu runners list Docker among their installed software, and Testcontainers' documentation covers other CI services.

So any machine with Docker gets an empty PostgreSQL for each run. But where do its tables come from?

## Building the schema with migrations

`InitializeAsync` builds the tables with `EnsureCreatedAsync`, as `TestDatabase` did. `EnsureCreated` creates the tables from EF Core's current model of the entities and ignores the `Migrations` folder. Production gets its tables from the migrations, as in [the schema changes article](/dump/blog/changing-the-schema-without-breaking-the-app/#migrations-schema-changes-as-code). The two can disagree.

Here's a change that makes them disagree: a new property on `TaskItem`, with no migration for it.

```csharp
public string? Description { get; set; }
```

With `EnsureCreated`, all 18 tests pass, because the test database gets a `description` column straight from the model. The real API, on a database built by the migrations, fails on the first new task:

```text
POST /tasks    500 Internal Server Error
```

The app's log has the reason:

```text
Npgsql.PostgresException (0x80004005): 42703: column "description" of relation "tasks" does not exist
```

`GET /tasks/1` still answers `200`, because its query reads only the columns it needs.

So `InitializeAsync` uses the migrations instead, with one changed line:

```csharp
await db.Database.MigrateAsync();
```

`MigrateAsync` applies every migration in order, the way production gets its schema. Since EF Core 9 it first compares the model with the one recorded by the latest migration, and throws when the model has changes no migration covers. With the same `Description` property, all 18 tests fail without running:

```text
Assembly fixture type 'TaskBoardApp' threw in InitializeAsync
---- System.InvalidOperationException : An error was generated for warning 'Microsoft.EntityFrameworkCore.Migrations.PendingModelChangesWarning': The model for context 'TaskBoardDb' has pending changes. Add a new migration before updating the database.
```

Adding the migration fixes it, in the tests and in production. The cost is small: in five runs each, `MigrateAsync` took 0.54 to 0.61 seconds and `EnsureCreatedAsync` 0.48 to 0.52, once per test run.

The tables now match production's. But before, each test class's `TestDatabase` dropped and recreated the database, and now six classes share one database for the whole run.

## Keeping tests out of each other's way

With one database for the whole run, one test failed in 7 of 12 runs:

```text
PendingEmailSenderTests.Sends_pending_emails_with_their_keys_and_keeps_the_ones_that_failed [FAIL]
  Assert.Single() Failure: The collection contained 3 items
```

The worker test saves two `pending_emails` rows, starts `PendingEmailSender` with a mail sender that fails once, and expects exactly one email sent. But the worker sends every row in the table, and completing a task adds a row, as [the background work article](/dump/blog/background-work-in-aspnet-core/#keeping-the-email-in-a-table) set up. `CompleteTaskTests` and `TaskRulesTests` complete tasks, so when they run before the worker test, their rows are still waiting, and the worker sends them too.

It failed in only some runs because xUnit runs test classes in an unpredictable order. Four runs gave four orders, such as these two:

```text
TaskRulesTests  AuthenticationTests  CompleteTaskTests  ConfigurationTests  PendingEmailSenderTests  CreateTaskTests
CompleteTaskTests  PendingEmailSenderTests  ConfigurationTests  AuthenticationTests  TaskRulesTests  CreateTaskTests
```

The other 17 tests already avoid each other. Each one creates its own users, with a new GUID in each email address, its own tasks, and its own keys, and checks only those, such as counting tasks with a title that contains its key. The worker test is the only one that reads a whole table, so it empties the table first:

```csharp
await using (var db = app.CreateContext())
{
    await db.PendingEmails.ExecuteDeleteAsync(TestContext.Current.CancellationToken);
}
```

With that, the worker test passed in all 52 runs.

One more thing reads `pending_emails` during the tests: the app itself. `TaskBoardApp` runs the whole app, including the `PendingEmailSender` that `Program.cs` registers with `AddHostedService`. So every 5 seconds, the app's own worker sends whatever is in the table to `FakeMailSender`. In 4 of 5 recorded runs, it sent `Completed: First`, the row the worker test leaves behind on purpose, or the email that `CompleteTaskTests` checks for. Neither broke a test in those runs. But `CompleteTaskTests` checks that its row exists right after completing the task, so a check by the app's worker between the two would delete the row first. `TaskBoardApp` removes the worker inside `ConfigureTestServices`:

```csharp
services.Remove(services.Single(service => service.ImplementationType == typeof(PendingEmailSender)));
```

What to notice:

- Adding `FakeMailSender` was enough to replace the mail sender, because the app asks for one `IMailSender`. The host asks for every registered hosted service, so adding another one wouldn't replace anything. The worker's registration has to go.
- `PendingEmailSenderTests` still tests the worker by starting it directly. No test sends an email all the way through the app, which would also wait up to 5 seconds for the worker's next check.

Test classes still run one at a time. In parallel, the worker test's `ExecuteDeleteAsync` could delete the row `CompleteTaskTests` is about to check. Running them in parallel saved about half a second: 6.0 to 6.4 seconds per run against 6.9 to 7.0.

Bigger suites keep tests apart in other ways, each with a cost. A database per test class, copied from a migrated template database with `CREATE DATABASE … TEMPLATE`, took about 15 ms per copy and lets classes run in parallel. A reset tool such as Respawn empties every table between tests in a few milliseconds, but then no test can rely on data that another created. A container per class costs about 3 seconds per class. Rolling back a transaction after each test doesn't fit here, because the app opens its own connection for each request, outside the test's transaction.

<details>
<summary>The complete <code>TaskBoardApp.cs</code></summary>

```csharp
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using Testcontainers.PostgreSql;

[assembly: AssemblyFixture(typeof(TaskBoardApp))]
[assembly: CollectionBehavior(DisableTestParallelization = true)]

public class TaskBoardApp : WebApplicationFactory<Program>, IAsyncLifetime
{
    readonly PostgreSqlContainer database = new PostgreSqlBuilder("postgres:18.6-trixie").Build();

    public async ValueTask InitializeAsync()
    {
        await database.StartAsync();
        await using var db = CreateContext();
        await db.Database.MigrateAsync();
    }

    public TaskBoardDb CreateContext()
    {
        var options = new DbContextOptionsBuilder<TaskBoardDb>()
            .UseNpgsql(database.GetConnectionString())
            .UseSnakeCaseNamingConvention()
            .Options;
        return new TaskBoardDb(options);
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseSetting("ConnectionStrings:TaskBoard", database.GetConnectionString());
        builder.UseSetting("Mail:ApiKey", "test-key");
        builder.ConfigureTestServices(services =>
        {
            services.Configure<JwtBearerOptions>(JwtBearerDefaults.AuthenticationScheme, options =>
            {
                var configuration = new OpenIdConnectConfiguration { Issuer = TestTokens.Issuer };
                configuration.SigningKeys.Add(TestTokens.Key);
                options.Configuration = configuration;
            });
            services.AddSingleton<IMailSender, FakeMailSender>();
            services.Remove(services.Single(service => service.ImplementationType == typeof(PendingEmailSender)));
        });
    }

    public override async ValueTask DisposeAsync()
    {
        await base.DisposeAsync();
        await database.DisposeAsync();
    }
}
```

</details>

## Back to the key

So why did the test for a repeated key pass while the API created two tasks? It called `CreateTask.Handle` with the key as an argument, and the bug was in how ASP.NET Core finds that argument in a request. The HTTP test sends the key the way Ada's client does, and with the cleanup applied it fails:

```text
CreateTaskTests.Repeating_a_request_with_the_same_key_returns_the_first_task [FAIL]
  Expected: /tasks/17
  Actual:   /tasks/18
```

With the header name back, all 18 pass, on any machine with Docker, against a PostgreSQL built by the same migrations as production.

The direct tests still have their place. Microsoft's integration testing page gives the rule: "If a behavior can be tested using either a unit test or an integration test, choose the unit test." `CompleteTaskTests` checks the completion rule by calling the handler, and a request would add nothing it needs. A header's name, a route, a policy, or a status code is a behavior only a request reaches. [Testing what your code does from the outside](/dump/blog/testing-observable-behavior/#what-to-call-these-tests) covers the names people give these kinds of tests.

## Check your understanding

1. **A test called `CreateTask.Handle` twice with the same key and got the same task, yet two real requests with that key created two tasks. Why?** The test passed the key as an argument, so binding never ran. Without a name, `[FromHeader]` read a header called `idempotencyKey`, which Ada's client never sent. Only a test that sends a request runs binding.
2. **Why does `TaskBoardApp` pass the connection string with `UseSetting` and not `ConfigureAppConfiguration`?** `Program.cs` reads the connection string before `builder.Build()`. `UseSetting` values arrive as command-line arguments, which are already in the configuration then; `ConfigureAppConfiguration` runs at `Build()`, too late, so the app used `appsettings.json`'s database.
3. **A property was added to an entity without a migration. Why did the tests pass with `EnsureCreated`, and what does `MigrateAsync` do instead?** `EnsureCreated` builds tables from the current model, so the test database had the new column while production's didn't. `MigrateAsync` builds tables from the migrations, as production does, and since EF Core 9 it throws when the model has changes no migration covers.
4. **After all test classes started sharing one database, the worker test failed in some runs and passed in others. Why, and what fixed it?** The worker sends every row in `pending_emails`, including rows that other classes' completions left behind, and those classes ran before it only in some of xUnit's unpredictable orders. Emptying the table at the start of the worker test fixed it, and removing the app's own worker kept it from sending rows that other tests check.

## Sources and further reading

- Microsoft, [Integration tests in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/test/integration-tests?view=aspnetcore-10.0) and [Unit and integration tests in Minimal API apps](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/minimal-apis/test-min-api?view=aspnetcore-10.0).
- ASP.NET Core source at v10.0.13: [WebApplicationFactory.cs](https://github.com/dotnet/aspnetcore/blob/v10.0.13/src/Mvc/Mvc.Testing/src/WebApplicationFactory.cs) and [DeferredHostBuilder.cs](https://github.com/dotnet/aspnetcore/blob/v10.0.13/src/Mvc/Mvc.Testing/src/DeferredHostBuilder.cs); .NET's [HostFactoryResolver.cs](https://github.com/dotnet/runtime/blob/v10.0.13/src/libraries/Microsoft.Extensions.HostFactoryResolver/src/HostFactoryResolver.cs).
- xUnit.net, [Shared context between tests](https://xunit.net/docs/shared-context), [What's new in v3](https://xunit.net/docs/getting-started/v3/whats-new), and [Running tests in parallel](https://xunit.net/docs/running-tests-in-parallel).
- Testcontainers for .NET, [PostgreSQL module](https://dotnet.testcontainers.org/modules/postgres/), [Resource Reaper](https://dotnet.testcontainers.org/api/resource_reaper/), and [Continuous integration](https://dotnet.testcontainers.org/cicd/); [Moby Ryuk](https://github.com/testcontainers/moby-ryuk).
- EF Core, [Choosing a testing strategy](https://learn.microsoft.com/en-us/ef/core/testing/choosing-a-testing-strategy), [Testing against your production database system](https://learn.microsoft.com/en-us/ef/core/testing/testing-with-the-database), [Create and drop APIs](https://learn.microsoft.com/en-us/ef/core/managing-schemas/ensure-created), [Applying migrations](https://learn.microsoft.com/en-us/ef/core/managing-schemas/migrations/applying), and [Breaking changes in EF Core 9](https://learn.microsoft.com/en-us/ef/core/what-is-new/ef-core-9.0/breaking-changes).
- PostgreSQL, [Template databases](https://www.postgresql.org/docs/18/manage-ag-templatedbs.html); [Respawn](https://github.com/jbogard/Respawn).
- GitHub, [GitHub-hosted runners](https://docs.github.com/en/actions/concepts/runners/github-hosted-runners) and the [Ubuntu 24.04 runner image's software list](https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md).
