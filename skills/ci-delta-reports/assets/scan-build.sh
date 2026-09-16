#!/usr/bin/env bash
# Check 6: scan the built output for code that must never ship.
#
#   bash scan-build.sh dist [fragment-dir]
#
# With a fragment directory, the scan writes `60-scan.md` and `60-scan.json`
# into it, so a leak appears in the PR comment beside every other check rather
# than only as a red job nobody opens.
#
# Runs over the SAME dist/ the bundle measurement just read — never build twice
# for two scans. Head branch only: there is nothing to diff, a string either
# leaked or it did not.
#
# This is the one check with no portable default, because "must never ship"
# means something different in every project. The entries below are examples.
# Replace them, and keep the reason on each line — a bare regex list rots
# within months and nobody dares delete an entry they cannot explain.

set -uo pipefail

DIST="${1:?usage: scan-build.sh <build-output-dir> [fragment-dir]}"
FRAGMENTS="${2:-}"
[ -d "$DIST" ] || { echo "no such directory: $DIST" >&2; exit 2; }

# CONFIGURE: one entry per forbidden pattern, as "regex<TAB>why it must not ship".
FORBIDDEN=(
	'__TEST_ONLY__	test-only helpers reachable from the production entry point'
	'localhost:[0-9]{4}	a development hostname baked into the build'
	'console\.debug	debug logging left enabled'
)

# CONFIGURE: files to search. Source maps legitimately contain original source,
# so scanning them produces hits that mean nothing.
#
# `mapfile` rather than word splitting, so a path containing a space is one
# entry rather than two nonexistent ones.
mapfile -t FILES < <(find "$DIST" -type f \( -name '*.js' -o -name '*.css' -o -name '*.html' \) ! -name '*.map')
[ "${#FILES[@]}" -gt 0 ] || { echo "no scannable files in $DIST" >&2; exit 2; }

found=0
report=()
for entry in "${FORBIDDEN[@]}"; do
	pattern="${entry%%	*}"
	reason="${entry#*	}"
	hits=$(grep -rlE "$pattern" "${FILES[@]}" 2>/dev/null || true)
	if [ -n "$hits" ]; then
		# `::error::` puts the reason on the run summary and on the file, where a
		# contributor sees it without reading the log.
		echo "::error::$reason"
		echo "   pattern: $pattern"
		echo "$hits" | sed 's|^|   |'
		report+=("- ❌ **$reason** — \`$pattern\`")
		while IFS= read -r hit; do report+=("  - \`$hit\`"); done <<<"$hits"
		found=$((found + 1))
	fi
done

if [ -n "$FRAGMENTS" ]; then
	mkdir -p "$FRAGMENTS"
	{
		echo "#### Build content scan"
		echo
		if [ "$found" -gt 0 ]; then
			echo "❌ **$found forbidden pattern(s) reached the build output.**"
			echo
			printf '%s\n' "${report[@]}"
		else
			echo "✅ Build output clean — ${#FORBIDDEN[@]} pattern(s) checked."
		fi
	} >"$FRAGMENTS/60-scan.md"
	printf '{\n\t"check": "scan",\n\t"found": %d,\n\t"checked": %d\n}\n' \
		"$found" "${#FORBIDDEN[@]}" >"$FRAGMENTS/60-scan.json"
fi

if [ "$found" -gt 0 ]; then
	echo
	echo "$found forbidden pattern(s) reached the production build."
	exit 1
fi

echo "✅ build output clean — ${#FORBIDDEN[@]} pattern(s) checked"
