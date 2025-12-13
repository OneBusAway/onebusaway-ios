# Code Review: PR #918 - Add Core Survey Functionality

## Overview

This PR establishes foundational survey infrastructure for the OneBusAway iOS app. It adds components for survey visibility management, prioritization, and user state persistence.

| | |
|---|---|
| **Author** | mosliem |
| **Files Changed** | 18 |
| **Lines** | +1,638 / -1 |
| **Related Issues** | #819, #829, #830 |

---

## Critical Issues

### 1. Incorrect UUID Retrieval in `CoreApplication.swift:251`

```swift
let surveyUUID = userDefaultsStore.surveyPreferences().userSurveyId
```

This reads from `surveyPreferences()` which returns a `SurveyPreferences` struct with potentially empty `userSurveyId`. The `userSurveyId` computed property on `UserDefaultsStore` (line 790) properly generates and persists a UUID if none exists, but this code bypasses that logic.

**Should be:**
```swift
let surveyUUID = userDefaultsStore.userSurveyId
```

### 2. Thread Safety in `SurveyService.swift`

The `@Published var error` and `surveys` array are mutated from async contexts without main actor isolation:

```swift
public final class SurveyService: SurveyServiceProtocol, ObservableObject {
    @Published public var error: Error?
    public private(set) var surveys: [Survey] = []

    public func fetchSurveys() async {
        // ...
        self.surveys = studyResponse.surveys  // Called from async context
        self.error = error  // Potentially off main thread
    }
}
```

**Recommendation:** Add `@MainActor` to the class or use `await MainActor.run { }` for property updates.

---

## Moderate Issues

### 3. Error State Not Cleared Before Operations

In `SurveyService.swift`, errors are stored but never cleared before starting new operations:

```swift
public func fetchSurveys() async {
    // error is never cleared here
    do {
        let studyResponse = try await apiService.getSurveys()
        self.surveys = studyResponse.surveys
    } catch {
        self.error = error  // Previous errors persist
    }
}
```

**Recommendation:** Clear error at the start of operations:
```swift
public func fetchSurveys() async {
    self.error = nil  // Clear previous error
    // ...
}
```

### 4. Access Level Inconsistency - `SurveyStateManager`

`SurveyStateProtocol` is `public`, but `SurveyStateManager` is `internal`:

```swift
public protocol SurveyStateProtocol { ... }

final class SurveyStateManager: SurveyStateProtocol {  // Missing 'public'
```

This restricts external instantiation. If intentional for encapsulation, consider adding a documentation comment explaining this design decision.

### 5. `SurveyService` Initializer is Internal

The class is `public final` but the initializer is `internal`:

```swift
public final class SurveyService: SurveyServiceProtocol, ObservableObject {
    init(apiService: SurveyAPIService?, surveyStore: SurveyPreferencesStore) {
```

This means external consumers cannot instantiate `SurveyService` directly. If intentional, add `public` to the init for testing purposes, or document why it's internal-only.

---

## Minor Issues / Suggestions

### 6. Trailing Comma in Initializer (`SurveyPreferences.swift:32`)

```swift
public init(
    // ...
    nextReminderDate: Date? = nil,  // <-- trailing comma
) {
```

While valid Swift, this is unusual style. Consider removing for consistency.

### 7. Magic Number for Launch Count Modulo

In `SurveyStateManager.swift:27`:
```swift
guard preferences.isSurveyEnabled && surveyStore.appLaunch > 0 && surveyStore.appLaunch % 3 == 0 else {
```

The `3` is a magic number. Consider extracting to a constant:
```swift
private static let surveyLaunchInterval = 3

guard ... && surveyStore.appLaunch % Self.surveyLaunchInterval == 0 else {
```

### 8. Redundant `return` in `isSurveyVisible`

In `SurveyPrioritizer.swift:111`:
```swift
routeListExistence = routesList.contains { routeId in
    return stop.routes.contains(where: { $0.id == routeId })
}
```

The `return` is unnecessary in single-expression closures.

### 9. Documentation Typo

In `SurveyService.swift:66`:
```swift
/// Upon successful submission, the server response is saved in `UserDeaults`.
```

Should be `UserDefaults`.

---

## What's Done Well

1. **Excellent test coverage** - Comprehensive tests for `SurveyPrioritizer` (~35 test cases) and `SurveyStateManager` covering edge cases

2. **Clean protocol-based architecture** - Good use of protocols (`SurveyPrioritizing`, `SurveyStateProtocol`, `SurveyPreferencesStore`) enabling dependency injection and testability

3. **Well-documented code** - Clear documentation comments explaining the purpose and behavior of methods

4. **Proper use of `Set<Int>`** for completed/skipped survey IDs instead of arrays - better performance for lookups

5. **Calendar-aware date calculations** in `setNextReminderDate()` with fallback

6. **Mock implementation** (`SurveyPreferencesStoreMock`) provided for testing

7. **Priority-based survey selection** with clear classification enum and `Comparable` conformance

---

## Summary

| Category | Count |
|----------|-------|
| Critical | 2 |
| Moderate | 3 |
| Minor | 4 |

The overall architecture is solid and follows good Swift practices. The critical issues around UUID retrieval and thread safety should be addressed before merging. The test coverage is excellent, which will make fixing these issues safer.
