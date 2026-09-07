#!/usr/bin/env bash
# List the files this PR touches, into <outDir>/touched.txt.
#
#   bash list-touched.sh <baseSha> <outDir>
#
# Only the formatter gate needs this: it is scoped to the PR's own footprint
# rather than to a delta. Drop the step from the workflow if formatting is
# report-only.
#
# Two-dot diff, because the default checkout for `pull_request` is the MERGE
# ref — base is already merged in — so base..HEAD is exactly this PR's own
# changes. If you change the checkout to `ref: github.event.pull_request.head.sha`,
# switch to the three-dot form and drop the shallow fetch, or you will pick up
# every file that landed on base since the branch diverged.
set -euo pipefail

BASE_SHA="${1:?usage: list-touched.sh <baseSha> <outDir>}"
OUT="${2:?usage: list-touched.sh <baseSha> <outDir>}"

mkdir -p "$OUT"
git fetch --no-tags --depth=1 origin "$BASE_SHA"
git diff --name-only --diff-filter=d "$BASE_SHA" HEAD | sort >"$OUT/touched.txt"
wc -l "$OUT/touched.txt"
