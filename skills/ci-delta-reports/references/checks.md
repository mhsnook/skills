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
| ESLint | `-f unix` |
| oxlint | `-f unix` |
| Ruff | `--output-format concise` |
| golangci-lint | `--out-format line-number` |
| Clippy | `--message-format short` |

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
  trend — report it as a percentage of the limit. `wrangler deploy --dry-run`
  is the cheap companion check: it bundles exactly as a deploy would and
  validates the bindings, without deploying.
- **A framework with a split output** (`dist/client` + `dist/server`, `.next/`):
  measure the two halves on separate axes. They move for different reasons and
  a combined total tells you nothing about either.

**Watch for:** a bundler that reads environment variables at build time may
tree-shake large dependencies away when those variables are missing, producing
a build that looks dramatically smaller and means nothing. Set dummy-but-truthy
values in CI and sanity-check that a known dependency is present in the output.

**Watch for:** a build that exits zero having written nothing. Measured against
a real base, that reports a triumphant −100%. Treat an empty measurement the
same as a missing one.

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
