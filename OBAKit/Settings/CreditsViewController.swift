//
//  CreditsViewController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 7/6/19.
//

import Eureka
import IGListKit
import WebKit
import OBAKitCore

/// Displays the app's third party credits.
class CreditsViewController: UIViewController, AppContext, ListAdapterDataSource {

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
        addChildController(collectionController)
        collectionController.view.pinToSuperview(.edges)
    }

    // MARK: - Actions

    private func navigateTo(key: String) {
        guard let licenseText = credits[key] as? String else { return }
        let viewer = CreditViewerController(title: key, licenseText: licenseText)
        application.viewRouter.navigate(to: viewer, from: self)
    }

    // MARK: - IGListKit

    private lazy var collectionController = CollectionController(application: application, dataSource: self, style: .plain)

    public func objects(for listAdapter: ListAdapter) -> [ListDiffable] {
        var rows = [TableRowData]()

        for key in credits.keys.localizedCaseInsensitiveSort() {
            let row = TableRowData(title: key, accessoryType: .disclosureIndicator) { [weak self] _ in
                guard let self = self else { return }
                self.navigateTo(key: key)
            }
            rows.append(row)
        }

        return [TableSectionData(rows: rows)]
    }

    public func listAdapter(_ listAdapter: ListAdapter, sectionControllerFor object: Any) -> ListSectionController {
        return defaultSectionController(for: object)
    }

    public func emptyView(for listAdapter: ListAdapter) -> UIView? {
        return nil
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
