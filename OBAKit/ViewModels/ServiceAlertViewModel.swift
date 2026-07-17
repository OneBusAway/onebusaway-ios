//
//  ServiceAlertViewModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Combine
import OBAKitCore

/// Shared ViewModel for `ServiceAlertViewController`.
///
/// Owns the rendered HTML document for a single `ServiceAlert` and the
/// mark-as-read side effect. Contains no UIKit/WebKit imports.
@MainActor
final class ServiceAlertViewModel: ObservableObject {

    // MARK: - Published State

    /// The rendered HTML document. `nil` until the first build completes.
    @Published private(set) var renderedHTML: String?

    // MARK: - Private

    private let serviceAlert: ServiceAlert
    private let application: Application
    private let buildQueue = DispatchQueue(
        label: "servicealert_detail_html_builder",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private var hasMarkedRead = false
    private var isBuilding = false

    // MARK: - Init

    init(serviceAlert: ServiceAlert, application: Application) {
        self.serviceAlert = serviceAlert
        self.application = application
    }

    // MARK: - Intent

    /// Call from `viewDidAppear`. Idempotent — only marks the alert read once
    /// per VM and only builds the HTML on the first call.
    func viewDidAppear() {
        if !hasMarkedRead {
            application.userDataStore.markRead(serviceAlert: serviceAlert)
            hasMarkedRead = true
        }
        guard renderedHTML == nil, !isBuilding else { return }
        buildPage()
    }

    // MARK: - Page Content

    private func buildPage() {
        isBuilding = true
        let alert = serviceAlert
        let formatter = application.formatters.shortDateTimeFormatter

        // Formatters is not Sendable (lazy formatter caches), so resolve the
        // formatter-dependent strings here on the main actor instead of sending it.
        let formatters = application.formatters
        let activeWindows: [String] = alert.activeWindows
            .map { $0.interval }
            .sorted()
            .compactMap { formatters.formattedDateRange($0) }

        buildQueue.async { [weak self] in
            let html = Self.buildDocument(
                alert: alert,
                dateTimeFormatter: formatter,
                activeWindows: activeWindows
            )
            DispatchQueue.main.async {
                guard let self else { return }
                self.renderedHTML = html
                self.isBuilding = false
            }
        }
    }

    // swiftlint:disable:next function_body_length
    private nonisolated static func buildDocument(
        alert: ServiceAlert,
        dateTimeFormatter: DateFormatter,
        activeWindows: [String]
    ) -> String {
        var builder = HTMLBuilder()
        builder.append(.h1, value: alert.summary?.value ?? Strings.serviceAlert)
        builder.append(.p, value: dateTimeFormatter.string(from: alert.createdAt))

        if let description = alert.situationDescription {
            description.value.components(separatedBy: "\n").forEach {
                builder.append(.p, value: $0)
            }
        }

        if let urlString = alert.urlString?.value {
            let fmt = OBALoc(
                "service_alert_controller.learn_more_fmt",
                value: "Learn more: %@",
                comment: "Directs the user to tap on the link that comes at the end of the string. Learn more: <HYPERLINK IS INSERTED HERE>"
            )
            builder.append(.p, value: String(format: fmt, urlString))
        }

        if !activeWindows.isEmpty {
            builder.append(.h2, value: OBALoc("service_alert_controller.in_effect", value: "In Effect", comment: "As in 'this is in effect/occurring' from/to"))
            builder.append(.ul) { b in
                activeWindows.forEach { b.append(.li, value: $0) }
            }
        }

        let affectedAgencies = alert.affectedAgencies.map { $0.name }.sorted()
        if !affectedAgencies.isEmpty {
            builder.append(.h2, value: OBALoc("service_alert_controller.affected_agencies", value: "Affected Agencies", comment: "The transit agencies affected by this service alert."))
            builder.append(.ul) { b in
                affectedAgencies.forEach { b.append(.li, value: $0) }
            }
        }

        let affectedRoutes = alert.affectedRoutes.map { $0.shortName }.sorted()
        if !affectedRoutes.isEmpty {
            builder.append(.h2, value: OBALoc("service_alert_controller.affected_routes", value: "Affected Routes", comment: "The routes affected by this service alert."))
            builder.append(.ul) { b in
                affectedRoutes.forEach { b.append(.li, value: $0) }
            }
        }

        let affectedStops = alert.affectedStops.map { Formatters.formattedTitle(stop: $0) }.sorted()
        if !affectedStops.isEmpty {
            builder.append(.h2, value: OBALoc("service_alert_controller.affected_stops", value: "Affected Stops", comment: "The stops affected by this service alert."))
            builder.append(.ul) { b in
                affectedStops.forEach { b.append(.li, value: $0) }
            }
        }

        let affectedTrips = alert.affectedTrips.map { $0.routeHeadsign }.sorted()
        if !affectedTrips.isEmpty {
            builder.append(.h2, value: OBALoc("service_alert_controller.affected_trips", value: "Affected Trips", comment: "The trips affected by this service alert."))
            builder.append(.ul) { b in
                affectedTrips.forEach { b.append(.li, value: $0) }
            }
        }

        let body = builder.HTML
        return """
        <html>
        <head>
            <style>
                body {
                    background-color:#000;
                    color:#fff
                }
                @media screen and (prefers-color-scheme:light) {
                    body {
                        background-color:#fff;
                        color:#000
                    }
                }
            </style>
        </head>
        <body>
            \(body)
        </body>
        </html>
        """
    }
}

nonisolated fileprivate struct HTMLBuilder {
    private(set) var HTML = String()

    enum Tag: String {
        case h1, h2, h3
        case ul, li
        case p

        var opening: String { "<\(rawValue)>" }
        var closing: String { "</\(rawValue)>" }
    }

    mutating func append(_ tag: Tag, value: String? = nil, closure: ((inout HTMLBuilder) -> Void)? = nil) {
        HTML.append(tag.opening)
        if let value = value {
            HTML.append(value)
        } else if let closure = closure {
            var builder = HTMLBuilder()
            closure(&builder)
            HTML.append(builder.HTML)
        }
        HTML.append(tag.closing)
    }
}
