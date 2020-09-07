//
//  AgencyAlertsSectionController.swift
//  OBAKit
//
//  Created by Alan Chu on 8/30/20.
//

import IGListKit
import OBAKitCore

// MARK: - Data models

final class AgencyAlertData: TransitAlertData, Equatable {
    let agencyAlert: AgencyAlert

    // MARK: - Properties
    var id: String { agencyAlert.id }
    var title: String? { agencyAlert.titleForLocale(Locale.current) }
    var agencyID: String { agencyAlert.agencyID }
    var isHighSeverity: Bool { agencyAlert.isHighSeverity }

    /// Truncated summary for UILabel performance. Agencies often provide long
    /// summaries, which causes poor UI performance for us. See #264 & #266.
    /// To access the full summary, use `agencyAlert.bodyForLocale(:_)` instead.
    lazy var truncatedSummary: String? = {
        guard let body = self.agencyAlert.bodyForLocale(Locale.current) else { return nil }
        return String(body.prefix(192))
    }()

    // MARK: - TransitAlertData
    var subjectText: String? { self.title }
    var subtitleText: String? { self.truncatedSummary }
    let isUnread: Bool

    // MARK: - Initializers
    init(agencyAlert: AgencyAlert, isUnread: Bool) {
        self.agencyAlert = agencyAlert
        self.isUnread = isUnread
    }

    // MARK: - Equatable methods
    static func == (lhs: AgencyAlertData, rhs: AgencyAlertData) -> Bool {
        return lhs.id == rhs.id &&
            lhs.title == rhs.title &&
            lhs.agencyID == rhs.agencyID &&
            lhs.isHighSeverity == rhs.isHighSeverity &&
            lhs.isUnread == rhs.isUnread
    }
}

final class AgencyAlertsSectionData: NSObject, ListDiffable {
    var agencyName: String
    var alerts: [AgencyAlertData]
    var isCollapsed: Bool

    public init(agencyName: String, alerts: [AgencyAlertData], isCollapsed: Bool) {
        self.agencyName = agencyName
        self.alerts = alerts
        self.isCollapsed = isCollapsed
    }

    func diffIdentifier() -> NSObjectProtocol {
        return "AgencyAlertsSectionData_\(agencyName)" as NSString
    }

    func isEqual(toDiffableObject object: ListDiffable?) -> Bool {
        guard let data = object as? AgencyAlertsSectionData else { return false }
        return self.agencyName == data.agencyName &&
            self.alerts == data.alerts &&
            self.isCollapsed == data.isCollapsed
    }
}

// MARK: - Section controller

protocol AgencyAlertsSectionControllerDelegate: class {
    func agencyAlertsSectionController(_ controller: AgencyAlertsSectionController, didSelectAlert alert: AgencyAlert)
    func agencyAlertsSectionControllerDidTapHeader(_ controller: AgencyAlertsSectionController)
}

final class AgencyAlertsSectionController: OBAListSectionController<AgencyAlertsSectionData> {
    weak var delegate: AgencyAlertsSectionControllerDelegate?

    override func numberOfItems() -> Int {
        let data = sectionData!
        if data.isCollapsed {
            return 1                        // Only 1 cell for section header
        } else {
            return data.alerts.count + 1    // + 1 for section header
        }
    }

    override func cellForItem(at index: Int) -> UICollectionViewCell {
        if index == 0 {
            return headerCell(at: index)
        } else {
            return alertCell(forAgencyAlert: sectionData!.alerts[index - 1], at: index)
        }
    }

    func headerCell(at index: Int) -> UICollectionViewCell {
        let cell = dequeueReusableCell(type: CollapsibleHeaderCell.self, at: index)
        cell.textLabel.text = sectionData!.agencyName
        cell.state = sectionData!.isCollapsed ? .closed : .open
        return cell
    }

    func alertCell(forAgencyAlert agencyAlert: AgencyAlertData, at index: Int) -> UICollectionViewCell {
        let cell = dequeueReusableCell(type: TransitAlertCell.self, at: index)
        cell.data = agencyAlert

        cell.titleNumberOfLines = 3
        cell.subtitleNumberOfLines = 2
        cell.imageView.isHidden = true

        return cell
    }

    override func didSelectItem(at index: Int) {
        if index == 0 {
            delegate?.agencyAlertsSectionControllerDidTapHeader(self)
        } else {
            guard let alert = sectionData?.alerts[index - 1].agencyAlert else { return }
            delegate?.agencyAlertsSectionController(self, didSelectAlert: alert)
        }
    }
}
