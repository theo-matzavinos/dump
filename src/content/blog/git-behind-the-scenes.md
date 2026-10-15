---
title: "Git behind the scenes: objects, snapshots, and moving pointers"
description: "Build a throwaway repository with two task-app files and watch which Git commands save new snapshots and which ones only move names: staging, branching, merging, rebasing, syncing, and undo."
pubDate: "2026-10-08"
updatedDate: "2026-10-15"
tags:
  - git
  - tooling
  - fundamentals
---

Stage a file, edit it once more, and run `git status`: Git now lists that same file twice, once with staged changes and once with changes that aren't staged. It's holding two versions of the file at the same time. That looks like a glitch, but it falls straight out of how Git stores your work. The same design explains why creating a branch is instant even in a huge repository, and why rebasing onto a different base can give your commits new IDs even when the code looks identical.

Git saves snapshots that never change, and it keeps names, such as branches, that point at those snapshots. Almost every command either saves something new or moves a name. This article builds a tiny throwaway repository with two task-app files and watches both happen, one command at a time.

You'll need Git and a Bash-compatible terminal: Bash on Linux or macOS, or Git Bash on Windows. The outputs shown come from Git 2.55. There's no app to build or server to start.

## Contents

1. [Git and hosting services](#git-and-hosting-services)
2. [Create a throwaway repository](#create-a-throwaway-repository)
3. [The objects Git stores](#the-objects-git-stores)
4. [Commits link snapshots into history](#commits-link-snapshots-into-history)
5. [The working tree, the index, and HEAD](#the-working-tree-the-index-and-head)
6. [Branches and tags](#branches-and-tags)
7. [Merging](#merging)
8. [Cherry-pick, rebase, and squash](#cherry-pick-rebase-and-squash)
9. [Remotes, fetch, pull, and push](#remotes-fetch-pull-and-push)
10. [Rejected pushes and shared history](#rejected-pushes-and-shared-history)
11. [Undoing changes](#undoing-changes)
12. [Predicting what a command will do](#predicting-what-a-command-will-do)

## Git and hosting services

Editing a file changes that file on disk. Git can also record versions of chosen files in its own storage. That storage, with its saved history and the names that point into it, is a **repository**, or "repo" for short.

In an ordinary repository, the files you edit sit next to a hidden `.git` directory that holds Git's storage. Everything in this article runs against that directory, so creating commits, reading history, and making branches all work without a network connection.

GitHub and similar services host repositories and add features such as code review and access control, but Git doesn't need them. A **remote** is simply another repository yours can exchange data with. It can live on another machine or in another folder on the same machine, which is how the remote examples later work without an account anywhere.

## Create a throwaway repository

Run these examples only in the new directory created below, never in a repository with work you want to keep: later steps deliberately throw away changes and rewrite branches.

Run the shell blocks in order in one terminal. A few are supposed to fail; those are marked **Expected failure**, so keep going with the next block. If anything else errors, stop and check what went wrong. Blocks shown as plain text are diagrams or editor content, not commands.

Each commit message starts with a letter, like `A: Start task app`, so you can match it to the diagrams.

```bash
sandbox=$(mktemp -d "${TMPDIR:-/tmp}/git-scenes.XXXXXX")
cd "$sandbox"
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CEILING_DIRECTORIES="$sandbox"
export GIT_AUTHOR_NAME="Git Example"
export GIT_AUTHOR_EMAIL="git-example@example.invalid"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"

git init --template= -b main task-app
cd task-app
git config gc.auto 0
git config maintenance.auto false

cat > tasks.txt <<'EOF'
Read Git
EOF
cat > app.js <<'EOF'
const heading = "Tasks";
EOF

git add tasks.txt app.js
git commit -m "A: Start task app"
git tag start
pwd
git status --short
```

The first two lines create a new empty folder with a unique name, remember its path in the `sandbox` variable, and move into it. The `export` lines make this one terminal ignore your personal Git settings and use a made-up name and email for commits, so the experiment can't touch your real configuration. Close the terminal when you're done and those settings disappear.

`git init` creates the repository. `--template=` skips copying Git's starter files, such as sample hook scripts, and the two `git config` lines turn off Git's automatic cleanup so nothing gets tidied away in the middle of the experiment.

The lines between each `<<'EOF'` and `EOF` are the literal file contents. `>` writes a file, replacing what was there; `>>`, used later, appends to it.

`git add` copies each file's current content into the **index**, Git's list of what goes into the next commit. A file listed in the index is **tracked**. A file that only exists on disk and was never added is untracked, and Git leaves it out of commits. `git commit` then saves what the index holds, and `-m` supplies the message without opening an editor.

`git tag start` gives this first commit a name that stays put, so later examples can start from it. The empty `git status --short` output means the index, the files on disk, and the commit all agree, and there's no untracked file to report.

## The objects Git stores

Git keeps everything as **objects**, and there are four kinds:

| Object        | What it records                                                                 |
| ------------- | ------------------------------------------------------------------------------- |
| Blob          | The content of one file, without its filename                                   |
| Tree          | A directory listing: names, file modes, and the IDs of blobs or child trees     |
| Commit        | The ID of a root tree, the IDs of parent commits, author, committer, and message |
| Annotated tag | The ID of a target object, a tag name, the tagger, a message, and optionally a signature |

The author is who originally wrote a change; the committer is who recorded this commit. Their names, emails, and times are **metadata**: information about the commit rather than file content. A commit's **root tree** describes the top-level folder of its snapshot, and subfolders appear in it as child trees.

Every object has an **object ID**, calculated by running the object's type, size, and content through a hash function: a calculation that turns any bytes into a fixed-length fingerprint. That's called **content-addressed storage**. Git finds objects by an ID made from their data, rather than by a version number.

Two things follow. Identical content always gets the same ID, so a file that doesn't change is stored once and reused by every snapshot that contains it. And changing anything, whether a file, a tree entry, a parent, or a message, produces a different ID, so Git never edits an existing object; it writes a new one. Your IDs won't match anyone else's, because commits include your timestamps, so the examples always ask Git to look up names instead of pasting IDs.

### Inspect the objects

```bash
git cat-file -t HEAD
git cat-file -p HEAD
git cat-file -p 'HEAD^{tree}'
git cat-file -t HEAD:tasks.txt
git cat-file -p HEAD:tasks.txt
```

`HEAD` means "the commit you're on right now". You'll see later that it usually points at a branch name, which in turn points at a commit. `-t` prints an object's type and `-p` prints its contents in readable form. `HEAD^{tree}` asks for that commit's root tree, and `HEAD:tasks.txt` asks for the object stored at that path in its snapshot.

Read the output from the outside in:

1. Commit A has a `tree` line, `author` and `committer` lines, and the message. It's the first commit, so it has no `parent` line.
2. The tree lists `app.js` and `tasks.txt`, each with a mode, the word `blob`, and an object ID. `100644` means an ordinary file that isn't executable.
3. The blob contains `Read Git` and a newline. The name `tasks.txt` isn't in it; the tree supplied that name.

```text
commit A --> root tree T
             |-- app.js    --> blob J: const heading = "Tasks";
             `-- tasks.txt --> blob K: Read Git
```

A snapshot only covers tracked files. Git records whether each file is executable, but it doesn't store owners, permissions beyond that, or file timestamps.

Following commit → tree → blob gives you the files as they were, but it doesn't mean every commit stores a full copy of every file on disk: Git reuses unchanged objects and compresses the rest into [packfiles](https://git-scm.com/docs/gitformat-pack), so 100 commits don't take 100 copies' worth of space.

## Commits link snapshots into history

A normal commit points to the commit before it, its **parent**. A merge commit can have several parents. Following parent links from commit to commit gives you the history graph.

The links only point backward, toward older commits, and never loop back around. That kind of graph is called a **directed acyclic graph**, or DAG. Ancestry comes from these parent links, not from commit timestamps.

Two different commits can point to exactly the same root tree. This block records a second commit on purpose without changing any file:

```bash
git commit --allow-empty -m "B: Record a checkpoint"
git rev-parse 'start^{tree}' 'HEAD^{tree}'
git rev-parse start HEAD
git cat-file -p HEAD
```

`rev-parse` turns names into object IDs, and `--allow-empty` permits a commit with no changes. The two tree IDs are equal, but the commit IDs differ: B has a different message and records A as its parent.

```text
A -- B  (main)
|    |
T    T  (same root tree)
```

So "the files look the same" doesn't mean "these are the same commits". Keep that in mind for rebase later.

## The working tree, the index, and HEAD

When you prepare a change, Git keeps three versions of your files apart:

- **Working tree:** the files on disk that you edit.
- **Index**, also called the **staging area:** the list of file contents that will go into the next commit.
- **HEAD commit:** the snapshot you last committed or checked out.

`git add` copies a file's content into the index at that moment. Editing the file afterward doesn't update the index, and that's exactly the opening's double-listed file. This block stages one version of `tasks.txt` and then edits it again:

```bash
printf 'Read Git\nTry staging\n' > tasks.txt
git add tasks.txt
printf 'Read Git\nTry staging\nNot staged yet\n' > tasks.txt

git status --short
git diff -- tasks.txt
git diff --cached -- tasks.txt
git ls-files --stage
git cat-file -p :tasks.txt
```

`git status --short` shows `MM tasks.txt`. The first `M` says the index differs from HEAD; the second says the working tree differs from the index.

The two diffs answer different questions:

| Comparison           | Command             | Change shown here     |
| -------------------- | ------------------- | --------------------- |
| Index → working tree | `git diff`          | Adds `Not staged yet` |
| HEAD → index         | `git diff --cached` | Adds `Try staging`    |

`--` separates options from file paths. `ls-files --stage` lists the index entries, and `:tasks.txt` selects the blob the index holds for that path, which ends at `Try staging`.

```text
HEAD:          Read Git
Index:         Read Git / Try staging
Working tree:  Read Git / Try staging / Not staged yet
```

Now commit only what's staged, then throw away the leftover edit:

```bash
git commit -m "C: Add staging exercise"
git cat-file -p HEAD:tasks.txt
git diff -- tasks.txt
git restore -- tasks.txt
git status --short
```

Commit C records the index, so `Not staged yet` is still an unstaged change afterward. `git restore -- tasks.txt` copies the index version back over the working file, which discards that line without creating a commit. The repository is clean again. (`git commit -a` and similar shortcuts stage files for you; these examples avoid them so the three versions stay visible. See [git-add](https://git-scm.com/docs/git-add).)

## Branches and tags

A branch is a name that points at one commit, its **tip**. Creating a branch doesn't copy any files or history; it just writes down a new name for an existing commit. That's why it's instant in any repository size. When you commit while on a branch, Git moves that branch's name to the new commit.

These names are **references**, or **refs**. The full name of the local branch `main` is `refs/heads/main`. `HEAD` normally points at a branch name, and the branch name points at a commit.

This block creates names without changing files or switching branches:

```bash
git branch experiment
git tag checkpoint
git tag -a v0-demo -m "Demonstration snapshot"
git symbolic-ref HEAD
git rev-parse main experiment checkpoint
git cat-file -t checkpoint
git cat-file -t v0-demo
git cat-file -p v0-demo
```

`main`, `experiment`, and `checkpoint` all resolve to C. `git branch experiment` didn't switch to the new branch, and `symbolic-ref HEAD` prints `refs/heads/main`.

The lightweight tag `checkpoint` points directly at the commit. The annotated tag `v0-demo` points at a separate tag object, which points at the commit and carries the message. Tags are meant to stay put: when you commit, your branch moves forward but tags stay on the old commit. You can force-move a tag, but it's rare and confuses anyone who already fetched it. See [git-tag](https://git-scm.com/docs/git-tag).

```text
HEAD --> main ----------> commit C --> tree
         experiment ----> commit C
         checkpoint ----> commit C
         v0-demo --> tag object -----> commit C
```

### Detached HEAD

You can check out a commit without choosing a branch. `HEAD` then points straight at a commit, which Git calls a **detached HEAD**. Committing still works, but only `HEAD` moves forward; no branch follows along.

```bash
git switch --detach start
git commit --allow-empty -m "D: Detached experiment"
detached_commit=$(git rev-parse HEAD)
git branch detached-work
git switch main
```

`git branch detached-work` names commit D before you leave it. Without a name, D is still stored, but nothing you'd normally look at leads to it anymore. The shell variable `detached_commit` saves D's ID so the [undo section](#undoing-changes) can delete the name and find D again.

## Merging

The next examples all start new branches from the `start` tag, so the `main` history above stays as it is. Lots of names appear from here on, so here's the cast to scroll back to:

| Branch               | Points at   | What it holds                                                   |
| -------------------- | ----------- | --------------------------------------------------------------- |
| `start` (a tag)      | A           | The first snapshot                                              |
| `ff-main`            | F           | Moved forward to `ff-feature`'s commit                          |
| `ff-feature`         | F           | A heading change                                                |
| `feature`            | Q, later Q′ | Two task-list commits, P then Q                                 |
| `feature-original`   | Q           | The feature tip before rebasing, kept for comparison            |
| `heading`            | R           | A different heading change, on its own                          |
| `integration`        | M           | The merge of `feature` and `heading`                            |
| `conflict-main`      | H, later MC | One rewording of the first task, then the conflict resolution   |
| `conflict-target`    | H           | That same rewording, kept for the rebase conflict               |
| `conflict-feature`   | I           | A different rewording of the same line                          |
| `picked`             | P′          | Only P's change, copied on top of R                             |
| `replay-conflict`    | I           | A copy of `conflict-feature` used for a rebase that's abandoned |
| `squashed`           | S           | P and Q combined into one commit                                |
| `squash-integration` | SM          | The feature's result added on top of R as one commit            |

### Fast-forward

```bash
git switch -c ff-main start
git switch -c ff-feature
printf 'const heading = "Task list";\n' > app.js
git add app.js
git commit -m "F: Clarify heading"
git switch ff-main
git merge --ff-only ff-feature
git log --graph --oneline --decorate -3
```

Before the merge, `ff-main` points at A, and A is F's parent. There's no separate line of work to combine, so the merge just moves `ff-main` forward to F and updates the index and working files. No new commit is created. Moving a branch forward like this is a **fast-forward**.

```text
Before: A (ff-main) -- F (ff-feature)
After:  A ----------- F (ff-main, ff-feature)
```

`--ff-only` tells Git to fast-forward or refuse. In `git log`, `--graph` draws the parent links, `--oneline` shortens each entry, and `--decorate` shows which names point where.

### Two branches that both changed

Now both branches get their own changes after A. The task branch adds P and then Q. The heading branch adds R. The combined result will be M.

```bash
git switch -c feature start
printf 'Read Git\nMark a task done\n' > tasks.txt
git add tasks.txt
git commit -m "P: Add completion task"
printf 'Review history\n' >> tasks.txt
git add tasks.txt
git commit -m "Q: Add review task"
git branch feature-original

git switch -c integration start
printf 'const heading = "Task list";\n' > app.js
git add app.js
git commit -m "R: Use clearer heading"
git branch heading

git merge-base integration feature
git diff start heading -- app.js tasks.txt
git diff start feature-original -- app.js tasks.txt
git merge -m "M: Merge task list and heading" feature
git cat-file -p HEAD
git cat-file -p HEAD:tasks.txt
git cat-file -p HEAD:app.js
```

`feature-original` and `heading` are extra names that keep Q and R easy to reach after `feature` and `integration` move on.

Just before the merge, Git compares three snapshots:

| Snapshot                      | Name                                          | `app.js`                       | `tasks.txt`                                              |
| ----------------------------- | --------------------------------------------- | ------------------------------ | -------------------------------------------------------- |
| A, the shared starting point  | `start`                                       | `const heading = "Tasks";`     | `Read Git`                                               |
| R, the current branch's tip   | `heading` (and `integration` before merging)  | `const heading = "Task list";` | `Read Git`                                               |
| Q, the other branch's tip     | `feature-original` (and `feature`)            | `const heading = "Tasks";`     | `Read Git`<br />`Mark a task done`<br />`Review history` |

The first `git diff` compares A with R: only `app.js` changes. The second compares A with Q: only `tasks.txt` changes, gaining two lines. Q's snapshot already includes P's line, because Q was built on P.

Git combines these file states step by step:

1. For `app.js`, Q matches A and R changed it, so the result takes R's `const heading = "Task list";`.
2. For `tasks.txt`, R matches A and Q changed it, so the result takes Q's three-line list.
3. Git saves those two files as M's root tree, updates the index and working files to match, and moves `integration` to M.

The shared starting point is the **merge base**, and `git merge-base` prints A's ID. Each file here changed on only one side, so Git combined them automatically. Edits to different parts of the same file usually combine cleanly too.

M has two parents, R first and Q second, and `cat-file` shows them in that order. A was only the comparison point; it's already an ancestor of both.

```text
A --> P --> Q (feature, feature-original)
|           |
v           v
R --------> M (integration)
(heading)
```

This is a **three-way merge**: one base, A, and two tips, R and Q. Git doesn't replay P and then Q on top of R. It compares the final snapshots, and the original P and Q stay in history through M's second parent. See [git-merge: true merge](https://git-scm.com/docs/git-merge#_true_merge).

### Merge conflicts

This time both branches replace A's `Read Git` line, each in a different way, so Git can't pick one for you.

```bash
git switch -c conflict-main start
printf 'Read Git carefully\n' > tasks.txt
git add tasks.txt
git commit -m "H: Emphasize careful reading"
git branch conflict-target

git switch -c conflict-feature start
printf 'Read Git objects\n' > tasks.txt
git add tasks.txt
git commit -m "I: Focus on objects"
git switch conflict-main
```

**Expected failure:** a content conflict in `tasks.txt`.

```bash
git merge conflict-feature
```

Git stops without making a merge commit. `conflict-main` still points at H and `conflict-feature` at I. Look at what's in the file and the index now:

```bash
cat tasks.txt
git status --short
git ls-files --unmerged
git show :1:tasks.txt
git show :2:tasks.txt
git show :3:tasks.txt
```

The working file contains conflict markers:

```text
<<<<<<< HEAD
Read Git carefully
=======
Read Git objects
>>>>>>> conflict-feature
```

The part between `<<<<<<< HEAD` and `=======` is your current branch's version; the part after it, down to `>>>>>>> conflict-feature`, is the branch you're merging in. `git status --short` shows `UU`: unmerged on both sides.

Meanwhile the index holds three numbered versions of the file instead of the usual single entry (which is stage 0):

- Stage 1 is the merge base, A: `Read Git`.
- Stage 2 is **"ours"**, the branch you're on: H's `Read Git carefully`.
- Stage 3 is **"theirs"**, the branch being merged in: I's `Read Git objects`.

Commands such as `git checkout --ours` and `git checkout --theirs` use those names. To resolve the conflict, write the result you actually want, stage it, and commit:

```bash
printf 'Read Git objects carefully\n' > tasks.txt
git add tasks.txt
git commit -m "MC: Combine reading instructions"
git cat-file -p HEAD
```

`git add` replaces the three numbered entries with your chosen content, and the commit records MC with parents H and I. Git only knows that you marked the file resolved; checking that the combined result actually works, by running the app or its tests, is still up to you.

## Cherry-pick, rebase, and squash

A merge keeps both histories connected through parent links. The commands in this section reuse changes but record different parents, so they produce new commits.

### Cherry-pick

A commit stores a snapshot, but comparing it with its parent gives you the change it introduced. A **cherry-pick** takes that change and applies it on top of the commit you're on.

```bash
git switch -c picked heading
git cherry-pick feature-original~1
git rev-parse 'feature-original~1' HEAD
git cat-file -p HEAD
git cat-file -p HEAD:tasks.txt
git cat-file -p HEAD:app.js
```

`~1` means "one parent back", so `feature-original~1` is P. The cherry-pick creates a new commit whose parent is R. Its snapshot has R's clearer heading and P's completion task, but not Q's review task.

The original P is untouched. The new commit gets a different ID because its parent and its tree differ, and the diagrams label it P′ (P prime). Its message still starts with `P:`, because cherry-pick keeps the original message. See [git-cherry-pick](https://git-scm.com/docs/git-cherry-pick).

### Rebase

A **rebase** does the same thing for a series of commits and then moves the branch. Rebasing `feature` onto `heading` applies P's change after R, then Q's change after that, and moves `feature` to the last new commit.

```bash
git switch feature
git rebase heading
git rev-parse feature-original feature
git log --graph --oneline --decorate feature feature-original heading
git cat-file -p HEAD
git cat-file -p HEAD:tasks.txt
git cat-file -p HEAD:app.js
```

```text
Before:
A --> P --> Q (feature, feature-original)
|
v
R (heading)

After:
A --> P --> Q (feature-original)
|
v
R (heading) --> P′ --> Q′ (feature)
```

P′ has R as its parent and Q′ has P′, so both get new IDs, though their messages stay the same. If you paste these blocks quickly, P′ may have the same ID as the earlier cherry-pick, so the log also labels it `picked`: both operations produced identical commit data, including the timestamp. The final snapshot has both task changes and the heading change. P and Q still exist unchanged; `feature-original` keeps them visible. That's the opening's third puzzle: a rebase gives commits new IDs because it writes new commits with new parents, while the old ones stay where they were. (If a commit's change is already on the new base, rebase skips it instead of copying it. See [git-rebase](https://git-scm.com/docs/git-rebase).)

A rebase can conflict too. A change that made sense after A may not apply after another commit rewrote the same line. This block makes a throwaway copy of the conflicting branch:

```bash
git switch -c replay-conflict conflict-feature
```

**Expected failure:** replaying I on top of H, which rewrote the same line.

```bash
git rebase conflict-target
```

Git stops partway, with the same kind of markers in `tasks.txt`. This time, look at which side is which:

```bash
git show :2:tasks.txt
git show :3:tasks.txt
git status --short
git rebase --abort
git rev-parse replay-conflict conflict-feature
git status --short
```

Stage 2, "ours", is now H's `Read Git carefully`, and stage 3, "theirs", is I's `Read Git objects`. During a rebase, ours and theirs flip compared with a merge: "ours" is the branch you're rebasing onto, and "theirs" is your own commit being replayed. That's because Git first checks out the new base and then applies your commits to it one by one.

To finish a real rebase you'd edit the file, `git add` it, and run `git rebase --continue`. Here, `git rebase --abort` puts the branch back exactly where it was, so the two IDs printed afterward are equal and the status is clean.

### Squash

**Squashing** combines several commits into one. Instead of P followed by Q, a branch can have a single commit S whose snapshot includes both changes and whose parent is A.

```bash
git switch -c squashed feature-original
git reset --soft start
git commit -m "S: Add task checklist"
git rev-parse 'feature-original^{tree}' 'squashed^{tree}'
git cat-file -p HEAD
```

`git reset --soft start` moves the `squashed` branch back to A but leaves Q's snapshot in the index. Committing that index records S, with A as its only parent. The two tree IDs match, but S is a new commit, neither P nor Q.

```text
A --> P --> Q (feature-original)
|
v
S (squashed)
```

From `squashed`, the history no longer shows P and Q as separate steps. They're still in the repository, though, because `feature-original` points at them.

An interactive rebase is the more common way to squash. On a branch with P and Q after `start`, `git rebase -i start` opens a list of commits in your editor. Leave the first line as `pick` and change the second to `squash` to fold Q into P; Git then asks for the combined message. `fixup` folds the commit in too but drops its message. The list looks like this, with the real IDs Git shows you:

```text
pick <ID-of-P> P: Add completion task
squash <ID-of-Q> Q: Add review task
```

A **squash merge** is a different thing with a similar name. `git merge --squash` prepares the combined result of a merge in your index and working tree, but it doesn't commit and doesn't record the other branch as a parent:

```bash
git switch -c squash-integration heading
git merge --squash feature-original
git status --short
git rev-parse HEAD heading
git diff --cached
git commit -m "SM: Integrate task checklist"
git cat-file -p HEAD
git rev-parse 'integration^{tree}' 'squash-integration^{tree}'
```

Before the commit, HEAD still points at R. After it, SM has R as its only parent, even though its tree matches the normal merge M. So the task changes are there, but history has no link showing that Q was merged. A later merge of the same branch can't use that missing link to tell what was already integrated.

## Remotes, fetch, pull, and push

Three similar-looking names describe different things:

| Name                                   | Where it lives and what it means                                                     |
| -------------------------------------- | ------------------------------------------------------------------------------------ |
| `sync`                                 | A local branch in `task-app`                                                         |
| `main` in the other repository         | A branch stored in that repository                                                   |
| `origin/main` in `task-app`            | A **remote-tracking reference**: `task-app`'s record of where that branch was last seen |

`origin/main` is a saved note, updated when you fetch, so it can be out of date. `origin` is just the short name you give the other repository's location.

The setup below uses only repositories inside `sandbox`. `shared.git` is a **bare repository**: Git storage and references with no working files to edit, which is what servers usually hold. It plays the remote. A second clone, `peer`, plays another person on your team.

```bash
git init --bare --template= -b main "$sandbox/shared.git"
git remote add origin "$sandbox/shared.git"
git push origin start:refs/heads/main
git fetch origin
git switch -c sync --track origin/main
git clone --template= "$sandbox/shared.git" "$sandbox/peer"
git -C "$sandbox/peer" config gc.auto 0
git -C "$sandbox/peer" config maintenance.auto false
```

`start:refs/heads/main` is a **refspec**, written `source:destination`. It means "send my `start`, and call it `main` over there." So the push copies the objects `start` needs into `shared.git` and sets its `main` branch to A, without pushing any of the experiment branches or tags. `-C` runs a Git command in another folder without changing your shell's current folder.

`git fetch` downloads objects and updates the remote-tracking references such as `origin/main`. `--track` makes `origin/main` the **upstream** of `sync`: the branch `git status` compares `sync` against, and the one a plain `git pull` integrates from. A plain `git push` is a different story: by default it only pushes to an upstream with the same name, and `sync` and `main` differ, so the examples always spell out the push mapping, such as `sync:refs/heads/main`.

Now the peer changes the shared branch, while your terminal stays in `task-app`:

```bash
printf 'const heading = "Remote tasks";\n' > "$sandbox/peer/app.js"
git -C "$sandbox/peer" add app.js
git -C "$sandbox/peer" commit -m "N: Update shared heading"
git -C "$sandbox/peer" push origin main:refs/heads/main

git rev-parse sync origin/main
git fetch origin
git rev-parse sync origin/main
git show HEAD:app.js
git show origin/main:app.js
```

Before the fetch, `task-app`'s `origin/main` still points at A, even though the peer already pushed. After the fetch, `origin/main` points at the peer's N, but `sync`, HEAD, the index, and your files are all still at A. The two `show` commands print `Tasks` and `Remote tasks`. With this remote's default fetch mapping, a fetch only updates what you know about the remote and leaves your own branches alone. See [git-fetch](https://git-scm.com/docs/git-fetch).

### Pull and push

`git pull` runs a fetch and then integrates what it fetched into your current branch. Depending on options and configuration, that integration can be a fast-forward, a merge, or a rebase, so it's worth saying which one you want.

```bash
git pull --ff-only origin main
printf 'Read Git\nSynchronize tasks\n' > tasks.txt
git add tasks.txt
git commit -m "W: Add synchronization task"
git push origin sync:refs/heads/main
git -C "$sandbox/shared.git" rev-parse refs/heads/main
git rev-parse sync
git -C "$sandbox/peer" show HEAD:tasks.txt
```

The pull can fast-forward because `sync` has no commits of its own yet, so it moves `sync` to N and updates your files. You then record W on top of N. The push asks `shared.git` to move its `main` to W, and the two printed IDs match.

The push doesn't touch the peer's folder, though. Its last command still prints only `Read Git`; the peer has to fetch and integrate to see W. See [git-pull](https://git-scm.com/docs/git-pull) and [git-push](https://git-scm.com/docs/git-push).

Meanwhile, the peer commits something of its own, still based on N:

```bash
printf 'const filter = "all";\n' >> "$sandbox/peer/app.js"
git -C "$sandbox/peer" add app.js
git -C "$sandbox/peer" commit -m "X: Add task filter"
```

**Expected failure:** the peer's push is rejected.

```bash
git -C "$sandbox/peer" push origin main:refs/heads/main
```

Git prints `! [rejected] main -> main (fetch first)`. The peer's X has N as its parent, while the shared `main` has already moved on to W. Moving `main` to X would drop W from the shared branch, so `shared.git` refuses anything that isn't a fast-forward. Neither the shared branch nor the peer's branch moved.

## Rejected pushes and shared history

A rejected push is one of the most common Git moments on a team, and the fix is the same three steps every time: fetch, put your commits on top of what's there, push again.

```bash
git -C "$sandbox/peer" fetch origin
git -C "$sandbox/peer" rebase origin/main
git -C "$sandbox/peer" push origin main:refs/heads/main
git -C "$sandbox/peer" log --oneline -3
git -C "$sandbox/peer" show HEAD:app.js
git -C "$sandbox/peer" show HEAD:tasks.txt
```

The fetch brings W into the peer. The rebase replays X on top of W as a new commit, X′, which has both the filter line and W's task. Now `main` in `shared.git` can fast-forward from W to X′, so the push succeeds. The log shows X′, then W, then N.

`git merge origin/main` works as the middle step too. It keeps X as it is and adds a merge commit with parents X and W, and that merge commit can be pushed the same way.

The rebase was fine here because X had never left the peer, so nobody else had built on it. Rewriting commits that other people already have is where trouble starts. Suppose `task-app` now amended or rebased W into W′. The peer's X′ still has the old W as its parent, because a commit's parents can never change. Pushing W′ would be rejected for the same reason as before. Forcing it with `git push --force` would make the shared `main` point at W′ and drop both W and the peer's X′ from that branch. The peer would then have to untangle two versions of the same work.

So the practical rule: rebase and squash your own commits freely until you push them; once others may have built on them, add new commits or merge instead. Merge, rebase, and squash each record history differently, and who has already built on that history matters more than any "always merge" or "always rebase" rule.

## Undoing changes

"Undo" can mean throwing away a file edit, unstaging content, moving a branch, or recording a change that reverses an earlier one. Each one touches a different part of what you've seen so far.

Everything below stays inside the throwaway repository. In a real one, `git restore` and `git reset --hard` discard work Git may have no copy of, and `reset --hard` can also overwrite untracked files that are in the way, so save anything important first.

### Restore files without moving a branch

This block starts a clean `undo` branch and creates a staged and an unstaged version again:

```bash
git switch -c undo start
printf 'Read Git\nPrepared task\n' > tasks.txt
git add tasks.txt
printf 'Temporary edit\n' >> tasks.txt

git restore -- tasks.txt
git cat-file -p :tasks.txt
git restore --staged -- tasks.txt
git status --short
git restore --source=HEAD --staged --worktree -- tasks.txt
git status --short
```

Step by step:

1. Plain `git restore` copies the index version over the working file, which removes only `Temporary edit`.
2. `git restore --staged` copies HEAD's version into the index. The working file still has `Prepared task`, which is now an unstaged change.
3. `--source=HEAD --staged --worktree` copies HEAD's version into both, so everything is back to `Read Git`.

None of these moves the `undo` branch or creates a commit. See [git-restore](https://git-scm.com/docs/git-restore).

### Reset moves the branch tip

Given a commit, `git reset` moves the current branch to that commit and, depending on the mode, also updates the index and working tree:

| Mode                | Branch tip    | Index           | Working tree                                    |
| ------------------- | ------------- | --------------- | ----------------------------------------------- |
| `--soft`            | Target commit | Unchanged       | Unchanged                                       |
| `--mixed` (default) | Target commit | Target snapshot | Unchanged                                       |
| `--hard`            | Target commit | Target snapshot | Target snapshot, discarding tracked file edits |

```bash
printf 'Read Git\nSaved task\n' > tasks.txt
git add tasks.txt
git commit -m "U: Save an undo example"
git branch undo-original

git reset --soft start
git status --short
git diff --cached

git reset --mixed start
git status --short
git diff

git reset --hard start
git status --short
```

After the soft reset, `undo` points at A, but U's content is still in the index and the working tree, so it shows up as staged. That's the same trick the squash example used.

The mixed reset then sets the index to A and leaves the working file alone, so `Saved task` becomes an unstaged change. The hard reset makes the index and the tracked files match A, discarding that edit. The branch already pointed at A for these two steps; they still changed the index and files.

None of this deleted U, and `undo-original` still points at it. A reset with a path, such as `git reset -- tasks.txt`, is different: it only unstages that file and doesn't move the branch. See [git-reset](https://git-scm.com/docs/git-reset).

### Revert records an opposite change

```bash
git switch -c inverse undo-original
git revert --no-edit HEAD
git rev-parse 'HEAD^{tree}' 'start^{tree}'
git log --oneline -3
git cat-file -p HEAD
```

`git revert` creates a new commit that undoes U's change, with the message `Revert "U: Save an undo example"`; `--no-edit` accepts it without opening an editor. Its parent is U, so U stays in history, and here its tree matches A. That makes revert the safe undo for commits you've already pushed: it adds history instead of rewriting it. Reverting an older commit can conflict with later edits to the same lines. See [git-revert](https://git-scm.com/docs/git-revert).

### Find lost commits with the reflog

Git records every move of your local references in a **reference log**, or **reflog**: each commit, reset, and branch switch. The reflog belongs to this one repository; pushes don't send it anywhere.

Remember commit D from the detached HEAD section? Delete its branch name:

```bash
git branch -D detached-work
git cat-file -t "$detached_commit"
git reflog | grep "D: Detached"
git branch detached-again "$detached_commit"
```

`git branch -D` prints `Deleted branch detached-work (was …)` with D's short ID. Deleting a branch removes the name, not the commit, so `cat-file` still reports a `commit`. In real life you won't have a shell variable, but HEAD's reflog remembers making D, and the `grep` finds that line with the ID in it. `git branch detached-again` gives D a name again.

The reflog also finds commits that a reset moved away from:

```bash
git switch -c recovery undo-original
printf 'Read Git\nRecover this commit\n' > tasks.txt
git add tasks.txt
git commit -m "L: Commit worth recovering"
printf 'Never staged or committed\n' >> tasks.txt

git reset --hard start
git reflog show recovery
git branch recovered 'recovery@{1}'
git show recovered:tasks.txt
```

Right after the reset, `recovery@{1}` means "where `recovery` pointed one move ago", which is L. `git branch recovered` gives L a lasting name without changing what's checked out. In a real recovery, read the reflog and pick the right entry, because every new move shifts the numbers.

The recovered file contains `Recover this commit` but not `Never staged or committed`. Git never recorded that last line anywhere, so nothing can bring it back.

An object is **reachable** when you can get to it from some reference by following parents, trees, and tag targets. Git keeps reachable objects, and reflog entries keep recently abandoned commits alive too. Unreachable objects are eventually deleted by **garbage collection**, Git's storage cleanup. By default Git keeps reflog entries for 30 to 90 days, but treat that as "probably still there", not a guarantee. Edits you never staged or committed, untracked files, and a deleted `.git` folder can't be recovered through Git at all. The [reflog documentation](https://git-scm.com/docs/git-reflog) and [garbage collection notes](https://git-scm.com/docs/git-gc#_notes) cover the details.

## Predicting what a command will do

Before running an unfamiliar Git command, you can usually predict its effect by asking:

1. **Does it create objects?** A new snapshot, new commits with different parents, or nothing at all?
2. **Which names move?** Your branch, HEAD, a remote-tracking reference such as `origin/main`, or a branch in another repository?
3. **What happens to the index and your files?** Left alone, prepared for a commit, partly replaced, or discarded?

That's also where the opening puzzles land. The file showed up twice in `git status` because the index and the working tree are separate copies, and `git add` only updated one of them. Creating a branch is instant because it writes a name for an existing commit instead of copying anything. And the commits replayed here got new IDs because their parents changed: rebase wrote new commits and left the old ones untouched until nothing points at them anymore.

Git's [object and index tutorial](https://git-scm.com/docs/gittutorial-2), [glossary](https://git-scm.com/docs/gitglossary), and [repository layout reference](https://git-scm.com/docs/gitrepository-layout) describe the same model in more depth.
