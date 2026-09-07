#!/usr/bin/env bash
# Check out .github/ci/ from the head SHA, over the base branch's copy.
#
#   bash fetch-scripts.sh <headSha>
#
# Both trees must be measured by the SAME scripts. If each side used its own
# version, a PR that edits a collection script would read as a change in the
# codebase. Pinning both to head keeps the comparison about the code.
set -euo pipefail

HEAD_SHA="${1:?usage: fetch-scripts.sh <headSha>}"

git fetch --no-tags --depth=1 origin "$HEAD_SHA"
git checkout "$HEAD_SHA" -- .github/ci/
