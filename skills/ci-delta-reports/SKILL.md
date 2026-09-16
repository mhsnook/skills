---
name: ci-delta-reports
description: Set up CI that reports what CHANGED between the base branch and the PR — new vs resolved type errors, lint issues, formatter drift, bundle size, and test failures — in one PR comment that updates in place. Use when someone wants PR checks that show a delta rather than a pass/fail, wants to adopt linting on a legacy codebase without fixing everything first, wants bundle-size reporting on PRs, or wants to consolidate several noisy CI comments into one.
license: MIT
---

# CI delta reports

You are going to build a CI workflow that answers **"what did this pull request
change?"** rather than **"is the repository clean?"**

The difference matters most on a codebase that carries debt. A workflow that
fails on any lint error is unusable once the repository holds 4,000 of them, so
the team switches it off. A workflow that fails only on the errors a pull
request *adds* works from its first run, and the total drops as people touch old
files.

Both designs are legitimate. Ask the developer which one they want, so that you
build the workflow they will keep.

You write this workflow yourself, in the language and style the repository
already uses. These three files tell you what to build; read all of them before
you write anything.

- [references/architecture.md](references/architecture.md) — the structural
  decisions, and the one algorithm that needs an exact specification
- [references/checks.md](references/checks.md) — per check: what to measure, and
  what its delta means
- [references/failure-modes.md](references/failure-modes.md) — **read this
  twice.** Each entry describes a real failure from a real adoption, and most of
  them make the report say "no change" while something is broken.

## What you will produce

The workflow writes one comment on the pull request and updates that same
comment on every push. The comment leads with a summary table and puts the
detail underneath. On a pull request that has something to fix:

```markdown
### PR checks
_Compared against `main`._

❌ **2 checks failing**

| Check                          | Delta | Status |
|--------------------------------|-------|--------|
| Type errors                    |   +2  |   ❌   |
| Formatting (files you touched) |   +1  |   ❌   |
| Lint                           |   −6  |   ✅   |
| Bundle size                    | +0.5% |   ⚠️   |
| Test failures                  |    0  |   ✅   |

**Details**

- **Type errors** — 41 on `main` → 43 here · 1 resolved · 3 shifted, not counted
  - `src/client/deck.tsx(88,12): error TS2322: Type 'string' is not assignable…`
  - `src/shared/vote.ts(14,3): error TS18048: 'entry' is possibly 'undefined'.`
- **Formatting** — 1 file this PR touches is unformatted. Run the formatter and
  commit; a file you edited ships formatted.
  - `src/client/deck.tsx`
  - 82 other unformatted files are not this PR's problem, and block nothing:
    `.ts` 51 · `.tsx` 24 · `.sql` 8 — down from 84
- **Lint** — no new issues. 1,204 on `main` → 1,198 here · 6 resolved
- **Bundle size** — eager JS 198.4 → 199.1 kB gzipped · CSS unchanged · 12 lazy
  - `index.js` re-hashed, 91.2 → 91.9 kB raw, so returning visitors fetch it again
  - 11 other chunks keep their hash, 107 kB gzipped, still cached
- **Tests** — 891/891 passed, 7 reports merged
```

On a clean pull request the comment keeps the same shape, shows a zero delta and
a ✅ on every row, and gives one line of detail per check.

Four properties of that comment are deliberate, and each one earns its place:

- **The delta column carries the product.** The detail lines hold the absolute
  counts, which answer "how bad is this repository overall". The table answers
  "what did I just do", which is the question the author of the pull request
  actually has.
- **The status column uses three states.** ✅ means the check passed, ❌ means
  the check blocks the merge, and ⚠️ means a report-only check moved. If the
  table used two states, a reader could not tell which failures they have to act
  on, so they would read every detail line to find out.
- **The report job omits the Build row while both trees build.** It adds that
  row only to say that this pull request broke the build, repaired a broken base
  branch, or inherited a base branch that was already broken. A bot that reports
  success on every green pull request teaches the team to skim past it, which
  costs the one time it reports a failure.
- **The two formatter lines carry the check's scope.** A file the author touched
  ships formatted, whether the drift is new or predates the pull request. A file
  the author left alone blocks nothing, and the comment reports it as a trend.
  This pair is what makes the check safe to switch on in a repository that
  already has 84 unformatted files.

## Step 1 — read the repository first

Find out the following, so that your questions in step 2 cost the developer as
little time as possible:

- **Where the repository pins its package manager version** — pnpm's
  `packageManager` field, `go.mod`, `rust-toolchain.toml`, `.python-version`.
  The setup step needs to read that file. If the workflow pins the version a
  second time, the two pins drift apart, which is the most common way this CI
  breaks.
- **Which file declares the runtime version.** If no file declares it, offer to
  add one — and read *Measure both trees with the same instrument* in
  architecture.md first, because the base branch does not have the file your
  pull request adds.
- **Which of typecheck, lint, format, build and test exist as real commands.** A
  repository with no formatter cannot take the formatter check. Adopting a
  formatter is a separate decision that produces a much larger diff, so offer it
  rather than folding it into this work.
- **Whether the typechecker needs generated files before it runs**, and whether
  the repository invokes it as a compound command whose first half can fail in a
  different output format.
- **What the build emits, and in what shape**: an HTML entry point, a library
  directory, a server bundle, a split client and server output — or nothing a
  consumer downloads, in which case this repository takes no bundle check.
- **Whether any build step globs the whole repository for its inputs.** The
  Tailwind v4 CSS scan reads class-like strings out of every tracked file, so
  the CI scripts you are about to add change the CSS the build emits. Scope that
  scan to the client source before you measure anything, so that your first
  bundle report describes this pull request rather than a leak that predates it.
- **Whether another bot already comments on pull requests.** If one does, retire
  its comment as part of this work, so that the pull request carries one voice
  rather than two.
- **Which repository-specific jobs have to keep working**: a database service, a
  browser container, a release workflow, a deploy dry-run. This work replaces
  the *reporting*; those jobs stay.

Report what you found before you ask anything. A summary like "you're on pnpm
with `check`, `lint`, `format`, `build` and `test:unit`, and no workflows yet"
makes the questions below much cheaper for the developer to answer.

## Step 2 — ask the developer, rather than assuming

Present the checks and let the developer choose. Each tree costs one install and
one build, whatever the number of checks, and each check then adds its own run
time on top.

| # | Check | What its delta tells the reader | Trees | Marginal cost |
|---|-------|--------------------------------|-------|---------------|
| 0 | **Build outcome** | Broke it, fixed it, or inherited a broken base | both | free with any build |
| 1 | **Type errors** | New and resolved, with line shifts discounted | both | one typecheck per tree |
| 2 | **Lint** | New and resolved, several linters merged into one list | both | no extra install or build; its own run time |
| 3 | **Formatter drift** | Which touched files are unformatted, and the repo-wide trend | both | seconds |
| 4 | **Bundle size** | Eager set, entry chunk, CSS, and which chunks stopped being cacheable | both | **forces the build**, then ≈ free |
| 5 | **Tests** | Pass or fail, with the failures inline | head | the suite's own runtime |
| 6 | **Build content scan** | Strings the team requires to stay out of the build | head | a grep over the build |

Read the marginal-cost column to the developer. Check 4 is the one that changes
the shape of the job, because it forces a build on both trees. If the developer
declines check 4, drop the build steps — unless the typechecker resolves its
inputs through built declarations (checks.md §1), in which case the build stays
and only the measurement goes.

Avoid quoting minute figures for their repository. Install and build times vary
by more than an order of magnitude between projects, and a confident wrong
number costs you more trust than "it depends on your build".

Then ask the policy questions, which are the ones developers hold opinions
about:

1. **Does each check block the merge, or only report?** A sensible default
   blocks on type errors and tests, and lets the developer choose on lint.
   Formatting blocks as well, on a different scope — see below.
2. **How strict should a new issue be?** Block on the first one, or allow a
   budget?
3. **Do vendored and generated files belong in the lint and format deltas?**
   Leave them out by default: a reviewer cannot act on an issue in a generated
   file, so including it costs attention and returns nothing.
4. **What bundle budget, if they took check 4?** Report-only suits a repository
   where nobody has watched the number yet.
5. **How much line-shift tolerance?** When an edit inserts lines above an
   existing error, the tool reports that error at a new line number. Pair those
   within ±10 lines, so that the report describes one shifted issue rather than
   one new issue plus one resolved issue. Widen the tolerance in a codebase
   whose pull requests make large mechanical diffs.

Ask these as one batch, so the developer answers once.

**If nobody is available to answer**, choose defaults and write each choice into
the pull request description, so the developer can overturn any of them in
review. These defaults are defensible:

| Check | Default | Why |
|---|---|---|
| Build, tests | block | A tree that fails to build, or fails its tests, cannot support any other judgement. |
| Type errors | block on new | Run the typechecker on `main` first. If it already reports a high count, choose report-only and say in the comment that the check tightens at zero. |
| Lint | block on new when `main` is clean, report-only otherwise | Same test, same reasoning. Say which one you found. |
| Formatting | block on touched files | The scope makes this check safe in any repository, however much drift it carries. |
| Bundle size | report-only | Nobody has watched this number yet, so any budget you pick is a guess. |
| Content scan | skip | Ask the team which strings must stay out of the build. A scan with an invented list is machinery pretending to be a check. |

**The formatter check blocks on a different scope** — the files this pull
request touched, rather than the delta. Lead with that when you present it,
because that scope is what makes the check safe in a repository with debt. Offer
report-only if the developer wants the number without the teeth. checks.md §3
has the mechanics.

## Step 3 — build it

The architecture reference gives you the shape and the reasoning behind it.
**Settle one question before the others: how head's measuring tools reach the
base tree.** That answer decides your job layout, and it separates a first run
that works from three that fail — see *Measure both trees with the same
instrument* in architecture.md.

Four more points deserve stating here, because adopters get these wrong:

- **Cache the base job.** Its output depends on the base SHA and on head's
  configs, and neither one changes when the author pushes another commit — yet
  the job reinstalls and rebuilds on every push for the life of the pull
  request. Key a cache on those two inputs and skip the job on a hit, so the
  repository spends runner minutes only on work that can produce a new answer.
- **Write the workflow in the repository's own idiom**: its language, its script
  conventions, its test runner. When the repository has a test suite, put the
  diff logic's tests in that suite. A bespoke `--selftest` flag adds a second,
  weaker test system beside the one the project already trusts, and nothing runs
  it.
- **Include only what this repository reaches.** A policy parser that accepts
  five budget formats, in a repository whose budget is switched off, hides the
  fact that the feature is off. When someone wants a budget later, one constant
  and one comparison is the whole feature.
- **Write each comment to prevent a misread**, rather than to justify a
  decision. "Two-dot, not three-dot, because the checkout is the merge ref"
  stops the next editor from breaking the touched-file list. "Reporting and
  gating are separate because a contributor who cannot see why it failed will
  guess" explains your design to someone who did not ask, and belongs in the
  pull request description that you are also writing.

## Step 4 — make it fail before you hand it over

Reading the code catches less than you expect. Nine adoptions verified their
work by reading it, and five of them still failed on their first real run.

- **Prove the gate can fail.** Plant an error the gate should catch, and watch
  the job turn red. A gate that has only ever passed is a gate nobody has
  tested.
- **Prove that a missing measurement blocks.** Delete one output file and re-run
  the report job. It needs to say that the tree went unmeasured; if it says "no
  change" instead, a broken run reads to the team as a clean one.
- **Prove the formatter gate fires, and that it stops firing.** Plant drift in a
  file the pull request touched, then in a file it left alone.
- **Prove the repository's own checks reach the check scripts.** They are files
  in the repository like any other, so plant an error in one and confirm the
  report names it. Two things defeat this test: excluding those scripts from the
  deltas, and a tool whose file glob skips a dot-directory.
- **Confirm that no placeholder and no unreferenced file survives** in what you
  hand over.

Then tell the developer plainly that a real pull request is the only full test,
and that the first run is that test. Tell them as well that the pull request
adding this workflow gets checked *by its own new version* of the workflow, so a
bug in the workflow can make that pull request look fine while it is not.

**Keep the design contrast out of the pull request.** Title it by what the
workflow reports: "Add PR checks: type errors, lint, formatter drift, bundle
size, tests". A title built on "report this, not that" reads as a slogan, and in
a repository that had no CI it answers a question nobody asked.

## Rules that keep the report honest

- **The report job posts the comment, and a separate step decides the verdict.**
  The comment then reaches the author even when the run goes red, so they can
  see which check failed and why.
- **The report job updates one comment**, matching it by a hidden marker rather
  than by a visible heading.
- **Normalise each list before you diff it.** Sort it, and strip summary lines
  such as "Found 12 errors": those lines change whenever the count changes, so
  they diff as noise on every pull request.
- **Cap each list at about 20 items.** A mechanical refactor produces thousands
  of lines, and the platform rejects an over-long comment body.
- **A file the author touched ships formatted; a file they left alone is not
  their problem.**
- **Missing input blocks the merge.** An absent measurement, an empty
  measurement, and a tool that could not run all mean the same thing, and none
  of them means "no change".
