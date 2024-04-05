//
//  TodayViewController.swift
//  OneBusAway Today
//
//  Created by Aaron Brethorst on 10/5/17.
//  Copyright © 2017 OneBusAway. All rights reserved.
//

import UIKit
import CoreLocation
import NotificationCenter
import OBAKitCore

let kMinutes: UInt = 60

@available(iOS, deprecated: 14.0)
class TodayViewController: UIViewController, BookmarkDataDelegate, NCWidgetProviding {
    // MARK: - App Context
    private let formatters = Formatters(
        locale: Locale.autoupdatingCurrent,
        calendar: Calendar.autoupdatingCurrent,
        themeColors: ThemeColors.shared)

    private let userDefaults = UserDefaults(suiteName: Bundle.main.appGroup!)!
    private lazy var locationManager = CLLocationManager()
    private lazy var locationService = LocationService(userDefaults: userDefaults, locationManager: locationManager)

    private lazy var app: CoreApplication = {
        let bundledRegions = Bundle.main.path(forResource: "regions", ofType: "json")!
        let config = CoreAppConfig(appBundle: Bundle.main, userDefaults: userDefaults, bundledRegionsFilePath: bundledRegions)
        return CoreApplication(config: config)
    }()

    // MARK: - Bookmarks
    var bookmarkViewsMap: [Bookmark: TodayRowView] = [:]
    private lazy var dataLoader = BookmarkDataLoader(application: app, delegate: self)

    func dataLoaderDidUpdate(_ dataLoader: BookmarkDataLoader) {
        refreshControl.stopRefreshing()
        rebuildUI()
        lastUpdatedAt = Date()
    }

    private var bestAvailableBookmarks: [Bookmark] {
        var bookmarks = app.userDataStore.favoritedBookmarks
        if bookmarks.count == 0 {
            bookmarks = app.userDataStore.bookmarks
        }
        return bookmarks
    }

    private let outerStackView: UIStackView = TodayViewController.buildStackView()

    private lazy var frontMatterStack: UIStackView = {
        let stack = TodayViewController.buildStackView()
        stack.addArrangedSubview(refreshControl)
        stack.addArrangedSubview(errorTitleLabel)
        stack.addArrangedSubview(errorDescriptionLabel)
        return stack
    }()

    private lazy var frontMatterWrapper: UIView = {
        return frontMatterStack.embedInWrapperView()
    }()

    private let bookmarkStackView: UIStackView = TodayViewController.buildStackView()
    private lazy var bookmarkWrapper: UIView = {
        return bookmarkStackView.embedInWrapperView()
    }()

    private lazy var errorTitleLabel: UILabel = {
        let label = UILabel.autolayoutNew()
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = UIFont.preferredFont(forTextStyle: .body).bold
        label.text = Strings.error
        label.isHidden = true
        return label
    }()

    private lazy var errorDescriptionLabel: UILabel = {
        let label = UILabel.autolayoutNew()
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .body)
        label.text = OBALoc("today_screen.inexplicable_error", value: "Oops, you've run into a problem that we didn't think could occur. Please contact us with any information about how you ended up in this situation. Sorry!", comment: "")
        label.isHidden = true
        return label
    }()

    private lazy var refreshControl: TodayRefreshView = {
        let refresh = TodayRefreshView.autolayoutNew()
        refresh.lastUpdatedAt = lastUpdatedAt
        refresh.refreshButton.addTarget(self, action: #selector(beginRefreshing), for: .touchUpInside)
        return refresh
    }()

    private lazy var spacerView: UIView = {
        let spacer = UIView.autolayoutNew()
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return spacer
    }()

    // MARK: - Init/View Controller Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()

        extensionContext?.widgetLargestAvailableDisplayMode = .expanded

        outerStackView.addArrangedSubview(frontMatterWrapper)
        outerStackView.addArrangedSubview(bookmarkWrapper)
        outerStackView.addArrangedSubview(spacerView)

        self.view.addSubview(outerStackView)

        let insets = NSDirectionalEdgeInsets(top: ThemeMetrics.compactPadding, leading: 10, bottom: ThemeMetrics.compactPadding, trailing: -10)
        outerStackView.pinToSuperview(.edges, insets: insets)

        rebuildUI()
    }

    // MARK: - UI Construction
    private func rebuildUI() {
        for v in bookmarkStackView.arrangedSubviews {
            bookmarkStackView.removeArrangedSubview(v)
            v.removeFromSuperview()
        }

        bookmarkViewsMap.removeAll()

        displayErrorMessagesIfAppropriate()

        for (idx, bm) in bestAvailableBookmarks.enumerated() {
            let view = viewForBookmark(bm, index: idx)
            bookmarkStackView.addArrangedSubview(view)
            bookmarkViewsMap[bm] = view

            if let key = TripBookmarkKey(bookmark: bm) {
                view.departures = dataLoader.dataForKey(key)
            }
        }

        layoutBookmarkVisibility()
    }

    private func viewForBookmark(_ bookmark: Bookmark, index: Int) -> TodayRowView {
        let v = TodayRowView(frame: .zero, formatters: formatters)
        v.translatesAutoresizingMaskIntoConstraints = false
        v.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(TodayViewController.bookmarkTapped(sender:))))
        v.bookmark = bookmark
        v.setContentHuggingPriority(.defaultHigh, for: .vertical)
        v.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)

        return v
    }

    private func displayErrorMessagesIfAppropriate() {
        if bestAvailableBookmarks.isEmpty {
            let title = OBALoc("today_screen.no_data_title", value: "No Bookmarks", comment: "The empty data set title for the Today View widget.")
            let description = OBALoc("today_screen.no_data_description", value: "Add bookmarks to Today View Bookmarks to see them here.", comment: "The empty data set description for the Today View widget.")
            showErrorMessage(title: title, description: description)
        } else if app.currentRegion == nil {
            showErrorMessage(title: Strings.error, description: OBALoc("today_screen.no_region_description", value: "We don't know where you're located. Please choose a region in OneBusAway.", comment: ""))
        } else {
            errorTitleLabel.isHidden = true
            errorDescriptionLabel.isHidden = true
        }
    }

    private func showErrorMessage(title: String, description: String) {
        errorTitleLabel.isHidden = false
        errorDescriptionLabel.isHidden = false

        errorTitleLabel.text = title
        errorDescriptionLabel.text = description
    }

    @objc func bookmarkTapped(sender: UITapGestureRecognizer?) {
        guard let sender = sender,
              let rowView = sender.view as? TodayRowView,
              let bookmark = rowView.bookmark else {
            return
        }

        let router = URLSchemeRouter(scheme: Bundle.main.extensionURLScheme!)
        let url = router.encodeViewStop(stopID: bookmark.stopID, regionID: bookmark.regionIdentifier)

        extensionContext?.open(url, completionHandler: nil)
    }

    private static func buildStackView(spacing: CGFloat = ThemeMetrics.compactPadding) -> UIStackView {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = spacing

        return stack
    }

    // MARK: - NCWidgetProviding methods
    func widgetPerformUpdate(completionHandler: @escaping (NCUpdateResult) -> Void) {
        rebuildUI()
        reloadData(completionHandler)
    }

    func widgetActiveDisplayModeDidChange(_ activeDisplayMode: NCWidgetDisplayMode, withMaximumSize maxSize: CGSize) {
        layoutBookmarkVisibility()
    }

    /// Resposible for calculating how many bookmarks can fit into the widget's size.
    func layoutBookmarkVisibility() {
        guard let extensionContext = self.extensionContext else { return }
        let displayMode = extensionContext.widgetActiveDisplayMode
        let maximumSize = extensionContext.widgetMaximumSize(for: displayMode)

        // Calculate the number of bookmarks to display given the display mode.
        // This varies depending on the number of lines the bookmark name is using.

        frontMatterWrapper.setNeedsLayout()
        frontMatterWrapper.layoutIfNeeded()
        let frontMatterHeight = frontMatterWrapper.frame.height

        let heightAvailableForBookmarks = maximumSize.height - frontMatterHeight

        var numberOfBookmarksToDisplay: Int = 0
        if displayMode == .compact {
            // Calculate the number of rows we can fit into the height available for bookmarks.
            var usedHeight: CGFloat = 0.0
            for view in bookmarkStackView.arrangedSubviews {
                let layoutSize = view.systemLayoutSizeFitting(maximumSize, withHorizontalFittingPriority: .required, verticalFittingPriority: .defaultHigh)

                guard layoutSize.height + usedHeight < heightAvailableForBookmarks else { break }
                numberOfBookmarksToDisplay += 1
                usedHeight += layoutSize.height
            }
        } else {
            // We don't need to calculate how many bookmarks to fit.
            numberOfBookmarksToDisplay = bookmarkStackView.arrangedSubviews.count
        }

        // Apply visibility of which bookmarks to display.
        for (index, row) in bookmarkStackView.arrangedSubviews.enumerated() {
            row.isHidden = index >= numberOfBookmarksToDisplay
        }

        let bookmarksSize = self.bookmarkWrapper.systemLayoutSizeFitting(maximumSize, withHorizontalFittingPriority: .required, verticalFittingPriority: .defaultHigh)

        self.preferredContentSize = CGSize(width: 10000, height: frontMatterHeight + bookmarksSize.height)
    }

    // MARK: - Refresh Control UI

    @objc private func beginRefreshing() {
        reloadData(nil)
    }

    private func reloadData(_ completionHandler: ((NCUpdateResult) -> Void)?) {
        if bestAvailableBookmarks.isEmpty {
            completionHandler?(NCUpdateResult.noData)
            return
        }

        refreshControl.beginRefreshing()
        dataLoader.loadData()
    }

    // MARK: - Last Updated Section
    private static let lastUpdatedAtUserDefaultsKey = "lastUpdatedAtUserDefaultsKey"
    var lastUpdatedAt: Date? {
        get {
            guard let defaultsDate = self.app.userDefaults.value(forKey: TodayViewController.lastUpdatedAtUserDefaultsKey) else {
                return nil
            }

            return defaultsDate as? Date
        }
        set(val) {
            self.app.userDefaults.setValue(val, forKey: TodayViewController.lastUpdatedAtUserDefaultsKey)
            refreshControl.lastUpdatedAt = val
        }
    }
}
