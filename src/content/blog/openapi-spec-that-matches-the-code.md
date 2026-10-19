---
title: "The spec says 200, the endpoint sends 204: an OpenAPI document that matches your ASP.NET Core code"
description: "Find where ASP.NET Core's generated OpenAPI document and your endpoints disagree, declare the responses your code, middleware, and framework send in both controllers and minimal APIs, and make every API change show up in code review."
pubDate: "2026-10-19"
updatedDate: "2026-10-20"
tags:
  - aspnet-core
  - openapi
  - dotnet
  - http
audience:
  - backend
---

Here's what the task board's OpenAPI document says the controller version's `PUT /tasks/{id}` can answer:

```json
"responses": {
  "200": {
    "description": "OK"
  }
}
```

And here's what the endpoint actually answers, depending on the request:

```text
HTTP/1.1 204 No Content
HTTP/1.1 404 Not Found         Content-Type: application/problem+json
HTTP/1.1 412 Precondition Failed      Content-Type: application/problem+json
HTTP/1.1 428 Precondition Required    Content-Type: application/problem+json
```

The endpoint never sends `200`, and the document mentions none of the four responses it does send. A client generated from this document treats `412` as an unknown error, so the editor's "someone else saved first" handling from [the transactions article](/dump/blog/transactions-and-concurrent-edits/) never runs, and nobody notices until a user hits it.

ASP.NET Core generated that document from the code. So where did the `200` come from, and where did the other four go? This article finds out, for both the controller and the minimal API versions of the task board, and then shows how to declare what each endpoint really sends and how to catch the next mismatch in code review.

You'll need [Controllers and minimal APIs compared](/dump/blog/controllers-and-minimal-apis/), whose two versions of the API this article uses unchanged, including their `TypedResults` and problem details setup. [The transactions article](/dump/blog/transactions-and-concurrent-edits/) explains why `PUT` answers `412` and `428`, and [From bytes to your handler](/dump/blog/aspnet-core-request-pipeline/) explains the `400` and `415` responses that come from binding and routing. [gRPC for frontend developers](/dump/blog/grpc-onboarding/) shows what an OpenAPI document looks like and what a client generated from one does. You should be able to read a `git diff`.

## Contents

1. [Set up the example](#set-up-the-example)
2. [Where the document's responses come from](#where-the-documents-responses-come-from)
3. [The task board's document, endpoint by endpoint](#the-task-boards-document-endpoint-by-endpoint)
4. [Declaring responses by hand](#declaring-responses-by-hand)
5. [API analyzers and conventions for controllers](#api-analyzers-and-conventions-for-controllers)
6. [Typed results describe themselves, in both styles](#typed-results-describe-themselves-in-both-styles)
7. [Responses your handler never sends](#responses-your-handler-never-sends)
8. [One transformer for responses that follow from metadata](#one-transformer-for-responses-that-follow-from-metadata)
9. [Request schemas can drift too](#request-schemas-can-drift-too)
10. [Generate the document at build time and review the diff](#generate-the-document-at-build-time-and-review-the-diff)
11. [Back to the 200](#back-to-the-200)

## Set up the example

The examples use the .NET 10 SDK (ASP.NET Core 10.0.13), Microsoft.AspNetCore.OpenApi 10.0.13, Microsoft.Extensions.ApiDescription.Server 10.0.13, and the previous article's EF Core, Npgsql, and PostgreSQL versions, in the `Production` environment. Security schemes, documentation comments, and generating clients are outside this article's scope.

Both versions of the API get the same three additions:

```bash
dotnet add package Microsoft.AspNetCore.OpenApi --version 10.0.13
```

```csharp
builder.Services.AddOpenApi();
// …
var app = builder.Build();
app.MapOpenApi();
```

`GET /openapi/v1.json` now returns the document, in OpenAPI version 3.1.1. The `dotnet new webapi` template wraps `app.MapOpenApi()` in `if (app.Environment.IsDevelopment())`; that's a choice the template makes, and without the `if`, the document is served in every environment.

Integer properties in the document look noisier than you might expect:

```json
"schema": {
  "pattern": "^-?(?:0|[1-9]\\d*)$",
  "type": ["integer", "string"],
  "format": "int32"
}
```

That's accurate: ASP.NET Core's JSON settings for web APIs accept numbers written as strings, so `{"assigneeId":"5"}` is accepted. The excerpts below leave this out.

## Where the document's responses come from

An **OpenAPI document** describes an HTTP API: its paths, parameters, request bodies, and the responses each operation can send. Tools read it to generate clients, render documentation pages, and run mock servers. The frontend in [One task, different models](/dump/blog/api-responses-to-ui-models/) checks every response at runtime instead of trusting a type, and a document like the opening's is one reason.

It's easy to assume that a document generated from the code must be right. But look at what the generator can see. When the app starts, ASP.NET Core builds a description of each endpoint from what it can find **without running anything**:

1. The handler's declared return type, such as `ActionResult<TaskDetails>` or `Results<Ok<TaskDetails>, NotFound>`.
2. Metadata that some result types add about themselves.
3. Attributes and extension method calls that declare responses, which later sections show.

Microsoft.AspNetCore.OpenApi turns those descriptions into the JSON document. Your handler never runs during any of this, so a status code your code chooses at runtime, like `return NoContent();` inside an `if`, is invisible to it.

And when an endpoint declares no responses at all, ASP.NET Core's code fills in a default, with this comment in its source: "Set the default status only when no status has already been set explicitly." The default is `200`. That's where the opening's `200` came from.

The OpenAPI specification sets the target: "The documentation is expected to cover a successful operation response and any known errors."

## The task board's document, endpoint by endpoint

Here's what each version's generated document lists, next to what both versions actually sent:

| Endpoint | Minimal document | Controller document | Actually sent |
|---|---|---|---|
| `GET /tasks` | 200 | 200 | 200; the minimal version also sends 400 without `assigneeId` |
| `GET /tasks/{id}` | 200, 404 (no body) | 200 | 200, 404 with a problem body |
| `POST /tasks` | 201 | 200 | 201, 400 from validation, 415 |
| `PUT /tasks/{id}` | 204, 404 | 200 | 204, 404, 412, 428 |
| `POST /tasks/{id}/complete` | 204, 404 | 200 | 204, 404 |

What to notice:

- **`ActionResult<TaskDetails>` documents one response:** a `200` with the `TaskDetails` schema. That's why the controller's `Create` claims `200` though it sends `201`.
- **`IActionResult` documents a bare `200`**, with no schema, because it could be anything.
- **The minimal version's `Results<…>` types do better:** `Results<NoContent, NotFound, ProblemHttpResult>` lists `204` and `404`. But `ProblemHttpResult` adds no status code, because its status is only known when the handler runs it, so `412` and `428` are missing here too.
- **The minimal `404` is documented without a body**, because `TypedResults.NotFound()` has none, but `UseStatusCodePages()` adds a problem body when the response is sent.
- **Parameters match their binding rules.** `assigneeId` is `"required": true` in the minimal document and optional in the controller's, which matches what the previous article found: MVC binds a missing `int` to `0`.
- **The controller's responses list three content types:** `text/plain`, `application/json`, and `text/json`, from MVC's output formatters. A request with `Accept: text/plain` still got JSON.

A related belief is that returning `IResult` documents itself. The untyped `Results` helpers don't: a handler that returns `Results.Ok(task)` or `Results.NotFound()` as `IResult` gets a bare `200`, the same as `IActionResult`. Only the `TypedResults` types, used in a return type that names them, add response metadata.

## Declaring responses by hand

The oldest fix is to declare the responses next to the handler. In a controller, that's `[ProducesResponseType]`:

```csharp
[HttpPut("{id:int}")]
[ProducesResponseType(StatusCodes.Status204NoContent)]
[ProducesResponseType(StatusCodes.Status404NotFound)]
[ProducesResponseType(StatusCodes.Status412PreconditionFailed)]
[ProducesResponseType(StatusCodes.Status428PreconditionRequired)]
public async Task<IActionResult> Edit(int id, TaskEdit edit, CancellationToken cancellationToken)
```

On a minimal endpoint, it's a set of extension methods on the `Map…` call:

```csharp
tasks.MapPut("/{id:int}", Edit)
    .ProducesProblem(StatusCodes.Status404NotFound)
    .ProducesProblem(StatusCodes.Status412PreconditionFailed)
    .ProducesProblem(StatusCodes.Status428PreconditionRequired);
```

`ProducesProblem` declares a problem details response with the `application/problem+json` content type; `Produces<T>(status)` declares any other. With these, both documents list `204`, `404`, `412`, and `428` for `PUT`.

Many developers expect the compiler to check those declarations against the code. It doesn't, and Microsoft's documentation says so: "By default, there are no compile-time checks to ensure that the response metadata specified with a `[ProducesResponseType]` attribute is consistent with the actual behavior of the action method." The minimal API methods are the same: they "only set the response metadata for the endpoint."

Here's that in practice. The controller's `Complete` action declares `204` and `404`. Someone changes it to return the updated task:

```csharp
var task = await db.Tasks
    .Where(t => t.Id == id)
    .Select(t => new TaskSummary(t.Id, t.Title, t.Done, t.DueOn))
    .SingleAsync(cancellationToken);
return Ok(task);
```

It compiles without a warning, and the document still says `204`.

### Declaring one response removes the default 200

Declarations replace what ASP.NET Core would infer; they don't add to it. Give the controller's `Get`, which returns `ActionResult<TaskDetails>`, only a `404`:

```csharp
[HttpGet("{id:int}")]
[ProducesResponseType(StatusCodes.Status404NotFound)]
public async Task<ActionResult<TaskDetails>> Get(int id, CancellationToken cancellationToken)
```

and the document lists only `404`: the `200` it inferred from `ActionResult<TaskDetails>` is gone. The same happens with a `[ProducesResponseType]` on the controller class, which removes the `200` from every `ActionResult<T>` action in it, and on the minimal side, to a handler declared as returning `IResult` once its group declares any response. Declare the success response too: `[ProducesResponseType(StatusCodes.Status200OK)]` on an `ActionResult<TaskDetails>` action documents the `TaskDetails` schema by itself.

### Content types

Controller error declarations default to the same three content types as successes, `text/plain`, `application/json`, and `text/json`, with a `ProblemDetails` schema. The real body is `application/problem+json`. Say so in the attribute:

```csharp
[ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound, "application/problem+json")]
```

Don't reach for MVC's `[Produces("application/json")]` attribute to clean this up: it's a filter that changes the actual response, not just the document, so the real `404` started arriving as `application/json`. On minimal endpoints, `Produces` only describes.

## API analyzers and conventions for controllers

For controllers, ASP.NET Core has offered compile-time help. Setting `<IncludeOpenAPIAnalyzers>true</IncludeOpenAPIAnalyzers>` in the project file turns on analyzers that compare an action's `return` statements with its declarations. On the undecorated `TasksController`, the build warns:

```text
warning API1000: Action method returns undeclared status code '201'
warning API1000: Action method returns undeclared status code '204'
warning API1000: Action method returns undeclared status code '404'
```

It says nothing about `412` and `428`, because those come from `Problem(…, statusCode: …)`, where the status is an argument rather than part of the method called. It doesn't see the automatic validation `400` either. And the same build prints:

```text
warning ASPDEPR007: The IncludeOpenAPIAnalyzers property and its associated MVC API analyzers are deprecated and will be removed in a future release.
```

They're deprecated as of .NET 10. Microsoft's breaking change notice recommends: "Migrate to the TypedResults pattern."

**Conventions**, `[ApiConventionType(typeof(DefaultApiConventions))]`, declare typical responses for actions by name and shape. They matched none of the task board's actions, because conventions match by parameter count and every action here also takes a `CancellationToken`. The documentation also notes that conventions don't compose: an action gets one convention or none.

## Typed results describe themselves, in both styles

The `TypedResults` types do something attributes can't: they're the values the handler returns and their own declarations at the same time. `Results<Ok<TaskDetails>, NotFound>` in a return type tells the compiler what the handler may return, and each of those types adds its own response to the endpoint's metadata. Return anything else, and the code doesn't compile.

Since .NET 10, that works in controllers too. Here's the controller's `Get` with typed results:

```csharp
[HttpGet("{id:int}")]
public async Task<Results<Ok<TaskDetails>, NotFound>> Get(int id, CancellationToken cancellationToken)
{
    var task = await db.Tasks
        .Where(t => t.Id == id)
        .Select(t => new TaskDetails(t.Id, t.Title, t.Done, t.DueOn, t.Version))
        .SingleOrDefaultAsync(cancellationToken);
    if (task is null)
    {
        return TypedResults.NotFound();
    }

    Response.Headers.ETag = ETags.For(task.Version);
    return TypedResults.Ok(task);
}
```

A controller written this way produced the same document entries as the minimal version. If you read older posts saying typed results don't document controller actions, they were right at the time; .NET 10 added it.

Typed results have limits, in both styles:

- **`ProblemHttpResult` doesn't know its status.** `TypedResults.Problem(…, statusCode: 412)` can return any status, so `412` and `428` still need declaring by hand. Typed results and declarations add up: on a typed controller action, `[ProducesResponseType<ProblemDetails>(StatusCodes.Status412PreconditionFailed, "application/problem+json")]` adds `412` to the typed responses, and on a minimal endpoint, `.ProducesProblem(412)` does the same.
- **A declared type that's never returned is still documented.** The compiler checks that you return only listed types, not that you return each of them.
- **In a controller, a typed `404` has an empty body.** As the previous article found, MVC's automatic problem details apply only to MVC's own results, so switching a controller from `NotFound()` to `TypedResults.NotFound()` changes the body clients get. Declare and send what you mean: `.ProducesProblem(404)` with a problem body, or the empty `404` you now return.

## Responses your handler never sends

Some responses come from middleware and the framework, before or after your handler runs. Each needs declaring where it applies:

| Response | Who sends it | Body in this setup | Minimal API | Controller |
|---|---|---|---|---|
| `400`, missing or unparseable value | parameter binding | problem details, with `AddProblemDetails` and `UseStatusCodePages` | `.ProducesProblem(400)` | MVC binds defaults instead, as the previous article showed |
| `400`, validation | `AddValidation()` or `[ApiController]` | validation problem details | `.ProducesValidationProblem()` | `[ProducesResponseType<ValidationProblemDetails>(400, "application/problem+json")]` |
| `404` body | `UseStatusCodePages()` | problem details | `.ProducesProblem(404)`, which replaces `NotFound`'s empty entry | already a problem body |
| `415` | routing | problem details | the `requestBody` already lists accepted content types | same |
| `401` | authorization middleware | empty | see the next section | see the next section |
| `500` | an unhandled exception | empty by default; problem details with `UseExceptionHandler()` and `AddProblemDetails()` | `.ProducesProblem(500)` on the group | an attribute on the class, with typed results |

For a whole group of minimal endpoints, `ProducesProblem` and `ProducesValidationProblem` work on the group, `app.MapGroup("/tasks").ProducesProblem(StatusCodes.Status500InternalServerError)`, but the plain `Produces(…)` doesn't exist for groups and fails to compile, whatever the documentation suggests. A `403` only happens when a rule checks more than "signed in", such as a role, so declare it only for those endpoints. OpenAPI also has a `default` response for "anything not listed"; naming the real responses tells clients more.

## One transformer for responses that follow from metadata

A `401` belongs on every endpoint that requires a signed-in user, and adding it by hand to each one is exactly the kind of declaration that gets forgotten on the next new endpoint. The OpenAPI package lets you change each operation as it's generated, with an **operation transformer**. This one reads the same endpoint metadata the authorization middleware uses:

```csharp
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.OpenApi;
using Microsoft.OpenApi;

public class UnauthorizedResponses : IOpenApiOperationTransformer
{
    public Task TransformAsync(OpenApiOperation operation, OpenApiOperationTransformerContext context, CancellationToken cancellationToken)
    {
        var metadata = context.Description.ActionDescriptor.EndpointMetadata;
        var requiresUser = metadata.OfType<IAuthorizeData>().Any() && !metadata.OfType<IAllowAnonymous>().Any();
        if (requiresUser)
        {
            operation.Responses ??= new();
            operation.Responses.TryAdd("401", new OpenApiResponse { Description = "Unauthorized" });
        }

        return Task.CompletedTask;
    }
}
```

```csharp
builder.Services.AddOpenApi(options => options.AddOperationTransformer<UnauthorizedResponses>());
```

What to notice:

- **`IAuthorizeData`** is what both `[Authorize]` on a controller and `RequireAuthorization()` on a group add to an endpoint's metadata, so the same transformer works for both styles. With `RequireAuthorization()` on the minimal `/tasks` group and `[Authorize]` on `TasksController`, every operation in both documents gained a `401`.
- **`IAllowAnonymous`** is what `[AllowAnonymous]` and `AllowAnonymous()` add, for endpoints that opt out.
- **The types come from `Microsoft.OpenApi`**, version 2 of that library. Older samples use `Microsoft.OpenApi.Models`, from version 1, which no longer compiles.

If you're coming from older tutorials: `WithOpenApi()`, once the way to change a single minimal endpoint's operation, is deprecated in .NET 10; `AddOpenApiOperationTransformer` on the endpoint replaces it.

## Request schemas can drift too

The document describes requests as well as responses. `NewTask` is a positional record:

```csharp
public record NewTask([Required, StringLength(200)] string Title, int? AssigneeId, DateOnly? DueOn);
```

Validation enforces the 200-character limit, but the document's schema for it doesn't mention it:

```json
"NewTask": {
  "required": ["title", "assigneeId", "dueOn"],
  "properties": {
    "title": { "type": "string" },
    …
```

Two things are wrong: there's no `maxLength`, and `assigneeId` and `dueOn` are listed as required although the API accepts requests without them, because positional parameters without default values count as required. The missing `maxLength` is an open ASP.NET Core issue at the time of writing.

A record with properties instead of constructor parameters describes itself correctly:

```csharp
public record NewTask
{
    [Required, StringLength(200)]
    public required string Title { get; init; }

    public int? AssigneeId { get; init; }

    public DateOnly? DueOn { get; init; }
}
```

Both documents then show `"required": ["title"]` and `"maxLength": 200`, and both versions still reject a 201-character title with a validation `400`. The C# `required` keyword means a body without `title` now fails while the JSON is read, before validation: the minimal version answers with a plain `400` problem, the controller with a validation problem naming the missing property.

## Generate the document at build time and review the diff

Everything so far fixes the document today. Keeping it right means noticing when it changes, and the place people notice changes is code review. For that, the document has to be a file in the repository.

Add the build-time generator, and tell it where to write:

```bash
dotnet add package Microsoft.Extensions.ApiDescription.Server --version 10.0.13
```

```xml
<PropertyGroup>
  <OpenApiDocumentsDirectory>openapi</OpenApiDocumentsDirectory>
</PropertyGroup>
```

Every `dotnet build` now writes `openapi/TaskBoard.json`, the same document `/openapi/v1.json` serves, minus the `servers` section that depends on where the app runs. Commit it. To produce it, the build starts your app's `Program.cs` far enough to read its endpoints, so startup code that connects to a database or another service needs to tolerate running at build time; Microsoft's documentation shows how to detect it.

Now change the minimal `Complete` handler to return the updated task, declared with typed results:

```csharp
public static async Task<Results<Ok<TaskSummary>, NotFound>> Complete(int id, TaskBoardDb db, CancellationToken cancellationToken)
```

and build. `git diff --stat` shows two files:

```text
 TaskEndpoints.cs       |  8 ++++++--
 openapi/TaskBoard.json | 11 +++++++++--
```

and the document's part of the diff says exactly what clients will see:

```diff
         "responses": {
-          "204": {
-            "description": "No Content"
+          "200": {
+            "description": "OK",
+            "content": {
+              "application/json": {
+                "schema": {
+                  "$ref": "#/components/schemas/TaskSummary"
+                }
+              }
+            }
           },
```

A reviewer sees that `complete` stopped answering `204` and started returning a `TaskSummary`, and can ask whether clients are ready. The typed controller version shows the same two files.

Make the same change in the controller that declares its responses with attributes, without touching the attributes, and `git diff --stat` shows one file:

```text
 TasksController.cs | 6 +++++-
```

The document didn't change, because the attributes didn't, so the reviewer sees nothing about the API at all. Attributes stay a valid way to document controllers; this is the cost to know about: a declaration only shows up in review when someone changes the declaration.

To make sure the committed document is never stale, run the build in continuous integration and fail if it changed anything:

```bash
dotnet build
git diff --exit-code -- openapi/
```

`git diff --exit-code` exits with `1` when the regenerated document differs from the committed one, which fails the pipeline until someone commits it. Tools such as `oasdiff` can compare two documents and flag breaking changes, and Spectral can check a document against rules.

Many people think of the documentation page, Swagger UI or Scalar, as the spec. Those are viewers; the document is the JSON file they render, and it's the file that clients and tools use. Either can be added for Development, and neither is set up by default anymore.

## Back to the 200

The opening's `200` was ASP.NET Core's default, filled in because `Edit` returns `IActionResult` and declared nothing. The four real responses, `204`, `404`, `412`, and `428`, were all decided inside the method at runtime, where the generator never looks. Nothing was hidden; the document simply couldn't know.

So the document matches the code only where the code declares itself:

| Where a response comes from | Minimal API | Controller |
|---|---|---|
| A result your handler returns | `TypedResults` in the return type | `TypedResults` in the return type, or `[ProducesResponseType]` |
| A status your code picks at runtime, like `412` | `.ProducesProblem(412)` | `[ProducesResponseType<ProblemDetails>(412, "application/problem+json")]` |
| Binding and validation | `.ProducesProblem(400)`, `.ProducesValidationProblem()` | `[ProducesResponseType<ValidationProblemDetails>(400, …)]` |
| Authorization | the `401` transformer | the `401` transformer |
| Unhandled exceptions | `.ProducesProblem(500)` on the group | a class attribute, with typed results |
| Request bodies | records with `init` properties | records with `init` properties |

and the committed, build-generated document turns every change to any of these into a diff someone reviews.

## Check your understanding

1. **What does an action declared as returning `IActionResult`, with no attributes, document, and why?** A single `200` with no schema. The generator can't see which results the method returns at runtime, and when nothing is declared, ASP.NET Core fills in a default `200`.
2. **You add `[ProducesResponseType(404)]` to an action that returns `ActionResult<TaskDetails>`. What happens to its `200`?** It disappears. Declared responses replace the inferred one, so declare the `200` as well.
3. **An endpoint returns `Results<NoContent, NotFound, ProblemHttpResult>` and sends `412` through `TypedResults.Problem`. Why is `412` missing from the document?** `ProblemHttpResult` can carry any status, so it adds no specific status to the metadata. Declare `412` with `ProducesProblem` or an attribute.
4. **The `complete` endpoint changes from `204` to returning a task. With typed results and a committed, build-generated document, what does the reviewer see? With attributes left unchanged?** With typed results, a diff in `openapi/TaskBoard.json` showing `204` replaced by `200` with a schema. With unchanged attributes, only the C# change: the document didn't change, so the API change isn't visible.

## Sources and further reading

- [OpenAPI support in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/openapi/overview?view=aspnetcore-10.0) and [generating OpenAPI documents](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/openapi/aspnetcore-openapi?view=aspnetcore-10.0), including build-time generation.
- [Include OpenAPI metadata](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/openapi/include-metadata?view=aspnetcore-10.0): responses for minimal APIs and controllers.
- [Customize OpenAPI documents](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/openapi/customize-openapi?view=aspnetcore-10.0): transformers.
- [Controller action return types](https://learn.microsoft.com/en-us/aspnet/core/web-api/action-return-types?view=aspnetcore-10.0) and [responses in minimal APIs](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/minimal-apis/responses?view=aspnetcore-10.0).
- [API analyzers deprecated](https://learn.microsoft.com/en-us/aspnet/core/breaking-changes/10/openapi-analyzers-deprecated?view=aspnetcore-10.0) and [`WithOpenApi` deprecated](https://learn.microsoft.com/en-us/aspnet/core/breaking-changes/10/withopenapi-deprecated?view=aspnetcore-10.0).
- [OpenAPI 3.1.1: the Responses Object](https://spec.openapis.org/oas/v3.1.1.html#responses-object).
