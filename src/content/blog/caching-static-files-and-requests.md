---
title: "Why users still see the old version after you deploy"
description: "Learn how browser caching decides when a saved copy can be reused, how ETags check it, and how hashed file names and always-checked HTML get a deployment in front of users."
pubDate: "2026-10-07T11:00:00Z"
updatedDate: "2026-10-15"
tags:
  - http
  - caching
  - browser
audience:
  - frontend
  - backend
---

You deploy a fix. A teammate opens the app and still gets the bug. They press Ctrl+Shift+R, and the bug is gone.

What happened is that their browser kept a copy of the old JavaScript file, and the server had told it that reusing that copy was fine. This article explains who decides how long a saved copy can be reused, how the browser checks whether its copy is still current, and how a deployment gets new files in front of users without anyone having to force a reload.

You'll need to recognize a URL, an HTTP request, and an HTTP response; the [HTTP article](/dump/blog/http-from-tcp-to-fetch/) introduces them. A response has **headers**, which describe it and how it may be handled, and a **body**, which holds the HTML, JavaScript, JSON, or other content. The hands-on section at the end uses a small Node.js server and the DevTools in a Chromium-based browser such as Chrome or Edge.

## Contents

1. [Where the old copy comes from](#where-the-old-copy-comes-from)
2. [How long a saved copy stays fresh](#how-long-a-saved-copy-stays-fresh)
3. [Checking a stale copy with an ETag](#checking-a-stale-copy-with-an-etag)
4. [fetch() calls get the same treatment](#fetch-calls-get-the-same-treatment)
5. [The Cache-Control directives you'll use](#the-cache-control-directives-youll-use)
6. [Ship changed files under new URLs](#ship-changed-files-under-new-urls)
7. [How new HTML points the browser to new files](#how-new-html-points-the-browser-to-new-files)
8. [Deploy without breaking open tabs](#deploy-without-breaking-open-tabs)
9. [Serve a stale copy while checking in the background](#serve-a-stale-copy-while-checking-in-the-background)
10. [Watch the caching happen in DevTools](#watch-the-caching-happen-in-devtools)
11. [Other caches to know about](#other-caches-to-know-about)
12. [Debugging "I still see the old version"](#debugging-i-still-see-the-old-version)

## Where the old copy comes from

When your browser downloads `/assets/tasks.js`, it can save the response, both the headers and the body, on your machine. The next time a page asks for the same URL, the browser checks whether it has a saved response for it and whether the server allowed reusing it. If both are true, it uses the saved copy instead of downloading the file again. That storage is the browser's **HTTP cache**.

A response can be saved in more than one place:

```text
Browser HTTP cache  →  CDN cache, if there is one  →  your server
used only by you       shared by many users            where the response comes from
```

A **CDN**, or content delivery network, is a set of servers placed close to users. It can keep its own copy of a response and hand it to everyone who asks. Each browser profile has its own HTTP cache (a private window gets a separate, temporary one). When someone says "the cache", it's worth asking which of these they mean.

A browser cache hit can skip the network entirely. A CDN cache hit still means a request and a response over the network, just a shorter trip than going all the way to your server.

## How long a saved copy stays fresh

Your server decides how long a saved copy may be reused with the `Cache-Control` response header. Suppose it sends `/assets/tasks.js` with:

```http
Cache-Control: max-age=60
```

That means "you can reuse this for 60 seconds without asking me." While a saved copy is within that time, it's **fresh**. After that, it's **stale**: it's still saved, but the browser has to check with the server before using it again.

Here's what that looks like when you deploy in the middle of it:

```text
12:00:00  The browser downloads tasks.js with max-age=60.
12:00:20  You deploy a new tasks.js. Nobody tells the browser.
12:00:30  The page asks for tasks.js again. The copy is 30 seconds old,
          so it's still fresh: the browser reuses the old file
          without sending any request.
12:01:00  The copy turns 60 seconds old and becomes stale.
12:01:05  The page asks again. Now the browser checks with the server
          and finds out about the new file.
```

So "fresh" only means the server allowed reuse for that long. It doesn't mean the file on the server is unchanged. That's the teammate's situation from the opening: their copy was still fresh, so their browser never asked.

The 60 seconds count from when your server created the response, not from when the browser received it. If a CDN held the response for 20 seconds before passing it on, it sends an `Age: 20` header, and the browser has only 40 seconds of freshness left.

A browser can also delete saved copies early to free up space. A long freshness time allows reuse but doesn't guarantee the copy stays saved.

## Checking a stale copy with an ETag

Re-downloading a whole file just to find out it hasn't changed would be wasteful. So servers can label each response with a version marker, and the browser uses that marker to ask "do I still have the current version?"

That marker is an **ETag**, short for entity tag. It's a response header whose value the server chooses: a version name, a fingerprint of the file's bytes, or anything else that changes whenever the content at that URL changes.

### Follow one HTML document through both outcomes

These are HTTP/1.1 exchanges with unrelated headers left out. Each HTML body is shortened to the one line that matters: the script it loads.

First, the browser requests `/index.html`. The server sends the document, allows the browser to save it, requires a check before every reuse (that's what `no-cache` means, more on it below), and attaches an ETag:

```http
HTTP/1.1 200 OK
Content-Type: text/html
Cache-Control: no-cache
ETag: "html-v7"

<script type="module" src="/assets/tasks.a1b2.js"></script>
```

The browser saves the body and the tag. The next time it needs `/index.html`, it sends a **conditional request**: a request that asks for the body only if a condition holds. `If-None-Match` means "send me the content only if its ETag no longer matches this one":

```http
GET /index.html HTTP/1.1
Host: example.test
If-None-Match: "html-v7"
```

**If the document hasn't changed,** the tag still matches, and the server answers with no body:

```http
HTTP/1.1 304 Not Modified
Cache-Control: no-cache
ETag: "html-v7"
```

`304 Not Modified` tells the browser to use the body it already saved. The browser updates the saved headers and shows the saved document.

**If the document has changed,** for example because a deployment switched it to a new script, the server has a different tag. The same conditional request now gets the full new document:

```http
HTTP/1.1 200 OK
Content-Type: text/html
Cache-Control: no-cache
ETag: "html-v8"

<script type="module" src="/assets/tasks.c3d4.js"></script>
```

The browser replaces its saved document and tag. The new HTML names a different script, so the browser requests that new script next. That's how a deployment reaches a browser, and the rest of the article builds on it.

A check still costs a request and a response. It saves downloading the body when nothing changed, not the round trip itself.

An older validator works the same way with dates: the server sends `Last-Modified`, and the browser asks with `If-Modified-Since`. When a request contains both `If-None-Match` and `If-Modified-Since`, the server goes by `If-None-Match`.

## fetch() calls get the same treatment

The browser's HTTP cache also sits underneath requests your JavaScript makes with `fetch()`. A JSON API response follows the same freshness and ETag rules as the HTML above.

Take a request for open tasks. A relative URL such as `/tasks?filter=open` goes to the page's own **origin**: the same scheme (`http` or `https`), hostname, and port as the page.

```js
const response = await fetch("/tasks?filter=open");
const tasks = await response.json();
```

You don't write any ETag code. If the API's response has an ETag and needs checking, the browser saves the tag, sends `If-None-Match` itself, and when the server answers `304`, hands your code the saved body. Your code sees `response.status` as `200`, and `response.json()` parses the saved body as usual.

Each `response.json()` call creates a new array. The HTTP cache saves responses, not the arrays your code built from them, so a newer response never updates an array or a list that's already on screen.

You can also tell a single `fetch()` call how to use the HTTP cache with its `cache` option:

| `cache` option | What the browser does for that request                                  |
| -------------- | ----------------------------------------------------------------------- |
| `default`      | Follows the normal freshness and ETag rules                             |
| `no-cache`     | Checks with the server before using a saved copy, even a fresh one      |
| `reload`       | Ignores any saved copy and downloads again, then saves the new response |
| `no-store`     | Ignores any saved copy and doesn't save the new response either         |

For example, `fetch("/tasks?filter=open", { cache: "no-cache" })` sends a conditional request whenever the browser has a saved copy with an ETag.

## The Cache-Control directives you'll use

Now that you've seen freshness and checking, here are the `Cache-Control` values a server sends most often. A response can combine several, separated by commas.

| Directive    | What it tells caches                                                                                                   |
| ------------ | ---------------------------------------------------------------------------------------------------------------------- |
| `max-age=60` | The response stays fresh for 60 seconds after the server created it                                                   |
| `no-cache`   | Caches may save it, but must check with the server before every reuse                                                  |
| `no-store`   | Caches must not save it at all                                                                                         |
| `private`    | Only the user's own browser may save it, not a shared cache such as a CDN                                              |
| `public`     | Shared caches may save it, even in cases they normally wouldn't, such as requests that carry an `Authorization` header |
| `immutable`  | The content at this URL won't change while it's fresh, so the browser doesn't need to check it                         |

The name `no-cache` misleads a lot of people: it allows saving and requires a check. `no-store` is the one that forbids saving. Neither one deletes copies saved earlier under a different policy.

If a response has no `Cache-Control` header at all, browsers may still reuse it for a while, using a guessed lifetime based on its `Last-Modified` date. This is called **heuristic freshness**, and it's a common source of surprise reuse, so set `Cache-Control` on every response.

For HTML or data that's specific to the logged-in user, a good default is `private, no-cache`. The browser may keep a copy, a CDN won't, and the browser checks with the server before each reuse. When the response must not be saved anywhere, use `no-store`. These headers only control caching: your server still has to check who's allowed to see the data.

## Ship changed files under new URLs

**Static assets** are the JavaScript, CSS, images, and fonts the app loads. They only change when you deploy, so you'd like browsers to keep them for a long time. But a long freshness time causes exactly the opening bug.

### Why a long-lived file with a fixed name goes wrong

Say `/assets/tasks.js` is served with a year of freshness. Tomorrow you deploy a new version under the same URL. A browser that already has a fresh copy keeps using yesterday's script without contacting your server. A new ETag on the server can't help, because the browser isn't asking.

Turning caching off would fix that, but every visit would then download everything again.

### Give each version of a file its own URL

The browser looks up saved responses by URL (and request method). So these are four separate entries, as far as the cache is concerned:

```text
/assets/tasks.js
/assets/tasks.js?v=123
/assets/tasks.js?v=124
/assets/tasks.a1b2.js
```

That gives you a better arrangement for files that only change on deployment:

1. Give each version of a file its own URL.
2. Never change the content at a URL once it's published.
3. Let browsers and CDNs keep those files for a long time.
4. When a file changes, update the HTML or CSS that references it to use the new URL.

This is **cache busting**: when content changes, the browser requests a different URL instead of re-checking the same one. It doesn't delete the old saved copy. The old copy just stops being requested.

The usual way to make those URLs is a **content hash**. A hash is a short fingerprint computed from a file's bytes. Change one character in the file and the fingerprint changes; leave the file alone and it stays the same. Put the fingerprint in the file name, and the name changes exactly when the content does.

Angular's build already does this. In a project created by `ng new`, the production configuration sets the build option `outputHashing` to `"all"`, so `ng build` writes files with names such as `main-<hash>.js`, `chunk-<hash>.js`, and `styles-<hash>.css` into `dist/`. The generated `index.html` keeps its plain name and references the hashed files.

Other ways to put a version in the URL work too, with different tradeoffs:

| Technique                       | Old URL → new URL                                                         | What to watch for                                                                                                                         |
| ------------------------------- | ------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| Content hash in the file name   | `tasks.a1b2.js` → `tasks.c3d4.js`                                         | The build has to update every reference. Unchanged files keep their names, so browsers keep their copies.                                 |
| Release number in a name or folder | `tasks.v123.js` → `tasks.v124.js`, or `/v123/tasks.js` → `/v124/tasks.js` | Easy to read, but every file gets a new URL each release, even unchanged ones.                                                         |
| Version in a query parameter    | `tasks.js?v=123` → `tasks.js?v=124`                                       | The server usually ignores `v` and serves whatever `tasks.js` is current, so old pages asking for `?v=123` get the new file. Some CDNs are also configured to ignore query strings. |

Two approaches look like cache busting but don't work:

- **`tasks.js#v=124`:** the part after `#` is a fragment. The browser never sends it to the server, so the request URL doesn't change.
- **A random value or timestamp on every request:** each request gets a new URL, so nothing is ever reused. A value that changes once per release is fine. One that changes on every request turns caching off.

### Send a long-lived policy with those files

For files whose URL changes whenever their content does, servers commonly send:

```http
Cache-Control: public, max-age=31536000, immutable
```

That's a year of freshness (31,536,000 seconds), permission for CDNs to share the file, and a promise that the content at this URL won't change. Your server or CDN has to send this header. A hashed file name alone doesn't set it, so check the actual response headers of your hosting.

Don't use this policy for personalized content, and remember that browsers can still delete saved copies early or bypass them on a forced reload.

ETags and cache busting solve different problems, so they work together:

- An **ETag** checks whether the saved copy at the **same URL** is still current.
- **Cache busting** sends the browser to a **different URL** when the content changes.

## How new HTML points the browser to new files

After a deployment, the browser doesn't look around the server for new file names. It finds them by reading the HTML (and CSS) it loads. Suppose only the JavaScript changed:

```text
Old HTML → tasks.a1b2.js + tasks.e5f6.css
New HTML → tasks.c3d4.js + tasks.e5f6.css
```

The new script URL brings the new code. The stylesheet kept its URL, so the browser keeps using its saved copy. If a font or image changes, it gets a new URL too, the stylesheet that references it changes, and so the stylesheet's own hashed name changes as well.

That means the HTML is the one file that has to be checked every time. For an `index.html` at a fixed URL that's the same for every user, send:

```http
Cache-Control: no-cache
ETag: "html-v8"
```

The browser may save the HTML but checks it before every use. If nothing changed, it gets a quick `304`. If you deployed, it gets the new HTML and, through it, the new file names. If the HTML is personalized, add `private`.

So the pattern for a deployed frontend is: HTML with `no-cache`, and hashed assets with a long `max-age` and `immutable`.

## Deploy without breaking open tabs

A deployment changes the files on the server. It doesn't reload any tabs users already have open, and those tabs keep running the old code. Angular apps load each lazy-loaded route from its own chunk file, only when the user first navigates to it. Here's what happens if a deployment deletes the old files:

```text
09:00  A user opens the app. The browser loads index.html, which loads
       main-OLD.js. main-OLD.js knows that the task details route
       lives in chunk-OLD.js, but doesn't load it yet.
10:00  You deploy. The server now has index.html, main-NEW.js, and
       chunk-NEW.js. The old files are deleted.
10:05  The user, still in the same tab, opens a task's details.
       main-OLD.js requests chunk-OLD.js.
       The server answers 404 Not Found.
       The route fails to load.
```

In Chromium the console shows `TypeError: Failed to fetch dynamically imported module:` followed by the chunk's URL. Apps built with webpack, including Angular projects that still use the older webpack-based `browser` builder, report the same failure as a `ChunkLoadError`.

To avoid it:

- **Keep old asset files available for a while after each deploy**, including the files you'd need for a rollback. Because every version has its own file names, old and new files can sit side by side.
- **Upload the new assets before the new HTML goes live.** Otherwise a browser could get new HTML that points to files that aren't there yet.
- **Expect old tabs to exist.** Some apps catch this loading error and reload the page, which makes the tab fetch the new `index.html`.

A CDN purge removes saved copies from that CDN only. It can't delete copies in users' browsers or change code that's already running in an open tab.

## Serve a stale copy while checking in the background

Sometimes a slightly old response is acceptable if it means no waiting. The `stale-while-revalidate` directive allows that:

```http
Cache-Control: max-age=60, stale-while-revalidate=300
```

This sets up two time windows, counted from when the server created the response:

```text
Age 0 to 60 seconds      → fresh: reuse without asking
Age 60 to 360 seconds    → stale, but reuse it right away and
                            check with the server in the background
After 360 seconds        → check with the server first, then respond
```

During the second window, a request gets the saved copy immediately, and the cache starts checking with the server in the background. The background check only happens when a request arrives during that window. Once the check succeeds, later requests get the refreshed copy. Until then, more requests can still get the stale copy, and if the check fails, nothing gets refreshed. Not every cache supports the directive; Chromium's HTTP cache does.

The refreshed copy doesn't change anything already on screen, and doesn't replace code running in an open tab. If your app shows API data and later wants newer data, it has to request it again.

Use this only where showing slightly old content is harmless. Permissions, prices, and similar data usually need a fresh answer.

## Watch the caching happen in DevTools

This small Node.js server sends the two policies from this article: `no-cache` for the page and a year of `immutable` freshness for anything in `assets/`. It computes each file's ETag from a hash of its bytes and prints every request it receives, so you can see when the browser didn't ask at all.

Create a folder with three files: `server.mjs`, `index.html`, and `assets/tasks-v1.js`. The part of `server.mjs` that matters for caching is how it answers a request for a file it found:

```js
const hash = createHash("sha256").update(body).digest("base64url");
const etag = `"${hash.slice(0, 16)}"`;
const headers = { "Cache-Control": policy.cacheControl, ETag: etag };

if (ifNoneMatch === etag) {
  response.writeHead(304, headers).end();
  return;
}

response.writeHead(200, { ...headers, "Content-Type": policy.type }).end(body);
```

What to notice:

- `policy.cacheControl` is `no-cache` for the page at `/` and `public, max-age=31536000, immutable` for files in `assets/`.
- The ETag is the first 16 characters of a hash of the file's bytes, wrapped in double quotes. Change the file and the ETag changes.
- When the request's `If-None-Match` header matches the current ETag, the server sends `304` with the caching headers and no body. Otherwise it sends `200` with the body. Real servers also handle lists of tags and weak tags, which this demo skips.

The rest of the file reads the request, picks a policy for the URL, reads the file, and logs each request.

<details>
<summary>The complete <code>server.mjs</code></summary>

```js
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { createServer } from "node:http";

function policyFor(pathname) {
  if (pathname === "/") {
    return { file: "index.html", type: "text/html; charset=utf-8", cacheControl: "no-cache" };
  }

  if (/^\/assets\/[\w-]+\.js$/.test(pathname)) {
    return {
      file: `.${pathname}`,
      type: "text/javascript",
      cacheControl: "public, max-age=31536000, immutable",
    };
  }

  return null;
}

const server = createServer(async (request, response) => {
  const { pathname } = new URL(request.url, "http://localhost");
  const ifNoneMatch = request.headers["if-none-match"] ?? "";
  console.log(request.method, pathname, ifNoneMatch);

  const policy = policyFor(pathname);
  if (policy === null) {
    response.writeHead(404).end();
    return;
  }

  let body;
  try {
    body = await readFile(policy.file);
  } catch {
    response.writeHead(404).end();
    return;
  }

  const hash = createHash("sha256").update(body).digest("base64url");
  const etag = `"${hash.slice(0, 16)}"`;
  const headers = { "Cache-Control": policy.cacheControl, ETag: etag };

  if (ifNoneMatch === etag) {
    response.writeHead(304, headers).end();
    return;
  }

  response.writeHead(200, { ...headers, "Content-Type": policy.type }).end(body);
});

server.listen(8080, "127.0.0.1", () => {
  console.log("Open http://localhost:8080/");
});
```

</details>

`index.html`:

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="color-scheme" content="dark light" />
    <title>Cache demo</title>
    <script type="module" src="/assets/tasks-v1.js"></script>
  </head>
  <body>
    <h1>Tasks</h1>
    <p id="version"></p>
  </body>
</html>
```

`assets/tasks-v1.js`:

```js
document.querySelector("#version").textContent = "Script version 1";
```

The `-v1` in the file name stands in for the content hash a real build would add.

Run `node server.mjs` in that folder. The steps below assume the browser starts with nothing saved for this site. Tabs in the same browser profile share one HTTP cache, so a new tab isn't enough. Instead, close every private window, then open a new one (Ctrl+Shift+N in Chrome and Edge, Cmd+Shift+N on macOS). Private windows share a separate HTTP cache that starts empty and is thrown away when the last private window closes. Do this once; from then on, leave caching on.

In the private window, open DevTools, select the **Network** panel, and make sure **Disable cache** at the top of the panel is **unchecked**; that checkbox turns off the browser's HTTP cache while DevTools is open. Now follow these steps and compare what DevTools shows with what the server prints in its terminal:

1. **First visit.** Go to `http://localhost:8080/` in that window. Both `/` and `/assets/tasks-v1.js` show status `200`, and the terminal prints a line for each. Click a row and open its **Headers** tab to see the `Cache-Control` and `ETag` response headers.
2. **Normal reload.** Press Ctrl+R (Cmd+R on macOS). The `/` row shows `304`, and its request headers include `If-None-Match`. The terminal prints `GET /` with the tag. The script row says it came from the browser's cache (the **Size** column shows a label such as `(memory cache)`), and the terminal prints nothing for it: the browser didn't ask.
3. **Ask for a check from JavaScript.** In the **Console** panel, run:

   ```js
   const response = await fetch("/", { cache: "no-cache" });
   response.status;
   ```

   The console shows `200`. The new row in the Network panel shows `304`. The browser received a bodyless `304` and handed your code the saved body as a normal `200`.

4. **Deploy.** Copy `assets/tasks-v1.js` to `assets/tasks-v2.js`, change its text to `"Script version 2"`, change the script URL in `index.html` to `/assets/tasks-v2.js`, and delete `assets/tasks-v1.js`. Reload normally. `/` now returns `200` with a new ETag, the browser requests `tasks-v2.js`, and the page shows "Script version 2".
5. **Request a missing chunk, like an old open tab would.** An old tab asking for a chunk file that a deployment deleted gets the same answer as a request for a file that never existed. In the console, run `await import("/assets/details-v1.js")`. The Network panel shows a `404`, and the console shows `TypeError: Failed to fetch dynamically imported module`. That's the broken lazy route from the deployment section. Importing `/assets/tasks-v1.js` instead would still work in this browser, even though you deleted it: the browser saved a fresh copy in step 1 and doesn't ask the server.
6. **Hard reload.** Press Ctrl+Shift+R (Cmd+Shift+R on macOS). Every request now shows `200` and none of them carries `If-None-Match`: a hard reload ignores the saved copies.

To run the steps again, put back the original `index.html` and `assets/tasks-v1.js`, close every private window, and start from a new one.

## Other caches to know about

The browser's HTTP cache isn't the only place an old version can come from:

- **A CDN** keeps its own copies, following its own configuration. If it's set to ignore query strings, changing `?v=` doesn't change what it serves. Responses served from a CDN cache often include an `Age` header.
- **Responses that vary by request header.** If `/labels.json` returns English or Greek depending on the `Accept-Language` request header, the server sends `Vary: Accept-Language`, and caches then keep a separate copy per language. So the URL isn't always the whole lookup key.
- **Service workers and the Cache API.** A service worker is a script that can answer the page's requests itself, often from storage managed with the Cache API. That storage doesn't follow `Cache-Control`, and the service worker answers before the HTTP cache is involved. In DevTools, the **Application** panel lists service workers, and the Network panel marks responses that came from one.
- **Data your app already holds.** Arrays, signals, or other state built from an earlier response stay as they are until your code fetches again.
- **The back-forward cache.** When the user presses Back, the browser may restore a snapshot of the whole earlier page instead of loading it again, so `Cache-Control` on the HTML doesn't come into play.

## Debugging "I still see the old version"

When someone reports old behavior after a deploy, work through these in order:

1. **Is the tab older than the deploy?** A deployment doesn't reload open tabs. Ask them to reload normally (not hard reload) and check again.
2. **Which HTML did the browser use?** In the Network panel, select the document request and check its status, its `ETag`, and, in the **Response** tab, which script and stylesheet file names it references. If those are the old names, the problem is the HTML, not the assets.
3. **Does the HTML get checked?** Its `Cache-Control` should be `no-cache` (or `private, no-cache`). A `max-age`, or no `Cache-Control` at all, lets the browser reuse old HTML without asking.
4. **Is a CDN serving old HTML?** Look for an `Age` header or a CDN cache-status header on the document response. If the CDN has the old copy, purge it or fix its caching rules for HTML.
5. **Do the asset URLs change when their content changes?** If a changed file kept its name and has a long `max-age`, browsers keep the old copy until it goes stale.
6. **Is a service worker answering?** Check the Application panel. If one is registered, it decides what the page gets, regardless of HTTP caching.
7. **Are requests failing with `404`?** Old tabs asking for deleted chunk files mean the deployment removed old assets too early.

## Check your understanding

1. **Does `Cache-Control: no-cache` stop the browser from saving a response?** No. The browser may save it but has to check with the server before every reuse. `no-store` is the one that forbids saving.
2. **You change `tasks.js` on the server, and its ETag changes. Why does a browser with a fresh copy keep running the old script?** While the copy is fresh, the browser doesn't contact the server at all, so it never sees the new ETag.
3. **Why does `index.html` get `no-cache` while hashed assets get a year of `immutable` freshness?** The HTML is how the browser discovers the current file names, so it has to be checked every time. A hashed asset's URL changes whenever its content changes, so a saved copy at that URL can never be out of date.
4. **Why keep old asset files after a deployment?** Open tabs still run the old code and can request old chunk files, for example when the user opens a lazy-loaded route. Deleting those files makes the route fail with a `404`.

## References

- [MDN: HTTP caching](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Caching): private and shared caches, freshness, validation, cache busting, and HTML versus assets.
- [MDN: Cache-Control](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Cache-Control): every directive and what it does.
- [MDN: ETag](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/ETag) and [If-None-Match](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/If-None-Match): version markers and conditional requests.
- [MDN: Request.cache](https://developer.mozilla.org/en-US/docs/Web/API/Request/cache): the `cache` option for `fetch()`.
- [MDN: Vary](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Vary) and [Cache API](https://developer.mozilla.org/en-US/docs/Web/API/Cache): responses that depend on request headers, and storage managed by scripts.
- [Angular CLI: `ng build`](https://angular.dev/cli/build): the `output-hashing` option.
- [RFC 9111](https://www.rfc-editor.org/rfc/rfc9111.html): HTTP caching rules for storage, freshness, age, and validation.
- [RFC 9110 §15.4.5](https://www.rfc-editor.org/rfc/rfc9110.html#section-15.4.5): the `304 Not Modified` response.
- [RFC 5861 §3](https://www.rfc-editor.org/rfc/rfc5861.html#section-3): `stale-while-revalidate`.
- [RFC 8246 §2](https://www.rfc-editor.org/rfc/rfc8246.html#section-2): `immutable`.
