//
//  ServiceAlertViewController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 4/9/20.
//

import UIKit
import OBAKitCore
import WebKit
import SafariServices

// swiftlint:disable cyclomatic_complexity

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

        view.addSubview(webView)
        webView.pinToSuperview(.edges)

        let builder = HTMLBuilder()
        builder.append(.h1, value: serviceAlert.summary.value)
        builder.append(.p, value: application.formatters.shortDateTimeFormatter.string(from: serviceAlert.createdAt))
        if let description = serviceAlert.situationDescription {
            builder.append(.p, value: description.value)
        }

        if let urlString = serviceAlert.urlString?.value {
            let fmt = OBALoc("service_alert_controller.learn_more_fmt", value: "Learn more: %@", comment: "Directs the user to tap on the link that comes at the end of the string. Learn more: <HYPERLINK IS INSERTED HERE>")
            builder.append(.p, value: String(format: fmt, urlString))
        }

//        if serviceAlert.consequences.count > 0 {
//            builder.append(.h2, value: "Consequences")
//            for c in serviceAlert.consequences {
//                text.append("<h3>\(c.condition)</h3>")
//                if let details = c.conditionDetails {
//                    text.append("<p>Path: \(details.diversionPath)</p>")
//                    text.append("<p>Stops: \(details.stopIDs.joined(separator: ", "))</p>")
//                }
//            }
//        }

        if serviceAlert.activeWindows.count > 0 {
            builder.append(.h2, value: OBALoc("service_alert_controller.in_effect", value: "In Effect", comment: "As in 'this is in effect/occurring' from/to"))
            builder.append(.ul) { b in
                for a in self.serviceAlert.activeWindows {
                    b.append(.li, value: self.application.formatters.formattedDateRange(from: a.from, to: a.to))
                }
            }
        }

        if serviceAlert.affectedAgencies.count > 0 {
            builder.append(.h2, value: OBALoc("service_alert_controller.affected_agencies", value: "Affected Agencies", comment: "The transit agencies affected by this service alert."))
            builder.append(.ul) { b in
                for a in self.serviceAlert.affectedAgencies {
                    b.append(.li, value: a.name)
                }
            }
        }

        if serviceAlert.affectedRoutes.count > 0 {
            builder.append(.h2, value: OBALoc("service_alert_controller.affected_routes", value: "Affected Routes", comment: "The routes affected by this service alert."))
            builder.append(.ul) { b in
                for route in self.serviceAlert.affectedRoutes {
                    b.append(.li, value: route.shortName)
                }
            }
        }

        if serviceAlert.affectedStops.count > 0 {
            builder.append(.h2, value: OBALoc("service_alert_controller.affected_stops", value: "Affected Stops", comment: "The stops affected by this service alert."))
            builder.append(.ul) { b in
                for stop in self.serviceAlert.affectedStops {
                    b.append(.li, value: Formatters.formattedTitle(stop: stop))
                }
            }
        }

        if serviceAlert.affectedTrips.count > 0 {
            builder.append(.h2, value: OBALoc("service_alert_controller.affected_trips", value: "Affected Trips", comment: "The trips affected by this service alert."))
            builder.append(.ul) { b in
                for trip in self.serviceAlert.affectedTrips {
                    b.append(.li, value: trip.routeHeadsign)
                }
            }
        }

        webView.setPageContent(builder.HTML)
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
