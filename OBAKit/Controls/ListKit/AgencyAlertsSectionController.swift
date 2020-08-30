//
//  AgencyAlertsSectionController.swift
//  OBAKit
//
//  Created by Alan Chu on 8/30/20.
//

import OBAKitCore
import Foundation
import IGListKit

final class AgencyAlertData: NSObject {
    let agencyAlert: AgencyAlert

    var id: String { agencyAlert.id }
    var title: String? { agencyAlert.titleForLocale(Locale.current) }
    var agencyID: String { agencyAlert.agencyID }
    var isHighSeverity: Bool { agencyAlert.isHighSeverity }

    lazy var summary: String? = {
        guard let body = self.agencyAlert.bodyForLocale(Locale.current) else { return nil }
        return String(body.prefix(128))
    }()

    let isUnread: Bool

    public init(agencyAlert: AgencyAlert, isUnread: Bool) {
        self.agencyAlert = agencyAlert
        self.isUnread = isUnread
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
        return false // TODO: me
    }
}

final class AgencyAlertsSectionController: OBAListSectionController<AgencyAlertsSectionData> {
    override func numberOfItems() -> Int {
        let data = sectionData!
        if data.isCollapsed {
            return 1            // Only 1 cell for section header
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
        let cell = dequeueReusableCell(type: ServiceAlertCell.self, at: index)
        cell.data = .agency(agencyAlert)

        cell.subjectLabel.numberOfLines = 2
        cell.subtitleLabel.numberOfLines = 4

        return cell
    }
}

//final class AgencyAlertCell: BaseSelfSizingTableCell {
//    private var contentStack: UIStackView!
//    private let unreadDot: UIImageView = {
//        let image: UIImage
//        if #available(iOS 13.0, *) {
//            image = UIImage(systemName: "exclamationmark.circle.fill")!
//        } else {
//            image = Icons.errorOutline
//        }
//
//        let view = UIImageView(image: image)
//        view.contentMode = .scaleAspectFit
//        view.setCompressionResistance(vertical: .required)
//        view.setHugging(horizontal: .defaultHigh)
//
//        if #available(iOS 13, *) {
//            view.preferredSymbolConfiguration = .init(font: .preferredFont(forTextStyle: .headline))
//        }
//        view.tintColor = ThemeColors.shared.brand
//
//        return view
//    }()
//
//    private var textStack: UIStackView!
//
//    private let subjectLabel: UILabel = .obaLabel(font: .preferredFont(forTextStyle: .body))
//    private let agencyLabel: UILabel = .obaLabel(font: .preferredFont(forTextStyle: .footnote), textColor: ThemeColors.shared.secondaryLabel)
//
//
//}
