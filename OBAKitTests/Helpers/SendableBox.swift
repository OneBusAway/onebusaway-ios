//
//  SendableBox.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// A lock-guarded box for a value a test needs to capture out of concurrently
/// executing code — a `MockDataLoader` matcher, a `@Sendable` completion
/// handler, anything the runtime may call off the main actor.
///
/// The test target defaults to main-actor isolation, so the obvious `var
/// captured: T?` in a test body is main-actor state; mutating it from a matcher
/// is a data race, and one the compiler now rejects because
/// `MockDataLoaderMatcher` is `@Sendable`.
///
/// `@unchecked Sendable` is honest here because the lock, not isolation, is what
/// serialises access — and `nonisolated` keeps the box out of the target's
/// main-actor default so it can be touched from wherever the callback lands.
nonisolated final class SendableBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: T

    var value: T {
        get { lock.withLock { storage } }
        set { lock.withLock { storage = newValue } }
    }

    init(_ value: T) {
        storage = value
    }
}
