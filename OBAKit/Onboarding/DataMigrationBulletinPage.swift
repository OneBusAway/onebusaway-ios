//
//  DataMigrationBulletinPage.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import BLTNBoard
import OBAKitCore

// MARK: - DataMigrationBulletinManager

final class DataMigrationBulletinManager: NSObject {

    private let dataMigrator: DataMigrator

    init(dataMigrator: DataMigrator) {
        self.dataMigrator = dataMigrator
    }

    private lazy var bulletinManager = BLTNItemManager(rootItem: dataMigrationItem)

    private lazy var dataMigrationItem = DataMigrationBulletinPage(dataMigrator: dataMigrator) { [weak self] in
        guard let self = self else { return }
        self.dismissBulletin()
    }

    public var hasDataToMigrate: Bool {
        dataMigrator.hasDataToMigrate
    }

    func show(in application: UIApplication) {
        // Don’t show another bulletin if one already exists and is being presented.
        guard !bulletinManager.isShowingBulletin else { return }

        dataMigrationItem.forceMigration = true

        bulletinManager.showBulletin(in: application)
    }

    private func dismissBulletin() {
        bulletinManager.dismissBulletin()
    }
}

// MARK: - DataMigrationBulletinPage

final class DataMigrationBulletinPage: ThemedBulletinPage {
    private let dataMigrator: DataMigrator
    private let completion: VoidBlock

    public var forceMigration = false

    init(dataMigrator: DataMigrator, completion: @escaping VoidBlock) {
        self.dataMigrator = dataMigrator
        self.completion = completion
        super.init(title: Strings.migrateData)

        descriptionText = Strings.migrateDataDescription
        isDismissable = false
        actionButtonTitle = OBALoc("data_migration_bulletin.action_button", value: "Migrate", comment: "Action button title for the DataMigrationBulletinPage.")
        alternativeButtonTitle = OBALoc("data_migration_bulletin.dismiss_button", value: "Maybe Later…", comment: "Dismissal button title for the DataMigrationBulletinPage.")

        actionHandler = { [weak self] _ in
            guard let self = self else { return }

            self.actionButton?.isEnabled = false
            self.alternativeButton?.isEnabled = false

            self.activityLabel.isHidden = false
            self.activityIndicator.startAnimating()
            self.performDataMigration(forceMigration: self.forceMigration)
        }

        alternativeHandler = { [weak self] _ in
            guard let self = self else { return }

            let card = ThemedBulletinPage(title: self.title)
            card.descriptionText = OBALoc("data_migration_bulletin.migrate_later_text", value: "You can upgrade your data later by going to the More tab > Settings, and then tapping on the Migrate Data button.", comment: "Explanatory text that tells the user how to migrate their data later on.")
            card.isDismissable = false

            self.dataMigrator.stopMigrationPrompts()

            card.actionButtonTitle = Strings.dismiss
            card.actionHandler = { _ in
                self.completion()
            }

            self.manager?.push(item: card)
        }
    }

    override func makeViewsUnderDescription(with interfaceBuilder: BLTNInterfaceBuilder) -> [UIView]? {
        return [activityStackWrapper]
    }

    // MARK: - Progress Indicator

    private lazy var activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true

        return indicator
    }()

    private lazy var activityLabel: UILabel = {
        let label = UILabel.autolayoutNew()
        label.text = Strings.loading
        label.isHidden = true
        label.setHugging(horizontal: .required, vertical: .defaultHigh)

        return label
    }()

    private lazy var activityStack: UIStackView = {
        let stack = UIStackView.horizontalStack(arrangedSubviews: [activityIndicator, activityLabel])
        stack.spacing = ThemeMetrics.compactPadding
        return stack
    }()
    private lazy var activityStackWrapper: UIView = {
        let wrapper = activityStack.embedInWrapperView(setConstraints: false)
        NSLayoutConstraint.activate([
            activityStack.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
            activityStack.topAnchor.constraint(equalTo: wrapper.topAnchor),
            activityStack.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor)
        ])
        return wrapper
    }()

    // MARK: - Data Migration

    func performDataMigration(forceMigration: Bool) {
        dataMigrator.performMigration(forceMigration: forceMigration) { result in
            switch result {
            case .failure(let error):
                Logger.info("Data Migration Error: \(error)")
                let errorPage = DataMigrationErrorPage(error: error, completion: self.completion)
                self.manager?.push(item: errorPage)

            case .success(let migration):
                print("Bookmarks: \(migration.bookmarks.count)")
                print("Loose bookmarks to migrate: \(migration.migrationBookmarks.count)")
                print("Groups: \(migration.migrationBookmarkGroups.count)")
                print("Bookmark failures: \(migration.failedBookmarks)")

                print("Recent stops: \(migration.recentStops.count)")
                print("Stops to migrate: \(migration.migrationRecentStops.count)")
                print("Stops errors: \(migration.failedRecentStops)")

                let resultPage = DataMigrationResultPageItem(dataMigrator: self.dataMigrator, result: migration, completion: self.completion)
                self.manager?.push(item: resultPage)
            }
        }
    }
}

// MARK: - DataMigrationResultPageItem

final class DataMigrationResultPageItem: ThemedBulletinPage {
    private let dataMigrator: DataMigrator
    private let result: DataMigrationResult
    private let completion: VoidBlock

    init(dataMigrator: DataMigrator, result: DataMigrationResult, completion: @escaping VoidBlock) {
        self.dataMigrator = dataMigrator
        self.result = result
        self.completion = completion

        super.init(title: Strings.migrateData)

        descriptionText = OBALoc("data_migration_bulletin.finished_loading", value: "We're all done upgrading your data. Thanks for your patience!", comment: "This comment is displayed after the user's data is upgraded in the DataMigrationBulletinPage.")

        isDismissable = false

        actionButtonTitle = Strings.done
        actionHandler = { [weak self] _ in
            guard let self = self else { return }

            self.completion()
        }
    }
}

// MARK: - DataMigrationErrorPage

final class DataMigrationErrorPage: ThemedBulletinPage {
    private let error: DataMigrationError
    private let completion: VoidBlock

    init(error: DataMigrationError, completion: @escaping VoidBlock) {
        self.error = error
        self.completion = completion

        super.init(title: Strings.error)

        isDismissable = true

        let badgeRenderer = ImageBadgeRenderer(fillColor: .white, backgroundColor: ThemeColors.shared.errorColor)
        image = badgeRenderer.drawImageOnRoundedRect(Icons.errorOutline)

        switch error {
        case .noAPIServiceAvailable:
            descriptionText = OBALoc("data_migration_bulletin.errors.no_api_service_available", value: "Check your internet connection and try again.", comment: "An error message that appears when the user needs to have data migrated, but is not connected to the Internet.")
        case .noDataToMigrate:
            descriptionText = OBALoc("data_migration_bulletin.errors.no_data_to_migrate", value: "You're all set!", comment: "An error message that appears when the data migrator runs but no data can be migrated.")
        case .noMigrationPending:
            descriptionText = OBALoc("data_migration_bulletin.errors.no_migration_pending", value: "No data migration is pending.", comment: "An error message that appears when the data migrator runs without a pending migration.")
        }
    }
}
