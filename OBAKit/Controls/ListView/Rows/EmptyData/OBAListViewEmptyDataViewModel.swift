//
//  OBAListViewEmptyDataViewModel.swift
//  OBAKit
//
//  Created by Alan Chu on 10/26/20.
//

import OBAKitCore
import UIKit

extension OBAListView {
    /// The standard empty data view model, applicable to most cases.
    /// See `OBAListView.EmptyData` for more details.
    public struct StandardEmptyDataViewModel: Equatable {
        public let alignment: EmptyDataSetView.EmptyDataSetAlignment
        public let title: String?
        public let body: String?
        public let image: UIImage?
        public let buttonConfig: ActivityIndicatedButton.Configuration?

        // MARK: - Initializers
        public init(alignment: EmptyDataSetView.EmptyDataSetAlignment = .center,
                    title: String?,
                    body: String?,
                    image: UIImage? = nil,
                    buttonConfig: ActivityIndicatedButton.Configuration? = nil) {

            self.alignment = alignment
            self.title = title
            self.body = body
            self.image = image
            self.buttonConfig = buttonConfig
        }

        /// This initializer may set a relevant image depending on the error, only if `image == nil`.
        public init(error: Error, image: UIImage? = nil, buttonConfig: ActivityIndicatedButton.Configuration? = nil) {
            // If no image is specified...
            guard image == nil else {
                self.init(alignment: .center, title: nil, body: error.localizedDescription, image: image, buttonConfig: buttonConfig)
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

            self.init(alignment: .center, title: nil, body: error.localizedDescription, image: icon, buttonConfig: buttonConfig)
        }
    }
}

extension EmptyDataSetView {
    func apply(_ viewModel: OBAListView.StandardEmptyDataViewModel) {
        titleLabel.text = viewModel.title
        bodyLabel.text = viewModel.body
        imageView.image = viewModel.image

        button.config = viewModel.buttonConfig
        layoutView()
    }
}
