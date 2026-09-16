# Architecture

The structural decisions, why each one is the way it is, and the one algorithm
worth specifying exactly. Everything here is language-agnostic; write it in
whatever the repository already uses.

## One job per tree, not one per check

Two trees get measured: the PR's, and the base branch's. Run **one job per
tree**, each installing once and building once, then answering every question
that tree can answer. A third job fans in, diffs the two, posts the comment and
owns the verdict.

```
head   install → build → typecheck, lint, format, bundle, tests, scan → artifact
base   install → build → typecheck, lint, format, bundle               → artifact
report                    diff both artifacts → one comment → gate
```

The alternative — a job per check — pays an install and a build per job, which
is how the bill explodes. Which checks can share work is decided by **which tree
they need**, not by what kind of check they are: type errors, lint, formatter
drift and bundle size need both trees; tests and the content scan need only
head.

Head and base run in parallel, so wall clock is roughly the slower tree.

**An alternative worth knowing:** one job, with the base branch as a worktree
beside the head checkout. It costs the parallelism, and wins four things — one
install when the lockfile is unchanged (symlink the base tree's dependencies),
no artifact round-trip, both measurements provably from one machine, and no
path-shape join for the formatter gate, because you can ask the formatter
directly which of the PR's own files it would rewrite. It breaks any tool that
prints absolute paths, because the two trees sit at different roots and every
finding then reads as one resolved plus one new.

## The diff happens in the report job, over artifacts

Neither tree is checked out there. Each measuring job writes small summaries —
one sorted line per issue, or a JSON of byte counts — and uploads them. That is
what lets the two builds happen once each, in parallel, on separate runners.

It also keeps the diff logic pure. Put the comparison and the rendering in one
module with no API calls in it, and the platform coupling in another. The first
is testable in the repo's own test suite without a token; the second is a thin
wrapper you verify on the first real run.

## Both trees must be measured by the same instrument

This is the central problem, and most of the traps in failure-modes.md are
consequences of getting it wrong.

The base branch has its own copy of the check scripts, possibly an older one. If
each tree were measured by its own version, a PR that edits a script would show
up as a change in the codebase. So **head's measuring tools measure both trees**.

The clean way to do that is a second, sparse checkout of the head SHA into a
sibling directory, rather than copying files over the base tree one path at a
time:

```yaml
- uses: actions/checkout@v7
  with:
    ref: ${{ github.event.pull_request.head.sha }}
    path: .ci-head
    sparse-checkout: .github/ci
```

Cone-mode sparse checkout always includes the repository root, so every root
config arrives without being named. That property is the whole point: there is
no list to maintain and nothing to forget. Head's scripts then live *beside* the
measured tree rather than inside it, so they are not part of what gets measured,
and they do not need excluding from their own checks.

It also solves the bootstrap problem in one move. The base branch does not
contain the files the PR adds to make CI work — the runtime-version file, the
package-manager version, the scripts themselves — and every adoption hits this
on its first run.

### Judgment config and build config are different

Only some configs belong to the instrument:

- **Judgment configs** decide *what counts as an issue*: lint rules, format
  rules, type strictness, and the ignore files the tools read to decide what to
  scan. Share head's copy. A PR that turns on a rule otherwise has its base tree
  judged by the old rule, and every file the rule touches reads as newly broken.
- **Build configs** decide *what gets built*: the bundler config, the deploy
  config. Each tree uses its own. A build-config change is a real change, and it
  is exactly what the bundle delta exists to show — share it and you erase the
  effect you are measuring.

When a PR changes a judgment config, the report will show a wall of new issues.
That is rare, it happens only when someone is working on the CI setup itself,
and the person reading the report can see why. Do not build machinery for it.

Some judgment configs must resolve from the tree root — a typechecker following
relative project references, a tool reading its config from the working
directory. Those get copied in rather than read from the sibling checkout.

## Line-shift pairing

The one algorithm worth specifying. Without it, inserting a line above an
existing error reports one new issue and one resolved issue, and a PR that adds
an import to a file with ten errors reads as twenty changes.

Compare two lists of issues as sets, then reconcile what is left:

```
parse each line into { file, line, column, message }
identity = file + message      # NOT the line number

resolved = base issues whose identity is absent from head
added    = head issues whose identity is absent from base

for each pair (r in resolved, a in added) with the same identity:
    if abs(r.line - a.line) <= PROXIMITY:   # default 10
        drop both, and count it as "shifted"
```

Report the shifted count separately and quietly: "3 shifted, not counted". It
tells a reader the number is doing real work.

Two properties matter. The identity must not include the line number, or nothing
ever pairs. And the pairing must be one-to-one, or ten errors in a moved block
collapse into one.

Renames defeat this, and nothing here fixes that: a renamed file makes every
issue in it new and its old path resolved. Say so in the PR template so
reviewers expect it.

## The gate is separate from the report

Post the comment, then decide. Two reasons:

- **A red build still explains itself.** A contributor who cannot see why it
  failed will guess.
- **Strictness lives in one place.** Loosening a rule during a migration is a
  one-line edit rather than a workflow rewrite.

Keep the policy as data — one rule per check — rather than scattered `if`
statements across the rendering code. The useful rules in practice:

| Rule | Fails when |
|---|---|
| report-only | never; the comment is the whole point |
| no-new | this PR adds any issue of this kind |
| touched-clean | any issue in a file this PR touched, new or pre-existing |
| a budget | the measured value grows past a number |
| must-pass | a head-only step simply failed — a deploy dry-run, a smoke suite |

**Missing input blocks.** A check that produced no measurement did not pass; it
crashed. So did a tree whose whole job died, and a check that wrote nothing at
all. One rule covers all three: a tree counts as measured only when every
expected output is present, and anything else blocks. That is stronger than
checking that a directory exists, which an empty directory satisfies.

## One comment, updated in place

Match on a hidden marker (`<!-- ci-delta:pr-checks -->`), not on the visible
heading. Rewording a heading orphans every comment already on an open PR, and
the next run posts a second one beside it.

Each check contributes three things, and keeping them separate is what lets the
comment stay short while the gate stays strict:

| Contribution | Goes to |
|---|---|
| a delta, a status and a label | one row of the summary table |
| the counts and the offending items | one entry in the detail list |
| a verdict against its policy | the gate step |

Give each check an ordering key so a table row and its detail entry line up, and
so jobs finishing out of order still render the same. Cap the detail — platforms
reject a comment body over about 65,000 characters, and a mechanical refactor
will find that limit. The table has a fixed number of rows and never needs
capping, which is most of why it belongs at the top.

A check that measured nothing still gets a row. An absent row and a passing row
look identical at a glance, which is the failure this whole report exists to
avoid.

If the repo already has a bot comment this replaces, delete it once on the first
run. Match only comments reporting the same checks: a deployment bot's comment
is not a duplicate. Make sure the new body cannot match the string you retire on,
or the workflow deletes what it just posted.

## Known limits

- **Fork PRs.** A `pull_request` run from a fork gets a read-only token, so the
  comment step cannot write. Either accept that forks see only the gate's exit
  code, or move the comment to a separate trigger with its own risks.
- **Toolchain skew.** Head and base build on separate runners. The lockfile and
  the pinned runtime version keep the exposure small.
- **The base job is waste on repeat pushes.** Its output is a function of the
  base SHA and head's configs, and neither changes when someone pushes a
  follow-up commit — yet it reinstalls and rebuilds every time. It is never the
  critical path, so it costs money rather than minutes. Cache it on those
  inputs, or say plainly that you chose not to.
- **The workflow judges itself.** On a `pull_request` trigger the workflow runs
  from the PR branch, so the PR introducing this CI is checked by its own new
  version. That is the real test, and it is also why a bug in the workflow can
  make that PR look fine when it is not.
