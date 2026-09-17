# How this CI reports the wrong answer

Each entry below happened in a real adoption. They are grouped by what the
report says while it is wrong, because that grouping matches how you meet them:
not as an error, but as a plausible number.

A delta reporter rarely fails by crashing. It fails by saying **"no change"**.

Each entry names the layout it applies to where that matters, so you can tell
which ones your design has already solved.

## It reports clean, and nothing is checking

- **A pipeline exits with its LAST command's status, so `errexit` alone does not
  catch a failure upstream of a pipe.** This holds for every POSIX shell and
  every runner that spawns one. GitHub Actions runs `run:` under `bash -e`
  without `pipefail`, so `gate | tee` exits 0 however the gate exited — one
  repository shipped a green run while the gate printed three failures, and
  `build | tee log` recorded a failed build as a success. Set `pipefail` where
  your runner defines the shell, once rather than per step, or keep the command
  whose status you need out of a pipe.
- **A tool that cannot run prints nothing your parser matches.** Read more than
  the exit code: `tsc --noEmit` exits 2 when it finds errors, which is a
  successful run. The rule that generalises is that **a non-zero exit with no
  parseable output means the tool could not run.** Record that as "did not run"
  and block on it, because a check that could not run has not found zero issues.
- **Read machine output rather than a human formatter.** A text format can get
  reworded, colourised or dropped between versions, and your parser then matches
  nothing. ESLint 9 moved its `unix` formatter out of core, so
  `-f unix` exits 2 with a line of advice — one repository ran ESLint in CI for
  months with it contributing zero issues, while its code was not clean. Ask the
  tool for JSON, and treat an unparseable payload as "did not run".
- **A JSON payload whose shape changed still parses, and still means nothing.**
  Reading `parsed.diagnostics ?? []` turns a renamed key into zero issues and a
  green report, so assert that the key exists.
- **A compound typecheck hides most of itself.** `tsc -p a && tsc -p b && tsc -p
  c` stops at the first project that fails, so it checks neither b nor c. Fixing
  the last error in `a` then makes every pre-existing error in `b` and `c` read
  as newly added.
- **A recursive runner stops at the first failing package.** `pnpm -r typecheck`
  measured 5 errors across 3 of 15 projects; with `--no-bail`, it measured 41
  across all 15. Without that flag, how much of the repository gets measured
  depends on which package fails first, so the delta swings on unrelated
  changes. That is worse than a wrong count, because it looks like movement.
- **The check scripts sat outside their own checks.** *(Copy-over layouts.)* If
  the base job copies head's scripts *into* both trees, an issue in a script
  appears on both sides and cancels to "no change", so adopters exclude those
  scripts from the deltas — after which drift in a check script escapes the gate
  by construction. Running head's tooling from a sibling directory removes the
  cancellation, so the exclusion becomes unnecessary.
- **The formatter gate's two lists do not intersect.** The touched-file list and
  the drift list need the same path shape — repo-root-relative, with no `./`
  prefix. A formatter run from a subdirectory, or a `--list-different` that
  emits absolute paths, empties the intersection on every pull request, and the
  gate then stops firing.
- **Both trees report zero because the runner measured neither.** An empty
  output directory satisfies an existence check, so a job that died right after
  creating that directory reads as a clean bill of health. Check for each
  expected file rather than for the directory, and check that the file is
  non-empty, because a build that wrote nothing is the same failure in disguise.
- **A dot-directory escapes the glob that was supposed to cover it.** *(Any
  layout.)* TypeScript's `include: ["**/*.ts"]` does not match `.github/ci/`, so
  the CI code stays outside the typecheck however firmly you intended otherwise.
  Put the scripts in a directory whose name does not start with a dot — `ci/` at
  the repository root — which removes the problem without a config change. Then
  plant an error in a check script and confirm the report names it.
- **A GitHub expression treats `0` as false.** *(GitHub Actions.)* `fetch-depth:
  ${{ cond && 0 || 1 }}` yields 1 on both branches of the condition, so a step
  that needed full history got a shallow clone, and anything downstream that
  walks history reports what a one-commit repository looks like.

## It reports a change where nothing changed

- **A hash-stripping pattern that accepts a range of lengths matches too early.**
  In `client-entry-a1b2c3d4.js`, the substring `entry-a1b2c3d4` falls inside a
  `{8,20}` range, so the key becomes `client.js`. Every chunk whose own name
  contains a dash then collapses onto a neighbour's key, and the report compares
  two different files as one unchanged chunk. Pin each accepted hash length
  exactly.
- **A recursive runner rewrites every path.** `pnpm -r`, `turbo`, `nx` and
  `lerna` prefix each line with the package directory while the tool's own path
  stays package-relative, so `packages/a/src/types.ts` and
  `packages/b/src/types.ts` both key as `src/types.ts`. Splice the two halves
  back together. Both trees produce the same wrong shape, so the delta looks
  plausible while same-named files collide across packages.
- **A typechecker prints one error per project that includes the file.** With
  project references, a shared directory belongs to several projects, so every
  error in shared code appears two or three times. Sort unique.
- **The locale changes the sort order.** Under a UTF-8 locale, `sort` ignores
  leading punctuation, so it orders `.oxfmtrc.json` after `AGENTS.md`. Force
  byte order on both trees.
- **A CSS framework that scans the repository for class names** — Tailwind v4
  does — makes the CSS total depend on which files exist, so the CI scripts you
  add move it. This belongs under real changes rather than noise: in two
  repositories the scan read class-like strings out of the new CI scripts and
  shipped real generated CSS to every visitor, 3.4 kB in one and 1.6 kB in the
  other. Scope that scan to the client source *before* you measure anything, or
  your first bundle report blames the pull request for a leak that predates it,
  and your second report hides the leak.
- **The base tree does not ignore a checkout placed inside it.** *(Instrument
  inside the measured tree.)* An ignore rule for `.ci-head/` lives on head, and
  the base job checks out the base branch, which does not contain that rule — so
  the base job's linter walks into the directory the workflow just created and
  reports head's files as the base branch's own. It hides from casual testing,
  because it shows up only once those files carry issues. Two sibling
  directories make this unreachable; copying head's ignore file in is the
  weaker fix.
- **Two checkouts sit at different absolute paths.** *(Worktree layout.)* The
  base tree lives at `/tmp/base-branch` and head at the workspace root, so any
  tool that prints absolute paths reports every issue as one resolved plus one
  new.
- **The package manager looks for its version at the workspace root.** A
  sibling-checkout layout puts the tree one level down, so the setup action
  reads a `package.json` that is not there. Pass it the path explicitly, rather
  than pinning the version a second time.

## It blocks the wrong person, or blocks nobody

- **A broken base branch reads as the author's fault.** Read both build
  outcomes, so the report tells an author who inherited a broken base that they
  inherited it, and tells an author who repaired one that they did.
- **An absent touched-file list is not an empty pull request.** Treat it as a
  crashed step and block, because otherwise a broken workflow reads as a clean
  bill of health.
- **Two-dot and three-dot diffs answer different questions.** Under the default
  `pull_request` checkout, `HEAD` is the merge ref, so a two-dot diff against
  the base SHA gives the pull request's own footprint. If you check out the head
  SHA instead, that two-dot diff widens to every file that landed on the base
  branch since the author created their branch.
- **A build that exits zero having written nothing** measures as a triumphant
  −100%. Treat an empty measurement as a missing one, and emit a file count
  whatever shape you measure, or that guard has nothing to read.
- **A crashed test runner leaves reports that parse.** In a workspace, each
  runner process resolves its output path against its own directory, so one
  absolute path keeps only whichever package finished last — and the files that
  survive parse perfectly and count zero failures. Carry the test step's own
  outcome into the report.
- **The gate sees only the checks that reported.** A check whose job died writes
  no measurement at all, so a rule that inspects measurements does not see it.
  Name the outputs you expect, and block when one is absent.

## It damages the repository

- **Running the formatter in write mode to find drift destroys uncommitted
  work.** The usual shape — format, diff, then restore with `git checkout -- .`
  — is correct in CI, where the checkout is clean, and destructive anywhere
  else. On a dirty tree it does worse: the diff reports the developer's edits as
  drift, and the restore rewrites files the shell is still reading, so the run
  produces partial output that looks like a result. Use the formatter's
  read-only list mode. If a formatter genuinely lacks one, do the
  write-and-restore in a throwaway copy.

## Traps in the writing, rather than in the code

- **Excluding vendored paths in the tool's config alone.** Until both trees
  share head's configs, each tree reads its own, so a pull request that edits an
  ignore rule moves its own baseline.
