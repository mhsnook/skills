# Architecture

Why the generated workflow is shaped the way it is. Read this before adapting
the templates — several choices look arbitrary and are not.

## The shape: one job per tree, not one per check

```
   ┌───────────────────────┐   ┌───────────────────────┐
   │        head           │   │        base           │
   │  install ─┐           │   │  install ─┐           │
   │  build ───┤           │   │  build ───┤           │   in parallel
   │  static · measure ·   │   │  static · measure     │
   │  scan · tests         │   │                       │
   └──────────┬────────────┘   └──────────┬────────────┘
              │ artifact                  │ artifact
              └────────────┬──────────────┘
                           ▼
                    ┌─────────────┐
                    │   report    │  if: always()
                    └─────────────┘
                 diff · one comment · one verdict
```

Two installs and two builds, whatever the number of checks.

The instinct is to give each check its own job, which reads cleanly in the
Actions UI. It is also how the cost explodes: what is expensive here is
installing dependencies and building, and both are paid **per job**, not per
check. Five check-jobs means five installs.

What actually decides whether two checks can share work is which tree they
need:

| Check | Needs |
|---|---|
| Type errors, lint, formatter drift, bundle size | both trees |
| Tests, build-content scan | head only |

So the split is by tree. Each job installs once, builds once, and runs every
check that tree can answer. `head` and `base` do not depend on each other, so
they run concurrently and wall-clock is roughly one install plus one build, not
two.

The bundle content scan reads the same `dist/` the measurement just read. Two
scans, one build. Building twice for two questions about one artifact is the
mistake this layout exists to prevent.

## Why the diff moved into the report job

Each build job **measures** and writes a summary — sorted issue lists for the
static checks, a small JSON for the bundle. Neither job compares anything.

That is what allows the two trees to live on separate runners. If the diff
happened in a build job, that job would need both trees, which forces them back
into one job and back into serial execution.

The report job then downloads two summaries and diffs them. It checks out the
repository only to get the scripts; it never needs either build.

## Why the base job fetches its scripts from head

```yaml
git checkout "${{ github.event.pull_request.head.sha }}" -- .github/ci/
```

The base branch has its own copy of `.github/ci/`, possibly an older one. If
each tree were measured by its own version of the collection script, a PR that
edits the script would show up as a change in the codebase. Pinning both sides
to the head branch's scripts keeps the comparison about the code.

The trade-off is real and worth stating: a PR that breaks the collection script
breaks the base measurement too. That is the correct failure — it is visible
immediately, rather than producing a plausible and wrong delta.

One small consequence, so nobody reads it as a bug: a build tool that scans the
repository for content — Tailwind v4 scans for class names — sees head's copy of
`.github/ci/` on the base tree too. That can move a CSS measurement by a few
bytes, permanently and in one direction. It is real, it is tiny, and chasing it
costs more than it saves.

**Which configs, though — and this is where the rule reverses.** The argument
above is about the measuring instrument. A tool's *config* is only sometimes
part of the instrument:

- **Formatter configs: fetch them.** The formatter gate is scoped to the files
  the PR touched, and those are judged by head's config either way. Fetching it
  only keeps the repo-wide trend honest, so there is no gate to fail open.
- **tsconfig, and the linter config when lint is gated: do not fetch them.**
  Here the config change *is* the thing being measured, and fetching it makes
  the gate **fail open**. A PR that sets `strict: true` and surfaces 40 errors
  has both trees judged by the new option, so the delta is zero, `no-new`
  passes, the PR merges, and `tsc` on the default branch starts failing. Left on
  its own config, base reports 0 against head's 40 and the gate blocks.

Both behaviours are noisy on a config change. One is noisy in the safe
direction, and a gate that cannot fail is worth less than a gate that cries
wolf. When lint is `report-only`, the trade-off flips back — there is no gate to
protect, and judging both trees by the new rule gives the more readable number. A PR that enables a lint rule changes what the head tree
reports and leaves the base tree judged by the old rule, so every file the rule
touches reads as newly broken and the PR cannot merge. Check those configs out
from head too — one `git checkout` per file, because a single call listing all
of them fails as a whole when any one path is absent, which would silently leave
the base tree on its own configs.

## Why line-shift pairing exists

Insert one import at the top of a file and every issue below it moves down a
line. A naive set difference then reports 40 resolved and 40 new. The report
becomes noise, and worse, a `no-new` gate blocks a PR that introduced nothing.

`differential()` pairs an appeared item with a disappeared one when the file,
the column, and the message all match and the line moved by no more than
`proximity` (default 10). Paired items are counted as `moved` and excluded from
both totals.

Deliberate limits:

- **Column must match exactly.** If the column moved, the code itself changed,
  not just its position. That is a real new issue.
- **Message must match exactly.** Same location, different rule, is a new issue.
- **Only line numbers get tolerance.** Nothing else is fuzzy.

Set `proximity` to `0` for a plain set difference. Do that whenever the unit of
change is a whole file — formatter drift, for instance, where there is no line
number to shift.

## Why one gate ignores the delta

Formatting is not linting. The formatter applies to every file you touch, every
time, so the question is not "did this PR add drift?" but "is anything this PR
touched still unformatted?"

That makes it the one check whose gate needs a third input beyond the two trees:
the PR's own file list. `touched-clean` reads its intersection with head's
drift rather than `added`. The delta is still computed and still reported; it
just is not what fails the build.

## Why the formatter runs last in its script

Read-only checks run concurrently with `&` and `wait`, since the typechecker is
the long pole and the linters finish underneath it.

The formatter cannot join them. It **rewrites files**, and the set of files it
rewrote *is* the drift measurement — no separate `--check` pass is needed.
Running it alongside a typechecker would have it editing files out from under
the tool. So it runs after, and the tree is restored with `git checkout -- .`
immediately, or every later step in the job sees a dirty checkout.

## Why fan-in rather than one comment per job

Parallel jobs cannot safely share a comment — two finishing together will race,
and one overwrites the other. The options are one comment per job, or a fan-in
job that owns the write.

Fan-in wins on the thing that matters, which is the reader: a PR with four bot
comments gets collapsed and ignored. It also puts the pass/fail decision in one
file, so "how strict are we?" has one answer instead of being spread across job
definitions.

The cost is a serialised final job, roughly 30 seconds, and `if: always()` is
required — without it, a failing check job cancels the report and the
contributor sees a red X with no explanation.

## Why the gate is separate from the report

The comment always posts. The gate then reads the same JSON sidecars and
decides. Two consequences worth keeping:

- A red build still explains itself.
- Strictness lives in one object in `gate.cjs`. Loosening a rule during a
  migration is a one-line edit, not a workflow rewrite.

A missing sidecar is a failure, not a pass. A runner that crashed before writing
output must not read as a clean run.

## The alternative layout: one job, base as a worktree

Two jobs in parallel is the default because wall clock is what people feel. One
job with the base branch as a `git worktree` is a real alternative, and it wins
on four counts:

- **One install, usually.** When the PR does not touch the lockfile, the base
  tree can borrow the head tree's `node_modules`:

  ```bash
  git worktree add --detach /tmp/base-branch origin/"$BASE_REF"
  if cmp -s pnpm-lock.yaml /tmp/base-branch/pnpm-lock.yaml; then
    ln -s "$GITHUB_WORKSPACE/node_modules" /tmp/base-branch/node_modules
  else
    (cd /tmp/base-branch && pnpm install --frozen-lockfile --silent)
  fi
  ```

- **No artifact round-trip**, so no upload, download, or retention window.
- **No toolchain skew**: both measurements provably came off one machine.
- **No path-shape join for the formatter gate.** In one tree you can ask the
  formatter directly which of the PR's own changed files it would rewrite, which
  removes the `touched.txt` intersection and all three of its silent failures.

What it costs: the two builds run in series, so wall clock is the sum rather
than the maximum. On a slow build that is the whole argument.

It also breaks any tool that prints **absolute paths**, which ESLint does. The
base worktree lives at `/tmp/base-branch` and head in the workspace, so the same
issue appears under two different paths and every finding reads as one resolved
plus one new. Normalise both roots out of every path before diffing, or use the
two-job layout, which cannot have this problem: each tree is at the workspace
root on its own runner.

Two rules carry over unchanged. Move each build's output aside before the next
build overwrites it, and remove the worktree with `if: always()`. One rule is
easy to lose: the base worktree runs the **base branch's** configs, so check the
tool configs out from head inside the worktree exactly as the base job does.

## Two rules that generalise past the template

**Every `run:` step containing a pipe needs `bash -eo pipefail`.** GitHub's
default shell for `run:` is `bash -e`, with no pipefail, so a piped step reports
the LAST command's exit status. `node gate.cjs | tee -a "$GITHUB_STEP_SUMMARY"`
therefore always exits 0: the gate prints its failures and the job goes green.
The template sets `defaults.run.shell: bash` once at the top for that reason, so
a step added later inherits it. The failure is invisible until the first run
that should have blocked and did not.

**CI runs the tool, not the package script.** `collect-static.sh` calls
`pnpm exec tsc`, never `pnpm typecheck`. This is the same argument as fetching
the measurement from head, one level up: the base tree is the base branch, so on
the PR that introduces a script, the base tree does not have it. Keep the
package script for humans, who benefit from the shorthand and are never running
against a tree from before it existed.

## Known limits

- **Toolchain skew.** Head and base build on separate runners, so in principle
  they could get different runner images mid-rollout. `setup-node` pins the
  language version and the lockfile pins dependencies, so the exposure is small.
  If a project is sensitive to it, use the one-job worktree layout above.
- **Container jobs.** Every script here shells out to git, and git refuses to
  operate on a directory owned by another user. A job with `container:` must run
  `git config --global --add safe.directory "$GITHUB_WORKSPACE"` before the
  first step that touches the repository.
- **Fork PRs.** `pull_request` grants a read-only token to forks, so the comment
  step cannot write. Either switch to `pull_request_target` and accept its
  security implications — it runs the base branch's workflow with a write token,
  so never check out and execute fork code in it — or let the comment step fail
  on forks and rely on the gate's exit code.
- **Rename churn.** Renaming a file makes every issue in it appear new and its
  old path resolved. Proximity pairing does not help, because the file key
  changed. Nothing here fixes that; mention it in the PR template so reviewers
  expect it.
- **Retry granularity.** Re-running a failed `head` job re-runs its build and
  its tests together. Splitting them back out would restore per-check retries
  at the cost of another install.
