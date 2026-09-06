# SwiftLint CI gate (#1340)

Follow-ups from #1325 / #1303:

1. **`longPressGesture` is `private`** again — only used in `MapViewController.swift`.
2. **Lint is its own job** (`lint:` beside `build:`), so a lint failure does not
   erase test signal for the same run.
3. **SwiftLint is version-pinned** in `.github/workflows/tests.yml`
   (`SWIFTLINT_PIN`, official portable release). Bump the pin after reviewing
   new error-tier rules — do not rely on unpinned `brew install`.
4. Extension doc comments no longer claim a `type_body_length` ceiling that the
   split already removed.
