//
//  ServiceAlertViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore
import WebKit
import SafariServices

// swiftlint:disable function_body_length

// Page Content Generation Flow
// Generating HTML may take a couple of seconds, so do it in the background.
// Method               Queue
// ----------------------------------
// viewDidLoad()        main
//  ↓
// viewDidAppear()      main
//  ↓
// preparePage()        background
//  ↓
// buildPageContent()   background
//  ↓
// displayPage()        main
//  ↓
// Done.
final class ServiceAlertViewController: UIViewController, WKNavigationDelegate {
    lazy var webView: DocumentWebView = {
        let config = WKWebViewConfiguration()
        config.dataDetectorTypes = [.all]
        let webView = DocumentWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self

        return webView
    }()

    let serviceAlert: ServiceAlert
    let application: Application

    let queue: DispatchQueue = .init(label: "servicealert_detail_html_builder",
                                     qos: .userInitiated,
                                     attributes: .concurrent)

    init(serviceAlert: ServiceAlert, application: Application) {
        self.serviceAlert = serviceAlert
        self.application = application
        super.init(nibName: nil, bundle: nil)

        title = Strings.serviceAlert
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.rightBarButtonItem = UIActivityIndicatorView.asNavigationItem()

        view.addSubview(webView)
        webView.pinToSuperview(.edges)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        preparePage()

        application.userDataStore.markRead(serviceAlert: serviceAlert)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.navigationType == .linkActivated else {
            decisionHandler(.allow)
            return
        }

        if let url = navigationAction.request.url {
            let safari = SFSafariViewController(url: url)
            application.viewRouter.present(safari, from: self)
        }

        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        self.navigationItem.rightBarButtonItem = UIActivityIndicatorView.asNavigationItem()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        self.navigationItem.rightBarButtonItem = nil
    }

    // MARK: - Page Content
    private func preparePage() {
        queue.async { self.buildPageContent() }
    }

    private func displayPage(contents html: String) {
        DispatchQueue.main.async {
            self.view.addSubview(self.webView)
            self.webView.pinToSuperview(.edges)
            self.webView.setPageContent(html)
        }
    }

    private func buildPageContent() {
        let builder = HTMLBuilder()
        builder.append(.h1, value: serviceAlert.summary.value)
        builder.append(.p, value: application.formatters.shortDateTimeFormatter.string(from: serviceAlert.createdAt))
        if let description = serviceAlert.situationDescription {
            // Some agencies may separate information using `\n`, so we try to account for that.
            description.value.components(separatedBy: "\n").forEach {
                builder.append(.p, value: $0)
            }
        }

        if let urlString = serviceAlert.urlString?.value {
            let fmt = OBALoc("service_alert_controller.learn_more_fmt", value: "Learn more: %@", comment: "Directs the user to tap on the link that comes at the end of the string. Learn more: <HYPERLINK IS INSERTED HERE>")
            builder.append(.p, value: String(format: fmt, urlString))
        }

//        if serviceAlert.consequences.count > 0 {
//            builder.append(.h2, value: "Consequences")
//            for c in serviceAlert.consequences {
//                builder.append(.h3, value: c.condition)
//                if let details = c.conditionDetails {
//                    builder.append(.p, value: "Path: \(details.diversionPath)")
//                    builder.append(.p, value: "Stops: \(details.stopIDs.joined(separator: ", "))")
//                }
//            }
//        }

        // Timeframe
        let activeWindows: [String] = serviceAlert.activeWindows
            .map { $0.interval }
            .sorted()
            .compactMap { application.formatters.formattedDateRange($0) }

        if activeWindows.count > 0 {
            builder.append(.h2, value: OBALoc("service_alert_controller.in_effect", value: "In Effect", comment: "As in 'this is in effect/occurring' from/to"))
            builder.append(.ul) { b in
                activeWindows.forEach {
                    b.append(.li, value: $0)
                }
            }
        }

        // Agencies
        let affectedAgencies = serviceAlert.affectedAgencies.map { $0.name }.sorted()
        if affectedAgencies.count > 0 {
            builder.append(.h2, value: OBALoc("service_alert_controller.affected_agencies", value: "Affected Agencies", comment: "The transit agencies affected by this service alert."))
            builder.append(.ul) { b in
                affectedAgencies.forEach {
                    b.append(.li, value: $0)
                }
            }
        }

        // Routes
        let affectedRoutes = serviceAlert.affectedRoutes.map { $0.shortName }.sorted()
        if affectedRoutes.count > 0 {
            builder.append(.h2, value: OBALoc("service_alert_controller.affected_routes", value: "Affected Routes", comment: "The routes affected by this service alert."))
            builder.append(.ul) { b in
                affectedRoutes.forEach {
                    b.append(.li, value: $0)
                }
            }
        }

        // Stops
        let affectedStops = serviceAlert.affectedStops.map { Formatters.formattedTitle(stop: $0) }.sorted()
        if affectedStops.count > 0 {
            builder.append(.h2, value: OBALoc("service_alert_controller.affected_stops", value: "Affected Stops", comment: "The stops affected by this service alert."))
            builder.append(.ul) { b in
                affectedStops.forEach {
                    b.append(.li, value: $0)
                }
            }
        }

        // Trips

        let affectedTrips = serviceAlert.affectedTrips.map { $0.routeHeadsign }.sorted()
        if affectedTrips.count > 0 {
            builder.append(.h2, value: OBALoc("service_alert_controller.affected_trips", value: "Affected Trips", comment: "The trips affected by this service alert."))
            builder.append(.ul) { b in
                affectedTrips.forEach {
                    b.append(.li, value: $0)
                }
            }
        }

        displayPage(contents: builder.HTML)
    }
}

fileprivate class HTMLBuilder {
    public private(set) var HTML = String()

    enum Tag: String {
        case h1, h2, h3
        case ul, li
        case p

        var opening: String {
            return "<\(rawValue)>"
        }

        var closing: String {
            return "</\(rawValue)>"
        }
    }

    func append(_ tag: Tag, value: String? = nil, closure: ((HTMLBuilder) -> Void)? = nil) {
        HTML.append(tag.opening)
        if let value = value {
            HTML.append(value)
        }
        else if let closure = closure {
            let builder = HTMLBuilder()
            closure(builder)
            HTML.append(builder.HTML)
        }
        HTML.append(tag.closing)
    }
}
