---
name: comment-review-a
description: 'Review the code comments in a batch of work — a pull request, a branch, or the current diff — cutting changelog comments, references to PRs and issues, restatements of the code or of a project doc, and padding, while keeping the comments that explain why non-obvious code exists, name a contract others depend on, or warn about a footgun. Triggers: review the comments in this PR, check the comments before I push, are these comments over-specified, too many comments in this diff, comment review. For a whole codebase rather than one change, use the spec-debt skill.'
license: MIT
---

# Comment review

Code comments that explain where and when we have done something tricky, or a
bit different, make everyone happier and smarter. But excessive code comments
can lead to specification debt, context bloat, and reader strain. **Review all
code comments in this batch of work, including comments adjacent to or related
to the code we touched, checking for**:

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
    an error message or UI content or logging message that the comment restates.
- comments don't use a 7-line explanation when 2 lines will do
- sometimes a comment can just say "// <package> <version> <purpose>": an
  unfamiliar function in a zod schema might become fully clear with just 4 words:
  "// zod 4 recursive schema"
- comments don't have to restate what is already clearly spelled out in a
  site-wide readme, architecture doc, top-level document comment or sibling
  module; a single reference at the top of the file will do, or very brief,
  "require the signal, per architecture.md p4"
- A doc comment on an exported symbol says what the thing is and how to use it.
  An inline comment says why this line is written the odd way it is. A "why" in
  a doc comment is usually a commit message that escaped.
- Keep a comment if removing it makes a plausible future edit wrong. Cut it if it
  records a decision where the fork not taken has no defenders in the code.

When you are considering removing a comment, if you're worried about losing
knowledge altogether -- ask yourself if it should go in an architecture doc, the
readme, an issue in the repo, or a comment on the PR. Remember that every deleted
comment is probably going to be a win — unless it's genuinely a foot gun-avoider
or a useful signpost that we remove — whether it's because we documented
something in a more appropriate place, or we aligned the code structure to
standard practices that don't need comments.
