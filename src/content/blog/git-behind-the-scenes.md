---
title: "Git behind the scenes: objects, snapshots, and moving pointers"
description: "Follow two task-app files through staging, merging, rewriting, synchronization, and recovery by separating stored objects from moving names."
pubDate: "2026-10-08"
tags:
  - git
  - tooling
  - fundamentals
---

A file can contain both staged and unstaged changes. Creating a branch can finish almost instantly, even in a large project. Rebasing can change commit IDs without visibly changing the feature's code.

These are consequences of the same design: **Git stores objects describing tracked snapshots and their relationships, then moves names that refer to those objects.** The files being edited and the snapshot prepared for the next commit are separate states.

We will follow two small task-app files. They are enough to inspect the storage and predict what commands change; there is no application to build or server to start.

## Contents

1. [Git is local; hosting is separate](#git-is-local-hosting-is-separate)
2. [Create a disposable repository](#create-a-disposable-repository)
3. [Objects describe content and relationships](#objects-describe-content-and-relationships)
4. [A snapshot is connected to history](#a-snapshot-is-connected-to-history)
5. [Working tree, index, and HEAD are separate](#working-tree-index-and-head-are-separate)
6. [Branches and tags name objects](#branches-and-tags-name-objects)
7. [Merge reconciles histories](#merge-reconciles-histories)
8. [Replay and squash build different history](#replay-and-squash-build-different-history)
9. [Remotes exchange objects and update references](#remotes-exchange-objects-and-update-references)
10. [Undo depends on the state being changed](#undo-depends-on-the-state-being-changed)

## Git is local; hosting is separate

Editing a file changes that file on disk. Git can additionally record versions of selected files in its own storage. That storage, including saved history and names for points in history, is a **repository**. “Repo” is shorthand for repository.

In the ordinary repository created below, the editable files sit beside a hidden `.git` directory containing Git's storage and bookkeeping. Creating commits, inspecting history, and creating branches require no network connection.

GitHub and similar services host repositories and add features such as review discussions and access control. Git itself does not depend on them. A **remote** is another repository that a local repository can exchange data with. It can be on another machine or another path on the same machine.

## Create a disposable repository

**Run these examples only in the new disposable directory created here, never in a repository containing work you want to keep.** Later examples deliberately discard file changes and rewrite branch history. They are demonstrations, not instructions to undo an unknown problem in a real project.

You need Git and a Bash-compatible terminal, such as Bash on Linux/macOS or Git Bash on Windows. Run the `bash` blocks in order in the same shell. Stop after an unexpected error. Three blocks are explicitly marked as expected failures; run their following inspection or resolution blocks afterward. `text` blocks are diagrams or illustrative editor content, not shell commands.

Begin in a fresh terminal with no custom `GIT_*` environment variables. This setup ignores system/global Git configuration for this shell and sets a demonstration identity, not your account credentials. It does not edit your global configuration. Close this terminal when finished so these environment settings do not affect other work.

Throughout the examples, letters such as A and P are **teaching labels**, not Git object IDs or reference names. Each commit message we supply starts with its label, such as `A: Start task app`, so you can connect command output to the prose and diagrams. Commands still use real Git names such as `start` and `HEAD`, not these letters.

Executable shell — create the sandbox and the initial snapshot:

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

`mktemp` creates a new uniquely named directory; `sandbox` remembers its path. `cd` changes the shell's current directory. `--template=` avoids copying Git initialization templates. The two local maintenance settings keep automatic housekeeping out of this experiment.

The lines between each `<<'EOF'` and `EOF` are literal file contents. `>` writes a file, replacing existing contents; `>>`, used later, appends. Here both files are new. `git add` prepares their contents and `git commit` records them. `-m` supplies a message without opening an editor.

A path in the index is **tracked**: Git knows about it as part of the proposed snapshot. A file merely present on disk is not automatically tracked. The empty status output means there are no staged or unstaged changes and no untracked files to report in this setup.

The lightweight tag `start` gives the first commit a stable name for later examples. We will explain tags shortly.

## Objects describe content and relationships

Git stores the file data, the directory entries connecting names to that data, and the history connecting snapshots as different kinds of **objects**:

| Object        | What it records                                                                    |
| ------------- | ---------------------------------------------------------------------------------- |
| Blob          | Stored file content, without the filename                                          |
| Tree          | Directory entries: names, file modes, and IDs of blobs or child trees              |
| Commit        | A root tree ID, parent commit IDs, author/committer metadata, and a message        |
| Annotated tag | A target object ID, tag name, tagger metadata, and message; optionally a signature |

The author records who originally wrote a change; the committer records who recorded this commit. Their names, email addresses, and times are **metadata**: information about the commit rather than file content.

A **root tree** describes the top-level directory of the tracked snapshot. An entry for a subdirectory refers to another tree, so following the entries reconstructs the directory hierarchy.

An **object ID** is calculated from the object's type and contents, including a size header. A hash function is the calculation that turns those bytes into the ID. This is **content-addressed storage**: Git looks up stored objects by IDs derived from their data, rather than by an increasing version number.

Within a repository's object format, identical object data has the same ID and can be reused. An unchanged file can therefore appear in many snapshots through the same blob. Changing a tree entry, commit parent, message, or other object data changes the corresponding ID; Git does not edit an existing object under its old ID.

Do not assume a particular ID length or hash algorithm. Git supports different object formats, and the examples ask Git to resolve names instead of copying hashes from someone else's run. Actual commit IDs also depend on metadata such as identity and timestamps; Git's formatting/version choices can matter when they change recorded bytes.

### Inspect the objects

Executable shell — still in `task-app`, at the initial commit:

```bash
git cat-file -t HEAD
git cat-file -p HEAD
git cat-file -p 'HEAD^{tree}'
git cat-file -t HEAD:tasks.txt
git cat-file -p HEAD:tasks.txt
```

`HEAD` identifies the current checkout's place in history. `-t` prints an object's type; `-p` prints its contents in a readable form. `HEAD^{tree}` asks for the commit's root tree, and `HEAD:tasks.txt` selects the stored object at that path in its snapshot.

Read the output from the outside in:

1. Commit A has a `tree` line, author and committer lines, and the message `A: Start task app`. This first commit has no `parent` line.
2. The tree lists `app.js` and `tasks.txt`, each with a mode, `blob`, and an object ID. Here `100644` means an ordinary non-executable tracked file.
3. The selected blob contains `Read Git` followed by a newline. Its data does not include the name `tasks.txt`; the tree supplied that name.

Conceptual object diagram — symbolic labels, not observed IDs:

```text
commit A --> root tree T
             |-- app.js    --> blob J: const heading = "Tasks";
             `-- tasks.txt --> blob K: Read Git

A: Start task app
```

A snapshot covers **tracked paths**, not everything on the machine. Git's recorded modes distinguish a limited set of types and the executable bit; they are not a backup of all filesystem permissions, owners, or timestamps. A blob is the stored content: attributes and conversion filters can transform file bytes during staging or checkout. This example has no such filters.

### Snapshots do not require full physical copies

Following commit → tree → blob gives the logical file state. It does not mean every commit duplicates every file on disk.

Git can reuse unchanged blobs and trees. It can also combine many objects into compressed **packfiles**. Inside a packfile, an object may be represented using another object's data plus instructions to reconstruct it, called a **delta**.

That storage optimization is separate from the history model. A packed blob's delta base is not a commit parent, and a commit is not merely a saved patch. Git calculates a **diff**, the differences between states, by comparing them. The [pack format documentation](https://git-scm.com/docs/gitformat-pack) describes these physical representations; the examples here inspect logical objects, not packing behavior.

## A snapshot is connected to history

A normal commit points to its predecessor as a parent. A merge commit can have multiple parents. Repeatedly following parent links gives the history graph: commits are its points, and links show ancestry.

The links have a direction and do not loop back to their starting point. This is a **directed acyclic graph**, often shortened to **DAG**. The parent relationships define ancestry; commit timestamps are not a reliable substitute for them.

Two different commits can point to exactly the same root tree.

Executable shell — deliberately record a second commit with no file changes:

```bash
git commit --allow-empty -m "B: Record a checkpoint"
git rev-parse 'start^{tree}' 'HEAD^{tree}'
git rev-parse start HEAD
git cat-file -p HEAD
```

`rev-parse` resolves the supplied names to object IDs. The two tree IDs are equal, while the commit IDs differ. Commit B (`B: Record a checkpoint`) records A as its parent and a different message even though its snapshot is unchanged. `--allow-empty` permits this intentionally unchanged snapshot.

Symbolic history diagram — lines connect parents to children, with newer commits to the right:

```text
A -- B  (main)
|    |
T    T  (same root tree)

A: Start task app; B: Record a checkpoint
```

This distinction explains why “the files look the same” does not mean “these are the same commits.”

## Working tree, index, and HEAD are separate

When preparing a change, there are three states to keep apart:

- **Working tree:** the files on disk that you edit.
- **Index**, also called the **staging area:** entries describing the proposed next tracked snapshot, including references to stored file content.
- **HEAD commit:** the snapshot currently recorded at the checkout's place in history.

Staging captures content at that moment. It does not establish a connection that automatically follows later edits.

Executable shell — stage one version of `tasks.txt`, then edit it again:

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

`git status --short` shows `MM tasks.txt`: the first `M` describes an index change relative to HEAD; the second describes a working-tree change relative to the index.

The two diffs answer different questions:

| Comparison           | Command             | Change shown here     |
| -------------------- | ------------------- | --------------------- |
| Index → working tree | `git diff`          | Adds `Not staged yet` |
| HEAD → index         | `git diff --cached` | Adds `Try staging`    |

`--` separates command options from paths. `ls-files --stage` exposes the index entries. `:tasks.txt` selects the index's blob, whose content ends at `Try staging`.

State diagram — file contents, not commands:

```text
HEAD:          Read Git
Index:         Read Git / Try staging
Working tree:  Read Git / Try staging / Not staged yet
```

Executable shell — commit only the staged snapshot, then discard the remaining demonstration edit:

```bash
git commit -m "C: Add staging exercise"
git cat-file -p HEAD:tasks.txt
git diff -- tasks.txt
git restore -- tasks.txt
git status --short
```

Commit C (`C: Add staging exercise`) records the index, not the later working-tree edit. Afterward, `Not staged yet` is still unstaged. `git restore -- tasks.txt` replaces the working file from the index and discards that line. It creates no commit. The repository is clean again for the branch examples.

Options such as `git commit -a` or explicit path arguments can alter how content is prepared for a commit. The demonstrations use explicit `git add` followed by plain `git commit` so the three states remain visible. See [the index tutorial](https://git-scm.com/docs/gittutorial-2) and [git-add](https://git-scm.com/docs/git-add).

## Branches and tags name objects

A branch stores a name for a commit, its **tip**. Creating a branch does not copy the project or duplicate its history; it creates another name for an existing commit. When you commit while on a branch, Git normally moves that branch's tip to the new commit.

These names are **references**, or **refs**. For example, the full name of the local branch `main` is `refs/heads/main`. `HEAD` normally refers to that branch name, which in turn refers to a commit.

Executable shell — create names without changing files or switching branches:

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

`main`, `experiment`, and `checkpoint` resolve to C (`C: Add staging exercise`) here. `git branch experiment` did not switch to it. `symbolic-ref HEAD` prints `refs/heads/main`.

The lightweight tag `checkpoint` points directly to the commit. The annotated tag `v0-demo` points to a separate tag object, which refers to that commit and carries the annotation. Both kinds of tag names normally stay in place when subsequent commits advance a branch. Tags can be explicitly replaced; they are not inherently impossible to move. See [git-tag](https://git-scm.com/docs/git-tag).

Conceptual reference diagram — objects stay fixed; names can change:

```text
HEAD --> main ----------> commit C --> tree
         experiment ----> commit C
         checkpoint ----> commit C
         v0-demo --> tag object -----> commit C

C: Add staging exercise
```

### Detached HEAD

You can check out a commit without selecting a branch. `HEAD` then refers directly to a commit; it is **detached**. Committing still works, but it advances HEAD without advancing any branch.

Executable shell — start from `start`, make a detached commit, and name it before leaving:

```bash
git switch --detach start
git commit --allow-empty -m "D: Detached experiment"
detached_commit=$(git rev-parse HEAD)
git branch kept-detached
git switch main
git branch -D kept-detached
git cat-file -t "$detached_commit"
```

The shell variable remembers the observed ID; it is not a Git reference. `kept-detached` initially gave D (`D: Detached experiment`) a branch name. After switching back to `main`, `-D` deliberately removes that name even though the commit is not in main's ancestry.

The final command still finds the commit object. Deleting a branch deletes a reference, not all the objects behind it immediately. Other references or local reference logs may retain the objects, and even objects no longer retained can remain until housekeeping collects them. Recovery has limits, covered below.

## Merge reconciles histories

Each of the next examples starts new branches from the tag `start`. The previous `main` history remains untouched. The working tree and index are clean before each operation.

### Fast-forward: no divergent histories to combine

Executable shell — create one new commit and advance another branch to it:

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

Before the merge, `ff-main` names A, the parent of F (`F: Clarify heading`), which is `ff-feature`'s tip. There is no separate line of work to reconcile. The merge moves `ff-main` forward to the existing commit and updates the index and working files. It creates no new commit. This reference movement is a **fast-forward**.

Symbolic before/after diagram:

```text
Before: A (ff-main) -- F (ff-feature)
After:  A ----------- F (ff-main, ff-feature)

A: Start task app; F: Clarify heading
```

`--ff-only` requires that kind of update and refuses divergence. `git log --graph` draws parent relationships, `--oneline` abbreviates each entry, and `--decorate` shows reference names.

### Divergence: compare a common base and both tips

Now both branches will have their own changes from A (`A: Start task app`), named by `start`. The task branch adds P (`P: Add completion task`) and then Q (`Q: Add review task`). The heading branch adds R (`R: Use clearer heading`). We will label the combined result M (`M: Merge task list and heading`).

Executable shell — arrange the divergent starting state and merge it:

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
git branch new-base

git merge-base integration feature
git diff start new-base -- app.js tasks.txt
git diff start feature-original -- app.js tasks.txt
git merge -m "M: Merge task list and heading" feature
git cat-file -p HEAD
git cat-file -p HEAD:tasks.txt
git cat-file -p HEAD:app.js
```

`feature-original` preserves Q, the old feature tip, for later comparisons. `new-base` preserves R, the heading commit, before `integration` advances. The merge's `-m` supplies M's message without opening an editor.

Just before the merge, these are the three snapshots to compare. Each displayed file line ends with a newline:

| Snapshot and message                 | Git name                                       | `app.js`                       | `tasks.txt`                                              |
| ------------------------------------ | ---------------------------------------------- | ------------------------------ | -------------------------------------------------------- |
| A: Start task app — shared base      | `start`                                        | `const heading = "Tasks";`     | `Read Git`                                               |
| R: Use clearer heading — current tip | `new-base` (also `integration` before merging) | `const heading = "Task list";` | `Read Git`                                               |
| Q: Add review task — other tip       | `feature-original` (also `feature`)            | `const heading = "Tasks";`     | `Read Git`<br />`Mark a task done`<br />`Review history` |

The first `git diff` compares A → R: only `app.js` changes, replacing `Tasks` with `Task list`. The second compares A → Q: only `tasks.txt` changes, adding `Mark a task done` and `Review history`. Q's snapshot already includes the completion task introduced by P.

Git combines these file states step by step:

1. For `app.js`, Q is unchanged from A, while R has the new heading. The result keeps R's `const heading = "Task list";`.
2. For `tasks.txt`, R is unchanged from A, while Q has the two added lines. The result keeps Q's three-line task list.
3. Git records those two resulting files in M's root tree, updates the index and working files to match, and moves `integration` to M.

This comparison uses **three snapshots, not three branches**. A suitable shared ancestor used as the starting point is the **merge base**; `git merge-base` prints A's ID here. In this simple case, one side left each file unchanged from A, so Git can combine the changes automatically. This is not a rule that all same-file edits conflict: non-overlapping edits within one file can also combine cleanly.

M records R and Q as its parents, not A. A supplies the comparison base; it is already their ancestor. In `cat-file`, the first parent is R, the previous `integration` tip, and the second is Q, the feature tip.

Symbolic graph — `M` is the merge result:

```text
A --> P --> Q (feature, feature-original)
|           |
v           v
R --------> M (integration)

R: new-base
Parents: P: A; R: A; Q: P; M: R, Q.

A: Start task app; P: Add completion task; Q: Add review task
R: Use clearer heading; M: Merge task list and heading
```

This is a **three-way merge**: it reconciles base A and tips R and Q. P is an intermediate ancestor of Q, not a separate merge input. **Git does not replay P and then Q as separate commits on top of R.** Those original commits remain connected through the merge's second parent. See [git-merge: true merge](https://git-scm.com/docs/git-merge#_true_merge).

### A conflict means the result needs a decision

Here both sides replace A's `Read Git` line differently. H (`H: Emphasize careful reading`) and I (`I: Focus on objects`) will require a decision about the intended task text.

Executable shell — make another pair of branches from `start`:

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

Executable shell — **expected failure**, a content conflict in `tasks.txt`:

```bash
git merge conflict-feature
```

No merge commit has been made. HEAD and `conflict-main` stay at H; `conflict-feature` still names I. The working file contains conflict markers, and the index holds separate versions for the unresolved path.

Executable shell — inspect those versions, then choose and commit the intended result:

```bash
git status --short
git ls-files --unmerged
git show :1:tasks.txt
git show :2:tasks.txt
git show :3:tasks.txt

printf 'Read Git objects carefully\n' > tasks.txt
git add tasks.txt
git commit -m "MC: Combine reading instructions"
git cat-file -p HEAD
```

For this merge, index stage 1 is base A (`Read Git`), stage 2 is our current tip H (`Read Git carefully`), and stage 3 is the other tip I (`Read Git objects`). These numbered index entries are different from the ordinary stage-0 entry seen earlier.

The resolution combines both intentions in `Read Git objects carefully`. `git add` replaces the unresolved entries with the chosen content; `git commit` records MC (`MC: Combine reading instructions`) with parents H and I. MC labels this conflict-resolution merge; M labels the earlier automatic merge. Removing markers alone would not prove that a real application's behavior is correct. Git can establish that a conflict has been staged as resolved, not that the chosen behavior meets its requirements.

## Replay and squash build different history

Merging retains parent links to both histories. Other operations can reuse changes while recording different parent relationships.

### Cherry-pick: apply a selected change in another context

A commit records a snapshot. Comparing it with its parent gives the change it introduced. A **cherry-pick** takes that change and applies it at the current checkout's context.

Executable shell — start at the preserved heading commit, then select only the first feature change:

```bash
git switch -c picked new-base
git cherry-pick feature-original~1
git rev-parse 'feature-original~1' HEAD
git cat-file -p HEAD
git cat-file -p HEAD:tasks.txt
git cat-file -p HEAD:app.js
```

`~1` follows one first-parent link, selecting P rather than Q. This divergent example records a new commit: its parent is R, not A. Its snapshot includes the clearer heading from R and the completion task from P, but not Q's review task.

The original P object is unchanged. We label the replacement object P': it has a different ID because its parent, and here its root tree, differ. The cherry-pick retains the message `P: Add completion task`; the prime identifies a replacement object in the explanation, not a renamed message. See [git-cherry-pick](https://git-scm.com/docs/git-cherry-pick).

### Rebase: replay a selected series, then move the branch

For this linear feature history, rebasing onto `new-base` applies P's change and then Q's change after R. Once successful, Git moves `feature` to the resulting tip.

Executable shell — rebase the original feature branch, with `feature-original` retaining its old tip:

```bash
git switch feature
git rebase new-base
git rev-parse feature-original feature
git log --graph --oneline --decorate feature feature-original new-base
git cat-file -p HEAD
git cat-file -p HEAD:tasks.txt
git cat-file -p HEAD:app.js
```

Symbolic before/after graph — primes label replacement commits, not hash suffixes:

```text
Before:
A --> P --> Q (feature, feature-original)
|
v
R (new-base)
Parents: P: A; R: A; Q: P.

After:
A --> P --> Q (feature-original)
|
v
R (new-base) --> P' --> Q' (feature)
Parents: P: A; R: A; Q: P; P': R; Q': P'.

A: Start task app; R: Use clearer heading
P and P': "P: Add completion task"
Q and Q': "Q: Add review task"
```

P' has R as its parent. Q' has P' as its parent. Both IDs differ from the corresponding old commits in this example, but their messages remain `P: Add completion task` and `Q: Add review task`. Rebase normally retains those messages; P' and Q' label replacement objects, not new message prefixes. The resulting snapshot includes both task changes and the heading change. Original objects P and Q were not mutated; we kept a name for them so the distinction is visible.

This is not a promise that every rebase or cherry-pick invocation always creates new IDs. A rebase can find nothing to do, fast-forward over unchanged commits, or skip changes already present upstream. Cherry-pick has options for fast-forwarding and handling redundant or empty changes. The demonstrated case is a genuinely divergent base with applicable, nonempty changes. See [git-rebase](https://git-scm.com/docs/git-rebase).

Replay can also conflict. A change that made sense after A may not apply cleanly after another commit replaces the same text.

Executable shell — create a disposable branch at the old conflicting feature tip:

```bash
git switch -c replay-conflict conflict-feature
```

Executable shell — **expected failure**, replay onto the independently edited task text:

```bash
git rebase conflict-target
```

Git stops while trying to replay I (`I: Focus on objects`) after H (`H: Emphasize careful reading`). It has not completed the branch rewrite. A resolution would require editing, staging, and `git rebase --continue`; skipping would omit that change. Here the demonstration instead aborts.

Executable shell — inspect and return to the branch's pre-rebase state:

```bash
git status --short
git rebase --abort
git rev-parse replay-conflict conflict-feature
git status --short
```

The two IDs are equal after abort, and the checkout is clean. Conflict labels such as “ours” and “theirs” during rebase refer to the so-far rebased history and the replayed commit, respectively; do not assume they mean the same branch roles as in the earlier merge.

### Squash: keep the combined result without every intermediate commit

**Squashing** combines multiple changes into one resulting commit. A branch containing P followed by Q can instead contain S (`S: Add task checklist`), whose snapshot includes both changes but whose parent is A.

Executable shell — combine the two original feature commits using the index:

```bash
git switch -c squashed feature-original
git reset --soft start
git commit -m "S: Add task checklist"
git rev-parse 'feature-original^{tree}' 'squashed^{tree}'
git cat-file -p HEAD
```

This is confined to the disposable branch `squashed`. The soft reset moves its tip back to A while retaining the prepared snapshot from Q in the index. Committing that snapshot records S, with A as its only parent. The tree IDs match, but S is neither P nor Q.

Symbolic graph:

```text
A --> P --> Q (feature-original)
|
v
S (squashed)

Parents: P: A; Q: P; S: A.

A: Start task app; P: Add completion task; Q: Add review task
S: Add task checklist
```

From `squashed`, parent traversal no longer shows the separate completion-task and review-task steps. Their intermediate snapshot and individual messages are absent from **this branch's new history**, not instantly erased from every repository. Here `feature-original` still retains both commits.

Interactive rebase offers another way to combine them. `git rebase -i start`, run on a branch with just P and Q after `start`, opens a list of actions. Leave P as `pick` and change Q to `squash` to fold it into the preceding commit. Git then asks for the combined message. `fixup` also folds the change but normally discards that commit's message.

Illustrative editor input only — replace the symbolic placeholders with the IDs Git actually lists; this is not an executable command block:

```text
pick <ID-of-P> P: Add completion task
squash <ID-of-Q> Q: Add review task
```

Interactive squashing rewrites that branch's selected commits. **A squash merge is different:** it prepares the combined merge result in the current branch's index and working tree without recording a merge commit or moving HEAD by itself.

Executable shell — start at R and prepare the original feature's combined result:

```bash
git switch -c squash-integration new-base
git merge --squash feature-original
git status --short
git rev-parse HEAD new-base
git diff --cached
git commit -m "SM: Integrate task checklist"
git cat-file -p HEAD
git rev-parse 'integration^{tree}' 'squash-integration^{tree}'
```

Before the explicit commit, HEAD still names R. After it, SM (`SM: Integrate task checklist`) has only R as a parent, even though its tree equals the normal merge result M (`M: Merge task list and heading`) in this example. There is no second-parent link recording integration of Q. The task changes are present; the original branch's history is not connected as merge ancestry. A later merge therefore cannot rely on that missing parent link to recognize the earlier integration.

### Why shared history changes the consequences

Suppose a collaborator made a commit whose parent was the old Q. Moving your feature branch to Q' does not change their commit's stored parent. Their history still leads to Q, while your new history leads through P' and Q'. Reconciling those histories can require coordination and careful selection of which changes to keep.

Likewise, replacing a shared branch tip can remove other people's commits from that branch's visible ancestry. Ordinary pushes reject non-fast-forward branch updates; overriding that rejection is a separate, consequential action, not something rebase itself does.

Merge, rebase, and squash record different relationships. Which history a team needs to retain, and who has already built on it, matter more than an “always merge” or “always rebase” rule.

## Remotes exchange objects and update references

Three similar-looking names can describe different state:

| Name                           | Location and meaning                                                       |
| ------------------------------ | -------------------------------------------------------------------------- |
| `sync`                         | A local branch in `task-app`                                               |
| `main` in the other repository | A branch stored by that repository                                         |
| `origin/main` in `task-app`    | A local remote-tracking reference: recorded knowledge of the remote branch |

A **remote-tracking reference** is not a live view of another repository. `origin` is a configured short name for a repository location; it is not a special server built into Git.

The following setup uses only repositories you own inside `sandbox`. `shared.git` is a **bare repository**: storage and references without editable working files. It serves as the remote. A small `peer` checkout represents another writer. Including its commands makes the other writer's changes reproducible, without invisible setup or a hosting account.

Executable shell — from `task-app`, create the shared repository and a local synchronization branch:

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

The first push transfers the necessary objects and asks `shared.git` to set its `main` branch to our `start` commit. `start:refs/heads/main` explicitly identifies the source and destination; it does not push all the experimental branches or tags. `-C` runs a Git command in the specified directory without changing the shell's directory.

`fetch` obtains objects and, with this ordinary remote configuration, updates local remote-tracking references. `--track` connects `sync` to `origin/main` as its **upstream**, the configured branch used for comparisons and default integration choices.

Executable shell — let the peer advance the shared branch, while the main shell stays in `task-app`:

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

Before the fetch, `task-app`'s `origin/main` still names A, like `sync`, despite the peer's successful push. After fetching, `origin/main` names N (`N: Update shared heading`), the peer's newer commit, but `sync`, HEAD, the index, and the checked-out files still describe A. The two `show` commands print `Tasks` and `Remote tasks`, respectively.

This is the normal fetch arrangement, not a universal restriction: explicit destination mappings, called **refspecs**, or unusual configuration can direct a fetch to update other local refs. See [git-fetch: configured remote-tracking branches](https://git-scm.com/docs/git-fetch#CRTB).

### Pull integrates; push requests an update elsewhere

`pull` first fetches, then integrates the selected history. Integration can be fast-forward-only, merge, rebase, or squash according to options and configuration. Being explicit avoids relying on an unseen default.

Executable shell — fast-forward `sync`, then send a new local task commit to shared `main`:

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

The pull can fast-forward because `sync` has no independent commits yet. It updates the branch, index, and working files to N's heading snapshot. We then record W (`W: Add synchronization task`) with N as its parent. The subsequent push asks the shared repository to advance `main` to W, our new `sync` tip; the printed IDs match.

That push does not edit the peer's checkout. Its last command still prints only `Read Git`; the peer needs to fetch and integrate to bring its files up to date. See [git-pull](https://git-scm.com/docs/git-pull) and [git-push](https://git-scm.com/docs/git-push).

If the peer independently commits now, its history diverges from the shared branch.

Executable shell — arrange that divergence:

```bash
printf 'Read Git\nAnother writer task\n' > "$sandbox/peer/tasks.txt"
git -C "$sandbox/peer" add tasks.txt
git -C "$sandbox/peer" commit -m "X: Add independent peer task"
```

Executable shell — **expected failure**, a rejected non-fast-forward push:

```bash
git -C "$sandbox/peer" push origin main:refs/heads/main
```

The peer's X (`X: Add independent peer task`) has N as its parent, not W. It does not contain W's shared synchronization change in its ancestry. The rejected request does not move the shared branch or the peer's local branch. Fetching and deciding how to reconcile the work are separate steps; forcing an update would not perform that reconciliation. This demonstration leaves the peer divergent and returns to local undo examples in `task-app`.

## Undo depends on the state being changed

“Undo” can mean replacing a file, unstaging content, moving a branch tip, or recording an inverse change. Those affect different parts of the model.

**Everything below remains inside the disposable sandbox. `restore` can discard edits; `reset --hard` discards tracked-file changes and can also overwrite or remove untracked paths that obstruct writing the target snapshot. It is not safe merely because a file is untracked.** Save important work independently before trying an undo operation in a real repository.

### Restore selected content without moving a branch

Executable shell — start a clean `undo` branch at `start`, then recreate staged and unstaged versions:

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

The operations proceed through these states:

1. Plain `restore` copies the index version to the working file, removing only `Temporary edit` here.
2. `restore --staged` defaults to HEAD as its source and replaces the index entry. The working file still has `Prepared task`, now an unstaged change.
3. The explicit source plus `--staged --worktree` restores both destinations to HEAD. Both are now back to `Read Git`.

None moves `undo` or creates a commit. Restoring a tracked path absent from the chosen source can remove it to match that source. See [git-restore](https://git-scm.com/docs/git-restore).

### Reset a tip, optionally the index and working tree

For the whole-commit forms shown here, `reset` moves the current branch's tip to a target commit and optionally updates other state. With detached HEAD, it moves HEAD directly.

| Mode                | Current tip   | Index           | Working tree                                            |
| ------------------- | ------------- | --------------- | ------------------------------------------------------- |
| `--soft`            | Target commit | Unchanged       | Unchanged                                               |
| `--mixed` (default) | Target commit | Target snapshot | Unchanged                                               |
| `--hard`            | Target commit | Target snapshot | Target tracked snapshot, with destructive path handling |

Executable shell — commit a task, retain a name for it, then progressively reset the three states:

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

The saved task commit is U (`U: Save an undo example`), retained by `undo-original`. After the soft reset, `undo` names A, but U's snapshot remains in both the index and working tree. It is staged relative to the new HEAD. This is the mechanism used to squash earlier.

The mixed reset then changes the index to A while leaving the working file alone: `Saved task` becomes unstaged. The hard reset makes the index and tracked working files match A, discarding that remaining edit. For the mixed and hard steps here, the branch already names A; updating the other states is still meaningful.

These resets did not erase U. `undo-original` still names it. Also distinguish the path form, such as `git reset -- tasks.txt`: it updates selected index entries without moving HEAD or the branch. See [git-reset](https://git-scm.com/docs/git-reset).

### Revert records an inverse change

Executable shell — start from the saved task commit and reverse it with a new commit:

```bash
git switch -c inverse undo-original
git revert --no-edit HEAD
git rev-parse 'HEAD^{tree}' 'start^{tree}'
git log --oneline -3
git cat-file -p HEAD
```

Git supplies the message `Revert "U: Save an undo example"`; `--no-edit` accepts it without an editor. This new commit's tree equals A's initial snapshot in this simple case. Its parent is U, which remains in the history. Revert applies the inverse of an earlier change in the current context; it does not generally restore an entire old snapshot or erase the original commit. Reverting an older change can conflict with later edits. See [git-revert](https://git-scm.com/docs/git-revert).

### Reflog helps locate old tips, not every old file

Git can record local reference movements, including previous branch tips, in a **reference log**, or **reflog**. HEAD's reflog also records checkout switches. A reflog belongs to this repository; it is not the shared commit history and is not transferred by an ordinary push.

Executable shell — create a new commit, make an uncommitted edit, then deliberately reset away from both:

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

Immediately after that reset, `recovery@{1}` means the previous recorded tip of `recovery`: L (`L: Commit worth recovering`), the commit just created. `git branch recovered` gives it a persistent branch name without changing the checkout. In a real recovery, inspect your reflog and choose the correct entry; `{1}` is not a universal “last good commit” selector, and more updates change the numbering.

The recovered snapshot contains `Recover this commit`. It does **not** contain `Never staged or committed`. Git did not record that later file state. Reflog recovery works here because there is a recorded reference update and the committed objects are still available.

An object is **reachable** from a reference when following object relationships from that reference can lead to it: commit parents, commit trees, tree entries, and annotated-tag targets. Removing one name does not remove an object still reachable from another. Reflogs and index entries also help Git retain objects that no longer appear in a branch's current history.

Objects no longer retained can eventually be removed by **garbage collection**, Git's housekeeping for storage. Reflogs expire too. The documented defaults are 90 days for general reflog expiration and 30 days for entries not reachable from the current tip, but configuration and maintenance choices can change this. These are expiration policies, **not guaranteed recovery windows** or a promise that objects are removed on a particular day.

Staged content may have created blob objects, but without a retained commit/tree there may be no saved filename or complete snapshot to recover. Never-staged edits, untracked files, deleted repository storage, or already-collected objects may be unrecoverable through Git. Keep backups appropriate to the work's value. The [reflog documentation](https://git-scm.com/docs/git-reflog) and [garbage-collection notes](https://git-scm.com/docs/git-gc#_notes) explain retention and expiration; this example does not run collection or test long-term recovery.

## Predict the operation before running it

For a Git operation, ask three questions:

1. **What objects describe the result?** Reuse an existing tree, record a new snapshot, or create commits with different parents?
2. **Which names move?** A local branch, HEAD, remote-tracking knowledge, or a branch in another repository?
3. **What happens to the index and working files?** Preserve them, prepare a result, replace selected paths, or discard changes?

The opening mysteries now have concrete answers. A file can be staged and then edited again because the index and working tree are separate. A branch is cheap because it names an existing commit rather than copying the project. Rebase can change IDs because it records commits in a new parent context instead of mutating the old ones.

For further inspection, Git's [object and index tutorial](https://git-scm.com/docs/gittutorial-2), [glossary](https://git-scm.com/docs/gitglossary), and [repository layout reference](https://git-scm.com/docs/gitrepository-layout) connect the commands to the same underlying model.
