---
title: "From bytes to your handler: how ASP.NET Core runs a request"
description: "Follow one task-board request from Kestrel through middleware, routing, parameter binding and filters to your handler, and learn to tell which of those steps sent the response you're looking at."
pubDate: "2026-10-19T09:00:00Z"
tags:
  - aspnet-core
  - dotnet
  - middleware
  - routing
audience:
  - backend
---

You send `GET /tasks/abc` to the task board's API and get back `400 Bad Request`. There's a breakpoint on the first line of the handler for `/tasks/{id}`, and it never hits. Then you mistype the path as `/task/1` and get `404 Not Found`, without a single log line from your code.

Something answered both requests, and it wasn't your handler. Between the moment bytes arrive on the server and the moment your handler runs, ASP.NET Core passes each request through several steps. Any of them can send the response itself and stop there. This article walks through those steps in the order a request meets them, so that when you see a status code, you can say which step sent it.

You'll need to read C# lambdas such as `x => x + 1` and know that a `Func<A, B>` is a function that takes an `A` and returns a `B`. You'll also need basic `async` and `await`: you'll see `await next(context)` a lot. You don't need to know what happens during an `await` to follow along. HTTP requests, responses, methods and status codes are explained in [HTTP from TCP to fetch](/dump/blog/http-from-tcp-to-fetch/). How the app creates and shares services is the subject of [Who creates your services](/dump/blog/aspnet-core-dependency-injection/). Authentication and the format of error responses are outside this article's scope.

## Contents

1. [Set up the example](#set-up-the-example)
2. [Kestrel turns bytes into an HttpContext](#kestrel-turns-bytes-into-an-httpcontext)
3. [The whole app is one function](#the-whole-app-is-one-function)
4. [Build a pipeline by hand](#build-a-pipeline-by-hand)
5. [Routing picks an endpoint, and a later step runs it](#routing-picks-an-endpoint-and-a-later-step-runs-it)
6. [How MapGet turns a lambda into an endpoint](#how-mapget-turns-a-lambda-into-an-endpoint)
7. [Controllers are endpoints too](#controllers-are-endpoints-too)
8. [Filters wrap the handler inside an endpoint](#filters-wrap-the-handler-inside-an-endpoint)
9. [When something throws](#when-something-throws)
10. [Which step answered?](#which-step-answered)

## Set up the example

The examples use the .NET 10 SDK (10.0.402, which ships ASP.NET Core 10.0.13) and `curl` to send requests. Any .NET 10 SDK works. Check yours with:

```bash
dotnet --version
```

The running example is the task board's API: tasks with an `id`, a `title`, and a `done` flag, the same shape the frontend articles use. Tasks live in memory, so they disappear when the app stops.

Create an empty web project:

```bash
dotnet new web -o TaskBoard
cd TaskBoard
```

The template gives you a `Program.cs` with a single "Hello World!" endpoint. You'll replace it piece by piece. Start the app with:

```bash
dotnet run --urls http://localhost:5000
```

`--urls` picks the address, so the `curl` commands below work as written. `dotnet run` also reads `Properties/launchSettings.json`, which sets the **environment** to `Development`. The environment is a name ASP.NET Core reads at startup, and some behavior changes with it. Where that matters, the article shows both `Development` and `Production`. To run as `Production`, skip the launch settings:

```bash
dotnet run --no-launch-profile --urls http://localhost:5000
```

## Kestrel turns bytes into an HttpContext

**Kestrel** is the web server built into ASP.NET Core. When you run the app, Kestrel listens on a port, accepts connections, and reads HTTP messages off them. For each request it reads, ASP.NET Core creates one `HttpContext` object and hands it to your application.

`HttpContext` holds everything about one request and the response being built for it. These are the parts this article uses:

| Property | What it holds |
|---|---|
| `Request` | What the client sent: `Method`, `Path`, `Query`, `Headers`, and `Body` |
| `Response` | What you're sending back: `StatusCode`, `Headers`, and `Body` |
| `RequestAborted` | A `CancellationToken` that fires if the client disconnects before you finish |
| `RequestServices` | The services this request can use: objects the app creates and hands to the code that asks for them |

There's also `User`, which holds who sent the request once authentication has run.

In production, Kestrel can face the internet directly, or it can sit behind a **reverse proxy** such as nginx, IIS, or YARP. A reverse proxy is a server that receives requests first and forwards them to Kestrel. Microsoft supports both setups. The rest of this article starts after that point, at the moment ASP.NET Core has an `HttpContext` in hand.

## The whole app is one function

Here's the part that makes everything else make sense: for each request, ASP.NET Core calls exactly one function. ASP.NET Core gives that function's type a name:

```csharp
public delegate Task RequestDelegate(HttpContext context);
```

A **delegate** is a C# type for "a function with this signature". So a `RequestDelegate` is any function that takes an `HttpContext` and returns a `Task`, which is .NET's object for work that may finish later.

The smallest complete app is one such function. Replace `Program.cs` with:

```csharp
var app = WebApplication.Create(args);

app.Run(context => context.Response.WriteAsync("hello"));

app.Run();
```

The first `app.Run(...)` registers the function, and the second, without arguments, starts the server. (Sharing a name is unfortunate, but they're different methods.) Every request gets `hello`, whatever its method or path:

```bash
curl http://localhost:5000/anything
```

```text
hello
```

A real app does far more than one function could hold neatly. It logs requests, matches paths, reads JSON, checks permissions and handles errors. ASP.NET Core's answer is to build that one function out of many small ones, chained together. The chain is called the **pipeline**, and each link in it is a **middleware**.

## Build a pipeline by hand

The chaining mechanism is small enough to write yourself, and doing it once makes middleware order predictable instead of mysterious. This example doesn't even start a server: it builds a pipeline and calls it directly with fake requests.

Create a second project next to `TaskBoard`:

```bash
dotnet new web -o PipelineByHand
cd PipelineByHand
```

Replace its `Program.cs`. Start with a list of middleware:

```csharp
var components = new List<Func<RequestDelegate, RequestDelegate>>();
```

Each middleware is a `Func<RequestDelegate, RequestDelegate>`: a function that receives **the next step** and returns **a new step that wraps it**. Here's one that logs before and after whatever comes next:

```csharp
components.Add(next => async context =>
{
    Console.WriteLine($"logger: before {context.Request.Path}");
    await next(context);
    Console.WriteLine($"logger: after, status {context.Response.StatusCode}");
});
```

What to notice: `next` is the rest of the pipeline. Code above `await next(context)` runs on the way in, and code below it runs on the way out, after everything later in the chain has finished.

The second middleware answers `/health` by itself and passes every other path along:

```csharp
components.Add(next => context =>
{
    if (context.Request.Path == "/health")
    {
        Console.WriteLine("health: answering");
        context.Response.StatusCode = 200;
        return Task.CompletedTask;
    }

    return next(context);
});
```

What to notice: for `/health`, it never calls `next`. Nothing after it runs. That's called **short-circuiting** the pipeline.

The chain also needs an end: something to run when every middleware has passed the request along. This one answers `404`:

```csharp
RequestDelegate app = context =>
{
    Console.WriteLine("end of pipeline: 404");
    context.Response.StatusCode = 404;
    return Task.CompletedTask;
};
```

Now chain them. Start from the end and wrap backwards:

```csharp
for (var i = components.Count - 1; i >= 0; i--)
{
    app = components[i](app);
}
```

Walk through the loop with the two middleware above:

1. `app` starts as the 404 function.
2. `i = 1`: the health middleware receives the 404 function as its `next` and returns a function that checks for `/health`, then falls through to 404. That becomes `app`.
3. `i = 0`: the logger receives that function as its `next` and returns a function that logs, calls it, and logs again. That becomes `app`.

The result is one `RequestDelegate` with the others nested inside it:

```text
logger
└── health
    └── 404
```

The loop runs in reverse because each middleware needs its `next` to exist before it can wrap it. The first middleware you registered ends up on the outside, so it runs first.

Finally, call the pipeline with two fake requests. `DefaultHttpContext` is the ordinary `HttpContext` class, created here by hand instead of by Kestrel:

```csharp
foreach (var path in new[] { "/health", "/tasks/1" })
{
    var context = new DefaultHttpContext();
    context.Request.Path = path;
    await app(context);
    Console.WriteLine();
}
```

Run it with `dotnet run`:

```text
logger: before /health
health: answering
logger: after, status 200

logger: before /tasks/1
end of pipeline: 404
logger: after, status 404
```

### Order decides what runs

A common assumption is that middleware order doesn't matter as long as everything is registered. Swap the two `components.Add` calls so the health check comes first, and run it again:

```text
health: answering

logger: before /tasks/1
end of pipeline: 404
logger: after, status 404
```

The `/health` request never reaches the logger, because the health middleware answers before calling `next`. Nothing in the code changed except the order, so order is part of what the code means. The rule of thumb that falls out of this: middleware that has to see every request, such as logging or error handling, goes early.

### ASP.NET Core does the same thing

In a real app, you register middleware with `app.Use`:

```csharp
app.Use(async (context, next) =>
{
    // before
    await next(context);
    // after
});
```

`app.Use` adds a component to a list just like `components`. When the app starts, ASP.NET Core builds the pipeline with this loop, from `ApplicationBuilder.Build` in the ASP.NET Core source (shortened):

```csharp
RequestDelegate app = context =>
{
    // ...
    context.Response.StatusCode = StatusCodes.Status404NotFound;
    return Task.CompletedTask;
};

for (var c = _components.Count - 1; c >= 0; c--)
{
    app = _components[c](app);
}

return app;
```

It's the same idea you just wrote: a `404` at the end and a reverse loop that wraps it. So a request that passes through every middleware without anyone answering gets a `404`. Remember that for `/task/1`.

One thing the by-hand version doesn't show: once a middleware starts writing the response body, the status code and headers have already been sent to the client. Code that runs later can't change them anymore. You'll see what that looks like in [When something throws](#when-something-throws).

## Routing picks an endpoint, and a later step runs it

Back in the `TaskBoard` project. Matching paths like `/tasks/{id}` is the job of **routing**, and it introduces the idea the rest of the article builds on: the endpoint.

An **endpoint** is a piece of your app that can handle a request. It has three parts:

- a `RequestDelegate` that does the work;
- a **route pattern**, such as `/tasks/{id}`, plus usually an HTTP method;
- **metadata**: a list of extra facts about the endpoint, such as "requires a logged-in user" or "accepts JSON".

`app.MapGet("/tasks/{id}", ...)` creates an endpoint. So does every other `Map...` call.

Routing happens in two separate pipeline steps:

1. The **routing middleware** looks at the request's method and path, compares them with every endpoint's pattern, and records the best match on the `HttpContext`. It doesn't run anything.
2. The **endpoint middleware**, near the end of the pipeline, runs the recorded endpoint's `RequestDelegate`.

Between those two steps, any middleware can ask which endpoint was selected with `context.GetEndpoint()` and read its metadata. That's how the authorization middleware knows whether this particular endpoint requires a logged-in user before the endpoint runs. CORS works the same way.

### What WebApplication adds for you

You didn't register either routing step yourself. `WebApplication` adds them when you map at least one endpoint. For a `Program.cs` with two `app.Use` calls and some `Map...` calls, the pipeline it builds is effectively:

```csharp
app.UseRouting();    // added first: selects the endpoint
app.Use(/* your first middleware */);
app.Use(/* your second middleware */);
app.UseEndpoints();  // added last: runs the selected endpoint
```

In `Development`, it also puts the **developer exception page** in front of everything; you'll see it later. If you register authentication or authorization services, it adds their middleware right after routing.

You can call `app.UseRouting()` yourself to move routing to a different spot. Middleware placed before it sees `GetEndpoint()` return `null`, because nothing has been selected yet.

### Watch routing work

Replace `TaskBoard/Program.cs` with the beginning of the real app. First, the task data. Add a file `TaskStore.cs`:

```csharp
public record TaskItem(int Id, string Title, bool Done);

public record CreateTaskRequest(string Title);

public static class TaskStore
{
    public static readonly Dictionary<int, TaskItem> Tasks = new()
    {
        [1] = new TaskItem(1, "Read the DOM", false),
    };
}
```

The record is called `TaskItem` because `Task` already means something in .NET: the type `async` methods return. A static dictionary keeps the example short, but it isn't safe when two requests change it at the same time, so treat it as a demo for sending one request at a time.

Then `Program.cs`, starting with two middleware: one that times each request and one that logs which endpoint routing selected:

```csharp
using System.Diagnostics;

var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.Use(async (context, next) =>
{
    var started = Stopwatch.GetTimestamp();
    await next(context);
    var elapsed = Stopwatch.GetElapsedTime(started);
    app.Logger.LogInformation(
        "{Method} {Path} -> {Status} in {Elapsed:F1} ms",
        context.Request.Method, context.Request.Path, context.Response.StatusCode, elapsed.TotalMilliseconds);
});

app.Use(async (context, next) =>
{
    var endpoint = context.GetEndpoint();
    app.Logger.LogInformation("Selected endpoint: {Endpoint}", endpoint?.DisplayName ?? "(none)");
    await next(context);
});
```

`app.Logger` writes to the console. The strings in braces, such as `{Method}`, are placeholders filled from the arguments that follow, in order.

Then the endpoint for one task:

```csharp
app.MapGet("/tasks/{id}", (int id) =>
{
    app.Logger.LogInformation("Handler running for task {Id}", id);
    if (!TaskStore.Tasks.TryGetValue(id, out var task))
    {
        return Results.NotFound();
    }

    return Results.Ok(task);
});

app.Run();
```

Run the app and send two requests, one to a real path and one to the mistyped path:

```bash
curl http://localhost:5000/tasks/1
curl -i http://localhost:5000/task/1
```

The first returns the task as JSON. The second returns `404` with an empty body. The console shows why (log category lines trimmed):

```text
Selected endpoint: HTTP: GET /tasks/{id}
Handler running for task 1
GET /tasks/1 -> 200 in 0.6 ms
Selected endpoint: (none)
GET /task/1 -> 404 in 0.3 ms
```

For `/task/1`, routing found no matching endpoint, so the endpoint middleware had nothing to run and passed the request on. It reached the `404` at the end of the pipeline. That's the first mystery from the opening: your handler never had a chance, because no endpoint matched the path.

## How MapGet turns a lambda into an endpoint

Your lambda `(int id) => ...` isn't a `RequestDelegate`. It takes an `int`, not an `HttpContext`. So when you call `MapGet`, ASP.NET Core generates a `RequestDelegate` around it. That generated function does three things on every request:

1. **Binding**: it reads each of your lambda's parameters from the request and converts it to the right type.
2. It calls your lambda.
3. It writes your lambda's return value into the response.

### Where parameters come from

The generated code decides where each parameter comes from by looking at its name and type, in this order:

1. An explicit attribute, such as `[FromQuery]`, `[FromHeader]` or `[FromBody]`, wins.
2. Special types are filled in directly: `HttpContext`, `CancellationToken` (which receives `RequestAborted`), and a few others.
3. A simple type, such as `int`, `string` or `Guid`, comes from the route if its name matches a placeholder in the pattern, and from the query string otherwise.
4. A type registered with `builder.Services` comes from the app's services.
5. Anything else comes from the request body, read as JSON.

So `int id` comes from the route, because the pattern has `{id}`. If the pattern were `/tasks` and the request were `/tasks?id=1`, the same parameter would come from the query string.

### How return values become responses

| Your lambda returns | The response |
|---|---|
| a `string` | the string as `text/plain`, status `200` |
| an `IResult`, such as `Results.NotFound()` | whatever that result writes; `NotFound` writes `404` |
| any other object | the object serialized as JSON, status `200` |

`Results.Ok(task)` is an `IResult` that writes `200` with the task as JSON.

### Binding fails before your lambda runs

Now the second mystery. Send `abc` as the id:

```bash
curl -i http://localhost:5000/tasks/abc
```

The route pattern `/tasks/{id}` matches any value in that position, so routing selects the endpoint. Then the generated code tries to turn `"abc"` into an `int`, fails, and answers `400` itself. Your lambda never runs:

```text
Selected endpoint: HTTP: GET /tasks/{id}
GET /tasks/abc -> 400 in 0.2 ms
```

What the client sees depends on the environment. In `Production`, it's a `400` with an empty body. In `Development`, the generated code throws an exception instead, and the developer exception page turns it into a `400` that explains exactly what went wrong:

```text
Microsoft.AspNetCore.Http.BadHttpRequestException: Failed to bind parameter "int id" from "abc".
```

That message is the fastest way to recognize a binding failure. (The behavior is controlled by `RouteHandlerOptions.ThrowOnBadRequest`, which defaults to `true` only in `Development`.)

### A route constraint moves the failure into routing

You can make the route itself only match integers by adding a **route constraint**:

```csharp
app.MapGet("/tasks/{id:int}", (int id) => /* same as before */);
```

Now `/tasks/abc` doesn't match the pattern at all. Routing selects no endpoint, and the request falls through to the end of the pipeline:

```text
Selected endpoint: (none)
GET /tasks/abc -> 404 in 0.2 ms
```

Same request, different status, because a different step rejected it. Constraints are for choosing between routes, not for validating input: Microsoft's routing documentation recommends against using them for validation. They're shown here because they change which step answers. Without the constraint, the `400` says "your input is wrong", which is usually what you want.

### Reading a JSON body

Add an endpoint that creates a task. Its parameter is a record, which isn't a simple type, so it comes from the body:

```csharp
app.MapPost("/tasks", (CreateTaskRequest request) =>
{
    var id = TaskStore.Tasks.Count + 1;
    var task = new TaskItem(id, request.Title, false);
    TaskStore.Tasks[id] = task;
    return Results.Created($"/tasks/{id}", task);
});
```

Send it a valid body, a broken body, and a body that isn't JSON:

```bash
curl -i -X POST -H 'Content-Type: application/json' -d '{"title":"Learn middleware"}' http://localhost:5000/tasks
curl -i -X POST -H 'Content-Type: application/json' -d '{"title":' http://localhost:5000/tasks
curl -i -X POST -H 'Content-Type: text/plain' -d 'Learn middleware' http://localhost:5000/tasks
```

The responses are `201 Created`, `400 Bad Request` and `415 Unsupported Media Type`. The logs show that the last two were rejected at different steps:

```text
Selected endpoint: HTTP: POST /tasks
POST /tasks -> 201 in 31.0 ms
Selected endpoint: HTTP: POST /tasks
POST /tasks -> 400 in 3.5 ms
Selected endpoint: 415 HTTP Unsupported Media Type
POST /tasks -> 415 in 0.1 ms
```

The broken JSON got as far as the endpoint, and binding failed while reading it. The `text/plain` request never got that far. When `MapPost` saw a body parameter, it recorded in the endpoint's metadata that the endpoint accepts `application/json`. Routing checks the request's `Content-Type` against that metadata. When no endpoint accepts it, routing selects a small built-in endpoint whose only job is to answer `415`.

## Controllers are endpoints too

If you've worked with ASP.NET Core before, you may know controllers better than `MapGet`. A **controller** is a class whose public methods, called **actions**, handle requests. Here's the same `GET` as a controller, in a file `TasksController.cs`:

```csharp
using Microsoft.AspNetCore.Mvc;

[ApiController]
[Route("mvc/tasks")]
public class TasksController : ControllerBase
{
    [HttpGet("{id}")]
    public ActionResult<TaskItem> Get(int id)
    {
        if (!TaskStore.Tasks.TryGetValue(id, out var task))
        {
            return NotFound();
        }

        return task;
    }
}
```

It uses the path `/mvc/tasks/{id}` because two endpoints with the same method and pattern would make routing fail with an "ambiguous match" error. Register controllers in `Program.cs`:

```csharp
builder.Services.AddControllers();   // before builder.Build()
// ...
app.MapControllers();                // with the other Map calls
```

`MapControllers` finds every action and creates one endpoint for each. They go into the same list of endpoints that routing searches. You can see that list by asking for the `EndpointDataSource` service once the app has started:

```csharp
app.Lifetime.ApplicationStarted.Register(() =>
{
    var endpoints = app.Services.GetRequiredService<EndpointDataSource>().Endpoints;
    foreach (var endpoint in endpoints)
    {
        app.Logger.LogInformation("Endpoint: {Endpoint}", endpoint.DisplayName);
    }
});
```

```text
Endpoint: HTTP: GET /tasks/{id}
Endpoint: HTTP: POST /tasks
Endpoint: TasksController.Get (TaskBoard)
```

Both kinds sit side by side, and everything earlier in this article applies to both: the same middleware runs before them, the same routing selects them, and `GetEndpoint()` works the same way.

The difference is inside the endpoint. A controller endpoint's `RequestDelegate` runs MVC's own sequence of steps: it creates the controller, binds the action's parameters, runs filters (next section), calls the action, and writes the result. MVC binds parameters with its own rules, and `[ApiController]` adds some of its own behavior. For example, `/mvc/tasks/abc` also fails binding before the action runs, but `[ApiController]` answers with a JSON body describing the error, in every environment (shortened here):

```json
{
  "type": "https://tools.ietf.org/html/rfc9110#section-15.5.1",
  "title": "One or more validation errors occurred.",
  "status": 400,
  "errors": { "id": ["The value 'abc' is not valid."] }
}
```

## Filters wrap the handler inside an endpoint

People often think of filters as a controller feature, or as another name for middleware. Both kinds of endpoint support filters, and filters differ from middleware in one important way.

A **filter** wraps your handler the same way middleware wraps the rest of the pipeline: it runs code before and after calling `next`, and it can short-circuit by not calling it. The difference is where it runs. A filter runs inside the endpoint, after routing and after binding. So it sees what middleware can't: your handler's parameters as typed objects, and your handler's return value.

Add a filter to the `POST /tasks` endpoint by chaining `AddEndpointFilter` onto `MapPost`:

```csharp
app.MapPost("/tasks", (CreateTaskRequest request) => { /* same as before */ })
    .AddEndpointFilter(async (context, next) =>
    {
        var request = context.GetArgument<CreateTaskRequest>(0);
        app.Logger.LogInformation("Filter: creating task {Title}", request.Title);
        var result = await next(context);
        app.Logger.LogInformation("Filter: handler returned {Result}", result);
        return result;
    });
```

`GetArgument<CreateTaskRequest>(0)` reads the handler's first parameter, already bound from JSON. Send the valid and broken bodies again:

```text
Selected endpoint: HTTP: POST /tasks
Filter: creating task Learn middleware
Filter: handler returned Microsoft.AspNetCore.Http.HttpResults.Created`1[TaskItem]
POST /tasks -> 201 in 31.0 ms
Selected endpoint: HTTP: POST /tasks
POST /tasks -> 400 in 3.5 ms
```

What to notice:

- The filter reads a `CreateTaskRequest` object, not JSON text.
- It sees the handler's result, a `Created<TaskItem>` object, before anything is written to the response.
- For the broken body, the filter never ran. Binding failed first, so there were no arguments to give it.
- It only applies to this endpoint. To apply a filter to several endpoints at once, put them in a route group with `app.MapGroup("/tasks")` and call `AddEndpointFilter` on the group.

Several filters on one endpoint nest the same way middleware does: the first one added runs first on the way in and last on the way out.

Controllers have their own, older filter system with several kinds of filter, each running at a different point around the action:

```text
Authorization → Resource → (binding) → Action → the action runs → Exception → Result
```

- **Authorization** filters decide whether the request may continue.
- **Resource** filters wrap almost everything, including binding.
- **Action** filters run right before and after the action, and can see its arguments.
- **Exception** filters handle exceptions thrown by the action or its result.
- **Result** filters run around writing the action's result to the response.

Endpoint filters also work on controller actions: `app.MapControllers().AddEndpointFilter(...)` applies one to every action.

### Middleware or filter?

| Use | When |
|---|---|
| Middleware | The work applies to every request, whichever endpoint handles it: request logging, CORS, authentication, error handling |
| A filter | The work needs the handler's typed arguments or its result, or applies only to some endpoints |

For error handling in particular, Microsoft's documentation recommends middleware over filters, because middleware also catches errors thrown before any endpoint runs.

## When something throws

Add an endpoint that fails:

```csharp
app.MapGet("/crash", () =>
{
    throw new InvalidOperationException("Something broke");
});
```

In `Production`, `curl -i http://localhost:5000/crash` gets a `500` with an empty body, and the console shows the exception:

```text
Selected endpoint: HTTP: GET /crash
fail: Microsoft.AspNetCore.Server.Kestrel[13]
      ... An unhandled exception was thrown by the application.
      System.InvalidOperationException: Something broke
```

Two things to notice. Nothing in your code chose `500`: the exception travelled back out through every middleware, and the server sent `500` because nobody handled it. And the timing middleware's log line is missing. The exception came out of `await next(context)`, so the code after that line never ran. Middleware that has to run its "after" code even when something fails needs a `try` and `finally` block around `await next(context)`.

In `Development`, the developer exception page catches the exception first and answers `500` with the exception message and stack trace in the body. That's useful on your machine and dangerous in production, which is why it's only there in `Development`.

### When it's too late to change the status

Earlier you read that once the body starts, the status code is gone. Here's what that looks like. This endpoint writes part of a response and then fails:

```csharp
app.MapGet("/started", async (HttpContext context) =>
{
    await context.Response.WriteAsync("partial");
    throw new InvalidOperationException("Too late");
});
```

```bash
curl -i http://localhost:5000/started
```

```text
HTTP/1.1 200 OK
Server: Kestrel
Transfer-Encoding: chunked

partial
```

The client got `200 OK` and part of a body, while the server logged an unhandled exception. The status line had already been sent when the exception happened, so the server could only cut the connection short. This is one reason handlers usually build their whole result first and write it at the end, which is what returning an `IResult` does.

<details>
<summary>The complete <code>Program.cs</code></summary>

```csharp
using System.Diagnostics;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddControllers();

var app = builder.Build();

app.Use(async (context, next) =>
{
    var started = Stopwatch.GetTimestamp();
    await next(context);
    var elapsed = Stopwatch.GetElapsedTime(started);
    app.Logger.LogInformation(
        "{Method} {Path} -> {Status} in {Elapsed:F1} ms",
        context.Request.Method, context.Request.Path, context.Response.StatusCode, elapsed.TotalMilliseconds);
});

app.Use(async (context, next) =>
{
    var endpoint = context.GetEndpoint();
    app.Logger.LogInformation("Selected endpoint: {Endpoint}", endpoint?.DisplayName ?? "(none)");
    await next(context);
});

app.MapGet("/tasks/{id}", (int id) =>
{
    app.Logger.LogInformation("Handler running for task {Id}", id);
    if (!TaskStore.Tasks.TryGetValue(id, out var task))
    {
        return Results.NotFound();
    }

    return Results.Ok(task);
});

app.MapPost("/tasks", (CreateTaskRequest request) =>
{
    var id = TaskStore.Tasks.Count + 1;
    var task = new TaskItem(id, request.Title, false);
    TaskStore.Tasks[id] = task;
    return Results.Created($"/tasks/{id}", task);
})
.AddEndpointFilter(async (context, next) =>
{
    var request = context.GetArgument<CreateTaskRequest>(0);
    app.Logger.LogInformation("Filter: creating task {Title}", request.Title);
    var result = await next(context);
    app.Logger.LogInformation("Filter: handler returned {Result}", result);
    return result;
});

app.MapGet("/started", async (HttpContext context) =>
{
    await context.Response.WriteAsync("partial");
    throw new InvalidOperationException("Too late");
});

app.MapGet("/crash", () =>
{
    throw new InvalidOperationException("Something broke");
});

app.MapControllers();

app.Lifetime.ApplicationStarted.Register(() =>
{
    var endpoints = app.Services.GetRequiredService<EndpointDataSource>().Endpoints;
    foreach (var endpoint in endpoints)
    {
        app.Logger.LogInformation("Endpoint: {Endpoint}", endpoint.DisplayName);
    }
});

app.Run();
```

</details>

## Which step answered?

Back to the opening. `GET /task/1` got `404` because routing found no endpoint, so the request ran off the end of the pipeline. `GET /tasks/abc` got `400` because routing did find the endpoint, and binding failed to turn `abc` into an `int` before your handler could run. Neither one was your code, and now each has a place in the request's path.

When a response surprises you, find the step that sent it:

| You see | The step that answered | Where to look |
|---|---|---|
| No response at all | The network, or Kestrel never got the request | The address and port; [HTTP from TCP to fetch](/dump/blog/http-from-tcp-to-fetch/) |
| `404`, and the handler never ran | Routing matched no endpoint | `Selected endpoint`, the route pattern, its constraints, the HTTP method |
| `400`, and the handler never ran | Binding | The developer exception page in `Development`; parameter names and types |
| `415` | Routing, because the endpoint doesn't accept that `Content-Type` | The request's `Content-Type` header |
| `401` or `403` | Authentication or authorization middleware | The request's credentials and the endpoint's authorization requirements |
| `500` | An exception nobody handled | The console log; the developer exception page |
| A status from your handler | Your handler | Your code, finally |

A log line in early middleware that prints the selected endpoint, like the one in this article, answers most of these at a glance.

## Check your understanding

1. **Middleware A is registered first and logs before and after calling `next`. Middleware B is registered second and returns without calling `next`. What does A log?** Both lines. A wraps B, so A's code runs before B, B returns, and then A's code after `next` runs. If the order were reversed, A wouldn't run at all.
2. **Why does `/tasks/abc` get `400` with the pattern `/tasks/{id}`, but `404` with `/tasks/{id:int}`?** Without the constraint, routing matches the endpoint and binding fails to convert `abc`. With the constraint, routing doesn't match it at all, and the request reaches the `404` at the end of the pipeline.
3. **How can a middleware know which endpoint will handle the request before that endpoint runs?** Routing and running are separate steps. The routing middleware records the selected endpoint on the `HttpContext`, and any middleware after it can read it with `GetEndpoint()`.
4. **A check needs the parsed request body and applies to three endpoints. Middleware or filter?** A filter, attached to the three endpoints or to a route group containing them. Middleware runs before binding, so it would have to read and parse the body itself, and it would run for every request.

## Sources and further reading

- [ASP.NET Core middleware](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/middleware/?view=aspnetcore-10.0): `Use`, `Run`, short-circuiting, the middleware `WebApplication` adds, and recommended order.
- [Routing in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/routing?view=aspnetcore-10.0): selecting versus running endpoints, `GetEndpoint`, metadata, and route constraints.
- [Parameter binding in minimal APIs](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/minimal-apis/parameter-binding?view=aspnetcore-10.0): where each parameter comes from and what happens when binding fails.
- [Responses in minimal APIs](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/minimal-apis/responses?view=aspnetcore-10.0): how return values become responses.
- [Filters in minimal APIs](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/minimal-apis/min-api-filters?view=aspnetcore-10.0) and [filters in controllers](https://learn.microsoft.com/en-us/aspnet/core/mvc/controllers/filters?view=aspnetcore-10.0).
- [Kestrel](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/servers/kestrel?view=aspnetcore-10.0): the web server, and when to put a reverse proxy in front of it.
- [`ApplicationBuilder.Build` in the ASP.NET Core source](https://github.com/dotnet/aspnetcore/blob/release/10.0/src/Http/Http/src/Builder/ApplicationBuilder.cs): the loop that builds the pipeline.
