#!/usr/bin/env bash
# Publish skills to your claude.ai account, which is what cloud sessions,
# Cowork, and routines load at session start. Local sessions do NOT use this —
# they read ~/.claude/skills, so run link-local.sh for those.
#
#   ./scripts/upload.sh              # every skill
#   ./scripts/upload.sh ci-delta-reports
#
# Needs ANTHROPIC_API_KEY, curl, and jq. Skill IDs are recorded in
# .skill-ids.json so a second run creates a new VERSION instead of a duplicate.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ID_MAP="$REPO_ROOT/.skill-ids.json"
API="https://api.anthropic.com/v1/skills"
BETA="skills-2025-10-02"

: "${ANTHROPIC_API_KEY:?set ANTHROPIC_API_KEY}"
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }
[ -f "$ID_MAP" ] || echo '{}' >"$ID_MAP"

# The Skills API accepts only the six Agent Skills spec fields. Anything else —
# argument-hint, disable-model-invocation, paths, model — fails the upload with
# a hard error, so catch it here where the message is actionable.
ALLOWED='^(name|description|license|compatibility|metadata|allowed-tools):'
validate() {
	local skill_md="$1" bad
	bad="$(awk '/^---$/{n++; next} n==1' "$skill_md" |
		grep -E '^[a-zA-Z-]+:' |
		grep -Ev "$ALLOWED" || true)"
	if [ -n "$bad" ]; then
		echo "  ✗ frontmatter fields the Skills API rejects:" >&2
		echo "$bad" | sed 's/^/      /' >&2
		return 1
	fi
}

upload_one() {
	local dir="$1" name existing args=() rel
	name="$(basename "$dir")"
	echo "→ $name"

	validate "$dir/SKILL.md" || return 1

	# Every file must carry a path-qualified filename so the API rebuilds the
	# directory structure. A version update replaces the whole file set, so
	# always send all of them.
	while IFS= read -r file; do
		rel="${file#"$dir"/}"
		args+=(-F "files[]=@$file;filename=$name/$rel")
	done < <(find "$dir" -type f ! -name '.DS_Store' | sort)

	existing="$(jq -r --arg n "$name" '.[$n] // empty' "$ID_MAP")"
	local url="$API"
	[ -n "$existing" ] && url="$API/$existing/versions"

	local response
	response="$(curl -sS -X POST "$url" \
		-H "x-api-key: $ANTHROPIC_API_KEY" \
		-H "anthropic-version: 2023-06-01" \
		-H "anthropic-beta: $BETA" \
		"${args[@]}")"

	local id
	id="$(printf '%s' "$response" | jq -r '.id // empty')"
	if [ -z "$id" ]; then
		echo "  ✗ upload failed:" >&2
		printf '%s\n' "$response" | jq . >&2 2>/dev/null || printf '%s\n' "$response" >&2
		return 1
	fi

	jq --arg n "$name" --arg i "$id" '.[$n] = $i' "$ID_MAP" >"$ID_MAP.tmp" && mv "$ID_MAP.tmp" "$ID_MAP"
	echo "  ✓ ${existing:+new version of }$id ($(printf '%s' "$response" | jq -r '.version'))"
}

failed=0
if [ $# -gt 0 ]; then
	for name in "$@"; do
		upload_one "$REPO_ROOT/skills/$name" || failed=$((failed + 1))
	done
else
	for dir in "$REPO_ROOT"/skills/*/; do
		[ -f "$dir/SKILL.md" ] || continue
		upload_one "${dir%/}" || failed=$((failed + 1))
	done
fi

echo
if [ "$failed" -gt 0 ]; then
	echo "$failed skill(s) failed to upload." >&2
	exit 1
fi
echo "Done. Enable them at claude.ai → Settings → Capabilities → Skills."
