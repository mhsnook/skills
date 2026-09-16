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

## What you will produce

CI that writes one comment on the pull request and updates it in place on every
push. Something like this:

```markdown
### PR checks
_Compared against `main`._

❌ **Blocking:** 2 new type errors · 1 file you touched is unformatted

#### Type errors
❌ **2 new** · 41 on `main` → 43 here · 1 resolved · 3 shifted, not counted

  New:
    src/client/deck.tsx(88,12): error TS2322: Type 'string' is not assignable…
    src/shared/vote.ts(14,3): error TS18048: 'entry' is possibly 'undefined'.

#### Lint
✅ No new issues. 1,204 on `main` → 1,198 here · 6 resolved

#### Formatter drift
❌ **Blocking — 1 file this PR touches is not formatted.** Run the formatter
    and commit. A file you edited ships formatted, no exceptions.
      src/client/deck.tsx

  The other 82 unformatted files are not this PR's problem, and are reported
  only as a trend: 83 files ↓ from 84.
  By type: `.ts` 51 · `.tsx` 24 · `.sql` 8

#### Bundle size
🟢 Eager load 198.4 kB → 199.1 kB gzipped (+0.7 kB)
    Entry chunk +0.7 kB · CSS unchanged · 12 lazy chunks

  Chunks that changed — repeat visitors re-download these in full:
    `index.js` — 91.2 kB → 91.9 kB raw, ↑ 0.7 kB
    11 other chunks keep their hash, 107 kB gzipped, still cached.

#### Tests
✅ 891/891 passed · 7 reports merged
```

The **Build** section is absent here on purpose: both trees built, so it says
nothing. It appears only to report that this PR broke the build, fixed a broken
base branch, or inherited one that was already broken.

Each section has a policy, and one step at the end reaches the verdict from the
same numbers the comment shows. In this example, type errors and the touched
unformatted file block the merge, while the bundle growth and the repo-wide
formatter total are reported and nothing else.

Two of those defaults are worth saying out loud, because they are the ones that
make this CI usable on a repo carrying debt:

- **A file you touched ships formatted.** That blocks, whether the drift is new
  or was there before you opened the file.
- **A file you did not touch is not your problem.** 82 unformatted files sit in
  the same report as a trend, and block nothing.

## This skill is instructions, not a framework

It ships no code to copy. You are building CI for **this** repository, in
whatever language and style that repository already uses, and you will make
better decisions with the repo in front of you than any template could make in
advance.

What the skill gives you: the architecture that works and why, the per-check
detail, and a catalogue of the ways this kind of CI silently reports the wrong
answer. Read all three before you write anything.

- [references/architecture.md](references/architecture.md) — the structural
  decisions, and the one algorithm worth specifying exactly
- [references/checks.md](references/checks.md) — per check: what to measure and
  what the delta means
- [references/failure-modes.md](references/failure-modes.md) — **read this
  twice.** Every entry is a real failure from a real adoption, and most of them
  report "no change" while something is broken.

Two working implementations to read rather than imitate line by line:

| Repo | Shape |
|---|---|
| `mhsnook/pomoduo`, `.github/ci/` | Vite + Cloudflare Worker. Pruned hard after a review pass — the closest thing to a reference. |
| `mhsnook/sunlo`, `.github/workflows/` | The original, and the largest: two linters, two formatters, a Supabase e2e job alongside. |

## Step 1 — read the repo first

Never ask a question the repository already answers. Determine:

- The package manager and **where its version is pinned**. For pnpm that is the
  `packageManager` field; pinning the version again in the workflow is the most
  common way this CI breaks.
- The runtime version and where it is declared. If nothing declares it, offer to
  add that file — and see the bootstrap trap in failure-modes.md, because the
  base branch will not have it yet.
- Which of typecheck, lint, format, build and test exist as real commands. A
  repo with no formatter cannot take the formatter check; adopting one is a
  separate decision with a much larger diff.
- Whether the typechecker needs generated files first, and whether it is a
  compound command whose first half can fail in a different output format.
- What the build emits, and in what shape: an HTML entry point, a library
  directory, a server bundle, a split client/server output.
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
| 2 | **Lint** | New / resolved, several linters merged into one list | both | runs beside the typecheck, so ≈ free |
| 3 | **Formatter drift** | Which touched files are unformatted, plus the repo-wide trend | both | seconds |
| 4 | **Bundle size** | Eager set, entry chunk, CSS, and which chunks stopped being cacheable | both | **forces the build**, then ≈ free |
| 5 | **Tests** | Pass / fail with failure detail inline | head | the suite's own runtime |
| 6 | **Build content scan** | Code that must never ship, found in the built output | head | a grep over the build |

Say these out loud, because they change what people pick:

- **Checks 1–3 are close to a package deal.** They run off the same install.
- **Check 4 is the one that costs.** It forces a build on both trees. If they
  say no, drop the build steps from both jobs entirely.
- **Check 6 is nearly free once 4 is in**, because it scans a build that
  already happened.
- **Wall clock is roughly the slower tree**, not the sum.

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

**Formatting blocks, on a different scope.** It is not linting: the formatter
applies to every file the PR touched, every time — new drift or old — and never
to a file it left alone. So it does not gate on the delta like the others; it
gates on the intersection of the PR's own file list with the drift list. Lead
with that, and offer report-only only if they ask for the number without the
teeth.

## Step 3 — build it

The architecture reference gives you the shape and the reasoning. Three things
are worth stating here because they are the ones people get wrong:

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
- **Prove the check scripts are subject to their own checks.** If you excluded
  them, drift in them is invisible to the gate by construction.
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
- **Cap every list.** A mechanical refactor will find the comment size limit.
- **A file you touched ships formatted; a file you did not is not your problem.**
- **Missing input blocks.** Never "no change".
- **Say nothing when there is nothing to say.** A bot that reports success on
  every green PR trains people to skim past the one time it does not.
