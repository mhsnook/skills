# Pass A — reduce

The cheap pass. Runs on one comment and the few lines under it, with no greps
and no cross-file reasoning, so it parallelises one agent per file.

It runs first for two reasons. It cuts the volume the expensive passes have to
reach-test, and it separates claims that were sharing a comment — Pass B asks
for one altitude verdict per claim, and a seven-line comment carrying three
claims plus a changelog entry has no single answer.

**Every deleted comment is a win.** Either the knowledge went somewhere more
appropriate, or the code turned out to say it already. Count the deletions.

## What a good comment does

Comments that explain where and when we did something tricky, or a bit
different, make everyone happier and smarter. Keep every comment that:

- explains why non-obvious code exists, or why code that looks redundant is not
- names a contract other code depends on
- warns about a footgun, or a departure from the library's standard usage
- records a decision whose reasoning would otherwise be lost

Excessive comments cost the opposite: specification debt, context bloat, reader
strain. The rest of this page is how to tell the two apart.

## Cut list

**A comment is not a commit message or a changelog.** "Previously this used
`useMutation`, changed in the migration to collections" belongs in history, not
in the file. The exception is code genuinely in a middle state that should
resolve soon, and that comment should say what would end it.

**A comment is not a place to reference a PR or an issue.** "See #412 for why"
sends the reader off-site to a thread that has probably moved on. Put the
reason in the comment, or put it in a doc and cite the doc.

**Cut comments documenting bog-standard usage.** A `useEffect` cleanup, a
standard zod field, a `map` over an array — the library's own docs cover these
better than a local comment can.

**Cut comments restating the obvious.** Given:

```ts
const offerKinds = ['reference', 'quote']
```

a comment saying we are defining kinds of offers, and there are two, helps
nobody. The line already says it.

**Cut comments restating a string the code already contains.** When the code
holds an error message, a UI label, or a log line, a comment paraphrasing it
adds a second copy to keep in sync and no information.

**Cut what the project already says out loud.** A claim spelled out in the
site-wide readme, an architecture doc, a top-level file comment, or a sibling
module does not need restating here. One reference at the top of the file
carries it: `// requires the signal, per ./docs.md §4`.

This is where duplicates get caught, and it is cheap because it is one
question about one comment against the doc inventory already in context — not
a pairwise sweep.

## Shorten list

**Two lines where seven are written.** Cut the padding, keep the claim.

**Sometimes four words is the whole comment.** An unfamiliar construct can
become clear with `// <package> <version> <purpose>`:

```ts
// zod 4 recursive schema
```

That does what a paragraph was doing.

**A long comment on a genuinely dense routine is allowed.** A tuned inner loop,
or the rare ball of wax that has to live in one method, earns a long comment —
and this pass leaves it alone. The distinction is padding versus density: cut
words that repeat, keep words that carry. If shortening would lose a
condition, a number, or a qualifier, it is density.

## The file header

Additive, not a relocation. Leave the local comments where they are — a file
whose comments read linearly down the page, building understanding as you go,
is the good case, and hoisting them upward makes it worse.

What is often missing is a header. A file with twelve fine local comments and
no header makes every reader re-derive the context. Give it one that says what
the module is for and cites the relevant doc and section.

That also does some of Pass B's work early: once the header carries the
reference, the individual comments stop needing to.

`enumerate.mjs` reports `filesWithoutHeader`, so this is a work list rather
than a judgment call.

## Before deleting, ask where it should go

If cutting a comment would lose knowledge, it belongs somewhere:

- a module `docs.md` or the project architecture doc, when other files need it
- the readme, when a newcomer needs it
- an issue, when it is work rather than knowledge
- a comment on the PR, when it is about this change rather than this code

Record the destination in the ledger's `would_write`. A cut whose knowledge
moved is still a cut.

## What this pass does not do

- **No greps.** Reach is Pass B's question. Guessing at it here produces
  altitude verdicts with no evidence behind them.
- **No promotions.** Proposing that a claim move into a project doc needs the
  reach test first.
- **No file structure.** Never propose splitting a file, moving a function, or
  adopting a colocation convention.
- **No hedging removal.** Weakening an overstated rule is Pass B's modality
  work. Stripping an honest "may" or "probably" is the opposite of the job.
