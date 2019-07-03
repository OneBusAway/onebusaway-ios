//
//  BookmarksViewController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 6/26/19.
//

import UIKit
import AloeStackView

/// This view controller powers the Bookmarks tab.
@objc(OBABookmarksViewController) public class BookmarksViewController: UIViewController, AloeStackTableBuilder {

    /// The OBA application object
    private let application: Application

    var theme: Theme { return application.theme }

    lazy var stackView = AloeStackView.autolayoutNew(
        backgroundColor: application.theme.colors.systemBackground
    )

    /// Creates a Bookmarks controller
    /// - Parameter application: The OBA application object
    public init(application: Application) {
        self.application = application

        super.init(nibName: nil, bundle: nil)

        title = NSLocalizedString("bookmarks_controller.title", value: "Bookmarks", comment: "Title of the Bookmarks tab")
        tabBarItem.image = Icons.bookmarksTabIcon
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.addSubview(stackView)
        stackView.pinToSuperview(.edges)

        reloadTable()
    }

    private func reloadTable() {
        stackView.removeAllRows()

        for group in application.userDataStore.bookmarkGroups {
            let bookmarks = application.userDataStore.bookmarksInGroup(group)
            if bookmarks.count > 0 {
                addRowsForGroup(name: group.name, bookmarks: bookmarks)
            }
        }

        addRowsForGroup(name: self.title!, bookmarks: application.userDataStore.bookmarksInGroup(nil))
    }

    private func addRowsForGroup(name: String, bookmarks: [Bookmark]) {
        addTableHeaderToStack(headerText: name)

        for b in bookmarks {
            let row = DefaultTableRowView(title: b.name, accessoryType: .disclosureIndicator)
            addGroupedTableRowToStack(row) { [weak self] _ in
                guard let self = self else { return }
                self.application.viewRouter.navigateTo(stop: b.stop, from: self)
            }
        }
    }
}
