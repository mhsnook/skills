#!/usr/bin/env bash
# Symlink every skill in this repo into ~/.claude/skills, making them available
# in every LOCAL Claude Code session.
#
# Symlinks rather than copies, because Claude Code follows them and watches the
# target for changes: edit a SKILL.md here and the running session picks it up
# without a restart.
#
# This does nothing for cloud, Cowork, or routine sessions — those read the
# skills enabled on your claude.ai account, not this machine. Use upload.sh.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"

mkdir -p "$TARGET"

linked=0
for dir in "$REPO_ROOT"/skills/*/; do
	[ -f "$dir/SKILL.md" ] || continue
	name="$(basename "$dir")"
	dest="$TARGET/$name"

	if [ -e "$dest" ] && [ ! -L "$dest" ]; then
		echo "skip  $name — a real directory is already there, not replacing it" >&2
		continue
	fi

	ln -sfn "${dir%/}" "$dest"
	echo "link  $name → $dest"
	linked=$((linked + 1))
done

echo
echo "Linked $linked skill(s) into $TARGET"
