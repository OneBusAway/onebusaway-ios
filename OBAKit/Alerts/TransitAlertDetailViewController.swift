//
//  TransitAlertDetailViewController.swift
//  OBAKit
//
//  Created by Alan Chu on 10/31/20.
//

import OBAKitCore
import UIKit
@preconcurrency import WebKit
import SafariServices

/// Renders a full page version of a `TransitAlertViewModel`
///
/// This includes an optional "Learn More" button at the bottom of the page if the transit alert has a value for `url(forLocale:)`.
class TransitAlertDetailViewController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate {
    private let locale: Locale

    init(_ transitAlert: TransitAlertViewModel, locale: Locale = .current) {
        self.transitAlert = transitAlert
        self.locale = locale
        super.init(nibName: nil, bundle: nil)

        self.title = Strings.serviceAlert

        navigationItem.largeTitleDisplayMode = .never
    }

    override func viewDidLoad() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: closeButton)

        view.addSubview(webView)

        let html = Self.htmlFragment(for: transitAlert, locale: locale)
        webView.setPageContent(html, actionButtonTitle: destinationURL != nil ? Strings.learnMore : nil)
    }

    /// Builds the HTML fragment for a transit alert, with all user-supplied strings escaped.
    /// Exposed as `internal` so tests can assert on the output directly without loading a view.
    static func htmlFragment(for alert: TransitAlertViewModel, locale: Locale) -> String {
        let title = (alert.title(forLocale: locale) ?? Strings.serviceAlert).htmlEscaped
        let rawBody = alert.body(forLocale: locale) ?? OBALoc("transit_alert.no_additional_details.body", value: "No additional details available.", comment: "A notice when a transit alert doesn't have body text.")
        // Escape first, then convert newlines to <br> so the line breaks survive
        // HTML rendering without re-introducing any injection surface.
        let body = rawBody.htmlEscaped.replacingOccurrences(of: "\n", with: "<br>")
        return """
        <h1 class='title'>\(title)</h1>
        <p class='body'>\(body)</p>
        """
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard isModalInPresentation else { return }
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: Strings.close, style: .done, target: self, action: #selector(close))
    }

    // MARK: - Transit Alert

    private let transitAlert: TransitAlertViewModel

    /// Returns the alert's URL only when its scheme is `https` or `http`.
    /// Any other scheme (e.g. `javascript:`) is silently dropped.
    private var destinationURL: URL? {
        guard let url = transitAlert.url(forLocale: locale),
              url.scheme == "https" || url.scheme == "http" else {
            return nil
        }
        return url
    }

    // MARK: - Web View

    /// Exposes `webView` for unit tests that need to drive the navigation delegate directly.
    var testWebView: DocumentWebView { webView }

    private lazy var webView: DocumentWebView = {
        let configuration = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        userContentController.add(self, name: DocumentWebView.actionButtonHandlerName)
        configuration.userContentController = userContentController

        let view = DocumentWebView(frame: view.bounds, configuration: configuration)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.navigationDelegate = self
        view.isOpaque = false
        view.backgroundColor = ThemeColors.shared.systemBackground
        view.isInspectable = true

        return view
    }()

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard
            message.name == DocumentWebView.actionButtonHandlerName,
            let destinationURL
        else {
            return
        }

        let safari = SFSafariViewController(url: destinationURL)
        present(safari, animated: true)
    }

    // MARK: - WKNavigationDelegate

    /// Only explicit user-tapped http/https links are allowed to navigate.
    /// All other navigations (including the initial `loadHTMLString` load and
    /// any injected link with a non-http scheme) are blocked.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.navigationType == .linkActivated,
              let url = navigationAction.request.url,
              url.scheme == "https" || url.scheme == "http" else {
            decisionHandler(.allow)
            return
        }

        let safari = SFSafariViewController(url: url)
        present(safari, animated: true)
        decisionHandler(.cancel)
    }

    // MARK: - Close

    private lazy var closeButton: UIButton = {
        let btn = UIButton.buildCloseButton()
        btn.addTarget(self, action: #selector(close), for: .touchUpInside)

        return btn
    }()

    @objc func close() {
        if let navController = self.navigationController, navController.topViewController != self {
            navController.popViewController(animated: true)
        } else {
            self.dismiss(animated: true, completion: nil)
        }
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
