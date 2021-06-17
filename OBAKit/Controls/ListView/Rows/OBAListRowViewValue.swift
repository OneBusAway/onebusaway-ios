//
//  OBAListRowViewValue.swift
//  OBAKit
//
//  Created by Alan Chu on 10/4/20.
//

import OBAKitCore

// MARK: - Default ViewModel for convenience
extension OBAListRowView {
    /// For convenience, if you are tracking data separately from the view model or you are displaying UI with no data,
    /// you can use this view model to define a `value` appearance list row.
    public struct ValueViewModel: OBAListViewItem {
        public let id: UUID = UUID()
        public var image: UIImage?
        public var title: OBAListRowConfiguration.LabelText
        public var subtitle: OBAListRowConfiguration.LabelText?
        public var accessoryType: OBAListRowConfiguration.Accessory = .disclosureIndicator

        public var onSelectAction: OBAListViewAction<ValueViewModel>?

        public var configuration: OBAListViewItemConfiguration {
            return .custom(OBAListRowConfiguration(image: image, text: title, secondaryText: subtitle, appearance: .value, accessoryType: accessoryType))
        }

        /// Convenience initializer for `ValueViewModel` using `String` as text.
        public init(
            image: UIImage? = nil,
            title: String,
            subtitle: String?,
            accessoryType: OBAListRowConfiguration.Accessory = .disclosureIndicator,
            onSelectAction: OBAListViewAction<ValueViewModel>? = nil) {

            self.init(image: image, title: .string(title), subtitle: .string(subtitle), accessoryType: .disclosureIndicator, onSelectAction: onSelectAction)
        }

        /// Convenience initializer for `ValueViewModel` using `NSAttributedString` as text.
        public init(
            image: UIImage? = nil,
            title: NSAttributedString,
            subtitle: NSAttributedString?,
            accessoryType: OBAListRowConfiguration.Accessory = .disclosureIndicator,
            onSelectAction: OBAListViewAction<ValueViewModel>? = nil) {

            self.init(image: image, title: .attributed(title), subtitle: .attributed(subtitle), accessoryType: .disclosureIndicator, onSelectAction: onSelectAction)
        }

        public init(
            image: UIImage? = nil,
            title: OBAListRowConfiguration.LabelText,
            subtitle: OBAListRowConfiguration.LabelText?,
            accessoryType: OBAListRowConfiguration.Accessory = .disclosureIndicator,
            onSelectAction: OBAListViewAction<ValueViewModel>? = nil) {
            self.image = image
            self.title = title
            self.subtitle = subtitle
            self.accessoryType = accessoryType
            self.onSelectAction = onSelectAction
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(id)
            hasher.combine(image)
            hasher.combine(title)
            hasher.combine(subtitle)
            hasher.combine(accessoryType)
        }

        public static func == (lhs: ValueViewModel, rhs: ValueViewModel) -> Bool {
            return
                lhs.id == rhs.id &&
                lhs.image == rhs.image &&
                lhs.title == rhs.title &&
                lhs.subtitle == rhs.subtitle &&
                lhs.accessoryType == rhs.accessoryType
        }
    }
}
