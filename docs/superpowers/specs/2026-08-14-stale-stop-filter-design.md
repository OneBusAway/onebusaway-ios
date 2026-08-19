# Stop page stale arrival/departure filter after Settings

**Date:** 2026-08-14
**Status:** Approved for implementation
**Issue:** #1273

## Goal

An already-open stop page keeps showing the arrival/departure filter it seeded in `init`, including a stale checkmark in its own Departure Type menu, after the rider changes the same setting in Settings (modal, More tab). Fresh navigation is already correct.

## Approach

Mirror `MapViewModel`'s `UserDefaults.didChangeNotification` subscription.

On each notification (same `UserDefaults` instance as Settings writes):

1. Read `environment.effectiveArrivalDepartureFilter`.
2. If it differs from the published `arrivalDepartureFilter`, assign the published property.
3. Do **not** call `setArrivalDepartureFilter` from this path — that would write defaults again.
4. Do **not** refetch arrivals. The list already filters in the view from the published value.

Unrelated defaults writes are a no-op via the equality guard, same as `MapViewModel.syncMapTypeFromRegionManager`.

## Protocol

Add `var userDefaults: UserDefaults { get }` to `StopViewModelEnvironment` so the subscription can target the same store Settings uses. `Application` already has this property. The preview stub uses its existing suite defaults.

Do not add a test-only handler or extra publisher.

## Tests

A `StopViewModel` constructed with `.all`, then `application.setArrivalDepartureFilter(.estimatedOnly)` (Settings' write path, not `updateArrivalDepartureFilter`), must publish `.estimatedOnly` after the notification hops to the main actor (`Task.yield` loop, same as `MapViewModelTests`).

That test is green on `main` today only if someone already subscribed — it must fail before the production change.

Do not load `StopPageViewController.view`.
