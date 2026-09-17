---
name: clear-instructions
description: Write or rewrite prose that another agent will act on — a skill, a plan, a prompt, a brief, an AGENTS.md or CLAUDE.md. Names the actor in every instruction, replaces absolutes like "never" and "must" with the analysis they stand in for, and keeps specificity where a reader can verify it. Use when writing instructions for an agent, rewriting a skill or plan, reviewing a prompt before you send it, or when an agent followed your instructions and did the wrong thing.
license: MIT
---

# Clear instructions

This skill covers prose that another agent reads and then acts on: a skill file,
an implementation plan, a prompt, a brief, an `AGENTS.md`. The reader cannot ask
you a follow-up question, so anything they have to infer is a coin flip you will
not see land.

For prose a *person* reads — a PR description, a commit message, UI copy, a code
comment — use the `prose-clarity` skill instead. The two overlap on clarity and
differ on what happens next: a person who misreads asks; an agent who misreads
implements.

## The rules, and what each one is for

### 1. Name the actor in every instruction

Write "A does X to B, so that C". A reader who knows which component acts can go
and look at that component.

When you cannot name the actor, you have found a decision nobody has made yet.
Say so, rather than writing around it in the passive voice — settling it costs
less now than it costs the implementing agent to guess.

> "Two trees get measured" → "The workflow measures two trees"
> "Post the comment, then decide" → "The report job posts the comment, and a
> later step decides the verdict"

### 2. State need and causality separately, in that order

What needs to happen, what goes wrong otherwise, and what to do about it.

A rule with its consequence removed reads as complete, so the reader stops
there. In one trial, a reviewer said it would have skipped a verification step
entirely, because the brief gave the rule and left the failure unstated.

> "It must say that tree was not measured — never 'no change'."
> → "It needs to say that the tree went unmeasured. If it says 'no change'
> instead, the team reads a broken run as a clean one."

### 3. Strike the absolutes, and write the analysis they stand in for

"Never", "always", "must", "do not" ask the reader for obedience in place of a
reason. They also hide which kind of claim you are making: an expectation of how
the system behaves, or a rule for the code you are asking someone to write.
Those are different things, and the reader needs to tell them apart.

Removing the absolute leaves a space, and analysis is what fills it:

> "Never guess what must not ship."
> → "Ask the team which strings the build has to exclude. A scan with an
> invented list is machinery pretending to be a check."

**An imperative is not an absolute.** "Share head's copy" tells the reader what
to do and stays. "You must always share head's copy" substitutes authority for
the reason, and goes. Keep the verb; drop the enforcement.

### 4. Say which one you mean

"The Vite build hook", rather than "the hook". In a system large enough to need
instructions, a generic referent has several candidates, and the reader picks
one before you can correct them.

Specific referents also shorten the text, because they let you delete the
explanatory clause that only existed to disambiguate.

### 5. Be specific about what the reader can verify, and vague about the rest

Specificity has two opposite effects depending on where it points:

- **A claim the reader can check in front of them** — a file, a command, a field
  name, a symbol — gets checked, and a wrong one surfaces fast.
- **A claim about the outside world** — a platform's size limit, a tool's
  current major version, a price, an API shape — rots between your writing and
  their reading, and they copy it without checking.

Say where to look the second kind up. A skill once carried a platform's size
limit and, in the same sentence, told the reader to go and verify it — which is
a sentence arguing for its own deletion.

## Rewriting something that already exists

The five rules above apply. Four more guard the rewrite itself, because a pass
that optimises sentences one at a time loses the things that were terse because
they carried weight.

### 6. Keep every identifier verbatim

Anything that is also a value in code, config, or a neighbouring document stays
exactly as written. A rewrite once replaced the policy name `touched-clean` with
the prose "block on touched files", and a reader then holding both files could
not tell that the rule and its description were the same thing.

### 7. Keep the imperatives that already work

See rule 3. Naming the actor is worth doing; it is not worth trading an order
the reader would obey for a description they can read past.

### 8. Change no content

A rewrite changes how a claim reads. Revising what it claims is separate work,
and mixing the two hides both.

### 9. Report what moved

List back:

- every claim you dropped, merged, or added, so the author can check for drift
- every sentence where you could not name the actor, and why
- every fact you removed as stale-prone, and what you put in its place
- anything the pass revealed as wrong, contradictory, or unverifiable

That last line is usually where the value is. Rewriting forces you to ask what
each sentence claims and who makes it true, which is a different question from
"is this clear", and it is the question that finds errors. One pass over a CI
skill found a cross-reference pointing at a renamed heading, and a
line-shift algorithm whose specification could not work as written.

## Checking your own pass

- Search for `never`, `always`, `must`, `do not`. Each survivor needs a reason
  to stay.
- Search for passive constructions — "is measured", "are excluded", "gets
  called". Each one either names its actor or explains why it cannot.
- Read the identifiers in the rewritten text against the original. Every
  backtick-quoted token from before is either present or deliberately gone.
- Count the sentences you re-read. Each one is a sentence the implementing agent
  will read twice, and a proportion of them will be read wrong.
- Read for description sitting where an instruction belongs. "Cone-mode sparse
  checkout always includes the repository root" is a true fact about git, and a
  reader met it where they expected to be told what to do with those files.

## Writing something new

Rules 1 to 5 carry over; 6 to 9 have nothing to act on yet.

One addition. If a sentence resists being written with a named actor, stop and
settle the decision underneath it. That resistance is the cheapest signal you
will get that the plan has a hole, and it costs far less to close it while
writing than to have an implementing agent choose for you and report back a day
later.
