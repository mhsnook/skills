# The checks

For each check: what the job measures, how it normalises the output, and what
the delta tells the reader. The diff needs one sorted line per issue, so any
tool you can coax into `file:line:col: message` drops straight in.

## 0. Build outcome

Run both builds so that a failure does not end the job, and keep each build's
log. Two outcomes give the report job four things to say:

| head | base | The comment says |
|---|---|---|
| builds | builds | nothing at all |
| builds | broken | this pull request repairs the build |
| broken | builds | this pull request breaks the build, with a log excerpt |
| broken | broken | the base branch is already broken — repair it first |

If you pipe the build into anything to capture that log, read the pipe entry in
failure-modes.md first: the obvious form records a failed build as a success.

The last row is why the report job reads both trees. If it blamed the author for
a build the base branch already broke, they would spend an afternoon looking for
a cause in their own diff.

Quote the log from its **first error**, rather than from its tail. Most build
tools print a summary, a stack and an exit code after the useful part, so the
last 40 lines are usually the least informative 40 lines. Check whether the
build tool timestamps its lines, and anchor the excerpt on words that appear
only in a failing build — a successful Vite build also prints `[vite]` and its
plugin names.

Treat "skipped" and "cancelled" as different from "success". A tree the runner
did not build has not shown that it builds.

**Gate:** `must-pass`. If a tree does not build, no other check in the report
can say anything trustworthy about it.

## 1. Type errors

**Normalised form:** the tool's own error lines, sorted unique, with summary
lines stripped. A line such as `Found 12 errors` changes whenever the count
changes, so it diffs as a phantom issue on every pull request.

| Language | Command |
|---|---|
| TypeScript | `tsc --noEmit`, keeping only lines matching `: error TS` |
| Python | `mypy --no-error-summary --no-color-output .` |
| Go | `go build ./...` — `go vet` runs analysis, rather than typechecking |
| Rust | `cargo check --message-format short` |

Two rules sit underneath that table, and both hold in any language:

**Generate the typechecker's inputs cheaply, rather than making the build a
prerequisite.** A tree that fails to build still deserves a type report, and a
generation step usually costs seconds. One exception: in a workspace whose
packages resolve each other through built artifacts, the build *is* the
generation step, so an unbuilt tree reports a phantom missing-module error for
every sibling package — one repository measured 41 errors unbuilt against 0
built.

**Normalise the output once, and strip colour before you parse it.** Not every
typechecker prints `file:line:col: message`; `astro check` prints
`file:line:col - error ts(NNNN):` with ANSI colour and code frames. A parser fed
escape codes matches nothing while appearing to run.

**Gate:** `no-new`, which suits almost every repository, because a type error is
unambiguous and cheap to fix at the moment someone introduces it. Run the
typechecker on the base branch first: if it already reports a high count, start
with `report-only` and say in the comment that the check tightens at zero.

## 2. Lint

**Normalised form:** `file:line:col: message`, with several linters merged into
one sorted list. A reviewer cares that a new issue sits at `src/foo.ts:12`,
rather than which of two tools found it, so keep the rule name in the message
and let the fix stay obvious.

Filter vendored and generated paths before you sort. A reviewer cannot act on an
issue in a generated file, and those issues can outnumber the ones they can act
on.

If the linter distinguishes warnings from errors, separate them: block on
errors, report warnings.

**Gate:** `no-new` in a maintained codebase. In a legacy one, run `report-only`
for a few weeks so the team watches the number first, then tighten. Blocking on
new issues in a repository that already holds thousands is how these workflows
get switched off.

## 3. Formatter drift

**Normalised form:** a sorted list of paths — the files the formatter would
rewrite.

Use the formatter's **read-only list mode**. Running it in write mode and then
diffing the tree answers the same question, and it destroys uncommitted work
whenever someone runs the script outside CI.

Run whichever formatter the repository already runs, and read its command out of
the repository's scripts rather than asking. If two formatters cover different
file types, run both; each one yields a path list.

This check compares two sets of paths. Its unit is the file, so line-shift
pairing does not apply.

### The gate covers touched files, rather than the delta

Formatting differs from linting. The formatter applies to every file the author
touched, every time, and leaves alone every file they did not. So the gate takes
the intersection of the pull request's own file list with the drift list, and it
blocks on any file in both — whether that drift is new or predates the pull
request.

Those two lists have to use the same path shape, or the intersection comes out
empty on every pull request and the gate stops firing altogether. Read the
path-shape entry in failure-modes.md before you write this check.

The repo-wide total still belongs in the comment, with a trend arrow, as
context. Group it by extension: eighty `.sql` files read very differently from
eighty spread across `.ts` and `.tsx`.

**If the repository has no formatter**, this check does not exist. Remove its
machinery rather than leaving it inert — the touched-file list, the policy
entry, the fragment — because a half-removed check renders "no list of touched
files was produced" on every pull request from then on. Adopting a formatter is
a separate decision that produces a much larger diff, so offer it rather than
folding it in.

**Gate:** `touched-clean`.

## 4. Bundle size

**Normalised form:** byte counts, raw and compressed, on several axes.

Label the unit you actually divided by: 1,000 bytes is a kB and 1,024 is a KiB.
Two reports that disagree by 2.4% while using the same word waste a reader's
afternoon.

Measure **the artifact a consumer actually pays for, as the tool that ships it
reports the size** — rather than summing the output directory. For a web app
that artifact is the eager-load set, which is what a first paint downloads; for
a binary it is the linked binary; for a package, the published archive; for a
container, the image layers. **If the build produces nothing a consumer
downloads, skip this check.**

The rest of this section describes the web-app case, which carries the
interesting axes. Report lazy chunks separately, so that a route split out of
the eager set reads as the win it is rather than disappearing into one total.

These axes move for different reasons, so report them apart:

- **Eager total** — what a first paint costs
- **Entry chunk** — your own code, which every visitor re-downloads on each
  deploy
- **CSS** — render-blocking, and it moves when the design changes rather than
  when the logic does
- **Chunk identity** — compared by content hash rather than by size, wherever
  the platform caches the artifact in pieces

Chunk identity is the axis people miss, and often the most useful one. A chunk
whose hash has not changed still sits in returning visitors' caches, so a pull
request that adds 2 kB to one chunk has cost every returning visitor the whole
chunk again. Report which chunks changed first, and their sizes second. If the
hash-stripping pattern is wrong, it compares two different files as one
unchanged chunk (failure-modes.md).

Compare the **union** of both trees' chunks, rather than the intersection. A
report built on the intersection cannot show a chunk that appeared or
disappeared, which is the largest thing that happens on this axis.

A project with manual chunk groups sees its own shared chunks in that list too,
and those chunks re-hash on most changes. The list answers "what does a
returning visitor download again", rather than "what went wrong".

### When the build emits no HTML entry point

- **A library.** Take no bundle check. `publish --dry-run` is the check that
  matters here, because it catches a package that ships the wrong files.
- **A server or Worker bundle.** Report what the deploy tool reports, rather
  than what the output directory sums to: the platform compresses the assembled
  bundle once and counts only what the entry point pulls in, so a sum over files
  measures a quantity the limit does not apply to. Where the platform imposes a
  hard limit — Cloudflare rejects a Worker over 64 MiB compressed, on every plan
  — report the size as a share of that limit rather than as a trend, and check
  the current figure rather than trusting this sentence.
- **A split client and server output.** Report two axes, rather than one total.
- **A server-rendered app that emits no HTML.** The framework's route manifest
  holds the eager set, and that manifest may not be a data file: TanStack Start
  compiles it into a module inside the *server* build, and Next.js keeps its own
  under `.next`. Find it, and parse it by matching delimiters rather than by a
  regex over indentation, because a regex that assumes the emitted whitespace
  breaks on the next formatter change and falls back without saying so. Record
  which source produced the eager set and print it, so that a fallback to
  walking the directory stays visible instead of passing as a number.

A Worker repository wants two instruments rather than one: the client bundle
takes this check, and the Worker takes a deploy dry-run. The dry-run bundles
exactly as a deploy would, and it is the only check that validates the deploy
config and its bindings — a binding typo passes every other check in the report.
Run it after the build, because an assets binding needs the built output to
exist.

**Watch for a bundler that reads environment variables at build time.** When
those variables are missing, it can tree-shake dependencies away, and the build
then looks dramatically smaller while meaning nothing. Set dummy-but-truthy
values, and check that a known dependency survived into the output.

**Gate:** `report-only` until someone has watched the number for a few weeks,
then a `budget` generous enough that only a real regression trips it. Percentages
misbehave on small bundles, where 5% of 40 kB is one dependency bump. Whatever
budget you set, ignore a delta of a few hundred bytes: two builds of the same
commit differ by that much.

## 5. Tests

**Normalised form:** counts, plus a list of failures.

This check reads head alone. A test passes on head or it does not, and the base
branch offers nothing to compare against, so a delta framing here produces a
confusing report.

Run the suite so that a failure still reaches the comment, and let the report
job decide the verdict. Ask the runner for machine-readable output —
`--reporter=json`, `--json-report`, `-json` — because a parser built on human
output breaks at the next minor version.

In a workspace, expect **one report per package**, and carry the test step's own
outcome into the renderer.

Cap the failure list at about 20 entries, and truncate each message to its first
line. Stack traces belong in the job log.

**Gate:** `must-pass` — any failure blocks, and so does a missing report.

## 6. Build content scan

**Normalised form:** a list of forbidden strings that the scan found in the
built output.

This skill ships no default list, because each project forbids different things.
Common ones: a test-only helper reachable from the production entry point, a
debug flag left on, a staging hostname, a development key.

Ask the team which strings must stay out of the build, rather than guessing.
Keep a reason on each entry: a bare pattern list rots within months, and nobody
dares delete an entry they cannot explain. Prefer a literal string over a clever
pattern — a string literal survives minification, while an identifier does not
(`__TEST_ONLY__` is still in the bundle; `isTestMode` became `a`).

This check reads head alone, and it needs the build. Scan the same output the
bundle measurement already read, so the job builds once. Write the result into
the same comment: a check that only turns a job red is a check people re-run
rather than read.

**Gate:** `must-pass`. A leaked key is not a trend to watch.

## 7. HTTP contract — optional, head only

**Skip this unless the repository asks for it.** Most adoptions leave it out,
and a repository with end-to-end tests already covers the ground.

It catches what no static check can: a redirect that lost its target, a page
that started returning 404, a cache header that quietly became `no-store`. Start
the built server, wait until it answers, then run a request-only suite against
it — no browser, so the job downloads no browser. A hermetic script that boots
the real runtime locally fits the same slot.

Four decisions separate a suite that catches those failures from one that passes
regardless:

- Fail when the server does not become ready, rather than letting a poll loop
  fall through, so the suite reports "the server did not start" instead of a
  hundred connection errors.
- Stop the client following redirects, or a 301 → 200 chain reads as 200 and the
  redirect assertions test nothing.
- Assert only the headers that stay stable across two runs of the same build.
- List the routes literally. A glob over the app's own routes passes when a route
  disappears, which is the failure this suite exists to catch.

## Workspaces

**Skip this section unless the repository has a workspace file that lists
packages.** In a single-package repository, none of it applies.

A recursive runner changes every check above. failure-modes.md covers the path
splice, the bail behaviour, the per-package test reports, and the reporter
format that the splice depends on.
