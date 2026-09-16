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
.github/workflows/pr-checks.yml   head job · base job · report job
.github/ci/collect-static.sh      runs typecheck + lint + format, normalises output
.github/ci/measure-bundle.cjs     reads dist/ into a JSON summary
.github/ci/scan-build.sh          greps dist/ for strings that must not ship
.github/ci/delta.cjs              diff engine — set difference plus shift-pairing
.github/ci/render-*.cjs           turn measurements into markdown fragments
.github/ci/render-build.cjs       says whether this PR broke the build, or inherited it
.github/ci/comment.cjs            fragment assembly and comment upsert
.github/ci/gate.cjs               the single place pass/fail policy lives
```

**One job per tree, not one per check.** `head` and `base` each install once and
build once, in parallel, then run every check that tree can answer. `report`
diffs the two summaries, posts one comment, and decides pass or fail. Two
installs and two builds total, whatever the number of checks — installs and
builds are paid per job, so a job per check is how the cost explodes.

The architecture, and why each piece is shaped the way it is, lives in
[references/architecture.md](references/architecture.md). Read it before you
adapt the templates — several choices look arbitrary and are not.

## Step 1 — read the repo first

Never ask a question the repository already answers. Determine:

- Package manager, from the lockfile: `pnpm-lock.yaml`, `package-lock.json`, `yarn.lock`, `bun.lockb`
- The package manager's **version source**. For pnpm that is the `packageManager`
  field, and `pnpm/action-setup` reads it. Never also pin `version:` on the
  action — a mismatch between the two is the most common way this workflow
  breaks. Recommend the `pnpm@10.33.0+sha512...` form, which pins the integrity
  hash as well.
- The **Node version source**: a `.nvmrc` if there is one, so `node-version-file`
  keeps it in one place. If there is none, offer to add one rather than
  hardcoding the version in the workflow.
- Available scripts: read `package.json` `scripts`, or the equivalent for a non-JS project
- Which of typecheck, lint, format, build, and test actually exist as commands.
  A repo with no formatter and no linter cannot take checks 2 and 3 — adopting
  one is a separate decision, not part of this setup.
- Whether the typechecker needs generated files first (`next typegen`,
  `wrangler types`, `prisma generate`), and whether it is a compound command
  whose first half can fail in a different output format
- Whether `.github/workflows/` already has something, so you extend rather than replace
- Whether any existing workflow already comments on PRs. Those comments need
  retiring — see `retireComments` in step 3 — or the PR grows a second bot voice.
- The default branch name, and whether PRs target it
- Repo-specific jobs that must survive: a database service, a Playwright
  container, a release or publish workflow, a deploy dry-run. This workflow
  replaces the *reporting*, never those.

Report what you found before you ask anything. "You're on pnpm with `check`,
`lint`, `format`, `build`, and `test:unit` scripts, and no workflows yet" makes
the following questions much cheaper to answer.

## Step 2 — ask, do not assume

Present the six checks and let the developer pick. The **fixed** cost is one
install and one build per tree, paid once no matter how many checks they take.
Each check then adds only its own run time, listed below as *marginal* cost.

| # | Check | What the delta tells you | Trees | Marginal cost |
|---|-------|--------------------------|-------|---------------|
| 0 | **Build outcome** | Whether this PR broke the build, fixed it, or inherited a broken base | both | free — it comes with any build |
| 1 | **Type errors** | New / resolved, with line shifts discounted | both | one typecheck per tree |
| 2 | **Lint** | New / resolved, several linters merged into one list | both | runs beside the typecheck, so ≈ free |
| 3 | **Formatter drift** | Which touched files are still unformatted, plus the repo-wide total as a trend | both | one format pass per tree, ~seconds |
| 4 | **Bundle size** | Eager set, entry chunk, CSS, and which vendor chunks stopped being cacheable | both | **forces the build**, then ≈ free to measure |
| 5 | **Tests** | Pass / fail with failure detail inline | head | the suite's own runtime |
| 6 | **Build content scan** | Code that must never ship, found in the built output | head | a grep over the build, seconds |

Say these out loud, because they change what people pick:

- **Check 0 is not optional and costs nothing.** Any repo that builds gets the
  build verdict, because both build steps run under `continue-on-error`
  anyway. It stays quiet when both trees build.
- **Checks 1–3 are close to a package deal.** They run in the same script off
  the same install. Adding lint to a repo that already typechecks is about a minute.
- **Check 4 is the one that costs.** It forces a build on both trees. If they
  say no to it, drop the build steps from both jobs entirely.
- **Check 6 is nearly free once check 4 is in**, because it scans the `dist/`
  that was already built. On its own it still forces a build.
- **Wall clock is roughly the slower tree**, not the sum, because `head` and
  `base` run concurrently.

Do not quote minute figures for their repo. Install and build time varies by
more than an order of magnitude across projects, and a confident wrong number
is worse than "it depends on your build".

Then ask the policy questions. These are the ones people have real opinions about:

1. **Gate or report?** Per check: fail the build on new issues, or comment only?
   A sensible default is gate on type errors and tests, and let them decide lint.
   Formatting is the exception — see below.
2. **How strict on new issues?** Fail on the first new one, or allow a budget?
3. **Vendored and generated files** — in or out of the lint and format deltas?
   Default them out; nobody reviewing the PR can act on them.
4. **Bundle budget**, if they took check 4. A byte ceiling on gzipped growth, or
   report-only?
5. **Line-shift tolerance.** An unrelated edit above an existing error bumps its
   line number. The default pairs those within ±10 lines so they do not read as
   one new plus one resolved. Widen it on a codebase with big mechanical diffs.

Ask these as a batch, not one at a time.

**Formatting is scoped differently.** It is not linting: the formatter applies
to every file the PR touched, every time — new drift or old — and never to a
file it left alone. The repo-wide total still goes in the comment, with a trend
arrow. Lead with this; offer plain `report-only` if they want the number
without the teeth. [references/checks.md](references/checks.md) has the
mechanics and the three ways this gate fails silently.

## Step 3 — generate

Copy the templates from `assets/` into `.github/`, then adapt. Every line that
depends on the toolchain carries a `# CONFIGURE:` marker — resolve all of them
and delete the marker. A leftover `CONFIGURE` comment in generated output is a
bug.

- `workflow.yml` → `.github/workflows/pr-checks.yml`. Delete the **steps** for
  checks they did not pick, keeping the three jobs. Drop the build steps from
  both jobs if they took neither check 4 nor check 6. The "List files this PR
  touches" step exists only to feed the formatter gate — keep it if they took
  check 3 with the default policy, drop it if formatting is report-only.
- `collect-static.sh` → swap in the real typecheck, lint, and format commands,
  and set `EXCLUDE` from their answer about vendored files. Read the commands
  out of `package.json` `scripts` rather than asking which formatter they use;
  if two formatters cover different file types, run both. Keep the shape:
  read-only checks concurrent, formatter last.
- `measure-bundle.cjs` → its `measure()` assumes an `index.html` entry point.
  For a library, a server bundle, or a Cloudflare Worker, walk the output
  directory instead — [references/checks.md §4](references/checks.md) has both
  variants, including the one where the deploy platform imposes a hard size
  limit.
- `render-build.cjs` → set `ERROR_HEADING` to the first line of an error in your
  build tool's output, so the excerpt starts at the error rather than at the
  tail of the log.
- `render-tests.cjs` → its `parse()` reads the Vitest and Jest JSON shape.
  Rewrite it for another runner and leave the rest.
- `scan-build.sh` → replace the example `FORBIDDEN` entries. Ask what must never
  ship; do not guess. Keep the reason on each line.
**A repo with no linter and no formatter is a shape, not a subtraction.** Do not
leave the machinery behind, because dead machinery in a gate file reads as an
active check. [references/checks.md §3](references/checks.md) lists the five
deletions; `EXCLUDE` in `collect-static.sh` is a sixth once nothing filters
through it.

**The base tree is the base branch, so it does not have what this PR adds.**
That bites three ways on the very PR that sets CI up, and each one fails the
first run:

- `.nvmrc` and the tool configs — fixed by the fetch-from-head step, which is
  why it sits above `setup-node`.
- The `packageManager` field, when this PR is what adds it. `pnpm/action-setup`
  reads it from the base tree and dies with "No pnpm version is specified". Do
  not check out `package.json` itself into the base tree — it carries the
  dependency list, and `--frozen-lockfile` would then fail against the base
  lockfile on every PR that adds a dependency. Write just the toolchain fields
  to a scratch file and point `package_json_file:` at it.
- New `package.json` scripts. `collect-static.sh` must call the TOOL
  (`pnpm exec tsc`), not the script (`pnpm check`), for exactly this reason.
  Keep the script for humans.

**A library takes no bundle check at all.** Do not adapt `measure-bundle.cjs` to
walk a `tsc` output directory — a byte budget on that teaches nobody anything.
`pnpm publish --dry-run` is the check that matters, because it catches a package
shipping the wrong files. Delete `measure-bundle.cjs`, `render-bundle.cjs`, and
the bundle branch of `gate.cjs`.

- `gate.cjs` → set `POLICY` from the answers to step 2, and set `REQUIRED` to
  the checks whose *absence* must fail. A crashed job writes no sidecar at all,
  which the per-check missing rule cannot see.
- `workflow.yml` → the base job's "Fetch the measurement from head" step lists
  the scripts, the toolchain files and the **formatter** configs. Do not add the
  tsconfigs or a gated linter's config: fetching those makes the gate fail open
  on the PR that changes the rule. The comment in the template and
  [references/architecture.md](references/architecture.md) explain which way
  round and why. Keep that step above `setup-node`, because `.nvmrc` is in it.
- If the repo already has a bot comment this workflow replaces, call
  `retireComments(github, context, ['### Old heading'])` in the report job once,
  so open PRs lose the stale comment instead of carrying two. This is
  **mandatory, not optional, when a repo that adopted an earlier version of this
  skill moves to the hidden marker**: the old comments match neither the new
  marker nor anything else, so every open PR grows a second one. Check that the
  new body does not contain the retire string itself, or the workflow deletes
  its own comment. `retireComments` matches on `startsWith`, so this is only
  safe because the new body begins with the hidden marker: retire a heading that
  the new comment also starts with, and the workflow deletes what it just
  posted. Retire only comments that report the **same checks** — a deployment
  bot's comment is not a duplicate of this one.
- If you write a custom bundle verdict rather than using the template's, pass
  the base size through into the sidecar. A `'5%'` budget has no meaning without
  the number it is 5% of.

## Step 4 — verify before you hand it over

Do not claim this works until you have checked:

```bash
node .github/ci/delta.cjs --selftest              # the shift-pairing logic
bash -n .github/ci/collect-static.sh              # shell syntax
bash -n .github/ci/scan-build.sh
for f in .github/ci/*.cjs; do node -e "require('./$f')"; done   # every module parses
node .github/ci/measure-bundle.cjs dist /tmp/m.json   # after a local build
```

**Commit before you test-run `collect-static.sh`.** It ends with
`git checkout -- .`, so running it to check your work reverts any uncommitted
edit — including the edit you just made to that script.

Then confirm by reading, not by running:

- The report job has `permissions: pull-requests: write` and `if: always()`, so
  the comment still posts when a check job fails.
- The `base` job checks out `.github/ci/` from the head SHA. Both trees must be
  measured by the same scripts, or editing a script reads as a code change.
- If the formatter gate is on: the head job writes `touched.txt`, and the paths
  in it have the same shape as the ones in `format.txt` — both repo-root-relative,
  no `./`. A mismatch makes the intersection empty and the gate passes forever.
  Check one path from each list against the other by eye.
- The base job checks out the **linter and formatter configs** from head too,
  and the file names in that loop are the repo's real ones.
- Both build steps carry `id:`, `continue-on-error: true` and `tee`, and each
  job records `build.outcome`. Without all three, check 0 reports nothing.
- The workflow triggers on `pull_request` only. A `push` trigger on this
  workflow has no base tree to compare against, and on a PR branch it doubles
  every run.
- Every step the workflow references exists as a file, and every file the
  workflow does not reference has been deleted.
- If any job runs inside a `container:`, it runs `git config --global --add
  safe.directory "$GITHUB_WORKSPACE"` first. Every script here uses git.
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
- **A file you touched ships formatted; a file you did not is not your problem.**
  The formatter gate is scoped to the PR's own footprint, not to the delta.
- **A missing report is a failure, not a pass.** If a runner crashes before
  writing output, say so in the comment and fail the gate. That covers three
  distinct absences: a check that could not measure, a tree whose whole job
  died, and a check that wrote no sidecar at all.
- **Say nothing when there is nothing to say.** The build section stays silent
  while both trees build. A bot that reports success on every green PR trains
  people to skim past the one time it does not.
- **Static checks never depend on the build** — with one exception. A branch
  that fails to build is the branch that most needs to be told about its type
  errors. The exception is a workspace whose packages resolve each other through
  built `dist/*.d.ts`: there the build is the generation step, and an unbuilt
  tree reports a phantom "cannot find module" for every sibling. Reorder, and
  say why in the workflow.
- **Measure both trees with the same scripts AND the same tool configs.** The
  base job checks both out from head. Otherwise a PR that changes a rule reads
  as a PR that broke every file the rule touches.
- **Match on a hidden marker, not on the heading.** Reword a visible heading and
  every comment already on an open PR is orphaned, so the next run posts a
  second one beside it.
