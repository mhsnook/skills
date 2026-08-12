---
name: cut-comments
description: 'A final pass over a PR, branch, or set of files that makes every comment earn its line. Not a deletion sweep: comments are cut, compressed to their load-bearing clause, moved to their one true home, or made unnecessary by renaming the code. Run it at the end of a PR before merge, or as a CI job in report-only mode. Triggers: cut unnecessary comments, comment pass, trim the comments, comment cleanup, decomment, make the comments earn their keep.'
license: MIT
---

# Cut comments

## The test

A comment earns its line only if a competent maintainer, without it, would
break something or waste real time. Apply that test to every comment in
scope. Everything that fails it gets one of five fixes — pick the one the
code wants, not always the delete:

1. **Cut** — the comment says nothing the code doesn't.
2. **Compress** — one clause is load-bearing; keep it, cut the elaboration.
3. **Relocate** — the fact is true, but this is not its home (see below).
4. **Rename** — the comment is compensating for a bad name. Fix the name,
   then delete the comment. Prefer this whenever it works: a name is read
   every time, a comment only sometimes.
5. **Improve** — occasionally a surviving comment is also *unclear*. You are
   already here; make it say the invariant plainly.

Expect to roughly halve the comment volume in a comment-heavy codebase, not
zero it. If your diff is all deletions and no rewrites, you are running a
cruder pass than this one.

## What tends to fail the test

- **Echoes** of the name, the type, or the adjacent line. Prop and field
  docs that restate the declaration.
- **Consequence chains.** State the mechanism; cut the "so that /
  otherwise / which would mean" that follows. If the next line *is* the
  consequence, the clause describing it is an echo.
- **Imagined failures.** The narrative of what would go wrong keeps only
  its causal facts; the reader can run the scenario themselves.
- **Design philosophy** that a design doc, ADR, or architecture file
  already owns. Cite it if the code depends on it; never restate it.
- **Platform education** — what the library call, hook, or CSS feature
  does in general. That is the platform docs' job.
- **Alternatives not taken** ("X rather than Y", "unlike Z") — *unless* Y
  is the edit a future maintainer would plausibly make. A warded-off trap
  survives; a design diary does not.
- **Restated contracts across a boundary.** The callee documents its
  contract; the caller documents its use; neither narrates the other.
- **Docs on private, same-file code** whose one call site is visible on
  the same screen. The same doc on an *exported* symbol may survive: the
  caller there can't see in.

## What tends to pass it

Almost every survivor is one sentence naming a non-obvious mechanism,
invariant, or trap:

- Ordering and event-timing hacks (why mousedown not click, why the blur
  check, why this handler stops propagation).
- Invariants the code cannot show (an ID format, "pushed before its
  children so a subtree is one contiguous run", why a lookup goes against
  the rendered set instead of the source data).
- The "because" on a surprising shape (a function where a constant was
  expected, a guard that looks redundant but isn't).
- The behavioral contract of an optional public parameter — what omitting
  it means.
- A citation that *replaces* an explanation: "not counted again here —
  architecture.md §4."

## One home per fact

Every fact lives in exactly one place, at the highest level that owns it:
design doc > module header > declaration > line comment. Lower homes cite
upward instead of restating. If two files carry the same rationale, keep it
in the one that enforces it and cut the other. Content can move as part of
this pass — a fact stranded on a state variable may belong on the function
that uses it.

## Judgment, not pattern-matching

The lists above are evidence, not law. The test is the law. A comment that
looks like an "echo" but encodes a real invariant stays; a comment that
looks like a "trap warning" but wards off nothing goes. When genuinely
unsure, keep the comment — a false deletion loses information, a false keep
costs a line.

Preserve the codebase's voice. Survivors should still read like this
project wrote them, only terser. Do not normalize a distinctive comment
style into generic boilerplate, and do not add markdown emphasis, headers,
or bold warnings — if a comment needs bold to be noticed, it is too long.

## Running the pass

1. **Scope.** Default to the files touched by the current branch's diff
   against the default branch; the user may name files or directories
   instead. Read each in-scope file in full — comments are judged in the
   context of the whole file, never from diff hunks alone.
2. **Edit.** Apply the five fixes directly. Renames stay within scope and
   within reason: a local variable or private function, yes; a public API,
   flag it instead. If a comment led you to dead code (a guard that can
   never fire), remove the dead code too and say so.
3. **Verify.** Run the project's formatter, linter, and typecheck if
   present — renames especially.
4. **Report.** A short summary: counts by fix (cut / compressed /
   relocated / renamed / improved), plus anything flagged rather than
   changed. Don't enumerate every deletion.

In CI or report-only mode, make no edits: emit the same report with
file:line references and the proposed fix for each finding, and exit
nonzero only if there are findings above whatever threshold the job set.
