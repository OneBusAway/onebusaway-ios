# ``OBAKit``

UI framework for the OneBusAway iOS app, providing view controllers and user interface components for transit information.

## Overview

OBAKit is a higher-level framework that contains the OneBusAway application UI. It depends on ``OBAKitCore`` for networking and data modeling. Transit agencies can use OBAKit to embed OneBusAway screens — such as stops, trip information, and bookmarks — into their own apps.

## Topics

### Essentials

- <doc:WhiteLabel>
- <doc:ContextMenus>

### Orchestration

- ``Application``
- ``AppConfig``

### Classic UI

- ``ClassicApplicationRootController``
- ``MapViewController``
- ``MoreViewController``
- ``RecentStopsViewController``
- ``StopViewController``

### Bookmarks

- ``BookmarksViewController``

### Search

- ``SearchResultsController``

### Deep Linking

- ``AppInterop``
- ``AppLinksRouter``
- ``URLSchemeRouter``
- ``ViewRouter``

### Miscellaneous UI

- ``CollectionController``
- ``DepartureTimeBadge``
- ``EmptyDataSetView``
- ``Formatters``
- ``ImageBadgeRenderer``
- ``ThemeColors``
- ``ThemeMetrics``
- ``VisualEffectViewController``
