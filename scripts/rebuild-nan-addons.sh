#!/bin/sh

node_modules="${REBUILD_NAN_ADDONS_PATH:-/usr/src/app/node_modules}"
detect_only="${REBUILD_NAN_ADDONS_DETECT_ONLY:-0}"
fail_marker="$(mktemp)"
rm -f "$fail_marker"

if [ ! -d "$node_modules" ]; then
  exit 0
fi

# Returns 0 if the package uses nan (needs rebuild), 1 if it's N-API or not native
uses_nan() {
  pkg_dir="$1"

  # Must have binding.gyp to be a native addon
  [ -f "$pkg_dir/binding.gyp" ] || return 1

  # If source files exist, check them for nan.h include
  src_files="$(find "$pkg_dir" -maxdepth 4 \( -name "*.cc" -o -name "*.cpp" -o -name "*.h" \) 2>/dev/null)"
  if [ -n "$src_files" ]; then
    echo "$src_files" | xargs grep -l '#include.*[<"]nan\.h[>"]' 2>/dev/null | grep -q . && return 0
    return 1
  fi

  # No source files: inspect the prebuilt .node binary for nan symbols
  node_bin="$(find "$pkg_dir" -name "*.node" -print -quit 2>/dev/null)"
  if [ -n "$node_bin" ]; then
    nm -D "$node_bin" 2>/dev/null | grep -q '_ZN3Nan' && return 0
    strings "$node_bin" 2>/dev/null | grep -q 'nan\.h' && return 0
  fi

  return 1
}

# Returns 0 if the package uses ABI-versioned prebuilt .node files (node-gyp-build pattern)
# These are NAN-style (not N-API) because they are keyed by Node ABI version.
# Skips packages that also have binding.gyp (already handled by uses_nan).
uses_prebuilt_nan() {
  pkg_dir="$1"

  # Skip if it has binding.gyp — handled by the binding.gyp loop
  [ -f "$pkg_dir/binding.gyp" ] && return 1

  # Must have prebuilds/ with ABI-versioned .node files (node-*.node naming = NAN/ABI-specific)
  find "$pkg_dir/prebuilds" -name "node-*.node" -print -quit 2>/dev/null | grep -q . || return 1

  return 0
}

rebuild_pkg() {
  pkg_dir="$1"

  pkg_json="$pkg_dir/package.json"
  pkg_name="$(node -pe "require('$pkg_json').name" 2>/dev/null)"
  pkg_version="$(node -pe "require('$pkg_json').version" 2>/dev/null)"
  pkg_repo="$(node -pe "var r=require('$pkg_json').repository; typeof r==='string'?r:r&&r.url||''" 2>/dev/null | sed 's|git+||')"

  echo "Found nan addon: $pkg_name@$pkg_version"

  [ "$detect_only" = "1" ] && return 0

  (
    cd "$pkg_dir" || exit 1
    npm install --ignore-scripts 2>/dev/null || true

    # Check if source files are present
    if find . -maxdepth 4 \( -name "*.cc" -o -name "*.cpp" \) -print -quit 2>/dev/null | grep -q .; then
      echo "  Source present, rebuilding $pkg_name..."
      if npm run rebuild; then
        echo "  OK: $pkg_name"
      else
        echo "  FAILED: rebuild failed for $pkg_name"
        exit 1
      fi
    else
      echo "  Source missing for $pkg_name, fetching from $pkg_repo..."
      if [ -z "$pkg_repo" ] || [ "$pkg_repo" = "undefined" ] || [ "$pkg_repo" = "null" ]; then
        echo "  FAILED: no repository URL for $pkg_name"
        exit 1
      fi

      tmp_dir="$(mktemp -d)"
      cloned=0
      for tag in "v${pkg_version}" "${pkg_version}"; do
        if git clone -q --depth=1 --branch="$tag" "$pkg_repo" "$tmp_dir" 2>/dev/null; then
          cloned=1
          break
        fi
      done

      if [ "$cloned" = "1" ]; then
        [ -f "$tmp_dir/binding.gyp" ] && mv "$tmp_dir/binding.gyp" .
        [ -d "$tmp_dir/bindings" ]    && mv "$tmp_dir/bindings" .
        rm -rf "$tmp_dir"
        if npm run rebuild; then
          echo "  OK: $pkg_name"
        else
          echo "  FAILED: rebuild failed for $pkg_name"
          exit 1
        fi
      else
        rm -rf "$tmp_dir"
        echo "  FAILED: could not clone $pkg_repo at v$pkg_version or $pkg_version"
        exit 1
      fi
    fi
  ) || { echo "1" > "$fail_marker"; }
}

echo "Scanning for nan-dependent native addons in $node_modules..."

# Pass 1: packages with binding.gyp that include nan.h
find "$node_modules" -maxdepth 3 -name "binding.gyp" | while IFS= read -r binding; do
  pkg_dir="$(dirname "$binding")"

  # Skip nested node_modules
  rel="${pkg_dir#$node_modules/}"
  case "$rel" in
    */node_modules/*) continue ;;
  esac

  uses_nan "$pkg_dir" || continue

  rebuild_pkg "$pkg_dir"
done

# Pass 2: packages using node-gyp-build with ABI-versioned prebuilts (e.g. @datadog/pprof)
# These have no binding.gyp in the installed package but ship prebuilds/*/node-<abi>.node
find "$node_modules" -maxdepth 3 -type d -name "prebuilds" | while IFS= read -r prebuilds_dir; do
  pkg_dir="$(dirname "$prebuilds_dir")"

  # Skip nested node_modules
  rel="${pkg_dir#$node_modules/}"
  case "$rel" in
    */node_modules/*) continue ;;
  esac

  uses_prebuilt_nan "$pkg_dir" || continue

  rebuild_pkg "$pkg_dir"
done

if [ -f "$fail_marker" ]; then
  rm -f "$fail_marker"
  echo "ERROR: one or more native addon rebuilds failed"
  exit 1
fi
