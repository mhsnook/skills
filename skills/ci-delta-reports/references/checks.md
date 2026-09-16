# The checks

Per-check detail: what to run, how to normalise the output, and what the delta
means. The diff engine only needs one sorted line per issue, so any tool that
can be coaxed into `file:line:col: message` drops straight in.

## 0. Build outcome

**Normalised form:** one word per tree — the step outcome — plus the build log.

Both build steps run under `continue-on-error: true` and `tee` their output.
Each job writes `build.outcome` into its artifact, and `render-build.cjs` turns
the pair into one of four verdicts:

| head | base | What the comment says |
|---|---|---|
| builds | builds | nothing at all |
| builds | broken | this PR fixes the build |
| broken | builds | this PR breaks the build, with the log excerpt |
| broken | broken | the base branch is already broken — repair it first |

That last row is the reason to read both trees. Telling someone they broke the
build when they inherited it wastes their afternoon.

Quote the log from the **first error heading**, not from the tail. Most build
tools print a summary, a stack trace, and an exit code after the useful part,
so the last 40 lines are usually the least informative 40 lines.

`skipped` and `cancelled` are not `success`. A tree that was never built has not
been shown to build.

**Gate advice:** always gating. A PR whose tree does not build cannot be
verified by any other check in the report.

## 1. Type errors

**Normalised form:** the tool's own error lines, sorted, with summary lines
stripped.

| Language | Command | Parser |
|---|---|---|
| TypeScript | `tsc --noEmit` piped through `grep ': error TS'` | `parsers.tsc` |
| Python | `mypy --no-error-summary --no-color-output .` | `parsers.unix` |
| Go | `go vet ./... 2>&1` | `parsers.unix` |
| Rust | `cargo check --message-format short 2>&1` | `parsers.unix` |

Strip the summary line in every case. `Found 12 errors in 5 files` changes
whenever the count does, so it diffs as a permanent phantom issue.

**Generate before you typecheck.** If the typechecker needs generated
declarations — `next typegen`, `wrangler types`, `prisma generate` — run that
first, in seconds, rather than making the build a prerequisite. The typecheck
has to work on a tree that does not build.

**A typechecker that fails silently reads as clean.** `grep ': error TS'` over a
compound command like `wrangler types --check && tsc --build` produces an empty
file when the *first* half fails in its own format, and an empty file means zero
errors. Capture the exit status, and when it is non-zero with no recognised
error lines, write one synthetic issue line instead. The template does this.

### A compound typecheck hides most of its own errors

`tsc -p a && tsc -p b && tsc -p c` stops at the first project that fails, so
projects 2 and 3 are never typechecked. The delta then reads backwards: fixing
the last error in project 1 makes every pre-existing error in projects 2 and 3
appear as newly added, in a PR that added none of them.

Run each project separately, OR their exit statuses together, concatenate the
output and `sort -u`. The de-duplication is not cosmetic — multi-project
TypeScript setups share files, so one error in a shared file prints once per
project and would otherwise be counted three times.

`tsc --build` has the same problem without the `&&`: a shared directory that
several projects include produces one printed error per project. Sort unique,
always.

Some typecheckers do not print `tsc` format at all. `astro check` prints
`file:line:col - error ts(NNNN): message`, with ANSI colour and code frames. Strip
the colour, keep only the diagnostic lines, rewrite ` - ` into `: `, and read it
with `parsers.unix` rather than `parsers.tsc`.

**Gate advice:** `no-new` is right for almost everyone. Type errors are
unambiguous and cheap to fix at the moment you introduce one.

## 2. Lint

**Normalised form:** `file:line:col: message`, several linters merged, sorted
and de-duplicated.

| Tool | Flag |
|---|---|
| ESLint 8 | `-f unix` |
| ESLint 9 | ⚠️ no `unix` formatter — see below |
| oxlint | `-f unix` |
| Ruff | `--output-format concise` |
| golangci-lint | `--out-format line-number` |
| Clippy | `--message-format short` |

**ESLint 9 dropped the `unix` formatter from core.** `eslint . -f unix` exits 2
with "The unix formatter is no longer part of core ESLint", which prints nothing
the grep matches, so the report reads zero issues. Either add the
`eslint-formatter-unix` package, or write a ~20-line formatter module in
`.github/ci/` and point `-f` at it. The local module has a second advantage:
ESLint prints absolute paths, which would carry `/home/runner/work/...` into the
diff, and a formatter you control emits repo-root-relative ones.

**Guard the linter's exit status too.** Exit 1 means it found issues; exit 2
means it could not run — a bad config, a missing formatter package, a parse
error. Exit 2 produces no parseable output, which reads as a clean run. The
template writes one synthetic issue line instead.

Merging linters into one list is deliberate: a reviewer cares that there is a
new issue at `src/foo.ts:12`, not which of the two tools found it. Keep the
rule name in the message so the fix is still obvious.

Filter vendored and generated paths *before* sorting. They produce issues that
nobody reviewing the PR can act on, and they can outnumber the real ones.

Repeat that filter in `collect-static.sh` even when the linter config already
ignores the same paths. Each tree is measured with its own config until the base
job checks the configs out from head, and duplicating the list means a PR that
edits an ignore rule cannot move its own baseline.

**Gate advice:** `no-new` on a maintained codebase. On a legacy one, start
`report-only` for a few weeks so the team sees the number, then tighten. Going
straight to `no-new` on a repo with thousands of existing issues is how these
workflows get disabled.

## 3. Formatter drift

**Normalised form:** a sorted list of file paths — the files the formatter
would rewrite.

Run whatever formatter the repo already runs. Read its command out of the
`scripts` block rather than asking — a repo that has a `format` script has
already made this decision, and the check works the same whichever tool is
behind it. If two formatters are configured for different file types, run both
and concatenate; the output is a path list either way.

Run it in write mode, then read `git diff --name-only`. That is one pass
instead of two, and it gives the exact file set rather than a count. Then
`git checkout -- .`.

Do not use `--check` mode. It exits non-zero and prints a list in a different
shape per tool, which you would then have to parse.

This check is set-difference only — pass `proximity: 0`. The unit is the file.

Group the remaining drift by extension in the comment. Eighty `.sql` files read
very differently from eighty spread across `.ts` and `.tsx`, and one stray
`.css` is easy to spot and fold into the current PR.

### The gate is scoped to touched files, not to the delta

Formatting is not linting. The formatter applies to every file the PR touched,
every time — new drift or old — and never to a file it left alone. So this is
the one check that does not gate on `no-new`.

Mechanically: the head job emits `touched.txt` — `git diff --name-only
--diff-filter=d <base sha> HEAD`, sorted — and the report step intersects it
with head's drift list. The gate rule is `touched-clean`, and it fails on that
intersection.

Three things to get right, all of which fail silently:

- **Both lists must use the same path shape.** `git diff --name-only` gives
  repo-root-relative paths with no `./` prefix, on both sides, which is exactly
  why the drift list is produced that way too. Swap in `--list-different` or a
  formatter run from a subdirectory and the paths stop matching — the
  intersection is then empty on every PR and the gate silently never fires.
- **Diff against the right commit.** With the default `pull_request` checkout,
  `HEAD` is the merge ref, so a two-dot diff against `base.sha` is the PR's own
  footprint. Check out `head.sha` instead and two-dot silently widens to every
  file that landed on base since the branch diverged — use three-dot there.
- **An absent `touched.txt` is not an empty PR.** Treat a missing list as a
  crashed step and fail, the same as any other missing measurement. Otherwise a
  broken workflow reads as a clean bill of health.

Vendored and generated paths are filtered out of the drift list before any of
this, so a touched file under `EXCLUDE` cannot block the PR. That is deliberate
— checking in a regenerated file should not require formatting it.

**Gate advice:** `touched-clean`. The repo-wide total stays report-only, with
the trend arrow doing that work.

### If the repo has no formatter, delete five things

The templates assume this check exists, so skipping it is five coordinated
deletions across four files. Half-doing it leaves a fragment that renders
"⚠️ No list of touched files was produced" on every PR forever:

1. the "List files this PR touches" step in the head job,
2. the `format` entry in `POLICY` and the `touched-clean` branch in `verdict()`,
3. `format` in `REQUIRED`,
4. the formatter run and the `format.txt` write in `collect-static.sh` —
   including its closing `git checkout -- .`, which is only there because a
   formatter rewrites files,
5. the whole format section in `render-static.cjs`.

Adopting a formatter later is a separate decision, and a much larger diff than
this workflow. Offer it; do not smuggle it in.

## 4. Bundle size

**Normalised form:** byte counts, raw and gzipped, on several axes.

Measure the **eager-load set** — everything `index.html` references directly —
not the whole output directory. Lazy chunks are part of the app a user may
never download, so folding them into one total hides the number that matters.

Report these axes separately, because they move for different reasons:

- **Eager total** — what a first paint costs.
- **Entry chunk** — your own code, re-downloaded on every deploy.
- **CSS** — render-blocking, and moves when design changes rather than logic.
- **Vendor chunks** — compared by content hash, not size.

That last one is the non-obvious axis and often the most useful. A vendor chunk
whose hash is unchanged is still in returning visitors' caches. A PR that adds
2 kB to a vendor chunk has really cost every returning user the *whole* chunk
again, which may be 200 kB. Report identity, then size.

Lazy chunks still belong in the report, on their own line. A route split out of
the eager set is a win that a single total would hide.

### When there is no index.html

`measure()` reads `index.html` to find the eager set. Three common shapes have
none, and each wants a different measurement:

- **A library** (`dist/` from `tsc` or a bundler): walk the output directory and
  report the total. The useful gate is usually not size at all — it is
  `pnpm publish --dry-run`, which catches a package that ships the wrong files.
- **A server or Worker bundle**: walk the output directory, and check whether
  the platform imposes a hard limit. Cloudflare rejects a Worker over 10 MB
  gzipped on the Workers Paid plan, so that number is a budget rather than a
  trend — report it as a percentage of the limit.

### A Worker repo has two artifacts and wants two instruments

Do not ask "how do I point `measure()` at a Worker". Ask which artifact each
check is for. A dashboard SPA takes check 4 unchanged; the Worker takes
`wrangler deploy --dry-run`, gated `must-pass`.

The dry-run earns first-class status: it bundles exactly as a deploy would, it
is the only thing that validates `wrangler.toml` and the D1, Durable Object and
R2 bindings, it runs offline, and it takes seconds. A binding typo passes every
other check in this report.

**It runs after the build, not beside the static checks.** An `assets` binding
pointing at `dist/client` means the dry-run needs the built output to exist.

A hermetic end-to-end script (`wrangler dev` plus workerd, no developer-local
state) fits the head job the same way: after the build, `continue-on-error`, and
gated `must-pass`. Without `continue-on-error` it kills the job before the
comment posts.
- **A framework with a split output** (`dist/client` + `dist/server`, `.next/`):
  measure the two halves on separate axes. They move for different reasons and
  a combined total tells you nothing about either.

**A server-rendered app may have no HTML file at all.** TanStack Start and
Next.js generate the HTML per request, so `dist/client` holds only assets. Do
not fall straight to walking the directory — that reports every lazy chunk as
eager, which inflates the number people are watching. Look for the framework's
own route manifest first: TanStack Start writes one into the server bundle
(`_tanstack-start-manifest_v-*.js`, with `__root__.preloads` and
`__root__.scripts`), and Next.js has the equivalent in `.next`. Record which
source you used in the measurement — `eagerSource` in the template — and print
it in the comment, so a fallback is visible rather than silent.

CSS that the framework injects at render time counts as eager even though no
preload tag references it.

**Watch for:** a bundler that reads environment variables at build time may
tree-shake large dependencies away when those variables are missing, producing
a build that looks dramatically smaller and means nothing. Set dummy-but-truthy
values in CI and sanity-check that a known dependency is present in the output.

**Watch for:** a build that exits zero having written nothing. Measured against
a real base, that reports a triumphant −100%. Treat an empty measurement the
same as a missing one.

Whatever shape you measure, **emit a file count**. That is the field the
empty-build guard reads, and a hand-written `measure()` for a library or a
Worker that omits it re-opens the −100% hole without any visible sign.

**Watch for:** a CSS framework that scans the repository for class names —
Tailwind v4 does — makes the CSS total depend on which files exist, so adding
unrelated files moves it by a few bytes. Harmless at report-only; a CSS budget
on such a repo trips on file additions.

**Noise floor.** Two builds of the same commit differ by a few bytes per chunk.
The template reports an eager delta under 512 bytes as zero, so a budget never
trips on build noise.

**Gate advice:** a gzipped byte budget on the eager total, generous enough that
only real regressions trip it. `maxGzDelta` also accepts `'20KiB'` and `'5%'`.
Percentages misbehave on small bundles — 5% of a 40 kB bundle is 2 kB, which is
one dependency bump — so prefer bytes unless the bundle is large.

## 5. Tests

**Normalised form:** counts plus a list of failures.

Single-branch. A test passes on head or it does not; there is nothing to
compare against base. The delta framing does not apply here, and pretending
otherwise produces a confusing report.

Run with `continue-on-error: true` and let the report job own the failure.
Otherwise the job dies before writing its fragment and the comment loses the
one section a contributor most wants to read.

Emit machine-readable output: `--reporter=json` for Vitest and Jest,
`--json-report` for pytest, `-json` for `go test`. Parsing human output breaks
on every minor version.

Cap the failure list — 20 is plenty — and truncate each message to its first
line. Full stack traces belong in the job log and the uploaded artifact.

**Gate advice:** `no-new`, meaning any failure fails the build. Also fail when
the results file is missing, which is a crashed runner rather than a clean run.

## 6. Bundle content scan

**Normalised form:** a list of forbidden strings found in the built output.

No template ships for this one, because "must never ship" means something
different in every project. Common instances:

- Test-only helpers or fixture data reachable from the production entry point
- A debug or verbose logging flag left enabled
- A staging hostname or a development API key
- A dependency that was supposed to be `devDependencies`-only

Write it as a `grep` over the build output that exits non-zero on a hit, and
ask the developer what the forbidden strings are. Keep the list in one file
with a comment per entry saying why it must not ship — a bare regex list rots
within months.

Prefer a literal string over a clever pattern. String literals survive
minification; identifiers do not, so `__TEST_ONLY__` in the source is still
`__TEST_ONLY__` in the bundle while `isTestMode` became `a`.

Single-branch, and it builds. If bundle size is also in play, run both scans
over the same `dist/` rather than building twice.

The scan writes its own fragment, so a hit appears in the comment beside every
other check. A check that only turns a job red is a check people re-run rather
than read.

**Gate advice:** always gating, never report-only. A leaked key is not a trend
to watch.

## Workspaces and monorepos

A recursive runner changes every check above, and the failures are quiet.

**A recursive runner rewrites every path.** `pnpm -r`, `turbo`, `nx` and
`lerna` prefix each line with the package directory, while the tool's own path
stays package-relative:

```
packages/scenes typecheck: src/types.ts(1233,7): error TS2322: …
```

That is neither repo-root-relative nor unique — `packages/a/src/types.ts` and
`packages/b/src/types.ts` both key as `src/types.ts`, so errors in same-named
files across packages collide. Splice the two halves:

```bash
sed 's#^\([^[:space:]]\{1,\}\) typecheck: #\1/#'
```

Both trees produce the same wrong shape, so the delta looks plausible while
being wrong. Run the command yourself and read the raw output before trusting
any of it.

**Turn off bail.** `pnpm -r typecheck` stops at the first failing package: one
repo measured 5 errors across 3 of 15 projects, and 41 across all 15 with
`--no-bail`. Without it, how much of the repo gets measured depends on which
package fails first, so the delta swings on unrelated changes. That is worse
than a wrong count, because it looks like a real movement.

**Pin the reporter.** pnpm picks a different output format on a TTY, and the
splice above depends on the non-TTY one. `--reporter=append-only`.

**One test report per package.** Each runner process resolves `--outputFile`
against its own directory, so one absolute path leaves only the package that
finished last. Collect the reports into a directory and pass the directory to
`render-tests.cjs`, which merges them.

**`git ls-tree` the config list.** The fetch-from-head step's hardcoded file
list is a single-package idea. A workspace has one `tsconfig.json` per package,
and a new package silently drops out of a fixed loop.

**The build may be a prerequisite for the typecheck here.** When packages
resolve their siblings through built `dist/*.d.ts`, `tsc --noEmit` on an unbuilt
tree reports phantom "cannot find module" errors for every sibling — one repo
measured 41 unbuilt against 0 built. In that layout the build *is* the
generation step from §1, so it runs first, and the general rule below does not
apply. Say it in the workflow comment, because it contradicts the default.

## 7. HTTP contract — optional, head only

Not in the templates, because it needs a running server. Worth describing,
because it catches what no static check can: a redirect that lost its
`Location`, a page that started returning 404, a `cache-control` header that
quietly went `no-store`.

Start the built server, wait for it to answer, then run a request-only test
suite against it — no browser, so no browser download. The mechanics that
matter:

- **Wait for readiness, and fail when it never comes.** A poll loop that falls
  through silently turns "the server never started" into sixty connection
  errors in the test output.
- **`maxRedirects: 0`.** Otherwise a 301 → 200 chain reads as 200 and the
  redirect assertions test nothing.
- **Assert only headers that are stable across two runs of the same build.**
  `date`, `etag`, `set-cookie` and the CDN's own request IDs are not.
- **List the routes literally.** A glob over the app's own routes passes when a
  route disappears, which is the failure the suite exists to catch.
- **Discover data from the app's own sitemap** rather than from fixtures, and
  skip rather than fail when the dataset is empty. That is what lets one suite
  run against an empty CI database and against production.

Run it under `continue-on-error` like every other check, or a contract failure
kills the job before the comment is posted.
