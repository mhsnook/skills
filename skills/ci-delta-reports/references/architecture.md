# Architecture

Why the generated workflow is shaped the way it is. Read this before adapting
the templates — several choices look arbitrary and are not.

## The shape

```
      ┌──────────┐   ┌──────────┐   ┌──────────┐
      │  static  │   │  bundle  │   │  tests   │     check jobs, in parallel
      └────┬─────┘   └────┬─────┘   └────┬─────┘
           │ fragment     │ fragment     │ fragment    (markdown + json sidecar)
           └──────────────┼──────────────┘
                          ▼
                    ┌──────────┐
                    │  report  │   if: always()
                    └──────────┘
                     one comment, then one verdict
```

Each check job writes `NN-name.md` (what the reader sees) and `NN-name.json`
(what the gate reads), uploads both as an artifact, and never touches the PR.
The `report` job downloads every fragment, assembles them in filename order,
upserts one comment, and then runs the gate.

## Why fan-in rather than one comment per job

Parallel jobs cannot safely share a comment — two jobs finishing together will
race, and one overwrites the other. The options are one comment per job, or a
fan-in job that owns the write.

Fan-in wins on the thing that actually matters, which is the reader. A PR with
four bot comments gets collapsed and ignored. It also puts the pass/fail
decision in exactly one file, so "how strict are we?" has one answer instead of
being scattered across job definitions.

The cost is a serialised final job, roughly 30 seconds, and `if: always()` so
the report still posts when a check job fails. Without `always()`, a failing job
cancels the report and the contributor sees a red X with no explanation.

## Why compare against a base worktree

`git worktree add /tmp/base origin/<base-ref>` gives a second checkout inside
the same job, so both branches are measured by **the same toolchain version on
the same runner**. That is the property that makes the numbers comparable.

The alternatives are worse:

- **Caching the base result** across runs makes the comparison depend on when
  the cache was written. A dependency bump on the base branch silently poisons
  every open PR's delta.
- **A separate job for the base** doubles the setup cost and reintroduces the
  version-skew problem when the runner image updates mid-flight.
- **`git diff` against the merge base** tells you which *lines* changed, not
  which *issues* changed. A type error can appear in a file the PR never
  touched, because the PR changed a type three files away. Only running the
  tool on both trees finds that.

This requires `fetch-depth: 0` on the checkout. Without full history the
worktree cannot resolve the base ref, and the job fails with an unhelpful
message about an unknown revision.

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

## Why the static checks share a job

Installing dependencies twice, once per branch, is the dominant cost of a
delta check. It is paid per job, not per check. Three separate jobs for
typecheck, lint, and format pay it three times for identical results.

So: one job, one install per branch, then run the checks over both trees.
Read-only checks run concurrently with `&` and `wait`, since the typechecker is
the long pole and the linters finish underneath it.

The formatter is the exception and must run last. It **rewrites files**, and
the set of files it rewrote *is* the drift measurement — no separate `--check`
pass is needed. Restore the tree with `git checkout -- .` immediately after, or
every later step in the job sees a dirty checkout.

Bundle size stays in its own job because it builds rather than lints, and a
build is expensive enough that pinning it behind a typecheck helps nobody.

## Why the gate is separate from the report

The comment always posts. The gate then reads the same JSON sidecars and
decides. Two consequences worth keeping:

- A red build still explains itself. Failing before the comment posts leaves a
  contributor with an exit code and nothing else.
- Strictness lives in one object in `gate.cjs`. Loosening a rule during a
  migration is a one-line edit, not a workflow rewrite.

A missing sidecar is treated as a failure, not a pass. A runner that crashes
before writing output must not read as a clean run.

## Known limits

- **Fork PRs.** `pull_request` grants a read-only token to forks, so the
  comment step cannot write. Either switch to `pull_request_target` and accept
  its security implications — it runs the base branch's workflow with a write
  token, so never check out and execute fork code in it — or let the comment
  step fail on forks and rely on the gate's exit code.
- **First-run cost.** Two installs and two builds on every PR is real CI time.
  Dependency caching keyed on the lockfile helps the head branch; the base
  worktree usually reuses the same cache entry.
- **Rename churn.** Renaming a file makes every issue in it appear new and its
  old path resolved. Proximity pairing does not help, since the file key
  changed. Nothing here fixes that; it is worth mentioning in the PR template
  so reviewers expect it.
