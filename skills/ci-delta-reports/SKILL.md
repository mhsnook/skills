---
name: ci-delta-reports
description: Set up GitHub Actions CI that reports what CHANGED between the base branch and the PR — new vs resolved type errors, lint issues, formatter drift, bundle size, and test failures — in one PR comment that updates in place. Use when someone wants PR checks that show a delta rather than a pass/fail, wants to adopt linting on a legacy codebase without fixing everything first, wants bundle-size reporting on PRs, asks for "CI like sunlo has", or wants to consolidate several noisy CI comments into one.
license: MIT
---

# CI delta reports

Build CI that answers **"what did this PR change?"** instead of **"is the repo clean?"**

The difference matters most on a codebase with existing debt. A workflow that fails on any lint error is unusable when the repo already has 4,000 of them, so teams turn it off. A workflow that fails only on *newly added* errors works from day one, and the count ratchets down as people touch old files.

Both are legitimate. Ask which one the developer wants — do not assume this one.

## What you will produce

```
.github/workflows/pr-checks.yml   one workflow, several check jobs, one report job
.github/ci/delta.cjs              diff engine — set difference plus shift-pairing
.github/ci/comment.cjs            fragment assembly and comment upsert
.github/ci/collect-static.sh      runs the checks, normalises their output
.github/ci/render-*.cjs           one renderer per check
.github/ci/gate.cjs               the single place pass/fail policy lives
```

The architecture, and why each piece is shaped the way it is, lives in
[references/architecture.md](references/architecture.md). Read it before you
adapt the templates — several choices look arbitrary and are not.

## Step 1 — read the repo first

Never ask a question the repository already answers. Determine:

- Package manager, from the lockfile: `pnpm-lock.yaml`, `package-lock.json`, `yarn.lock`, `bun.lockb`
- Available scripts: read `package.json` `scripts`, or the equivalent for a non-JS project
- Which of typecheck, lint, format, build, and test actually exist as commands
- Whether `.github/workflows/` already has something, so you extend rather than replace
- The default branch name, and whether PRs target it

Report what you found before you ask anything. "You're on pnpm with `check`,
`lint`, `format`, `build`, and `test:unit` scripts, and no workflows yet" makes
the following questions much cheaper to answer.

## Step 2 — ask, do not assume

Present the six checks with their cost, and let the developer pick. Costs
below are the *extra work* each check adds, not wall-clock guarantees — a slow
test suite or a large dependency tree dominates everything here.

| # | Check | What the delta tells you | Extra work | Rough |
|---|-------|--------------------------|-----------|-------|
| 1 | **Type errors** | New / resolved, with line shifts discounted | install + typecheck on both branches | 3–6 min |
| 2 | **Lint** | New / resolved, several linters merged into one list | shares job 1's installs | +1 min |
| 3 | **Formatter drift** | How many files the formatter would still rewrite, grouped by extension | shares job 1's installs | +1 min |
| 4 | **Bundle size** | Eager-load set, entry chunk, CSS, and which vendor chunks stopped being cacheable | install + **build** on both branches | 5–12 min |
| 5 | **Tests** | Pass / fail with failure detail inline | install + suite, head branch only | suite + 2 min |
| 6 | **Bundle content scan** | Dev-only code that leaked into the production build | install + build, head branch only | 3–8 min |

Two things to say out loud, because they change what people pick:

- **Checks 1–3 share one job.** If they take any of them, the other two are
  nearly free. Adding lint to a repo that already typechecks costs about a minute.
- **Checks 4 and 6 both build.** If they want both, build once and run both
  scans over the same output rather than running two jobs that each build.

Then ask the policy questions. These are the ones people have real opinions about:

1. **Gate or report?** Per check: fail the build on new issues, or comment only?
   A sensible default is gate on type errors and tests, report-only on formatter
   drift, and let them decide lint.
2. **How strict on new issues?** Fail on the first new one, or allow a budget?
3. **Vendored and generated files** — in or out of the lint and format deltas?
   Default them out; nobody reviewing the PR can act on them.
4. **Bundle budget**, if they took check 4. A byte ceiling on gzipped growth, or
   report-only?
5. **Line-shift tolerance.** An unrelated edit above an existing error bumps its
   line number. The default pairs those within ±10 lines so they do not read as
   one new plus one resolved. Widen it on a codebase with big mechanical diffs.

Ask these as a batch, not one at a time.

## Step 3 — generate

Copy the templates from `assets/` into `.github/`, then adapt. Every line that
depends on the toolchain carries a `# CONFIGURE:` marker — resolve all of them
and delete the marker. A leftover `CONFIGURE` comment in generated output is a
bug.

- `workflow.yml` → `.github/workflows/pr-checks.yml`. Delete the jobs for checks
  they did not pick, and prune the `needs:` list to match.
- `collect-static.sh` → swap in the real typecheck, lint, and format commands.
  Keep the shape: read-only checks concurrent, formatter last.
- `render-tests.cjs` → its `parse()` reads the Vitest and Jest JSON shape.
  Rewrite it for another runner and leave the rest.
- `render-bundle.cjs` → its `measure()` assumes an `index.html` entry point.
  For a library or server bundle, walk the output directory instead.
- `gate.cjs` → set `POLICY` from the answers to step 2.

Check 6 has no template, because "dev-only code" means something different in
every project. Write it fresh: a `grep` over the built output for the strings
that must never ship, exiting non-zero on a hit. Ask what those strings are.

## Step 4 — verify before you hand it over

Do not claim this works until you have checked:

```bash
node .github/ci/delta.cjs --selftest     # the shift-pairing logic
bash -n .github/ci/collect-static.sh     # shell syntax
node -e "require('./.github/ci/gate.cjs')"   # the policy object parses
```

Then confirm by reading, not by running:

- The workflow's `needs:` list names exactly the jobs that still exist.
- The report job has `permissions: pull-requests: write` and `if: always()`, so
  the comment still posts when a check job fails.
- Every check job has `fetch-depth: 0` if it adds a base-branch worktree.
- No `CONFIGURE` markers survive.

Say plainly that CI cannot be fully verified without a real PR, and that the
first run is the actual test.

## Rules that keep the report honest

- **Report and gate are separate steps.** The comment posts even on a red build.
  A contributor who cannot see why it failed will guess.
- **One comment, updated in place.** Match on a marker prefix and edit. Four
  comments per push trains people to collapse them.
- **Normalise before diffing.** Sort every list and strip summary lines like
  "Found 12 errors" — those change with the count and diff as pure noise.
- **Cap every list.** 50 items plus "… and N more". GitHub rejects a comment
  body over 65,536 characters, and a mechanical refactor will find that limit.
- **The formatter runs last in its job.** It rewrites files, and the set it
  rewrote is the signal. Restore the tree with `git checkout -- .` afterwards.
- **A missing report is a failure, not a pass.** If a runner crashes before
  writing output, say so in the comment and fail the gate.
