# How this CI lies to you

Every entry below happened in a real adoption. They are grouped by what the
report says while it is wrong, because that is how you will meet them: not as an
error, but as a plausible number.

A delta reporter's failure mode is not a crash. It is **"no change"**.

## It reports clean, and nothing is checking

- **A piped step reports the last command's exit status.** GitHub Actions runs
  `run:` under `bash -e` with no `pipefail`, so `gate | tee` exits 0 however the
  gate exited. One repo shipped green while the gate printed three failures.
  Anything piped is affected, including `build | tee log`, which records a
  failed build as a success. Set the shell once at workflow level, not per step.
- **A tool that cannot run prints nothing your parser matches.** Do not read the
  exit code alone — `tsc --noEmit` exits 2 for "found errors", which is a
  perfectly successful run. The rule that generalises is **non-zero exit with no
  parseable output means it could not run**. Record that as "did not run" and
  block on it; a check that could not run is not a check that found nothing.
- **Read machine output, never a human formatter.** Text formats get reworded,
  colourised and dropped between versions, and the failure is always silent
  because your parser matches nothing. ESLint 9 moved the `unix` formatter out
  of core, so `-f unix` exits 2 with a line of advice — one repo ran ESLint in
  CI for months with it contributing zero issues, not because the code was
  clean. Ask for JSON, and treat an unparseable payload as "did not run".
- **A JSON payload whose shape changed parses fine and means nothing.** Reading
  `parsed.diagnostics ?? []` turns a renamed key into zero issues and a green
  report. Assert the key exists.
- **A compound typecheck hides most of itself.** `tsc -p a && tsc -p b && tsc -p
  c` stops at the first failure, so projects b and c are never checked. Fixing
  the last error in `a` then makes every pre-existing error in `b` and `c`
  appear as newly added.
- **A recursive runner stops at the first failing package.** `pnpm -r typecheck`
  measured 5 errors over 3 of 15 projects; with `--no-bail`, 41 over all 15.
  How much of the repo gets measured then depends on which package fails first,
  so the delta swings on unrelated changes. That is worse than a wrong count,
  because it looks like movement.
- **The check scripts were excluded from their own checks.** If head's scripts
  are copied *into* both trees, any issue in them cancels to "no change", so the
  usual fix is to exclude them from the deltas — after which a lint error or
  drift introduced in a check script is invisible to the gate by construction.
  Keeping head's tooling in a sibling directory avoids the whole problem.
- **The formatter gate's two lists never intersect.** The touched-file list and
  the drift list must have the same path shape — repo-root-relative, no `./`. A
  formatter run from a subdirectory, or a `--list-different` emitting absolute
  paths, makes the intersection empty on every PR, and the gate silently never
  fires again.
- **Both trees report zero because neither was measured.** An empty output
  directory passes an existence check, so a job that died right after creating
  it reads as a clean bill of health. Check for each expected file, not for the
  directory.
- **A dot-directory escapes the glob that was supposed to cover it.**
  TypeScript's `include: ["**/*.ts"]` does not match `.github/ci/`, so the CI
  code stays outside the typecheck however emphatically you intended otherwise.
  Whatever you do to make the check scripts subject to the repo's own checks,
  plant an error in one and confirm it is reported.
- **A GitHub expression treats `0` as false.** `fetch-depth: ${{ cond && 0 || 1
  }}` yields 1 on both branches of the condition, so a step that needed full
  history quietly got a shallow clone. Anything downstream that walks history
  then reports whatever a one-commit repository looks like.

## It reports change where there is none

- **A hash-stripping pattern that accepts a range of lengths matches too early.**
  In `client-entry-a1b2c3d4.js`, the substring `entry-a1b2c3d4` is itself inside
  a `{8,20}` range, so the key becomes `client.js`. Every chunk whose own name
  contains a dash then collapses onto a neighbour's key, and two different files
  compare as one unchanged chunk. Pin each accepted hash length exactly.
- **A recursive runner rewrites every path.** `pnpm -r`, `turbo`, `nx` and
  `lerna` prefix each line with the package while the tool's own path stays
  package-relative, so `packages/a/src/types.ts` and `packages/b/src/types.ts`
  both key as `src/types.ts`. Splice the two halves back together. Both trees
  produce the same wrong shape, so the delta looks plausible.
- **A typechecker prints one error per project that includes the file.** With
  project references, a shared directory belongs to several projects, so every
  error in shared code appears two or three times. Sort unique.
- **Locale changes sort order.** Under a UTF-8 locale `sort` ignores leading
  punctuation, so `.oxfmtrc.json` orders after `AGENTS.md`. Force byte order on
  both trees.
- **A CSS framework that scans the repository for class names** — Tailwind v4
  does — makes the CSS total depend on which files exist, so adding CI scripts
  moves it. Do not file this under noise: in two separate repos the scan was
  reading class-like strings out of the new CI scripts and shipping real
  generated CSS to every visitor, 3.4 kB in one and 1.6 kB in the other. Scope
  the scan to the client source *before* you measure anything — otherwise your
  first bundle report blames the PR for a pre-existing leak, and your second one
  hides it.
- **The sibling checkout is invisible only if the base tree ignores it.** The
  `.ci-head/` entry lives in head's ignore file, and the base job checks out the
  base branch, which has never heard of that path — so the base job walks into
  the directory it just created and reports head's files as its own. It hides
  from casual testing, because it only shows up when those files have issues.
  The ignore file is a judgment config; copy it with the others.
- **Absolute paths differ between two checkouts.** In a one-job worktree layout
  the base tree is at `/tmp/base-branch` and head at the workspace root, so any
  tool printing absolute paths reports every issue as one resolved plus one new.
- **The package manager looks for its version at the workspace root.** Check the
  tree out into a subdirectory — which the sibling-checkout layout does — and
  the setup action reads a `package.json` that is not there. Point it at the
  file explicitly rather than pinning the version a second time.

## It blocks the wrong person, or nobody

- **A broken base branch reads as the PR's fault.** Read both build outcomes, so
  a PR that inherits a broken base is told so rather than blamed, and a PR that
  repairs one hears that it did.
- **An absent touched-file list is not an empty PR.** Treat it as a crashed step
  and block. Otherwise a broken workflow reads as a clean bill of health.
- **Two-dot and three-dot diffs differ.** With the default `pull_request`
  checkout, `HEAD` is the merge ref, so a two-dot diff against the base SHA is
  the PR's own footprint. Check out the head SHA instead and two-dot silently
  widens to every file that landed on base since the branch diverged.
- **A build that exits zero having written nothing** measures as a triumphant
  −100%. Treat an empty measurement as a missing one. Whatever shape you
  measure, emit a file count, or that guard has nothing to read.
- **A crashed test runner leaves reports that parse.** In a workspace, each
  runner process resolves its output path against its own directory, so one
  absolute path keeps only whichever package finished last — and the files that
  do exist parse perfectly and count zero failures. Carry the step's own outcome
  into the report.
- **The gate only catches checks that reported.** A check whose job died writes
  no measurement at all, so a rule that inspects measurements never sees it.
  Name the outputs you expect and block on their absence.

## It damages the repository

- **Running the formatter in write mode to find drift eats uncommitted work.**
  The usual shape — format, diff, then restore with `git checkout -- .` — is
  correct in CI and destructive anywhere else. Worse on a dirty tree: the diff
  reports your edits as drift, and the restore rewrites files the shell is still
  reading, so the run produces partial output that looks like a result. Use the
  tool's read-only list mode. If it genuinely lacks one, do the write-and-restore
  in a throwaway copy.

## Traps in the writing, not the code

- **Matching the sticky comment on its visible heading.** Reword the heading and
  every comment on an open PR is orphaned, so the next run posts a second one.
  Use a hidden marker.
- **Retiring a comment string the new comment also starts with.** The workflow
  then deletes what it just posted.
- **Excluding vendored paths only in the tool's config.** Until the configs are
  shared, each tree reads its own, so a PR that edits an ignore rule moves its
  own baseline.
- **A content scan written against identifiers.** String literals survive
  minification and identifiers do not: `__TEST_ONLY__` is still there in the
  bundle, while `isTestMode` became `a`.
