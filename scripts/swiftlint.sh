if [ "$CI" = true ]; then
  echo "skipping swiftlint because in CI environment"
elif which swiftlint >/dev/null; then
  swiftlint
else
  echo "warning: SwiftLint not installed, download from https://github.com/realm/SwiftLint"
fi
