//
//  TransitAlertDetailViewController.swift
//  OBAKit
//
//  Created by Alan Chu on 10/31/20.
//

import OBAKitCore
import UIKit

class TransitAlertDetailViewController: UIViewController {
    private let transitAlert: TransitAlertViewModel
    private let webView = DocumentWebView()

    init(_ transitAlert: TransitAlertViewModel) {
        self.transitAlert = transitAlert
        super.init(nibName: nil, bundle: nil)

        self.title = Strings.serviceAlert

        navigationItem.largeTitleDisplayMode = .never
    }

    override func viewDidLoad() {
        webView.frame = view.bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(webView)

        let title = transitAlert.title(forLocale: .current) ?? Strings.serviceAlert
        let body = transitAlert.body(forLocale: .current) ?? "No additional details available."

        let html = """
        <h1>\(title)</h1>
        <p>\(body)</p>
        """

        webView.setPageContent(html)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
