//
//  UmamiAnalytics.swift
//  App
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import UIKit
import OBAKitCore

/// A JSON-safe value for a Umami custom-event `data` dictionary.
///
/// The `Analytics` protocol passes `value: Any?`, so values are coerced through
/// `init?` into a closed set of encodable cases. Anything that can't be
/// represented (e.g. a non-finite `Double`) is dropped by returning `nil`, which
/// keeps body construction crash-free (we never hand raw `Any` to JSON encoding).
enum UmamiJSONValue: Encodable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    init?(_ value: Any?) {
        guard let value else { return nil }
        switch value {
        case let v as Bool: self = .bool(v)
        case let v as Int: self = .int(v)
        case let v as Double:
            guard v.isFinite else { return nil }
            self = .double(v)
        case let v as Float:
            guard v.isFinite else { return nil }
            self = .double(Double(v))
        case let v as String: self = .string(v)
        case let v as CustomStringConvertible: self = .string(v.description)
        default: return nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        }
    }
}

/// Fire-and-forget Umami event emitter. POSTs to `<serverURL>/api/send`.
///
/// Never throws, never blocks the UI, swallows all errors. Constructed per-region
/// by `AnalyticsOrchestrator`; one instance is bound to a single Umami website.
final class UmamiAnalytics {
    private let serverURL: URL
    private let websiteID: String
    private let hostname: String
    private let dataLoader: URLDataLoader
    private let userAgent: String

    /// Default properties merged into every event's `data`. Set via `setUserProperty`.
    private var defaultData: [String: UmamiJSONValue] = [:]
    private let defaultDataLock = NSLock()

    // @MainActor: reads UIDevice.current for the user agent; constructed only by
    // AnalyticsOrchestrator, which is main-actor-isolated.
    @MainActor init(serverURL: URL,
         websiteID: String,
         hostname: String,
         dataLoader: URLDataLoader = UmamiAnalytics.makeDefaultSession()) {
        self.serverURL = serverURL
        self.websiteID = websiteID
        self.hostname = hostname
        self.dataLoader = dataLoader

#if targetEnvironment(simulator)
        // OneBusAway/26.1.2 (iOS 18.5; iPhone Simulator arm64)
        self.userAgent = "OneBusAway/\(Bundle.main.appVersion) (iOS \(UIDevice.current.systemVersion); iPhone Simulator \(UIDevice.current.modelName))"
#else
        self.userAgent = "OneBusAway/\(Bundle.main.appVersion) (iOS \(UIDevice.current.systemVersion); \(UIDevice.current.modelName))"
#endif
    }

    /// A session with a tight end-to-end resource timeout. `URLSession.shared`
    /// cannot be configured, so we build our own.
    static func makeDefaultSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10   // idle/stall timer
        config.timeoutIntervalForResource = 10  // wall-clock end-to-end cap
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }

    // MARK: - Event API (mirrors the Analytics protocol)

    func reportEvent(pageURL: String, label: String, value: Any?) async {
        var data = defaultDataLock.withLock { defaultData }
        if let jsonValue = UmamiJSONValue(value) {
            data["value"] = jsonValue
        }
        await postEvent(path: Self.path(from: pageURL), name: label, data: data)
    }

    func reportSearchQuery(_ query: String) async {
        await reportEvent(pageURL: "app://localhost/search", label: "query", value: query)
    }

    func reportStopViewed(name: String, id: String, stopDistance: String) async {
        var data = defaultDataLock.withLock { defaultData }
        data["id"] = .string(id)
        data["distance"] = .string(stopDistance)
        // No `name` → recorded as a pageview at /stop.
        await postEvent(path: "/stop", name: nil, data: data)
    }

    func setUserProperty(key: String, value: String?) {
        defaultDataLock.withLock {
            if let value {
                defaultData[key] = .string(value)
            } else {
                defaultData.removeValue(forKey: key)
            }
        }
    }

    // MARK: - Wire format

    private struct Payload: Encodable {
        let type = "event"
        let payload: Body

        struct Body: Encodable {
            let website: String
            let hostname: String
            let url: String
            let name: String?                       // omitted when nil → pageview
            let data: [String: UmamiJSONValue]?     // omitted when nil/empty
        }
    }

    private func postEvent(path: String, name: String?, data: [String: UmamiJSONValue]) async {
        let payload = Payload(payload: .init(
            website: websiteID,
            hostname: hostname,
            url: path,
            name: name,
            data: data.isEmpty ? nil : data
        ))

        // JSONEncoder throws a *catchable* Swift error; never an NSException.
        guard let httpBody = try? JSONEncoder().encode(payload) else { return }

        var request = URLRequest(url: serverURL.appendingPathComponent("api/send"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = httpBody

        do {
            let (responseData, _) = try await dataLoader.data(for: request)
            if !Self.isSuccessfulIngest(responseData) {
                #if DEBUG
                let body = String(data: responseData, encoding: .utf8) ?? "<non-utf8>"
                print("[UmamiAnalytics] event dropped (bot UA / bad config?). Body: \(body)")
                #endif
            }
        } catch {
            #if DEBUG
            print("[UmamiAnalytics] emit failed: \(error)")
            #endif
        }
    }

    // MARK: - Helpers

    /// Reduces an internal page URL (e.g. `app://localhost/map`) to the Umami `url`
    /// path (`/map`). Empty/path-less URLs become `/`; query strings are dropped.
    static func path(from pageURL: String) -> String {
        guard let components = URLComponents(string: pageURL), !components.path.isEmpty else {
            return "/"
        }
        return components.path
    }

    /// A successful Umami ingest returns a body with `cache`/`sessionId`/`visitId`.
    /// A dropped event returns `{"beep":"boop"}`. Treats anything else as failure.
    static func isSuccessfulIngest(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        if object["beep"] != nil { return false }
        return object["cache"] != nil || object["sessionId"] != nil || object["visitId"] != nil
    }
}
