# Adds support for Apple Silicon brew directory
export PATH="$PATH:/opt/homebrew/bin"

# CI runs SwiftLint as its own workflow step (errors fail the job; warnings
# annotate). Skipping the build-phase copy here keeps Xcode from double-linting
# and is why `scripts/swiftlint.sh` historically no-op'd when `$CI` was set —
# that skip is also why a type_body_length error on main was invisible in
# review. See .github/workflows/tests.yml and
# https://github.com/OneBusAway/onebusaway-ios/issues/1303
if [ "$CI" = true ]; then
  echo "skipping build-phase swiftlint; CI runs it as a dedicated step"
elif which swiftlint >/dev/null; then
  swiftlint
else
  echo "warning: SwiftLint not installed, download from https://github.com/realm/SwiftLint"
fi
