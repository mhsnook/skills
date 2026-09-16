# The checks

Per check: what to measure, how to normalise it, and what the delta means. The
diff only needs one sorted line per issue, so any tool that can be coaxed into
`file:line:col: message` drops straight in.

## 0. Build outcome

Run both builds under "continue on error" and keep each log. Two outcomes give
four messages:

| head | base | Say |
|---|---|---|
| builds | builds | nothing at all |
| builds | broken | this PR fixes the build |
| broken | builds | this PR breaks the build, with a log excerpt |
| broken | broken | the base branch is already broken — repair it first |

That last row is why both trees are read. Telling someone they broke a build
they inherited wastes their afternoon.

Quote the log from the **first error**, not the tail: most tools print a
summary, a stack and an exit code after the useful part. Check whether your
build tool timestamps its lines, and anchor on words that appear only in a
failing build — successful builds print `[vite]` and plugin names too.

"Skipped" and "cancelled" are not "success". A tree that was never built has not
been shown to build.

**Gate:** always. A PR whose tree does not build cannot be verified by anything
else in the report.

## 1. Type errors

**Normalised form:** the tool's own error lines, sorted unique, with summary
lines stripped. `Found 12 errors` changes whenever the count does, so it diffs
as a permanent phantom issue.

| Language | Command |
|---|---|
| TypeScript | `tsc --noEmit`, keeping only lines matching `: error TS` |
| Python | `mypy --no-error-summary --no-color-output .` |
| Go | `go vet ./...` |
| Rust | `cargo check --message-format short` |

**Generate before you typecheck.** If the typechecker needs generated
declarations, run that step in seconds rather than making the build a
prerequisite — a tree that does not build still deserves a type report. The
exception is a workspace whose packages resolve each other through built
declaration files: there the build *is* the generation step, and an unbuilt tree
reports a phantom missing-module error for every sibling. One repo measured 41
unbuilt against 0 built.

Not every typechecker prints `tsc` format. `astro check` prints
`file:line:col - error ts(NNNN):` with ANSI colour and code frames; strip the
colour, keep the diagnostic lines, and rewrite the separator.

**Gate:** `no-new` suits almost everyone. Type errors are unambiguous and cheap
to fix at the moment you introduce one.

## 2. Lint

**Normalised form:** `file:line:col: message`, several linters merged into one
sorted list. A reviewer cares that there is a new issue at `src/foo.ts:12`, not
which tool found it. Keep the rule name in the message so the fix stays obvious.

Filter vendored and generated paths before sorting; they produce issues nobody
on the PR can act on, and they can outnumber the real ones.

Warnings and errors are worth separating if the tool distinguishes them: gate on
errors, report warnings.

**Gate:** `no-new` on a maintained codebase. On a legacy one, start report-only
for a few weeks so the team sees the number, then tighten. Going straight to
`no-new` on a repo with thousands of existing issues is how these workflows get
switched off.

## 3. Formatter drift

**Normalised form:** a sorted list of file paths — the files the formatter would
rewrite.

Use the tool's **read-only list mode**. Running it in write mode and diffing the
tree answers the same question and destroys uncommitted work outside CI.

Run whatever formatter the repo already runs; read the command out of its
scripts rather than asking. If two formatters cover different file types, run
both — the output is a path list either way.

This check is set-difference only. The unit is the file, so line-shift pairing
does not apply.

### The gate is scoped to touched files, not to the delta

Formatting is not linting. The formatter applies to every file the PR touched,
every time, and never to a file it left alone. So the gate is the intersection
of the PR's own file list with the drift list, and it fails on any file in both
— new drift or old.

The repo-wide total still belongs in the comment, with a trend arrow, as
context. Group it by extension: eighty `.sql` files read very differently from
eighty spread across `.ts` and `.tsx`.

**If the repo has no formatter**, this check does not exist. Do not leave its
machinery behind — the touched-file list, the policy entry, the fragment — or
the comment renders "no list of touched files was produced" forever. Adopting a
formatter is a separate decision with a much larger diff. Offer it; do not
smuggle it in.

**Gate:** touched-clean.

## 4. Bundle size

**Normalised form:** byte counts, raw and compressed, on several axes.

Measure the **eager-load set** — what a first paint must download — not the
whole output directory. Report lazy chunks separately: a route split out of the
eager set is a win that one total would hide.

Axes that move for different reasons, and so belong apart:

- **Eager total** — what a first paint costs
- **Entry chunk** — your own code, re-downloaded on every deploy
- **CSS** — render-blocking, and moves with design rather than logic
- **Chunk identity** — compared by content hash, not size

That last one is the axis people miss and often the most useful. A chunk whose
hash is unchanged is still in returning visitors' caches, so a PR that adds 2 kB
to one has really cost every returning visitor the whole chunk again. Report
which chunks changed first, sizes second.

Compare the **union** of both trees' chunks, not the intersection. A report that
only lists chunks present on both sides cannot show a chunk that appeared or
disappeared, which is the largest thing that can happen to this axis.

A project with manual chunk groups sees its own shared chunks in that list too,
and those re-hash on most changes. The list answers "what does a returning
visitor re-download", not "what went wrong".

### When there is no HTML entry point

- **A library.** Take no bundle check. `publish --dry-run` is the check that
  matters, because it catches a package shipping the wrong files.
- **A server or Worker bundle.** Report what the deploy tool reports, not what
  the output directory sums to: the platform compresses the assembled bundle
  once and counts only what the entry point pulls in, so a sum over files is not
  the quantity the limit applies to. Where there is a hard limit — Cloudflare
  rejects a Worker over 64 MiB compressed, on every plan — report it as a share
  of that limit rather than as a trend, and check the current figure rather than
  trusting this sentence.
- **A split client/server output.** Two axes, never one total.
- **A server-rendered app with no HTML at all.** The eager set lives in the
  framework's route manifest, and the manifest may not be a data file: TanStack
  Start compiles it into a module inside the *server* build, and Next.js keeps
  its own under `.next`. Find it, and parse it by matching delimiters rather
  than by a regex over indentation — a regex that assumes the emitted
  whitespace breaks on the next formatter change and falls back silently.
  Record which source the eager set came from and print it, so a fallback to
  walking the directory is visible rather than passing as a number.

A Worker repo wants two instruments rather than one: the client bundle takes
this check, and the Worker takes a deploy dry-run. That dry-run bundles exactly
as a deploy would and is the only thing validating the deploy config and its
bindings — a binding typo passes every other check in the report. It runs after
the build, because an assets binding needs the built output to exist.

**Watch for:** a bundler that reads environment variables at build time can
tree-shake dependencies away when they are missing, producing a build that looks
dramatically smaller and means nothing. Set dummy-but-truthy values and
sanity-check that a known dependency survived.

**Gate:** report-only until someone has watched the number for a few weeks.
Then a byte budget, generous enough that only real regressions trip it.
Percentages misbehave on small bundles — 5% of 40 kB is one dependency bump.
Whatever the budget, ignore deltas of a few hundred bytes: two builds of the
same commit differ by that much.

## 5. Tests

**Normalised form:** counts plus a list of failures.

Single-branch. A test passes on head or it does not; there is nothing to compare
against base, and pretending otherwise produces a confusing report.

Run it so a failure still reaches the comment, and let the report job own the
verdict. Emit machine-readable output — `--reporter=json`, `--json-report`,
`-json` — because parsing human output breaks on every minor version.

In a workspace, expect **one report per package**, and carry the step's own
outcome into the renderer.

Cap the failure list at about 20 and truncate each message to its first line.
Stack traces belong in the job log.

**Gate:** any failure fails, and so does a missing report.

## 6. Build content scan

**Normalised form:** a list of forbidden strings found in the built output.

No default ships, because "must never ship" means something different in every
project. Common instances: test-only helpers reachable from the entry point, a
debug flag left on, a staging hostname, a development key.

Ask what the forbidden strings are; do not guess. Keep a reason on each entry —
a bare pattern list rots within months and nobody dares delete an entry they
cannot explain. Prefer literal strings over clever patterns.

Single-branch, and it needs the build. Scan the same output the bundle
measurement already read; never build twice. Write its result into the same
comment: a check that only turns a job red is a check people re-run rather than
read.

**Gate:** always. A leaked key is not a trend to watch.

## 7. HTTP contract — optional, head only

**Skip this unless the repo asks for it.** Most adoptions do not take it, and a
repo with end-to-end tests already covers the ground.

It catches what no static check can: a redirect that lost its target, a page
that started returning 404, a cache header that quietly went `no-store`. Start
the built server, wait for it to answer, then run a request-only suite — no
browser, so no browser download. A hermetic script that boots the real runtime
locally fits the same slot.

Four things make the difference between a suite that catches those and one that
passes regardless: fail when the server never becomes ready rather than letting
a poll loop fall through; do not follow redirects, or a 301 → 200 chain reads as
200; assert only headers that are stable across two runs of the same build; and
list the routes literally, because a glob over the app's own routes passes when
a route disappears.

## Workspaces

**Skip this section unless the repo has a workspace file listing packages.** In
a single-package repo none of it applies.

A recursive runner changes every check above. See failure-modes.md for the path
splice, bail behaviour, per-package test reports, and the reporter format that
the splice depends on.
