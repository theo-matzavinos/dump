---
title: "Caching is permission to reuse, not proof that nothing changed"
description: "Understand browser caching, ETag revalidation, and static-asset cache busting, then follow how HTML and new asset URLs let clients discover a deployment."
pubDate: "2026-10-07"
tags:
  - http
  - caching
  - browser
  - frontend
---

You deploy a new JavaScript file, but a browser still runs the old one. Another request returns `304 Not Modified`, yet JavaScript receives a usable response with status `200`. Adding `?v=124` to an asset URL changes what gets requested—but does not clear anyone's cache.

These behaviors make more sense when we separate three decisions: **which stored response matches, whether it may be reused, and how a client discovers a different version**.

This article follows ordinary browser requests for HTML, JavaScript, CSS, images, and fonts. The same HTTP mechanisms can apply to API responses. You need to recognize a URL and an HTTP request and response; the [HTTP article](/dump/blog/http-from-tcp-to-fetch/) introduces those. A response's **headers** describe it and its handling rules; its **body** contains the HTML, file bytes, JSON, or other content.

## Contents

1. [What is stored, and which cache answers?](#what-is-stored-and-which-cache-answers)
2. [Freshness tells a cache when reuse is allowed](#freshness-tells-a-cache-when-reuse-is-allowed)
3. [ETags: validate content at the same URL](#etags-validate-content-at-the-same-url)
4. [Cache static assets without hiding updates](#cache-static-assets-without-hiding-updates)
5. [HTML lets a browser discover the new asset URLs](#html-lets-a-browser-discover-the-new-asset-urls)
6. [HTTP stale-while-revalidate: serve now, validate in the background](#http-stale-while-revalidate-serve-now-validate-in-the-background)
7. [Follow the requests in DevTools](#follow-the-requests-in-devtools)
8. [Check your understanding](#check-your-understanding)

## What is stored, and which cache answers?

When a browser downloads `/assets/tasks.js`, it can retain the response's content and metadata. On a later request, it checks whether that stored answer matches and whether reuse is allowed. If both checks pass, it can avoid downloading the file again. That mechanism is an **HTTP cache**.

There can be more than one owner:

```text
Browser HTTP cache → shared HTTP cache, if present → origin server
one browser context   e.g. a CDN cache               source of the response
```

A **CDN**, or content delivery network, can serve content from servers nearer to clients. Its shared caches can reuse responses across clients. A browser's HTTP cache is private to that browser context. A response can be reused at either boundary; a browser-cache hit need not send any request, while reaching a CDN still involves communication.

### The URL is part of the lookup key

A **cache key** identifies which stored answer a request can use. HTTP caches use at least the request method and target URL; the following are different request URLs:

```text
/assets/tasks.js
/assets/tasks.js?v=123
/assets/tasks.js?v=124
/assets/tasks.a1b2.js
```

The query string is part of the URL. The browser does not give `v` a special meaning—it simply sees different URLs. A fragment such as `#v=124` is not sent in the HTTP request, so it does not create a different HTTP request URL.

Some responses also vary by request headers. If `/labels.json` returns different languages, `Vary: Accept-Language` tells an HTTP cache to consider that header when selecting a stored response. A cache key is therefore not always just a filename.

Application-held objects are a separate owner. If JavaScript parses a response and keeps an array, HTTP headers do not automatically expire that array or update the visible interface. Likewise, scripts can explicitly manage request/response pairs with the **Cache API**, often used by service workers; that storage does not automatically honor HTTP caching headers. Neither mechanism is the browser's ordinary HTTP cache.

## Freshness tells a cache when reuse is allowed

Suppose the server sends:

```http
Cache-Control: max-age=60
```

This permits a 60-second freshness lifetime. While the stored response is **fresh**, normal HTTP rules can allow reuse without validation. Fresh means “the policy permits reuse,” not “the origin definitely still has these bytes.” The origin could change after 20 seconds without notifying the browser.

**Stale** means the freshness lifetime has ended. It does not mean deleted or necessarily incorrect: validation may confirm that the stored content is still suitable.

The lifetime is compared with the response's **age**, not universally a new timer starting at each download. HTTP caches account for `Date`, any upstream `Age`, transfer time, and time resident in the cache. In a simplified example with synchronized clocks and negligible transfer delay:

```text
12:00:00  Origin generates a response with max-age=60.
12:00:20  A shared cache sends it with Age: 20.
          About 40 seconds of freshness remain—not another 60.
12:01:00  Age reaches 60. Normal fresh reuse is no longer allowed.
```

Expiration is a policy boundary. **Eviction** is removal from storage: a browser may discard an entry to reclaim space even before it expires. A long freshness lifetime does not guarantee that the response will remain stored.

### Response directives answer different questions

These directives are sent in the HTTP **response**. Their combined constraints matter:

| Directive    | What it permits or requires                                                                                             |
| ------------ | ----------------------------------------------------------------------------------------------------------------------- |
| `max-age=60` | A 60-second freshness lifetime, compared with response age                                                              |
| `no-cache`   | Storage is allowed, but validation is required before normal HTTP reuse                                                 |
| `no-store`   | Do not store this response in an HTTP cache; it does not purge older stored copies                                      |
| `private`    | A shared HTTP cache must not store this response; a private browser cache may                                           |
| `public`     | Explicit permission for shared caching where applicable, subject to other rules                                         |
| `immutable`  | During its freshness lifetime, the representation is not expected to change, so unnecessary revalidation can be avoided |

A **representation** is the particular content selected for a resource—for example, the English rather than Greek response at the same URL. `immutable` does not mean “retain forever” or extend `max-age`.

Omitting `Cache-Control` does not reliably prevent caching: eligible responses can receive an estimated, or **heuristic**, freshness lifetime. Use deliberate policies.

For personalized HTML or task data, `private, no-cache` is one possible policy: no shared storage, and validation before normal reuse. When the response must not be stored, use `no-store`. Cookies alone do not prevent shared caching, and `private` is **not authorization**; the server must still enforce who may read the resource. These directives also do not delete copies already held by application code.

## ETags: validate content at the same URL

An **ETag**, or entity tag, is a version marker supplied by the server in a response header. It describes the selected representation at that URL. It can be a content hash or another suitable version identifier; its format is chosen by the server.

The point is to ask: **“I already have this version. Is it still suitable, or do I need the new content?”**

### Where does an ETag apply?

| Response             | What the tag identifies                                                            | Why validation can help                                                     |
| -------------------- | ---------------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| `/index.html`        | The selected HTML document, including its asset references                         | Discover changed HTML without downloading the whole document when unchanged |
| `/assets/tasks.js`   | The selected script content at that URL                                            | Avoid retransferring an unchanged script when validation is needed          |
| `/tasks?filter=open` | That selected API response—for example, the open-task list for the authorized user | Check that response without retransferring unchanged JSON                   |

The tag is not a version number for “the entire application” or every database record. It belongs to the selected response. Authentication and variant selection still matter before the server decides which representation is being validated.

### When does the browser use it?

An ETag does **not** set the freshness lifetime or require a request on every visit:

- A matching fresh response can normally be reused without contacting the server.
- A stale response may be validated before reuse.
- A response with `no-cache` requires validation before normal reuse, even when recently stored.
- A request can explicitly require validation too.

`Cache-Control` determines the reuse policy; the ETag supplies a way to validate the retained version when that policy or request requires it.

### Browser `fetch()` uses ETags for API responses too

The browser's HTTP cache also sits underneath requests made by JavaScript. A JSON API response can use the same storage and validation rules as an HTML document or script.

Suppose the page and API share an **origin**: the same scheme (`http` or `https`), hostname, and port. This illustrative request asks the API for open tasks; the article does not supply that endpoint. `fetch()` requests a response, `await` waits for the pending result before continuing these lines, and `.json()` reads the response body and parses its JSON into JavaScript values:

```js
const response = await fetch("/tasks?filter=open");
const tasks = await response.json();

console.log(response.status, tasks);
```

On the first request, assume the API returns this shortened response:

```http
HTTP/1.1 200 OK
Content-Type: application/json
Cache-Control: private, no-cache
ETag: "open-v7"

[{"id":1,"title":"Review release","done":false}]
```

The browser may retain the HTTP response and its tag. `private` forbids shared-cache storage; `no-cache` requires validation before normal reuse. Neither directive performs authentication—the API must still enforce access to the selected task list.

When JavaScript requests the same list again, with matching request variants and the response still stored, the browser can add the condition automatically:

```http
GET /tasks?filter=open HTTP/1.1
Host: example.test
If-None-Match: "open-v7"
```

There are two outcomes:

- **Unchanged list:** the server returns a bodyless `304`. The browser uses its retained JSON body, so application code receives `response.status === 200` and `.json()` parses that body normally. It does not need a special `304` parsing branch.
- **Changed list:** the server returns `200` with the current JSON and a new tag, such as `"open-v8"`. The browser stores the replacement response, and `.json()` parses the new body.

**Application code normally does not need to store the ETag or set `If-None-Match` itself.** The server supplies and checks validators; the browser manages its HTTP-cache copy and conditional request. Without a retained response, the browser must obtain the body again.

The validation on every normal reuse above comes from response `no-cache`, not from calling `fetch()` or having an ETag. With a suitable `max-age=60` policy instead, a matching fresh response could answer a normal `fetch()` without communication. Requesting `{ cache: "no-cache" }` explicitly asks for validation even while fresh; the [request-mode example below](#ask-for-validation-not-automatic-non-storage) shows that separate control.

This reuses an **HTTP response**, not the parsed `tasks` array. Each `.json()` call parses the supplied body into values for that call. It does not update an earlier array or an already-rendered list. Cross-origin access rules are another boundary; this example stays on one origin and does not manually read or send validator headers.

### Follow one document through both outcomes

The following are annotated HTTP/1.1 exchanges. Unrelated headers are omitted, and each HTML body is shortened to the relevant script reference.

First, the browser requests `/index.html`. The server returns a document, permits storage but requires validation, and supplies a tag:

```http
HTTP/1.1 200 OK
Content-Type: text/html
Cache-Control: no-cache
ETag: "html-v7"

<script type="module" src="/assets/tasks.a1b2.js"></script>
```

The browser retains both the body and the tag. Later, instead of blindly downloading the body again, it sends a **conditional request**—a request whose outcome depends on a condition:

```http
GET /index.html HTTP/1.1
Host: example.test
If-None-Match: "html-v7"
```

**Unchanged document:** the current tag still matches. The server responds:

```http
HTTP/1.1 304 Not Modified
Cache-Control: no-cache
ETag: "html-v7"
```

The `304` has no replacement body. The HTTP cache updates the applicable stored metadata and uses the body it already has. Browser `fetch()` can expose a usable response with status `200` and that stored body even though the **network exchange** was `304`.

**Changed document:** the current document now names a different script, and its tag is different. The same conditional request receives new content instead:

```http
HTTP/1.1 200 OK
Content-Type: text/html
Cache-Control: no-cache
ETag: "html-v8"

<script type="module" src="/assets/tasks.c3d4.js"></script>
```

Now the browser replaces the stored document and tag. The new HTML tells it to request the new script URL.

Validation saves body transfer when content is unchanged. It **still requires a request and response** with the server or an applicable intermediary, and does not necessarily eliminate server-side work.

`Last-Modified` is another validator, based on a modification timestamp; the corresponding request header is `If-Modified-Since`. For this validation, `If-None-Match` takes precedence when both conditions are present.

## Cache static assets without hiding updates

**Static assets** include the JavaScript, CSS, images, and fonts an interface loads. They may change between releases even though no per-user response generation is needed to serve them.

### The problem with overwriting one long-lived URL

Imagine `/assets/tasks.js` was served with a year of freshness. You replace its server-side contents tomorrow but leave the URL unchanged. A browser holding a fresh response can continue using yesterday's script without contacting the server. A different ETag at the origin cannot help a client that does not yet ask for validation.

Disabling caching from the start would avoid that reuse but also lose its benefit on every visit. A better arrangement for suitable public assets is:

1. Give each published content version a distinct URL.
2. Keep the contents at each versioned URL fixed.
3. Allow long-lived reuse of those fixed contents.
4. Update the documents or stylesheets that reference them when the version changes.

This is **cache busting**: change the lookup URL when content changes, rather than demand a fresh download of the same URL on every request. It does not delete old cache entries.

### Three ways to change the asset URL

| Technique                                  | Earlier URL → new URL                                                     | Benefit and responsibility                                                                                                                                                                             |
| ------------------------------------------ | ------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Content-hashed filename                    | `tasks.a1b2.js` → `tasks.c3d4.js`                                         | The name is derived from file contents. A content change produces a new name; unchanged contents can keep their URL. The build must update references.                                                 |
| Release version in a filename or directory | `tasks.v123.js` → `tasks.v124.js`, or `/v123/tasks.js` → `/v124/tasks.js` | Easy to understand, but the version must be advanced and references updated. Versioning a whole release can change URLs for unchanged files too.                                                       |
| Version or hash in a query parameter       | `tasks.js?v=123` → `tasks.js?v=124`                                       | Changes the browser's request URL while keeping the base filename. The server must serve the intended contents at each advertised URL, and shared-cache keys must retain the relevant query parameter. |

A query parameter does not magically select old contents from disk. If a server ignores `v` and always serves its current `tasks.js`, an older document requesting `?v=123` after a deployment might receive the new bytes. Merely decorating the URL is not enough to promise immutable contents at every advertised version. Versioned files or directories make retaining multiple versions more straightforward.

If a shared cache is configured to ignore the version parameter, changing it does not change that cache's key either. Check the policy at each cache boundary.

**Avoid two misleading alternatives:**

- `tasks.js#v=124` does not change the HTTP request URL; fragments stay in the browser.
- A fresh random value or timestamp on **every request** makes each lookup different and defeats useful reuse. A timestamp generated once per release can be a version marker; the problem is changing it when the contents have not changed.

### Pair fixed URLs with a deliberate response policy

For genuinely fixed, publicly shareable asset contents, a common response policy is:

```http
Cache-Control: public, max-age=31536000, immutable
```

That grants a year of freshness and says the representation is not expected to change while fresh. It is a server/CDN **response-header policy**, not something established by naming a file or adding a JavaScript option. A filename that looks hashed does not make its bytes immutable.

`public` is not required for every cacheable response; it explicitly permits shared caching where applicable. Do not apply a public-asset policy indiscriminately to personalized content. Browser eviction and explicit request overrides still exist.

ETags and cache busting are complementary, not interchangeable:

- **ETag:** validate retained content at the same URL when validation is needed.
- **Cache busting:** request a different URL because a different content version is needed.

A content hash could be used in both a filename and an ETag, but it has different jobs in those two places.

## HTML lets a browser discover the new asset URLs

The browser does not scan the server for new filenames after a deployment. It follows references in HTML, CSS, and other loaded resources.

Suppose only the JavaScript changed:

```text
Earlier HTML → tasks.a1b2.js + tasks.e5f6.css
New HTML     → tasks.c3d4.js + tasks.e5f6.css
```

The new script URL selects new contents. The unchanged stylesheet can retain its URL and benefit from an existing fresh entry. A changed font or background image needs a new URL too; the stylesheet must reference that URL, and a content-hashed stylesheet changes name when its own contents change.

### Give stable HTML a discovery policy

For a non-personalized document at a stable URL such as `/index.html`, one useful policy is:

```http
Cache-Control: no-cache
ETag: "html-v8"
```

The browser may store the HTML, but normal reuse must validate it. If unchanged, the document can be reused after a `304`. If changed, the browser receives the new HTML and discovers its new asset references. This is why the ETag example used HTML rather than treating all resources as year-long immutable files.

Personalized HTML needs a suitable additional constraint, such as `private`, or a non-storage policy when appropriate. These are illustrative policies, not claims about this site's deployed headers.

### A deployment must support both discovery and older references

A client can still have an earlier document or an open page that loads another asset later. Keep earlier versioned assets available while clients may reference them, including versions needed for rollback. Publish the referenced new assets before making new HTML available, so discovering the new URLs does not lead to missing files.

A CDN purge removes entries at that CDN boundary. It cannot delete every browser's response or replace code already executing in an open page. Likewise, a new deployment does not force every client to reload. Long-lived asset caching works with an HTML discovery policy and stable versioned contents—not with an expectation that users will hard-refresh after each release.

## HTTP stale-while-revalidate: serve now, validate in the background

Sometimes a short period of older content is acceptable. A supporting HTTP cache can return a usable stale response now while attempting to validate or refresh it in the background. This is **stale-while-revalidate**, often shortened to SWR:

```http
Cache-Control: max-age=60, stale-while-revalidate=300
```

The policy describes two windows measured against response age:

```text
Age below 60 seconds       → fresh reuse
Next 300 seconds           → stale reuse may accompany background revalidation
After that stale window    → normal blocking path, unless another rule permits reuse
```

The cache may serve stale content during the additional window; it is not a guarantee that every cache supports the directive or that all requests take the same path. Requests trigger the background work—if no request does so during the window, a later request outside it cannot rely on this permission alone.

A refreshed response is available for subsequent requests. It does **not** replace the JavaScript or HTML already executing in an open page, or push newly parsed API data into UI state. Showing an API result and later accepting another result is an application workflow, separate from this HTTP policy.

Use the stale window only where temporarily older content is acceptable. It is not a universal policy for permissions, prices, or other data where acting on an old value may cause harm.

## Follow the requests in DevTools

Use the Network panel to inspect the requested URL, request and response headers, status, transfer size, and cache indicators. Cache labels differ between browsers. Equal bodies or a small transfer size alone do not prove that no communication occurred.

### Repeat a normal asset request

With browser caching enabled, choose an actual same-origin asset URL. **Same-origin** means the same scheme (`http` or `https`), hostname, and port as the open page. In the browser console, replace the illustrative URL below with that asset's URL.

`fetch()` asks the browser for a response, `await` waits for the pending result before continuing these lines, and `.text()` reads the response body as text. The calls are sequential so the first response has been consumed before the repeat:

```js
const assetURL = "/assets/tasks.a1b2.js";
const first = await fetch(assetURL);
const firstBody = await first.text();

const repeat = await fetch(assetURL);
const repeatBody = await repeat.text();

console.log(first.status, repeat.status, firstBody === repeatBody);
```

If the server permits fresh reuse and the response remains stored, the repeat can use the browser's HTTP cache. Inspect Network evidence—and server logs when available—to distinguish that from two downloads with identical contents. Request variants must remain the same too.

### Ask for validation, not automatic non-storage

Using the same `assetURL`, this request mode requires validation of a matching stored response, even if fresh:

```js
const validated = await fetch(assetURL, { cache: "no-cache" });
console.log(validated.status);
```

With a stored validator and unchanged content, the wire exchange can be `304` while the logged application-visible status is `200`. If content changed, expect a new response and body. The response's `Cache-Control` and the Fetch request's `cache` option have different owners:

| Fetch request mode | Browser HTTP-cache behavior for that read                                             |
| ------------------ | ------------------------------------------------------------------------------------- |
| `default`          | Apply normal matching, freshness, and validation rules                                |
| `no-cache`         | Validate a matching stored response before reuse                                      |
| `reload`           | Bypass the stored response for this read, then allow the download to update the cache |
| `no-store`         | Bypass the stored response and do not update the cache with the download              |

These modes do not delete application-held objects or purge a CDN.

### Walk through the cases separately

1. **Cold read:** start with an empty cache in a fresh browser context. Record the body download, freshness policy, and any validator.
2. **Fresh repeat:** repeat the same request normally. Check whether the browser reused it without an origin request.
3. **Unchanged validation:** trigger validation. Inspect `If-None-Match`, the wire `304`, and the usable application response.
4. **Changed validation:** change the origin's selected content and its tag, then validate again. Look for `200`, the new body, and the new tag.
5. **Deployment:** inspect the actual HTML and asset references. Check that new references load the intended new contents and older referenced assets remain available.
6. **Cache busting:** compare changed filename/path/query URLs. Verify which cache key changed and which contents the server supplied.

DevTools **Disable cache** changes the browser HTTP-cache path while that control applies; it does not turn off CDN storage or application-held data. Keep it off for fresh-reuse observations. Reloads and hard reloads can impose request rules different from ordinary reuse, so inspect the headers rather than assuming a warm reload demonstrates a fresh hit.

History navigation is another path: a browser's back/forward cache may restore an earlier page snapshot. It is not simply another HTTP response lookup, and `no-cache` alone is not a promise that pressing Back will revalidate the document.

## Check your understanding

1. **Can a fresh response be older than the origin's current content?** Yes. Freshness permits reuse under a policy; it is not notification that nothing changed.
2. **Does `no-cache` mean “do not store”?** No. It requires validation before normal reuse. `no-store` prohibits storing that response; it does not purge older copies.
3. **What does an ETag identify?** The selected representation at a resource URL, not the whole application or a frontend array.
4. **Why can validation return `304`?** The retained version still matches. The cache uses its stored body, avoiding another body download but not the request and response.
5. **Why doesn't a new ETag immediately fix an old fresh script?** The client may not contact the server until validation is needed. It cannot compare a tag it has not received.
6. **What does cache busting change?** The request URL and therefore its lookup key. It does not clear old entries or disable caching.
7. **Are `?v=124` and `#v=124` equivalent?** No. The query reaches the HTTP request; the fragment does not.
8. **Why retain old asset versions?** Earlier documents and open sessions can still reference them. New HTML and old HTML may coexist across clients.
9. **Does HTTP SWR update an already-rendered interface?** Not by itself. It refreshes cached responses; the application must separately obtain and accept updated data.
10. **What should be checked first when a client seems stuck?** Which document and URLs it actually used, which cache answered, and what reuse or validation policy applied—not just whether new files exist at the origin.

## References

- [MDN: HTTP caching](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Caching): cache owners, freshness, revalidation, cache busting, and HTML versus subresources.
- [MDN: Cache-Control](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Cache-Control): response directives and their distinct purposes.
- [MDN: ETag](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/ETag) and [If-None-Match](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/If-None-Match): version markers and conditional validation.
- [MDN: Request.cache](https://developer.mozilla.org/en-US/docs/Web/API/Request/cache): browser request modes.
- [MDN: Vary](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Vary) and [Cache API](https://developer.mozilla.org/en-US/docs/Web/API/Cache): response variants and separately managed script storage.
- [RFC 9111](https://www.rfc-editor.org/rfc/rfc9111.html): HTTP storage, freshness, age, and validation rules.
- [RFC 9110 §15.4.5](https://www.rfc-editor.org/rfc/rfc9110.html#section-15.4.5): the bodyless `304` response.
- [RFC 5861 §3](https://www.rfc-editor.org/rfc/rfc5861.html#section-3): bounded HTTP stale-while-revalidate.
- [RFC 8246 §2](https://www.rfc-editor.org/rfc/rfc8246.html#section-2): immutable responses during their freshness lifetime.
