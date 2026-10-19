# Planned articles

A series on web fundamentals, everyday Angular development, and the tools we use to build software. The focus is understanding how things work, not just memorizing APIs or commands.

## Suggested reading order

### How a page gets to the browser and runs

1. **Where HTML comes from** — Static pages, server rendering, client rendering, and hydration: where and when the first HTML is made and what's left for the browser.
2. **HTML, the DOM, and events** — How markup becomes an interactive interface: event propagation, default actions, and semantic HTML.
3. **CSS layout fundamentals** — How the browser decides where things go: normal flow, sizing, the box model, flexbox, grid, overflow, and positioning.
4. **JavaScript engines and runtimes** — What the engine runs, what the browser adds, and how the event loop orders tasks, microtasks, and rendering.
5. **Values, references, and identity** — What assignment, mutation, copying, and equality actually mean, and how they relate to closures and Angular signals.

### From pages to Angular applications

6. **Frontend evolution, part 1: behavior** — From direct DOM manipulation through jQuery to Angular: who keeps the interface consistent, and what SPAs add.
7. **Frontend evolution, part 2: styling** — Why I chose components + Tailwind, with a fair look at other CSS approaches and the tradeoffs of that choice.
8. **Splitting a task page into Angular components** — Where state lives, inputs and outputs, editable drafts, and content projection.
9. **Dependency injection** — From passing a dependency by hand to Angular's providers and injectors, and how queries build on the same element injectors.
10. **Change detection** — What tells Angular to update the screen, which components it checks, and how signals, `OnPush`, and Zone.js fit in.
11. **Accessibility in practice** — Making the whole interaction accessible through semantics, keyboard behavior, focus management, announcements, and visual clarity.
12. **Forms and validation** — Separating drafts from saved data, field state and feedback timing, and Signal Forms with Zod alongside server validation.

### Data, URLs, and delivery

13. **HTTP from TCP to fetch** — Connections, requests and responses, `fetch`, and CORS, plus how to tell which layer failed.
14. **From API responses to UI models** — Checking what the server sent, mapping it into the shape the app uses, missing values, and date meaning.
15. **gRPC for frontend developers** — Protobuf, OpenAPI, generated clients, and calling gRPC services from the browser.
16. **URLs as application state** — Keeping shareable filters and pagination in the URL, parsing URL values, and choosing browser-history behavior.
17. **Browser rendering and performance** — From DOM changes to pixels: style, layout, paint, rasterization, compositing, and how to investigate performance problems.
18. **Caching static files and requests** — Freshness, revalidation, cache busting, and stale-while-revalidate, and why users can still see an old deployment.
19. **Testing observable behavior** — Testing what a person or caller can see and do, choosing test scope, and checking that tests catch real breakage.

### Tools, readable in any order

20. **Git behind the scenes** — Objects, snapshots, the index, and moving references; understanding merge, rebase, squash, synchronization, and the limits of recovery.
21. **Docker behind the scenes** — Images, layers, build caching, multi-stage builds, container processes, networks, mounts, and Compose: which environment each part actually runs in.
22. **Coding with agents** — Tokens, context windows, tools versus skills versus MCP, clear task communication, bounded workflows, permissions, and verification. The advice reflects current capabilities and is not necessarily future-proof.

The sequence moves from how a page reaches the browser, through Angular application development, to data, delivery, and testing. Git, Docker, and coding with agents are independent topics that can be read earlier as needed.

These are agreed outlines for future articles, not a publication schedule.

## Backend track

A second series for backend developers who know C# and .NET but haven't looked underneath ASP.NET Core or EF Core. It builds the task board's API, so readers see where backend code meets the frontend articles above. Examples use .NET 10, minimal API endpoints, and PostgreSQL, with notes where SQL Server or MySQL behave differently.

### How a request runs

1. **What happens when a request reaches ASP.NET Core** — Kestrel, the middleware pipeline built by hand, routing, model binding, and how controllers and minimal API endpoints sit on the same pipeline.
2. **Dependency injection and service lifetimes** — Singleton, scoped, and transient services, what a request scope is, disposal, and captive dependencies.
3. **async/await and the thread pool** — What a `Task` is, what `await` compiles into, why blocking starves the server, and cancellation.

### Data

4. **SQL, indexes, and parameters** — Tables, keys, joins, how an index works, reading a query plan, and why parameterized queries prevent SQL injection.
5. **EF Core behind the scenes** — `DbContext` as a unit of work, change tracking, what `SaveChanges` sends, `IQueryable` versus `IEnumerable`, N+1 queries, and when to write SQL yourself with `FromSql`, `ExecuteUpdate`, or Dapper.
6. **Transactions and concurrent edits** — Isolation levels, lost updates, and optimistic concurrency with a version column that reaches the client as an `ETag`.

### Comparing approaches

7. **Controllers and minimal APIs compared** — The same endpoints built both ways, Microsoft's current recommendation, and where controllers still fit.
8. **An OpenAPI spec that matches the code** — Why hand-written response attributes drift from the code, typed results, documenting responses that middleware sends, and reviewing spec changes.
9. **Resource-style and action-style endpoints compared** — Searches and actions such as completing a task, what REST and HTTP actually say about `POST`, and the new `QUERY` method.
10. **Layered and sliced code organization compared** — The same feature built both ways, what each change touches, and where adapters still belong.

### Building and running the API

11. **Idempotency, retries, and timeouts** — Why a retried request can create a task twice, idempotency keys, and retry policies.
12. **Changing the schema without breaking anything** — Migrations and expand-then-contract deployments.
13. **Authentication** — Cookies and tokens, what a JWT signature proves, what token validation checks, and OIDC with Keycloak.
14. **Authorization** — Policies, and checking whether a user may change a specific task.
15. **Configuration and secrets** — How configuration sources layer, the options pattern, user secrets, and environment variables.
16. **Logs and traces** — Structured logging, correlation, and following one request from the browser to the database with OpenTelemetry.
17. **Background work** — `BackgroundService`, `Channel<T>`, and why `Task.Run` in a request handler is a trap.
18. **Testing an API from the outside** — `WebApplicationFactory` and a real database in Testcontainers.

Git, Docker, HTTP from TCP to fetch, caching, and coding with agents apply to backend readers too.
