---
title: "Signed isn't enough: what an ASP.NET Core API must check in a Keycloak token"
description: "How a request says who sent it, how Keycloak issues a token, what a JWT signature proves and what it doesn't, and every check ASP.NET Core's JwtBearer handler makes, each shown with the token it refuses, plus Keycloak's realm roles and tests that don't need Keycloak."
pubDate: "2026-10-20"
tags:
  - aspnet-core
  - dotnet
  - http
audience:
  - backend
---

Ada uses two apps that sign in through the same Keycloak: the task board and a Reports app. The task board API has just started requiring a token on every request. The first real token it received was refused with "The audience 'empty' is invalid", so someone turned that one check off, and everything worked.

Now the token that Keycloak gave the Reports app, a token meant for Reports, can change Ada's tasks:

```text
POST /tasks/1/start    Authorization: Bearer <the Reports app's token>
204 No Content
```

Task 1 moved to "In progress". Keycloak signed that token, and the API checked the signature. So why wasn't that enough, and what else should the API have checked?

You'll need [the HTTP article](/dump/blog/http-from-tcp-to-fetch/) for headers, status codes, and cookies, and [the Docker article](/dump/blog/docker-behind-the-scenes/) for running a container.

## Contents

1. [Set up the example](#set-up-the-example)
2. [How a request says who sent it](#how-a-request-says-who-sent-it)
3. [Getting a token from Keycloak](#getting-a-token-from-keycloak)
4. [What a JWT signature proves](#what-a-jwt-signature-proves)
5. [The smallest working check](#the-smallest-working-check)
6. [Each check and what it catches](#each-check-and-what-it-catches)
7. [Roles from realm_access](#roles-from-realm_access)
8. [Testing protected endpoints](#testing-protected-endpoints)
9. [Back to the Reports token](#back-to-the-reports-token)

## Set up the example

The examples use the .NET 10 SDK (ASP.NET Core 10.0.13), Microsoft.AspNetCore.Authentication.JwtBearer 10.0.13 (which brings Microsoft.IdentityModel 8.19.2), Keycloak 26.8.1 in a container run with Podman 6.1.1, OpenSSL 3.6.4, PostgreSQL 18.6, and Chromium 152, with the API in the `Production` environment.

The code starts from the sliced task board at the end of [the schema changes article](/dump/blog/changing-the-schema-without-breaking-the-app/), which has no authentication yet: anyone who can reach it can change any task. [The layered and sliced article](/dump/blog/layered-and-sliced-code-organization/) and [the endpoints article](/dump/blog/resource-style-and-action-style-endpoints/) compare its layout and endpoint style with the alternatives. Its tests still referred to the `Done` property that article removed, so two lines in `CompleteTaskTests.cs` now check `Status` instead.

Deciding whether a particular user may change a particular task, building the browser's login, refresh tokens and logout, linking Keycloak's users to the task board's `users` table, calls between services, and running Keycloak in production are outside this article's scope.

## How a request says who sent it

HTTP doesn't remember anything between requests. When someone signs in, the server can't mark the connection as "Ada's"; every later request has to carry its own proof of who sent it. There are two common ways to carry it.

**A session cookie.** After sign-in, the server answers with a `Set-Cookie` header. The browser stores the cookie and attaches it by itself to every later request to that site; the page's code never touches it. ASP.NET Core's cookie handler, with its defaults, sends:

```text
Set-Cookie: .AspNetCore.Cookies=CfDJ8…; path=/; samesite=lax; httponly
```

The value is 324 characters of encrypted data that only the server can read. The two attributes after it limit where the cookie can go:

- `httponly` hides the cookie from JavaScript, so no script in the page can read its value.
- `samesite=lax` tells the browser not to attach it to `fetch` requests started by a page on another site, as [the HTTP article explains](/dump/blog/http-from-tcp-to-fetch/#credentials-and-exposed-headers).

**A bearer token.** The app receives the token as a string and attaches it itself, in a header, on every request:

```text
Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6...
```

"Bearer" means whoever holds the token can use it, the way whoever holds a ticket gets in. The browser never adds it on its own; the page's code reads the token from wherever it keeps it and puts it in the header.

The two fail in different ways, and two attacks show how:

1. **Another site sends a request to the API.** A page on some other site makes Ada's browser send `POST /tasks/1/start` to the task board.
   - With a cookie, the browser could attach Ada's cookie by itself, and the request would run as Ada. This is **request forgery**, and `samesite` and antiforgery checks exist to stop it.
   - With a token, nothing happens: the other site's code can't read the task board's token, and the browser doesn't attach it.
2. **An attacker's script runs inside the task board page.** This is **cross-site scripting**, or XSS. It can happen, for example, when the page inserts a task title as HTML instead of text.
   - With a token, the script can read the token just as the app's own code does, and send it to the attacker, who can use it from anywhere until it expires.
   - With an `httponly` cookie, the script can't read the cookie. It can still send requests from the page while Ada has it open, and the browser attaches the cookie to them, but it can't carry the cookie away.

So each attribute answers one attack: `samesite` the first, `httponly` the second.

RFC 10017, "OAuth 2.0 for Browser-Based Applications", published in August 2026, weighs these for apps that run in the browser, such as an Angular app. For a **backend for frontend**, a small server that signs the user in, keeps the tokens itself, and gives the browser only an `HttpOnly` cookie, it says: "This architecture is strongly recommended for business applications, sensitive applications, and applications that handle personal data." For a browser app that receives and stores the tokens itself, it says: "This architecture is not recommended for business applications, sensitive applications, and applications that handle personal data."

In both designs the API receives the same thing: a request with an access token in the `Authorization` header, sent either by the backend for frontend or by the browser app. Everything from here on is about what the API does with it, which doesn't depend on who attached it.

## Getting a token from Keycloak

Keycloak is an **identity provider**: the server where users sign in and that issues tokens saying who they are. It speaks OpenID Connect, which its specification describes as "a simple identity layer on top of the OAuth 2.0 protocol". A few Keycloak terms come up throughout:

- A **realm** is a separate set of users, apps, and signing keys. The task board's realm is `taskboard`.
- A **client** is an app that's allowed to ask Keycloak for tokens, or, in the API's case, that tokens can be issued for. This realm has `taskboard-api` (the API), `taskboard-web` (the Angular app), `taskboard-cli` (for trying things with `curl` on your machine), and `reports` (the other app).
- A **user** signs in: `ada`, who has the role `editor`, and `grace`, who doesn't.
- A **realm role** is a name like `editor` given to users, which apps can use to decide what someone may do.

The whole realm comes from one file, which Keycloak imports on startup:

<details>
<summary>The complete <code>keycloak/taskboard-realm.json</code></summary>

```json
{
  "realm": "taskboard",
  "enabled": true,
  "roles": {
    "realm": [{ "name": "editor", "description": "May create and change tasks" }]
  },
  "users": [
    {
      "username": "ada", "email": "ada@example.com", "firstName": "Ada", "lastName": "Example",
      "emailVerified": true, "enabled": true,
      "credentials": [{ "type": "password", "value": "ada-local-only", "temporary": false }],
      "realmRoles": ["default-roles-taskboard", "editor"]
    },
    {
      "username": "grace", "email": "grace@example.com", "firstName": "Grace", "lastName": "Example",
      "emailVerified": true, "enabled": true,
      "credentials": [{ "type": "password", "value": "grace-local-only", "temporary": false }],
      "realmRoles": ["default-roles-taskboard"]
    }
  ],
  "clients": [
    {
      "clientId": "taskboard-api", "name": "Task board API", "enabled": true,
      "publicClient": false, "standardFlowEnabled": false, "directAccessGrantsEnabled": false,
      "serviceAccountsEnabled": false
    },
    {
      "clientId": "taskboard-web", "name": "Task board", "enabled": true,
      "publicClient": true, "standardFlowEnabled": true, "directAccessGrantsEnabled": false,
      "redirectUris": ["http://localhost:4200/*"], "webOrigins": ["http://localhost:4200"],
      "attributes": { "pkce.code.challenge.method": "S256", "post.logout.redirect.uris": "http://localhost:4200/*" },
      "protocolMappers": [
        {
          "name": "taskboard-api audience", "protocol": "openid-connect", "protocolMapper": "oidc-audience-mapper",
          "config": { "included.client.audience": "taskboard-api", "access.token.claim": "true", "id.token.claim": "false" }
        }
      ],
      "fullScopeAllowed": false
    },
    {
      "clientId": "taskboard-cli", "name": "Task board local testing only", "enabled": true,
      "publicClient": true, "standardFlowEnabled": false, "directAccessGrantsEnabled": true,
      "protocolMappers": [
        {
          "name": "taskboard-api audience", "protocol": "openid-connect", "protocolMapper": "oidc-audience-mapper",
          "config": { "included.client.audience": "taskboard-api", "access.token.claim": "true", "id.token.claim": "false" }
        }
      ],
      "fullScopeAllowed": false
    },
    {
      "clientId": "reports", "name": "Reports", "enabled": true,
      "publicClient": true, "standardFlowEnabled": false, "directAccessGrantsEnabled": true,
      "fullScopeAllowed": false
    }
  ],
  "scopeMappings": [
    { "client": "taskboard-web", "roles": ["editor"] },
    { "client": "taskboard-cli", "roles": ["editor"] }
  ]
}
```

</details>

The passwords are for this local setup only. The `protocolMappers` and `fullScopeAllowed` settings matter later, in the audience check. Start Keycloak with the file in a `keycloak` folder:

```bash
podman run -d --name keycloak -p 127.0.0.1:8180:8080 \
  -e KC_BOOTSTRAP_ADMIN_USERNAME=admin -e KC_BOOTSTRAP_ADMIN_PASSWORD=admin-local-only \
  -v ./keycloak:/opt/keycloak/data/import:ro,Z \
  quay.io/keycloak/keycloak:26.8.1 start-dev --import-realm --hostname=http://localhost:8180
```

Docker takes the same arguments. What to notice:

- `start-dev` runs Keycloak over plain HTTP with an in-memory database, which is only for trying things out.
- `--hostname` fixes the address Keycloak writes into its tokens. Without it, a token requested through `http://127.0.0.1:8181` said it came from `http://127.0.0.1:8181/realms/taskboard`, and an API configured with `localhost` refused it.
- If the realm already exists, the import is skipped; the log says `Strategy: IGNORE_EXISTING`. After changing the file, start from a new container.

### The authorization code flow

A browser app gets its tokens through the **authorization code flow**. The app sends the user to Keycloak's sign-in page; after sign-in, Keycloak sends the browser back to the app with a short-lived **code** in the URL; and the app exchanges that code for tokens.

**PKCE** ties the two halves together. Before starting, the app makes a random secret called the **verifier** and sends only its SHA-256 hash, the **challenge**. When it exchanges the code, it sends the verifier itself, and Keycloak checks that it matches the challenge. Someone who intercepts the code doesn't have the verifier, which is the attack RFC 7636 describes: "OAuth 2.0 public clients utilizing the Authorization Code Grant are susceptible to the authorization code interception attack."

You can do the whole flow by hand. Make the verifier and challenge:

```bash
verifier=$(openssl rand -base64 48 | tr '+/' '-_' | tr -d '=\n')
challenge=$(printf '%s' "$verifier" | openssl dgst -sha256 -binary | openssl base64 | tr '+/' '-_' | tr -d '=\n')
echo "http://localhost:8180/realms/taskboard/protocol/openid-connect/auth?client_id=taskboard-web&response_type=code&scope=openid&redirect_uri=http%3A%2F%2Flocalhost%3A4200%2F&code_challenge=$challenge&code_challenge_method=S256"
```

Open the printed URL in a browser and sign in as `ada` with `ada-local-only`. Keycloak redirects to `http://localhost:4200/?session_state=…&iss=…&code=…`. Nothing runs on port 4200, so the page fails to load, but the code is in the address bar. Exchange it within 60 seconds, the realm's default code lifetime:

```bash
curl -s http://localhost:8180/realms/taskboard/protocol/openid-connect/token \
  -d grant_type=authorization_code -d client_id=taskboard-web \
  -d redirect_uri=http://localhost:4200/ -d code="<the code>" -d code_verifier="$verifier"
```

The answer is JSON with `"token_type":"Bearer"`, `"expires_in":300`, and three tokens:

- The **access token** is for the API. It's the one that goes in the `Authorization` header.
- The **ID token** tells the app who signed in. It's for the app, not for APIs.
- The **refresh token** gets new tokens when the access token expires, after five minutes here.

Without `code_verifier`, Keycloak refused the exchange with `{"error":"invalid_grant","error_description":"PKCE code verifier not specified"}`.

### A shortcut for curl

Signing in through a browser for every `curl` command gets old quickly. The `taskboard-cli` client allows the **password grant**, where `curl` sends the username and password straight to Keycloak:

```bash
curl -s http://localhost:8180/realms/taskboard/protocol/openid-connect/token \
  -d grant_type=password -d client_id=taskboard-cli -d username=ada -d password=ada-local-only
```

This exists only to make the examples short. RFC 9700, the current OAuth security best practice, says "The resource owner password credentials grant [RFC6749] MUST NOT be used", and Keycloak's documentation says the same. The `reports` client allows it too, only so the opening can be reproduced with `curl`. A real app uses the code flow.

## What a JWT signature proves

The access token is a **JWT**, a JSON Web Token: three base64url-encoded parts separated by dots. **Base64url** is a way to write bytes using only letters, digits, `-`, and `_`, so they're safe in a header or URL. It isn't encryption: anyone can decode it. The first two parts of Ada's token decode to a header:

```json
{ "alg": "RS256", "typ": "JWT", "kid": "yh8QzCVFfirxVeQOvF_Qzh3SVtouvr5C9-GcCYRfQzU" }
```

and a payload, whose fields are called **claims**:

```json
{
  "exp": 1792515500,
  "iat": 1792515200,
  "iss": "http://localhost:8180/realms/taskboard",
  "aud": "taskboard-api",
  "sub": "c7bdbf5d-de4d-4a66-8f9c-436e0b38e6eb",
  "azp": "taskboard-cli",
  "realm_access": { "roles": ["editor"] },
  "preferred_username": "ada",
  "…": "…"
}
```

- `iss`, the **issuer**, is who made the token: the realm's address.
- `aud`, the **audience**, is who the token is for.
- `exp` and `iat` are when it expires and when it was issued, in seconds since 1970.
- `sub` is the user's ID in Keycloak, and `azp` is the client that asked for the token.

The third part is the **signature**. Keycloak signs the first two parts with its realm's private key, a key only Keycloak has. Anyone can check the signature with the matching public key, which Keycloak publishes. A valid signature proves two things: the realm's key made it, and nothing in the header or payload changed since.

So decoding a token proves nothing, since anyone can write a payload and encode it. Only checking the signature does. You can see both with `openssl`, using a key of your own:

```bash
b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out key.pem
openssl pkey -in key.pem -pubout -out pub.pem

header=$(printf '%s' '{"alg":"RS256","typ":"JWT"}' | b64url)
payload=$(printf '%s' '{"sub":"ada","aud":"taskboard-api","exp":1792512000}' | b64url)
signature=$(printf '%s.%s' "$header" "$payload" | openssl dgst -sha256 -sign key.pem | b64url)
```

`$header.$payload.$signature` is a complete token, 450 characters long. Checking the signature against the same two parts with the public key prints `Verified OK`. Checking it against a payload where `"sub":"ada"` was changed to `"sub":"grace"` prints `Verification failure`. A Keycloak token checks the same way: with the public key from `http://localhost:8180/realms/taskboard`, `Verified OK`; with the key above, `Verification failure`.

JwtBearer, the ASP.NET Core handler set up in the next section, checks signatures the same way, and it refused every forged version of Ada's token:

| Forged token | Answer |
|---|---|
| Header changed to `"alg": "none"`, signature removed | `401`, "The signature is invalid" |
| Payload edited: role `admin` added, user changed to `grace` | `401`, "The signature is invalid" |
| Re-signed with another key, keeping Keycloak's `kid` | `401`, "The signature is invalid" |
| `HS256`, using the realm's public key as a shared secret | `401`, "The signature is invalid" |
| Re-signed with another key and a new `kid` | `401`, "The signature key was not found" |
| Another key, with that key embedded in the header | `401`, "The signature key was not found" |

But look at what the signature doesn't say. It doesn't say the token is meant for this API: the Reports app's token in the opening was signed by the same realm key. It doesn't say the token is still current, or which realm should have issued it. Those answers are in the claims, and the API has to check them.

## The smallest working check

ASP.NET Core's JwtBearer handler reads the `Authorization` header and checks the token. Add the package:

```bash
dotnet add TaskBoard package Microsoft.AspNetCore.Authentication.JwtBearer --version 10.0.13
```

and register it in `Program.cs`:

```csharp
builder.Services.AddAuthentication().AddJwtBearer(options =>
{
    options.Authority = builder.Configuration["Auth:Authority"];
    options.Audience = builder.Configuration["Auth:Audience"];
    options.RequireHttpsMetadata = builder.Configuration.GetValue("Auth:RequireHttpsMetadata", true);
});
builder.Services.AddAuthorization();
```

with the values in `appsettings.json`:

```json
"Auth": {
  "Authority": "http://localhost:8180/realms/taskboard",
  "Audience": "taskboard-api"
}
```

Then require a signed-in user for every task endpoint, on the route group:

```csharp
var tasks = app.MapGroup("/tasks").WithTags("Tasks").RequireAuthorization();
```

What to notice:

- `Authority` is the realm's address. On the first request, JwtBearer downloads `/.well-known/openid-configuration` from it, a small JSON document that gives the issuer's exact name and the address of the realm's public keys, and then the keys themselves. It caches both.
- `Audience` is the name the token's `aud` must contain.
- With minimal APIs, ASP.NET Core adds the authentication and authorization middleware itself, so there's no `UseAuthentication()` call.

`RequireHttpsMetadata` is `true` by default, which means the Authority must use HTTPS. Keycloak here runs on plain HTTP, and with the default, every request answered `500` with an empty body, `/openapi/v1.json` included. The log said: `InvalidOperationException: The MetadataAddress or Authority must use HTTPS unless disabled for development by setting RequireHttpsMetadata=false.` The setting stays at its default in `appsettings.json`, and the local run turns it off with an environment variable:

```bash
Auth__RequireHttpsMetadata=false dotnet run --project TaskBoard
```

That keeps a deployed API from ever fetching keys over HTTP by mistake.

One more line belongs in `appsettings.json`. JwtBearer logs why it refused a token at `Information`, under `Microsoft.AspNetCore.Authentication`, and the template's `"Microsoft.AspNetCore": "Warning"` hides those lines:

```json
"Logging": {
  "LogLevel": {
    "Default": "Information",
    "Microsoft.AspNetCore": "Warning",
    "Microsoft.AspNetCore.Authentication": "Information"
  }
}
```

The first requests:

```text
no Authorization header     401   WWW-Authenticate: Bearer
Ada's taskboard-cli token   200
"Bearer not-a-jwt"          401   WWW-Authenticate: Bearer error="invalid_token"
the Reports app's token     401   WWW-Authenticate: Bearer error="invalid_token", error_description="The audience 'empty' is invalid"
```

What to notice:

- A `401` must come with a `WWW-Authenticate` header that says which kind of credentials the API wants. With no token at all, it says only `Bearer`; RFC 6750 says that when a request "lacks any authentication information", the server "SHOULD NOT include an error code or other error information".
- With a bad token, it adds `error="invalid_token"` and, when it can, a description. The bodies are empty.
- The log line for the Reports token reads `IDX10206: Unable to validate audience. The 'audiences' parameter is empty.`

That's the opening's request, refused. The next section goes through each check that JwtBearer made.

## Each check and what it catches

### Signature and algorithm

The signature check is on by default and caught every forgery in the table above. One more forgery got through, though. A token with the header `"alg": "PS256"`, signed with the issuer's real key using a different RSA signing scheme than Keycloak uses, was accepted with `200`. It wasn't forged by an outsider here, but it shows that the API accepted an algorithm the issuer never uses. RFC 8725, the JWT best practices, says: "Libraries MUST enable the caller to specify a supported set of algorithms and MUST NOT use any other algorithms when performing cryptographic operations." One line does that:

```csharp
options.TokenValidationParameters.ValidAlgorithms = [SecurityAlgorithms.RsaSha256];
```

After it, the `PS256` token got `401`, "The signature is invalid".

### Issuer

The issuer check compares the token's `iss` with the issuer named in the realm's discovery document. A token from a second realm on the same Keycloak, `other`, even one with `aud: taskboard-api`, got `401`, "The issuer 'http://localhost:8180/realms/other' is invalid". Each realm has its own keys, so that token's signature didn't match either; when several checks fail, the description names the claim.

### Audience

The audience check is the one the opening turned off. It compares the token's `aud` with `Audience`. RFC 9700 explains why it matters: "every resource server is obliged to verify, for every request, whether the access token sent with that request was meant to be used for that particular resource server. If it was not, the resource server MUST refuse to serve the respective request."

Without the check, two kinds of token that aren't meant for the API worked:

| Token | `aud` | Audience checked | Audience not checked |
|---|---|---|---|
| The Reports app's access token | none | `401`, "The audience 'empty' is invalid" | `200` |
| Ada's ID token from `taskboard-cli` | `taskboard-cli` | `401`, "The audience '(null)' is invalid" | `200` |

The second message is misleading: the ID token's `aud` is `taskboard-cli`, not empty. Since Microsoft.IdentityModel 8.8, the message leaves out the audiences unless an app context switch, `Switch.Microsoft.IdentityModel.DoNotScrubExceptions`, is turned on.

So why did the first real token fail? Because Keycloak doesn't put the API in `aud` on its own; it can't know which API a client's tokens are for. Two settings in the realm file fix that:

- An **audience mapper** on each client that calls the API adds `taskboard-api` to `aud` in that client's access tokens. `taskboard-web` and `taskboard-cli` have one; `reports` doesn't, so its tokens stay refused.
- `"fullScopeAllowed": false`, with a scope mapping for `editor`, puts only the roles that client needs into its tokens. Ada's `taskboard-cli` token carries `realm_access: {"roles": ["editor"]}` and nothing else, and the Reports token carries no roles at all.

### Lifetime

The lifetime check compares `exp`, and `nbf` ("not before") if present, with the API's clock. A token with no `exp` got `401`, "The token has no expiration", and one with `nbf` ten minutes ahead got `401`, "The token is not valid before …".

The check allows five minutes of **clock skew**, because the API's clock and Keycloak's may differ a little; RFC 7519 says "Implementers MAY provide for some small leeway, usually no more than a few minutes, to account for clock skew." So a token lives a little longer than its `exp` says. A token with a 10-second lifetime, sent every five seconds, kept answering `200` until 297 seconds after its `exp`; the next request, at 302 seconds, got `401`, "The token expired at …". `TokenValidationParameters.ClockSkew` changes the allowance; five minutes is fine when both clocks are kept in sync.

### Key rotation

Keycloak can change its signing key, which is called **rotation**. The realm publishes all its current public keys, and each token's header names the one that signed it in `kid`. JwtBearer caches the keys it downloaded. When a token names a `kid` it doesn't have, it downloads the keys again:

```text
new key added in Keycloak; token signed with it
19:50:43.263   401   "The signature key was not found"
19:50:43.592   200
19:50:43.949   200
```

The first request failed, and the download it started let the next one through. But JwtBearer downloads again at most once every five minutes. When a token with an unknown `kid` arrived one second before a real rotation, new tokens were refused for just over five minutes: checked every 10 seconds, they got `401` until 301 seconds after that token and `200` at 311 seconds. Keycloak can publish a key as **passive**, which puts it in the published keys without signing anything with it; publishing the new key that way ahead of time means APIs already have it when it starts signing. In the other direction, JwtBearer keeps trusting a key Keycloak has removed until its next scheduled download, which is every 12 hours by default.

### The checklist

The checks above, together:

| Check | What it catches | In ASP.NET Core | In Keycloak |
|---|---|---|---|
| Signature | edited and forged tokens | on | the realm's keys, published automatically |
| Algorithm | a token signed in a way the issuer never uses | `ValidAlgorithms = [RS256]` | RS256 by default |
| Issuer | tokens from another realm or another server | from `Authority` | fixed with `--hostname` |
| Audience | tokens meant for another app, ID tokens | `Audience` | an audience mapper on each calling client |
| Expiry and not-before | old tokens, tokens from the future | on, with 5 minutes of clock skew | 5-minute access tokens by default |
| Signing keys | tokens signed by a key the realm no longer uses | downloaded from the realm; refreshed on an unknown `kid` at most every 5 minutes, otherwise every 12 hours | publish new keys as passive first |
| Token type | an ID token or another JWT used as an access token | off by default | sends `typ: JWT` unless the client attribute `access.token.header.type.rfc9068` is `true`, which makes it `at+jwt` |

The last row is the one this setup doesn't check, because the audience check already refuses ID tokens. RFC 9068 asks APIs to check that `typ` is `at+jwt`, and Keycloak sends `JWT` unless that client attribute is set; with it, `TokenValidationParameters.ValidTypes = ["at+jwt"]` adds the check.

You can hold any token-checking code against this table, whether it's JwtBearer, another library, or code written by hand.

## Roles from realm_access

The API now knows who's calling. To let only editors create tasks, it also has to see Ada's role. A small endpoint shows what ASP.NET Core built from the token:

```csharp
public record CurrentUser(string? Name, bool IsEditor, ClaimSummary[] Claims);

public record ClaimSummary(string Type, string Value);

public static class GetMe
{
    public static void Map(IEndpointRouteBuilder app) => app.MapGet("/me", Handle).RequireAuthorization();

    public static Ok<CurrentUser> Handle(ClaimsPrincipal user) =>
        TypedResults.Ok(new CurrentUser(user.Identity!.Name, user.IsInRole("editor"), [.. user.Claims.Select(c => new ClaimSummary(c.Type, c.Value))]));
}
```

With the setup so far, Ada's token gives `"name": null` and `"isEditor": false`, and the claims include:

```text
http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier = c7bdbf5d-de4d-4a66-8f9c-436e0b38e6eb
realm_access = {"roles":["editor"]}
name = Ada Example
preferred_username = ada
```

What to notice:

- JwtBearer renamed some claims to .NET's long `ClaimTypes` names, such as `sub` to `…/nameidentifier`.
- `User.Identity.Name` reads a claim type that this token doesn't have, so it's `null` even though the token has `name` and `preferred_username`.
- `realm_access` arrived as one claim whose value is a JSON string. `IsInRole` looks for separate role claims, so it finds nothing.

Three settings and one event fix that:

```csharp
options.MapInboundClaims = false;
options.TokenValidationParameters.NameClaimType = "preferred_username";
options.TokenValidationParameters.RoleClaimType = "roles";
options.Events = new JwtBearerEvents { OnTokenValidated = KeycloakRoles.AddRealmRoles };
```

`MapInboundClaims = false` keeps the token's own claim names. The event runs once for each token that passed every check and adds one `roles` claim per realm role:

```csharp
public record RealmAccess(string[] Roles);

public static class KeycloakRoles
{
    public static Task AddRealmRoles(TokenValidatedContext context)
    {
        var identity = (ClaimsIdentity)context.Principal!.Identity!;
        var realmAccess = identity.FindFirst("realm_access");
        if (realmAccess is null)
        {
            return Task.CompletedTask;
        }

        var access = JsonSerializer.Deserialize<RealmAccess>(realmAccess.Value, JsonSerializerOptions.Web)!;
        foreach (var role in access.Roles)
        {
            identity.AddClaim(new Claim(identity.RoleClaimType, role));
        }

        return Task.CompletedTask;
    }
}
```

Now `/me` gives `{"name":"ada","isEditor":true}` for Ada and `{"name":"grace","isEditor":false}` for Grace, whose token has no `realm_access` at all. Keycloak can also write the roles as a flat `roles` claim through a protocol mapper, which removes the event but puts the mapping in Keycloak's configuration instead. Other identity providers put roles elsewhere, Entra ID in a `roles` claim and Auth0 in a custom claim, but the checks above don't change.

A **policy** names a rule that endpoints can require:

```csharp
builder.Services.AddAuthorizationBuilder()
    .AddPolicy("editor", policy => policy.RequireRole("editor"));

public static void Map(RouteGroupBuilder tasks) => tasks.MapPost("/", Handle).RequireAuthorization("editor");
```

```text
Ada    POST /tasks     201
Grace  POST /tasks     403   (empty body, no WWW-Authenticate)
Grace  GET /tasks/1    200
nobody POST /tasks     401   WWW-Authenticate: Bearer
```

What to notice:

- `401` means "I don't know who you are": the token is missing or failed a check. `403` means "I know who you are, and you may not do this". The log for Grace's request says `AuthenticationScheme: Bearer was forbidden.`
- Neither response has a body. Clients have to go by the status code and, for `401`, the `WWW-Authenticate` header.
- The generated OpenAPI document doesn't mention any of this on its own: it has no security scheme, and `POST /tasks` lists only `201`. A document transformer like the one in [the OpenAPI article](/dump/blog/openapi-spec-that-matches-the-code/#one-transformer-for-responses-that-follow-from-metadata) can add them.

## Testing protected endpoints

The task board's tests call handlers directly, so they don't go through authentication and kept passing. Tests that send HTTP requests to the app do go through it, and they can't depend on a running Keycloak. Instead, they make their own signing key and give it to JwtBearer in place of the realm's discovery document, so every check except the download still runs:

```csharp
public static class TestTokens
{
    public const string Issuer = "https://keycloak.test/realms/taskboard";
    public static readonly RsaSecurityKey Key = new(RSA.Create(2048)) { KeyId = "test-key" };

    public static string For(string username, string[] roles, string audience = "taskboard-api")
    {
        var claims = new Dictionary<string, object>
        {
            ["sub"] = Guid.NewGuid().ToString(),
            ["preferred_username"] = username,
        };
        if (roles.Length > 0)
        {
            claims["realm_access"] = new Dictionary<string, object> { ["roles"] = roles };
        }

        return new JsonWebTokenHandler().CreateToken(new SecurityTokenDescriptor
        {
            Issuer = Issuer,
            Audience = audience,
            Claims = claims,
            Expires = DateTime.UtcNow.AddMinutes(5),
            SigningCredentials = new SigningCredentials(Key, SecurityAlgorithms.RsaSha256),
        });
    }
}
```

```csharp
public class TaskBoardApp : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseSetting("ConnectionStrings:TaskBoard", TestDatabase.ConnectionString);
        builder.ConfigureTestServices(services =>
            services.Configure<JwtBearerOptions>(JwtBearerDefaults.AuthenticationScheme, options =>
            {
                var configuration = new OpenIdConnectConfiguration { Issuer = TestTokens.Issuer };
                configuration.SigningKeys.Add(TestTokens.Key);
                options.Configuration = configuration;
            }));
    }
}
```

What to notice:

- `WebApplicationFactory`, from the `Microsoft.AspNetCore.Mvc.Testing` package, runs the whole app in memory, and `CreateClient()` returns an `HttpClient` that talks to it.
- Setting `options.Configuration` replaces what JwtBearer would download from the Authority, so the test key and issuer stand in for Keycloak's. `Audience`, the algorithm, the lifetime, and the role mapping are the app's own.
- Because the checks still run, a test can catch a mistake in them. One of the four new tests sends a token for another audience and expects `401`.

The four tests send no token, a token for `reports`, Ada's token to `POST /tasks`, and Grace's. With the six existing ones, all ten passed with Keycloak stopped.

## Back to the Reports token

So why wasn't Keycloak's signature enough? Because a signature proves who made a token and that it wasn't changed, not who it was made for. The Reports app's token was a real Keycloak token, signed by the right key, for the right user. It just wasn't meant for the task board, and the one check that says so, the audience, was off.

Turning it off was a reaction to Keycloak's default, which leaves the API out of `aud`. The fix belongs in Keycloak: an audience mapper on each client that calls the API. With that and `Audience` set, the Reports token gets `401`, "The audience 'empty' is invalid", and Ada's tasks stay as they are.

## Check your understanding

1. **A colleague decodes a token's payload, sees `"preferred_username": "ada"`, and trusts it. What's missing?** The signature check. Decoding is base64url, which anyone can produce; only a valid signature from the realm's key shows that Keycloak made the token and nothing in it changed.
2. **A token's signature is valid and it hasn't expired. Why can the API still refuse it?** It may be meant for another app (`aud`), come from another realm (`iss`), or use an algorithm the API doesn't accept. A valid signature covers none of those.
3. **Why did Keycloak's tokens fail the audience check at first, and where does the fix belong?** Keycloak doesn't add an API to `aud` unless a client is configured to. The fix is an audience mapper on each client that calls the API, not turning the check off.
4. **Grace gets `403` on `POST /tasks` and Ada gets `201`. What did the API know about each, and why isn't Grace's answer `401`?** Both tokens passed every check, so the API knew who each was. Only Ada's carried the `editor` role that the policy requires. `401` would mean the API didn't know who was calling.

## Sources and further reading

- RFC 7519, [JSON Web Token](https://www.rfc-editor.org/rfc/rfc7519); RFC 7515, [JSON Web Signature](https://www.rfc-editor.org/rfc/rfc7515); RFC 8725, [JWT Best Current Practices](https://www.rfc-editor.org/rfc/rfc8725); RFC 9068, [JWT Profile for OAuth 2.0 Access Tokens](https://www.rfc-editor.org/rfc/rfc9068).
- RFC 6750, [Bearer Token Usage](https://www.rfc-editor.org/rfc/rfc6750); RFC 7636, [PKCE](https://www.rfc-editor.org/rfc/rfc7636); RFC 9700, [OAuth 2.0 Security Best Current Practice](https://www.rfc-editor.org/rfc/rfc9700); RFC 10017, [OAuth 2.0 for Browser-Based Applications](https://www.rfc-editor.org/rfc/rfc10017).
- [OpenID Connect Core 1.0](https://openid.net/specs/openid-connect-core-1_0.html).
- Microsoft, [Configure JWT bearer authentication](https://learn.microsoft.com/en-us/aspnet/core/security/authentication/configure-jwt-bearer-authentication) and [Mapping, customizing, and transforming claims](https://learn.microsoft.com/en-us/aspnet/core/security/authentication/claims).
- Keycloak, [Server Administration Guide](https://www.keycloak.org/docs/latest/server_admin/index.html), [Configuring the hostname](https://www.keycloak.org/server/hostname), and [Importing and exporting realms](https://www.keycloak.org/server/importExport).
- Microsoft.IdentityModel, [App context switches](https://github.com/AzureAD/azure-activedirectory-identitymodel-extensions-for-dotnet/wiki/App-Context-Switches-in-IdentityModel).
