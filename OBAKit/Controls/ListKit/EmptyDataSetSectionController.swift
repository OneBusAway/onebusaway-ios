//
//  EmptyDataSetSectionController.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import IGListKit
import OBAKitCore

final class EmptyDataSetSectionData: NSObject, ListDiffable {
    // MARK: - Properties
    let alignment: EmptyDataSetView.EmptyDataSetAlignment
    let title: String?
    let body: String?
    let image: UIImage?
    let buttonConfig: ActivityIndicatedButton.Configuration?

    // MARK: - Initializers
    init(alignment: EmptyDataSetView.EmptyDataSetAlignment = .top,
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
    convenience init(error: Error, image: UIImage? = nil, buttonConfig: ActivityIndicatedButton.Configuration? = nil) {
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

    // MARK: - ListDiffable methods
    func diffIdentifier() -> NSObjectProtocol {
        return "EmptyDataSetSectionData" as NSString
    }

    func isEqual(toDiffableObject object: ListDiffable?) -> Bool {
        guard let object = object as? EmptyDataSetSectionData else { return false }
        return alignment == object.alignment &&
            title == object.title &&
            body == object.body &&
            image == object.image &&
            buttonConfig == object.buttonConfig
    }
}

final class EmptyDataSetSectionController: OBAListSectionController<EmptyDataSetSectionData> {
    override public func cellForItem(at index: Int) -> UICollectionViewCell {
        let cell = dequeueReusableCell(type: EmptyDataSetCell.self, at: index)
        cell.configure(with: sectionData!)

        return cell
    }
}

final class EmptyDataSetCell: SelfSizingCollectionCell {
    var emptyDataView = EmptyDataSetView()

    func configure(with sectionData: EmptyDataSetSectionData) {
        emptyDataView.removeFromSuperview()
        emptyDataView = EmptyDataSetView(alignment: sectionData.alignment)
        emptyDataView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(emptyDataView)
        emptyDataView.pinToSuperview(.readableContent)

        emptyDataView.titleLabel.text = sectionData.title
        emptyDataView.bodyLabel.text = sectionData.body
        emptyDataView.imageView.image = sectionData.image

        emptyDataView.button.config = sectionData.buttonConfig
    }
}
