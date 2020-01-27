//
//  CreditsViewController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 7/6/19.
//

import Eureka
import AloeStackView
import WebKit
import OBAKitCore

/// Displays the app's third party credits.
class CreditsViewController: UIViewController, AloeStackTableBuilder {

    lazy var stackView = AloeStackView.autolayoutNew(
        backgroundColor: ThemeColors.shared.systemBackground
    )

    private let application: Application

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

        view.addSubview(stackView)
        stackView.pinToSuperview(.edges)

        for key in credits.keys.localizedCaseInsensitiveSort() {
            let row = DefaultTableRowView(title: key, accessoryType: .disclosureIndicator)
            addGroupedTableRowToStack(row, isLastRow: false) { [weak self] _ in
                guard let self = self else { return }
                self.navigateTo(key: key)
            }
        }

        if let row = stackView.lastRow {
            stackView.setSeparatorInset(forRow: row, inset: .zero)
        }
    }

    // MARK: - Actions

    private func navigateTo(key: String) {
        guard let licenseText = credits[key] as? String else { return }
        let viewer = CreditViewerController(title: key, licenseText: licenseText)
        application.viewRouter.navigate(to: viewer, from: self)
    }
}

class CreditViewerController: UIViewController {
    private let licenseText: String
    private let webView = WKWebView()

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

        webView.loadHTMLString(buildHTML(), baseURL: nil)
    }

    private func buildHTML() -> String {
        guard
            let path = bundle.path(forResource: "credits", ofType: "html"),
            let template = try? String(contentsOfFile: path)
        else {
            return licenseText
        }

        let mungedCredits = "<code>\(licenseText.replacingOccurrences(of: "\n", with: "<br>"))</code>"
        return template.replacingOccurrences(of: "{{{credits}}}", with: mungedCredits)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
