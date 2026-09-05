# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

OneBusAway iOS (OBAKit) is a white-label transit app framework written in Swift. It's designed as reusable frameworks that transit agencies can use to create custom-branded apps without forking the source code.

## Build System & Commands

### Project Generation (Required Before Building)
```bash
scripts/generate_project [APP_NAME]     # Generate Xcode project for specific app
scripts/generate_project OneBusAway     # Generate default OneBusAway app
scripts/generate_project                # Defaults to OneBusAway if no app specified
```

**Available Apps**: OneBusAway, KiedyBus

### Picking a Simulator

Every command below needs a simulator UDID. Resolve one with:

```bash
SIMULATOR_UDID=$(scripts/resolve_simulator_udid)
```

That prints the first iPhone on the newest installed iOS runtime — the same
selection `.github/workflows/tests.yml` makes, from the same implementation, so
the two cannot drift apart.

**Run it in the same shell invocation as the command that uses it.** It sets an
ordinary shell variable, and this file's audience is Claude Code, whose Bash tool
starts a fresh shell per call — the working directory persists, environment does
not. Resolve it in one call and build in the next and `$SIMULATOR_UDID` is empty,
so `-destination "platform=iOS Simulator,id="` is rejected while parsing
arguments, before any device lookup happens:

```
xcodebuild: error: missing value for key 'id' of option 'Destination'
```

That is neither of the errors in the table below, and it is the friendlier of the
three — it names the problem rather than implying the device is missing. Each
block that follows repeats the resolve line so this cannot arise; keep it when
copying one.

Address the device by `id=` rather than `name=`. A hardcoded name breaks two ways,
and they report differently — which is why neither `OS=latest` nor a fresh device
name fixes both:

| | Error |
|---|---|
| not installed | "Unable to find a device matching the provided destination specifier" |
| ambiguous across runtimes | "The requested device could not be found because multiple devices matched the request" |

The first is verified on the current toolchain. The second is the historical
wording and has shifted between Xcode releases — treat the text as indicative and
the cause as the reliable part. `id=` avoids both.

A name also goes stale on every Xcode release: this file has already carried
`iPhone 16` and `iPhone 17 Pro`.

### Building, Testing, and Driving the App: use `xcodebuildmcp`

**Reach for `xcodebuildmcp` first.** It wraps `xcodebuild`/`xcrun simctl` and — critically —
is the only thing in this repo that reliably drives the simulator's UI. Discover commands
from the CLI itself rather than from memory:

```bash
xcodebuildmcp --help                 # workflows
xcodebuildmcp <workflow> --help      # commands in a workflow
xcodebuildmcp ui-automation --help   # snapshot-ui, tap, swipe, type-text, screenshot, ...
```

Typical loop for verifying a change in the running app:

```bash
scripts/generate_project OneBusAway                      # required before any build
SIMULATOR_UDID=$(scripts/resolve_simulator_udid)         # same shell invocation as the commands below
xcodebuildmcp simulator build-and-run --project-path OBAKit.xcodeproj --scheme App --simulator-id "$SIMULATOR_UDID"
xcodebuildmcp ui-automation snapshot-ui  --simulator-id "$SIMULATOR_UDID" --style minimal
xcodebuildmcp ui-automation touch        --simulator-id "$SIMULATOR_UDID" --element-ref e26 --down --up --delay 0.08
xcodebuildmcp ui-automation screenshot   --simulator-id "$SIMULATOR_UDID" --return-format path --style minimal
```

`snapshot-ui` returns semantic `elementRef` handles; drive those refs instead of
coordinates, and re-snapshot after any navigation or layout change.

Two things that cost real time here:

- **Flag spelling differs between the CLI and the MCP tools.** The CLI documents
  kebab-case (`--simulator-id`, `--element-ref`, `--project-path`,
  `--return-format`); the MCP tool schema uses camelCase (`simulatorId`,
  `elementRef`). The CLI tolerates camelCase on some commands and rejects it on
  others (`simulator open` errors with "Unknown arguments"), so always use
  kebab-case — `<workflow> <command> --help` prints the canonical names.
- **Prefer `touch --down --up` over `tap`.** `tap` reports
  "simulated successfully" and frequently changes nothing — notably on SwiftUI
  onboarding buttons. `touch` reaches the same refs and actually lands. If a screen
  will not advance, swap `tap` for `touch` before suspecting anything else.

Map annotations are not exposed as snapshot targets, so map pins still cannot be
driven this way — verify those with hosted unit tests instead.

**If `xcodebuildmcp` is not installed, install it — do not hand-roll simulator automation.**

```bash
brew tap getsentry/xcodebuildmcp && brew install xcodebuildmcp
# or, with Node.js 18+: npm install -g xcodebuildmcp@latest
```

Homebrew is the path with no Node dependency. XcodeBuildMCP itself requires
macOS 14.5+ and Xcode 16+.

Every homegrown alternative on this codebase has been a dead end or a time sink: `idb` is
broken on current Xcode, AppleScript/System Events hit an empty accessibility tree, and
synthesizing `CGEvent` clicks against the Simulator window means recalibrating a window→device
coordinate mapping that silently drifts whenever the window moves or another simulator window
overlaps it. Those taps fail *silently* — they report success and change nothing — which is
the single most expensive failure mode here. Install the CLI instead.

### Building & Testing (raw xcodebuild)

Use these only when `xcodebuildmcp` genuinely cannot do the job.

```bash
SIMULATOR_UDID=$(scripts/resolve_simulator_udid)         # same shell invocation as the commands below

# Build for testing
xcodebuild clean build-for-testing -scheme 'App' -destination "platform=iOS Simulator,id=$SIMULATOR_UDID"

# Run unit tests
xcodebuild test-without-building -only-testing:OBAKitTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination "platform=iOS Simulator,id=$SIMULATOR_UDID"

# Run specific test class
xcodebuild test-without-building -only-testing:OBAKitTests/SpecificTestClass -project 'OBAKit.xcodeproj' -scheme 'App' -destination "platform=iOS Simulator,id=$SIMULATOR_UDID"
```

### Code Quality
```bash
scripts/swiftlint.sh                    # Run SwiftLint (skips in CI)
swiftlint                              # Run SwiftLint directly
```

### Documentation
```bash
scripts/docs                          # Generate DocC documentation (output in api-docs/)
```

### Other Utilities
```bash
scripts/version                        # Version management
scripts/update_package_resolved        # Update Swift Package Manager dependencies
scripts/extract_strings               # Extract strings for localization
```

## Architecture

### Framework Structure
- **OBAKitCore**: Core business logic, networking, data models (application extension safe)
- **OBAKit**: UI framework with view controllers and user interface components
- **App**: Main application target that combines the frameworks

### Key Architectural Patterns
- **Dependency Injection**: Central `Application` class manages all services
- **Coordinator Pattern**: `ViewRouter` handles navigation
- **Repository Pattern**: Service classes handle data access
- **MVVM-like Pattern**: View controllers work with view models and services

### Core Components
- **Models**: REST API models, Protobuf models, user data models, view models
- **Services**: RESTAPIService, RegionsService, LocationService, UserDataStore
- **Controllers**: Tab-based navigation with map, stops, bookmarks, search, and more
- **Extensions**: Foundation, CoreLocation, UIKit, and MapKit extensions

## Key Directories

### Frameworks
- `OBAKitCore/`: Core business logic (extension-safe)
  - `Models/`: Data models for API, Protobuf, user data
  - `Network/`: API services and networking
  - `Location/`: Location services and region management
  - `Orchestration/`: Application setup and configuration
- `OBAKit/`: UI framework
  - `Controls/`: Reusable UI components
  - `Mapping/`: Map views and location features
  - `Stops/`: Stop information and arrivals
  - `Bookmarks/`: Bookmark management
  - `Search/`: Search functionality

### Applications
- `Apps/OneBusAway/`: Main OneBusAway branded app
- `Apps/KiedyBus/`: Polish transit app variant
- `Apps/Shared/`: Common configuration and analytics

### Testing
- `OBAKitTests/`: Unit tests for all frameworks. Written with **Swift Testing**
  (`@Suite` / `@Test` / `#expect`), not XCTest. The single exception is
  `PolylinePerformanceTests`, which stays on XCTest because `measure` has no
  Swift Testing equivalent — and is marked `nonisolated`, without which the
  target cannot build in the Swift 6 language mode.
- Suites are marked `.serialized`, which serializes the tests *within* each
  suite — that is the ordering XCTest gave them, and what the suites were
  written against. It does **not** stop separate suites running concurrently,
  so anything process-global (`NSTimeZone.default`, `UserDefaults.standard`,
  singletons) still needs handling on its own terms; see the GMT pin in
  `OBAKitTests/Helpers/OBATestCase.swift` for the pattern. Whole-target
  serialization, where it holds, comes from `parallelizable: false` on the test
  target in `Apps/Shared/app_shared.yml`.
- `OBATestCase` is a plain `@MainActor` base class, not an `XCTestCase`. Suites
  that need its fixtures inherit it and override `init() async throws` (where
  `setUp` used to go); teardown goes in `deinit`.

## Third-Party Dependencies

**UI Libraries**: BulletinBoard, Eureka, FloatingPanel, MarqueeLabel
**Networking**: CocoaLumberjack, Hyperconnectivity, SwiftProtobuf
**Testing**: Swift Testing (first-party; Nimble was removed)

## Configuration & Deployment

- **Target iOS Version**: 18.0+
- **Swift Version**: every target builds in the **Swift 6 language mode** with main-actor default isolation (`Apps/Shared/app_shared.yml`); OBAKitCore is the one target that pins `SWIFT_DEFAULT_ACTOR_ISOLATION` back to `nonisolated`. The five concurrency diagnostic groups are escalated to errors, so a data-race warning fails the build. Modern syntax (shorthand optional binding, `URL.host()`) is fine — the iOS 18 deployment target exceeds their requirements.
- **Package Manager**: Swift Package Manager
- **Project Generation**: XcodeGen from YAML configurations
- **Localization**: in-repo .strings files (OBAKit/Strings, OBAKitCore/Strings)
- **Linting**: SwiftLint with relaxed rules for flexibility

## White-Label Features

The codebase supports easy customization through:
- Separate app configurations in `Apps/` directory
- Pluggable analytics systems (Firebase, Plausible)
- Custom region support via deep links
- Theming and branding capabilities

## Deep Linking

Custom region addition:
```
onebusaway://add-region?name=REGION_NAME
    &oba-url=ENCODED_OBA_URL
    &otp-url=ENCODED_OTP_URL
    &sidecar-url=ENCODED_SIDECAR_URL
    &umami-url=ENCODED_UMAMI_URL
    &umami-id=UMAMI_WEBSITE_ID
```

**Parameter details:**
- `name` (required): Region display name
- `oba-url` (required): OneBusAway server base URL
- `otp-url` (optional): OpenTripPlanner server URL
- `sidecar-url` (optional): Obaco sidecar server URL for OneBusAway.co features
- `umami-url` and `umami-id` (optional, both required together): Umami analytics URL and website ID—omit both to disable analytics

**Rules:**
1. All optional parameters can be omitted; their absence preserves existing behavior
2. **Umami is "both-or-nothing"**: analytics are enabled only if both `umami-url` and `umami-id` are present and valid; a partial pair is silently ignored
3. URL parameters must be percent-encoded (e.g., query strings in nested URLs: `https://example.com/api?a=1&b=2` must be encoded as `https%3A%2F%2Fexample.com%2Fapi%3Fa%3D1%26b%3D2`)
4. New URL fields are validated for well-formedness only; invalid optional URLs degrade to nil. The Add Custom Region form live-validates the base URL on save; the deep link path checks well-formedness only

## Development Notes

- Always run `scripts/generate_project` before building
- SwiftLint has relaxed rules - check `.swiftlint.yml` for disabled rules
- Core framework (OBAKitCore) must remain application extension safe
- UI tests are minimal - focus is on unit tests
- Documentation is generated with DocC via `scripts/docs`