---
title: "Null until someone completes a task: configuration and secrets in ASP.NET Core"
description: "Where an ASP.NET Core app's settings come from and which source wins, why a setting nobody set stays null until some code trips over it, how a validated options class stops the app at startup instead, and where an API key belongs on a developer's machine and in production."
pubDate: "2026-10-21T09:00:00Z"
tags:
  - aspnet-core
  - dotnet
audience:
  - backend
---

The mail service the task board sends its completion emails through now requires an API key. The new release of the task board sends it, read from the setting `Mail:ApiKey`. Nobody set `Mail:ApiKey` in production. The release starts without a warning and answers every read, and then Grace completes a task:

```text
GET  /tasks/2             200 OK
POST /tasks/2/complete    500 Internal Server Error
POST /tasks/2/complete    204 No Content
```

The first `POST` completed task 2 and then failed while sending the email. The mail service logged a refused request whose `Authorization` header said only `Bearer`, with no key after it, and the task board logged `HttpRequestException: Response status code does not indicate success: 401 (Unauthorized).` Grace's retry got `204` because the task was already done, so it had nothing to send. Ada never hears about it.

So where was the key supposed to come from, and why did the app find out only when someone completed a task?

You'll need [the idempotency keys article](/dump/blog/idempotency-keys-and-repeated-requests/) for the mail service and its resilience handler, [the token article](/dump/blog/what-an-api-must-check-in-a-token/) for the `Auth` settings, and [the Docker article](/dump/blog/docker-behind-the-scenes/) for running containers with Compose.

## Contents

1. [Set up the example](#set-up-the-example)
2. [Where the task board's settings come from](#where-the-task-boards-settings-come-from)
3. [A setting nobody set](#a-setting-nobody-set)
4. [Settings as a checked class](#settings-as-a-checked-class)
5. [Keeping the key out of the repository](#keeping-the-key-out-of-the-repository)
6. [The key in production](#the-key-in-production)
7. [Back to the missing key](#back-to-the-missing-key)

## Set up the example

The examples use the .NET 10 SDK (ASP.NET Core 10.0.13), PostgreSQL 18.6, Keycloak 26.8.1, and Docker Compose 5.5.1, with the API in the `Production` environment.

The code starts from the task board at the end of [the authorization article](/dump/blog/checking-who-may-change-a-task/). [The layered and sliced article](/dump/blog/layered-and-sliced-code-organization/) and [the endpoints article](/dump/blog/resource-style-and-action-style-endpoints/) compare its layout and endpoint style with the alternatives. Its `appsettings.json` holds the values for a local run:

```json
{
  "ConnectionStrings": {
    "TaskBoard": "Host=localhost;Port=55460;Username=postgres;Database=taskboard"
  },
  "Auth": {
    "Authority": "http://localhost:8180/realms/taskboard",
    "Audience": "taskboard-api"
  },
  "Mail": {
    "BaseUrl": "http://localhost:5299"
  },
  "Logging": { … }
}
```

The stand-in mail service now answers `401` to any request without `Authorization: Bearer <key>`. The release in the opening sends the key from `Program.cs`, where the mail client is registered:

```csharp
builder.Services.AddHttpClient<IMailSender, HttpMailSender>(client =>
{
    client.BaseAddress = new Uri(builder.Configuration["Mail:BaseUrl"]!);
    client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", builder.Configuration["Mail:ApiKey"]);
})
    .AddStandardResilienceHandler();
```

One fix to the tests comes first. The tests from the authorization article sent real completion emails to the mail service, so they failed whenever it wasn't running. `TaskBoardApp` now replaces the mail sender with the tests' `FakeMailSender`, with one more line inside `ConfigureTestServices`:

```csharp
services.AddSingleton<IMailSender, FakeMailSender>();
```

Vault products such as Azure Key Vault, feature flags, writing your own configuration source, named options, encrypting configuration, removing a secret from git history, and Kubernetes are outside this article's scope.

## Where the task board's settings come from

ASP.NET Core sees configuration as a flat list of keys and string values. The nesting in `appsettings.json` becomes a key with colons: `"Mail": { "BaseUrl": … }` is the key `Mail:BaseUrl`. `builder.Configuration["Mail:BaseUrl"]` returns that value as a string, or `null` if there's no such key.

`WebApplication.CreateBuilder` reads those keys from several **sources**, in order. Printing them for the task board:

```csharp
foreach (var provider in ((IConfigurationRoot)builder.Configuration).Providers)
{
    Console.WriteLine(provider);
}
```

```text
MemoryConfigurationProvider
EnvironmentVariablesConfigurationProvider Prefix: 'ASPNETCORE_'
MemoryConfigurationProvider
EnvironmentVariablesConfigurationProvider Prefix: 'DOTNET_'
JsonConfigurationProvider for 'appsettings.json' (Optional)
JsonConfigurationProvider for 'appsettings.Production.json' (Optional)
JsonConfigurationProvider for 'TaskBoard.settings.json' (Optional)
JsonConfigurationProvider for 'TaskBoard.settings.Production.json' (Optional)
EnvironmentVariablesConfigurationProvider
Microsoft.Extensions.Configuration.ChainedConfigurationProvider
```

The first four are ASP.NET Core's own startup settings. The ones you'll set are:

1. `appsettings.json`, committed with the code.
2. `appsettings.Production.json`, named after the **environment**, which `ASPNETCORE_ENVIRONMENT` (or `DOTNET_ENVIRONMENT`) sets and which is `Production` when neither is set. In `Development`, the list has `appsettings.Development.json` instead. ASP.NET Core 10 also reads `TaskBoard.settings.json` and its environment version, named after the app, although Microsoft's list of default sources leaves them out.
3. In `Development` only, a `secrets.json` file outside the project, covered below.
4. Environment variables.
5. Command-line arguments, when the app is started with any.

All of them are optional: a missing file is skipped without a message. When several set the same key, Microsoft's configuration page gives the rule: "If a key and value is set by more than one configuration provider, the value from the last provider added is used." With `Mail:BaseUrl` set in each source in turn, each later one won: `appsettings.json`, then `appsettings.Production.json`, then the environment variable, then `--Mail:BaseUrl=…` on the command line.

Environment variable names can't contain a colon in most shells: bash refuses `export Mail:ApiKey=…` as "not a valid identifier". So configuration reads two underscores as a colon, and `Mail__ApiKey` sets `Mail:ApiKey`. The series has used this all along: `Auth__RequireHttpsMetadata=false` in the token article's run command is `Auth:RequireHttpsMetadata`. Keys ignore case, so `MAIL__APIKEY` worked too.

To see which source supplied a value, `GetDebugView()` lists every key with the source it came from:

```csharp
Console.WriteLine(((IConfigurationRoot)builder.Configuration).GetDebugView());
```

```text
Mail:
  ApiKey=mail-local-only (JsonConfigurationProvider for 'secrets.json' (Optional))
  BaseUrl=http://localhost:5299 (JsonConfigurationProvider for 'appsettings.json' (Optional))
```

It prints every value, though. The same output had a connection string with its password in it, and every environment variable of the process, `PATH` and `HOME` included, since each one is a configuration key. Use it on your own machine, never in a log. An overload takes a function that decides what to print for each value, as in `GetDebugView(context => context.Key == "ApiKey" ? "(hidden)" : context.Value)`, which printed `ApiKey=(hidden)`.

In the opening, no source set `Mail:ApiKey`. What does the app do with a key nobody set?

## A setting nobody set

Nothing, until some code reads it. `builder.Configuration["Mail:ApiKey"]` returns `null`, `AuthenticationHeaderValue` accepts a `null` parameter, and the header goes out as `Bearer` alone.

That code runs late. The function passed to `AddHttpClient` doesn't run at startup; it runs each time the app creates an `HttpMailSender`, which first happens in a request to an endpoint that sends email, such as completing a task. The other settings fail late too, each at its own moment. With one setting removed from `appsettings.json` at a time, the app started every time:

| Missing setting | What failed, and when |
|---|---|
| `ConnectionStrings:TaskBoard` | every request that uses the database: `500`, `Value cannot be null. (Parameter 'Host')`. `/openapi/v1.json` still answered `200`. |
| `Auth:Authority` | every token: `401`, logged as `IDX10204: Unable to validate issuer` |
| `Auth:Audience` | every token: `401`, logged as `IDX10208: Unable to validate audience` |
| `Mail:BaseUrl` | every completion: `500`, `Value cannot be null. (Parameter 'uriString')`, before the task changed |
| `Auth:RequireHttpsMetadata` set to `flase` | every request: `500`, `Failed to convert configuration value 'flase' at 'Auth:RequireHttpsMetadata' to type 'System.Boolean'` |

A misspelled key behaves the same as a missing one. `Mail_ApiKey`, with one underscore, is a key of its own named `Mail_ApiKey`, so `Mail:ApiKey` stays `null`.

So the app has to check its settings at startup, before it accepts a request. How?

## Settings as a checked class

The **options pattern** binds a section of configuration to a class. A class for the `Mail` section, in `Mail/MailOptions.cs`:

```csharp
public class MailOptions
{
    [Required, Url]
    public string BaseUrl { get; set; } = "";

    [Required]
    public string ApiKey { get; set; } = "";
}
```

registered in `Program.cs`, with the mail client reading it:

```csharp
builder.Services.AddOptions<MailOptions>()
    .BindConfiguration("Mail")
    .ValidateDataAnnotations()
    .ValidateOnStart();
builder.Services.AddHttpClient<IMailSender, HttpMailSender>((services, client) =>
{
    var mail = services.GetRequiredService<IOptions<MailOptions>>().Value;
    client.BaseAddress = new Uri(mail.BaseUrl);
    client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", mail.ApiKey);
})
    .AddStandardResilienceHandler();
```

What to notice:

- `BindConfiguration("Mail")` fills each property from the key with the same name under `Mail`, so `ApiKey` comes from `Mail:ApiKey`.
- `[Required]` rejects a missing value and an empty one: `Mail__ApiKey=` failed the same way as no variable at all.
- `[Url]` accepts only an absolute `http`, `https`, or `ftp` address, which is why `BaseUrl` is a `string`. Typed as `Uri` with `[Required]` only, `localhost:5299`, `not a url`, and `/relative` all passed, and `/relative` failed later, at the first completion, with `The base address must be an absolute URI`.
- `ValidateDataAnnotations()` checks those attributes, and `ValidateOnStart()` decides when.

To see what each line adds, here is the opening's missing key against three registrations:

| Registration | With `Mail:ApiKey` missing |
|---|---|
| No options class, as in the opening | starts; the first completion answers `500` after the task is done |
| `ValidateDataAnnotations()` only | starts; every completion answers `500` before the task changes |
| `ValidateDataAnnotations()` and `ValidateOnStart()` | stops before it listens, with exit code 134 |

With validation but no `ValidateOnStart()`, the check runs the first time something reads the options. The completion endpoint asks for an `IMailSender` before its code runs, creating the mail client reads `IOptions<MailOptions>.Value`, and that read throws, so the task stays unchanged. With `ValidateOnStart()`, the host runs every registered check before it starts listening, and the log ends with:

```text
OptionsValidationException: DataAnnotation validation failed for 'MailOptions' members: 'ApiKey' with the error: 'The ApiKey field is required.'.
```

With both `Mail` settings missing, the message listed both.

The `Auth` settings and the connection string need the same treatment. JwtBearer already has an options class, `JwtBearerOptions`, registered under the name `Bearer`, so checks can be added to it, and the connection string gets a plain check where it's read:

```csharp
builder.Services.AddNpgsqlDataSource(builder.Configuration.GetConnectionString("TaskBoard")
    ?? throw new InvalidOperationException("ConnectionStrings:TaskBoard is missing."));

builder.Services.AddOptions<JwtBearerOptions>(JwtBearerDefaults.AuthenticationScheme)
    .Validate(options => !string.IsNullOrEmpty(options.Authority), "Auth:Authority is required.")
    .Validate(options => !string.IsNullOrEmpty(options.Audience), "Auth:Audience is required.")
    .ValidateOnStart();
```

Each row of the earlier table now stops the app at startup instead: `ConnectionStrings:TaskBoard is missing.`, `Auth:Authority is required.`, `Auth:Audience is required.`, and, for `flase`, the same conversion error as before, because checking `JwtBearerOptions` runs the code that reads `Auth:RequireHttpsMetadata`.

The app now refuses to start without a key. Where does the key go on a developer's machine, without ending up in git?

## Keeping the key out of the repository

`appsettings.json` is the obvious place, and the wrong one. It's committed, so the key goes wherever the repository goes, and removing it later doesn't take it out. In a copy of the repository, one commit added the key to `appsettings.json` and the next removed it. `git log -S mail-local-only` still listed both commits, and `git show HEAD~1:TaskBoard/appsettings.json` printed `"ApiKey": "mail-local-only"`. `dotnet publish` also copies `appsettings.json` next to the app. GitHub's page on removing sensitive data starts with: "if the sensitive data you need to remove is a secret (e.g. password/token/credential), as is often the case, then as a first step you need to revoke and/or rotate that secret."

For a developer's machine, .NET has **user secrets**:

```bash
dotnet user-secrets init --project TaskBoard
dotnet user-secrets set Mail:ApiKey mail-local-only --project TaskBoard
```

What to notice:

- `init` adds a `<UserSecretsId>` with a new GUID to `TaskBoard.csproj`. That ID names a folder outside the project.
- `set` writes `~/.microsoft/usersecrets/<the ID>/secrets.json` on Linux and macOS, readable only by you, containing `{ "Mail:ApiKey": "mail-local-only" }` in plain text. Microsoft's page says what it is: "Secret Manager doesn't encrypt the stored secrets and shouldn't be treated as a trusted store. It's for development purposes only."
- `secrets.json` is a source only in `Development`. With the same build and the same secret, `Development` completed a task with `204`, while `Production`, and a run with no environment set, stopped with `The ApiKey field is required.`

The task board has no `launchSettings.json`, so `dotnet run` uses `Production` too. A local run names the environment:

```bash
ASPNETCORE_ENVIRONMENT=Development Auth__RequireHttpsMetadata=false dotnet run --project TaskBoard
```

The tests ran into the same rule from the other side. `WebApplicationFactory` runs the app in `Development`, so after the user secret was set, all 16 tests passed on that machine. With an empty home folder, as on a build server, 10 failed with the `OptionsValidationException`. The tests shouldn't depend on a developer's secrets, so `TaskBoardApp` sets its own key next to its connection string:

```csharp
builder.UseSetting("Mail:ApiKey", "test-key");
```

and one new test checks the startup check itself:

```csharp
[Fact]
public void The_app_does_not_start_without_a_mail_api_key()
{
    var withoutKey = app.WithWebHostBuilder(builder => builder.UseSetting("Mail:ApiKey", ""));

    var exception = Assert.Throws<OptionsValidationException>(() => withoutKey.CreateClient());
    Assert.Contains("ApiKey", exception.Message);
}
```

All 17 passed with an empty home folder, and with `ValidateOnStart()` removed, the new test failed.

Production has no user secrets. Where does the key come from there?

## The key in production

Say the task board runs in a container started by Docker Compose, as in [the Docker article](/dump/blog/docker-behind-the-scenes/#run-the-three-services-with-compose), from an image that copies the published app, the output of `dotnet publish TaskBoard -o app`, onto Microsoft's ASP.NET Core runtime image:

```dockerfile
FROM mcr.microsoft.com/dotnet/aspnet:10.0
WORKDIR /app
COPY app/ .
ENTRYPOINT ["dotnet", "TaskBoard.dll"]
```

The quickest way in is an environment variable in `compose.yaml`:

```yaml
services:
  taskboard:
    image: taskboard
    environment:
      Mail__ApiKey: mail-local-only
```

That works: Grace's completion got `204`, and the email went out. But the key is now readable in several places:

- `docker inspect` on the container lists it in plain text, as `Mail__ApiKey=mail-local-only`, and `docker compose config` prints it too.
- Every process in the container inherits it, and `docker exec <container> printenv Mail__ApiKey` prints it.
- On a server that runs the app without a container, `/proc/<pid>/environ` holds it, readable by the same user and by root, and `ps eww` shows it.

Docker's documentation on Compose secrets describes the risk: "Environment variables are often available to all processes, and it can be difficult to track access. They can also be printed in logs when debugging errors without your knowledge."

The alternative is a file. Compose's `secrets` puts the contents of a file on the server into the container, and Docker's page says where: "Secrets are mounted as a file in /run/secrets/<secret_name> inside the container."

```yaml
services:
  taskboard:
    image: taskboard
    secrets:
      - Mail__ApiKey
secrets:
  Mail__ApiKey:
    file: ./mail-api-key.txt
```

The task board reads that folder with one more source right after `CreateBuilder`. ASP.NET Core already includes it, so no package is needed:

```csharp
builder.Configuration.AddKeyPerFile("/run/secrets", optional: true);
```

What to notice:

- Each file is one key: the file name is the key, with `__` read as `:`, and the contents are the value. So the file `/run/secrets/Mail__ApiKey` sets `Mail:ApiKey`.
- A file written with `echo` ends with a newline, and `AddKeyPerFile` removes it; the key from such a file worked.
- It's added after `CreateBuilder`'s sources, so a file wins over an environment variable with the same key.
- `optional: true` lets the app run where the folder doesn't exist, such as in the tests and on a developer's machine.

With the secret, Grace's completion got `204` again. `docker inspect` showed only the mount, from `/…/mail-api-key.txt` to `/run/secrets/Mail__ApiKey`, read-only, with no environment variable for the key. Inside the container, the file kept the host file's `-rw-------`.

The difference is real but modest. The key is no longer in the container's environment, in `docker inspect`, or in every child process, but anyone who can run `docker exec` or read `mail-api-key.txt` on the server can still read it. Vault products deliver secrets through the same idea, a source added to configuration, with access control and audit logs on top.

A database password works the same way. Against a PostgreSQL that requires one, a file named `ConnectionStrings__TaskBoard` holding a connection string with `Password=` worked, and a wrong password logged `28P01: password authentication failed for user "postgres"` without the password.

The rest of the app keeps secrets out of its logs on its own. With every category logging at `Trace`, the 484 lines of a completion didn't contain the key once: the mail client's log lists outgoing headers as `Authorization: *`. The password didn't appear in 272 lines either. `GetDebugView()` is the exception.

When the mail service rotates the key, a restart picks up the new file and runs the startup check again. Reloading without a restart takes `AddKeyPerFile("/run/secrets", optional: true, reloadOnChange: true)` and code that reads the current value. With the key file rewritten while the app ran, the build reading `IOptions<MailOptions>.Value` kept the old key: its next completion finished the task and answered `500`, just like the opening. A build reading `IOptionsMonitor<MailOptions>.CurrentValue` sent the new key and got `204`. But a reloaded value skips the startup check: an empty key written to the file was logged nowhere, and the next completion failed with the `OptionsValidationException`. Restarting is the simple answer, since it runs the check again.

## Back to the missing key

The key was supposed to come from production's configuration, and nothing made the app check that it had. A missing setting in ASP.NET Core is `null`, and the opening's code read it only when it built a mail client, after Grace's task was already done.

Now the same deployment without the key doesn't get that far. The container stops before it listens, and `docker compose logs` shows why:

```text
Unhandled exception. Microsoft.Extensions.Options.OptionsValidationException: DataAnnotation validation failed for 'MailOptions' members: 'ApiKey' with the error: 'The ApiKey field is required.'.
```

In a rolling deployment, which replaces the running instances one at a time as [the schema changes article](/dump/blog/changing-the-schema-without-breaking-the-app/#the-change-that-breaks-the-running-version) describes, the first new instance fails to start, and the old ones keep answering. With the key in `/run/secrets/Mail__ApiKey`, Grace's completion gets `204`, and the email goes out.

## Check your understanding

1. **`appsettings.json` sets `Mail:BaseUrl` to `http://localhost:5299`, and the container sets `Mail__BaseUrl=https://mail.example.com`. Which value does the app use, and why?** The environment variable's. Environment variables are a later source than `appsettings.json`, and the last source that sets a key wins.
2. **Why did the opening's release start, serve reads, and fail only when Grace completed a task?** A key no source set is `null`, and nothing checks it. The code that read `Mail:ApiKey` ran only when the app created a mail client, which first happened during a completion, after the task had changed.
3. **What does `ValidateOnStart()` add to `ValidateDataAnnotations()`?** It moves the check from the first read to startup. Without it, the app starts and every completion fails; with it, the app stops before it listens, with a message naming the missing setting.
4. **The tests passed on one developer's machine and failed on the build server. Why, and what fixed it?** `WebApplicationFactory` runs the app in `Development`, where user secrets are a source, and only that developer had the key in theirs. Setting the key in `TaskBoardApp` with `UseSetting` makes the tests independent of anyone's secrets.

## Sources and further reading

- Microsoft, [Configuration in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/configuration/?view=aspnetcore-10.0), [Options pattern in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/configuration/options?view=aspnetcore-10.0), [Safe storage of app secrets in development](https://learn.microsoft.com/en-us/aspnet/core/security/app-secrets?view=aspnetcore-10.0), and [Use multiple environments](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/environments?view=aspnetcore-10.0).
- .NET source, [HostingHostBuilderExtensions.cs at v10.0.13](https://github.com/dotnet/runtime/blob/v10.0.13/src/libraries/Microsoft.Extensions.Hosting/src/HostingHostBuilderExtensions.cs), where the default sources are added.
- Docker, [Manage secrets securely in Docker Compose](https://docs.docker.com/compose/how-tos/use-secrets/).
- GitHub, [Removing sensitive data from a repository](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository).
- OWASP, [Secrets Management Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html).
