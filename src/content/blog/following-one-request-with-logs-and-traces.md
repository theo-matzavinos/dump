---
title: "Which of these lines are Ada's? Following one request with logs and traces in ASP.NET Core"
description: "Why two requests' log entries end up mixed together with nothing tying them to a request, how the trace ID ASP.NET Core gives every request picks one request's lines out of the log and reaches the services it calls, and how OpenTelemetry and Jaeger turn that request into a timeline that shows where its time went."
pubDate: "2026-10-21T10:00:00Z"
tags:
  - aspnet-core
  - dotnet
  - observability
audience:
  - backend
---

The mail service the task board sends its completion emails through is down, and it answers every request with `503 Service Unavailable`. At the same moment, Ada completes task 1 and Grace completes task 2:

```text
ada    POST /tasks/1/complete    500 Internal Server Error    10.1 s
grace  POST /tasks/2/complete    500 Internal Server Error    10.9 s
```

Both tasks are done in the database, and no email went out. In those 11 seconds the task board wrote 48 log entries, the two requests' entries mixed together. A slice of them:

```text
info: System.Net.Http.HttpClient.IMailSender.ClientHandler[101]
      Received HTTP response headers after 79.6727ms - 503
info: System.Net.Http.HttpClient.IMailSender.ClientHandler[101]
      Received HTTP response headers after 79.6736ms - 503
warn: Polly[3]
      Execution attempt. Source: 'IMailSender-standard//Standard-Retry', Operation Key: '', Result: '503', Handled: 'True', Attempt: '0', Execution Time: 90.4385ms
warn: Polly[3]
      Execution attempt. Source: 'IMailSender-standard//Standard-Retry', Operation Key: '', Result: '503', Handled: 'True', Attempt: '0', Execution Time: 90.4388ms
…
fail: Microsoft.AspNetCore.Server.Kestrel[13]
      Connection id "0HNPF88QU28VU", Request id "0HNPF88QU28VU:00000001": An unhandled exception was thrown by the application.
      System.Net.Http.HttpRequestException: Response status code does not indicate success: 503 (Service Unavailable).
```

None of the entries names a task, a user, or the request it belongs to. Ada asks what happened to her completion. Which of these lines are hers, and where did her 10 seconds go?

You'll need [the idempotency keys article](/dump/blog/idempotency-keys-and-repeated-requests/) for the mail service and the resilience handler that retries its requests, [the configuration article](/dump/blog/configuration-and-secrets/) for `appsettings.json` and environment variables such as `Mail__ApiKey`, [the HTTP article](/dump/blog/http-from-tcp-to-fetch/) for headers, and [the Docker article](/dump/blog/docker-behind-the-scenes/) for running a container. `jq`, a command-line tool that filters JSON, appears in two commands.

## Contents

1. [Set up the example](#set-up-the-example)
2. [What the log shows today](#what-the-log-shows-today)
3. [One request's lines](#one-requests-lines)
4. [Your own log lines](#your-own-log-lines)
5. [Where the trace ID comes from](#where-the-trace-id-comes-from)
6. [The request as a timeline](#the-request-as-a-timeline)
7. [Giving the trace ID to the client](#giving-the-trace-id-to-the-client)
8. [Back to Ada's completion](#back-to-adas-completion)

## Set up the example

The examples use the .NET 10 SDK (ASP.NET Core 10.0.13), EF Core 10.0.4, Npgsql 10.0.3, the OpenTelemetry packages listed later, PostgreSQL 18.6, Keycloak 26.8.1, and Jaeger 2.22.0, with the API in the `Production` environment.

The code starts from the task board at the end of [the configuration article](/dump/blog/configuration-and-secrets/). [The layered and sliced article](/dump/blog/layered-and-sliced-code-organization/) and [the endpoints article](/dump/blog/resource-style-and-action-style-endpoints/) compare its layout and endpoint style with the alternatives. The API runs with the mail service's key in an environment variable:

```bash
Mail__ApiKey=mail-local-only Auth__RequireHttpsMetadata=false dotnet run --project TaskBoard
```

The stand-in mail service answers `503` to every request, and it prints the `traceparent` header of each request it receives, which matters later. With a token for each from Keycloak, as in [the token article](/dump/blog/what-an-api-must-check-in-a-token/), Ada and Grace complete their tasks at the same moment:

```bash
curl -s -X POST -H "Authorization: Bearer $ADA" http://localhost:5000/tasks/1/complete &
curl -s -X POST -H "Authorization: Bearer $GRACE" http://localhost:5000/tasks/2/complete
```

Metrics, products that store and search logs, an OpenTelemetry Collector, running Jaeger with storage that survives a restart, tracing code in the browser, your own spans, sampling strategies, and Kubernetes are outside this article's scope.

## What the log shows today

Each entry starts with a line like `warn: Polly[3]`:

- The **level** says how serious the entry is: `info` for normal events, `warn` for something unexpected that the app handled, `fail` for an error.
- The **category** names the logger that wrote it, usually after the class or library: `Microsoft.EntityFrameworkCore.Database.Command` for EF Core's SQL, `System.Net.Http.HttpClient.IMailSender.ClientHandler` for the mail client's requests, `Polly` for the resilience handler.
- The number in brackets is the event ID, which identifies the kind of message within the category.

The message follows on the next lines. `appsettings.json` decides which entries are written at all:

```json
"Logging": {
  "LogLevel": {
    "Default": "Information",
    "Microsoft.AspNetCore": "Warning",
    "Microsoft.AspNetCore.Authentication": "Information"
  }
}
```

Each category writes entries at its level and above. `Microsoft.AspNetCore` is at `Warning`, so ASP.NET Core's own `Request starting` and `Request finished` entries are left out.

The 48 entries for the two completions were:

- 12 for SQL. EF Core and Npgsql each log every statement, so each of the 3 statements per completion appears twice per request. EF Core shows parameter values as `'?'`, as [EF Core behind the scenes](/dump/blog/ef-core-behind-the-scenes/) explains.
- 20 from the mail client: the start and end of each email, and a sent line and a received line for each of the 8 attempts.
- 14 from Polly: an `Execution attempt` entry for each attempt, and an `OnRetry` entry before each retry.
- 2 errors from Kestrel, the web server inside ASP.NET Core, one for each `500`, with the stack trace.

The retries are all there, but nothing ties an attempt to a request. The two `Received HTTP response headers` entries in the opening report almost the same time, 79.6727 ms and 79.6736 ms, and either could be Ada's. The Kestrel errors name a connection ID and a request ID, but each of those appeared exactly once in the log, in the error itself. And an entry spans several lines, so searching the file for a word returns pieces of entries.

How do you tell which request wrote a line?

## One request's lines

ASP.NET Core already knows. While it handles a request, it keeps a few values that the logging system attaches to every entry written during that request. Each set of such values is a **scope**. For each request, ASP.NET Core opens three: one with `SpanId`, `TraceId`, and `ParentId`, one with `ConnectionId`, and one with `RequestPath` and `RequestId`. The console only prints them when `IncludeScopes` is on.

Turned on for the default console format, with `Logging__Console__FormatterName=simple` and `Logging__Console__FormatterOptions__IncludeScopes=true`, each entry got one more line:

```text
info: Microsoft.EntityFrameworkCore.Database.Command[20101]
      => SpanId:a8fd8c5c3861ef39, TraceId:6c946b7eddbea84e5489dbe3aa52e114, ParentId:0000000000000000 => ConnectionId:0HNPF89DK31F4 => RequestPath:/tasks/1/complete RequestId:0HNPF89DK31F4:00000001
      Executed DbCommand (2ms) [Parameters=[@keycloakId='?'], CommandType='Text', CommandTimeout='30']
```

The **trace ID** is a random 32-digit hexadecimal ID that ASP.NET Core gives each incoming request. Every one of the 48 entries had one of two trace IDs, 24 each. But `grep 6c946b7eddbea84e5489dbe3aa52e114` returned only the 24 scope lines, not the entries, because the scope and the message sit on different lines.

The JSON console format writes each entry as one line. In `appsettings.json`, next to `LogLevel`:

```json
"Console": {
  "FormatterName": "json",
  "FormatterOptions": {
    "IncludeScopes": true,
    "TimestampFormat": "yyyy-MM-ddTHH:mm:ss.fffZ",
    "UseUtcTimestamp": true
  }
}
```

What to notice:

- `IncludeScopes` goes under `FormatterOptions`, and `FormatterOptions` only applies when `FormatterName` is set. Both of the other combinations printed no scopes: `FormatterOptions` without a `FormatterName`, and `"Console": { "IncludeScopes": true }`, the form in Microsoft's ASP.NET Core logging page, together with `FormatterName` `json`.
- Without `TimestampFormat` the entries have no timestamp at all. Without `UseUtcTimestamp` the time is the server's local time.

One of the entries from Ada's request, a Polly entry, formatted here across lines:

```json
{
  "Timestamp": "2026-10-21T07:10:59.135Z",
  "EventId": 3,
  "LogLevel": "Warning",
  "Category": "Polly",
  "Message": "Execution attempt. Source: 'IMailSender-standard//Standard-Retry', Operation Key: '', Result: '503', Handled: 'True', Attempt: '0', Execution Time: 85.8695ms",
  "State": { "Result": 503, "Handled": true, "Attempt": 0, "ExecutionTimeMs": 85.8695, … },
  "Scopes": [
    { "SpanId": "e3a0499122c7c3cb", "TraceId": "8450ab70f988307f280430dce4b12a3f", "ParentId": "0000000000000000", … },
    { "ConnectionId": "0HNPF89Q0UDLR", … },
    { "RequestId": "0HNPF89Q0UDLR:00000001", "RequestPath": "/tasks/1/complete", … },
    { "HttpMethod": "POST", "Uri": "http://localhost:5299/messages", … }
  ]
}
```

The last scope comes from the mail client, which opens one of its own around each request it sends. `BeginScope` lets your own code do the same, attaching a value to every entry written inside it.

With one entry per line, any entry with `/tasks/1/complete` in it shows Ada's trace ID, and `grep 8450ab70f988307f280430dce4b12a3f` returned exactly 24 entries: the 6 for her three SQL statements, the 10 from the mail client, the 7 from Polly, and the Kestrel error. Grace's 24 had the other trace ID.

Those lines show Ada's retries and her error. But nothing in them says that her task changed before the email failed, or that she was the one completing it. How do you add facts of your own?

## Your own log lines

The completion endpoint writes its own entry once the task is done. Code gets a logger from dependency injection: usually an `ILogger<T>`, whose category is the name of `T`. `CompleteTask` is a static class, though, and `ILogger<CompleteTask>` doesn't compile (`CS0718: static types cannot be used as type arguments`). So `Handle` takes an `ILoggerFactory` and creates a logger with the category `CompleteTask`:

```csharp
public static async Task<Results<NoContent, NotFound, ForbidHttpResult>> Handle(int id, ClaimsPrincipal user, TaskBoardDb db, TimeProvider clock, IMailSender mailSender, ILoggerFactory loggerFactory, CancellationToken cancellationToken)
{
    …
    if (changed == 1)
    {
        loggerFactory.CreateLogger(nameof(CompleteTask)).LogInformation("Task {TaskId} completed by user {UserId}", id, callerId);
        await CompletionMail.SendAsync(id, db, mailSender, cancellationToken);
        return TypedResults.NoContent();
    }
    …
}
```

The first argument is a **message template**, not a finished message. Each `{Name}` is a placeholder, and the arguments after the template fill the placeholders in order. The entry for Ada's completion:

```json
"Message": "Task 1 completed by user 1001",
"State": { "TaskId": 1, "UserId": 1001, "{OriginalFormat}": "Task {TaskId} completed by user {UserId}" }
```

The message reads the same as before, and `State` also keeps each value as a field of its own. Written with string interpolation instead, as `LogInformation($"Task {id} completed by user {callerId}")`, the message was identical, but `State` held only the finished text:

```json
"State": { "{OriginalFormat}": "Task 1 completed by user 1001" }
```

The build gave no warning for the interpolated version. The analyzer rule for it, CA2254, is only a suggestion by default in .NET 10. Microsoft's logging guide recommends templates: "The arguments themselves are passed to the logging system, not just the formatted message template."

With the values as fields, a tool can select by them instead of searching text. Two commands find Ada's request from her task ID alone:

```bash
jq -r 'select(.State.TaskId == 1) | .Scopes[0].TraceId' taskboard.log
grep 08c0ec21f2a975f7c131ac764949b61b taskboard.log
```

The first printed one trace ID, and the second returned 25 entries: the earlier 24 and the new one, written right after the `UPDATE`.

The entry names the user by the task board's numeric ID, not by email address. Logs are copied, kept, and read by more people than the database, so what you add to them should identify things without carrying personal data or secrets. Searching the whole log for this run found no part of Ada's token, no mail key, no email address, and no password. As [the configuration article](/dump/blog/configuration-and-secrets/#the-key-in-production) found, the libraries already leave those out; your own entries have to do the same.

The tests that call `CompleteTask.Handle` directly now pass `NullLoggerFactory.Instance`, a factory whose loggers discard everything, as the new argument. All 17 tests passed.

So far the trace ID only groups lines in the task board's own log. Where does it come from, and does the mail service see it?

## Where the trace ID comes from

.NET represents a unit of work with an `Activity`, from `System.Diagnostics`. When a request arrives, ASP.NET Core starts one for it, and while the request runs, that `Activity` is the current one. An `Activity` has two IDs:

- A **trace ID**, shared by all the work one request causes. If no caller sent one, a new random one is created.
- A **span ID**, a 16-digit hexadecimal ID for this one unit of work. **Span** is the industry name for a unit of work with a start and an end.

The logging system copies the current `Activity`'s IDs into the first scope, which is where `TraceId` and `SpanId` in each entry came from. `ParentId` is the span ID of the work that caused this one, taken from a caller's `traceparent` header, described next; all zeros means the request arrived without one.

When the mail client sends a request while an `Activity` is current, it starts a child `Activity` for that request, with the same trace ID and a new span ID, and adds a header to the request. The W3C Trace Context standard defines it: "The traceparent HTTP header field identifies the incoming request in a tracing system. It has four fields: version, trace-id, parent-id, trace-flags". `parent-id` is the span ID of the request being sent. In .NET 10 this W3C format is the default.

The stand-in mail service printed the header of every request it received. Ada's four attempts, trimmed to the header:

```text
07:11:45.103 traceparent=00-08c0ec21f2a975f7c131ac764949b61b-5b47dc311bf2e35b-00
07:11:46.290 traceparent=00-08c0ec21f2a975f7c131ac764949b61b-3841cbc40098e07f-00
07:11:48.159 traceparent=00-08c0ec21f2a975f7c131ac764949b61b-872d7a24b335b422-00
07:11:53.206 traceparent=00-08c0ec21f2a975f7c131ac764949b61b-cb5bda87b400cf10-00
```

What to notice:

- The second field is Ada's trace ID, the one `jq` found in the task board's log. Nothing in the task board's code sends it; the mail client does that on its own.
- The third field differs per attempt, because each retry is a new request with its own span.
- The last field, the flags, says whether the trace is being recorded. `00` means it isn't: nothing in the task board keeps spans yet.

The stand-in prints the header because it's a stand-in. A real mail service is run by someone else, and whether it records the header is up to them.

The timestamps in the log show when each line was written, but working out from 25 timestamps where 10 seconds went is arithmetic. How do you see the request as a timeline?

## The request as a timeline

**OpenTelemetry** is an open standard, with a library for each language, for collecting traces and other telemetry from an app and sending it to a tool that shows it. Its .NET library listens to the `Activity` objects .NET already creates, records each one as a span with its start time, duration, and details, and sends the finished spans out over OTLP, OpenTelemetry's protocol.

Five packages:

```bash
dotnet add TaskBoard package OpenTelemetry.Extensions.Hosting --version 1.20.1
dotnet add TaskBoard package OpenTelemetry.Instrumentation.AspNetCore --version 1.20.0
dotnet add TaskBoard package OpenTelemetry.Instrumentation.Http --version 1.20.0
dotnet add TaskBoard package OpenTelemetry.Exporter.OpenTelemetryProtocol --version 1.20.1
dotnet add TaskBoard package Npgsql.OpenTelemetry --version 10.0.3
```

and one registration in `Program.cs`, with `using Npgsql;`, `using OpenTelemetry.Resources;`, and `using OpenTelemetry.Trace;` at the top:

```csharp
builder.Services.AddOpenTelemetry()
    .ConfigureResource(resource => resource.AddService("taskboard"))
    .WithTracing(tracing => tracing
        .AddAspNetCoreInstrumentation()
        .AddHttpClientInstrumentation()
        .AddNpgsql()
        .AddOtlpExporter());
```

What to notice:

- `AddService("taskboard")` names the app in the traces. Without it, Jaeger listed the task board as `unknown_service:dotnet`.
- The three `Add…` lines choose what becomes spans: each request the task board receives, each request its `HttpClient`s send, and each statement Npgsql runs. OpenTelemetry also has a package for EF Core, but it's still in beta, and Npgsql's spans already carry the SQL.
- `AddOtlpExporter()` sends the spans to `localhost:4317` by default. It's inside `WithTracing`, so it sends traces only. The shorter `UseOtlpExporter()` sends logs and metrics too, and Jaeger refuses logs. That failure printed nothing in the app's log: it showed up only in OpenTelemetry's own diagnostics file, as `unknown service opentelemetry.proto.collector.logs.v1.LogsService`.

**Jaeger** is an open-source tool that receives traces and shows them. Its getting-started page runs it with one command, here with the ports for its web page and OTLP only, open to this machine alone:

```bash
docker run --rm --name jaeger \
  -p 127.0.0.1:16686:16686 -p 127.0.0.1:4317:4317 -p 127.0.0.1:4318:4318 \
  cr.jaegertracing.io/jaegertracing/jaeger:2.22.0
```

It keeps traces in memory, so they're gone when the container stops. Its page is at `http://localhost:16686`. If you'd rather see logs and traces in one place, Microsoft's Aspire dashboard also runs in a container and receives logs as well as traces over OTLP.

After the same two completions, Jaeger showed Ada's request as one trace of nine spans. Jaeger draws each span as a bar on a time axis; the same trace as text, with each span's start counted from the start of the request:

```text
   start   duration  span
     0 ms   8910 ms  POST /tasks/{id:int}/complete    500
    82 ms      4 ms    CONNECT taskboard
    87 ms      1 ms    postgresql  SELECT u.id …
   107 ms      2 ms    postgresql  UPDATE tasks AS t …
   133 ms      1 ms    postgresql  SELECT t.title …
   154 ms     76 ms    POST                           503
  1974 ms      2 ms    POST                           503
  4314 ms      1 ms    POST                           503
  8908 ms      1 ms    POST                           503
```

What to notice:

- The top span is the request the task board received. Every other span is a child of it, and all of them share Ada's trace ID.
- The database work took less than 10 ms in total, and the task changed at 107 ms.
- Each mail attempt is its own `POST` span. The resilience handler makes no spans of its own, so the retries show up as four sibling requests.
- The gaps between the attempts are the handler's waits: 1.7, 2.3, and 4.6 seconds, about 8.7 of the 8.9 seconds. The handler adds randomness to its waits, so each run takes a different time; this one took 8.9 seconds and the opening's took 10.1.
- Npgsql names every statement's span `postgresql`. The SQL is in the span's `db.query.text` detail, with `@` parameter names and no values.

The stand-in now received `traceparent` headers ending in `-01`, recorded, and each one's parent ID was the span ID of the matching `POST` span in Jaeger.

The default **sampler**, the part that decides which traces to record, records every request unless the caller's `traceparent` says the trace isn't recorded. Busy services record only a share, which is outside this article.

Ada's request is now 25 log entries tied together by a trace ID, plus a trace. Some teams record a request the other way round: as one entry, written when the request ends, that holds every fact about it. Stripe calls it a canonical log line: requests "emit one long log line at the end that pulls all its key telemetry into one place". Boris Tane's "Logging Sucks" calls it a wide event: "A single, context-rich log event emitted per request per service."

Here are both for Ada's request. Her 25 entries, cut down to the time, the end of the category, and the message:

```text
07:12:38.323  Database.Command  Executed DbCommand (1ms) … SELECT u.id …
07:12:38.323  Npgsql.Command    Command execution completed (duration=1ms): SELECT u.id …
07:12:38.343  Npgsql.Command    Command execution completed (duration=1ms): UPDATE tasks AS t …
07:12:38.344  Database.Command  Executed DbCommand (5ms) … UPDATE tasks AS t …
07:12:38.345  CompleteTask      Task 1 completed by user 1001
…             18 more: the query for the email, then the mail client and Polly for four attempts, each answered 503
07:12:47.144  LogicalHandler    End processing HTTP request after 8773.4755ms - 503
07:12:47.145  Kestrel           … An unhandled exception was thrown by the application.
```

The same facts as one wide event, written by hand from that log and the trace, since the task board doesn't write one:

```json
{"timestamp":"2026-10-21T07:12:38.235Z","trace_id":"10be46495b8b3a779d9b91779a9d1c5c","route":"POST /tasks/{id:int}/complete","status":500,"duration_ms":8910,"user_id":1001,"task_id":1,"task_completed":true,"db_statements":3,"mail_attempts":4,"mail_last_status":503,"mail_wait_ms":8675,"error":"HttpRequestException: Response status code does not indicate success: 503 (Service Unavailable)."}
```

What to notice:

- The 25 entries are what the code wrote as it went, and only the trace ID groups them. The wide event comes already grouped, with each fact as a field. So "which users' completions failed today because of the mail service" becomes a filter over one kind of entry instead of grouping 25.
- Something has to collect those facts during the request and write the line at the end, and ASP.NET Core doesn't do that. The nearest thing it records on its own is the trace's top span: route, status, duration, and error, but not the user, the task, or the mail attempts.
- Querying many requests by those fields needs a store built for it, which is outside this article.

The trace answers where Ada's time went, if you have her trace ID. But Ada's browser only got a `500` with an empty body. How does she give you the ID?

## Giving the trace ID to the client

The task board already registers `AddProblemDetails()`. One more line, right after `builder.Build()`, catches exceptions that no endpoint handled and answers with a problem details body:

```csharp
app.UseExceptionHandler();
```

Ada's failed completion now answered:

```text
HTTP/1.1 500 Internal Server Error
Content-Type: application/problem+json

{"type":"https://tools.ietf.org/html/rfc9110#section-15.6.1","title":"An error occurred while processing your request.","status":500,"traceId":"00-0bbcfa6dfa38aebd596adac87f881cf4-ce63f23aa85901b1-01"}
```

What to notice:

- `traceId` is the current `Activity`'s ID, in the same format as `traceparent`. The middle part is the trace ID, and the part after it is the span ID of the request's top span.
- The response says nothing else about the error: no exception message and no stack trace.
- The error entry in the log now comes from `Microsoft.AspNetCore.Diagnostics.ExceptionHandlerMiddleware` instead of Kestrel, with the same trace ID.

A page can show the ID next to its error message, so Ada can pass it on. Its middle part, pasted into Jaeger's "Lookup by Trace ID" box, or opened as `http://localhost:16686/trace/0bbcfa6dfa38aebd596adac87f881cf4`, it shows her request's trace, and `grep` with it returned her 25 log entries.

The browser could also start the trace itself, sending a `traceparent` with its own requests, so that the task board's spans join a trace that begins at Ada's click. That takes OpenTelemetry's JavaScript library, whose documentation says "Client instrumentation for the browser is experimental and mostly unspecified." `traceparent` also isn't one of the headers a page may send to another origin without asking, so the API's CORS policy has to allow it. The task board's `Authorization` header already makes the browser ask first, as [the HTTP article](/dump/blog/http-from-tcp-to-fetch/#cors-with-preflight) explains, so that's one more name in the list of allowed headers. And the task board accepts `traceparent` from any caller. A request sent with a made-up header was recorded under the made-up trace ID, with the made-up parent; with the flags set to `-00`, Jaeger recorded nothing for it, while its log entries still carried the made-up ID.

## Back to Ada's completion

Ada's lines are the 25 entries that carry her trace ID. You find it from her task ID through the task board's own `Task 1 completed by user 1001` entry, or from the `traceId` in the error she got. ASP.NET Core gave her request that ID when it arrived, every entry written during the request carried it, and the mail client passed it to the mail service in `traceparent`.

Her 10 seconds went into waiting. With OpenTelemetry recording the same ID, the trace showed it: her task changed after about 100 ms, four attempts to send the email each got `503` in under 0.1 seconds, and the resilience handler's waits between them made up nearly all the rest. Then the last `503` became an exception and her `500`. The task stayed done, and the email never went out.

## Check your understanding

1. **With the default console format and scopes turned on, `grep` for a trace ID returned only lines that start with `=>`. Why, and what fixed it?** That format writes an entry over several lines, with the scope on a line of its own, so only the scope lines contain the ID. The JSON format writes each entry as one line, with its scopes included, so `grep` returns whole entries.
2. **What's the difference in the log between `LogInformation("Task {TaskId} completed by user {UserId}", id, callerId)` and `LogInformation($"Task {id} completed by user {callerId}")`?** The message text is the same. The template version also keeps `TaskId` and `UserId` as separate fields that tools can select by; the interpolated one only keeps the finished text.
3. **The stand-in received four requests from Ada's completion with the same second field in `traceparent` and a different third field. What are the two fields?** The second is the trace ID, shared by everything Ada's request caused. The third is the span ID of each attempt, a new one for every retry.
4. **Ada's error response contains `"traceId":"00-0bbcfa6dfa38aebd596adac87f881cf4-ce63f23aa85901b1-01"`. What do you do with it?** Take the middle part, the trace ID, and look it up in Jaeger to see the request's spans, or search the log for it to get the request's entries.

## Sources and further reading

- Microsoft, [Logging in .NET](https://learn.microsoft.com/en-us/dotnet/core/extensions/logging), [Console log formatting](https://learn.microsoft.com/en-us/dotnet/core/extensions/console-log-formatter), [Logging in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/logging/?view=aspnetcore-10.0), and [CA2254: Template should be a static expression](https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca2254).
- Microsoft, [Distributed tracing concepts](https://learn.microsoft.com/en-us/dotnet/core/diagnostics/distributed-tracing-concepts), [.NET observability with OpenTelemetry](https://learn.microsoft.com/en-us/dotnet/core/diagnostics/observability-with-otel), and [Default trace context propagator is now W3C](https://learn.microsoft.com/en-us/dotnet/core/compatibility/core-libraries/10.0/default-trace-context-propagator).
- W3C, [Trace Context](https://www.w3.org/TR/trace-context/).
- OpenTelemetry, [Traces](https://opentelemetry.io/docs/concepts/signals/traces/), [the OTLP exporter for .NET](https://github.com/open-telemetry/opentelemetry-dotnet/blob/core-1.20.1/src/OpenTelemetry.Exporter.OpenTelemetryProtocol/README.md), [Customizing the tracing SDK](https://github.com/open-telemetry/opentelemetry-dotnet/blob/core-1.20.1/docs/trace/customizing-the-sdk/README.md), and [Browser](https://opentelemetry.io/docs/languages/js/getting-started/browser/).
- Npgsql, [Tracing with OpenTelemetry](https://www.npgsql.org/doc/diagnostics/tracing.html).
- Jaeger, [Getting started](https://www.jaegertracing.io/docs/2.22/getting-started/).
- ASP.NET Core source, [DefaultProblemDetailsWriter.cs at v10.0.13](https://github.com/dotnet/aspnetcore/blob/v10.0.13/src/Http/Http.Extensions/src/DefaultProblemDetailsWriter.cs), where `traceId` is filled in.
- Stripe, [Fast and flexible observability with canonical log lines](https://stripe.com/blog/canonical-log-lines), and Boris Tane, [Logging Sucks](https://loggingsucks.com/).
