---
name: comment-review-c
description: 'Trial variant C of three for reviewing the code comments in one change — a pull request, a branch, or the current diff — checking first whether comments still match the code the change moved, then cutting changelog comments, off-site references, restatements and padding while keeping footgun warnings and signposts. Variants A, B and C are being compared in real use, so run the one the user names rather than auto-selecting between them; if the user asks for a comment review without naming a variant, ask which. For a whole codebase rather than one change, use the spec-debt skill.'
license: MIT
---

# Comment review — variant C

Variant A's checklist, with three changes: drift goes first, the signpost
exemption gets a test instead of a mention, and the closing no longer says every
deletion is a win.

Code comments that explain where and when we did something tricky, or a bit
different, make everyone happier and smarter. But excessive code comments cause
specification debt, context bloat, and reader strain.

**Review all code comments in this batch of work, including comments adjacent to
or related to the code we touched.** A function whose body changed brings its doc
comment into scope even if the comment itself is untouched. Read the project's
README, architecture doc and the file headers first, or "restates a doc" is not
a question you can answer.

## First, does it still match the code?

For every comment whose subject this change touched: does it still describe what
the code does? A renamed parameter, a changed count, a deleted branch, a
guarantee the new code no longer provides. This is a defect rather than a matter
of taste, it is the one thing a diff-scoped review can catch cheaply, and it is
worth more than every cut below.

## Then, the checklist

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
- Keep a comment if removing it makes a plausible future edit wrong. Cut it if it
  records a decision where the fork not taken has no defenders in the code.

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
