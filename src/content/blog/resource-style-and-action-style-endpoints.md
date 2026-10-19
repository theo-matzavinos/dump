---
title: "Same task board, two shapes: resource-style and action-style endpoints in ASP.NET Core"
description: "Build a task search and task completion as resource-style and as action-style endpoints, check what REST and HTTP actually say about POST, and compare what changes for binding, URL limits, caching, logs, client code, and the OpenAPI document."
pubDate: "2026-10-20"
tags:
  - aspnet-core
  - http
  - dotnet
  - api-design
audience:
  - backend
---

The task board's list endpoint started as `GET /tasks?done=false`. Then people asked for more filters: tags, assignees, a due date range, and a text search. Each one became another query parameter:

```text
GET /tasks?done=false&tags=bug&tags=ui&assigneeIds=3&assigneeIds=7&dueFrom=2026-11-01&dueTo=2026-11-30&text=login
```

Someone proposes sending the filters as JSON instead, with `POST /tasks/search`. The answer comes back: "That's not allowed in REST. `POST` is for creating things." The same argument comes up for `POST /tasks/{id}/complete`, which the task board already has: shouldn't completing a task be a `PATCH` that sets `done` to `true`?

Is that rule real? And if you pick one shape over the other, what actually changes for the server, the browser, and the code that calls the API? This article builds the search and task completion both ways and compares them.

You'll need [Controllers and minimal APIs compared](/dump/blog/controllers-and-minimal-apis/), whose minimal API version of the task board this article extends, and [the OpenAPI article](/dump/blog/openapi-spec-that-matches-the-code/), which explains how ASP.NET Core generates the document and why records with `init` properties describe requests correctly. [The transactions article](/dump/blog/transactions-and-concurrent-edits/) built the ETag and `If-Match` handling used for edits. [HTTP from TCP to fetch](/dump/blog/http-from-tcp-to-fetch/) covers HTTP methods and CORS, and the frontend parts assume you've seen Angular's `HttpClient`.

## Contents

1. [Set up the example](#set-up-the-example)
2. [Two ways to shape the same API](#two-ways-to-shape-the-same-api)
3. [What REST means](#what-rest-means)
4. [What HTTP and Fielding say about POST](#what-http-and-fielding-say-about-post)
5. [Why not GET with a body](#why-not-get-with-a-body)
6. [Searching both ways](#searching-both-ways)
7. [Caching, logs, and history](#caching-logs-and-history)
8. [Completing a task both ways](#completing-a-task-both-ways)
9. [Client code and the OpenAPI document](#client-code-and-the-openapi-document)
10. [When each fits](#when-each-fits)
11. [Back to the query string](#back-to-the-query-string)

## Set up the example

The examples use the .NET 10 SDK (ASP.NET Core 10.0.13), Microsoft.AspNetCore.OpenApi 10.0.13 with the build-time document from the OpenAPI article, Microsoft.AspNetCore.JsonPatch.SystemTextJson 10.0.13, the earlier articles' EF Core and Npgsql versions, and PostgreSQL 18.6, in the `Production` environment. The browser checks use Chromium 152, Node.js 24, and Angular 22.2. Hypermedia formats, idempotency keys and retries, pagination, and authorization are outside this article's scope.

Tasks get tags and a completion time:

```sql
alter table tasks add column tags text[] not null default '{}';
alter table tasks add column completed_at timestamptz;
```

```csharp
public class TaskItem
{
    // …existing properties
    public DateTime? CompletedAt { get; set; }
    public string[] Tags { get; set; } = [];
}
```

Npgsql maps a PostgreSQL `text[]` column to a C# `string[]` without extra configuration. The response records gain the new fields:

```csharp
public record TaskDetails(int Id, string Title, bool Done, DateOnly? DueOn, DateTime? CompletedAt, string[] Tags, int Version);

public record TaskSummary(int Id, string Title, bool Done, DateOnly? DueOn, string[] Tags);
```

Notice that the task board already mixes the two shapes this article compares: `PUT /tasks/{id}` edits a task, and `POST /tasks/{id}/complete` completes one.

## Two ways to shape the same API

Every HTTP request carries a method and a URL. The URL picks what the request is aimed at, and the method says what to do with it. The two shapes split that work differently.

In a **resource-style** API, URLs name things: the collection `/tasks`, or one task, `/tasks/42`. A small set of methods does everything: `GET` reads, `POST` creates, `PUT` replaces, `PATCH` changes part of a resource, and `DELETE` removes. An operation such as completing a task is expressed as a change to the task's fields.

In an **action-style** API, URLs name operations: `/tasks/search`, `/tasks/42/complete`. Plain reads stay `GET`, and everything else is a `POST` to the operation's URL.

```text
Resource-style
GET    /tasks?done=false&tags=bug                                 search
GET    /tasks/42                                                  read one task
PUT    /tasks/42   { "title": …, "dueOn": …, "done": true }       replace the editable fields
PATCH  /tasks/42   [{ "op": "replace", "path": "/done", "value": true }]   change only some fields

Action-style
POST   /tasks/search   { "done": false, "tags": ["bug"] }
GET    /tasks/42
POST   /tasks/42/complete
```

What to notice:

- Both shapes use HTTP methods, URLs, status codes, and JSON the same way. The difference is where the verb lives: in the method, or in the URL.
- Reading one task looks the same in both. Completing one is a change to `done` in the resource-style list, through either `PUT` or `PATCH`, and its own URL in the action-style list.
- Teams often call the first shape "REST" and the second "RPC", short for remote procedure call: calling a function on another machine. The next section explains why this article uses different names.

## What REST means

REST, short for Representational State Transfer, is the name Roy Fielding gave in his 2000 dissertation to the architectural style of the web. One of its constraints is that the server's responses drive the client: they contain the links and forms that tell the client what it can do next, and the client follows them instead of building URLs from documentation. An HTML page works this way. The browser knows nothing about a shop in advance; it follows the links and submits the forms the page contains.

Fielding was explicit about this in 2008: "if the engine of application state (and hence the API) is not being driven by hypertext, then it cannot be RESTful and cannot be a REST API. Period."

The task board's responses contain no links. Its client builds URLs such as `/tasks/42` itself, from what its developers know about the API. So, by that definition, neither shape in this article is REST. That's why this article uses names that describe what the URLs look like: resource-style and action-style.

## What HTTP and Fielding say about POST

A common belief is that REST reserves `POST` for creating things, so searches and actions such as "complete" must use other methods. HTTP itself is defined in RFC 9110, and it describes `POST` this way: "The POST method requests that the target resource process the representation enclosed in the request according to the resource's own specific semantics." In other words, the resource decides what a `POST` means. RFC 9110 lists creating a resource as one example, next to "providing a block of data, such as the fields entered into an HTML form, to a data-handling process."

Two properties of methods matter more than names, because clients and proxies act on them:

- A method is **safe** if it's essentially read-only: `GET`, `HEAD`, `OPTIONS`, and `TRACE`. Browsers and crawlers may send safe requests on their own, for example to prefetch a link.
- A method is **idempotent** if sending the same request twice has the same intended effect as sending it once. `PUT`, `DELETE`, and the safe methods are idempotent, so a client may retry them automatically after a dropped connection.

`POST` is neither, and neither is `PATCH`: RFC 5789, which defines `PATCH`, says it "is neither safe nor idempotent." So moving "complete" from `PATCH` to `POST` gives up no guarantee that HTTP promised. Moving it from `PUT` does: a client may retry a `PUT` on its own, but not a `POST`, even when the `POST` endpoint behaves the same if it's repeated.

Fielding addressed the belief directly in a 2009 post titled "It is okay to use POST": "Search my dissertation and you won't find any mention of CRUD or POST." He continues: "Specific method definitions (aside from the retrieval:resource duality of GET) simply don't matter to the REST architectural style", and ends with "We don't need to use PUT for every state change in HTTP. REST has never said that we should."

The same post draws one line, and it applies to searches: "It isn't RESTful to use POST for information retrieval when that information corresponds to a potential resource, because that usage prevents safe reusability and the network-effect of having a URI." So for completing a task, Fielding and RFC 9110 agree that `POST` is fine. For a search, Fielding prefers `GET` with the filters in the URL, because a URL can be cached, linked, and reused. The sections below show what that URL buys and what it costs.

Large public APIs use both shapes. Microsoft's Azure REST API guidelines say "DO use a POST operation for any action on a resource or collection", with URLs such as `…/users:grant`. Google's API design guide uses `GET` for its standard list methods, with the filter in the query string, and `POST` for custom methods such as `POST /v1/{name}:archive`; it adds that "POST may be used for data retrieval methods if the request payload could exceed URL size limitations." Microsoft Graph's guidelines suggest `POST` with a `$query` segment when a query's options make the URL too long.

## Why not GET with a body

If the problem is a long query string, you might think `GET` with a JSON body solves it: the method stays `GET`, and the filters move to the body. ASP.NET Core accepts it if you ask for the body explicitly, here passing it to the `Search` handler that the next section builds:

```csharp
tasks.MapGet("/search", ([FromBody] TaskSearch search, TaskBoardDb db, CancellationToken cancellationToken) =>
    Search(search, db, cancellationToken));
```

```bash
curl -X GET http://localhost:5109/tasks/search -H 'Content-Type: application/json' -d '{"tags":["bug"]}'
```

That answers `200`. Without `[FromBody]`, the app fails with "Body was inferred but the method does not allow inferred body parameters": minimal APIs read a complex parameter from the body only for methods other than `GET`, `DELETE`, `HEAD`, `OPTIONS`, `TRACE`, and `CONNECT`.

The browser is where it stops. `fetch` refuses to send it:

```js
await fetch("/tasks/search", {
  method: "GET",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ tags: ["bug"] }),
});
```

```text
TypeError: Failed to execute 'fetch' on 'Window': Request with GET/HEAD method cannot have body.
```

Angular's `HttpClient` uses `fetch` by default, so `http.request("GET", url, { body })` fails with an `HttpErrorResponse` whose status is `0` and whose message carries the same `TypeError`. No request leaves the browser.

The standards back the browser. RFC 9110 says content in a `GET` request "has no generally defined semantics, cannot alter the meaning or target of the request, and might lead some implementations to reject the request". Caches identify a response by its method and URL, so two searches with different bodies but the same URL would look like the same request to a cache, and the second one could get the first one's results. OpenAPI 3.1 says a `GET` request body "SHOULD be avoided if possible."

HTTP has since added a method for exactly this: `QUERY`, published as RFC 10008 in June 2026, a safe and idempotent request that carries its query in the body. ASP.NET Core 10 can route it with `MapMethods`, but its OpenAPI generator leaves `QUERY` endpoints out of the document, and most proxies, caches, and CDNs don't handle it yet.

## Searching both ways

Both searches take the same filters, so they can share one record. It uses `init` properties for the reason the OpenAPI article showed: a positional record would make the document list every filter as required.

```csharp
public record TaskSearch
{
    public bool? Done { get; init; }
    public string[]? Tags { get; init; }
    public int[]? AssigneeIds { get; init; }
    public DateOnly? DueFrom { get; init; }
    public DateOnly? DueTo { get; init; }
    public string? Text { get; init; }
}
```

`List` replaces its earlier `assigneeId` and `dueBefore` parameters with the record, and the two handlers differ only in where the record comes from:

```csharp
tasks.MapGet("/", List);
tasks.MapPost("/search", Search);

public static async Task<Ok<List<TaskSummary>>> List([AsParameters] TaskSearch search, TaskBoardDb db, CancellationToken cancellationToken)
{
    var tasks = await Find(db, search, cancellationToken);
    return TypedResults.Ok(tasks);
}

public static async Task<Ok<List<TaskSummary>>> Search(TaskSearch search, TaskBoardDb db, CancellationToken cancellationToken)
{
    var tasks = await Find(db, search, cancellationToken);
    return TypedResults.Ok(tasks);
}

static Task<List<TaskSummary>> Find(TaskBoardDb db, TaskSearch search, CancellationToken cancellationToken) =>
    TaskFilters.Apply(db.Tasks, search)
        .OrderBy(t => t.DueOn).ThenBy(t => t.Id)
        .Take(20)
        .Select(t => new TaskSummary(t.Id, t.Title, t.Done, t.DueOn, t.Tags))
        .ToListAsync(cancellationToken);
```

What to notice:

- `[AsParameters]` tells ASP.NET Core to bind each property of the record as if it were its own handler parameter. For a `GET`, that means the query string.
- In `Search`, the same record has no attribute. On a `POST`, minimal APIs read a complex parameter from the JSON body.
- `TaskFilters.Apply` adds one `Where` per filter that's set, the way the controllers article's list endpoint added its `dueBefore` filter.

<details>
<summary>The complete <code>TaskFilters.cs</code></summary>

```csharp
public static class TaskFilters
{
    public static IQueryable<TaskItem> Apply(IQueryable<TaskItem> tasks, TaskSearch search)
    {
        if (search.Done is not null)
        {
            tasks = tasks.Where(t => t.Done == search.Done);
        }

        if (search.Tags is { Length: > 0 })
        {
            tasks = tasks.Where(t => t.Tags.Any(tag => search.Tags.Contains(tag)));
        }

        if (search.AssigneeIds is { Length: > 0 })
        {
            tasks = tasks.Where(t => t.AssigneeId != null && search.AssigneeIds.Contains(t.AssigneeId.Value));
        }

        if (search.DueFrom is not null)
        {
            tasks = tasks.Where(t => t.DueOn >= search.DueFrom);
        }

        if (search.DueTo is not null)
        {
            tasks = tasks.Where(t => t.DueOn <= search.DueTo);
        }

        if (!string.IsNullOrWhiteSpace(search.Text))
        {
            tasks = tasks.Where(t => t.Title.Contains(search.Text));
        }

        return tasks;
    }
}
```

</details>

The opening's `GET` and the equivalent `POST`:

```bash
curl "http://localhost:5109/tasks?done=false&tags=bug&tags=ui&assigneeIds=3&assigneeIds=7&dueFrom=2026-11-01&dueTo=2026-11-30&text=login"

curl -X POST http://localhost:5109/tasks/search -H 'Content-Type: application/json' \
  -d '{"done":false,"tags":["bug","ui"],"assigneeIds":[3,7],"dueFrom":"2026-11-01","dueTo":"2026-11-30","text":"login"}'
```

return the same eight tasks, and EF Core sends the same SQL for both:

```sql
SELECT t.id, t.title, t.done, t.due_on, t.tags
FROM tasks AS t
WHERE t.done = @search_Done AND t.tags && @search_Tags AND t.assignee_id IS NOT NULL
  AND t.assignee_id = ANY (@search_AssigneeIds) AND t.due_on >= @search_DueFrom
  AND t.due_on <= @search_DueTo AND t.title LIKE @search_Text_contains
ORDER BY t.due_on, t.id
LIMIT @p
```

(`&&` is PostgreSQL's "arrays share at least one element" operator.) The database can't tell the two shapes apart. The differences are all in how the filters travel.

### What a query string can carry

A JSON body has types: arrays, numbers, nested objects. A query string is a flat list of `name=value` text pairs, so the server has to decide how to turn each value into a C# type:

| Query string | `TaskSearch` gets | Result |
|---|---|---|
| `tags=bug&tags=ui` | `["bug", "ui"]` | tasks tagged `bug` or `ui` |
| `tags=bug,ui` | `["bug,ui"]` | no tasks: a comma doesn't split values |
| `dueFrom=2026-12-01` | 1 December 2026 | tasks from 1 December |
| `dueFrom=01/12/2026` | 12 January 2026 | tasks from October, the earliest in the data |
| `dueFrom=2026-13-01` | nothing | `400 Bad Request` |
| `Done=false&TAGS=docs` | `Done = false`, `["docs"]` | names ignore case |

The slash date is the one to watch. Query string values are parsed with the invariant culture, which puts the month first, so someone who means 1 December gets every task from October with no error. In a JSON body, dates follow the ISO 8601 format, `2026-12-01`, and anything else fails.

Structure is the other limit. Suppose the due date range becomes a nested record:

```csharp
public record DateRange(DateOnly? From, DateOnly? To);

public record TaskSearch
{
    // …
    public DateRange? Due { get; init; }
}
```

The `POST` search binds `{"due":{"from":"2026-12-01","to":"2026-12-31"}}` without any changes. The `GET` version can't: ASP.NET Core decides that `Due` must come from the body, which `GET` doesn't allow, and the first request to any endpoint fails with `500` while the log shows:

```text
System.InvalidOperationException: Body was inferred but the method does not allow inferred body parameters.
Below is the list of parameters that we found:

Parameter           | Source
---------------------------------------------------------------------------------
Done                | Query String (Inferred)
Tags                | Query String (Inferred)
AssigneeIds         | Query String (Inferred)
Due                 | Body (Inferred)
Text                | Query String (Inferred)
```

With build-time document generation, `dotnet build` fails with the same message, so you find out before deploying. Flat filters work in a query string; groups, "this or that" conditions, and nested ranges need a naming scheme you design and parse yourself.

### How long a URL can get

Lists of IDs make URLs grow fastest. Kestrel, ASP.NET Core's web server, limits the request line (the method, the URL, and the HTTP version) to 8 KB by default. Filling the search with tags until it breaks:

```text
582 tags   request line 8,178 bytes   200 OK
583 tags   request line 8,192 bytes   414 URI Too Long   (empty body)
```

Everything in front of Kestrel has its own limit, and some are lower. IIS, by default, rejects query strings over 2,048 characters with `404.15`, a `404` with a substatus code, not a `414`. Amazon CloudFront rejects URLs over 8,192 bytes. Chromium accepts URLs up to 2 MB, so the browser is rarely the first to fail. A JSON body has a much larger budget: Kestrel accepts request bodies up to 30,000,000 bytes by default, and the same search with 5,000 tags, 60 KB of JSON, answers `200`.

RFC 9110 recommends that everything support URLs of at least 8,000 octets, and describes `414` as "only likely to occur when a client has improperly converted a POST request to a GET request with long query information."

## Caching, logs, and history

A `GET` response can be cached; a `POST` response, in practice, can't. Give both search handlers the same header:

```csharp
context.Response.Headers.CacheControl = "private, max-age=30";
```

(`private` allows only the browser's own cache to keep it, and `max-age=30` keeps it fresh for 30 seconds. [Why users still see the old version](/dump/blog/caching-static-files-and-requests/#fetch-calls-get-the-same-treatment) explains how `fetch` calls use the browser cache.) A page in Chromium that sends each search twice:

```js
await fetch("/tasks?done=false&tags=bug");
await fetch("/tasks?done=false&tags=bug");

const body = JSON.stringify({ done: false, tags: ["bug"] });
const headers = { "Content-Type": "application/json" };
await fetch("/tasks/search", { method: "POST", headers, body });
await fetch("/tasks/search", { method: "POST", headers, body });
```

reaches the server three times. The second `GET` was answered from the browser cache; both `POST` requests went through. RFC 9110 allows caching a `POST` response only under extra conditions and notes that "the overwhelming majority of cache implementations only support GET and HEAD." CDNs and other shared caches work the same way. Whether a cached task list is a good idea depends on how fresh the results must be, but only the `GET` shape gives you the choice.

The URL travels further than the body, too. With `Microsoft.AspNetCore.Hosting.Diagnostics` logging at `Information`, ASP.NET Core logs every request's full URL:

```text
Request starting HTTP/1.1 GET http://localhost:5109/tasks?done=false&tags=bug - - -
Request starting HTTP/1.1 POST http://localhost:5109/tasks/search - application/json 29
```

The `dotnet new` templates set `Microsoft.AspNetCore` to `Warning`, which hides these lines, but reverse proxies such as nginx write the request line, query string included, to their access logs by default, and browsers keep page URLs in their history. RFC 9110 puts it plainly: "URIs are intended to be shared, not secured," so it's "unwise to include information within a URI that is sensitive, personally identifiable, or a risk to disclose." A text filter containing a customer's name or email ends up in all of those places as part of a URL, and in none of them as part of a `POST` body.

A common worry is that a `POST` search can't be bookmarked or shared. What gets bookmarked and shared is the page's URL in the address bar, not the URL of the API request the page sends. [The URL is part of your application's state](/dump/blog/urls-as-application-state/) keeps the task list's filters in the page URL, such as `/tasks?status=open&q=login`, and builds a checked `ViewState` from it. The component can send that state to either endpoint:

```ts
searchTasks(view: ViewState) {
  return this.http.post<TaskSummary[]>("/tasks/search", {
    done: view.status === "all" ? null : view.status === "completed",
    text: view.q || null,
  });
}
```

Refresh, Back, and copied links keep working, because they depend on the page URL. What the `POST` gives up is a shareable, cacheable URL for the API response itself, Fielding's "network-effect of having a URI".

## Completing a task both ways

### Resource-style: replace with PUT, or patch with PATCH

Resource-style APIs usually offer two ways to change a task. RFC 9110 defines `PUT` as a request that "the state of the target resource be created or replaced with the state defined by the representation enclosed in the request message content": the client sends every editable field. `PATCH` changes only part of it. The task board's `PUT /tasks/{id}` from the earlier articles already replaces the editable fields; this article adds a `PATCH` whose body lists only the changes.

`done` joins the editable fields:

```csharp
public record TaskEdit(string Title, DateOnly? DueOn, bool Done);

tasks.MapPut("/{id:int}", Replace);
tasks.MapPatch("/{id:int}", Patch);
```

`Replace` is the previous articles' `Edit` handler, renamed, with its `If-Match` and ETag checks. Both handlers end by calling the same method to copy an edit onto the task:

```csharp
static void ApplyEdit(TaskItem task, TaskEdit edit)
{
    var completing = edit.Done && !task.Done;
    var reopening = !edit.Done && task.Done;
    if (completing)
    {
        task.CompletedAt = DateTime.UtcNow;
    }

    if (reopening)
    {
        task.CompletedAt = null;
    }

    task.Title = edit.Title;
    task.DueOn = edit.DueOn;
    task.Done = edit.Done;
    task.Version++;
}
```

What to notice:

- The code finds out that someone completed the task by comparing the old and new values of `done`. The rule "completing sets `CompletedAt`" lives inside a general edit, next to title and date changes.
- Reopening comes free: set `done` to `false`.
- Setting `done` to `true` on a task that's already done changes nothing but the version.

A `PUT` replaces every editable field, and that matters once a field is added. A client written before `done` existed renames a completed task:

```bash
curl -X PUT http://localhost:5109/tasks/1 -H 'Content-Type: application/json' -H 'If-Match: "2"' \
  -d '{"title":"Plan the task list #1 (renamed)","dueOn":"2026-10-09"}'
```

```json
{"id":1,"title":"Plan the task list #1 (renamed)","done":false,"dueOn":"2026-10-09","completedAt":null,"tags":["bug","ui"],"version":3}
```

The missing `done` was read as `false`, so the rename reopened the task and erased its completion time. That's what replacing means: what the client leaves out is gone. A body without `title` fails worse, because the `null` title reaches the database's `not null` constraint and the client gets a `500`.

A `PATCH` avoids that by sending only the change. The task board uses JSON Patch (RFC 6902), where the body is a list of operations. Each one has an `op`, which RFC 6902 limits to `add`, `remove`, `replace`, `move`, `copy`, or `test`, and a `path` naming the field. ASP.NET Core 10 reads it with the `Microsoft.AspNetCore.JsonPatch.SystemTextJson` package:

```csharp
public static async Task<Results<NoContent, NotFound, ValidationProblem, ProblemHttpResult>> Patch(int id, JsonPatchDocument<TaskEdit> patch, HttpContext context, TaskBoardDb db, CancellationToken cancellationToken)
{
    // …the same If-Match, 404, and ETag checks as Replace

    var edit = new TaskEdit(task.Title, task.DueOn, task.Done);
    var errors = new List<string>();
    patch.ApplyTo(edit, error => errors.Add(error.ErrorMessage));
    if (errors.Count > 0)
    {
        return TypedResults.ValidationProblem(new Dictionary<string, string[]> { ["patch"] = [.. errors] });
    }

    ApplyEdit(task, edit);

    // …save and answer 204, as Replace does
}
```

```bash
curl -X PATCH http://localhost:5109/tasks/1 -H 'Content-Type: application/json-patch+json' -H 'If-Match: "1"' \
  -d '[{"op":"replace","path":"/done","value":true}]'
```

That answers `204` and completes the task, leaving the title and due date alone. What to notice:

- The patch is applied to a `TaskEdit` built from the current task, not to the entity. Microsoft's JSON Patch documentation warns that operations can otherwise change "internal flags, IDs, or computed fields." Applied to `TaskItem`, a patch replacing `/id`, `/version`, and `/completedAt` succeeded with no errors. Applied to `TaskEdit`, the same paths get a validation `400`: "The target location specified by path segment 'version' was not found."
- After the patch, the same `ApplyEdit` runs, so completing is still worked out from `done` changing.
- `JsonPatchDocument<T>` tells routing that the endpoint accepts only `application/json-patch+json`. The same body sent as `application/json` gets `415 Unsupported Media Type`.
- Older projects use `Microsoft.AspNetCore.JsonPatch`, which is based on Newtonsoft.Json; the operations format is the same. JSON Merge Patch (RFC 7396) is a different format for the same job: the body lists only the changed fields, as plain JSON.

From the task list, completing takes two requests with either method. `TaskSummary` has no version and no ETag, so the client first loads the task with `GET /tasks/1` to get its ETag (and, for `PUT`, its current fields), then sends the `PUT` or `PATCH` with `If-Match`. Without `If-Match`, both answer `428 Precondition Required`.

### Action-style: an endpoint per operation

`POST /tasks/{id}/complete` has existed since the controllers article. It now records the completion time and leaves done tasks alone:

```csharp
public static async Task<Results<NoContent, NotFound>> Complete(int id, TaskBoardDb db, CancellationToken cancellationToken)
{
    var changed = await db.Tasks
        .Where(t => t.Id == id && !t.Done)
        .ExecuteUpdateAsync(s => s
            .SetProperty(t => t.Done, true)
            .SetProperty(t => t.CompletedAt, DateTime.UtcNow)
            .SetProperty(t => t.Version, t => t.Version + 1), cancellationToken);
    if (changed == 1)
    {
        return TypedResults.NoContent();
    }

    var exists = await db.Tasks.AnyAsync(t => t.Id == id, cancellationToken);
    if (!exists)
    {
        return TypedResults.NotFound();
    }

    return TypedResults.NoContent();
}
```

What to notice:

- It's one `UPDATE … WHERE t.id = @id AND NOT (t.done)`, the atomic update from the transactions article. Two people completing the same task at once can't both change it.
- It needs no ETag, because it never overwrites the title or due date with values the client loaded earlier. The client sends one request with no body.
- Completing a task that's already done answers `204` and changes nothing; the completion time and version stay as they were. A missing task answers `404`.
- Bumping the version still protects edits: someone who loaded the task before it was completed and then sends a `PUT` or `PATCH` with the old ETag gets `412 Precondition Failed`.
- Reopening needs its own endpoint, such as `POST /tasks/{id}/reopen`. Each operation the API supports is one more endpoint.

## Client code and the OpenAPI document

In Angular, the two searches look like this:

```ts
// Resource-style
this.http.get<TaskSummary[]>("/tasks", {
  params: { done: false, tags: ["bug", "ui"], dueFrom: "2026-12-01" },
});

// Action-style
this.http.post<TaskSummary[]>("/tasks/search", {
  done: false, tags: ["bug", "ui"], dueFrom: "2026-12-01",
});
```

`HttpClient` turns the `params` object into `done=false&tags=bug&tags=ui&dueFrom=2026-12-01`, repeated keys for the array, which is what ASP.NET Core expects, so both calls return the same 20 tasks. The `POST` body is the `TaskSearch` record written as JSON.

Completing a task differs more:

```ts
// Resource-style: load the task for its ETag, then patch done
const response = await firstValueFrom(this.http.get<TaskDetails>(`/tasks/${id}`, { observe: "response" }));
await firstValueFrom(
  this.http.patch(`/tasks/${id}`, [{ op: "replace", path: "/done", value: true }], {
    headers: { "Content-Type": "application/json-patch+json", "If-Match": response.headers.get("ETag")! },
  }),
);

// Action-style
await firstValueFrom(this.http.post(`/tasks/${id}/complete`, null));
```

If the frontend runs on another origin, the shapes also differ in CORS. A `GET` with a query string is a simple request, sent right away. A `POST` with a JSON body isn't, so Chromium sent an `OPTIONS` preflight before the cross-origin search and none before the `GET`. [HTTP from TCP to fetch](/dump/blog/http-from-tcp-to-fetch/#cors-with-preflight) explains preflights; the `PUT` and `PATCH` with `If-Match` trigger one too, and `Access-Control-Max-Age` lets the browser reuse the answer.

The build-generated OpenAPI document lists the endpoints this way:

```text
GET    /tasks                  query: Done, Tags, AssigneeIds, DueFrom, DueTo, Text            200
POST   /tasks/search           body: TaskSearch                                                200
PUT    /tasks/{id}             body: TaskEdit                                                  204, 404, 412, 428
PATCH  /tasks/{id}             body: JsonPatchDocument, as application/json-patch+json         204, 400, 404, 412, 428
POST   /tasks/{id}/complete                                                                    204, 404
```

What to notice:

- Completing a task is a named operation in the action-style document. In the resource-style document, it's a `done` boolean inside `TaskEdit`. Nothing there says that setting it records a completion time, or that clearing it reopens the task.
- The `PATCH` body's schema is a generic list of operations: an `op` from RFC 6902's list and a `path` that can be any string. The document doesn't say which paths exist, that `/done` completes the task, or that `/version` is rejected.
- The `TaskEdit` schema lists `title`, `dueOn`, and `done` as required, because it's a positional record. That matches what `PUT` means, but nothing enforces it: the server read the missing `done` as `false`.
- `TaskSearch` lists no required properties, so a generated client lets you send any combination of filters.
- The query parameters appear with the property names, `Done` and `Tags`. Binding ignores case, so a generated client's `?Tags=bug` works the same as `?tags=bug`.

## When each fits

**Resource-style fits** when:

- Searches have a few flat filters, and a URL for the result is useful on its own: in a link, in `curl`, or for an API that other teams call directly.
- Responses benefit from HTTP caching in the browser, a CDN, or a shared cache. Only `GET` gets that.
- Data really is edited as a set of fields, such as a settings form, where one `PUT`, or one `PATCH` with several operations, saves them all at once.
- Clients or tools expect collections and items, such as generic admin screens or the list conventions in Google's guide.

**Action-style fits** when:

- An operation has rules or side effects beyond setting fields: completing records a time, could notify the person who created the task, or may only be allowed for the assignee. An endpoint per operation gives each rule, authorization check, log entry, and metric one obvious place.
- Searches carry long ID lists, nested groups, "this or that" conditions, or values that shouldn't end up in logs and browser history.
- One frontend team owns the API's main client, and caching API responses by URL doesn't matter.

Most real APIs mix the two, and the choice is made per endpoint. The task board already does: `GET /tasks/{id}` reads, `PUT` and `PATCH` edit, and `POST /tasks/{id}/complete` completes. Google's guide pairs `GET` list methods with `POST …:archive`, and Azure's guidelines pair resources with `POST …:action`.

## Back to the query string

So is `POST /tasks/search` "not allowed in REST"? RFC 9110 lets a resource define what `POST` means, Fielding says method definitions other than `GET`'s role as retrieval don't matter to REST, and his own 2009 post says REST never required a `PUT` for every change. The task board's API also returns no links, so by Fielding's definition, it isn't REST in either shape. For completing a task, nothing argues against `POST`.

For the search, the useful question is what the `GET` URL is worth to you. Fielding's preference for `GET` is about what a URL buys: caching, linking, and reuse by anything that understands HTTP. What it costs is a flat, text-only format, size limits that start around 2 KB to 8 KB depending on what sits in front of the server, and filters that end up in logs and history. Your page can keep shareable filters in its own URL either way.

| | Resource-style | Action-style |
|---|---|---|
| Search request | `GET /tasks?…` | `POST /tasks/search` with JSON |
| Filters | flat text pairs; arrays as repeated keys; month-first dates | any JSON shape; ISO dates |
| Size | 8 KB request line in Kestrel, 2,048-character query string in IIS | 30,000,000-byte body in Kestrel |
| HTTP caching | browser, CDN, and shared caches | in practice none |
| Filters in logs and history | yes | no |
| Cross-origin preflight | not for a plain `GET` | yes, for JSON |
| Completing a task | `PUT` with every editable field, or `PATCH` with a JSON Patch, both with `If-Match` | `POST /tasks/{id}/complete` |
| Where the completion rule lives | inferred from the change to `done` in the shared edit code | the endpoint itself |
| In the OpenAPI document | a `done` field in `TaskEdit`, and a generic operations list for `PATCH` | a named operation |
| Retries promised by the method | `PUT` is idempotent; `PATCH` isn't | none: `POST` isn't idempotent |

## Check your understanding

1. **A teammate says completing a task must be a `PATCH`, because REST doesn't allow `POST` for it. What do RFC 9110 and Fielding say?** RFC 9110 lets the resource define what a `POST` does, creation being one example among several. Fielding says method definitions, apart from `GET`'s role as retrieval, don't matter to REST, and that REST never required `PUT` for every change. `PATCH` isn't idempotent either, so `POST` gives up no guarantee.
2. **Why can't the Angular component send the search filters as a `GET` body?** `fetch` throws a `TypeError` for a body on `GET` or `HEAD`, and `HttpClient` uses `fetch` by default, so no request is sent. RFC 9110 gives a `GET` body no defined meaning, and caches identify responses by method and URL, not body.
3. **The search moves from `GET /tasks?…` to `POST /tasks/search`. What does the API response lose, and how does the page keep a link people can share?** It loses its own URL: browser and shared caches won't reuse it, and the API response can't be linked directly. The page keeps the filters in its own URL, reads them into its view state, and sends them as the `POST` body.
4. **A client written before `done` existed renames a completed task with `PUT`, sending `title` and `dueOn`. What happens, and how would a `PATCH` avoid it?** The task is reopened and its completion time erased. `PUT` replaces every editable field, so the missing `done` is read as `false`, which the edit code treats as reopening. A JSON Patch sends only `[{ "op": "replace", "path": "/title", … }]`, so `done` keeps its value.

## Sources and further reading

- [RFC 9110: HTTP Semantics](https://www.rfc-editor.org/rfc/rfc9110): `GET` (§9.3.1), `POST` (§9.3.3), `PUT` (§9.3.4), safe and idempotent methods (§9.2), URI length (§4.1), and sensitive information in URIs (§17.9).
- [RFC 5789: PATCH Method for HTTP](https://www.rfc-editor.org/rfc/rfc5789), [RFC 6902: JSON Patch](https://www.rfc-editor.org/rfc/rfc6902), and [RFC 7396: JSON Merge Patch](https://www.rfc-editor.org/rfc/rfc7396).
- [JSON Patch in ASP.NET Core web API](https://learn.microsoft.com/en-us/aspnet/core/web-api/jsonpatch?view=aspnetcore-10.0), including its security section.
- [RFC 10008: The HTTP QUERY Method](https://www.rfc-editor.org/rfc/rfc10008).
- Roy Fielding, [REST APIs must be hypertext-driven](https://roy.gbiv.com/untangled/2008/rest-apis-must-be-hypertext-driven) (2008) and [It is okay to use POST](https://roy.gbiv.com/untangled/2009/it-is-okay-to-use-post) (2009).
- [Microsoft Azure REST API guidelines](https://github.com/microsoft/api-guidelines/blob/vNext/azure/Guidelines.md), [Microsoft Graph REST API guidelines](https://github.com/microsoft/api-guidelines/blob/vNext/graph/GuidelinesGraph.md), and Google's [AIP-136: Custom methods](https://google.aip.dev/136) and [AIP-132: Standard methods: List](https://google.aip.dev/132).
- [Parameter binding in minimal APIs](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/minimal-apis/parameter-binding?view=aspnetcore-10.0), including `[AsParameters]`, and [Kestrel server limits](https://learn.microsoft.com/en-us/dotnet/api/microsoft.aspnetcore.server.kestrel.core.kestrelserverlimits?view=aspnetcore-10.0).
- [Fetch Standard](https://fetch.spec.whatwg.org/): the `Request` constructor and CORS-safelisted methods.
