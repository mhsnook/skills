#!/usr/bin/env bash
# Two hooks in one script, driving a short naming-and-comments pass at the end
# of any turn that edited code.
#
#   record  PostToolUse on Edit|Write|NotebookEdit. Notes the path, if it looks
#           like code, in a per-session scratch file.
#   check   Stop. If that scratch file has anything in it, hands Claude the
#           checklist in naming-pass.md and lets the turn continue.
#
# Claude Code owns the loop protection: `stop_hook_active` is true on any Stop
# that is itself the product of a stop hook continuing the turn, and we allow
# the stop there rather than asking for a pass on the pass. The scratch file is
# also cleared the moment it is read, so the checklist goes out at most once per
# turn even if that flag ever changes meaning.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKLIST="$SCRIPT_DIR/naming-pass.md"

# CLAUDE_PLUGIN_DATA is set when this runs as an installed plugin; the temp dir
# is the fallback for a hand-wired settings.json.
STATE_DIR="${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}/claude-naming-pass}"

# Extensions the pass applies to. Prose and config hold no variable names worth
# improving, so a turn that only touched those is not a code-editing turn.
EXTENSIONS="${NAMING_PASS_EXTENSIONS:-ts tsx js jsx mjs cjs py rb go rs java kt swift m c h cpp hpp cc cs php scala ex exs sh bash zsh sql vue svelte astro}"

if [ "${NAMING_PASS_DISABLE:-}" = "1" ]; then
	exit 0
fi

command -v jq >/dev/null || exit 0

mode="${1:-}"
input="$(cat)"

session="$(jq -j '.session_id // ""' <<<"$input" | tr -c 'A-Za-z0-9_-' '_')"
[ -n "$session" ] || session="unknown"
state="$STATE_DIR/$session.files"

case "$mode" in
record)
	file="$(jq -j '.tool_input.file_path // .tool_input.notebook_path // ""' <<<"$input")"
	[ -n "$file" ] || exit 0

	# Basename first, so a dot in a parent directory can't pose as an extension.
	ext="$(printf '%s' "${file##*/}" | awk -F. 'NF > 1 { print tolower($NF) }')"
	[ -n "$ext" ] || exit 0
	case " $EXTENSIONS " in
	*" $ext "*) ;;
	*) exit 0 ;;
	esac

	mkdir -p "$STATE_DIR"
	printf '%s\n' "$file" >>"$state"
	;;

check)
	# A Stop that only happened because a stop hook continued the turn — the
	# pass has already run, so drop whatever it edited rather than holding it
	# over and asking for a pass on unrelated files next turn.
	if [ "$(jq -j '.stop_hook_active // false' <<<"$input")" != "false" ]; then
		rm -f "$state"
		exit 0
	fi

	[ -s "$state" ] || exit 0
	[ -f "$CHECKLIST" ] || exit 0

	files="$(sort -u "$state")"
	rm -f "$state"

	# Sessions that never reach a Stop leave their scratch file behind.
	find "$STATE_DIR" -name '*.files' -mtime +7 -delete 2>/dev/null || true

	jq -n --rawfile checklist "$CHECKLIST" --arg files "$files" '{
		hookSpecificOutput: {
			hookEventName: "Stop",
			additionalContext: ($checklist + "\nFiles changed this turn:\n" + $files)
		}
	}'
	;;

*)
	echo "usage: naming-pass.sh record|check  (hook input on stdin)" >&2
	exit 1
	;;
esac
