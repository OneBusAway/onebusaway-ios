//
//  OBAListRowViewDefault.swift
//  OBAKit
//
//  Created by Alan Chu on 10/4/20.
//

// MARK: - Default ViewModel for convenience
extension OBAListRowView {
    /// For convenience, if you are tracking data separately from the view model or you are displaying UI with no data,
    /// you can use this view model to define a `default` appearance list row.
    public struct DefaultViewModel: OBAListViewItem {
        public let id: UUID = UUID()
        public var image: UIImage?
        public var title: OBAListRowConfiguration.LabelText
        public var accessoryType: OBAListRowConfiguration.Accessory = .disclosureIndicator

        public var onSelectAction: OBAListViewAction<DefaultViewModel>?

        public var configuration: OBAListViewItemConfiguration {
            return .custom(OBAListRowConfiguration(image: image, text: title, appearance: .default, accessoryType: accessoryType))
        }

        /// Convenience initializer for `DefaultViewModel` using `String` as text.
        public init(title: String, accessoryType: OBAListRowConfiguration.Accessory = .disclosureIndicator, onSelectAction: OBAListViewAction<DefaultViewModel>? = nil) {
            self.title = .string(title)
            self.accessoryType = accessoryType
            self.onSelectAction = onSelectAction
        }

        /// Convenience initializer for `DefaultViewModel` using `NSAttributedString` as text.
        public init(title: NSAttributedString, accessoryType: OBAListRowConfiguration.Accessory = .disclosureIndicator, onSelectAction: OBAListViewAction<DefaultViewModel>? = nil) {
            self.title = .attributed(title)
            self.accessoryType = accessoryType
            self.onSelectAction = onSelectAction
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(id)
            hasher.combine(image)
            hasher.combine(title)
            hasher.combine(accessoryType)
        }

        public static func == (lhs: DefaultViewModel, rhs: DefaultViewModel) -> Bool {
            return
                lhs.id == rhs.id &&
                lhs.image == rhs.image &&
                lhs.title == rhs.title &&
                lhs.accessoryType == rhs.accessoryType
        }
    }
}
