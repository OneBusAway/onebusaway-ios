//
//  OBAEmptyDataSetItem.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import OBAKitCore

struct EmptyDataSetItem: OBAListViewItem {
    var configuration: OBAListViewItemConfiguration {
        return .custom(EmptyDataSetContentConfiguration(viewModel: self))
    }

    static var customCellType: OBAListViewCell.Type? {
        return EmptyDataSetCell.self
    }
    var onSelectAction: OBAListViewAction<EmptyDataSetItem>?

    // MARK: - Properties
    var id: String
    var alignment: EmptyDataSetView.EmptyDataSetAlignment
    var title: String?
    var body: String?
    var image: UIImage?
    var buttonConfig: ActivityIndicatedButton.Configuration?

    // MARK: - Initializers
    init(id: String,
         alignment: EmptyDataSetView.EmptyDataSetAlignment = .top,
         title: String?,
         body: String?,
         image: UIImage? = nil,
         buttonConfig: ActivityIndicatedButton.Configuration? = nil) {

        self.id = id
        self.alignment = alignment
        self.title = title
        self.body = body
        self.image = image
        self.buttonConfig = buttonConfig
    }

    /// This initializer may set a relevant image depending on the error, only if `image == nil`.
    init(id: String, error: Error, image: UIImage? = nil, buttonConfig: ActivityIndicatedButton.Configuration? = nil) {
        // If no image is specified...
        guard image == nil else {
            self.init(id: id, alignment: .center, title: nil, body: error.localizedDescription, image: image, buttonConfig: buttonConfig)
            return
        }

        // Then, add an icon if applicable.
        var icon: UIImage?
        switch error {
        case let apiError as APIError:
            switch apiError {
            case .networkFailure:
                icon = UIImage(systemName: "wifi.slash")
            case .captivePortal:
                icon = UIImage(systemName: "wifi.exclamationmark")
            case .noResponseBody, .requestFailure, .invalidContentType :
                icon = UIImage(systemName: "bolt.horizontal.circle")
            }
        default:
            break
        }

        self.init(id: id, alignment: .center, title: nil, body: error.localizedDescription, image: icon, buttonConfig: buttonConfig)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine("EmptyDataSetItem")
    }

    static func == (_ lhs: EmptyDataSetItem, _ rhs: EmptyDataSetItem) -> Bool {
        return lhs.alignment == rhs.alignment &&
            lhs.title == rhs.title &&
            lhs.body == rhs.body &&
            lhs.image == rhs.image &&
            lhs.buttonConfig == rhs.buttonConfig
    }
}

struct EmptyDataSetContentConfiguration: OBAContentConfiguration {
    var formatters: Formatters?
    var viewModel: EmptyDataSetItem
    var obaContentView: (OBAContentView & ReuseIdentifierProviding).Type {
        return EmptyDataSetCell.self
    }
}

final class EmptyDataSetCell: OBAListViewCell {
    var emptyDataView = EmptyDataSetView()

    override func apply(_ config: OBAContentConfiguration) {
        guard let config = config as? EmptyDataSetContentConfiguration else { return }

        emptyDataView.removeFromSuperview()
        emptyDataView = EmptyDataSetView(alignment: config.viewModel.alignment)
        emptyDataView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(emptyDataView)
        emptyDataView.pinToSuperview(.readableContent, insets: NSDirectionalEdgeInsets(top: ThemeMetrics.padding, leading: 0, bottom: ThemeMetrics.padding, trailing: 0))

        emptyDataView.titleLabel.text = config.viewModel.title
        emptyDataView.bodyLabel.text = config.viewModel.body
        emptyDataView.imageView.image = config.viewModel.image

        emptyDataView.button.config = config.viewModel.buttonConfig
    }
}
