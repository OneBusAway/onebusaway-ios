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
        let body = transitAlert.body(forLocale: .current) ?? OBALoc("transit_alert.no_additional_details.body", value: "No additional details available.", comment: "A notice when a transit alert doesn't have body text.")

        let html = """
        <h1>\(title)</h1>
        <p>\(body)</p>
        """

        webView.setPageContent(html)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard isModalInPresentation else { return }
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: Strings.close, style: .done, target: self, action: #selector(close))
    }

    @objc func close() {
        if let navController = self.navigationController, navController.topViewController != self {
            navController.popViewController(animated: true)
        } else {
            self.dismiss(animated: true, completion: nil)
        }
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
