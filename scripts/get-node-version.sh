#!/bin/bash
# Fetches the latest Node.js v25.x release version from nodejs/node
#
# Usage: ./get-node-version.sh
# Output: Version number without 'v' prefix (e.g., 25.6.1)
#
# Requires: gh CLI (GitHub CLI)

set -e

VERSION=$(gh api repos/nodejs/node/releases \
  --jq '[.[] | select(.tag_name | startswith("v25.")) | .tag_name][0]' \
  | sed 's/^v//')

if [ -z "$VERSION" ]; then
  echo "ERROR: Could not determine Node.js v25.x version" >&2
  exit 1
fi

echo "$VERSION"
