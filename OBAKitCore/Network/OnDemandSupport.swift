//
//  OnDemandSupport.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Synchronization

/// Remembers which servers have proven they lack the `/api/ondemand`
/// namespace, so the on-demand map layer can hide itself instead of probing on
/// every pan.
///
/// Keyed by the resolved REST base URL rather than by region, so custom
/// regions work and a region switch consults the right entry. Only the
/// `services-for-location` call records here (it is the cheap probe every map
/// pan already makes); a 404 from `service/{id}` or `services-for-agency` is an
/// ordinary not-found and must never mark a server. Absence lasts for the
/// process lifetime: nothing clears an entry, because a server does not grow
/// the namespace between launches.
///
/// `Mutex` (as in `DecodingErrorReporter`) keeps the class `Sendable` with
/// compiler-checked exclusivity; the readers are nonisolated and synchronous so
/// `@MainActor` layers can consult it without an await.
public final class OnDemandSupport: Sendable {

    public static let shared = OnDemandSupport()

    private let absentBaseURLs = Mutex<Set<String>>([])

    public init() {}

    public func isKnownUnsupported(baseURL: URL) -> Bool {
        let key = Self.key(for: baseURL)
        return absentBaseURLs.withLock { $0.contains(key) }
    }

    public func recordAbsent(baseURL: URL) {
        let key = Self.key(for: baseURL)
        absentBaseURLs.withLock { _ = $0.insert(key) }
    }

    /// `https://host/api/` and `https://host/api` are the same server.
    private static func key(for baseURL: URL) -> String {
        var key = baseURL.absoluteString
        while key.hasSuffix("/") {
            key.removeLast()
        }
        return key
    }
}
