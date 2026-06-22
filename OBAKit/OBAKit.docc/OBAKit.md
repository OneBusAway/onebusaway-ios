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
- ``ViewRouter``

### Miscellaneous UI

- ``OBAListView``
- ``VisualEffectViewController``
