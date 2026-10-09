---
title: "Coding with agents: context, direction, and verification"
description: "Follow one request through a coding agent: supplied context, tokens, responses, tools, skills, MCP, reasoning, and verified changes."
pubDate: "2026-10-09"
tags:
  - agents
  - tooling
  - fundamentals
---

You ask a coding agent:

> Find why the task editor loses the user's entered title when saving fails. Investigate first; don't change anything yet.

The saved task is called `Report`. The user types `Updated report`, presses Save, and gets an error. The saved task is unchanged, but the entered text disappears. The intended behavior is that the text remains available for correction or retry.

This article follows that request through the agent. At each step, ask three questions: **what information is available, which program does the work, and what result comes back?** That gives tools, context, reasoning, and instruction files a concrete purpose instead of treating them as separate AI vocabulary.

> This advice is not necessarily future-proof. Model capabilities, agent applications, context limits, and effective workflows change quickly. Product-specific behavior is identified rather than presented as a permanent rule. Check current documentation and evaluate results on your own tasks.

## Contents

- [You send a request; the application prepares the input](#you-send-a-request-the-application-prepares-the-input)
- [The text is represented as tokens](#the-text-is-represented-as-tokens)
- [The model generates a reply—or requests an operation](#the-model-generates-a-replyor-requests-an-operation)
- [A tool turns a request into an actual operation](#a-tool-turns-a-request-into-an-actual-operation)
- [A skill gives the investigation a repeatable procedure](#a-skill-gives-the-investigation-a-repeatable-procedure)
- [MCP connects capabilities supplied by another program](#mcp-connects-capabilities-supplied-by-another-program)
- [Reasoning helps choose what to do with the evidence](#reasoning-helps-choose-what-to-do-with-the-evidence)
- [The conversation grows; context has to be selected](#the-conversation-grows-context-has-to-be-selected)
- [Project instructions keep recurring guidance available](#project-instructions-keep-recurring-guidance-available)
- [Progressive disclosure keeps detail available without loading it all](#progressive-disclosure-keeps-detail-available-without-loading-it-all)
- [A better starting point can beat more steering](#a-better-starting-point-can-beat-more-steering)
- [An edit is a proposal until its result is checked](#an-edit-is-a-proposal-until-its-result-is-checked)
- [Permissions bound what the loop can affect](#permissions-bound-what-the-loop-can-affect)
- [Sources and further reading](#sources-and-further-reading)

## You send a request; the application prepares the input

The editor or terminal application in which you type is not the language model itself. It is a program that manages the conversation, supplies information to the model, and can perform operations on your behalf.

When you press Send, that program prepares an input. Your message may be combined with general instructions, project guidance, earlier conversation, and descriptions of available operations.

For this investigation, a simplified first input could look like this:

```text
Instructions:
  Investigate before editing.
  Preserve unrelated work.
  Form behavior is documented in docs/forms.md.

Developer's request:
  Find why failed saves lose the task editor's entered title.
  The entered text must remain available for retry.

Available operations:
  Read a file by path.
  Search project files.
  Run an allowed project check.

Source file contents supplied so far:
  None.
```

This supplied information is the model's **context**: what is available for the current response. The repository may contain hundreds of files, but that does not put all their contents into context. A tool that can read them is a route to obtain information, not proof that the information has already been obtained.

The model also has patterns learned during training. Those can help it recognize that this sounds like a form-state problem. They cannot establish which files exist here or where this particular editor clears its text.

The distinction is simple: **knowing how forms commonly work is different from having read this form**. The application's job is to make relevant evidence available. The model's job is to respond using what it has been supplied.

If the model is provided by a remote service, the application sends the selected input to that service. Models can also run locally. In either case, do not infer repository visibility from the model's location: visibility depends on what the application supplies and which capabilities it exposes.

## The text is represented as tokens

The model does not receive text in quite the same form as a person reading a paragraph. A **tokenizer** converts it into a sequence of numbered pieces called **tokens**.

First look at the pieces as text, rather than at their numbers. A tokenizer may represent text using pieces like these; the exact split depends on its vocabulary and rules:

```text
Text:    Saving failed.
Pieces:  [Saving][ failed][.]

Text:    saveDraft
Pieces:  [save][Draft]
```

Each pair of brackets marks one piece. In the first example, the space before `failed` belongs to that piece. In the second, a name that looks like one word is represented by two pieces. Punctuation can be a separate piece too.

A tokenizer has a vocabulary and rules for converting text into pieces from that vocabulary. It need not contain every possible word or identifier as a single entry. A word can be represented using smaller parts; common sequences can have their own entries.

For example, a possible subword split is:

```text
Text:    encoding
Pieces:  [encod][ing]
```

The pieces are not a grammatical explanation. The tokenizer is not deciding that `ing` has a particular meaning; it is applying its encoding rules. Another tokenizer can split the same text differently, including representing a whole word as one piece.

Each selected piece has a numerical identifier in that tokenizer's vocabulary. The model processes those identifiers. Generated identifiers are decoded back into text for the application. The numbers depend on the vocabulary; they are not universal IDs for English words.

This matters for the request we just sent. The instructions, task, operation descriptions, later file contents, and returned logs all contribute tokens when included. The visible message is not the whole input.

It also explains why counting words is not a reliable way to count tokens. Code contains names, symbols, indentation, and other sequences that do not line up neatly with ordinary words. A long error log can consume substantial capacity even if your newest message is only “try again.”

## The model generates a reply—or requests an operation

The application now has an input represented as tokens. The model uses that input and patterns learned during training to generate output.

A simplified text-generation picture is that the model evaluates possible next tokens, a selection process chooses a token, and generation continues with the growing output contributing to subsequent choices. An illustrative continuation for this task is:

```text
Output so far:       I need to
Next piece selected: [ inspect]
Output so far:       I need to inspect

Generation continues toward a reply such as:
I need to inspect the editor and its save path.
```

The bracketed text again includes its leading space. This is a picture of generation, not a recording from a particular model. The model produces a sequence of pieces rather than looking up a complete prewritten answer to the exact request.

For the editor task, it could generate a normal reply:

> I need to inspect the editor and its save path before identifying the cause.

That sentence is useful communication, but it has not read a file. It is an output from the model, not an operation on the repository.

The application can also provide a way for the model to request an operation. A model response might include a structured file-read request rather than—or alongside—a paragraph. The application recognizes that request and routes it to the appropriate capability.

These are two different kinds of result:

| Model output                                 | What it does by itself                      |
| -------------------------------------------- | ------------------------------------------- |
| “I will read the form guide”                 | Communicates an intended next step          |
| A structured request to read `docs/forms.md` | Asks the application to perform a file read |

The model still has not opened the file merely by generating the request. Something outside the model has to interpret it and execute the allowed operation. That is where tools enter the loop.

## A tool turns a request into an actual operation

A **tool** is a callable capability exposed by the application. It has inputs, performs an operation, and produces a result.

The application describes the capability to the model: its name, what it does, and the arguments it accepts. For a file reader named `read_file`, that might be a `path` argument containing text and a result containing file text or an error. The model can request that defined capability; inventing an operation name does not make it available.

A writing tool changes a file. A command tool runs a process and reports its outcome. They are not interchangeable simply because all are called tools.

Suppose the agent wants to read the form's documented behavior. This is a schematic exchange; names and request formats differ between applications:

```text
Model requests:
  read_file(path="docs/forms.md")

Application performs:
  Check whether this path is allowed.
  Open the file and read its contents.

Tool result:
  # Form behavior
  A failed save must keep the entered title for retry.
  Only a successful response confirms the saved title.
```

Notice the division of work. The model chose an operation and arguments. The application performed the filesystem access. The tool result contains evidence from a file, not another guess about what the file probably says.

The application then prepares another model input, including that result and the relevant earlier task. The model can now use the documented behavior to decide what to inspect next.

```text
Task and available capabilities
              |
              v
       Model requests a read
              |
              v
     Application reads the file
              |
              v
     Result enters the next input
              |
              v
    Model chooses the next response
```

It might request the editor implementation and then its caller. Reading `docs/forms.md` establishes the intended contract; it does not establish the actual cause of the failure. The implementation might clear an input too early, replace state on an error, or destroy the editor. The agent must retrieve evidence that distinguishes those possibilities.

If the file does not exist or access is denied, the tool returns that outcome. The next response should account for it, not claim that the missing read succeeded. Likewise, “I ran the tests” is not a test result: look for the command or check actually executed, its status, and its output.

The repeated cycle of model responses, tool operations, and returned results is what makes this a working **agent**, rather than only a text conversation with a model. The surrounding program may automate that cycle, pause for approval, or impose other rules.

## A skill gives the investigation a repeatable procedure

File access tells the agent how it can retrieve evidence. It does not tell it which evidence makes a good investigation.

Suppose a team repeatedly handles bugs where user input disappears. Rather than write a debugging procedure from scratch for every task, it can package one as a **skill**: reusable instructions, with optional references, scripts, and examples.

In the Agent Skills format, the package could have this shape:

```text
form-debugging/
  SKILL.md
  references/
    failed-save-checks.md
  scripts/
    check-editor.mjs
```

The application can initially make only the skill's name and description available. For example:

```text
Name: form-debugging
Description: Investigate forms that lose user input or accept
unconfirmed values during saving.
```

That is enough to identify a potentially relevant guide, but it is not the guide itself. When activated, the agent reads the full `SKILL.md`. Its instructions could include:

```markdown
# Investigate a form-state bug

1. Reproduce the behavior through the rendered form.
2. Identify the owner of entered text and confirmed saved data.
3. Read the submission code and its caller.
4. Explain which operation loses or replaces the entered text.
5. After an authorized change, rerun the same failure and retry.

Read `references/failed-save-checks.md` when choosing the checks.
```

This is an illustrative instruction excerpt, not a complete installable skill. The procedure helps the agent choose and order its work. It does not read the source, change the editor, or run the check by itself.

The distinctions are now concrete:

- Reading the skill puts a procedure into context.
- A file tool retrieves the procedure's referenced document.
- An execution tool can run a permitted script.
- The returned results supply evidence that the procedure alone cannot supply.

A skill is therefore not simply a different name for a tool. It guides the use of capabilities. Bundling a script does not grant permission to execute it, and activating a skill does not make every step happen automatically.

The task could also proceed without a skill if the necessary procedure was supplied in the request. A skill's benefit is reusable, discoverable guidance—not a requirement to add a package around every small job.

## MCP connects capabilities supplied by another program

So far, the application has provided file access directly. Now suppose the reported bug lives in the team's issue tracker, including a reproduction the developer has not pasted into the conversation.

The application needs a route to ask the tracker for that information. **MCP**, the Model Context Protocol, defines a way for AI applications and capability-providing programs to exchange requests and results.

The participants have different jobs:

- The **host** is the AI application coordinating the work.
- Its **MCP client** handles the connection to a capability provider.
- The **MCP server** is the program exposing those capabilities through the protocol.

For this task, the server could provide a tool named `get_issue`. The client first asks which tools the server provides. The server returns their names, descriptions, and accepted arguments. The host uses those descriptions to make the capabilities available to the model.

When the model requests `get_issue` with ID `142`, the host routes that request through the client to the server. The server performs its retrieval and sends the result back through the same connection. The host can then include that result in the next model input.

```text
Model requests issue 142
          |
          v
Agent application / MCP client
          |
       MCP request
          |
          v
Issue-tracker MCP server
          |
   Retrieve issue from tracker
          |
          v
Reproduction returned through the client
          |
          v
Result included in the next model input
```

The server might run locally and contact the tracker using an ordinary service interface, or run remotely as part of the tracker integration. “MCP server” describes its role, not necessarily a separate machine.

The result could supply a detail that changes the investigation: the title is lost only when the editor remains open after failure. The model can now investigate whether the code that handles failure clears the text, or whether closing and recreating the editor loses it. It did not gain the information simply because the tracker was connected.

### Tools, resources, and prompts through MCP

MCP can expose more than operations. Its server-side categories include:

| Category | Example for this investigation  | What is supplied                                |
| -------- | ------------------------------- | ----------------------------------------------- |
| Tool     | `get_issue` with an issue ID    | A callable operation and its result             |
| Resource | A team's form-behavior document | Addressable information the client can retrieve |
| Prompt   | A “triage a form bug” template  | Reusable text for structuring an interaction    |

A server need not expose all three. These are protocol interfaces, not three kinds of model intelligence.

An MCP prompt can contain instructions, but that does not make it an Agent Skills folder. A skill packages a task procedure and supporting resources in its own format. MCP specifies a communication route through which another program can supply information or capabilities. They can cooperate or contain overlapping guidance without becoming the same thing.

Likewise, tools do not require MCP. The local file reader worked without it. MCP gives integrations a defined exchange mechanism; it does not decide the model's reasoning, automatically read every available resource, or make the returned content trustworthy.

## Reasoning helps choose what to do with the evidence

The agent now has the task, a procedure, documented form behavior, and a more precise reproduction. It still needs to relate those facts to the implementation.

Suppose the implementation reveals a clear operation around submission. The important questions are when it happens, whether failure reaches it, whether the caller performs another reset, and whether the editor is recreated. Moving the first clear operation found is not necessarily a complete diagnosis.

**Reasoning-capable models** can perform additional intermediate work before responding and, on supported models, between tool calls. Providers can represent this work using internal reasoning or thinking tokens.

That work can help the model compare possible causes, notice missing evidence, or choose the next read before proposing a change. It is still part of generating a response or tool request—not the same as executing a test. An internal conclusion that “this should fix it” has not exercised the form.

Some applications hide or summarize the model's working content. A short final patch can follow substantial internal work; a long visible explanation does not prove that a large amount of reasoning happened. A displayed thinking summary is not a complete execution record or a correctness certificate.

### What the reasoning levels change

A product may expose **reasoning effort** levels such as `low`, `medium`, and `high`. They direct how the selected model spends effort. They do not select a different repository, add a missing requirement, or give the model new facts.

**Higher reasoning effort does not mean better results.** Extra intermediate work can help with a difficult problem, but it can also elaborate a wrong approach or add complexity where a simple solution was enough. On a straightforward task, the result may be no better despite taking longer or costing more. Treat effort as a setting to evaluate, not a quality scale where higher is automatically better.

For the same investigation, the practical tradeoff is:

| Setting direction | What to evaluate                                                                       |
| ----------------- | -------------------------------------------------------------------------------------- |
| Lower effort      | Can a simple, well-specified task finish reliably with less time or token expenditure? |
| Medium effort     | Does it provide a useful balance for ordinary investigation and implementation?        |
| Higher effort     | Does additional work improve a difficult diagnosis enough to justify its time or cost? |

These are evaluation questions, not fixed outcomes. A difficult request can require more work at a lower setting than a trivial request at a higher setting. The labels are not universal token budgets or ranks of intelligence.

OpenAI's documented `reasoning.effort` labels include `none`, `minimal`, `low`, `medium`, `high`, `xhigh`, and `max`; supported subsets and defaults depend on the model. Anthropic documents `low`, `medium`, `high`, `xhigh`, and `max`, with model-dependent support. Its effort control is a behavioral signal affecting token expenditure across thinking when active, text, and tool calls—not a strict token budget. An identical label does not promise identical behavior across providers.

Additional internal work can use tokens and time before visible answer text appears. Providers account for that work differently. OpenAI, for example, documents internal reasoning tokens as occupying context and being billed as output; an output limit can be reached without a visible answer. Check the selected service's rules rather than infer them from the effort label.

For our editor, a vague request might say “clear after submission.” Raising effort does not supply the missing decision: does submission mean starting a request or receiving success? If it works from the wrong interpretation, extra reasoning can produce an elaborate rollback mechanism around the wrong behavior rather than a small, correct fix. More work is not evidence of more correctness.

Improve the contract and evidence first. Then compare the actual outcomes at different settings: does the failed save preserve the entered title, does retry work, and does the change stay within scope? Keep higher effort only when the improvement justifies its time or cost.

## The conversation grows; context has to be selected

Every read and check can add information to the ongoing task. **The model does not remember earlier conversation turns on its own.** To continue the task, the agent application supplies conversation history alongside the new message or tool result: earlier messages, tool requests, file results, and instructions.

The application can supply the whole history while it fits, but may select or summarize it as it grows. Some services store that history and let the application refer to it instead of resending every message. Either way, earlier information must be made available for the next response; conversation storage is not the model remembering the task by itself.

A **context window** limits the information the model can use during a response, including generated work under the provider's accounting. An **output limit** separately constrains how much it can generate. Having room to read a large document is not the same as having permission to generate an equally large answer.

Consider a fictional 500-token window, only to make the arithmetic visible:

```text
Instructions:                     120 tokens
Task and conversation:             80 tokens
Capabilities and previous results: 100 tokens
                                  ----------
Already included:                 300 tokens
Remaining before new output:      200 tokens

Next complete file result:        250 tokens
```

That result will not fit in full alongside the existing material, even before allowing for the next output. These are illustrative numbers, not a real model limit or measured tokenizer counts.

The application can retrieve a focused part, remove unnecessary material, or reduce earlier conversation to a summary. But selecting less information is useful only when it preserves what the task needs. Dropping the editor's caller could hide the operation that actually resets the form.

**Compaction** reduces or replaces earlier context so work can continue. A summary might preserve the failed-save contract, or accidentally lose it:

```text
Too vague:
Fix the editor so saving updates the title.

Useful task state:
On failure, confirmed saved data must stay unchanged.
The entered title must remain available for retry.
The editor and caller have been read; a reset path is being checked.
No edits are authorized yet.
```

Those summaries lead into different tasks. A summary is not automatically lossless memory, and a larger window does not automatically resolve conflicting descriptions.

Persistent notes are similar: they are stored information that helps when the application loads it again. They can be stale, and they do not replace reading the current files. A handoff should distinguish what was observed, what is still a hypothesis, what changed on disk, and what remains to be done.

There is no universal token threshold at which quality suddenly collapses, nor a rule that every long conversation should be reset. Relevant, organized context can remain useful; obsolete attempts and contradictory instructions can make even a short context misleading.

## Project instructions keep recurring guidance available

The task began with instructions supplied by the application. Where can recurring project rules come from without retyping them for every request?

Common conventions include **`AGENTS.md`** and **`CLAUDE.md`**: Markdown files that an application can discover and include in model input. They are not additional learned knowledge or executable permission rules.

For the form investigation, a small project guide might contain:

```markdown
## Form changes

Keep entered proposals separate from confirmed saved data.
A failed save must preserve the proposal for correction or retry.

When changing submission behavior, read `docs/forms.md`.
Do not add dependencies or commit unless the task permits it.
```

Loading this text supplies the rule and the pointer. It does not supply the entire forms document. The next file read still has a purpose: obtaining its detailed contract or procedure.

Which files are discovered depends on the application. Codex documents a startup instruction chain through global guidance and the project path to its working directory. Claude Code documents ancestor instructions, on-demand nested loading, and version- and configuration-dependent `AGENTS.md` support. Do not assume identical filename recognition or precedence across tools.

Use current documentation and available loading diagnostics to establish what actually loaded. A filename existing on disk—or the model saying it knows the rules—is weaker evidence than the application's instruction-loading record.

### Hygiene prevents the guide from misleading the task

Start by putting guidance at the right scope. **Global or user-level files should contain standing defaults, not a handbook for every possible task.** They supply personal guidance across projects, so their contents can enter conversations that have nothing to do with the current repository.

Ask: “Would this guidance help during an unrelated task in another project?” Communication preferences and boundaries such as preserving unrelated work usually pass that test. This project's build commands, file paths, architecture, and form contracts do not; keep those in project guidance or project documentation.

Then choose how to package the guidance:

| Placement                               | What belongs there                                                                              | Example                                                                                                         |
| --------------------------------------- | ----------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| Directly in the global instruction file | Brief, durable defaults and boundaries that apply across projects                               | Keep answers concise; preserve unrelated work; commit or publish only when authorized                           |
| Linked reference                        | Detailed standards or facts, with a clear condition for reading them                            | “For coding tasks, read `~/CODING.md`”                                                                          |
| Skill                                   | Reusable task-specific procedures or expertise, with optional references, scripts, or templates | Investigate a form bug: reproduce it, trace the state changes, make a bounded fix, and verify failure and retry |

A small global guide could look like this:

```markdown
- Preserve unrelated work.
- Commit or publish only when explicitly authorized.
- For coding tasks, read `~/CODING.md`.
- For bug investigations, use the debugging skill.
```

Here, `~` is shorthand for your home directory. The first two rules belong in the standing context. The last two route the agent to details when the task calls for them; they do not copy the entire coding guide or debugging procedure into every conversation.

A long reference is not automatically a skill. A reference explains rules or facts; a skill packages how to perform a task and the expertise needed for it. The skill can link to an existing reference rather than duplicate it. Skills can be personal and useful across projects, or specific to one project.

A pointer should say **when to read**, not merely list a file. Whether it actually saves context depends on the application's loading behavior, explained in the next section. Eagerly importing all the linked material would defeat the purpose.

Placement alone does not prevent stale or conflicting instructions. Suppose an old nested guide says “clear input as soon as submission starts,” while the root guide says “preserve input on failure.” The application may include both. The model now has conflicting guidance about the exact behavior under investigation.

Or suppose the guide names a check that belonged to a deleted package. The agent can spend its effort troubleshooting obsolete instructions instead of checking the form.

Maintain instruction files and their references as documentation:

- Keep durable behavior, useful commands, and non-obvious constraints.
- Make rules concrete enough to check, rather than stacking “be careful” or “use best practices.”
- Remove obsolete paths and commands; resolve conflicting root, nested, and personal guidance.
- Avoid duplicated copies of the same policy that can diverge.
- Keep the current reproduction, temporary logs, and unfinished work in the task or handoff.

A repeated failure may justify a reusable rule. It does not justify appending every correction to a permanent file. The failed-save rule is durable; the output from today's failed check is not.

## Progressive disclosure keeps detail available without loading it all

The skill already demonstrated selective loading: discover its name and description, load its procedure when relevant, then retrieve a reference when needed.

That pattern is **progressive disclosure**. It keeps detail available without putting all of it into every model input.

For the current task:

```text
At the start:
  Project rule + where to find form guidance

When submission work is identified:
  Read the form contract and debugging procedure

When the failure check is chosen:
  Read its relevant setup or example
```

A deployment task does not need the form-testing reference merely because both live in the same repository. A form task should not have to guess where to find it.

The distinction is about loading, not just folder organization. Splitting a large guide into ten files does not reduce context use if all ten are imported immediately.

A plain “read this when changing forms” pointer depends on the agent following it. An application can also support path-scoped rules that load for matching files. An eager import loads another file with the importing instructions; Claude Code documents that behavior for `@path` imports. These mechanisms should not be assumed equivalent.

Keep essential boundaries in the small core and put detailed procedures behind clear relevance cues. Do not hide the failed-save rule in an obscure document, but do not preload every browser-testing example for tasks that never touch a form.

## A better starting point can beat more steering

The agent may now propose a change. Before authorizing it, compare its explanation with the contract and evidence.

If the approach is sound but incomplete—for example, the diagnosis is supported but the agent forgot to check retry—steering is useful. Point out the missing outcome; the existing investigation can still support the work.

A wrong underlying model is different. Suppose the agent treats every keystroke as confirmed saved data. It starts adding rollback state and replacing components to make that assumption work. Repeated “no, keep the title” messages can produce more patches around the wrong design.

A correction adds to the conversation; it does not erase what came before it. The next response can still receive the wrong assumption, the plan built around it, and several patch attempts alongside the correction. That older material can keep influencing the next proposal.

Starting a fresh attempt with better guidance can be more effective than continuing to steer it. Compare:

```text
More correction after the fact:
No, don't clear it. Keep that value.
Undo the other reset too. Make rollback preserve the input.

Better starting guidance:
Entered text and confirmed saved data are separate values.
On failure, the saved value stays unchanged and the proposal stays
available for retry. Trace the real reset path before choosing a fix.
```

The improvement is both corrected framing and cleaner context. The next attempt receives the contract and a focused handoff without replaying the discarded plan and patch attempts. An empty conversation with the same vague request would not fix the problem.

Preserve a focused handoff: established facts, rejected approach, current diff, remaining uncertainty, and authority. Do not present an earlier guess as a confirmed cause.

A new chat does not undo filesystem changes or stop a process. Inspect and preserve the current work, decide what to retain or discard, and stop an old writer before another attempt edits the same files.

Restart because the approach or task state is unusable—not just because the conversation is long. Likewise, time already spent is not a reason to keep repairing an approach that no longer fits the task.

## An edit is a proposal until its result is checked

Once the cause and approach are understood, editing can be authorized. A routine request can also authorize investigation through a bounded local fix from the start; separate approvals are not mandatory for every arrow in the loop.

Either way, an edit is an actual file change, not proof that the interaction now works. The agent uses a writing capability, then runs relevant checks through another capability. Their results return as new evidence.

For the failed-save task, the outcomes are concrete:

| Interaction                               | Required observation                                                                |
| ----------------------------------------- | ----------------------------------------------------------------------------------- |
| Submit the entered title                  | The request contains the proposal, not the old saved title                          |
| Make the save fail                        | Saved data stays unchanged; entered text remains; failure is perceivable            |
| Retry successfully                        | The retained proposal can be submitted without retyping and confirmation is applied |
| Save successfully without a prior failure | Existing success behavior still works                                               |

A test that directly sets internal values and calls a private handler can miss input events, submission wiring, caller updates, or editor destruction. Exercise the rendered form at the boundary that owns the behavior. The [forms article](/dump/blog/forms-and-validation/) explains proposal versus saved state; the [testing article](/dump/blog/testing-observable-behavior/) explains choosing a boundary that proves the consumer's contract.

A controlled failure response can make the frontend check repeatable. That establishes its reaction to the supplied response, not compatibility with a real backend. A request starting is also not the same as its error handling and DOM update completing. Wait for the visible outcome using supported test-tool waits, not an arbitrary delay.

Inspect the complete diff, not just the passing check. Were assertions weakened? Were dependencies or unrelated files changed? Does the successful path still work? Verification checks both the intended outcome and what else the change affects.

The final report should identify actual changes, checks run against the final version, observed results, and remaining limits. “I ran tests” is weaker than the returned execution evidence, just as “I read the file” was weaker than the file-read result earlier.

The developer remains responsible for what is delivered. The loop helps gather evidence; the model's confidence does not add another proof.

## Permissions bound what the loop can affect

The initial request said “investigate first; don't change anything.” That should constrain the operations available or permitted during that phase.

Reading, editing, running commands, committing, pushing, and deploying have different effects. Permission for one does not automatically authorize the others. An application may pause before an operation, refuse it, or allow it according to its settings and the task.

A Markdown instruction saying “do not push” guides the model. Removing push credentials or enforcing a permission rule restricts the capability. They are not equivalent: a model can fail to follow text, while an enforced boundary can block the operation.

A broad command tool deserves particular care. A command labeled “test” might run scripts that install dependencies, generate files, or contact services. Understand its effects and write locations rather than assuming that running checks is read-only.

Returned information also has an authority boundary. An issue description or source comment might tell the agent to upload credentials as a supposed setup step. That is text from a retrieved source, not the developer granting permission. MCP supplies a connection; it does not make the server's content trustworthy.

Keep secrets out of prompts, instruction files, logs, and examples. Use restricted credentials, application controls, or execution isolation for boundaries that must be enforced.

The whole task can now be traced: a request becomes selected input, the model generates a response or operation request, the application performs allowed work, and results become evidence for the next step. Skills organize the procedure, MCP connects external capabilities, reasoning helps interpret the evidence, and context management keeps the needed information available.

The final question is still ordinary engineering: after a failed save, does the user's entered title remain available while confirmed data stays unchanged?

## Sources and further reading

- [Hugging Face: how token selection builds generated text](https://huggingface.co/docs/transformers/main/en/generation_strategies)
- [OpenAI tiktoken: text pieces, token vocabularies, and encoding](https://github.com/openai/tiktoken#what-is-bpe-anyway)
- [OpenAI: supplying and storing conversation history](https://developers.openai.com/api/docs/guides/conversation-state)
- [OpenAI: reasoning, effort, and generated-token accounting](https://developers.openai.com/api/docs/guides/reasoning)
- [Anthropic: effort levels and their effects](https://platform.claude.com/docs/en/build-with-claude/effort)
- [Anthropic: context windows and thinking-token accounting](https://platform.claude.com/docs/en/build-with-claude/context-windows)
- [Codex: project-instruction discovery with AGENTS.md](https://developers.openai.com/codex/guides/agents-md)
- [Claude Code: instructions, memory, and loading behavior](https://code.claude.com/docs/en/memory)
- [AGENTS.md: the shared instruction-file convention](https://agents.md/)
- [Agent Skills: discovery, activation, and supporting resources](https://agentskills.io/home)
- [MCP: clients, servers, tools, resources, and prompts](https://modelcontextprotocol.io/docs/learn/architecture)
