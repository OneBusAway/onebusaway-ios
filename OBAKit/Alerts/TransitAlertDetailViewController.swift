//
//  TransitAlertDetailViewController.swift
//  OBAKit
//
//  Created by Alan Chu on 10/31/20.
//

import OBAKitCore
import UIKit
import WebKit
import SafariServices

/// Renders a full page version of a `TransitAlertViewModel`
///
/// This includes an optional "Learn More" button at the bottom of the page if the transit alert has a value for `url(forLocale:)`.
class TransitAlertDetailViewController: UIViewController, WKScriptMessageHandler {
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

        let title = transitAlert.title(forLocale: locale) ?? Strings.serviceAlert
        var body = transitAlert.body(forLocale: locale) ?? OBALoc("transit_alert.no_additional_details.body", value: "No additional details available.", comment: "A notice when a transit alert doesn't have body text.")
        body = body.replacingOccurrences(of: "\n", with: "<br>")

        let html = """
        <h1 class='title'>\(title)</h1>
        <p class='body'>\(body)</p>
        """

        webView.setPageContent(html, actionButtonTitle: destinationURL != nil ? Strings.learnMore : nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard isModalInPresentation else { return }
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: Strings.close, style: .done, target: self, action: #selector(close))
    }

    // MARK: - Transit Alert

    private let transitAlert: TransitAlertViewModel

    private var destinationURL: URL? {
        transitAlert.url(forLocale: locale)
    }

    // MARK: - Web View

    private lazy var webView: DocumentWebView = {
        let configuration = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        userContentController.add(self, name: DocumentWebView.actionButtonHandlerName)
        configuration.userContentController = userContentController

        let view = DocumentWebView(frame: view.bounds, configuration: configuration)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        if #available(iOS 16.4, *) {
            view.isInspectable = true
        }

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
