# Module Boundaries & Architectural Invariants

This document defines the architectural boundaries between frameworks and application targets in the OneBusAway iOS codebase, explains why these invariants exist, and documents the automated checker (`scripts/check_module_boundaries`) used to enforce them in CI and local development.

---

## Architecture Overview

OneBusAway iOS is built as a set of modular, white-label Swift package targets and Xcode targets designed to support multiple client applications (OneBusAway, KiedyBus) across multiple Apple platforms (iOS, watchOS, Widget extensions):

```
┌────────────────────────────────────────────────────────┐
│              App Shells (OneBusAway, KiedyBus)         │
├──────────────────────────┬─────────────────────────────┤
│   iOS Application        │       watchOS WatchApp      │
├──────────────────────────┼─────────────────────────────┤
│   OBAKit (iOS UIKit UI)  │   OBAKitWatch (watchOS UI)  │
├──────────────────────────┴─────────────────────────────┤
│             OBAKitCore (Swift Package Target)          │
│  ┌────────────────────────┬─────────────────────────┐  │
│  │ OBAKitCore/ (Portable) │ OBAKitCore/iOS/ (iOS)   │  │
│  └────────────────────────┴─────────────────────────┘  │
└────────────────────────────────────────────────────────┘
```

---

## Module Roles & Invariant Rules

### 1. `OBAKitCore/` (Portable Core)

- **Platforms:** iOS 18.0+, watchOS 11.0+.
- **Role:** Core transit business logic, REST & Protobuf networking, persistence (GRDB / SQLite), data models, and pure calculations.
- **Invariants:**
  - **No UIKit View Code:** Portable core must never reference `UIView`, `UIViewController`, `UIWindow`, `UIButton`, `UILabel`, `UIImageView`, `UITableView`, `UICollectionView`, `UIStackView`, or other UIKit view hierarchy classes.
  - **Restricted `import UIKit`:** Only 5 approved foundation/theme files may import `UIKit`, exclusively for `UIColor` and `NSDirectionalEdgeInsets` (which are supported across iOS and watchOS):
    1. `OBAKitCore/Extensions/UIColor+Hex.swift`
    2. `OBAKitCore/Extensions/UIColor+WCAG.swift`
    3. `OBAKitCore/Models/REST/References/Route.swift`
    4. `OBAKitCore/Theme/Theme.swift`
    5. `OBAKitCore/Theme/ThemeColors.swift`
    All other portable core files must remain completely free of `import UIKit`.
  - **No `ActivityKit`:** Live Activity APIs are iOS-only. `import ActivityKit` is forbidden in portable core; Live Activity models and registries live in `OBAKitCore/iOS/LiveActivities/`.
  - **No `WidgetKit`:** Portable core must not depend on `WidgetKit`. Widget entry planning remains pure date/model arithmetic (e.g., `WidgetTimelinePlanner`).
  - **Extension Safe (No `UIApplication`):** `OBAKitCore` is linked by iOS widgets and watch complications (`APPLICATION_EXTENSION_API_ONLY = YES`). Calling `UIApplication.shared` or extension-unsafe APIs is prohibited.
  - **No Region Monitoring:** `CLLocationManager` region-monitoring APIs (`startMonitoring(for:)`, `stopMonitoring(for:)`) are iOS-only and belong in `OBAKitCore/iOS/Location/`.
  - **No Platform `#if` Scattering:** The portable tree carries exactly two authorized platform conditionals:
    - `#if canImport(ActivityKit)` in `OBAKitCore/Orchestration/CoreApplication.swift`
    - `#if !os(watchOS)` / `#if os(watchOS)` in `OBAKitCore/Theme/ThemeColors.swift`
    Scattering `#if os(iOS)` across portable files is forbidden; any iOS-specific code must move to `OBAKitCore/iOS/`.

### 2. `OBAKitCore/iOS/` (Approved iOS-Only Core Boundary)

- **Platforms:** iOS only (compiled as part of the same `OBAKitCore` module).
- **Role:** iOS-specific core features: UIKit helper views, Live Activities push tracking and cards, and CoreLocation region monitoring.
- **Invariants:**
  - **Mandatory `#if os(iOS)` Wrapping:** Swift Package Manager compiles every source file in `OBAKitCore` for both platforms. To prevent breaking watchOS compilation, **every single file in `OBAKitCore/iOS/` must be wrapped in `#if os(iOS)` … `#endif // os(iOS)`**.
  - **Extension Safe:** Because `OBAKitCore` is linked into app extensions and widgets, files in `OBAKitCore/iOS/` must also remain extension-safe and must not call `UIApplication.shared`.

### 3. `OBAKitWatch/` (watchOS UI Framework)

- **Platforms:** watchOS only.
- **Role:** SwiftUI screens, views, view models, and the watch host assembly.
- **Invariants:**
  - **SwiftUI Only:** Must not `import UIKit`.
  - **No iOS Frameworks:** Must not `import ActivityKit` or `import OBAKit` (the iOS UIKit UI framework).
  - **No WidgetKit:** Widget complications belong in the dedicated `OBAWatchWidget` target.
  - **No `CoreApplication`:** Watch code must never instantiate `CoreApplication` or read `\.coreApplication`. `OBAKitWatch/Host/WatchAppHost.swift` is the composition root.
  - **Extension Safe:** Must not reference `UIApplication`.

### 4. `OBAKit/` (iOS UI Framework)

- **Platforms:** iOS only.
- **Role:** Primary UIKit-based iOS user interface, map views, view controllers, and coordinators.
- **Invariants:**
  - **No watchOS Target Dependencies:** Must not `import OBAKitWatch` or `import WatchKit`.

---

## Checker Tooling: `scripts/check_module_boundaries`

The repository includes an executable Python checker that enforces these invariants automatically.

### Running the Checker

```bash
# Run boundary check across all targets (OBAKitCore, OBAKitWatch, OBAKit)
scripts/check_module_boundaries

# Run self-test suite (validates current tree + 16 intentional violating fixtures)
scripts/check_module_boundaries --test

# Run with verbose scan reporting
scripts/check_module_boundaries --verbose

# Output diagnostic results in JSON format
scripts/check_module_boundaries --json
```

### Pre-PR Local Check

To verify module boundaries, run tests, and execute SwiftLint in a single command before submitting a pull request:

```bash
scripts/pre_pr_check
```

### CI Integration

The module boundary check is integrated into `.github/workflows/tests.yml`:
1. **`lint` Job (Ubuntu Linux):** Executes `scripts/check_module_boundaries` and `scripts/check_module_boundaries --test` on every pull request and push to `main` without waiting for macOS simulator runners.
2. **`watch` Job (macOS):** Executes `scripts/check_module_boundaries` alongside Swift package and watch stack validation.

---

## Rule Reference Table

| Rule ID | Target Scope | Violation Condition | Remediation Guidance |
|---|---|---|---|
| `CORE_FORBIDDEN_IMPORT_ACTIVITYKIT` | `OBAKitCore/` (portable) | `import ActivityKit` | ActivityKit is iOS-only. Move Live Activity code to `OBAKitCore/iOS/LiveActivities/`. |
| `CORE_FORBIDDEN_IMPORT_WIDGETKIT` | `OBAKitCore/` (portable) | `import WidgetKit` | Keep core free of WidgetKit; keep timeline calculations pure arithmetic. |
| `CORE_UNAUTHORIZED_IMPORT_UIKIT` | `OBAKitCore/` (portable) | `import UIKit` in unapproved files | Move UI code to `OBAKitCore/iOS/` or `OBAKit/`. Allowed only in the 5 foundation/theme files. |
| `CORE_FORBIDDEN_UIKIT_VIEW` | `OBAKitCore/` (portable) | Use of `UIView`, `UIViewController`, `UIButton`, etc. | Move view/view controller code to `OBAKitCore/iOS/UIKit/` or `OBAKit/`. |
| `CORE_FORBIDDEN_UIAPPLICATION` | `OBAKitCore/` (portable) | Use of `UIApplication` | Target is `APPLICATION_EXTENSION_API_ONLY`. Avoid `UIApplication.shared`. |
| `CORE_FORBIDDEN_REGION_MONITORING` | `OBAKitCore/` (portable) | Calling `startMonitoring(for:)` / `stopMonitoring(for:)` | Move geofence monitoring to `OBAKitCore/iOS/Location/`. |
| `CORE_FORBIDDEN_PLATFORM_IF` | `OBAKitCore/` (portable) | Use of `#if os(iOS)` | Do not scatter `#if os(iOS)` in portable core; move the file or extension into `OBAKitCore/iOS/`. |
| `IOS_MISSING_IF_GUARD` | `OBAKitCore/iOS/` | File missing `#if os(iOS)` wrapper | Wrap entire file in `#if os(iOS)` … `#endif // os(iOS)`. |
| `IOS_FORBIDDEN_UIAPPLICATION` | `OBAKitCore/iOS/` | Use of `UIApplication` | OBAKitCore is extension-safe; do not call `UIApplication` APIs. |
| `WATCH_FORBIDDEN_IMPORT_*` | `OBAKitWatch/` | Importing `UIKit`, `ActivityKit`, `WidgetKit`, `OBAKit` | Use SwiftUI and watchOS-safe dependencies only. |
| `WATCH_FORBIDDEN_CORE_APPLICATION` | `OBAKitWatch/` | Instantiating or accessing `CoreApplication` | Use `WatchAppHost` as composition root; never instantiate `CoreApplication`. |
| `WATCH_FORBIDDEN_UIAPPLICATION` | `OBAKitWatch/` | Use of `UIApplication` | Target is watchOS and extension-safe; use `WKApplication` or SwiftUI scenes. |
| `OBAKIT_FORBIDDEN_IMPORT_*` | `OBAKit/` | Importing `OBAKitWatch` or `WatchKit` | OBAKit is iOS-only and must not depend on watchOS targets. |
