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
xcodebuild clean build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'

# Run unit tests
xcodebuild test-without-building -only-testing:OBAKitTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'

# Run specific test class
xcodebuild test-without-building -only-testing:OBAKitTests/SpecificTestClass -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```

### Code Quality
```bash
scripts/swiftlint.sh                    # Run SwiftLint (skips in CI)
swiftlint                              # Run SwiftLint directly
```

### Documentation
```bash
bundle install                         # Install Ruby dependencies
brew install sourcekitten             # Install documentation tool
scripts/docs                          # Generate Jazzy documentation
```

### Other Utilities
```bash
scripts/version                        # Version management
scripts/update_package_resolved        # Update Swift Package Manager dependencies
scripts/extract_strings               # Extract strings for localization
scripts/tx_pull                       # Pull translations from Transifex
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

- **Target iOS Version**: 17.0+
- **Swift Version**: 5.3+
- **Package Manager**: Swift Package Manager
- **Project Generation**: XcodeGen from YAML configurations
- **Localization**: Transifex integration
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
onebusaway://add-region?name=REGION_NAME&oba-url=ENCODED_SERVER_URL
```

## Development Notes

- Always run `scripts/generate_project` before building
- SwiftLint has relaxed rules - check `.swiftlint.yml` for disabled rules
- Core framework (OBAKitCore) must remain application extension safe
- UI tests are minimal - focus is on unit tests
- Documentation is generated with Jazzy and requires Sourcekitten