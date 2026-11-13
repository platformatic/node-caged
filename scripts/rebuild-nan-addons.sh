#!/bin/sh
#
# Detect native addons that are tied to the Node.js ABI (NAN / raw V8 API)
# and rebuild them from source against the running pointer-compressed
# Node.js. Prebuilt binaries for these addons target stock Node.js and
# segfault under pointer compression. N-API addons are left untouched.
#
# Usage: rebuild-nan-addons [path/to/node_modules]
#
# Environment:
#   REBUILD_NAN_ADDONS_PATH         node_modules to scan (default: ./node_modules)
#   REBUILD_NAN_ADDONS_DETECT_ONLY  set to 1 to list addons without rebuilding
#
# Rebuilding needs python3, make, a C++ compiler and (when the npm tarball
# lacks sources) git. These are not present in the runtime images; run this
# in a build stage. See the README for a multi-stage example.

set -u

node_modules="${1:-${REBUILD_NAN_ADDONS_PATH:-$PWD/node_modules}}"
detect_only="${REBUILD_NAN_ADDONS_DETECT_ONLY:-0}"

if [ ! -d "$node_modules" ]; then
  echo "ERROR: $node_modules does not exist (pass a path or set REBUILD_NAN_ADDONS_PATH)" >&2
  exit 1
fi
node_modules="$(cd "$node_modules" && pwd)"

# Build against the headers of the running Node.js, not the ones node-gyp
# would download from nodejs.org for the stock (uncompressed) build.
node_prefix="$(dirname "$(dirname "$(command -v node)")")"
if [ -f "$node_prefix/include/node/common.gypi" ]; then
  npm_config_nodedir="$node_prefix"
  export npm_config_nodedir
fi

node_gyp() {
  npm_dir="$(dirname "$(dirname "$(readlink -f "$(command -v npm)")")")"
  if [ -f "$npm_dir/node_modules/node-gyp/bin/node-gyp.js" ]; then
    node "$npm_dir/node_modules/node-gyp/bin/node-gyp.js" "$@"
  else
    npx --yes node-gyp "$@"
  fi
}

check_build_tools() {
  missing=""
  for tool in python3 make; do
    command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
  done
  command -v c++ >/dev/null 2>&1 || command -v g++ >/dev/null 2>&1 || missing="$missing c++"
  if [ -n "$missing" ]; then
    echo "ERROR: missing build tools:$missing" >&2
    echo "  Debian: apt-get install -y python3 make g++ git" >&2
    echo "  Alpine: apk add python3 make g++ git" >&2
    exit 1
  fi
}

has_sources() {
  find "$1" -maxdepth 4 -path "$1/node_modules" -prune -o \
    \( -name "*.cc" -o -name "*.cpp" -o -name "*.c" \) -print 2>/dev/null | grep -q .
}

# Returns 0 if a package with binding.gyp is ABI-specific (NAN or raw V8),
# 1 if it is N-API or cannot be determined.
uses_nan() {
  pkg_dir="$1"

  if has_sources "$pkg_dir"; then
    find "$pkg_dir" -maxdepth 4 -path "$pkg_dir/node_modules" -prune -o \
      \( -name "*.cc" -o -name "*.cpp" -o -name "*.h" \) -print 2>/dev/null |
      xargs grep -l '#include.*[<"]nan\.h[>"]' 2>/dev/null | grep -q .
    return $?
  fi

  # No sources: inspect a prebuilt binary for NAN symbols
  node_bin="$(find "$pkg_dir" -path "$pkg_dir/node_modules" -prune -o -name "*.node" -print 2>/dev/null | head -n 1)"
  [ -n "$node_bin" ] || return 1
  if command -v nm >/dev/null 2>&1 && nm -D "$node_bin" 2>/dev/null | grep -q '_ZN3Nan'; then
    return 0
  fi
  grep -q 'nan\.h' "$node_bin" 2>/dev/null
}

# Returns 0 if a package without binding.gyp ships ABI-versioned prebuilds
# (node-gyp-build / prebuildify). N-API prebuilds contain "napi" in the name.
uses_prebuilt_nan() {
  pkg_dir="$1"
  [ -f "$pkg_dir/binding.gyp" ] && return 1
  find "$pkg_dir/prebuilds" -name "*.node" ! -name "*napi*" 2>/dev/null | grep -q .
}

pkg_field() {
  node -e '
    const p = require(process.argv[1])
    let v = p[process.argv[2]]
    if (v && typeof v === "object") v = v.url
    process.stdout.write(v ? String(v) : "")
  ' "$1/package.json" "$2"
}

# Fetch binding.gyp and sources from the package git repository at the
# tag matching the installed version, for tarballs that only ship prebuilds.
fetch_sources() {
  pkg_dir="$1"
  pkg_version="$2"
  pkg_repo="$(pkg_field "$pkg_dir" repository | sed -e 's|^git+||' -e 's|^git://|https://|')"

  if [ -z "$pkg_repo" ]; then
    echo "  FAILED: no repository URL in package.json" >&2
    return 1
  fi
  if ! command -v git >/dev/null 2>&1; then
    echo "  FAILED: sources missing and git is not installed" >&2
    return 1
  fi

  tmp_dir="$(mktemp -d)"
  for tag in "v$pkg_version" "$pkg_version"; do
    if git clone -q --depth=1 --branch="$tag" "$pkg_repo" "$tmp_dir/src" 2>/dev/null; then
      if [ ! -f "$tmp_dir/src/binding.gyp" ]; then
        echo "  FAILED: no binding.gyp at the root of $pkg_repo@$tag" >&2
        rm -rf "$tmp_dir"
        return 1
      fi
      # Copy the repository over the package without clobbering what npm
      # installed (package.json, dist files, node_modules).
      rm -rf "$tmp_dir/src/.git" "$tmp_dir/src/node_modules"
      for entry in "$tmp_dir/src"/* "$tmp_dir/src"/.[!.]*; do
        [ -e "$entry" ] || continue
        [ -e "$pkg_dir/$(basename "$entry")" ] || cp -R "$entry" "$pkg_dir/"
      done
      rm -rf "$tmp_dir"
      return 0
    fi
  done

  rm -rf "$tmp_dir"
  echo "  FAILED: could not clone $pkg_repo at v$pkg_version or $pkg_version" >&2
  return 1
}

rebuild_pkg() {
  pkg_dir="$1"
  pkg_name="$(pkg_field "$pkg_dir" name)"
  pkg_version="$(pkg_field "$pkg_dir" version)"

  echo "Found ABI-specific addon: $pkg_name@$pkg_version ($pkg_dir)"
  [ "$detect_only" = "1" ] && return 0

  if ! has_sources "$pkg_dir" || [ ! -f "$pkg_dir/binding.gyp" ]; then
    echo "  Sources missing, fetching from git..."
    fetch_sources "$pkg_dir" "$pkg_version" || return 1
  fi

  (
    cd "$pkg_dir" || exit 1
    # binding.gyp usually resolves headers via require('nan'); install the
    # package's own dependencies only if they are not already resolvable.
    if ! node -e "require.resolve('nan')" >/dev/null 2>&1; then
      echo "  Installing build dependencies for $pkg_name..."
      npm install --ignore-scripts --no-save --no-audit --no-fund --no-package-lock || exit 1
    fi
    echo "  Rebuilding $pkg_name..."
    node_gyp rebuild --release
  ) || { echo "  FAILED: $pkg_name" >&2; return 1; }

  echo "  OK: $pkg_name"
}

[ "$detect_only" = "1" ] || check_build_tools

echo "Scanning for ABI-specific native addons in $node_modules..."

# Top-level packages and scoped packages only (node_modules/pkg and
# node_modules/@scope/pkg); nested node_modules are skipped.
list_packages() {
  for dir in "$node_modules"/* "$node_modules"/@*/*; do
    case "$dir" in
      "$node_modules"/@*/*) ;;
      "$node_modules"/@*) continue ;;
    esac
    [ -f "$dir/package.json" ] && printf '%s\n' "$dir"
  done
}

failed=0
found=0
# Read from a file instead of a pipe so counters survive the loop.
pkg_list="$(mktemp)"
list_packages > "$pkg_list"
while IFS= read -r pkg_dir; do
  if [ -f "$pkg_dir/binding.gyp" ]; then
    uses_nan "$pkg_dir" || continue
  else
    uses_prebuilt_nan "$pkg_dir" || continue
  fi
  found=$((found + 1))
  rebuild_pkg "$pkg_dir" || failed=$((failed + 1))
done < "$pkg_list"
rm -f "$pkg_list"

echo "Found $found ABI-specific addon(s)."
if [ "$failed" -gt 0 ]; then
  echo "ERROR: $failed native addon rebuild(s) failed" >&2
  exit 1
fi
