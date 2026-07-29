#!/usr/bin/env bash
#
# Shared cold-build harness. Source this; don't run it.
#
#   source "$(dirname "$0")/_cold_build.sh"
#   cold_build_init                     # sets REPO_ROOT, SIMULATOR, WORKDIR + cleanup
#   cold_build "$LOG" -quiet            # any extra args go to xcodebuild
#
# Why a shared file rather than a copy in each script: getting a build to be
# genuinely cold takes two isolations, and missing either one silently produces
# numbers that look fine and are wrong.
#
#   1. -derivedDataPath, the obvious one.
#   2. COMPILATION_CACHE_CAS_PATH, the one that bites. It defaults to a
#      MACHINE-GLOBAL location (~/Library/Developer/Xcode/DerivedData/
#      CompilationCache.noindex) that lives OUTSIDE whatever derived data path
#      you pass, so a fresh -derivedDataPath alone still replays cached object
#      code -- without re-emitting its diagnostics or spending its compile time.
#
# Measured 2026-07-28 on one unchanged tree: the true warning count was 38,
# while warm -derivedDataPath builds reported 4, 12, 16, and 17 depending on
# cache state.

# Sets REPO_ROOT, SIMULATOR and WORKDIR, and arranges for WORKDIR to be removed
# on exit. Call once, before cold_build.
cold_build_init() {
  REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[1]}")/.." && pwd)"
  SIMULATOR="${SIMULATOR:-iPhone 17 Pro}"
  WORKDIR="$(mktemp -d)"

  # The caller must not `exec` xcodebuild: exec replaces the shell, this trap
  # never fires, and each run leaks a full DerivedData + CAS (~3.5 GB).
  trap 'rm -rf "$WORKDIR"' EXIT

  cd "$REPO_ROOT" || exit 1
}

# cold_build <log-path> [extra xcodebuild args...]
#
# Returns xcodebuild's exit status rather than dying, so callers can report
# failures their own way. Under `set -e`, guard the call site accordingly.
cold_build() {
  local log="$1"
  shift

  xcodebuild build-for-testing \
    -scheme 'App' \
    -destination "platform=iOS Simulator,name=${SIMULATOR}" \
    -derivedDataPath "$WORKDIR/DerivedData" \
    COMPILATION_CACHE_CAS_PATH="$WORKDIR/CompilationCache" \
    "$@" \
    > "$log" 2>&1
}
