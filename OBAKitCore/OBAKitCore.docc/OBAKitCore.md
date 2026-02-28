# ``OBAKitCore``

Core business logic framework for the OneBusAway iOS app, providing networking, data models, and services.

## Overview

OBAKitCore is a lower-level framework whose primary function is to provide networking and data modeling services. It is application extension safe and serves as the foundation for ``OBAKit``.

Use OBAKitCore when you want to:
- Access OneBusAway data from a service or extension.
- Build a new OneBusAway UI for another platform.
- Build a custom user interface for displaying OneBusAway data.

## Topics

### Orchestration

- ``CoreApplication``
- ``CoreAppConfig``

### REST API

- ``RESTAPIService``
- ``ArrivalDeparture``
- ``Route``
- ``Stop``
- ``StopArrivals``
- ``StopsForRoute``
- ``Trip``
- ``TripDetails``
- ``TripStatus``
- ``VehicleStatus``
- ``References``

### Regions

- ``Region``
- ``RegionsAPIService``
- ``RegionsService``

### Location

- ``LocationService``

### User Data

- ``UserDataStore``
- ``UserDefaultsStore``
- ``Bookmark``
- ``BookmarkGroup``

### Networking

- ``APIService``
- ``NetworkOperation``

### Analytics

- ``Analytics``
- ``AnalyticsEvent``

### Push Notifications

- ``PushService``
