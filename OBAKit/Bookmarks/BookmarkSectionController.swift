//
//  BookmarkSectionController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore

@available(*, deprecated, message: "Use OBAListView")
enum BookmarkSectionState: String, Codable {
    case open, closed

    func toggledValue() -> BookmarkSectionState {
        return self == .open ? .closed : .open
    }
}

@available(*, deprecated, message: "Use OBAListView")
final class CollapsibleHeaderCell: SelfSizingCollectionCell {

    private let kUseDebugColors = false

    let textLabel: UILabel = {
        let label = UILabel.autolayoutNew()
        label.font = UIFont.preferredFont(forTextStyle: .headline)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)

        return label
    }()

    private lazy var stateImageView: UIImageView = {
        let imageView = UIImageView(image: Icons.chevron)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        return imageView
    }()

    var state: BookmarkSectionState = .closed {
        didSet {
            if state == .open {
                stateImageView.transform = CGAffineTransform(rotationAngle: .pi / 2.0)
            } else {
                stateImageView.transform = CGAffineTransform(rotationAngle: 0.0)
            }
        }
    }

    // Override accessibility properties so we don't need to manually update.
    override var accessibilityLabel: String? {
        get { return textLabel.text }
        set { _ = newValue }
    }

    override var accessibilityValue: String? {
        get {
            switch state {
            case .open:
                return OBALoc("collapsible_header_cell.voiceover.expanded", value: "Section expanded", comment: "Voiceover text describing an expanded (or opened) section.")
            case .closed:
                return OBALoc("collapsible_header_cell.voiceover.collapsed", value: "Section collapsed", comment: "Voiceover text describing a collapsed (or closed) section.")
            }
        }
        set { _ = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.backgroundColor = ThemeColors.shared.systemFill

        let imageWrapper = stateImageView.embedInWrapperView(setConstraints: false)
        NSLayoutConstraint.activate([
            stateImageView.centerYAnchor.constraint(equalTo: imageWrapper.centerYAnchor),
            stateImageView.heightAnchor.constraint(equalToConstant: 12.0),
            imageWrapper.widthAnchor.constraint(equalToConstant: 12.0),
            stateImageView.leadingAnchor.constraint(equalTo: imageWrapper.leadingAnchor),
            stateImageView.trailingAnchor.constraint(equalTo: imageWrapper.trailingAnchor)
        ])

        let stack = UIStackView.horizontalStack(arrangedSubviews: [imageWrapper, textLabel])
        stack.spacing = ThemeMetrics.padding
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -ThemeMetrics.compactPadding),
            stack.leadingAnchor.constraint(equalTo: contentView.readableContentGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.readableContentGuide.trailingAnchor),

            contentView.heightAnchor.constraint(greaterThanOrEqualTo: stack.heightAnchor),
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 40.0)
        ])

        if kUseDebugColors {
            contentView.backgroundColor = .red
            textLabel.backgroundColor = .green
            stateImageView.backgroundColor = .blue
            imageWrapper.backgroundColor = .purple
        }

        accessibilityTraits = [.header, .button]
        isAccessibilityElement = true
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
