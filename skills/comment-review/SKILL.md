---
name: comment-review
description: 'Review the code comments in one change — a pull request, a branch, or the current diff — for the three ways a comment goes wrong: it says more than it knows, it has drifted from what the code now does, or it buries a project-wide rule where nobody will read it. Reports cut, shorten, reword and keep verdicts grouped by pattern, then offers to apply them. For a whole codebase rather than one change, use the spec-debt skill instead. Triggers: review the comments in this PR, check the comments before I push, are these comments over-specified, too many comments in this diff, comment review, do these comments still match the code.'
license: MIT
---

# Comment review

Comments that explain where and when we did something tricky, or a bit
different, make everyone happier and smarter. Excessive comments cost the
opposite: specification debt, context bloat, reader strain. This skill reads one
change and tells the two apart.

It runs at PR time, in one context, with the whole diff visible. That is what
makes it cheap, and it is also what makes it the right moment — a comment and
the code under it diverge *in a diff*, and this is the last point where the two
are on screen together.

## Extent

Default to the current branch against its base: `git diff origin/main...HEAD`.
Take an explicit target if given — a PR number, a branch, a path.

In scope are the comments **in the changed hunks, and the comments adjacent to
or about the code the change touched**. A function whose body changed brings its
doc comment into scope even if the comment itself is untouched, because that is
where drift lives.

**Read the project's own documents before judging anything**: `README`,
`CLAUDE.md`, `AGENTS.md`, anything under `docs/`, and the header comment of each
file in the diff. Without that inventory a comment restating a documented rule
looks like a keep, when it is the clearest cut on the list.

## The three failures

### Drift — the comment and the code disagree

The only one that is a defect rather than a matter of taste, so it goes first,
and a change-scoped review is where it is cheap to catch. Check every comment
whose subject the diff touched: does it still describe what the code does? A
comment naming a parameter that was renamed, a count that changed, a branch that
was deleted, or a guarantee the new code no longer provides is actively
misleading someone, and reporting it is worth more than every cut below.

### Over-specification — the comment says more than it knows

`never`, `always`, `every`, `the only way`, `guaranteed`, `impossible`. Each
flattens three meanings into one word, and only the third is served by it:

| Meaning | Rewrite as | Example |
|---|---|---|
| **We want this not to happen** | say what we do instead, or what breaks | "Calling this on the server would break X, which assumes Y" |
| **We are certain it cannot happen** | name the mechanism that makes it so | "isDevEnvironment() checks the hostname too, so a deployed domain fails it" |
| **It did not happen** | keep the absolute — this is the sense it serves | "an empty collection means the view was never populated" |

`so X will Y` is the workhorse: it states a theory of how the thing works, and
it is available whenever the meaning is one of the first two.

This matters more than tidiness, because **a law states an outcome and a
description carries a mechanism.** A reader can check a mechanism against their
own case; there is nothing to do with an outcome but obey it.

Do not strip an honest hedge. Weakening an overstated rule is the job;
manufacturing confidence is the opposite of it.

### Invisible spec — the rule is buried where nobody reads it

A claim that constrains other files, sitting in a function comment. Nobody
outside that function will ever see it, so it constrains the codebase without
being read.

Judge it by how far it reaches:

| How far it reaches | Where it belongs |
|---|---|
| Nothing — the code, the type, or the next sentence already says it | cut |
| The lines below, or one named sibling | leave it as a comment |
| Several functions in the file | the file header |
| Several files in the folder | the module doc |
| Across modules | the architecture doc or README |

A one-to-one bridge stays a comment — a note on one function naming one function
in another file is the right shape, even across a file boundary. Promoting it
would inflate a module doc with something exactly two functions care about.

**Promotion is not the success case.** A claim that turns trivial once written
out at project scope is a cut, and the report should say so.

## Cut list

**A comment is not a commit message or a changelog.** "Previously this used
`useMutation`, changed in the migration to collections" belongs in history. The
exception is code genuinely in a middle state that should resolve soon — and
that comment should say what would end it.

**A comment is not a place to reference a PR or an issue.** "See #412 for why"
sends the reader off-site to a thread that has moved on. Put the reason in the
comment, or in a doc, and cite the doc.

**Cut comments documenting bog-standard usage.** A `useEffect` cleanup, a
standard zod field, a `map` over an array — the library's own docs cover these
better than a local comment can.

**Cut comments restating a single self-evident line.**

```ts
// the two kinds of offer we support, reference and quote
const offerKinds = ['reference', 'quote']
```

The line already says we are defining kinds of offers and what the two are.

**Cut comments restating a string the code already contains** — but read the
whole string first. A comment paraphrasing an error message, a UI label, or a
log line adds a copy to keep in sync and no information. A comment adding *any*
fact the string lacks is a keep:

```ts
// First scoring review for this card today.
console.log(`Scoring pass: creating review`, { pid, direction, score, stage })
```

The log line says a scoring review is being created. It does not say this is the
first one **today**, for **this card**, which is the condition that selected the
branch.

**Cut what the project already says out loud.** A claim spelled out in the
README, an architecture doc, a file header, or a sibling module does not need
restating. One reference carries it: `// requires the signal, per ./docs.md §4`.

## Shorten list

**Two lines where seven are written.** Cut the padding, keep the claim.

**Sometimes four words is the whole comment.** An unfamiliar construct can
become clear with `// <package> <version> <purpose>` — `// zod 4 recursive
schema` does what a paragraph was doing.

**A long comment on a genuinely dense routine is allowed.** The distinction is
padding versus density: cut words that repeat, keep words that carry. If
shortening would lose a condition, a number, or a qualifier, it is density.

## What each carrier is for

Getting this wrong produces comments that are individually fine and collectively
useless, and the fix is a move of a few lines rather than a deletion.

- **A doc comment on an exported symbol** says what the thing is and how to use
  it. It is written for someone who will never read the body.
- **An inline comment** says why *this line* is written the odd way it is.
- **A file header** says what the module is for and cites the doc that governs
  it. A file with twelve fine local comments and no header makes every reader
  re-derive the context; adding one is the most common improvement here, and it
  is additive — leave the local comments where they are.

A "why" in a doc comment is usually a commit message that escaped.

## Two tests before you cut

**The delete test.** Remove it. Does anything become unknowable?

**The future-edit test.** Keep it if removing it makes a plausible future edit
wrong. Cut it if it records a decision where the fork not taken has no defenders
left in the code — the alternative it argues against is one nobody is going to
try.

## Orientation is not information

A signpost repeats the code on purpose. Its job is not to state a fact, it is to
mark a boundary, break up a long function, and let an eye scanning the file find
its place. It works like underlining. Judged as a fact it loses every time,
because it was never claiming one.

```ts
// Outer component handles auth check
function ReviewPageSetup() {
```

Nothing here is new — and keep it. It tells a reader arriving in a 600-line
route file which of the two components they are in, which no identifier does.

The test is **navigation, not novelty**. And scrutiny scales with length: a
seven-line comment restating the code costs seven lines of reading and a
maintenance obligation, a one-liner costs a line. **"The code below already says
this" is not sufficient grounds to cut a one-liner** — only the harmful
categories above are.

## Before deleting, ask where it should go

If cutting would lose knowledge, it belongs somewhere:

- a module doc or the architecture doc, when other files need it
- the README, when a newcomer needs it
- an issue, when it is work rather than knowledge
- a comment on the PR, when it is about this change rather than this code

A cut whose knowledge moved is still a cut. Say where it went.

## Report, then offer to apply

Order the report so the expensive findings arrive first:

1. **Drift** — each one naming the comment, the code that moved, and which is
   now wrong.
2. **Invisible specs** — the claim, its reach, and the document it should move
   to, with the sentence it would add written out. A conflict with what that
   document already says is much cheaper to see before the edit than after.
3. **Patterns, batched.** Group the cuts and shortens that share a fix — "six
   comments restate a zod field's own rule" — because applying goes by pattern,
   not by item.
4. **The torn ones**, listed individually. The ones where judgment decided it
   rather than a test, and the only ones needing a human to look at each.
5. **Counts**: comments in scope, and the verdict split. State the denominator.
   "9 verdicts across 74 comments" is a usable report; nine findings on their own
   read as a clean bill of health.

Then ask whether to apply. On approval, apply the cuts, shortens and rewords,
and write the promotions into the documents named. Report anything that could
not be applied cleanly.

## Boundaries

**Will not:**

- Edit anything before the report has been read and the offer accepted.
- Propose a file split, a new module boundary, or a move between files. It
  classifies comments against the structure that exists.
- Cut a comment that explains why non-obvious code exists, names a contract
  other code depends on, or stops a reader from making a specific mistake.
- Strip an honest hedge, or an absolute that is reporting something that did not
  happen.
- Trim for tidiness. Every deleted comment is *probably* a win — because the
  knowledge moved somewhere better, or the code stopped needing it. But losing a
  footgun-avoider or a signpost is a real cost that never shows up in the diff,
  so the count is not the score, and a pass that cuts a third of the comments is
  not self-evidently working.

## Related

For a whole codebase rather than one change — reach tests grepped rather than
inferred, contradiction hunting across the doc inventory, and a resumable ledger
— use the **spec-debt** skill. This skill is its PR-time counterpart and applies
the same judgment; spec-debt's `references/reduce.md` is the audit-scale
statement of it.
