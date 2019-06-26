//
//  BookmarksViewController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 6/26/19.
//

import UIKit

/// This view controller powers the Bookmarks tab.
@objc(OBABookmarksViewController) public class BookmarksViewController: UIViewController {

    private let application: Application

    public init(application: Application) {
        self.application = application

        super.init(nibName: nil, bundle: nil)

        title = NSLocalizedString("bookmarks_controller.title", value: "Bookmarks", comment: "Title of the Bookmarks tab")
        tabBarItem.image = Icons.bookmarksTabIcon
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
