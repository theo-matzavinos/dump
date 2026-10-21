---
title: "Same endpoints, two styles: controllers and minimal APIs in ASP.NET Core"
description: "Build the task board's endpoints as a controller and as minimal API endpoints, and compare what actually differs: binding defaults, validation, error bodies, dependencies, testing, speed, and what each style is for."
pubDate: "2026-10-19T15:00:00Z"
updatedDate: "2026-10-20"
tags:
  - aspnet-core
  - dotnet
  - minimal-apis
  - controllers
audience:
  - backend
---

There are two copies of the task board's API. They have the same endpoints, talk to the same database, and return the same tasks. A client forgets the `assigneeId` query parameter when listing tasks:

```bash
curl -i "http://localhost:5101/tasks?dueBefore=2027-01-01"
curl -i "http://localhost:5102/tasks?dueBefore=2027-01-01"
```

```text
HTTP/1.1 400 Bad Request

HTTP/1.1 200 OK
Content-Type: application/json; charset=utf-8

[]
```

The first copy says the request is wrong, with an empty body. The second says the request is fine and there's nothing to show. Asking each for a task that doesn't exist, `GET /tasks/9999999`, splits them again: the first answers `404` with an empty body, the second answers `404` with a JSON description of the error.

The first copy is written with minimal API endpoints, the style every example in this series has used. The second is written with a controller, the style many ASP.NET Core codebases use. Which one is broken? To answer, this article builds the same endpoints both ways and compares them where they actually differ.

You'll need [From bytes to your handler](/dump/blog/aspnet-core-request-pipeline/), which showed that a controller's actions become endpoints in the same routing table as `MapGet`, and how filters wrap a handler. [Who creates your services](/dump/blog/aspnet-core-dependency-injection/) covers request scopes, and [the transactions article](/dump/blog/transactions-and-concurrent-edits/) built the ETag and `If-Match` endpoints used here. The testing section assumes you've seen an xUnit test with `[Fact]` and `Assert`.

## Contents

1. [Set up the example](#set-up-the-example)
2. [What Microsoft recommends](#what-microsoft-recommends)
3. [Routes, and where the code lives](#routes-and-where-the-code-lives)
4. [How dependencies arrive](#how-dependencies-arrive)
5. [Binding: the same signature, different rules](#binding-the-same-signature-different-rules)
6. [Validation](#validation)
7. [Results and error bodies](#results-and-error-bodies)
8. [Filters and authorization](#filters-and-authorization)
9. [Testing](#testing)
10. [Speed, startup, memory, and Native AOT](#speed-startup-memory-and-native-aot)
11. [Both styles in one app](#both-styles-in-one-app)
12. [When each fits](#when-each-fits)
13. [Back to the two answers](#back-to-the-two-answers)

## Set up the example

The examples use the .NET 10 SDK (ASP.NET Core 10.0.13), Npgsql.EntityFrameworkCore.PostgreSQL 10.0.3, EFCore.NamingConventions 10.0.1, Npgsql.DependencyInjection 10.0.3, and PostgreSQL 18.6 with the task board's database from the earlier articles, including its `version` column. Both copies run with the `Production` environment, `dotnet run --no-launch-profile`, so the responses are the ones real clients get. Endpoint design and authentication setup are outside this article's scope.

There are two projects, `Minimal` and `Controllers`. They share the entity classes and `TaskBoardDb` from the transactions article, plus these records:

```csharp
public record TaskDetails(int Id, string Title, bool Done, DateOnly? DueOn, int Version);

public record TaskSummary(int Id, string Title, bool Done, DateOnly? DueOn);

public record TaskEdit(string Title, DateOnly? DueOn);

public record NewTask([Required, StringLength(200)] string Title, int? AssigneeId, DateOnly? DueOn);
```

and the ETag helpers from the transactions article, moved into a small shared class:

```csharp
public static class ETags
{
    public static string For(int version) => $"\"{version}\"";

    public static bool Matches(IList<EntityTagHeaderValue> ifMatch, int version)
    {
        var current = new EntityTagHeaderValue(For(version));
        foreach (var tag in ifMatch)
        {
            if (tag.Equals(EntityTagHeaderValue.Any) || tag.Compare(current, useStrongComparison: true))
            {
                return true;
            }
        }

        return false;
    }
}
```

Each project has five endpoints: a list of a user's open tasks, optionally due before a date; one task with its ETag; creating a task; editing it with `If-Match`; and completing it.

## What Microsoft recommends

Microsoft's API documentation for ASP.NET Core 10 states its position directly: "For new projects, we recommend using Minimal APIs as they provide a simplified, high-performance approach for building APIs with minimal code and configuration." The `dotnet new webapi` template follows it, creating minimal API endpoints unless you add `--use-controllers`.

The same page lists its reasons: simpler syntax, better performance, easier testing, and a modern approach. It also lists when to consider controllers: when you need model binding extensibility, advanced validation through `IModelValidator`, application parts or the application model, or OData, adding that "most of these features can be implemented in Minimal APIs with custom solutions, but controllers provide them out of the box." Elsewhere on the page, it says controllers "may be preferred for" large applications with complex business logic and teams familiar with the MVC pattern.

Both styles are supported, and as the pipeline article showed, both produce endpoints in the same routing table, behind the same middleware. The rest of this article checks those reasons against working code.

## Routes, and where the code lives

Here's the endpoint for one task, as a controller action:

```csharp
[ApiController]
[Route("tasks")]
public class TasksController(TaskBoardDb db) : ControllerBase
{
    [HttpGet("{id:int}")]
    public async Task<ActionResult<TaskDetails>> Get(int id, CancellationToken cancellationToken)
    {
        var task = await db.Tasks
            .Where(t => t.Id == id)
            .Select(t => new TaskDetails(t.Id, t.Title, t.Done, t.DueOn, t.Version))
            .SingleOrDefaultAsync(cancellationToken);
        if (task is null)
        {
            return NotFound();
        }

        Response.Headers.ETag = ETags.For(task.Version);
        return task;
    }

    // List, Create, Edit, and Complete follow the same pattern.
}
```

and as a minimal API endpoint:

```csharp
public static class TaskEndpoints
{
    public static void MapTaskEndpoints(this IEndpointRouteBuilder app)
    {
        var tasks = app.MapGroup("/tasks");

        tasks.MapGet("/", List);
        tasks.MapGet("/{id:int}", Get);
        tasks.MapPost("/", Create);
        tasks.MapPut("/{id:int}", Edit);
        tasks.MapPost("/{id:int}/complete", Complete);
    }

    public static async Task<Results<Ok<TaskDetails>, NotFound>> Get(int id, TaskBoardDb db, HttpContext context, CancellationToken cancellationToken)
    {
        var task = await db.Tasks
            .Where(t => t.Id == id)
            .Select(t => new TaskDetails(t.Id, t.Title, t.Done, t.DueOn, t.Version))
            .SingleOrDefaultAsync(cancellationToken);
        if (task is null)
        {
            return TypedResults.NotFound();
        }

        context.Response.Headers.ETag = ETags.For(task.Version);
        return TypedResults.Ok(task);
    }
}
```

What to notice:

- **The route templates are the same.** `[Route("tasks")]` plus `[HttpGet("{id:int}")]` builds `/tasks/{id:int}`, and so does `MapGroup("/tasks")` plus `MapGet("/{id:int}", …)`. Constraints like `:int` work identically.
- **The controller gets its routes from attributes;** `Program.cs` only calls `MapControllers()`, which finds every controller. The minimal endpoints are registered by code, `app.MapTaskEndpoints()`.
- **The handlers are named static methods,** not lambdas. Earlier articles used lambdas to keep examples short; named methods are easier to find and can be called directly from tests.

A common belief is that minimal APIs put everything in `Program.cs`. Microsoft's documentation says the opposite: "Minimal APIs don't have to be located in the Program.cs file." `MapTaskEndpoints` is an ordinary extension method in its own file, and `Program.cs` calls it once.

In this example, the two files come out about the same size: `TaskEndpoints.cs` is 106 lines and `TasksController.cs` is 101. Adding the "complete" endpoint meant changing one file in each style; adding a due date to `NewTask` meant changing the record and one handler in each. Where you look for a feature's code differs: a controller by its class name, minimal endpoints by their `Map…` calls. The endpoint list from the pipeline article prints both.

<details>
<summary>The complete <code>TasksController.cs</code></summary>

```csharp
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

[ApiController]
[Route("tasks")]
public class TasksController(TaskBoardDb db) : ControllerBase
{
    [HttpGet]
    public async Task<List<TaskSummary>> List(int assigneeId, DateOnly? dueBefore, CancellationToken cancellationToken)
    {
        var query = db.Tasks.Where(t => t.AssigneeId == assigneeId && !t.Done);
        if (dueBefore is not null)
        {
            query = query.Where(t => t.DueOn < dueBefore);
        }

        return await query
            .OrderBy(t => t.DueOn)
            .Take(20)
            .Select(t => new TaskSummary(t.Id, t.Title, t.Done, t.DueOn))
            .ToListAsync(cancellationToken);
    }

    [HttpGet("{id:int}")]
    public async Task<ActionResult<TaskDetails>> Get(int id, CancellationToken cancellationToken)
    {
        var task = await db.Tasks
            .Where(t => t.Id == id)
            .Select(t => new TaskDetails(t.Id, t.Title, t.Done, t.DueOn, t.Version))
            .SingleOrDefaultAsync(cancellationToken);
        if (task is null)
        {
            return NotFound();
        }

        Response.Headers.ETag = ETags.For(task.Version);
        return task;
    }

    [HttpPost]
    public async Task<ActionResult<TaskDetails>> Create(NewTask newTask, CancellationToken cancellationToken)
    {
        var task = new TaskItem { Title = newTask.Title, AssigneeId = newTask.AssigneeId, DueOn = newTask.DueOn, Version = 1 };
        db.Tasks.Add(task);
        await db.SaveChangesAsync(cancellationToken);
        return CreatedAtAction(nameof(Get), new { id = task.Id }, new TaskDetails(task.Id, task.Title, task.Done, task.DueOn, task.Version));
    }

    [HttpPut("{id:int}")]
    public async Task<IActionResult> Edit(int id, TaskEdit edit, CancellationToken cancellationToken)
    {
        var ifMatch = Request.GetTypedHeaders().IfMatch;
        if (ifMatch.Count == 0)
        {
            return Problem("Send the task's ETag in an If-Match header.", statusCode: StatusCodes.Status428PreconditionRequired);
        }

        var task = await db.Tasks.SingleOrDefaultAsync(t => t.Id == id, cancellationToken);
        if (task is null)
        {
            return NotFound();
        }

        if (!ETags.Matches(ifMatch, task.Version))
        {
            return Problem("The task changed after you loaded it. Load it again and reapply your edit.", statusCode: StatusCodes.Status412PreconditionFailed);
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
            return Problem("The task changed after you loaded it. Load it again and reapply your edit.", statusCode: StatusCodes.Status412PreconditionFailed);
        }

        Response.Headers.ETag = ETags.For(task.Version);
        return NoContent();
    }

    [HttpPost("{id:int}/complete")]
    public async Task<IActionResult> Complete(int id, CancellationToken cancellationToken)
    {
        var changed = await db.Tasks
            .Where(t => t.Id == id)
            .ExecuteUpdateAsync(s => s
                .SetProperty(t => t.Done, true)
                .SetProperty(t => t.Version, t => t.Version + 1), cancellationToken);
        if (changed == 0)
        {
            return NotFound();
        }

        return NoContent();
    }
}
```

</details>

<details>
<summary>The complete <code>TaskEndpoints.cs</code></summary>

```csharp
using Microsoft.AspNetCore.Http.HttpResults;
using Microsoft.EntityFrameworkCore;

public static class TaskEndpoints
{
    public static void MapTaskEndpoints(this IEndpointRouteBuilder app)
    {
        var tasks = app.MapGroup("/tasks");

        tasks.MapGet("/", List);
        tasks.MapGet("/{id:int}", Get);
        tasks.MapPost("/", Create);
        tasks.MapPut("/{id:int}", Edit);
        tasks.MapPost("/{id:int}/complete", Complete);
    }

    public static async Task<Ok<List<TaskSummary>>> List(int assigneeId, DateOnly? dueBefore, TaskBoardDb db, CancellationToken cancellationToken)
    {
        var query = db.Tasks.Where(t => t.AssigneeId == assigneeId && !t.Done);
        if (dueBefore is not null)
        {
            query = query.Where(t => t.DueOn < dueBefore);
        }

        var tasks = await query
            .OrderBy(t => t.DueOn)
            .Take(20)
            .Select(t => new TaskSummary(t.Id, t.Title, t.Done, t.DueOn))
            .ToListAsync(cancellationToken);
        return TypedResults.Ok(tasks);
    }

    public static async Task<Results<Ok<TaskDetails>, NotFound>> Get(int id, TaskBoardDb db, HttpContext context, CancellationToken cancellationToken)
    {
        var task = await db.Tasks
            .Where(t => t.Id == id)
            .Select(t => new TaskDetails(t.Id, t.Title, t.Done, t.DueOn, t.Version))
            .SingleOrDefaultAsync(cancellationToken);
        if (task is null)
        {
            return TypedResults.NotFound();
        }

        context.Response.Headers.ETag = ETags.For(task.Version);
        return TypedResults.Ok(task);
    }

    public static async Task<Created<TaskDetails>> Create(NewTask newTask, TaskBoardDb db, CancellationToken cancellationToken)
    {
        var task = new TaskItem { Title = newTask.Title, AssigneeId = newTask.AssigneeId, DueOn = newTask.DueOn, Version = 1 };
        db.Tasks.Add(task);
        await db.SaveChangesAsync(cancellationToken);
        return TypedResults.Created($"/tasks/{task.Id}", new TaskDetails(task.Id, task.Title, task.Done, task.DueOn, task.Version));
    }

    public static async Task<Results<NoContent, NotFound, ProblemHttpResult>> Edit(int id, TaskEdit edit, HttpContext context, TaskBoardDb db, CancellationToken cancellationToken)
    {
        var ifMatch = context.Request.GetTypedHeaders().IfMatch;
        if (ifMatch.Count == 0)
        {
            return TypedResults.Problem("Send the task's ETag in an If-Match header.", statusCode: StatusCodes.Status428PreconditionRequired);
        }

        var task = await db.Tasks.SingleOrDefaultAsync(t => t.Id == id, cancellationToken);
        if (task is null)
        {
            return TypedResults.NotFound();
        }

        if (!ETags.Matches(ifMatch, task.Version))
        {
            return TypedResults.Problem("The task changed after you loaded it. Load it again and reapply your edit.", statusCode: StatusCodes.Status412PreconditionFailed);
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
            return TypedResults.Problem("The task changed after you loaded it. Load it again and reapply your edit.", statusCode: StatusCodes.Status412PreconditionFailed);
        }

        context.Response.Headers.ETag = ETags.For(task.Version);
        return TypedResults.NoContent();
    }

    public static async Task<Results<NoContent, NotFound>> Complete(int id, TaskBoardDb db, CancellationToken cancellationToken)
    {
        var changed = await db.Tasks
            .Where(t => t.Id == id)
            .ExecuteUpdateAsync(s => s
                .SetProperty(t => t.Done, true)
                .SetProperty(t => t.Version, t => t.Version + 1), cancellationToken);
        if (changed == 0)
        {
            return TypedResults.NotFound();
        }

        return TypedResults.NoContent();
    }
}
```

</details>

## How dependencies arrive

A controller receives its dependencies through its constructor, `TasksController(TaskBoardDb db)`, and every action in the class shares them. As the dependency injection article explained, ASP.NET Core creates a new controller for every request, so it also resolves every constructor parameter for every request. A minimal handler lists its own dependencies as parameters, `Get(int id, TaskBoardDb db, …)`, and gets only those.

The difference shows when one action needs something the others don't. Give the controller a `ReminderSender` that logs when it's created, used only by a "remind" action:

```csharp
public class ReminderSender
{
    public ReminderSender(ILogger<ReminderSender> logger)
    {
        logger.LogInformation("ReminderSender created");
    }

    public string Send(int id) => $"reminder for {id}";
}
```

```csharp
public class TasksController(TaskBoardDb db, ReminderSender reminders) : ControllerBase
```

A request to the controller's `complete` action, which never touches `reminders`, still logs "ReminderSender created": the controller needed one to be constructed. The minimal `Complete` handler doesn't list it, so it's never created. For a cheap service that doesn't matter; for one that opens a connection or reads configuration when created, it does. A controller action can ask for a dependency for itself alone with `[FromServices]` on a parameter, the same way a minimal handler does.

## Binding: the same signature, different rules

Both styles fill handler parameters from the request, but not with the same defaults. The opening is the first example.

**A missing `int` in the query string.** Both versions of `List` take `int assigneeId`. Minimal API binding treats a non-nullable parameter as required, so a request without it fails with `400` before the handler runs, empty in `Production`, as the pipeline article showed. MVC model binding fills a missing value with its default instead; its documentation says: "Non-nullable value types are set to `default(T)`. For example, a parameter `int id` is set to 0." So the controller listed the open tasks of user 0, of which there are none, and returned `200 []`. To make the controller reject it, mark the parameter `[BindRequired]`:

```text
HTTP/1.1 400 Bad Request
Content-Type: application/problem+json; charset=utf-8

{"type":"https://tools.ietf.org/html/rfc9110#section-15.5.1","title":"One or more validation errors occurred.","status":400,"errors":{"assigneeId":["A value for the 'assigneeId' parameter or property was not provided."]},…}
```

**A record of filters on a `GET`.** Suppose the list's filters move into `public record TaskFilter(int AssigneeId, DateOnly? DueBefore);`. Written as `MapGet("/search", (TaskFilter filter) => …)`, the minimal app refuses to start:

```text
System.InvalidOperationException: Body was inferred but the method does not allow inferred body parameters.
```

A record parameter defaults to the request body, and `GET` requests don't have one. The controller version starts fine, also treats the record as the body, and answers every request with `415 Unsupported Media Type`. The fixes are `[AsParameters]` on the minimal parameter, which binds the record's properties from the query string, and `[FromQuery]` on the controller's.

**A missing required `string`.** For `string title` with no value, both reject the request with `400`. The minimal response is empty; the controller's is a JSON body naming the field.

**A `PUT` with no body at all.** The minimal endpoint answers `400`, the controller `415`.

None of these is wrong. They're different defaults, and moving an endpoint from one style to the other changes them.

## Validation

`NewTask` marks its title `[Required, StringLength(200)]`. These **DataAnnotations** attributes describe rules; something has to check them.

In a controller, `[ApiController]` checks them automatically before the action runs, and rejects an invalid body with `400` and a problem details body:

```text
HTTP/1.1 400 Bad Request
Content-Type: application/problem+json; charset=utf-8

{"type":"https://tools.ietf.org/html/rfc9110#section-15.5.1","title":"One or more validation errors occurred.","status":400,"errors":{"Title":["The Title field is required."]},…}
```

It's sometimes said that minimal APIs can't validate. Since .NET 10 they can, once you register it:

```csharp
builder.Services.AddValidation();
```

That adds a validation step, generated at compile time, to every minimal endpoint, and it checks bodies, query values, headers, route values, and `[AsParameters]` records. It applies only to minimal APIs; the documentation notes "the API isn't supported for MVC or Razor Pages."

The response shape differs by default:

```text
HTTP/1.1 400 Bad Request
Content-Type: application/json; charset=utf-8

{"title":"One or more validation errors occurred.","errors":{"Title":["The Title field is required."]}}
```

It has the same errors, but no `type` or `status`, and a plain JSON content type. Register the problem details service as well,

```csharp
builder.Services.AddProblemDetails();
```

and the same request gets `Content-Type: application/problem+json` and the same fields as the controller's response.

## Results and error bodies

A controller action returns `ActionResult<TaskDetails>` or `IActionResult`, built with helper methods on `ControllerBase` such as `NotFound()`, `NoContent()`, `Problem(…)`, and `CreatedAtAction(…)`. A minimal handler returns `IResult` values from `TypedResults`, and its return type can list every possible result: `Results<Ok<TaskDetails>, NotFound>`. The compiler then rejects a `return` of anything else. Those types also describe the endpoint's responses to tools that read endpoint metadata.

The second half of the opening comes from here. `[ApiController]` turns every error status code a controller returns into a problem details body, which is why its `404` had JSON. A minimal endpoint sends exactly what the result says: `TypedResults.NotFound()` is a `404` with no body. To give minimal endpoints problem details bodies for error status codes, add `AddProblemDetails()` and a status code pages middleware:

```csharp
builder.Services.AddProblemDetails();
// …
var app = builder.Build();
app.UseStatusCodePages();
```

With both, the minimal `404` becomes:

```text
HTTP/1.1 404 Not Found
Content-Type: application/problem+json

{"type":"https://tools.ietf.org/html/rfc9110#section-15.5.5","title":"Not Found","status":404,…}
```

and the missing `assigneeId` from the opening gets a problem details `400` too.

Two smaller differences:

- **The `Location` header after creating a task.** `CreatedAtAction` builds an absolute URL from the route of `Get`: `Location: http://localhost:5102/tasks/1000004`. `TypedResults.Created($"/tasks/{task.Id}", …)` sends the path you gave it: `Location: /tasks/1000003`.
- **`TypedResults` also work inside a controller action.** But `[ApiController]`'s automatic problem details only apply to MVC's own results, so a controller returning `TypedResults.NotFound()` sends an empty `404`.

## Filters and authorization

The pipeline article showed that controllers have their own filter pipeline and that endpoint filters wrap minimal handlers. Here's one concrete case in both styles: an endpoint that requires a signed-in user and marks its responses `Cache-Control: no-store`.

```csharp
[ApiController]
[Route("mvc/secure/tasks")]
[Authorize]
[NoStore]
public class SecureController : ControllerBase
{
    [HttpGet("{id:int}")]
    public TaskFilter Get(int id) => new(id, null);
}
```

`NoStore` is a small action filter that sets the header:

```csharp
public class NoStoreAttribute : ActionFilterAttribute
{
    public override void OnResultExecuting(ResultExecutingContext context)
    {
        context.HttpContext.Response.Headers.CacheControl = "no-store";
    }
}
```

The minimal version applies both to a route group:

```csharp
var tasks = app.MapGroup("/secure/tasks")
    .RequireAuthorization()
    .AddEndpointFilter(async (context, next) =>
    {
        var result = await next(context);
        context.HttpContext.Response.Headers.CacheControl = "no-store";
        return result;
    });
tasks.MapGet("/{id:int}", (int id) => new TaskFilter(id, null));
```

Both answer `401 Unauthorized` without a signed-in user, and `200` with `Cache-Control: no-store` with one. Setting up how users sign in is outside this article; `AddAuthentication` and `AddAuthorization` were configured the same way for both.

Controllers have more filter kinds than this: resource, exception, and result filters run at different points around an action. Endpoint filters have one kind, which wraps the handler.

## Testing

**Integration tests**, which start the whole app in memory with `WebApplicationFactory<Program>` from the `Microsoft.AspNetCore.Mvc.Testing` package and send it HTTP requests, don't care which style the endpoints use:

```csharp
public class TaskApiTests(WebApplicationFactory<Program> factory) : IClassFixture<WebApplicationFactory<Program>>
{
    [Fact]
    public async Task Get_sends_the_version_as_an_etag()
    {
        var client = factory.CreateClient();

        var response = await client.GetAsync("/tasks/41");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.NotNull(response.Headers.ETag);
    }
}
```

The same file, byte for byte, passes against both projects. (Each `Program.cs` ends with `public partial class Program;` so the test project can refer to it.)

**Unit tests** call a handler directly, without HTTP. A static minimal handler is an ordinary method, so the test calls it and checks the typed result:

```csharp
var context = new DefaultHttpContext();

var result = await TaskEndpoints.Get(41, db, context, CancellationToken.None);

var ok = Assert.IsType<Ok<TaskDetails>>(result.Result);
Assert.Equal(41, ok.Value!.Id);
Assert.Equal($"\"{ok.Value.Version}\"", context.Response.Headers.ETag.ToString());
```

The controller action needs one more step. This test:

```csharp
var controller = new TasksController(db);

var result = await controller.Get(41, CancellationToken.None);
```

fails with `System.NullReferenceException`, at `Response.Headers.ETag`. Inside an action, `Response` comes from the controller's `ControllerContext`, which ASP.NET Core sets when it runs the action and a test has to set itself:

```csharp
var controller = new TasksController(db)
{
    ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() },
};
```

With that, it passes. That's the concrete content of "easier testing": not less testing, but one less thing to set up when a handler touches the HTTP context.

## Speed, startup, memory, and Native AOT

Two beliefs pull in opposite directions here: that controllers are slow, and that switching to minimal APIs makes an API much faster. These numbers come from Release builds on one laptop, with the server limited to four processor cores, a C# load generator on eight others, and PostgreSQL on the same machine, measured over ten-second windows after a warm-up:

| Measurement | Minimal | Controllers |
|---|---|---|
| An endpoint returning a small JSON object, 64 concurrent clients | 118,000 to 135,000 requests/s | 97,000 to 105,000 requests/s |
| `GET /tasks/41` through EF Core, 64 concurrent clients, server CPU saturated | 10,400 to 11,000 requests/s | 9,100 to 9,600 requests/s |
| `GET /tasks/41`, 4 concurrent clients, median response time | 0.64 to 0.71 ms | 0.69 to 0.76 ms |
| Time until ready to serve | 185 to 257 ms | 195 to 284 ms |
| Memory after the first request | about 119 MB | about 122 MB |

The framework difference is real: an endpoint that does almost nothing serves about 25% more requests per second with minimal APIs. Once each request reads from the database through EF Core, the gap shrinks to 10 to 15% at full load and disappears into the noise at light load, because most of each request's time is spent in EF Core and PostgreSQL. A different machine, or a database on another host, will give different numbers; the shape, a small framework cost next to the cost of the work, is what carries over.

**Native AOT** publishing compiles an app to native code ahead of time, for faster startup and less memory. Microsoft's support table lists minimal APIs as partially supported and MVC as not supported. That's literal: a controller app published with `PublishAot` builds, with 91 warnings, and then logs "No action descriptors found" and answers `404` to every controller route. The minimal API AOT template publishes an 11 MB executable. The task board couldn't use it either way, though: EF Core describes its own Native AOT support as "highly experimental" and "not yet suited for production use."

## Both styles in one app

Nothing forces one style per app. Register both:

```csharp
builder.Services.AddControllers();
// …
app.MapControllers();
app.MapTaskEndpoints();
```

Controllers and minimal endpoints then share the routing table, the middleware, and the services. The one thing to avoid is two endpoints with the same method and route, one in each style: routing can't choose. In a small test app that mapped `GET /mvc/search-ok` both as a controller action and with `MapGet`, the request failed with

```text
Microsoft.AspNetCore.Routing.Matching.AmbiguousMatchException: The request matched multiple endpoints. Matches:

HTTP: GET /mvc/search-ok
GotchaController.SearchOk (Gotchas)
```

Moving one endpoint from a controller to a minimal handler is a matter of deleting the action and adding a `Map…` call, then rechecking the three places this article found differences: required values, error bodies, and validation registration. Integration tests that only speak HTTP, like the one above, keep working unchanged and tell you whether anything a client sees has moved.

## When each fits

**Minimal APIs fit:**

- New APIs: they're Microsoft's recommendation for new projects and the template's default.
- Apps that want Native AOT, or the smallest startup time and memory use.
- Endpoints whose dependencies differ, since each handler asks only for what it uses.
- Handlers you want to unit-test as plain methods, with result types that list every response.

**Controllers fit:**

- Apps that need features only MVC provides out of the box:
  - custom model binders through `IModelBinder` or `IModelBinderProvider`; minimal APIs offer `TryParse`, `BindAsync`, and `IBindableFromHttpContext` instead
  - validation through `IModelValidator`
  - application parts and application model conventions
  - OData
  - content negotiation with output formatters: with XML formatters registered, a controller answered `Accept: application/xml` with XML, while a minimal endpoint answered the same request with JSON
  - choosing between actions by request content type with `[Consumes]`
  - resource, exception, and result filters
- Existing controller codebases, and teams that know MVC well, which Microsoft's own page lists.

## Back to the two answers

Neither copy of the API was broken. The minimal version treated a missing `int` as an error because minimal API binding makes non-nullable parameters required; the controller version bound it to `0` because MVC model binding fills missing values with defaults. The minimal `404` was empty because a minimal endpoint sends exactly the result it returns; the controller's `404` had JSON because `[ApiController]` adds problem details to error responses. Both are documented defaults, and both can be changed: `[BindRequired]` on the controller, `AddProblemDetails()` and `UseStatusCodePages()` for minimal endpoints.

What matters is knowing where the defaults differ, especially when an app uses both styles or moves endpoints between them:

| | Minimal APIs | Controllers |
|---|---|---|
| Routes | `Map…` calls, often in a group | attributes, found by `MapControllers()` |
| Dependencies | per handler | per controller, constructed every request |
| Missing non-nullable value | `400` | default value, unless `[BindRequired]` |
| Record parameter on `GET` | startup error without `[AsParameters]` | `415` without `[FromQuery]` |
| DataAnnotations | `AddValidation()` | automatic with `[ApiController]` |
| Error bodies | as returned; problem details with `AddProblemDetails()` | problem details by default |
| Unit tests touching `Response` | pass a `DefaultHttpContext` | set a `ControllerContext` |
| Native AOT | partially supported | not supported |

## Check your understanding

1. **A request leaves out a required `int` query value. Why does the minimal endpoint answer `400` while the controller action runs with `0`?** Minimal API binding treats non-nullable parameters as required and rejects the request before the handler runs. MVC model binding sets missing value types to their default. `[BindRequired]` makes the controller reject it too.
2. **What does a minimal API need before DataAnnotations attributes on a request record reject invalid input?** `builder.Services.AddValidation()`. Adding `AddProblemDetails()` makes the error response a problem details body like MVC's.
3. **A unit test calls a controller action that sets `Response.Headers.ETag`, and it throws `NullReferenceException`. Why?** `Response` comes from the controller's `ControllerContext`, which ASP.NET Core sets only when it runs the action. The test has to set `ControllerContext` with a `DefaultHttpContext` itself.
4. **Your API spends most of each request waiting for PostgreSQL. What would switching styles change in throughput?** Little. The measured gap was about 25% for an endpoint that does nothing and 10 to 15% at full load for one that reads through EF Core, and it vanished at light load, because the database work dominates.

## Sources and further reading

- [APIs overview](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/apis?view=aspnetcore-10.0): Microsoft's recommendation and when to consider controllers.
- [Minimal APIs quick reference](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/minimal-apis?view=aspnetcore-10.0) and [parameter binding in minimal APIs](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/minimal-apis/parameter-binding?view=aspnetcore-10.0).
- [Create web APIs with controllers](https://learn.microsoft.com/en-us/aspnet/core/web-api/?view=aspnetcore-10.0) and [model binding](https://learn.microsoft.com/en-us/aspnet/core/mvc/models/model-binding?view=aspnetcore-10.0).
- [Validation in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/validation?view=aspnetcore-10.0) and [handling errors in APIs](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/error-handling-api?view=aspnetcore-10.0).
- [Integration tests](https://learn.microsoft.com/en-us/aspnet/core/test/integration-tests?view=aspnetcore-10.0) and [testing minimal APIs](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/minimal-apis/test-min-api?view=aspnetcore-10.0).
- [Native AOT support in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/native-aot?view=aspnetcore-10.0).
