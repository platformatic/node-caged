#!/bin/bash
# Fetches the latest Node.js v26.x release version from nodejs/node
#
# Usage: ./get-node-version.sh
# Output: Version number without 'v' prefix (e.g., 26.1.0)
#
# Requires: gh CLI (GitHub CLI)

set -e

VERSION=$(gh api repos/nodejs/node/releases \
  --jq '[.[] | select(.tag_name | startswith("v26.")) | .tag_name][0]' \
  | sed 's/^v//')

if [ -z "$VERSION" ]; then
  echo "ERROR: Could not determine Node.js v26.x version" >&2
  exit 1
fi

echo "$VERSION"
