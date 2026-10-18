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
            let icon = EmptyDataSetView.icon(for: error)

            self.init(alignment: .center, title: nil, body: error.localizedDescription, image: icon, buttonConfig: buttonConfig)
        }
    }
}

extension EmptyDataSetView {
    /// A symbol describing `error`, or `nil` when there isn't a relevant one.
    nonisolated static func icon(for error: Error) -> UIImage? {
        guard let apiError = error as? APIError else { return nil }

        let symbolName: String
        switch apiError {
        case .networkFailure, .cellularDataRestricted:
            symbolName = "wifi.slash"
        case .captivePortal:
            symbolName = "wifi.exclamationmark"
        case .noResponseBody, .requestFailure, .invalidContentType:
            symbolName = "bolt.horizontal.circle"
        case .requestNotFound:
            symbolName = "questionmark.square.dashed"
        case .serverError, .serverUnavailable, .rateLimited:
            symbolName = "server.rack"
        case .invalidResponseData:
            symbolName = "exclamationmark.triangle"
        case .surveyServiceNotConfigured:
            symbolName = "doc.text.magnifyingglass"
        case .noRegionSelected:
            symbolName = "location.slash"
        }
        return UIImage(systemName: symbolName)
    }

    func apply(_ viewModel: OBAListView.StandardEmptyDataViewModel) {
        alignment = viewModel.alignment
        titleLabel.text = viewModel.title
        bodyLabel.text = viewModel.body
        imageView.image = viewModel.image

        button.config = viewModel.buttonConfig
        layoutView()
    }
}
