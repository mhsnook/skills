---
name: comment-review-c
description: 'Review the code comments in a batch of work — a pull request, a branch, or the current diff — asking of each whether it is true and useful to someone who cloned the repo with no history, then checking it against what makes a comment good or bad: restatements, references to PRs and issues, and padding go; footgun warnings and signposts stay. Triggers: review the comments in this PR, check the comments before I push, are these comments over-specified, too many comments in this diff, comment review, do these comments still match the code. For a whole codebase rather than one change, use the spec-debt skill.'
license: MIT
---

# Comment review

Code comments that explain where and when we did something tricky, or a bit
different, make everyone happier and smarter. But excessive code comments cause
specification debt, context bloat, and reader strain.

**Do a pass over all the code comments in this batch of work, including the ones
adjacent to or related to the code we touched, asking of each: is this comment
true and useful to someone who cloned the repo with no history?** A function
whose body changed brings its doc comment into scope even if the comment itself
is untouched. Read the project's README, architecture doc and the file headers
first, or "restates a doc" is not a question you can answer.

That one question does most of the work, so run it first and run it on
everything. Every comment should read as if the code has always existed. If a
comment would be false or meaningless without the diff beside it, rewrite it to
say what the thing does, or cut it.

It catches more than the changelog rule below, and it catches a subtler thing. A
comment written while making the change describes the delta, because the delta is
what was in the writer's head — and the reader has no before. The tell is a
sentence about a transition:

```ts
// Counted rather than named: "the Sections meet the total" left the writer
// to go and check.

// Rendering the open ones alone threw the transcript away.
```

Neither looks like a changelog entry. Both are unreadable without the diff. Watch
for *now*, *instead of*, *used to*, *rather than*, *no longer* — and for any
sentence whose subject is a decision rather than the code.

**One thing the fresh clone will not tell you: whether the comment still matches
the code.** For every comment whose subject this change touched, check that it
still describes what the code does — a renamed parameter, a changed count, a
deleted branch, a guarantee the new code no longer provides. That is a defect
rather than a matter of taste, and a diff-scoped review is the cheapest place to
catch it.

## Then, what makes a comment good or bad

- comments aren't for commit-messages or change logs (unless the code is
  genuinely in a middle-state that should be resolved soon)
- comments aren't places to reference PRs or issues outside the code
- comments are relevant for future readers to understand the code, the contracts
  others can depend on, potential future footguns and departures from standard
  usage
  - remove comments that document bog-standard usage
  - remove comments that only restate the obvious highlighted words in the first
    couple lines below, such as `const offerKinds = ['reference', 'quote']` --
    this makes it clear we are defining kinds of offers, and what the two kinds
    are. A comment explaining this will help no one. similarly: when the code has
    an error message or UI content or logging message that the comment restates —
    but read the whole string first, because a comment adding any fact the string
    lacks is a keep
- comments don't use a 7-line explanation when 2 lines will do
- sometimes a comment can just say "// <package> <version> <purpose>": an
  unfamiliar function in a zod schema might become fully clear with just 4 words:
  "// zod 4 recursive schema"
- comments don't have to restate what is already clearly spelled out in a
  site-wide readme, architecture doc, top-level document comment or sibling
  module; a single reference at the top of the file will do, or very brief,
  "require the signal, per architecture.md p4"
- comments don't state a rule more strongly than they know it — `never`,
  `always`, `guaranteed`. Name the mechanism instead ("checks the hostname too,
  so a deployed domain fails it"), unless the absolute is reporting something
  that did not happen, which is the sense it serves
- A doc comment on an exported symbol says what the thing is and how to use it.
  An inline comment says why this line is written the odd way it is. A "why" in
  a doc comment is usually a commit message that escaped.
  - **the first sentence is a verb phrase about the thing.** "Keeps the Chat
    pinned to the bottom" passes. "The Chat opens on the last thing said" is a
    claim about behaviour with the subject swapped, and it is how a docstring
    gets three paragraphs deep without ever saying what the hook returns. Check
    that the doc comment names what the thing returns, or what the boolean
    selects, before it says anything else
- a comment explaining *why* cites a constraint that still holds — a browser
  behaviour, an invariant, a boundary — and not a decision someone made. "Scroll
  positions round" is a constraint. "Underlining a passage reads as emphasis" is
  taste being defended to a reviewer, and it stops being interesting the day the
  PR merges
- comments are written in the code's register, not the architecture doc's. A
  project doc argues; a docstring for a 12-line hook states. A bolded thesis
  sentence at this altitude is voice that leaked downhill
- Keep a comment if removing it makes a plausible future edit wrong. Cut it if it
  records a decision where the fork not taken has no defenders in the code. A
  rejected alternative is a keep when the reason is a mechanism someone could
  walk into — "re-pinning on every render forces a layout pass" — and a cut when
  the reason is taste.

## The signpost test

A signpost repeats the code on purpose — it marks a boundary, breaks up a long
function, and lets an eye scanning the file find its place. It works like
underlining, so judging it as a fact cuts it every time. The test is
**navigation, not novelty**: a label on a branch, a section, or one of several
sibling functions navigates; a gloss on a single self-evident line does not.

Scrutiny scales with length. A seven-line comment restating the code costs seven
lines of reading and a maintenance obligation; a one-liner costs a line. **"The
code below already says this" is not sufficient grounds to cut a one-liner** —
only the checklist items above are.

## Before deleting

If you're worried about losing knowledge, ask whether it should go in an
architecture doc, the readme, an issue, or a comment on the PR. Say where it
went — a cut whose knowledge moved is still a cut.

Most deletions here are wins, because the knowledge moved somewhere better or
the code stopped needing it. But losing a footgun-avoider or a signpost costs a
reader something that never shows up in the diff, so the count is not the score,
and cutting a third of the comments is not self-evidently working.

## Report

Group the cuts and shortens that share a fix rather than listing every item, and
state the denominator — "9 verdicts across 74 comments", because nine findings
on their own read as a clean bill of health. List separately the ones judgment
decided rather than a test. Then ask whether to apply.
