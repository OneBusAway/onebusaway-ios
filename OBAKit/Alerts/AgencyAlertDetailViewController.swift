//
//  AgencyAlertDetailViewController.swift
//  OBAKit
//
//  Created by Alan Chu on 10/31/20.
//

import OBAKitCore

class AgencyAlertDetailViewController: UIViewController {
    private let viewModel: AgencyAlert.ListViewModel
    private let webView = DocumentWebView()

    init(_ agencyAlert: AgencyAlert.ListViewModel) {
        self.viewModel = agencyAlert
        super.init(nibName: nil, bundle: nil)

        self.title = Strings.serviceAlert

        navigationItem.largeTitleDisplayMode = .never
    }

    override func viewDidLoad() {
        webView.frame = view.bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(webView)

        let html = """
        <h1>\(viewModel.title)</h1>
        <p>\(viewModel.subtitle)</p>
        """

        webView.setPageContent(html)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
