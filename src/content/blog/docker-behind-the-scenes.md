---
title: "Docker behind the scenes: images, containers, and what they can see"
description: "Build a small greeting app with Angular, nginx, a Node API, and PostgreSQL, and watch why a deleted file still takes space, why a container stops on its own, and why localhost means something different inside a container."
pubDate: "2026-10-08T11:00:00Z"
updatedDate: "2026-10-15"
tags:
  - docker
  - tooling
  - fundamentals
audience:
  - frontend
  - backend
---

Three things confuse almost everyone the first time they use Docker. You delete a 4 MB file in a Dockerfile, and the image is still 4 MB bigger. You start a container, it prints a message, and then it's gone. And your app answers at `localhost` in the browser, but inside a container `localhost` points somewhere else entirely.

They look like three unrelated quirks, but they come from one design. Docker keeps the files a program needs, the running program, and the network and storage that program can see as separate things, and each one has its own lifetime. This article builds a small app and makes each of the three happen on your machine, so you can see the cause instead of memorizing a rule.

The app shows `Hello, World!` and lets you save a different name. Angular runs in the browser, nginx serves Angular's built files, a small Node API reads and saves the name, and PostgreSQL stores it. Each server runs in its own container.

## Contents

1. [Before you start](#before-you-start)
2. [Your first Dockerfile and what it records](#your-first-dockerfile-and-what-it-records)
3. [A container runs one main process](#a-container-runs-one-main-process)
4. [Set up the greeting app](#set-up-the-greeting-app)
5. [Choose what the build can see](#choose-what-the-build-can-see)
6. [Build the frontend in two stages](#build-the-frontend-in-two-stages)
7. [How the build cache decides what to rerun](#how-the-build-cache-decides-what-to-rerun)
8. [Run the three services with Compose](#run-the-three-services-with-compose)
9. [What localhost means inside a container](#what-localhost-means-inside-a-container)
10. [Where a container's writes go](#where-a-containers-writes-go)
11. [Build-time values and runtime values](#build-time-values-and-runtime-values)
12. [The three mysteries, explained](#the-three-mysteries-explained)
13. [Clean up](#clean-up)
14. [Sources and further reading](#sources-and-further-reading)

## Before you start

You'll need Docker with Compose running on this computer: Docker Desktop on Windows or macOS, left in its default Linux-containers mode, or Docker Engine with the Compose plugin on Linux or inside WSL. You'll also need network access to Docker Hub and npm, and a few GB of free disk space.

The `docker` command is only a client. It sends requests to the Docker **daemon**, the background service that builds images and runs containers, and the daemon looks up the folders you share with containers on its own machine. So a Docker setup that points at a remote server won't find the lab's files. Docker Desktop's daemon runs in a virtual machine on your computer, and Desktop shares your folders with it. Run `docker version` and `docker compose version` to check that both answer.

You don't need Node or Angular installed, because every build tool runs inside a container. Node runs JavaScript outside a browser, npm is Node's package manager, and the Angular CLI is the command-line tool that creates and builds Angular projects. The networking part assumes you know what a port and an origin are; [HTTP from TCP to fetch](/dump/blog/http-from-tcp-to-fetch/) explains both.

The lab uses `node:24.21.0-bookworm-slim`, `nginx:1.30.5-alpine`, `postgres:17.11-bookworm`, Angular CLI 22.2.1, and the `pg` 8.23.1 database client. Everything in it is a learning demo: the API has no authentication, the database password is a public demo value, and nothing is backed up. Don't deploy it.

### Pick your shell

Use PowerShell on Windows, and bash on Linux, macOS, or inside WSL (the Linux environment built into Windows). macOS opens zsh by default, so type `bash` first to start a bash session.

Most commands below work unchanged in both shells, so they appear once. Where the shells differ, for example in how a long command continues onto the next line, you'll see a bash block followed by a PowerShell block. Run commands one at a time in the same terminal window, and keep that window open until the end: it holds the lab's variables. If a command fails and the text didn't say it would, stop and read the error.

### Load the lab helpers

A small helper script sets up the lab and cleans up after it. Loading it creates a new lab directory with a random name under your temporary directory and moves your terminal into it. It checks that Docker answers, that port 8080 is free, and that nothing in Docker already uses the lab's name. Then it sets four variables the commands use: `$lab` (the random name), `$lab_dir`, `$lab_share`, and `$lab_user`. At the end, one command removes what the lab created after checking that each item really came from the lab.

Download [lab-helpers.sh](/dump/downloads/docker-lab/lab-helpers.sh) for bash or [lab-helpers.ps1](/dump/downloads/docker-lab/lab-helpers.ps1) for PowerShell, and read it before you run it. Then open a terminal in the folder you saved it in and load it. In bash, `source` runs the file inside your current session, so the variables it sets stay available:

```bash
source ./lab-helpers.sh
```

In PowerShell, the leading dot does the same job, which is called dot-sourcing. On many Windows desktop machines, PowerShell's execution policy blocks script files, and where it allows local scripts it can still block downloaded ones. So allow scripts for this window first:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
. .\lab-helpers.ps1
```

`-Scope Process` changes the setting for this PowerShell window only, needs no administrator rights, and disappears when you close the window. If your organization sets the policy through Group Policy, this command can't override it.

The helper prints the lab directory's path. Open that directory in your editor: blocks headed with a file path, such as `layers/Dockerfile`, are files to save there. If Docker later reports that this path isn't shared, add it in Docker Desktop's File sharing settings. If port 8080 is taken, the helper says so and tells you how to choose another port; use that port wherever this article says 8080.

## Your first Dockerfile and what it records

A server program needs more than its own source file. It needs a runtime such as Node, some libraries, maybe configuration files. Docker packages all of those files, plus a few settings such as which command to start, into an **image**. An image is something built and stored, like an archive of a small Linux system's files. It doesn't run anything by itself.

You describe how to build an image in a **Dockerfile**. Save this one:

File: `layers/Dockerfile`

```dockerfile
FROM node:24.21.0-bookworm-slim
RUN head -c 4M /dev/urandom > /large.bin
RUN rm /large.bin
CMD ["sh", "-c", "if [ -e /large.bin ]; then echo 'File is present'; else echo 'File is absent'; fi"]
```

Read it line by line:

1. `FROM` starts from an existing image, here the official Node image built on Debian Linux.
2. The first `RUN` executes a command during the build. It writes about 4 MB of random bytes to `/large.bin`.
3. The second `RUN` deletes that file.
4. `CMD` records the command a container should start later. Nothing runs it during the build.

Now build it. `--label` attaches a name-value note to the image, here `docker-lab=` followed by the lab's name, which the cleanup command checks before it removes anything. `-t` gives the image a name, and the last argument, `layers`, is the directory whose files the build may use:

```sh
docker build --label "docker-lab=$lab" -t "$lab-layers" layers
```

Each `RUN` records what it changed: "added `/large.bin`" for the first one, "deleted `/large.bin`" for the second. Each recorded change set is a **layer**, and an image is an ordered stack of layers plus a small settings file holding things like the `CMD`. To show a container its files, Docker applies the layers in order. A later layer can hide a file, but it can't reach back and edit an earlier layer. So the 4 MB stay inside the image, even though no container will ever see them.

`docker image history` lists the steps and how much each one added:

```sh
docker image history "$lab-layers"
```

Trimmed output, newest step first:

```text
CREATED BY                                      SIZE
CMD ["sh" "-c" "if [ -e /large.bin ]; then e…   0B
RUN /bin/sh -c rm /large.bin # buildkit         0B
RUN /bin/sh -c head -c 4M /dev/urandom > /la…   4.19MB
```

The delete step adds nothing, and the step that created the file still holds its 4.19 MB. `CMD` only changes a setting, so it adds no files either. That's the first mystery: deleting a file in a later step hides it but doesn't remove its bytes. Creating and deleting temporary files within the same `RUN` keeps them out of the image. And because earlier layers keep everything, never copy a password or key into an image and count on deleting it later; anyone with the image can read the earlier layer.

Where did `node:24.21.0-bookworm-slim` come from? Docker downloaded it from Docker Hub, a **registry**: a server that stores images so other machines can download them. In that name, `node` is the image's repository and `24.21.0-bookworm-slim` is its **tag**. A tag is a label the publisher can move to different content later, and `latest` is just another tag. To pin exact content, you can refer to an image by its **digest**, a `sha256:` fingerprint calculated from the content itself.

## A container runs one main process

A **container** is what Docker creates when you want to run an image. It combines the image's files with its own settings, such as environment variables, network connections, and storage, plus a private place for the files it writes. Starting the container starts one main **process**, a running program, which is the image's `CMD` unless you name a different command.

Run the image you just built. `--name` gives the container a name you can refer to later, and `--label` marks it as the lab's, just like the image:

```sh
docker run --name "$lab-exit" --label "docker-lab=$lab" "$lab-layers"
```

It prints `File is absent`, and the command returns. Now ask Docker about the container's state:

```sh
docker container inspect --format '{{.State.Status}} {{.State.ExitCode}}' "$lab-exit"
```

It prints `exited 0`. The container still exists, but it's stopped: its main process printed one line and finished, and a container runs only as long as its main process does. That's the second mystery. Exit code `0` means the command succeeded; it doesn't mean anything is still running.

So a container that should keep serving needs a main process that keeps running in the foreground, such as a web server waiting for requests. That's why the nginx image you'll build later runs nginx with `daemon off;`, which keeps nginx in the foreground instead of moving itself into the background and letting the main process end. Running `docker run --detach` returns your terminal to you right away, but it doesn't keep a short command alive.

These are the operations a container goes through:

| Operation | What it does                                                                         |
| --------- | ------------------------------------------------------------------------------------ |
| Create    | Makes a container from an image and settings, without starting its main process     |
| Start     | Starts that container's main process                                                 |
| Stop      | Asks the main process to end, and forces it to end if it doesn't within a time limit |
| Restart   | Stops and starts the same container, without rebuilding its image                    |
| Remove    | Deletes the container and its private files; the image stays                         |

A container isn't a virtual machine. Its processes run directly on the host's Linux **kernel**, the part of the operating system that manages processes, memory, files, and network access. Docker asks the kernel to give those processes their own view of files, network, and process IDs, and to limit the resources they use. macOS and Windows don't have a Linux kernel to share, so Docker Desktop runs a small Linux virtual machine there, and your containers run inside it.

## Set up the greeting app

Now for the real app. The Angular CLI generates the project's configuration, so run it inside a Node container instead of installing it:

In bash:

```bash
docker run --rm --user "$lab_user" --env HOME=/tmp --env NG_CLI_ANALYTICS=false \
  --mount "type=bind,src=$lab_dir,dst=/lab" --workdir /lab \
  node:24.21.0-bookworm-slim \
  npx --yes --package=@angular/cli@22.2.1 ng new web --directory web \
  --minimal --routing=false --ssr=false --style=css --skip-tests \
  --skip-git --skip-install --defaults --package-manager=npm --ai-config=none
```

In PowerShell:

```powershell
docker run --rm --user "$lab_user" --env HOME=/tmp --env NG_CLI_ANALYTICS=false `
  --mount "type=bind,src=$lab_dir,dst=/lab" --workdir /lab `
  node:24.21.0-bookworm-slim `
  npx --yes --package=@angular/cli@22.2.1 ng new web --directory web `
  --minimal --routing=false --ssr=false --style=css --skip-tests `
  --skip-git --skip-install --defaults --package-manager=npm --ai-config=none
```

The Docker options before the image name do the setup:

- `--mount "type=bind,src=$lab_dir,dst=/lab"` makes your lab directory appear at `/lab` inside the container, so the files the CLI writes there land in your lab directory. That's a **bind mount**; [Where a container's writes go](#where-a-containers-writes-go) covers mounts properly.
- `--workdir /lab` starts the command in that directory.
- `--user "$lab_user"` runs the command as your own user on Linux and macOS, so you own the files it creates. On Windows, the helper sets it to `0:0`, the root user these images run as anyway, because Docker Desktop handles file ownership there.
- `--env` sets environment variables for the command: npm gets a temporary home directory, and the CLI skips its usage-analytics question.
- `--rm` removes the container when the command finishes. The files it wrote through the mount stay.

Everything after the image name is the command to run. `ng new` creates a minimal Angular project in `web`: no tests, no routing, no server-side rendering, and no installed dependencies yet.

Next, replace the generated `web/src/main.ts` and add the nginx configuration and the API's files. You don't need to read the TypeScript and JavaScript closely; the note after them lists what matters for Docker.

File: `web/src/main.ts`

<details>
<summary>Show the Angular component</summary>

```typescript
import { Component, signal } from "@angular/core";
import { bootstrapApplication } from "@angular/platform-browser";

@Component({
  selector: "app-root",
  template: `
    <main>
      @if (name() !== "") {
        <h1>Hello, {{ name() }}!</h1>
      }
      <form (submit)="save($event, nameInput.value)">
        <label for="name">Name</label>
        <input #nameInput id="name" required maxlength="80" [value]="name()" />
        <button type="submit">Save</button>
      </form>
      <p role="status">{{ status() }}</p>
    </main>
  `,
})
class Greeting {
  readonly name = signal("");
  readonly status = signal("Loading the saved name…");

  constructor() {
    void this.load();
  }

  async load(): Promise<void> {
    const response = await fetch("/api/name");
    if (!response.ok) {
      this.status.set("Could not load the name.");
      return;
    }
    const name = await response.text();
    this.name.set(name);
    this.status.set("");
  }

  async save(event: Event, proposedName: string): Promise<void> {
    event.preventDefault();
    const response = await fetch("/api/name", { method: "PUT", body: proposedName });
    if (!response.ok) {
      this.status.set("Could not save the name.");
      return;
    }
    const name = await response.text();
    this.name.set(name);
    this.status.set("Name saved.");
  }
}

bootstrapApplication(Greeting).catch((error: unknown) => {
  console.error(error);
});
```

</details>

File: `web/nginx.conf`

```nginx
server {
    listen 80;
    root /usr/share/nginx/html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location /api/ {
        proxy_pass http://api:3000;
    }
}
```

File: `api/package.json`

```json
{
  "name": "api",
  "private": true,
  "type": "module",
  "dependencies": {
    "pg": "8.23.1"
  }
}
```

File: `api/server.mjs`

<details>
<summary>Show the Node API</summary>

```javascript
import { createServer } from "node:http";
import pg from "pg";

const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL });

await pool.query("CREATE TABLE IF NOT EXISTS greeting (id integer PRIMARY KEY, name text NOT NULL)");
await pool.query("INSERT INTO greeting (id, name) VALUES (1, 'World') ON CONFLICT (id) DO NOTHING");

async function handle(request, response) {
  if (request.method === "GET" && request.url === "/api/name") {
    const result = await pool.query("SELECT name FROM greeting WHERE id = 1");
    response.end(result.rows[0].name);
    return;
  }

  if (request.method === "PUT" && request.url === "/api/name") {
    const chunks = [];
    for await (const chunk of request) {
      chunks.push(chunk);
    }
    const name = Buffer.concat(chunks).toString("utf8").trim();
    if (name.length === 0 || name.length > 80) {
      response.statusCode = 400;
      response.end("Use a name of 1 to 80 characters.");
      return;
    }
    const result = await pool.query("UPDATE greeting SET name = $1 WHERE id = 1 RETURNING name", [name]);
    response.end(result.rows[0].name);
    return;
  }

  if (request.method === "GET" && request.url === "/api/message") {
    response.end(process.env.SERVICE_MESSAGE ?? "No message set");
    return;
  }

  if (request.method === "GET" && request.url === "/health") {
    await pool.query("SELECT 1");
    response.end("Ready");
    return;
  }

  response.statusCode = 404;
  response.end("Not found");
}

const server = createServer(async (request, response) => {
  response.setHeader("Content-Type", "text/plain; charset=utf-8");
  try {
    await handle(request, response);
  } catch (error) {
    console.error(error);
    response.statusCode = 503;
    response.end("Database unavailable");
  }
});

server.listen(3000, "0.0.0.0");

// `docker stop` sends SIGTERM. Node doesn't exit on it by default when it's
// the container's main process, so close the server and the pool here.
process.on("SIGTERM", () => {
  server.close(() => {
    void pool.end().then(() => process.exit(0));
  });
});
```

</details>

What matters for Docker in these files:

- The Angular code calls the relative URL `/api/name`. The browser sends that request to the same host and port that served the page, and nginx's `location /api/` block forwards it to `http://api:3000`, the API container.
- The API reads `DATABASE_URL` and `SERVICE_MESSAGE` from its environment, so Docker can set them when it creates the container.
- On startup, the API creates its table if it's missing and inserts `World` only if no row exists yet. It never overwrites a saved name.
- The API listens on `0.0.0.0` and handles the stop signal. Both come up again in the networking section.

Finally, generate a lockfile for each project. A **lockfile** (`package-lock.json`) records the exact version of every package, including the packages your packages depend on, so every later install gets the same set:

In bash:

```bash
docker run --rm --user "$lab_user" --env HOME=/tmp \
  --mount "type=bind,src=$lab_dir,dst=/lab" --workdir /lab \
  node:24.21.0-bookworm-slim \
  sh -c 'cd web && npm install --package-lock-only && cd ../api && npm install --package-lock-only'
```

In PowerShell:

```powershell
docker run --rm --user "$lab_user" --env HOME=/tmp `
  --mount "type=bind,src=$lab_dir,dst=/lab" --workdir /lab `
  node:24.21.0-bookworm-slim `
  sh -c 'cd web && npm install --package-lock-only && cd ../api && npm install --package-lock-only'
```

The single-quoted text after `sh -c` is one command string for the Linux shell inside the container, so its `&&` and `cd` belong to that shell, not to yours.

## Choose what the build can see

`docker build` doesn't get access to your whole disk. The last argument names one directory, and the files in it are the **build context**: the only files the Dockerfile's `COPY` instructions can copy into the image. In the first build, the context was `layers`. For the frontend it will be `web`, so the sibling `api` directory isn't part of that build at all.

A `.dockerignore` file in the context's top directory removes paths from the context before the build sees them. `node_modules` matters most: copied from your computer, those dependencies would be slow to send and could overwrite the Linux packages `npm ci` installs inside the build. Leaving `.env` files out keeps local secrets out of the image. Docker doesn't read `.gitignore` for this.

File: `web/.dockerignore`

```text
node_modules
dist
.angular
.env
.env.*
```

File: `api/.dockerignore`

```text
node_modules
.env
.env.*
```

Ignoring a file only keeps it out of the build. It stays in your lab directory.

## Build the frontend in two stages

nginx doesn't run TypeScript. Angular's build turns the source into plain JavaScript, HTML, and CSS files, and nginx sends those files to the browser, which runs the JavaScript. So building needs Node, npm, and Angular's compiler, but serving needs only nginx and the output files. A **multi-stage build** uses one stage for each job:

File: `web/Dockerfile`

```dockerfile
FROM node:24.21.0-bookworm-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build
ARG BUILD_LABEL=no-label
RUN echo "$BUILD_LABEL" > dist/web/browser/build-label.txt

FROM nginx:1.30.5-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist/web/browser/ /usr/share/nginx/html/
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

What to notice:

- The first `FROM` starts a stage named `build`. `WORKDIR /app` makes `/app` the current directory for the instructions after it.
- `COPY package.json package-lock.json ./` copies those two files from the build context into `/app`. In `COPY . .`, the first dot means "everything left in the context" and the second means "the current directory in the image".
- `npm ci` installs exactly what the lockfile lists, and `npm run build` runs Angular's build, which writes the browser files to `dist/web/browser/`.
- The second `FROM` starts a fresh stage from the nginx image. `COPY --from=build` copies only the built files out of the first stage. The final image gets nginx and those files; Node, `node_modules`, and the source code stay behind in the `build` stage.
- `EXPOSE 80` only documents which port nginx listens on. It doesn't make the port reachable from your computer.
- `ARG BUILD_LABEL` comes back in [Build-time values and runtime values](#build-time-values-and-runtime-values).

The API runs JavaScript on the server, so its image keeps Node and needs only one stage. `--omit=dev` skips packages that are only needed during development:

File: `api/Dockerfile`

```dockerfile
FROM node:24.21.0-bookworm-slim
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev
COPY server.mjs ./
EXPOSE 3000
CMD ["node", "server.mjs"]
```

## How the build cache decides what to rerun

Both Dockerfiles copy the package files and install dependencies before they copy the rest of the source. The order matters because of the **build cache**. For each step, Docker's builder looks at the instruction and its inputs, such as the files a `COPY` copies, plus the result of the step before it. If it has already run that exact step on those exact inputs, it reuses the stored result instead of running it again. That's a cache hit. If anything changed, it runs the step again, along with every step after it in that stage.

Suppose the Dockerfile copied everything first:

```dockerfile
COPY . .
RUN npm ci
RUN npm run build
```

Then fixing a typo in a component would change the `COPY . .` input, and the slow `npm ci` would run again even though no dependency changed. Copying `package.json` and `package-lock.json` first means only a change to those two files reruns the install.

Watch it happen. `--progress=plain` prints every step, and the tag after the colon (`:1`, `:2`, `:3`) keeps each build's image separate so cleanup can find them later:

```sh
docker build --progress=plain --label "docker-lab=$lab" -t "$lab-web:1" web
```

The first build runs every step, so `npm ci` takes a while. Now open `web/src/styles.css` in your editor, add a line such as `/* cache demo */`, save it, and build again:

```sh
docker build --progress=plain --label "docker-lab=$lab" -t "$lab-web:2" web
```

Trimmed output (step numbers and times vary):

```text
#9 [build 3/7] COPY package.json package-lock.json ./
#9 CACHED
#10 [build 4/7] RUN npm ci
#10 CACHED
#11 [build 5/7] COPY . .
#11 DONE 0.1s
#12 [build 6/7] RUN npm run build
#12 DONE 2.5s
```

`CACHED` means the builder reused the earlier result. The install was reused, and only the steps from `COPY . .` onward ran again. Next, open `web/package.json` and add `"description": "Greeting demo",` on the line after `"name": "web",`. Then build a third time:

```sh
docker build --progress=plain --label "docker-lab=$lab" -t "$lab-web:3" web
```

This time `COPY package.json package-lock.json ./` and `RUN npm ci` both run again, even though no dependency version changed. The builder compares file contents, not what the change means.

There's a trap here: the cache doesn't know about time. If `npm ci` ran last week and the lockfile hasn't changed, Docker reuses last week's result without asking npm anything. That's usually what you want, because the lockfile is the point. If you want to run every step again anyway, add `--no-cache`. If you want a newer version of the base image under the same tag, add `--pull`. They're separate flags because they solve separate problems.

This cache belongs to Docker's builder. It has nothing to do with npm's download cache or the browser's HTTP cache.

## Run the three services with Compose

Starting three containers by hand means three long `docker run` commands, plus a network and a volume. **Docker Compose** reads one file that describes all of them and creates the matching Docker resources. Save it in the lab directory itself:

File: `compose.yaml`

```yaml
services:
  web:
    build:
      context: ./web
      args:
        BUILD_LABEL: "${BUILD_LABEL:-first-build}"
      labels:
        docker-lab: "${COMPOSE_PROJECT_NAME}"
    ports:
      - "127.0.0.1:${WEB_PORT:-8080}:80"
    environment:
      BROWSER_GREETING: "${BROWSER_GREETING:-Hello}"
    depends_on:
      api:
        condition: service_healthy
  api:
    build:
      context: ./api
      labels:
        docker-lab: "${COMPOSE_PROJECT_NAME}"
    environment:
      DATABASE_URL: "postgres://demo:demo-only-password@db:5432/greetings"
      SERVICE_MESSAGE: "${SERVICE_MESSAGE:-Set when this container was created}"
    depends_on:
      db:
        condition: service_healthy
    healthcheck:
      test:
        [
          "CMD",
          "node",
          "-e",
          "fetch('http://127.0.0.1:3000/health').then((response) => { if (!response.ok) { process.exit(1); } }, () => process.exit(1))",
        ]
      interval: 2s
      retries: 15
  db:
    image: postgres:17.11-bookworm
    environment:
      POSTGRES_USER: demo
      POSTGRES_PASSWORD: demo-only-password
      POSTGRES_DB: greetings
    volumes:
      - dbdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -h 127.0.0.1 -U demo -d greetings"]
      interval: 2s
      retries: 15
volumes:
  dbdata:
```

What to notice:

- Each entry under `services` becomes a container. `web` and `api` have a `build` section, so Compose builds their images from those directories; `db` uses the official PostgreSQL image as it is.
- `${WEB_PORT:-8080}` reads the `WEB_PORT` environment variable from your terminal and falls back to `8080`. The other `${...}` values work the same way.
- `ports` connects port 8080 on your computer to port 80 in `web`. Only `web` has one, so no port on your computer leads to the API or the database.
- `environment` sets environment variables inside each container. That's how the API gets its `DATABASE_URL`.
- `volumes` gives the database a named storage area, `dbdata`, covered in [Where a container's writes go](#where-a-containers-writes-go).
- The helper set `COMPOSE_PROJECT_NAME` to the lab's name, so everything Compose creates starts with that name. `build.labels` gives the two built images the same `docker-lab` label as your earlier builds.

A database container can be running while PostgreSQL is still setting itself up, so "started" doesn't mean "ready". A **health check** is a command Docker runs inside the container every few seconds; the container counts as healthy once it succeeds. `pg_isready` asks whether PostgreSQL accepts connections, and the API's check requests its own `/health` URL, which runs a small database query. `condition: service_healthy` makes Compose wait for that dependency's health check before starting the next service, so the order is `db`, then `api`, then `web`.

Build the images and start everything. `-f compose.yaml` names the lab's file explicitly. Compose also reads a `COMPOSE_FILE` environment variable, which another project may have left in your terminal, and `-f` makes sure these commands use the lab's file instead; every Compose command in this article includes it. `--build` builds the `web` and `api` images first, `--detach` gives your terminal back, and `--wait` waits until the services are running and healthy:

```sh
docker compose -f compose.yaml up --build --detach --wait
```

Open `http://127.0.0.1:8080` in your browser. The page says `Hello, World!`. Enter a name, choose **Save**, and refresh the page: the name comes back from the database. In the browser's developer tools, the Network panel shows the `GET` and `PUT` requests going to `127.0.0.1:8080/api/name`, the same address that served the page.

## What localhost means inside a container

Follow one request. When the browser loads `http://127.0.0.1:8080`, the connection starts on your computer. When nginx forwards `/api/name`, a new connection starts inside the `web` container. When the API queries PostgreSQL, another connection starts inside `api`.

```text
Browser on your computer
  GET /                -> 127.0.0.1:8080 -> web:80 -> Angular's files
  runs the downloaded JavaScript
  GET or PUT /api/name -> 127.0.0.1:8080 -> web:80
                                             |
                                    nginx forwards to api:3000
                                             |
                                    API queries db:5432
                                             |
                                    named volume: dbdata
```

Each container gets its own network setup: its own network addresses and its own `localhost`. Inside a container, `localhost` (the address `127.0.0.1`) means that container and nothing else. See it from inside `web`. `docker compose exec` runs an extra command in a running service's container, and `wget -qO-` downloads a URL and prints it:

```sh
docker compose -f compose.yaml exec web wget -qO- http://localhost:3000/api/name
```

This fails with `Connection refused`, and that's expected: nothing listens on port 3000 inside `web`. Now ask for the API by its service name:

```sh
docker compose -f compose.yaml exec web wget -qO- http://api:3000/api/name
```

That prints the saved name. Compose put the three services on one private network and gave that network **DNS**, a name lookup that turns service names such as `api` and `db` into the containers' addresses. That's mystery number three: `localhost` always means the machine or container where the connection starts, so the API connects to `db`, not `localhost`, and nginx forwards to `api`.

Those service names exist only on the Compose network, so the browser can't use them. It doesn't need to: the Angular code calls the relative URL `/api/name`, which goes to the same origin as the page, and nginx forwards it from there. The `ports` entry in `compose.yaml` **publishes** a port: Docker listens on `127.0.0.1:8080` on your computer and passes those connections to port 80 inside `web`. With Docker Desktop, the Compose network lives inside Desktop's Linux virtual machine, so from macOS or Windows a published port is how you reach a container. Docker Engine on Linux differs: the Compose network is a bridge on the host itself, so programs on the host can also connect straight to a container's own address, for example the API's port 3000, without any published port. Published ports still decide what other machines can reach.

The listening side has its own version of the same rule. A server chooses which of its addresses to accept connections on. The API calls `server.listen(3000, "0.0.0.0")`, and `0.0.0.0` means every address the container has, including its address on the Compose network. Had it listened on `127.0.0.1` instead, it would accept connections only from inside its own container. Its health check, which runs inside `api`, would still pass, but every request from nginx would get `Connection refused`. That's a common reason a containerized server works in its own logs and fails for everyone else.

## Where a container's writes go

Start with a file write. Suppose a program in a container writes `/tmp/note`, and nothing is mounted at that path. The bytes go to that container's private **writable layer**, which sits on top of the image's layers. The image itself never changes.

Start two containers from the same image and write a note in the first one. `sleep 3600` gives each container a main process that waits for an hour, and `docker exec` runs an extra command in a running container:

```sh
docker run --detach --name "$lab-a" --label "docker-lab=$lab" node:24.21.0-bookworm-slim sleep 3600
docker run --detach --name "$lab-b" --label "docker-lab=$lab" node:24.21.0-bookworm-slim sleep 3600
docker exec "$lab-a" sh -c 'echo private A > /tmp/note'
docker exec "$lab-b" cat /tmp/note
```

The last command fails with `No such file or directory`, which is the point: `b` has its own writable layer and can't see `a`'s note. Now restart `a` and read its note again:

```sh
docker restart "$lab-a"
docker exec "$lab-a" cat /tmp/note
```

The restart can take about 10 seconds. `docker restart` first sends the main process a stop signal called SIGTERM, and `sleep` running as a container's main process ignores it, so Docker waits for its time limit and then forces it to stop. That's also why the API handles SIGTERM itself. After the restart, the note is still there: stopping and starting keeps the writable layer. Removing the container deletes it, and a new container made from the same image starts without the note.

### Bind mounts

A **mount** makes a path inside the container lead to storage outside the container's writable layer. A bind mount uses a directory you choose on the machine where the Docker daemon runs, which in this lab is your computer. In `--mount "type=bind,src=$lab_share,dst=/shared"`, `src` is the directory on your computer (the lab's `share` directory) and `dst` is where programs inside the container see it. There's one set of files and two paths to them; nothing is copied back and forth.

The setup commands already relied on this: the Angular project and the lockfiles appeared in your lab directory, even though `--rm` removed the containers that wrote them. Try it directly, then try the same write through a read-only mount:

In bash:

```bash
docker run --rm --user "$lab_user" --mount "type=bind,src=$lab_share,dst=/shared" \
  node:24.21.0-bookworm-slim sh -c 'echo from container > /shared/note'
cat share/note
docker run --rm --mount "type=bind,src=$lab_share,dst=/shared,readonly" \
  node:24.21.0-bookworm-slim sh -c 'echo replaced > /shared/note'
```

In PowerShell:

```powershell
docker run --rm --user "$lab_user" --mount "type=bind,src=$lab_share,dst=/shared" `
  node:24.21.0-bookworm-slim sh -c 'echo from container > /shared/note'
cat share/note
docker run --rm --mount "type=bind,src=$lab_share,dst=/shared,readonly" `
  node:24.21.0-bookworm-slim sh -c 'echo replaced > /shared/note'
```

`cat share/note` prints `from container`: the file is on your computer, and it outlives the container that wrote it. The last command fails with `Read-only file system`, as expected, and the note keeps its text. A bind mount without `readonly` lets the container create, change, and delete files in that directory, so mount only the directory a container actually needs, never your home directory.

A mount also hides whatever the image had at that path. If you mounted `share` at `/usr/local/bin`, the container would see your note there instead of the image's `node` program. The image still contains `node`; this container just can't see it at that path.

### Named volumes

PostgreSQL saves rows by writing its own database files, and those files should survive a replacement container without you picking a directory for them. A **named volume** is storage that Docker creates and manages under a name. In `compose.yaml`, `dbdata:/var/lib/postgresql/data` attaches the `dbdata` volume at the path where the PostgreSQL 17 image keeps its data. Compose names the actual volume after the project, so it starts with your lab's name. With Docker Desktop, the files live inside its Linux virtual machine, not in a folder you'd browse.

Saving a name follows this path:

```text
Save in the browser
  -> nginx forwards PUT /api/name
  -> the API updates the row in PostgreSQL
  -> PostgreSQL writes its files under /var/lib/postgresql/data
  -> those writes go to the dbdata volume
```

Test it. Save a new name in the browser, then remove all three containers and the network with `down`, which keeps named volumes unless you add `--volumes`:

```sh
docker compose -f compose.yaml down
docker volume ls --filter "name=$lab"
```

The containers are gone, and the volume is still listed. Create fresh containers:

```sh
docker compose -f compose.yaml up --detach --wait
```

Refresh the page and your saved name is still there. The startup code can't explain that, because it inserts `World` only when the row is missing. The new `db` container found the old database files in the volume.

| Storage                  | Stop and start the container | Remove the container                   |
| ------------------------ | ---------------------------- | -------------------------------------- |
| Image layers             | Unchanged                    | Unchanged; the image is still there    |
| Container writable layer | Kept                         | Deleted                                |
| Bind-mounted directory   | Kept                         | Kept on your computer                  |
| Named volume             | Kept                         | Kept until you remove the volume       |

## Build-time values and runtime values

Some values are fixed when an image is built, and others are read when a container starts.

`ARG BUILD_LABEL` in the web Dockerfile is a **build argument**: a value available only while the image is being built. Compose passed `first-build` through `build.args`, and a `RUN` step wrote it into `build-label.txt`, which is now part of the image. Environment variables under `environment` in `compose.yaml` are runtime values: Docker sets them when it creates a container, and they reach only programs that actually read them.

Change all three values in your terminal:

In bash:

```bash
export SERVICE_MESSAGE='Changed without a rebuild'
export BROWSER_GREETING='Howdy'
export BUILD_LABEL='changed-without-a-build'
```

In PowerShell:

```powershell
$env:SERVICE_MESSAGE = 'Changed without a rebuild'
$env:BROWSER_GREETING = 'Howdy'
$env:BUILD_LABEL = 'changed-without-a-build'
```

Then run `up` again. Compose sees that the `api` and `web` settings changed and replaces those two containers; it doesn't rebuild images that already exist:

```sh
docker compose -f compose.yaml up --detach --wait
```

Check each value:

- `http://127.0.0.1:8080/api/message` shows `Changed without a rebuild`. The API reads `SERVICE_MESSAGE` when it runs, and its new container got the new value.
- `http://127.0.0.1:8080/build-label.txt` still shows `first-build`. That file was written during the build, and nothing was rebuilt.
- The page still says `Hello, …`, not `Howdy`. Run `docker compose -f compose.yaml exec web printenv BROWSER_GREETING` and it prints `Howdy`: nginx's container has the variable, but nginx only sends files, and the browser never sees the server's environment. The word `Hello` is compiled into Angular's JavaScript. For the browser to get a value at runtime, the app has to fetch it, the way it fetches the name.

## The three mysteries, explained

Each mystery came from treating two separate things as one.

- **The deleted file still took space** because an image is a stack of layers, and a layer only records changes. `docker image history` showed the step that added 4.19 MB, and the later delete step only hid the file.
- **The container stopped on its own** because a container runs exactly as long as its main process. `docker container inspect` reported `exited 0` after the command printed its line, while nginx, the API, and `sleep` kept their containers running because their main processes kept running.
- **`localhost` meant something else** because every container has its own network setup. From inside `web`, `localhost:3000` was refused and `api:3000` answered, and the browser reached the app only through the published port.

The saved name follows the same idea: it survived new containers because it lives in a volume, which has its own lifetime. So when Docker surprises you, ask which of these you're dealing with: the image, the container's process, or the network and storage it can see.

## Clean up

The cleanup command removes the lab's containers, network, volume, and images, then deletes the lab directory. Before it deletes anything, it lists everything it plans to remove and checks each item. The lab directory must be the one the helper created. The experiment containers and the exact image tags the article built must carry this lab's `docker-lab` label. The Compose project's containers, network, and volume must have the names Compose gave them. If any check fails, or Docker reports an error while it checks, it stops before deleting anything and tells you what to inspect. It removes images by tag, so an image that also has a tag of yours keeps that tag. Deletions can't be undone, though: if Docker itself fails partway through, what's already removed stays removed, so fix the error and run the command again to finish.

In bash:

```bash
lab_cleanup
```

In PowerShell:

```powershell
Remove-DockerLab
```

If cleanup refuses a container or image that you know you created in this lab, for example one created without the `--label` option, the label is what's missing. Check it with `docker container inspect` or `docker image inspect` and the name from the message, remove it yourself with `docker container rm --force` or `docker image rm` and that name, then run the cleanup command again.

Cleanup also leaves untagged images alone. If you rebuilt a tag, for example by running `up --build` twice, the older image lost its name. Cleanup can't safely claim it, because an image built `FROM` one of the lab's images inherits the lab's label too. `docker image ls --filter dangling=true` lists untagged images, and `docker image rm` followed by an image ID removes one you're sure you don't need.

The base images the lab downloaded stay, because other projects on your machine may use them. Look for `node`, `nginx`, and `postgres` in `docker image ls`, and remove the ones nothing else needs with `docker image rm`. Docker's build cache stays too; `docker builder prune` clears it, but for every project on your machine, not just this lab.

## Sources and further reading

- [Docker: build contexts and `.dockerignore`](https://docs.docker.com/build/concepts/context/)
- [Docker: Dockerfile instructions](https://docs.docker.com/reference/dockerfile/)
- [Docker: build-cache invalidation](https://docs.docker.com/build/cache/invalidation/)
- [Docker: multi-stage builds](https://docs.docker.com/build/building/multi-stage/)
- [Docker Compose: networking](https://docs.docker.com/compose/how-tos/networking/)
- [Docker Compose: startup order and readiness](https://docs.docker.com/compose/how-tos/startup-order/)
- [Docker: bind mounts](https://docs.docker.com/engine/storage/bind-mounts/)
- [Docker: volumes](https://docs.docker.com/engine/storage/volumes/)
- [Microsoft: about execution policies](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_execution_policies)
