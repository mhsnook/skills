---
name: ci-delta-reports
description: Set up CI that reports what CHANGED between the base branch and the PR — new vs resolved type errors, lint issues, formatter drift, bundle size, and test failures — in one PR comment that updates in place. Use when someone wants PR checks that show a delta rather than a pass/fail, wants to adopt linting on a legacy codebase without fixing everything first, wants bundle-size reporting on PRs, or wants to consolidate several noisy CI comments into one.
license: MIT
---

# CI delta reports

Build CI that answers **"what did this PR change?"** rather than **"is the repo
clean?"**

The difference matters most on a codebase with existing debt. A workflow that
fails on any lint error is unusable when the repo already has 4,000 of them, so
teams turn it off. A workflow that fails only on *newly added* errors works from
day one, and the count ratchets down as people touch old files.

Both are legitimate. Ask which one the developer wants — do not assume this one.

You are building this CI yourself, in whatever language and style the
repository already uses. These three files stand alone — read all of them
before you write anything.

- [references/architecture.md](references/architecture.md) — the structural
  decisions, and the one algorithm worth specifying exactly
- [references/checks.md](references/checks.md) — per check: what to measure and
  what the delta means
- [references/failure-modes.md](references/failure-modes.md) — **read this
  twice.** Every entry is a real failure from a real adoption, and most of them
  report "no change" while something is broken.

## What you will produce

CI that writes one comment on the pull request and updates it in place on every
push: a summary table, then the detail under it. On a PR with something to fix:

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

On a clean PR the same shape renders with zero deltas, a ✅ on every row, and
one line of detail per check.

Four things in that shape are deliberate:

- **The delta column is the product.** Absolute counts live in the detail, where
  they answer "how bad is it overall"; the table answers "what did I just do".
- **Three states, not two.** ✅ passed, ❌ blocking, ⚠️ moved but not gated. A
  report-only check that moved deserves attention without stopping anyone, and
  a reader can tell at a glance which failures they must act on.
- **No Build row while both trees build.** It appears only to say that this PR
  broke the build, fixed a broken base branch, or inherited one already broken.
  Same rule everywhere: say nothing when there is nothing to say.
- **The formatter's two lines are the load-bearing pair** on a repo carrying
  debt. A file you touched ships formatted, whether the drift is new or was
  there before you opened the file. A file you did not touch blocks nothing,
  and is reported only as a trend.

## Step 1 — read the repo first

Determine:

- The package manager and **where its version is pinned** — pnpm's
  `packageManager` field, `go.mod`, `rust-toolchain.toml`, `.python-version`.
  Let the setup step read that file; pinning the version a second time in the
  workflow is the most common way this CI breaks.
- The runtime version and where it is declared. If nothing declares it, offer to
  add that file — then read *Both trees must be measured by the same instrument*
  in architecture.md, because the base branch will not have it yet.
- Which of typecheck, lint, format, build and test exist as real commands. A
  repo with no formatter cannot take the formatter check; adopting one is a
  separate decision with a much larger diff.
- Whether the typechecker needs generated files first, and whether it is a
  compound command whose first half can fail in a different output format.
- What the build emits, and in what shape: an HTML entry point, a library
  directory, a server bundle, a split client/server output — or nothing a
  consumer downloads, in which case there is no bundle check to take.
- Whether any build step globs the whole repository for its inputs. Tailwind v4
  scans for class names that way, so the files you are about to add change the
  output. Scope such a glob to its real source before you measure anything, or
  your first report blames this PR for a pre-existing leak.
- Whether anything already comments on PRs, so you retire it rather than adding
  a second bot voice.
- Repo-specific jobs that must survive: a database service, a browser container,
  a release workflow, a deploy dry-run. This work replaces the *reporting*,
  never those.

Report what you found before you ask anything. "You're on pnpm with `check`,
`lint`, `format`, `build` and `test:unit`, and no workflows yet" makes the
following questions much cheaper to answer.

## Step 2 — ask, do not assume

Present the checks and let the developer pick. The **fixed** cost is one install
and one build per tree, paid once no matter how many checks they take. Each
check then adds only its own run time.

| # | Check | What the delta tells you | Trees | Marginal cost |
|---|-------|--------------------------|-------|---------------|
| 0 | **Build outcome** | Broke it, fixed it, or inherited a broken base | both | free with any build |
| 1 | **Type errors** | New / resolved, with line shifts discounted | both | one typecheck per tree |
| 2 | **Lint** | New / resolved, several linters merged into one list | both | no extra install or build; its own run time |
| 3 | **Formatter drift** | Which touched files are unformatted, plus the repo-wide trend | both | seconds |
| 4 | **Bundle size** | Eager set, entry chunk, CSS, and which chunks stopped being cacheable | both | **forces the build**, then ≈ free |
| 5 | **Tests** | Pass / fail with failure detail inline | head | the suite's own runtime |
| 6 | **Build content scan** | Code that must never ship, found in the built output | head | a grep over the build |

Read the marginal-cost column out loud. Check 4 is the only one that changes
the shape of the job: it forces a build on both trees. If they decline it, drop
the build steps entirely — unless the typechecker needs built declarations
(checks.md §1), in which case the build stays and only the measurement goes.

Do not quote minute figures for their repo. Install and build time varies by
more than an order of magnitude, and a confident wrong number is worse than "it
depends on your build".

Then the policy questions, which are the ones people have opinions about:

1. **Gate or report, per check?** A sensible default gates type errors and
   tests, and lets them choose on lint. Formatting blocks too, but on a
   different scope — see below.
2. **How strict on new issues?** Fail on the first, or allow a budget?
3. **Vendored and generated files** — in or out of the lint and format deltas?
   Default them out; nobody reviewing the PR can act on them.
4. **Bundle budget**, if they took check 4. Report-only is the right default
   until someone has watched the number for a few weeks.
5. **Line-shift tolerance.** An unrelated edit above an existing error bumps its
   line number. Pair those within ±10 lines so they do not read as one new plus
   one resolved. Widen it on a codebase with big mechanical diffs.

Ask these as a batch, not one at a time.

**If nobody is available to answer**, decide and write every decision into the
PR description rather than stalling. These defaults are defensible:

| Check | Default | Why |
|---|---|---|
| Build, tests | block | A tree that does not build or pass cannot be judged. |
| Type errors | block on new | Run the typechecker on `main` first — if the count is already high, report-only and say it tightens at zero. |
| Lint | block on new if `main` is clean, report-only otherwise | Same test, same reason. Say which you found. |
| Formatting | block on touched files | The scope makes it safe on any repo. |
| Bundle size | report-only | Nobody has watched the number yet, so any budget is invented. |
| Content scan | skip | Never guess what must not ship. An empty scan is machinery pretending to be a check. |

**Formatting blocks on a different scope** — the files this PR touched, not the
delta. Lead with that, because it is what makes the check safe on a repo with
debt, and offer report-only only if they ask for the number without the teeth.
checks.md §3 has the mechanics.

## Step 3 — build it

The architecture reference gives you the shape and the reasoning. **Settle one
question before the rest: how head's measuring tools reach the base tree.** It
decides the job layout, and it is the difference between a first run that works
and three that do not — architecture.md, *Both trees must be measured by the
same instrument*.

Four more things are worth stating here, because they are the ones people get
wrong:

- **Cache the base job.** Its output is a function of the base SHA and head's
  configs, and neither changes when someone pushes again — yet it reinstalls and
  rebuilds on every push, for the life of the PR. Key a cache on those two and
  skip the job on a hit.
- **Write it in the repository's own idiom.** Its language, its script
  conventions, its test runner. If the repo has a test suite, the diff logic's
  tests belong in that suite — not behind a bespoke `--selftest` flag that
  nothing runs.
- **Include only what this repo reaches.** A policy parser that accepts five
  budget formats, in a repo whose budget is off, is not saving anyone work — it
  is hiding that the feature is off. One constant and one comparison is the
  whole feature when someone wants it.
- **Comment to prevent a misread, not to justify a decision.** "Two-dot, not
  three-dot, because the checkout is the merge ref" stops the next editor
  breaking it. "Reporting and gating are separate because a contributor who
  cannot see why it failed will guess" is your reasoning about the design, and
  it belongs in the PR description, which you are also writing.

## Step 4 — make it fail before you hand it over

Reading the code catches less than you think. Across nine adoptions, every one
was verified by reading, and five still failed on their first real run.

- **Prove the gate can fail.** Plant an error the gate should catch, and watch
  the job go red. A gate that has only ever passed has not been tested.
- **Prove a missing measurement blocks.** Delete one output and re-run the
  report. It must say that tree was not measured — never "no change".
- **Prove the formatter gate fires and stops firing.** Plant drift in a file the
  PR touched, then in one it did not.
- **Prove the check scripts are subject to their own checks.** They are files in
  the repository like any other, so plant an error in one and confirm it is
  reported. Two things defeat this: excluding them from the deltas, and a tool
  whose file glob does not reach a dot-directory.
- Confirm no leftover placeholder or unreferenced file survives.

Then say plainly that CI cannot be fully verified without a real PR, and that
the first run is the actual test. Note also that the PR adding this workflow is
checked *by its own new version*, so a bug in the workflow can make the PR look
fine when it is not.

**Keep the design contrast out of the pull request.** Name what the workflow
reports: "Add PR checks: type errors, lint, formatter drift, bundle size,
tests". A title built on "report this, not that" is a slogan, and in a repo that
had no CI it answers a question nobody asked.

## Rules that keep the report honest

- **Report and gate are separate steps.** The comment posts even on a red build.
- **One comment, updated in place**, matched on a hidden marker rather than a
  visible heading.
- **Normalise before diffing.** Sort every list and strip summary lines like
  "Found 12 errors" — those change with the count and diff as pure noise.
- **Cap every list** at about 20 items. A mechanical refactor will find the
  comment size limit.
- **A file you touched ships formatted; a file you did not is not your problem.**
- **Missing input blocks.** An absent measurement, an empty one, and a tool that
  could not run are all the same verdict, and none of them is "no change".
