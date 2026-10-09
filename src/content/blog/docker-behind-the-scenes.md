---
title: "Docker behind the scenes: images, processes, and their environment"
description: "Trace a small greeting app through image builds, running processes, networks, and persistent storage to explain what Docker actually changes."
pubDate: "2026-10-08"
tags:
  - docker
  - tooling
  - fundamentals
---

A container starts, prints a message, and immediately stops. An image stays large after a large file is deleted. An API works at `localhost` from one place but not another.

These are not three unrelated Docker quirks. They follow from separating **stored files**, **running processes**, and **the environment each process can see**.

The running example displays `Hello, World!`. Enter a name and save it to change the greeting. Angular runs in the browser, nginx serves its built files, a small Node API reads and saves the name, and PostgreSQL stores it. Each server has its own container. The saved name has a lifetime separate from those containers.

## Contents

1. [Three mysteries, three boundaries](#three-mysteries-three-boundaries)
2. [An image is an artifact; a container runs processes](#an-image-is-an-artifact-a-container-runs-processes)
3. [Layers describe filesystem changes](#layers-describe-filesystem-changes)
4. [A Dockerfile describes a build, not startup](#a-dockerfile-describes-a-build-not-startup)
5. [Build caching reuses relevant inputs](#build-caching-reuses-relevant-inputs)
6. [Multi-stage builds separate tools from serving](#multi-stage-builds-separate-tools-from-serving)
7. [Registries distribute images; tags name versions](#registries-distribute-images-tags-name-versions)
8. [Container lifetime follows the main process](#container-lifetime-follows-the-main-process)
9. [Networking depends on where code runs](#networking-depends-on-where-code-runs)
10. [Mounts give data a different lifetime](#mounts-give-data-a-different-lifetime)
11. [Compose describes collaborating services](#compose-describes-collaborating-services)
12. [Sources and further reading](#sources-and-further-reading)

## Three mysteries, three boundaries

Start with predictions rather than commands:

- Printing a message finishes a program. Why would its container keep running?
- Deleting a file changes what a later filesystem view shows. Does it erase an earlier stored copy?
- `localhost` means the machine or network environment making the connection. Which process is making this connection?

Keep those questions in view while building the example. Docker does not turn files into a permanently running service, erase previous image content, or make every process share one network address.

## An image is an artifact; a container runs processes

A server program needs more than its source file. It may need an executable runtime, libraries, configuration files, and a directory to work in. Docker can package those files together with defaults such as the command to start.

Before running anything, look at the package's parts. An **archive** groups file entries and their contents in one stored file. For these filesystem changes, the archive format is typically tar, optionally compressed to reduce storage or transfer size. A **manifest** is a document that points to the package's configuration and lists its filesystem-change archives in the order to apply them. The configuration records startup defaults such as the command, environment variables, and working directory.

Conceptual package view — not a promised directory layout:

```text
manifest
  configuration -> start command, environment, working directory
  filesystem changes, in order:
    1. archive -> add runtime and library files
    2. archive -> add application files; replace a configuration file
    3. archive -> record deletion of a temporary file from archive 2
```

To assemble the files a program will see, apply those changes in order: add new files, replace modified files, and hide paths marked as deleted. Each stored change archive is immutable: changing its contents creates different image content. A deletion in archive 3 hides the earlier file in the assembled view; it does not erase the bytes stored in archive 2.

That stored package is an **image**. It is an artifact: something built and saved, not a running program. Its recorded content does not change when a container writes a file. OCI (the Open Container Initiative) specifies interoperable image formats. An OCI image is not inherently a ZIP file or one directory per change archive; transport formats and Docker's extracted local storage can differ from this conceptual view.

When Docker creates a **container**, it combines an image with a particular configuration: environment variables, network connections, mounts, and a private place for filesystem writes. Starting the container starts its main program. A **process** is a running instance of a program, with memory and an execution state. A container can exist before that process starts and after it stops.

Two containers can use the same image while having different processes, environment variables, and writable files:

```text
                 shared image files + startup defaults
                              /         \
                    container A       container B
                    private writes    private writes
                    process A         process B
```

The **kernel** is the operating-system code that manages processes, memory, files, and network access. Linux containers share the kernel of their Linux host; each container does not boot its own operating system. Docker gives processes separate views of resources and can limit their resource use. This isolation is not perfect security or complete independence from the host.

On macOS and Windows, Docker Desktop normally runs Linux containers inside a Linux virtual machine. A **virtual machine** has its own operating-system kernel. The containers share that VM's Linux kernel, not the macOS or Windows kernel. This article concerns Linux containers, not Windows containers.

### Set up a disposable lab

Use ordinary **Windows PowerShell 5.1** on Windows 10/11 with Docker Desktop already running in **Linux container mode**, with Compose and BuildKit support. Use a Windows version supported by your Docker Desktop release; see its [Windows requirements](https://docs.docker.com/desktop/setup/install/windows-install/). Docker Desktop's WSL 2 backend does not require installing Ubuntu or opening a Bash terminal: the Docker client works from Windows PowerShell. This lab does not install Docker Desktop or change permissions or services.

You need network access to Docker Hub/npm and several GB of free disk space. No host Python, Node, or separate HTTP command-line tool is needed. The commands generate and install demonstration packages inside official Node containers; they still download and execute npm dependencies.

Node runs JavaScript outside a browser. npm is its package manager: it retrieves libraries and tools published as packages. The Angular CLI is a command-line tool that generates and builds Angular projects.

**Use a local Docker daemon.** The Docker command is a client; the daemon is the background service that creates containers. A bind mount exposes a path on the daemon's machine, not an arbitrary path on the client's machine. Desktop bridges supported host paths into its VM. These commands are not a remote-daemon setup guide and do not change Docker permissions.

Run the blocks labelled **Executable PowerShell** in order, in the same PowerShell window. Stop on any unexpected failure. Blocks labelled **File** are complete contents to save with your editor at that path relative to the lab, not commands; save them as UTF-8 without a byte-order mark (BOM). Other blocks are illustrative. Keep the window open: it remembers the lab's directory and resource names.

PowerShell commands run on Windows. Commands after an image name, or after `docker exec`, run inside a Linux container. In particular, `sh -c '...'` passes one literal command string to the container's Linux shell; its `>` and `&&` belong to that shell, not PowerShell. Dockerfile `RUN` commands also execute in the build container. A backtick at the end of a PowerShell line continues the command; do not put spaces after it.

All publications use the host's loopback address, which accepts local connections. The lab uses port 8080 by default. If occupied, set `$env:WEB_PORT = '8081'` (or another available port) before the setup block; use that value in the browser too. Nothing publishes the database or API directly.

Executable PowerShell — create the lab and refuse existing resource names:

```powershell
# lab:setup
$ErrorActionPreference = 'Stop'

function Invoke-LabDocker {
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $global:LASTEXITCODE = $null
        & docker.exe @args
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($null -eq $exitCode -or $exitCode -ne 0) {
        throw "Docker failed or returned no exit status ($exitCode). Stop the lab here."
    }
}

$lab = 'dockerscenes-' + [Guid]::NewGuid().ToString('N').Substring(0, 16)
$env:COMPOSE_PROJECT_NAME = $lab
$sandbox = Join-Path ([System.IO.Path]::GetTempPath()) $lab
New-Item -ItemType Directory -Path $sandbox | Out-Null
Set-Location -LiteralPath $sandbox
$utf8 = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false

if ([string]::IsNullOrEmpty($env:WEB_PORT)) {
    $env:WEB_PORT = '8080'
}
$port = [int]$env:WEB_PORT
if ($port -lt 1024 -or $port -gt 65535) {
    throw 'Choose a port between 1024 and 65535.'
}
$listener = New-Object -TypeName System.Net.Sockets.TcpListener -ArgumentList ([System.Net.IPAddress]::Loopback), $port
try {
    $listener.ExclusiveAddressUse = $true
    $listener.Start()
} finally {
    $listener.Stop()
}

$env:SERVICE_MESSAGE = 'Name stored in PostgreSQL'
$env:BROWSER_GREETING = 'Ignored by compiled JavaScript'
$env:BUILD_LABEL = 'built-in-the-lab'

$projectContainers = @(Invoke-LabDocker ps -aq --filter "label=com.docker.compose.project=$lab")
$labContainers = @(Invoke-LabDocker ps -aq --filter "label=io.example.docker-scenes=$lab")
if ($projectContainers.Count -ne 0 -or $labContainers.Count -ne 0) {
    throw 'This lab name already has containers.'
}
$containerNames = @(Invoke-LabDocker container ls --all --format '{{.Names}}')
foreach ($name in @('exit', 'a', 'b', 'bind', 'readonly', 'obscure', 'scaffold', 'web-lock', 'api-lock', 'web-1', 'api-1', 'db-1')) {
    if ($containerNames -ccontains "${lab}-$name") {
        throw "Container name already exists: ${lab}-$name"
    }
}
$networkNames = @(Invoke-LabDocker network ls --format '{{.Name}}')
$volumeNames = @(Invoke-LabDocker volume ls --format '{{.Name}}')
foreach ($name in @("${lab}-default", "${lab}-dbdata")) {
    if ($networkNames -ccontains $name -or $volumeNames -ccontains $name) {
        throw "Network or volume name already exists: $name"
    }
}
$imageTags = @(Invoke-LabDocker image ls --format '{{.Repository}}:{{.Tag}}')
foreach ($name in @('web', 'api', 'layers')) {
    if ($imageTags -ccontains "${lab}-${name}:lab") {
        throw "Image tag already exists: ${lab}-${name}:lab"
    }
}
New-Item -ItemType Directory -Path 'layers', 'api', 'share' | Out-Null
[System.IO.File]::WriteAllText((Join-Path $sandbox '.lab-owner'), "$lab`n", $utf8)
Write-Host "Lab: $lab"
Write-Host "Directory: $sandbox"
```

`New-Item` creates the new directory under Windows' temporary path; `Set-Location` enters it. `$sandbox` and `$lab` hold values in this PowerShell session. `$env:...` also makes a value available to programs started from that session, including Compose. Keep this temporary directory until the lab is finished; Desktop shares its Windows paths with the Linux VM for the bind mounts. Use a local temporary path that Desktop can share; the `--mount` arguments here assume the path contains no commas.

`Invoke-LabDocker` is the lab's small function, not a Docker subcommand. It forwards its arguments to `docker.exe` and checks `$LASTEXITCODE` immediately. Clearing the old status first prevents a failed launch from reusing an earlier success; a missing status is rejected too. PowerShell 5.1's `$ErrorActionPreference = 'Stop'` stops PowerShell errors, but does not turn a nonzero native program exit into an exception. Inside the function, `Continue` lets native stderr remain visible, including normal build progress, before the exit-code check. Docker's stdout can still be captured as data; none of that output is executed as PowerShell.

The unique name keeps this lab separate from other Compose projects. Labels attach ownership information to resources; they are metadata, not access controls. The port check catches an existing listener but cannot prevent another program taking the port afterward; Docker will then fail rather than use another port silently.

The examples use `node:24.21.0-bookworm-slim`, `nginx:1.30.5-alpine`, and `postgres:17.11-bookworm`: versioned tags of the official images. Tags are still movable, as explained below. The Angular CLI/framework versions are 22.2.1, TypeScript is 6.0.3, and the API's only direct npm dependency is `pg` 8.23.1. Generated lockfiles record the resolved indirect dependencies.

## Layers describe filesystem changes

Imagine storing one filesystem change that adds a file and another change that deletes it. Reading the combined result should hide the file, but the earlier stored addition still contains its bytes.

An image's **layers** record changes: additions, replacements, and deletions. Docker presents their combined view as the container's **filesystem**: the files and directories its programs see. Matching layers can be reused by different images rather than stored or transferred as separate full copies.

Each container also gets a **writable layer** for its own changes. Writing outside mounts changes that container's view, not the shared image. Removing the container discards that writable layer. Stopping it does not.

Save this small experiment. It creates 4 MiB of random demonstration bytes, then deletes the file in a separate build step.

File: `layers/Dockerfile`

```dockerfile
FROM node:24.21.0-bookworm-slim
RUN node -e "require('node:fs').writeFileSync('/large.bin', require('node:crypto').randomBytes(4 * 1024 * 1024))"
RUN rm /large.bin
CMD ["sh", "-c", "test ! -e /large.bin && echo 'File is absent'"]
```

Executable PowerShell — build and inspect the recorded changes:

```powershell
# lab:layers
Invoke-LabDocker build --progress=plain --label "io.example.docker-scenes=$lab" `
    -t "${lab}-layers:lab" layers
Invoke-LabDocker image history --no-trunc "${lab}-layers:lab"
```

The history includes the step that added the bytes even though the final view hides the file. Reported image sizes and transferred sizes need not be identical: compression and shared storage affect the accounting.

Creating and deleting temporary data within the **same** `RUN` can avoid retaining it in that step's final filesystem changes. A later deletion cannot make an earlier addition secret. **Never copy real credentials into the context or image and rely on later deletion.** Build arguments and ordinary environment variables are not secret-delivery mechanisms either.

Not every instruction adds filesystem bytes. `CMD`, `ENV`, and `EXPOSE`, for example, record configuration. A history entry is not necessarily a new filesystem-content layer.

## A Dockerfile describes a build, not startup

Follow the experiment line by line:

1. `FROM` chooses an existing image as the starting point.
2. `RUN node ...` executes a program during the build and records its filesystem changes.
3. `RUN rm ...` executes another build-time program.
4. `CMD` records the default command for a future container. It does not execute it during the build.

A **Dockerfile** is this build recipe. `WORKDIR`, used shortly, sets the working directory for later instructions. `COPY` copies files from the build inputs into the stage being built. `docker build` produces an image; `docker run` creates and starts a container from an image.

### Choose the files the build can use

The Dockerfile is a recipe, but it does not give the builder access to every file on Windows. The build command separately chooses a directory containing the files available to the recipe. This directory and its eligible contents are the **build context**.

In `docker build ... layers`, the final `layers` argument chooses that directory. In the frontend commands below, the final `web` argument chooses the frontend directory. A final `.` would instead choose the PowerShell window's current directory. Selecting a Dockerfile with `-f` changes the recipe, not the separately chosen context root.

For the frontend's local-directory build, follow these steps:

1. Start with `web` and its subdirectories as candidate inputs. Files outside `web`, such as the sibling `api` directory, are not ordinary `COPY` inputs for this build.
2. Read `web/.dockerignore`. Its rules remove matching paths from those inputs before their file contents are made available to the builder.
3. Make the remaining input files available to the build. BuildKit can skip transferring unused files and transfer changed content incrementally; this is not necessarily one ZIP containing the whole directory.
4. Execute the Dockerfile. Each ordinary `COPY` chooses files from the filtered inputs and places them in the stage's filesystem. Merely being available as an input does not put a file in an image.

Illustrative selected host paths — not extra files to create:

```text
web/                         chosen context root
  Dockerfile                 recipe, read by the builder
  .dockerignore              input-filtering rules
  package.json               available input
  package-lock.json          available input
  src/main.ts                available input
  node_modules/              excluded by our rules
  dist/                      excluded by our rules
  .env                       excluded by our rules
api/                         outside the chosen web context
```

### Filter inputs with .dockerignore

The ignore file below lists one rule per line, relative to the context root. `node_modules` excludes that directory and its contents; `dist` excludes old build output; `.env` excludes that file, and `.env.*` matches names such as `.env.local`. The files remain on Windows; filtering does not delete them. `.gitignore` does not replace `.dockerignore` for a local-directory build.

With `COPY . .`, leaving `node_modules` unignored makes those dependency files build inputs too. Reading and transferring them can slow context loading. The copy can also overwrite dependencies installed by `npm ci` inside the Linux build container with Windows-installed files that may not work there.

The relevant file here is **`web/.dockerignore`**, not an ignore file in the parent lab directory. The API later has its own context, `api`, and its own `api/.dockerignore`. Docker also supports Dockerfile-specific ignore files, but this lab uses only the ordinary context-root files.

In the frontend Dockerfile, `WORKDIR /app` makes `/app` the current directory inside the build stage. `COPY package.json package-lock.json ./` reads those two files from the **context root** and writes them to `/app`. In `COPY . .`, the first dot means the filtered context contents; the second means the stage's current directory. Neither dot means the Windows home directory. An excluded source file cannot be copied by an ordinary context-based `COPY`.

The Dockerfile and ignore rules are build-control inputs: Docker must read them even if an ignore rule excludes them from copyable inputs. `COPY --from=build`, used later, is different: it reads another stage's filesystem, not the Windows context.

Keep three boundaries separate: **available build inputs → files copied into a stage → files selected for the final image**. An edited Windows file does not change an already-built image automatically. Excluding unwanted files reduces accidental inclusion, but do not put real secrets in this lab or rely on deleting them in a later image layer.

### Generate the Angular skeleton explicitly

The official CLI creates the otherwise tedious project/build configuration. `--skip-install` leaves dependency installation for a separate step. `--minimal` omits test infrastructure; `--routing=false` and `--ssr=false` keep this a single static page.

Executable PowerShell — scaffold in a Linux container, mounting only this new lab:

```powershell
# lab:scaffold
Invoke-LabDocker run --rm --name "${lab}-scaffold" --label "io.example.docker-scenes=$lab" `
    --env HOME=/tmp --env NG_CLI_ANALYTICS=false `
    --mount "type=bind,src=$sandbox,dst=/lab" --workdir /lab `
    node:24.21.0-bookworm-slim `
    npx --yes --package=@angular/cli@22.2.1 ng new web --directory web `
    --minimal --routing=false --ssr=false --style=css --skip-tests `
    --skip-git --skip-install --defaults --package-manager=npm --ai-config=none
```

The source path is the Windows lab directory; `/lab` is its location inside the Linux container. No Linux user/group mapping is needed for this Windows host. `HOME=/tmp` gives npm a temporary home inside the container. `--rm` removes this short-lived container when its command finishes, not the files it wrote into the mount.

Retain the CLI's `angular.json`, TypeScript configuration, and other scaffold files. Replace `web/package.json`, `web/src/main.ts`, and `web/src/styles.css` with the files below. The generated `src/index.html` already contains `<app-root></app-root>`, where the page starts. The replacement `main.ts` contains the small greeting component itself; it no longer imports the generated sample component.

File: `web/.dockerignore`

```text
node_modules
dist
.angular
.git
.env
.env.*
```

Use the same complete ignore file for the API:

File: `api/.dockerignore`

```text
node_modules
dist
.angular
.git
.env
.env.*
```

## Build caching reuses relevant inputs

Suppose a build copied the entire frontend before installing dependencies:

Illustrative Dockerfile fragment — not a file to create:

```dockerfile
COPY . .
RUN npm ci
RUN npm run build
```

Changing a page's text changes the copied input. The dependency-install step then has a different preceding state, even if dependencies did not change.

Instead, copy `package.json` and `package-lock.json` first and install from them. Copy application source afterward. An unchanged install can be reused while the application is compiled again.

The builder stores results under keys derived from instructions and their relevant inputs. Finding an existing matching result is a **cache hit**; doing the work again is a **cache miss**. Files copied by `COPY` participate in this comparison; their content and relevant metadata matter, but merely changing their modification time does not. Work depending on changed inputs must be rebuilt. Independent stages can still reuse unrelated work.

A cached package-install command does not become fresh because a week passed. The builder does not contact the package registry just to discover whether that unchanged command could now install something different. A lockfile and `npm ci` deliberately preserve the recorded dependency resolution. `--no-cache` forces build steps to execute again; it does not update the lockfile or automatically pull a newer base image. `--pull` separately requests a fresh resolution of the base-image tag.

Keep three cache owners separate:

| Cache                           | Owner and stored work                            |
| ------------------------------- | ------------------------------------------------ |
| Docker build cache              | The builder; reusable instruction results        |
| npm download cache              | npm; downloaded package data                     |
| Browser/HTTP/application caches | Clients or applications; resources and responses |

Reusing one does not establish freshness in the others. The following build uses ordinary `npm ci`, without adding a persistent npm cache mount.

## Multi-stage builds separate tools from serving

Angular's TypeScript source is not what nginx executes. TypeScript adds type checks to JavaScript; Angular's build turns the application's source and assets into JavaScript, HTML, and CSS files. nginx sends those files over HTTP, the protocol in which a client makes a request and a server returns a response. The browser executes the downloaded JavaScript.

First provide the complete frontend files. The direct package versions are fixed here; the lockfile generated afterward fixes their dependency tree.

File: `web/package.json`

```json
{
  "name": "web",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "build": "ng build --configuration production --output-path dist/web"
  },
  "dependencies": {
    "@angular/common": "22.2.1",
    "@angular/compiler": "22.2.1",
    "@angular/core": "22.2.1",
    "@angular/platform-browser": "22.2.1",
    "rxjs": "7.8.2",
    "tslib": "2.8.1"
  },
  "devDependencies": {
    "@angular/build": "22.2.1",
    "@angular/cli": "22.2.1",
    "@angular/compiler-cli": "22.2.1",
    "typescript": "6.0.3"
  }
}
```

File: `web/src/main.ts`

```typescript
import { Component, signal } from "@angular/core";
import { bootstrapApplication } from "@angular/platform-browser";

@Component({
  selector: "app-root",
  template: `
    <main>
      @if (name() !== "") {
        <h1>Hello, {{ name() }}!</h1>
      } @else {
        <h1>Greeting demo</h1>
      }
      <form (submit)="saveName($event, nameInput.value)">
        <label for="name">Name</label>
        <input
          #nameInput
          id="name"
          name="name"
          autocomplete="name"
          required
          maxlength="80"
          [value]="name()"
          [disabled]="isBusy()"
          aria-describedby="name-help"
        />
        <p id="name-help">Enter a name of up to 80 characters.</p>
        <button type="submit" [disabled]="isBusy()">Save</button>
      </form>
      <p role="status">{{ status() }}</p>
    </main>
  `,
})
class Greeting {
  readonly name = signal("");
  readonly isBusy = signal(true);
  readonly status = signal("Loading saved name…");

  constructor() {
    void this.loadName();
  }

  async loadName(): Promise<void> {
    try {
      const response = await fetch("/api/name");
      if (!response.ok) {
        throw new Error("Name request failed");
      }
      const name = await response.text();
      this.name.set(name);
      this.status.set("");
    } catch {
      this.status.set("Could not load the name. Refresh to try again.");
    } finally {
      this.isBusy.set(false);
    }
  }

  async saveName(event: Event, proposedName: string): Promise<void> {
    event.preventDefault();
    this.isBusy.set(true);
    this.status.set("Saving…");
    try {
      const response = await fetch("/api/name", {
        method: "PUT",
        headers: { "Content-Type": "text/plain; charset=utf-8" },
        body: proposedName,
      });
      if (!response.ok) {
        throw new Error("Name save failed");
      }
      const name = await response.text();
      this.name.set(name);
      this.status.set("Name saved.");
    } catch {
      this.status.set("Could not save the name. Check it and try again.");
    } finally {
      this.isBusy.set(false);
    }
  }
}

bootstrapApplication(Greeting).catch((error: unknown) => {
  console.error(error);
});
```

The input holds the proposed name. Saving sends it to the API; only a successful response changes the greeting. `signal` stores a value and tells Angular to update the display when it changes. The API returns plain text, which `response.text()` reads as a string. Reloading the page requests the saved name again.

The native form supplies a labelled input, required/length checks, and Enter-to-submit behavior. The server also rejects blank or oversized names. The status paragraph announces request outcomes; a failed save leaves the proposed edit available to retry.

File: `web/src/styles.css`

```css
:root {
  color-scheme: dark;
  font-family: system-ui, sans-serif;
  background: #15171b;
  color: #f1f3f5;
}
body {
  margin: 0;
}
main {
  max-width: 40rem;
  margin: auto;
  padding: 1.5rem;
}
button,
input {
  font: inherit;
  padding: 0.5rem 0.75rem;
  max-width: 100%;
  box-sizing: border-box;
}
label {
  display: block;
  margin-block: 1rem 0.5rem;
}
h1 {
  overflow-wrap: anywhere;
}
@media (prefers-color-scheme: light) {
  :root {
    color-scheme: light;
    background: #fff;
    color: #20242a;
  }
}
```

File: `web/nginx.conf`

```nginx
server {
    listen 80;
    server_name _;
    root /usr/share/nginx/html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location /api/ {
        proxy_pass http://api:3000;
    }
}
```

`proxy_pass` forwards matching requests to the API. With no trailing URI on that directive, `/api/name` remains `/api/name` upstream. This file replaces nginx's default server configuration; no environment-template substitution is configured.

File: `web/Dockerfile`

```dockerfile
FROM node:24.21.0-bookworm-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
ARG BUILD_LABEL=built-in-the-lab
RUN npm run build && printf '%s\n' "$BUILD_LABEL" > dist/web/browser/build-label.txt

FROM nginx:1.30.5-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist/web/browser/ /usr/share/nginx/html/
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

The first `FROM` starts a stage named `build`. It includes Node, npm, Angular's compiler, dependencies, and source. The second `FROM` starts a different stage from nginx. `COPY --from=build` takes only generated browser files from the first stage.

The final image does **not** inherit all previous stages. Here it needs nginx and the generated files, not Node, TypeScript, `node_modules`, or the source tree. Build-stage data can still occupy the builder's cache even though it is not part of the final serving image.

`daemon off;` keeps nginx in the foreground. The official image's inherited entrypoint performs its startup setup and then launches this command. This is a **static Angular build**; an Angular application that renders pages on the server also needs its server runtime and server output. Copying only browser files would not reproduce that behavior.

Executable PowerShell — generate the frontend lockfile, then observe cache decisions:

```powershell
# lab:web-build
$webPath = Join-Path $sandbox 'web'
Invoke-LabDocker run --rm --name "${lab}-web-lock" --label "io.example.docker-scenes=$lab" `
    --env HOME=/tmp --mount "type=bind,src=$webPath,dst=/app" --workdir /app `
    node:24.21.0-bookworm-slim npm install --package-lock-only

Invoke-LabDocker build --no-cache --progress=plain --label "io.example.docker-scenes=$lab" `
    -t "${lab}-web:lab" web
Invoke-LabDocker build --progress=plain --label "io.example.docker-scenes=$lab" `
    -t "${lab}-web:lab" web

$cssPath = Join-Path $sandbox 'web\src\styles.css'
[System.IO.File]::AppendAllText($cssPath, "`n/* Changed source input for the cache example. */`n", $utf8)
Invoke-LabDocker build --progress=plain --label "io.example.docker-scenes=$lab" `
    -t "${lab}-web:lab" web

$packagePath = Join-Path $sandbox 'web\package.json'
$package = Get-Content -LiteralPath $packagePath -Raw -Encoding UTF8 | ConvertFrom-Json
$package | Add-Member -MemberType NoteProperty -Name description -Value 'Changed manifest input for the cache example' -Force
$packageJson = ConvertTo-Json -InputObject $package -Depth 10
[System.IO.File]::WriteAllText($packagePath, "$packageJson`n", $utf8)
Invoke-LabDocker build --progress=plain --label "io.example.docker-scenes=$lab" `
    -t "${lab}-web:lab" web
```

The first build forces execution without deleting anyone's cache. The unchanged build should reuse the install and compilation results. The CSS comment changes the source copy and compilation inputs, not the manifest copy/install inputs. Changing the manifest description makes even the manifest copy and install miss their previous cache keys, although no dependency version changed. `npm ci` still uses the same locked dependencies. Read the builder's actual step output; timings alone do not prove reuse.

## Registries distribute images; tags name versions

A **registry** stores images so another machine can retrieve them. Docker Hub supplies the official base images used here. Pulling downloads required content; already available matching layers can be reused. Pushing uploads content to a registry, but this lab never pushes anything.

In `node:24.21.0-bookworm-slim`, `node` is the image repository and the part after `:` is a **tag**. A tag is a name that its publisher can move to different content. Even a version-looking tag is not an immutable identity. `latest` is another tag, not a command to find the newest release or update containers automatically.

A **digest** is an identifier calculated from content. An image reference using `repository@sha256:...` identifies particular content instead of following a movable tag. Multi-platform images can have a digest for the platform index and separate digests for its platform-specific manifests; an image's local ID is not interchangeable with all of these registry identifiers.

Executable PowerShell — see the pulled base's recorded registry references:

```powershell
# lab:registry
$imageJson = Invoke-LabDocker image inspect node:24.21.0-bookworm-slim
$image = @(ConvertFrom-Json -InputObject ($imageJson -join "`n"))[0]
$image.RepoDigests
```

For a fixed external artifact, record and use the full digest returned for the intended image/platform rather than inventing one from a tag. Pulling new content under a tag or rebuilding `${lab}-web:lab` does not replace an already-created container. Its image was selected when it was created; replacement is a separate operation.

## Container lifetime follows the main process

A container is not a switch that permanently keeps any program alive. It runs while its main process runs. When that process finishes, the container stops; the stopped container can still be inspected.

Executable PowerShell — run the layer experiment's short command:

```powershell
# lab:exit
Invoke-LabDocker run --name "${lab}-exit" --label "io.example.docker-scenes=$lab" "${lab}-layers:lab"
$containerJson = Invoke-LabDocker container inspect "${lab}-exit"
$container = @(ConvertFrom-Json -InputObject ($containerJson -join "`n"))[0]
Write-Host "$($container.State.Status) $($container.State.ExitCode)"
```

It prints `File is absent`, then reports `exited 0`. Exit code zero means that command succeeded; it does not mean the container is still running. Starting a server in the background and letting the main shell exit has the same lifetime problem. nginx's foreground command and the API's listening Node process avoid it. Docker's `--detach` option lets the client return without staying attached to the container's output; it does not turn a short-lived command into a permanently running service.

| Operation | What it changes                                                                        |
| --------- | -------------------------------------------------------------------------------------- |
| Create    | Allocates a container from an image and configuration; does not start its main process |
| Start     | Starts that existing container's main process                                          |
| Stop      | Asks the main process to terminate, then kills it if the stop timeout expires          |
| Restart   | Stops and starts the same container; does not rebuild its image                        |
| Remove    | Deletes the container and its private writable layer; does not delete its image        |

### Build values and runtime values are different

`ARG BUILD_LABEL` makes a value available to this Dockerfile's build step. That step writes the value to `build-label.txt`, which is then copied into the serving image. The argument is not automatically a runtime environment variable. Compose will pass it with `build.args` below.

`ENV` in a Dockerfile sets environment defaults for later build steps in that stage and for containers made from that stage's image. Runtime `environment` in Compose or `docker run --env` can override container environment values without rewriting the image. The program must actually read those values for them to have an effect.

The API below reads `SERVICE_MESSAGE` from its runtime environment and returns it in `X-Service-Message`, an HTTP response header: a named value accompanying the response body. The PowerShell requests later display that header to show the runtime value changed. In contrast, putting `BROWSER_GREETING` in nginx's environment does not rewrite the literal `Hello,` in Angular's compiled template. The saved name changes because the browser explicitly fetches it from the API, not because it inherits nginx's environment. Runtime browser configuration requires an explicit response or file that the browser reads.

## Networking depends on where code runs

When the browser loads `http://127.0.0.1:8080`, the connection starts on the browser's machine. When nginx forwards that request, a new connection starts inside `web`. When the API queries PostgreSQL, another connection starts inside `api`.

```text
Browser on Windows host (Desktop forwards into its Linux VM)
  GET /                  -> 127.0.0.1:8080 -> web:80 -> static files
  execute downloaded JS
  GET or PUT /api/name    -> 127.0.0.1:8080 -> web:80
                                               |
                                      proxy to api:3000
                                               |
                                      query db:5432
                                               |
                                     named volume: dbdata
```

A **port** identifies a listening application within a network address. The browser uses the published host port; services talk to each other's container ports. The frontend calls the relative URL `/api/name`, so it uses the page's existing scheme, host, and port: the same **origin**. nginx forwards it; the browser does not need a separate cross-origin connection to the API.

A container's `localhost` normally refers to its own network environment. The API must connect to `db`, not `localhost`, because PostgreSQL is in a different container. Compose's network provides **DNS**, the name lookup that maps service names such as `api` and `db` to reachable addresses. These names belong to that network; the browser is not automatically a member and should not fetch `http://api:3000`.

`EXPOSE 80` documents an intended container port. It neither starts a listener nor publishes the port to the host. The later Compose `ports` mapping publishes `127.0.0.1:${WEB_PORT}` on the Windows host through Docker Desktop's forwarding into the Linux VM, where `web` listens on port 80. The Compose network and its service-name DNS operate inside that VM, not as Windows network interfaces. `api` and `db` need no host publication to communicate on the Compose network. With a remote daemon, a publication would be on that remote host, not on the machine running the command.

### Provide the small, real API

The API uses Node's built-in HTTP server and `pg`, the PostgreSQL client. It stores one name in one row. On startup it creates the table if absent and inserts `World` only if the row is absent; it does not reset a saved name. SQL is the database language used to define the table and read or update its rows.

File: `api/package.json`

```json
{
  "name": "api",
  "version": "1.0.0",
  "private": true,
  "type": "module",
  "dependencies": {
    "pg": "8.23.1"
  }
}
```

File: `api/server.mjs`

```javascript
import { createServer } from "node:http";
import pg from "pg";

const { Pool } = pg;
const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) {
  throw new Error("DATABASE_URL is required");
}
const pool = new Pool({
  connectionString: databaseUrl,
  connectionTimeoutMillis: 3000,
  query_timeout: 3000,
});
pool.on("error", (error) => {
  console.error("Idle database connection failed", error);
});

await pool.query(`
  CREATE TABLE IF NOT EXISTS greeting (
    id integer PRIMARY KEY CHECK (id = 1),
    name text NOT NULL
  )
`);
await pool.query("INSERT INTO greeting (id, name) VALUES (1, $1) ON CONFLICT (id) DO NOTHING", [
  "World",
]);

const serviceMessage = process.env.SERVICE_MESSAGE || "Name stored in PostgreSQL";
const server = createServer(async (request, response) => {
  response.setHeader("Content-Type", "text/plain; charset=utf-8");
  response.setHeader("Cache-Control", "no-store");
  response.setHeader("X-Service-Message", serviceMessage);
  try {
    if (request.method === "GET" && request.url === "/api/name") {
      const result = await pool.query("SELECT name FROM greeting WHERE id = 1");
      response.end(result.rows[0].name);
      return;
    }
    if (request.method === "PUT" && request.url === "/api/name") {
      const contentType = request.headers["content-type"];
      if (
        typeof contentType !== "string" ||
        contentType.split(";")[0].trim().toLowerCase() !== "text/plain"
      ) {
        response.statusCode = 415;
        response.end("Send the name as text/plain.");
        return;
      }
      const chunks = [];
      let bytes = 0;
      for await (const chunk of request) {
        bytes += chunk.length;
        if (bytes <= 1024) {
          chunks.push(chunk);
        }
      }
      if (bytes > 1024) {
        response.statusCode = 413;
        response.end("Name request is too large.");
        return;
      }
      const name = Buffer.concat(chunks).toString("utf8").trim();
      if (name.length === 0 || name.length > 80) {
        response.statusCode = 400;
        response.end("Use a name of 1 to 80 characters, not just spaces.");
        return;
      }
      const result = await pool.query("UPDATE greeting SET name = $1 WHERE id = 1 RETURNING name", [
        name,
      ]);
      response.end(result.rows[0].name);
      return;
    }
    if (request.method === "GET" && request.url === "/health") {
      await pool.query("SELECT 1");
      response.end("Ready");
      return;
    }
    response.statusCode = 404;
    response.end("Not found");
  } catch (error) {
    console.error(error);
    response.statusCode = 503;
    response.end("Database unavailable");
  }
});
server.listen(3000, "0.0.0.0");

process.on("SIGTERM", () => {
  server.close(async () => {
    await pool.end();
    process.exit(0);
  });
});
```

`GET /api/name` reads the stored name. `PUT /api/name` accepts plain text, trims surrounding whitespace, validates its length, updates the single row, and returns the saved value. `$1` keeps the name separate from SQL instructions, including when a name contains an apostrophe. The request-size check bounds retained body data; this is not a production request-timeout or abuse-control design.

`0.0.0.0` makes this server accept connections on the container's network interfaces, not just its own loopback address. The pool reuses database connections; `await` waits for each query's result. Table creation must finish before the seed insert, and both finish before the server listens. The stop signal closes the server and its pool. This is an unauthenticated learning API, not migrations or a production resilience design.

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

Unlike `web`, `api` executes JavaScript on the server and therefore needs Node at runtime.

Executable PowerShell — generate the API lockfile:

```powershell
# lab:api-lock
$apiPath = Join-Path $sandbox 'api'
Invoke-LabDocker run --rm --name "${lab}-api-lock" --label "io.example.docker-scenes=$lab" `
    --env HOME=/tmp --mount "type=bind,src=$apiPath,dst=/app" --workdir /app `
    node:24.21.0-bookworm-slim npm install --package-lock-only
```

## Mounts give data a different lifetime

Start with a file write, not a Docker option. Suppose a program writes `/tmp/note`. With no mount at that path, the new bytes belong to this container's private writable layer. Stopping and starting the same container keeps them; removing the container discards that layer. A replacement made from the same image does not inherit those private writes.

Write a note inside one container, then check whether the other can see it. Stop and start the first container, then read its note again. `docker exec` starts an additional command inside an already-running container; `cat` prints a file's contents.

Executable PowerShell — compare two independent writable layers:

```powershell
# lab:writable
Invoke-LabDocker create --name "${lab}-a" --label "io.example.docker-scenes=$lab" `
    node:24.21.0-bookworm-slim sleep 3600
Invoke-LabDocker create --name "${lab}-b" --label "io.example.docker-scenes=$lab" `
    node:24.21.0-bookworm-slim sleep 3600
Invoke-LabDocker start "${lab}-a" "${lab}-b"
Invoke-LabDocker exec "${lab}-a" sh -c 'echo private A > /tmp/note'
Invoke-LabDocker exec "${lab}-b" sh -c 'test ! -e /tmp/note'
Invoke-LabDocker stop "${lab}-a"
Invoke-LabDocker start "${lab}-a"
Invoke-LabDocker exec "${lab}-a" cat /tmp/note
```

### Make a container path lead to different storage

Now make `/shared` lead to the lab's `share` directory on Windows. When the container writes `/shared/note`, the new bytes go to `share\note` on Windows instead of its private writable layer. Removing the container does not remove that Windows file.

This attachment is a **mount**. It changes where reads and writes at a container path go. It does not copy the source directory into the image, and it is not a two-way file-copy job. A mounted path also stops using the container's private layer for ordinary writes beneath that path.

A **bind mount** uses a source path you choose. In `--mount "type=bind,src=$sharePath,dst=/shared"`, `src` names the existing Windows directory, `dst` names the absolute path programs use inside the container, and `type=bind` chooses this kind of attachment. Docker Desktop bridges that Windows path into its Linux VM. With a remote daemon, the source would instead have to exist on that remote machine.

Illustrative write destinations in this lab:

```text
Container path                    Where new bytes go
/tmp/note, with no mount           This container's private writable layer
/shared/note, with our bind        Windows lab directory: share\note
/var/lib/postgresql/data/...       Docker-managed database volume
```

The scaffold and lockfile commands already used bind mounts: files written under `/lab` or `/app` inside their short-lived Node container appeared in the Windows source directory. That is why `--rm` could remove the container without removing the generated source or lockfile.

Bind mounts are writable by default: the container can create, change, or delete files in the exposed Windows directory. Limit the mount to the intended lab directory, not the home directory, host root, or Docker socket. Adding `readonly` denies writes through that mount; it does not make the rest of the container read-only.

Executable PowerShell — observe a host write, then an expected read-only rejection:

```powershell
# lab:bind
$sharePath = Join-Path $sandbox 'share'
Invoke-LabDocker run --rm --name "${lab}-bind" --label "io.example.docker-scenes=$lab" `
    --mount "type=bind,src=$sharePath,dst=/shared" `
    node:24.21.0-bookworm-slim sh -c 'echo from container > /shared/note'
Get-Content -LiteralPath 'share\note' -Encoding UTF8

$readonlyCheck = @'
const { writeFileSync } = require('node:fs');
try {
    writeFileSync('/shared/note', 'replacement\n');
} catch (error) {
    if (error.code !== 'EROFS') {
        throw error;
    }
    console.log('Read-only mount rejected the write.');
    process.exit(0);
}
throw new Error('Unexpected write through read-only mount.');
'@
Invoke-LabDocker run --rm --name "${lab}-readonly" --label "io.example.docker-scenes=$lab" `
    --mount "type=bind,src=$sharePath,dst=/shared,readonly" `
    node:24.21.0-bookworm-slim node -e $readonlyCheck
$note = Get-Content -LiteralPath 'share\note' -Raw -Encoding UTF8
if ($note.Trim() -cne 'from container') {
    throw 'The host note changed unexpectedly.'
}
$note
```

The second write should fail with `EROFS`, the operating system's code for a read-only filesystem. The tiny Node program handles only that expected error inside the container and reports success after confirming the rejection. Any other error, or an unexpectedly successful write, throws. The host file still contains `from container`.

PowerShell's single-quoted here-string (`@'` through `'@`) holds the JavaScript literally; the program runs in the existing official Node container, so no host Node installation is needed. Handling `EROFS` is not ignoring a Docker failure: this run uses the same `Invoke-LabDocker` check as every other call, so Docker/client/removal failures still stop the lab.

### A mount covers the files at its destination

Suppose the image already has a `node` executable under `/usr/local/bin`. Mounting `share` at `/usr/local/bin` makes that path show the mounted directory's contents instead. The image's executable is **obscured**: hidden from this container at that path, not deleted from the image. The two directories are not merged.

Executable PowerShell — cover the image's Node directory with the lab's share directory:

```powershell
# lab:obscure
Invoke-LabDocker run --rm --name "${lab}-obscure" --label "io.example.docker-scenes=$lab" `
    --entrypoint /bin/sh `
    --mount "type=bind,src=$sharePath,dst=/usr/local/bin,readonly" `
    node:24.21.0-bookworm-slim `
    -c 'test ! -e /usr/local/bin/node && cat /usr/local/bin/note'
```

The image still contains Node. This container cannot see that file at the covered path. A new container without the mount sees it again.

### Keep database files in a named volume

PostgreSQL saves rows by writing database files; it does not write a convenient `name.txt` beside the Angular source. We want those database files to survive a container replacement without choosing their Windows directory ourselves.

A **named volume** is storage Docker creates and manages under a name. The upcoming `dbdata` volume is attached to PostgreSQL 17's `/var/lib/postgresql/data`. With Docker Desktop's Linux backend, these files live in Docker-managed storage inside the Linux VM, not in the Windows `share` folder. A name is how a replacement container asks Docker to attach the same storage again.

The application write has this path:

```text
Save name in browser
  -> nginx forwards PUT /api/name
  -> API updates the PostgreSQL row
  -> PostgreSQL writes database files under /var/lib/postgresql/data
  -> those writes go to the dbdata volume
```

With the named volume retained, a new `db` container reads the same database files and the same saved name. Stopping a container, removing a container, and explicitly removing a volume are different operations.

Do not infer that omitting this Compose mount puts PostgreSQL's files in its private writable layer: the official PostgreSQL 17 image already declares this data path as a volume. Docker can create an **anonymous volume**, with an automatically generated name, when no explicit mount is supplied. A replacement does not automatically find and reuse that previous anonymous volume. Naming the storage explicitly makes reuse intentional. The private-writable-layer rule applies to paths that are not mounted.

This data path is version-specific: PostgreSQL 18's official image changed its data-directory and volume layout. Do not substitute major versions without checking storage requirements and migration.

A populated volume covers underlying image files just as a bind mount does. There is one important initialization difference: Docker normally copies pre-existing files from the container's target directory into a newly mounted empty volume. It does not do that initialization copy for a bind mount. The ongoing mount still routes writes to the volume, rather than copying changes back into the image.

| Storage                  | Stop/start same container | Remove container                    | Explicitly delete storage                                              |
| ------------------------ | ------------------------- | ----------------------------------- | ---------------------------------------------------------------------- |
| Image content            | Unchanged                 | Still available as an image         | Removing the image can remove its reference; shared content may remain |
| Container writable layer | Preserved                 | Discarded                           | Removed with the container                                             |
| Bind-mounted files       | Preserved                 | Preserved on daemon host            | Host deletion removes them                                             |
| Named volume             | Preserved                 | Preserved unless explicitly removed | Volume removal discards its data                                       |

Removing this named volume deliberately deletes the saved database files; removing a container alone is not the same operation. Persistence is not a backup: host/VM storage loss or volume deletion can still lose the saved name.

## Compose describes collaborating services

Save the following file in the lab root. It describes three services, their inputs, one network, and one named volume. Compose translates it into individual Docker resources; it is not one large container or a new image format.

File: `compose.yaml`

```yaml
services:
  web:
    image: "${COMPOSE_PROJECT_NAME}-web:lab"
    build:
      context: ./web
      args:
        BUILD_LABEL: "${BUILD_LABEL}"
      labels:
        io.example.docker-scenes: "${COMPOSE_PROJECT_NAME}"
    labels:
      io.example.docker-scenes: "${COMPOSE_PROJECT_NAME}"
    ports:
      - "127.0.0.1:${WEB_PORT}:80"
    environment:
      BROWSER_GREETING: "${BROWSER_GREETING}"
    depends_on:
      api:
        condition: service_healthy
  api:
    image: "${COMPOSE_PROJECT_NAME}-api:lab"
    build:
      context: ./api
      labels:
        io.example.docker-scenes: "${COMPOSE_PROJECT_NAME}"
    labels:
      io.example.docker-scenes: "${COMPOSE_PROJECT_NAME}"
    environment:
      DATABASE_URL: "postgres://demo:demo-only-password@db:5432/greetings"
      SERVICE_MESSAGE: "${SERVICE_MESSAGE}"
    depends_on:
      db:
        condition: service_healthy
    healthcheck:
      test:
        [
          "CMD",
          "node",
          "-e",
          "fetch('http://127.0.0.1:3000/health').then(r => { if (!r.ok) { process.exit(1); } }).catch(() => process.exit(1))",
        ]
      interval: 2s
      timeout: 5s
      retries: 15
      start_period: 5s
  db:
    image: postgres:17.11-bookworm
    labels:
      io.example.docker-scenes: "${COMPOSE_PROJECT_NAME}"
    environment:
      POSTGRES_USER: demo
      POSTGRES_PASSWORD: demo-only-password
      POSTGRES_DB: greetings
    volumes:
      - dbdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -h 127.0.0.1 -U demo -d greetings"]
      interval: 2s
      timeout: 5s
      retries: 15
      start_period: 5s
volumes:
  dbdata:
    name: "${COMPOSE_PROJECT_NAME}-dbdata"
    labels:
      io.example.docker-scenes: "${COMPOSE_PROJECT_NAME}"
networks:
  default:
    name: "${COMPOSE_PROJECT_NAME}-default"
    labels:
      io.example.docker-scenes: "${COMPOSE_PROJECT_NAME}"
```

`build` tells Compose how to produce `web` and `api`; `image` gives those outputs names. `db` uses an existing registry image without a local build. The default network connects the services and gives them their service-name DNS entries. The unique project name separates this set from other Compose apps.

The password is a **public, non-production demo value**. The PostgreSQL image initializes the named database/user when its data directory is empty; changing those environment values later does not automatically change an existing database's password or contents. This example uses its initial superuser for convenience, has no authentication for the API, and is not an internet-facing deployment configuration. Do not replace demo values with real secrets in files sent to a builder.

### Started is not necessarily ready

A running database process may still be initializing. Simple startup order only establishes which container starts first. A **health check** periodically runs a command and records whether it succeeds. `service_healthy` tells Compose to wait for that dependency's health check before starting the dependent service.

The database check asks whether PostgreSQL accepts TCP connections. The API's startup actually creates/queries the table; its `/health` endpoint additionally executes `SELECT 1`. nginx starts after that API check passes. These are bounded startup checks, not promises that dependencies will never fail later. Compose does not automatically repair every later outage or restart dependents merely because a health status changes.

After building, list the existing container, network, and volume names again: another program could have created one of the lab's names during the build. Refuse existing exact matches before starting the services, independently of their labels.

Executable PowerShell — build, start, and wait with a timeout:

```powershell
# lab:up
Invoke-LabDocker compose --progress=plain -f compose.yaml build
$containerNames = @(Invoke-LabDocker container ls --all --format '{{.Names}}')
foreach ($name in @('web-1', 'api-1', 'db-1')) {
    if ($containerNames -ccontains "${lab}-$name") {
        throw "Container name appeared during the build: ${lab}-$name"
    }
}
$networkNames = @(Invoke-LabDocker network ls --format '{{.Name}}')
$volumeNames = @(Invoke-LabDocker volume ls --format '{{.Name}}')
if ($networkNames -ccontains "${lab}-default") {
    throw 'The declared network name already exists.'
}
if ($volumeNames -ccontains "${lab}-dbdata") {
    throw 'The declared volume name already exists.'
}
Invoke-LabDocker compose -f compose.yaml up --detach --wait --wait-timeout 120
Invoke-LabDocker compose -f compose.yaml ps
$baseUrl = "http://127.0.0.1:$($env:WEB_PORT)"
$nameResponse = Invoke-WebRequest -UseBasicParsing -Uri "$baseUrl/api/name" -TimeoutSec 15
$nameResponse.Content
$nameResponse.Headers['X-Service-Message']
(Invoke-WebRequest -UseBasicParsing -Uri "$baseUrl/build-label.txt" -TimeoutSec 15).Content
```

Open `http://127.0.0.1:8080` in a browser, adjusting the port if needed. The initial greeting is `Hello, World!`. Enter a name and choose **Save**; the greeting changes after the database update succeeds. Refresh the page to read the saved name again. In the browser's Network panel, GET and PUT `/api/name` use this same host/port, not the Docker service name `api`. The command-line name request returns plain text; `build-label.txt` contains the build argument's recorded value.

### Replace containers without replacing the data

Executable PowerShell — save a name through the API, remove this project's containers, and recreate them:

```powershell
# lab:persistence
$saveResponse = Invoke-WebRequest -UseBasicParsing -Uri "$baseUrl/api/name" -Method Put `
    -ContentType 'text/plain; charset=utf-8' -Body 'theo' -TimeoutSec 15
$saveResponse.Content
(Invoke-WebRequest -UseBasicParsing -Uri "$baseUrl/api/name" -TimeoutSec 15).Content

# Check the exact named resources and both ownership labels before down.
if ((Get-Location).Path -cne $sandbox -or $env:COMPOSE_PROJECT_NAME -cne $lab) {
    throw 'The lab directory or project name changed.'
}
if ((Get-Content -LiteralPath '.lab-owner' -Raw -Encoding UTF8).Trim() -cne $lab) {
    throw 'The lab owner file changed.'
}
foreach ($kind in @('network', 'volume')) {
    $expectedName = "${lab}-default"
    if ($kind -ceq 'volume') {
        $expectedName = "${lab}-dbdata"
    }
    $resourceJson = Invoke-LabDocker $kind inspect $expectedName
    $resource = @(ConvertFrom-Json -InputObject ($resourceJson -join "`n"))[0]
    if ($resource.Name -cne $expectedName -or
        $resource.Labels.'io.example.docker-scenes' -cne $lab -or
        $resource.Labels.'com.docker.compose.project' -cne $lab) {
        throw 'The declared resource name or ownership labels changed.'
    }
}
$projectIds = @(Invoke-LabDocker ps -aq --filter "label=com.docker.compose.project=$lab")
foreach ($id in $projectIds) {
    $containerJson = Invoke-LabDocker container inspect $id
    $container = @(ConvertFrom-Json -InputObject ($containerJson -join "`n"))[0]
    if (@("/${lab}-web-1", "/${lab}-api-1", "/${lab}-db-1") -cnotcontains $container.Name -or
        $container.Config.Labels.'io.example.docker-scenes' -cne $lab -or
        $container.Config.Labels.'com.docker.compose.project' -cne $lab) {
        throw 'Unexpected project container. Stop and inspect.'
    }
}
Invoke-LabDocker compose -f compose.yaml down --timeout 10
$volumeJson = Invoke-LabDocker volume inspect "${lab}-dbdata"
$volume = @(ConvertFrom-Json -InputObject ($volumeJson -join "`n"))[0]
$volume.Name
$networkNames = @(Invoke-LabDocker network ls --format '{{.Name}}')
if ($networkNames -ccontains "${lab}-default") {
    throw 'The network name still exists after down. Stop and inspect.'
}
Invoke-LabDocker compose -f compose.yaml up --detach --no-build --wait --wait-timeout 120
(Invoke-WebRequest -UseBasicParsing -Uri "$baseUrl/api/name" -TimeoutSec 15).Content
```

`down` removes the project's service containers and network, but keeps the named volume unless volume removal is requested. `up` creates replacements that attach it again. The name request should still return `theo`; refreshing the page should show `Hello, theo!`. The startup seed cannot explain that value: it inserts `World` only when the row is absent. The saved value comes from the retained database files.

Editing source and restarting a container are also different. Build a new image to include source changes, then let `docker compose up` replace containers whose image/configuration changed. A runtime environment change likewise needs recreation; `restart` uses the existing container's configuration. A static upstream address can become stale after API replacement, so recreate or restart `web` as well; bringing the whole lab down/up here avoids that issue.

Executable PowerShell — contrast explicit API runtime configuration with unchanged static files:

```powershell
# lab:configuration
$env:SERVICE_MESSAGE = 'A new API runtime message'
$env:BROWSER_GREETING = 'This still does not rewrite the browser bundle'
$projectIds = @(Invoke-LabDocker ps -aq --filter "label=com.docker.compose.project=$lab")
if ($env:COMPOSE_PROJECT_NAME -cne $lab -or (Get-Location).Path -cne $sandbox) {
    throw 'The lab directory or project name changed.'
}
foreach ($id in $projectIds) {
    $containerJson = Invoke-LabDocker container inspect $id
    $container = @(ConvertFrom-Json -InputObject ($containerJson -join "`n"))[0]
    if (@("/${lab}-web-1", "/${lab}-api-1", "/${lab}-db-1") -cnotcontains $container.Name -or
        $container.Config.Labels.'io.example.docker-scenes' -cne $lab -or
        $container.Config.Labels.'com.docker.compose.project' -cne $lab) {
        throw 'Unexpected project container. Stop and inspect.'
    }
}
Invoke-LabDocker compose -f compose.yaml up --detach --no-build --force-recreate `
    --wait --wait-timeout 120
$nameResponse = Invoke-WebRequest -UseBasicParsing -Uri "$baseUrl/api/name" -TimeoutSec 15
$nameResponse.Content
$nameResponse.Headers['X-Service-Message']
(Invoke-WebRequest -UseBasicParsing -Uri "$baseUrl/build-label.txt" -TimeoutSec 15).Content
```

The response header now carries the API's new runtime message; the saved name stays `theo`. The browser's greeting still starts with the literal `Hello,` because changing nginx's environment does not rewrite the compiled Angular template. The name can change through an explicit API save, which is a different mechanism. `build-label.txt` keeps its build-time value because no new image was built; changing `$env:BUILD_LABEL` alone would not rewrite that file either.

### Clean up only this lab

The next block is **destructive**: it deletes this lab's database volume and private container files. Run it only with the original PowerShell window, lab directory, and ownership labels intact. It checks the exact declared network and volume names as well as project-labelled resources before removal. It does not prune global caches or remove official base images. The Windows temporary directory and local lab image tags are left for inspection; do not reuse this lab for a second run.

There is still a gap between checking a resource and Docker using it: another program can change resources during that gap. These checks do not lock resources, and another actor can copy labels. If the expected names or labels no longer match, stop and inspect rather than changing the cleanup targets. After a partial failure, there may be resources outside the complete run's expected set, including a short-lived container whose removal failed. Stop and inspect those manually; do not broaden deletion to whatever carries a lab label.

Executable PowerShell — checked, project-scoped teardown:

```powershell
# lab:cleanup
if ((Get-Location).Path -cne $sandbox -or $env:COMPOSE_PROJECT_NAME -cne $lab) {
    throw 'The lab directory or project name changed.'
}
if ((Get-Content -LiteralPath '.lab-owner' -Raw -Encoding UTF8).Trim() -cne $lab) {
    throw 'The lab owner file changed.'
}
# Inspect declared names directly, even if label-filtered lists omit them.
foreach ($kind in @('network', 'volume')) {
    $expectedName = "${lab}-default"
    if ($kind -ceq 'volume') {
        $expectedName = "${lab}-dbdata"
    }
    $resourceJson = Invoke-LabDocker $kind inspect $expectedName
    $resource = @(ConvertFrom-Json -InputObject ($resourceJson -join "`n"))[0]
    if ($resource.Name -cne $expectedName -or
        $resource.Labels.'io.example.docker-scenes' -cne $lab -or
        $resource.Labels.'com.docker.compose.project' -cne $lab) {
        throw 'The declared resource name or ownership labels changed.'
    }
}
$projectIds = @(Invoke-LabDocker ps -aq --filter "label=com.docker.compose.project=$lab")
foreach ($id in $projectIds) {
    $containerJson = Invoke-LabDocker container inspect $id
    $container = @(ConvertFrom-Json -InputObject ($containerJson -join "`n"))[0]
    if (@("/${lab}-web-1", "/${lab}-api-1", "/${lab}-db-1") -cnotcontains $container.Name -or
        $container.Config.Labels.'io.example.docker-scenes' -cne $lab -or
        $container.Config.Labels.'com.docker.compose.project' -cne $lab) {
        throw 'Unexpected project container. Stop and inspect.'
    }
}
foreach ($kind in @('network', 'volume')) {
    $resourceIds = @(Invoke-LabDocker $kind ls -q --filter "label=com.docker.compose.project=$lab")
    foreach ($id in $resourceIds) {
        $resourceJson = Invoke-LabDocker $kind inspect $id
        $resource = @(ConvertFrom-Json -InputObject ($resourceJson -join "`n"))[0]
        $expectedName = "${lab}-default"
        if ($kind -ceq 'volume') {
            $expectedName = "${lab}-dbdata"
        }
        if ($resource.Name -cne $expectedName -or
            $resource.Labels.'io.example.docker-scenes' -cne $lab -or
            $resource.Labels.'com.docker.compose.project' -cne $lab) {
            throw 'Unexpected project network or volume. Stop and inspect.'
        }
    }
}
foreach ($name in @('exit', 'a', 'b')) {
    $containerJson = Invoke-LabDocker container inspect "${lab}-$name"
    $container = @(ConvertFrom-Json -InputObject ($containerJson -join "`n"))[0]
    if ($container.Name -cne "/${lab}-$name" -or
        $container.Config.Labels.'io.example.docker-scenes' -cne $lab) {
        throw 'An experiment container name or ownership label changed.'
    }
}
Invoke-LabDocker compose -f compose.yaml down --volumes --timeout 10
Invoke-LabDocker stop "${lab}-a" "${lab}-b"
Invoke-LabDocker rm "${lab}-exit" "${lab}-a" "${lab}-b"
```

Return to the three mysteries: the short command exits because its main process finishes; the deleted file's earlier layer still has bytes; and `localhost` changes meaning with the process making the connection.

A final check: building produces an image, restarting starts the same container again, removing discards its writable layer, and keeping the named volume preserves the database rows. Trace each request and write to its actual browser, process, network, and filesystem before choosing a Docker command.

## Sources and further reading

- [Docker: build contexts and `.dockerignore`](https://docs.docker.com/build/concepts/context/)
- [Docker: Dockerfile instructions](https://docs.docker.com/reference/dockerfile/)
- [Docker: build-cache invalidation](https://docs.docker.com/build/cache/invalidation/)
- [Docker: multi-stage builds](https://docs.docker.com/build/building/multi-stage/)
- [Docker Compose: networking](https://docs.docker.com/compose/how-tos/networking/)
- [Docker Compose: startup order and readiness](https://docs.docker.com/compose/how-tos/startup-order/)
- [Docker: bind mounts](https://docs.docker.com/engine/storage/bind-mounts/)
- [Docker: volumes](https://docs.docker.com/engine/storage/volumes/)
