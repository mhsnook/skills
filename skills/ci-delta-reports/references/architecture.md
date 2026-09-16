# Architecture

The structural decisions, the reasoning behind each one, and the one algorithm
that needs an exact specification. None of this depends on a language or a CI
platform; write it in whatever the repository already uses.

## Run one job per tree, rather than one job per check

The workflow measures two trees: the pull request's, and the base branch's. Give
each tree **one job**, which installs once, builds once, and then answers every
question that tree can answer. A third job reads both results, diffs them, posts
the comment and decides the verdict.

```
head   install → build → typecheck, lint, format, bundle, tests, scan → artifact
base   install → build → typecheck, lint, format, bundle               → artifact
report                    diff both artifacts → one comment → gate
```

A job per check pays for an install and a build in every job, so the bill grows
with the number of checks. What decides whether two checks can share a job is
**which tree each one needs**, rather than what kind of check it is: type
errors, lint, formatter drift and bundle size need both trees, while the tests
and the content scan need head alone.

The head job and the base job run in parallel, so the wall clock is roughly the
slower of the two.

**One alternative is worth knowing about:** a single job that adds the base
branch as a worktree beside the head checkout. It gives up the parallelism and
buys one install, no artifact round-trip, and a formatter gate you can ask
directly rather than joining two path lists. It breaks any tool that prints
absolute paths, because the two trees sit at different roots, so every finding
reads as one resolved issue plus one new issue.

## Let the report job do the diffing, over artifacts

The report job holds neither tree. Each measuring job writes a small summary —
one sorted line per issue, or a JSON object of byte counts — and uploads it.
That arrangement is what lets the two builds run once each, in parallel, on
separate runners.

It also keeps the diff logic pure. Put the comparison and the rendering in one
module that makes no API calls, and put the platform coupling in another. The
repository's own test suite can then exercise the first module without a token,
and the second module stays thin enough to verify on the first real run.

**Have each job write one measurement file**, so that boundary stays honest. A
shape along these lines is enough:

```
measurement = {
  tree:   "head" | "base",
  build:  { ran, ok, log },
  checks: {
    typecheck: { ran, issues: [ "file:line:col: message", … ] },
    lint:      { ran, issues: [ … ] },
    format:    { ran, drifted: [ path, … ], touched: [ path, … ] },
    tests:     { ran, total, failed, failures: [ … ] },
    bundle:    { ran, fileCount, eager: {…}, lazy: {…}, chunks: { name: hash } },
  },
}
```

`ran` is the field that earns its place. A check that could not run has not
found zero issues, and most of the traps in failure-modes.md come down to a
missing `ran` flag. Set it false whenever the tool exits without output your
parser can read, and have the report job block on it.

The head job fills `touched`; the base job leaves it empty, because the
formatter gate reads the pull request's own file list and the base branch does
not have one.

## Measure both trees with the same instrument

This is the central problem, and most of the traps in failure-modes.md follow
from getting it wrong.

The base branch carries its own copy of the check scripts, which may be older
than head's. If each tree used its own copy, a pull request that edits a script
would change what the script measures, and that change would show up as a change
in the codebase. So **head's measuring tools need to measure both trees.**

A second, sparse checkout of the head SHA into a sibling directory does this
cleanly, and beats copying files over the base tree one path at a time:

```yaml
- uses: actions/checkout@v7
  with:
    ref: ${{ github.event.pull_request.head.sha }}
    path: .ci-head
    sparse-checkout: .github/ci
```

Cone-mode sparse checkout always includes the repository root, so every root
config arrives without your naming it. That property does the whole job: you
maintain no list, so you can forget nothing. On another platform, use whatever
fetches one directory of one commit into a path you choose — the design is "one
copy of the instrument, sited outside both trees", rather than this syntax.

Head's scripts then run from *beside* the measured tree rather than from inside
it, and that placement keeps their own issues reportable. If you copy head's
scripts over the base tree instead, both trees hold identical scripts, so an
issue in a script appears on both sides and cancels to "no change" — which is
why the older layout had to exclude those scripts from the deltas, and why drift
in a check script then escaped the gate entirely. Under the sibling layout each
tree keeps its own committed copy, so a script's issues diff like any other
file's.

That handles cancellation. It does not make a tool look at a directory it skips:
see the dot-directory entry in failure-modes.md, and plant an error in a check
script to confirm the report names it.

The sibling checkout also solves the bootstrap problem in one move. The base
branch does not contain the files the pull request adds to make CI work — the
runtime-version file, the package-manager version, the scripts themselves — and
every adoption meets this on its first run.

### Judgment configs and build configs behave differently

Only some configs belong to the instrument:

- **A judgment config decides what counts as an issue**: lint rules, format
  rules, type strictness, and the ignore files those tools read to choose what
  to scan. Both trees use head's copy. If the base tree kept its own copy, a
  pull request that turns on a rule would have its base tree judged by the old
  rule, and every file the rule touches would read as newly broken.
- **A build config decides what gets built**: the bundler config, the deploy
  config. Each tree uses its own. A change to a build config is a real change,
  and showing it is exactly what the bundle delta is for, so sharing head's copy
  would erase the effect you are measuring.

When a pull request changes a judgment config, the report shows a wall of new
issues. That happens only when someone works on the CI setup itself, and the
person reading the report can see the cause, so the workflow needs no machinery
for it.

Some judgment configs have to resolve from the tree root — a typechecker
following relative project references, a tool that reads its config from the
working directory. One test tells you which: point the tool at head's config in
the sibling directory and run it against a tree you know has issues. If the tool
errors, or reports zero, copy that config into the tree instead.

## Pair the issues that only moved

This is the one algorithm that needs an exact specification. Without it, an edit
that inserts a line above an existing error makes the report show one new issue
and one resolved issue, so a pull request that adds an import to a file holding
ten errors reads as twenty changes.

**The algorithm needs two keys, and conflating them is the trap.** Membership
uses the issue's full position; pairing uses its kind. One key for both makes
the algorithm do nothing at all.

```
parse each line into { file, line, column, message }

place = file + line + column + message   # is this the same issue, here?
kind  = file + message                   # is this the same issue, anywhere?

resolved = base issues whose PLACE is absent from head
added    = head issues whose PLACE is absent from base

for each a in added:                     # one-to-one, so consume as you go
    find the first unconsumed r in resolved where
        kind(r) == kind(a) and abs(r.line - a.line) <= PROXIMITY   # default 10
    if found: consume both, and count one "shifted"
```

Report the shifted count separately and quietly — "3 shifted, not counted" —
which tells a reader the number is doing real work.

If you key membership on `kind`, a moved issue sits on both sides: it enters
neither `resolved` nor `added`, nothing reaches the pairing step, `shifted`
stays at zero, and an issue that moved 400 lines cancels without a trace. If you
key pairing on `place`, nothing pairs at all. The test cases below cover both
mistakes, along with the one-to-one consumption that stops ten errors in a moved
block from collapsing into one.

Whether `column` belongs in `place` is a judgement call. Including it reports a
re-indent as a change; excluding it forgives one. Choose, and write the test.

### Test cases

Whatever language you write the algorithm in, make these pass. They cost little,
and the first two catch the mistakes that otherwise fail silently.

| base | head | expect |
|---|---|---|
| `a.ts:10 X` | `a.ts:14 X` | 0 new, 0 resolved, 1 shifted |
| `a.ts:10 X` | `a.ts:450 X` | 1 new, 1 resolved, 0 shifted |
| `a.ts:10 X` | `a.ts:10 X` | 0 new, 0 resolved, 0 shifted |
| `a.ts:10 X` | `a.ts:12 X`, `a.ts:13 X` | 1 new, 0 resolved, 1 shifted |
| `a.ts:10 X`, `a.ts:11 X` | `a.ts:14 X` | 0 new, 1 resolved, 1 shifted |
| `a.ts:10 X` | `b.ts:10 X` | 1 new, 1 resolved, 0 shifted |
| (empty) | `a.ts:10 X` | 1 new |

A rename defeats this algorithm, and nothing here repairs that: renaming a file
makes every issue in it new, and every issue at its old path resolved. Say so in
the pull request template, so reviewers expect it.

## Separate the gate from the report

The report job posts the comment, and a later step decides the verdict. Two
reasons:

- **A red run then explains itself.** A contributor who cannot see which check
  failed will guess, and guessing costs more time than the check saved.
- **Strictness stays in one place.** Loosening a rule during a migration is then
  a one-line edit rather than a workflow rewrite.

Hold the policy as data — one rule per check — rather than as `if` statements
scattered through the rendering code. These rules cover what adopters need:

| Rule | Blocks when |
|---|---|
| report-only | it does not block; the comment carries the value |
| no-new | this pull request adds any issue of this kind |
| touched-clean | any issue sits in a file this pull request touched, new or pre-existing |
| a budget | the measured value grows past a number |
| must-pass | a head-only step failed — a deploy dry-run, a smoke suite |

**Missing input blocks the merge.** A check that produced no measurement did not
pass; it crashed. The same holds for a tree whose job died, and for a check that
wrote nothing at all. One rule covers all three: a tree counts as measured when
every expected output file is present and non-empty, and anything short of that
blocks. Checking that a directory exists is weaker, because an empty directory
satisfies it.

## Post one comment, and update it in place

Match the comment by a hidden marker (`<!-- ci-delta:pr-checks -->`) rather than
by its visible heading. If the workflow matches on the heading, rewording that
heading orphans every comment already on an open pull request, and the next run
posts a second comment beside the first.

Each check yields three things — a table row, a detail entry, and a verdict
against its policy. Keeping those three separate is what lets the comment stay
short while the gate stays strict.

Give each check an ordering key, so its table row and its detail entry line up,
and so jobs that finish out of order still render the same comment. Cap the
detail: platforms reject a comment body over roughly 65,000 characters, and a
mechanical refactor will find that limit. The table holds a fixed number of rows
and needs no cap, which is most of why it belongs at the top.

Give a check that measured nothing a row of its own. An absent row and a passing
row look alike at a glance, and that resemblance is the failure this whole
report exists to prevent.

Page through the comments while you look for the marker. A busy pull request
passes 100 comments, and a single-page lookup then stops finding the comment the
workflow wrote, so the workflow starts posting a new comment per push at exactly
the moment the thread is already long.

If the repository already carries a bot comment that this one replaces, delete
that comment once on the first run. Match only comments that report the same
checks, because a deployment bot's comment is not a duplicate of this one. Check
also that the new body cannot match the string you retire on, or the workflow
deletes what it just posted.

**Each tree also installs its own tool versions, and you cannot control that.**
A pull request that bumps the linter measures the two trees with two different
linters. Accept it: pinning the base tree to head's dependency list would void
the lockfile check that makes either measurement trustworthy. A dependency bump
is simply the other pull request, alongside a rules change, where the delta
carries noise and the reader can see why.

## Known limits

- **A fork's pull request gets a read-only token**, so the comment step cannot
  write. Either accept that forks see the gate's exit code alone, or move the
  comment to a separate trigger and take on its risks.
- **The base job wastes work on repeat pushes.** Its output depends on the base
  SHA and head's configs, and neither changes when the author pushes again — yet
  it reinstalls and rebuilds every time. It does not sit on the critical path,
  so it costs money rather than minutes. Cache it on those two inputs, or tell
  the developer plainly that you chose not to.
