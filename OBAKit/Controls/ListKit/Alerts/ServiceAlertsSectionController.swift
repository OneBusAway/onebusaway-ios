//
//  ServiceAlertsSectionController.swift
//  OBAKit
//
//  Created by Alan Chu on 8/30/20.
//

import UIKit
import IGListKit
import OBAKitCore

final class ServiceAlertData: TransitAlertData, Equatable {
    let serviceAlert: ServiceAlert

    // MARK: - Properties
    var id: String { serviceAlert.id }
    var title: String { serviceAlert.summary.value }

    fileprivate(set) lazy var agency: String = {
        return self.serviceAlert.affectedAgencies
            .map { $0.name }
            .sorted()
            .joined(separator: ", ")
    }()

    // MARK: - TransitAlertData
    var subjectText: String? { title }
    var subtitleText: String? { agency }
    let isUnread: Bool

    // MARK: - Initializers
    public init(serviceAlert: ServiceAlert, isUnread: Bool) {
        self.serviceAlert = serviceAlert
        self.isUnread = isUnread
    }

    // MARK: - Equatable methods
    static func == (lhs: ServiceAlertData, rhs: ServiceAlertData) -> Bool {
        return lhs.subjectText == rhs.subjectText
            && lhs.subtitleText == rhs.subtitleText
            && lhs.isUnread == rhs.isUnread
    }
}

// MARK: - Section data

final class ServiceAlertsSectionData: NSObject, ListDiffable {
    enum CollapsedState {
        /// This section is collapsed.
        case collapsed

        /// This section is expanded.
        case expanded

        /// This section will always be expanded (ignores user setting).
        case alwaysExpanded

        var isCollapsed: Bool {
            return self == .collapsed
        }
    }

    var serviceAlerts: [ServiceAlertData]
    var collapsedState: CollapsedState

    public init(serviceAlertData: [ServiceAlertData], collapsed: CollapsedState) {
        self.serviceAlerts = serviceAlertData
        self.collapsedState = collapsed
    }

    func diffIdentifier() -> NSObjectProtocol {
        return "ServiceAlertsSectionIdentifier" as NSString
    }

    func isEqual(toDiffableObject object: ListDiffable?) -> Bool {
        guard let object = object as? ServiceAlertsSectionData else { return false }

        return object.serviceAlerts == self.serviceAlerts &&
            object.collapsedState == self.collapsedState
    }
}

protocol ServiceAlertsSectionControllerDelegate: class {
    func serviceAlertsSectionController(_ controller: ServiceAlertsSectionController, didSelectAlert alert: ServiceAlert)
    func serviceAlertsSectionControllerDidTapHeader(_ controller: ServiceAlertsSectionController)
}

final class ServiceAlertsSectionController: OBAListSectionController<ServiceAlertsSectionData> {
    enum State {
        case noServiceAlerts
        case singleServiceAlert
        case multipleServiceAlerts
        case collapsedServiceAlerts
        case noHeader
    }

    var state: State {
        guard let sectionData = self.sectionData,
            sectionData.serviceAlerts.count > 0 else {
                return .noServiceAlerts
        }

        if sectionData.serviceAlerts.count == 1 {
            // If there is only one service alert, don't show the header.
            return .singleServiceAlert
        } else {
            switch sectionData.collapsedState {
            case .alwaysExpanded:
                return .noHeader
            case .collapsed:
                return .collapsedServiceAlerts
            case .expanded:
                return .multipleServiceAlerts
            }
        }
    }

    weak var delegate: ServiceAlertsSectionControllerDelegate?

    override func numberOfItems() -> Int {
        switch state {
        case .noServiceAlerts:          // Don't need to show anything
            return 0
        case .singleServiceAlert:       // No need to show header
            return 1
        case .collapsedServiceAlerts:   // Only show header
            return 1
        case .multipleServiceAlerts:    // +1 for the header
            return sectionData!.serviceAlerts.count + 1
        case .noHeader:                 // No header
            return sectionData!.serviceAlerts.count
        }
    }

    override func cellForItem(at index: Int) -> UICollectionViewCell {
        switch state {
        case .noServiceAlerts:
            preconditionFailure("There should be zero number of cells if the section data state is `noServiceAlerts`.")
        case .singleServiceAlert, .noHeader:
            return alertCell(forServiceAlert: sectionData!.serviceAlerts[index], at: index)
        case .collapsedServiceAlerts:
            return headerCell(at: index)
        case .multipleServiceAlerts:
            if index == 0 {
                return headerCell(at: index)
            } else {
                return alertCell(forServiceAlert: sectionData!.serviceAlerts[index - 1], at: index)
            }
        }
    }

    func headerCell(at index: Int) -> UICollectionViewCell {
        let cell = dequeueReusableCell(type: CollapsibleHeaderCell.self, at: index)
        cell.textLabel.text = Strings.serviceAlerts
        cell.state = sectionData!.collapsedState.isCollapsed ? .closed : .open
        return cell
    }

    func alertCell(forServiceAlert serviceAlert: ServiceAlertData, at index: Int) -> UICollectionViewCell {
        let cell = dequeueReusableCell(type: TransitAlertCell.self, at: index)
        cell.data = serviceAlert

        return cell
    }

    override func didSelectItem(at index: Int) {
        func didTapAlert(at index: Int) {
            guard let alert = sectionData?.serviceAlerts[index].serviceAlert else { return }
            delegate?.serviceAlertsSectionController(self, didSelectAlert: alert)
        }

        switch state {
        case .noServiceAlerts: return
        case .singleServiceAlert:
            didTapAlert(at: index)
        case .collapsedServiceAlerts:
            delegate?.serviceAlertsSectionControllerDidTapHeader(self)
        case .multipleServiceAlerts:
            if index == 0 {
                delegate?.serviceAlertsSectionControllerDidTapHeader(self)
            } else {
                didTapAlert(at: index - 1)
            }
        case .noHeader:
            didTapAlert(at: index)
        }
    }
}
