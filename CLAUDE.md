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

### Building & Testing
```bash
# Build for testing
xcodebuild clean build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Run unit tests
xcodebuild test-without-building -only-testing:OBAKitTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Run specific test class
xcodebuild test-without-building -only-testing:OBAKitTests/SpecificTestClass -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
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
- `Apps/MTA/`: MTA-specific variant
- `Apps/KiedyBus/`: Polish transit app variant
- `Apps/Shared/`: Common configuration and analytics

### Testing
- `OBAKitTests/`: Unit tests for all frameworks

## Third-Party Dependencies

**UI Libraries**: BulletinBoard, Eureka, FloatingPanel, MarqueeLabel
**Networking**: CocoaLumberjack, Hyperconnectivity, SwiftProtobuf
**Testing**: Nimble

## Configuration & Deployment

- **Target iOS Version**: 18.0+
- **Swift Version**: Swift 5/6 language modes, current Xcode toolchain (modern syntax like shorthand optional binding and `URL.host()` is fine — the iOS 18 deployment target exceeds their requirements)
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