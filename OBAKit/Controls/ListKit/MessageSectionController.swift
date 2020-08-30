//
//  MessageSectionController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import IGListKit
import SwipeCellKit
import OBAKitCore

// MARK: - MessageSectionData
@available(*, deprecated)
final class MessageSectionData: ListViewModel, ListDiffable {
    var author: String?
    var date: String?
    var subject: String
    var summary: String?
    var isUnread: Bool

    /// The maximum number of lines to display for the summary before truncation. Set to `0` for unlimited lines.
    /// - Note: A multiple of this value is used when the user's content size is set to an accessibility size.
    var summaryNumberOfLines: Int = 2

    /// The maximum number of lines to display for the subject before truncation. Set to `0` for unlimited lines.
    /// - Note: A multiple of this value is used when the user's content size is set to an accessibility size.
    var subjectNumberOfLines: Int = 1

    public func diffIdentifier() -> NSObjectProtocol {
        return self
    }

    public func isEqual(toDiffableObject object: ListDiffable?) -> Bool {
        guard let rhs = object as? MessageSectionData else {
            return false
        }

        return author == rhs.author && date == rhs.date && subject == rhs.subject && summary == rhs.summary && isUnread == rhs.isUnread
    }

    public init(author: String?, date: String?, subject: String, summary: String?, isUnread: Bool, tapped: ListRowActionHandler?) {
        self.author = author
        self.date = date
        self.subject = subject
        self.summary = summary
        self.isUnread = isUnread

        super.init(tapped: tapped)
    }
}

final class ServiceAlertData: NSObject {
    let serviceAlert: ServiceAlert
    let id: String
    let title: String
    let agency: String
    let isUnread: Bool

    public init(serviceAlert: ServiceAlert, id: String, title: String, agency: String, isUnread: Bool) {
        self.serviceAlert = serviceAlert
        self.id = id
        self.title = title
        self.agency = agency
        self.isUnread = isUnread
    }
}

final class ServiceAlertsSectionData: NSObject, ListDiffable {
    var serviceAlerts: [ServiceAlertData]
    var isCollapsed: Bool

    public init(serviceAlertData: [ServiceAlertData], isCollapsed: Bool) {
        self.serviceAlerts = serviceAlertData
        self.isCollapsed = isCollapsed
    }

    func diffIdentifier() -> NSObjectProtocol {
        return "ServiceAlertsSectionIdentifier" as NSString
    }

    func isEqual(toDiffableObject object: ListDiffable?) -> Bool {
        return false // TODO: me
        guard let object = object as? ServiceAlertsSectionData else { return false }
//        return object.serviceAlerts == self.serviceAlerts
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
            if sectionData.isCollapsed {
                // Only show collapsable header.
                return .collapsedServiceAlerts
            } else {
                // +1 for the collapsable header.
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
        }
    }

    override func cellForItem(at index: Int) -> UICollectionViewCell {
        switch state {
        case .noServiceAlerts:
            fatalError()                // uhhhhh.....
        case .singleServiceAlert:
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
        cell.state = sectionData!.isCollapsed ? .closed : .open
        return cell
    }

    func alertCell(forServiceAlert serviceAlert: ServiceAlertData, at index: Int) -> UICollectionViewCell {
        let cell = dequeueReusableCell(type: ServiceAlertCell.self, at: index)
        cell.serviceAlert = serviceAlert

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
        case.multipleServiceAlerts:
            if index == 0 {
                delegate?.serviceAlertsSectionControllerDidTapHeader(self)
            } else {
                didTapAlert(at: index - 1)
            }
        }
    }
}

// MARK: - MessageCell

final class ServiceAlertCell: BaseSelfSizingTableCell {
    public enum AlertData {
        case agency(AgencyAlertData)
        case service(ServiceAlertData)

        var subjectText: String? {
            switch self {
            case .service(let alert):
                return alert.title
            case .agency(let alert):
                return alert.title
            }
        }

        var subtitleText: String? {
            switch self {
            case .service(let alert):
                return alert.agency
            case .agency(let alert):
                return alert.summary
            }
        }

        var isUnread: Bool {
            switch self {
            case .service(let alert):
                return alert.isUnread
            case .agency(let alert):
                return alert.isUnread
            }
        }
    }

    private let useDebugColors = false

    // MARK: - UI

    private var contentStack: UIStackView!
    let imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.setCompressionResistance(vertical: .required)
        view.setHugging(horizontal: .defaultHigh)
        view.tintColor = ThemeColors.shared.brand

        if #available(iOS 13, *) {
            view.preferredSymbolConfiguration = .init(font: .preferredFont(forTextStyle: .headline))
        }

        return view
    }()

    private var textStack: UIStackView!

    let subjectLabel: UILabel = .obaLabel(font: .preferredFont(forTextStyle: .body))
    let subtitleLabel: UILabel = .obaLabel(font: .preferredFont(forTextStyle: .footnote), textColor: ThemeColors.shared.secondaryLabel)

    private var chevronView: UIImageView!

    // MARK: - Data
    var serviceAlert: ServiceAlertData? {
        get {
            guard let data = self.data,
                case let AlertData.service(alert) = data else {
                return nil
            }
            return alert
        }
        set {
            if let serviceAlert = newValue {
                data = .service(serviceAlert)
            } else {
                data = nil
            }
        }
    }

    var data: AlertData? {
        didSet {
            configureView()
        }
    }

    // MARK: - UICollectionViewCell

    override func prepareForReuse() {
        super.prepareForReuse()

        subjectLabel.text = nil
        subtitleLabel.text = nil

        configureView()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.textStack = UIStackView.stack(axis: .vertical, distribution: .equalSpacing, arrangedSubviews: [subjectLabel, subtitleLabel])
        self.textStack.spacing = ThemeMetrics.compactPadding

        self.contentStack = UIStackView.stack(axis: .horizontal, distribution: .fill, alignment: .leading, arrangedSubviews: [imageView, textStack])
        contentStack.spacing = ThemeMetrics.padding

        chevronView = UIImageView.autolayoutNew()
        chevronView.image = Icons.chevron
        chevronView.setCompressionResistance(vertical: .required)
        chevronView.setHugging(horizontal: .defaultHigh)

        let outerStack = UIStackView.stack(axis: .horizontal, distribution: .fill, alignment: .center, arrangedSubviews: [contentStack, chevronView])

        contentView.addSubview(outerStack)

        outerStack.pinToSuperview(.readableContent) {
            $0.trailing.priority = .required - 1
        }

        configureView()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        configureView()
    }

    private func configureView() {
        guard let data = self.data else { return }
        let imageName = data.isUnread ? "exclamationmark.circle.fill" : "exclamationmark.circle"
        if #available(iOS 13, *) {
            imageView.image = UIImage(systemName: imageName)
        }

        subjectLabel.text = data.subjectText
        subtitleLabel.text = data.subtitleText

        contentStack.axis = isAccessibility ? .vertical : .horizontal
        contentStack.alignment = isAccessibility ? .leading : .center

        isAccessibilityElement = true
        accessibilityTraits = [.button, .staticText]
        accessibilityLabel = data.subjectText
        accessibilityLabel = Strings.serviceAlert
        accessibilityValue = data.subtitleText

        if useDebugColors {
            subjectLabel.backgroundColor = .green
            contentView.backgroundColor = .yellow
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - MessageSectionController

final class MessageSectionController: OBAListSectionController<MessageSectionData> {
    override public func cellForItem(at index: Int) -> UICollectionViewCell {
        let cell = dequeueReusableCell(type: ServiceAlertCell.self, at: index)
//        cell.data = sectionData

        return cell
    }

    public override func didSelectItem(at index: Int) {
        guard
            let data = sectionData,
            let tapped = data.tapped
        else { return }

        tapped(data)
    }
}
