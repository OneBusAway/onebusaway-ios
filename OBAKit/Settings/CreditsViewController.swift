//
//  CreditsViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Eureka
import IGListKit
import WebKit
import OBAKitCore

/// Displays the app's third party credits.
class CreditsViewController: UIViewController, AppContext, OBAListViewDataSource {

    let listView = OBAListView()
    let application: Application

    private let credits: [String: Any]

    init(application: Application) {
        self.application = application

        let creditsPath = Bundle(for: CreditsViewController.self).path(forResource: "OBAKit_Credits", ofType: "plist")!
        let dict = (try? Dictionary<String, Any>(plistPath: creditsPath)) ?? [:] // swiftlint:disable:this syntactic_sugar
        credits = dict.merging(application.credits) { (_, new) in new }

        super.init(nibName: nil, bundle: nil)

        title = OBALoc("credits_controller.title", value: "Credits", comment: "Title of the Credits controller")
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UIViewController

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = ThemeColors.shared.systemBackground

        view.addSubview(listView)
        listView.pinToSuperview(.edges)
        listView.obaDataSource = self
        listView.applyData()
    }

    // MARK: - Actions

    private func navigateTo(key: String) {
        guard let licenseText = credits[key] as? String else { return }
        let viewer = CreditViewerController(title: key, licenseText: licenseText)
        application.viewRouter.navigate(to: viewer, from: self)
    }

    func items(for listView: OBAListView) -> [OBAListViewSection] {
        var items: [OBAListRowView.DefaultViewModel] = []
        for key in credits.keys.localizedCaseInsensitiveSort() {
            items.append(OBAListRowView.DefaultViewModel(title: key, onSelectAction: { _ in
                self.navigateTo(key: key)
            }))
        }

        return [OBAListViewSection(id: "credits", contents: items)]
    }
}

class CreditViewerController: UIViewController {
    private let licenseText: String
    private let webView = DocumentWebView()

    init(title: String, licenseText: String) {
        self.licenseText = licenseText
        super.init(nibName: nil, bundle: nil)

        self.title = title

        navigationItem.largeTitleDisplayMode = .never
    }

    override func viewDidLoad() {
        webView.frame = view.bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(webView)

        let mungedCredits = "<code>\(licenseText.replacingOccurrences(of: "\n", with: "<br>"))</code>"
        webView.setPageContent(mungedCredits)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
