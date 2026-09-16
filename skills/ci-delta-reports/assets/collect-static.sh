#!/usr/bin/env bash
# Collect normalised static-check output into $1.
#
# Runs once on the head tree and once on the base tree, always from that tree's
# own root. Output is one sorted line per issue, so the diff engine can treat
# the two runs as comparable sets.
#
# NOTE: this script ends by restoring the tree with `git checkout -- .`. That is
# correct in CI, where the checkout is clean. Run it against a working tree with
# uncommitted edits and it discards them.

# Deliberately no `-e`: every check here exits non-zero when it finds issues,
# which is the normal case, not a script failure.
set -uo pipefail

OUT="${1:?usage: collect-static.sh <output-dir>}"
mkdir -p "$OUT"

# Byte-order sorting, so the two trees produce comparable lists even if the two
# runners ever differ in locale. `sort` under a UTF-8 locale ignores leading
# punctuation, which would order `.oxfmtrc.json` after `AGENTS.md`.
export LC_ALL=C

# CONFIGURE: paths kept out of the lint and formatter deltas. Vendored and
# generated code produces noise nobody on the PR can act on.
#
# Repeat here whatever the linter and formatter configs already ignore. Each
# tree is measured with its own config, so a PR that edits one of those configs
# would otherwise move its own baseline.
#
# `.github/ci/` is in the list for a different reason: the base job checks these
# scripts out from head, so BOTH trees lint head's copy and any issue in them
# cancels to "no change". That is a number which cannot move, so it is noise.
EXCLUDE='^(vendor/|third_party/|dist/|\.github/ci/|.*\.generated\.[jt]s$)'

# CONFIGURE: code generation the typechecker needs, if any — `next typegen`,
# `wrangler types`, `prisma generate`, a protobuf step. Run it here rather than
# making the build a prerequisite: the typecheck should report on a tree that
# does not build.
# pnpm exec wrangler types >/dev/null 2>&1

# Read-only checks run concurrently. The typechecker is the long pole and the
# linters finish underneath it, so this is close to free.
(
	# CONFIGURE: your typecheck command. Keep the grep — it drops the summary
	# lines, which change with the error count and would diff as noise.
	#
	# `sort -u`, not `sort`. With TypeScript project references, a file in a
	# shared directory belongs to several projects, so `tsc --build` prints each
	# error in it once PER PROJECT. Keeping the duplicates doubles every
	# shared-code delta.
	pnpm exec tsc --build 2>&1 | grep ': error TS' | sort -u >"$OUT/typecheck.txt"
	status=${PIPESTATUS[0]}

	# A typechecker that failed but printed nothing the grep recognises would
	# leave an empty file, which reads as zero errors and merges clean. This
	# happens with any compound command (`wrangler types --check && tsc`), where
	# the first half can fail in its own format. Record the failure as an issue.
	if [ "$status" -ne 0 ] && [ ! -s "$OUT/typecheck.txt" ]; then
		echo "typecheck:0:0: error TS0000: the typechecker exited $status without recognisable error lines — see the job log" \
			>"$OUT/typecheck.txt"
	fi
) &
(
	# CONFIGURE: one block per linter, all normalised to unix format
	# (`file:line:col: message`) so they merge into a single sorted list.
	#
	# Call the TOOL, not the package script. The base tree is the base branch,
	# and on the PR that introduces a script, the base tree does not have it.
	# Keep the package script for humans; CI runs the binary.
	pnpm exec oxlint . -f unix >"$OUT/.oxlint.raw" 2>&1
	oxlint_status=$?
	pnpm exec eslint . -f unix >"$OUT/.eslint.raw" 2>&1
	eslint_status=$?
	cat "$OUT/.oxlint.raw" "$OUT/.eslint.raw" |
		grep -E '^[^:[:space:]][^:]*:[0-9]+:[0-9]+:' |
		grep -Ev "$EXCLUDE" |
		sort -u >"$OUT/lint.txt"

	# A linter exits 1 when it found issues and 2 when it could not RUN — a bad
	# config, a missing formatter package, a parse error. Exit 2 prints nothing
	# the grep matches, so without this the report reads "0 lint issues".
	for status in "$oxlint_status" "$eslint_status"; do
		if [ "$status" -gt 1 ]; then
			echo "lint:0:0: error: a linter exited $status without running — see the job log" \
				>>"$OUT/lint.txt"
		fi
	done
) &
wait

# The formatter REWRITES files, so it runs after the read-only checks. The set
# of files it modified is exactly the formatting debt — no separate --check
# pass needed. Restore the tree afterwards so later steps see a clean checkout.
# CONFIGURE: your formatter command(s). If two formatters cover different file
# types, run both — the output is a path list either way.
pnpm exec oxfmt . >/dev/null 2>&1
git diff --name-only | grep -Ev "$EXCLUDE" | sort >"$OUT/format.txt"
git checkout -- .

# Never let a missing file break the render step.
#
# `touched.txt` is deliberately NOT in this list. The workflow writes it into
# the same directory on the head tree only, and the formatter gate reads its
# ABSENCE as "the step that lists this PR's files did not run" — an empty file
# here would turn that failure into a silent pass.
for f in typecheck lint format; do
	[ -f "$OUT/$f.txt" ] || : >"$OUT/$f.txt"
done

wc -l "$OUT"/*.txt
