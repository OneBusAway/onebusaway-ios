//
//  ServiceAlertViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import Combine
import OBAKitCore
@preconcurrency import WebKit
import SafariServices

final class ServiceAlertViewController: UIViewController, WKNavigationDelegate {
    lazy var webView: DocumentWebView = {
        let config = WKWebViewConfiguration()
        config.dataDetectorTypes = [.all]
        let webView = DocumentWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self

        return webView
    }()

    private let application: Application
    private let viewModel: ServiceAlertViewModel
    private var cancellables = Set<AnyCancellable>()

    init(serviceAlert: ServiceAlert, application: Application) {
        self.application = application
        self.viewModel = ServiceAlertViewModel(serviceAlert: serviceAlert, application: application)
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

        viewModel.$renderedHTML
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] html in
                self?.webView.setPageContent(html)
            }
            .store(in: &cancellables)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewModel.viewDidAppear()
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
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
}
