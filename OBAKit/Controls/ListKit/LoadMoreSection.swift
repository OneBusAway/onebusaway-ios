//
//  LoadMoreSection.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore
import IGListKit

final class LoadMoreSectionData: NSObject, ListDiffable {
    func diffIdentifier() -> NSObjectProtocol {
        return self
    }

    func isEqual(toDiffableObject object: ListDiffable?) -> Bool {
        guard let object = object as? LoadMoreSectionData else { return false }

        return errorText == errorText &&
            footerText == object.footerText
    }

    init(footerText: String?, error: Error? = nil, callback: @escaping VoidBlock) {
        self.errorText = error?.localizedDescription
        self.footerText = footerText
        self.callback = callback
    }

    let errorText: String?
    let footerText: String?
    let callback: VoidBlock
}

final class LoadMoreSectionController: OBAListSectionController<LoadMoreSectionData> {
    var loadMoreCell: LoadMoreCell?

    override public func cellForItem(at index: Int) -> UICollectionViewCell {
        let cell = dequeueReusableCell(type: LoadMoreCell.self, at: index)
        cell.errorText = sectionData?.errorText
        cell.footerText = sectionData?.footerText

        loadMoreCell = cell

        return cell
    }

    public override func didSelectItem(at index: Int) {
        sectionData?.callback()
        loadMoreCell?.button.showActivityIndicator()
    }
}

final class LoadMoreCell: SelfSizingCollectionCell {
    var errorText: String? {
        get { errorLabel.text }
        set {
            configureView()
            errorLabel.text = newValue
        }
    }

    var footerText: String? {
        get { footerLabel.text }
        set { footerLabel.text = newValue }
    }

    private static var loadMoreLocalized: String {
        return OBALoc("stop_controller.load_more_button", value: "Load More", comment: "Load More button")
    }

    // MARK: - UI
    private lazy var errorLabel: UILabel = {
        let label: PaddingLabel = .obaLabel(font: .preferredFont(forTextStyle: .body), textColor: ThemeColors.shared.label)
        label.translatesAutoresizingMaskIntoConstraints = true
        label.textAlignment = .center
        label.backgroundColor = UIColor.red.withAlphaComponent(0.25)
        label.insets = UIEdgeInsets(top: ThemeMetrics.padding,
                                    left: ThemeMetrics.padding,
                                    bottom: ThemeMetrics.padding,
                                    right: ThemeMetrics.padding)
        label.cornerRadius = 8
        return label
    }()

    // There is no action because the button is only for visuals.
    private lazy var buttonConfig = ActivityIndicatedButton.Configuration(text: LoadMoreCell.loadMoreLocalized, largeContentImage: nil, action: { })
    lazy var button: ActivityIndicatedButton = {
        let button = ActivityIndicatedButton(config: buttonConfig)
        button.translatesAutoresizingMaskIntoConstraints = true
        button.isUserInteractionEnabled = false

        return button
    }()

    private lazy var footerLabel: UILabel = {
        let label: UILabel = .obaLabel(font: .preferredFont(forTextStyle: .footnote), textColor: ThemeColors.shared.secondaryLabel)
        label.textAlignment = .center
        return label
    }()

    private lazy var stack: UIStackView = {
        let stack = UIStackView.stack(axis: .vertical,
                                      distribution: .fill,
                                      alignment: .center,
                                      arrangedSubviews: [button, footerLabel])
        stack.spacing = ThemeMetrics.padding
        stack.setCompressionResistance(horizontal: nil, vertical: .required)
        return stack
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.addSubview(stack)
        stack.pinToSuperview(.layoutMargins)

        self.largeContentTitle = LoadMoreCell.loadMoreLocalized
        self.showsLargeContentViewer = true
        self.addInteraction(UILargeContentViewerInteraction())

        configureView()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        button.prepareForReuse()
        button.config = buttonConfig
    }

    func configureView() {
        // If there is an error, add the error label to the stack view.
        // If there isn't an error, remove error label from stack view.
        if let errorText = self.errorText, !errorText.isEmpty {
            if !stack.arrangedSubviews.contains(errorLabel) {
                stack.insertArrangedSubview(errorLabel, at: 0)
            }
        } else if stack.arrangedSubviews.contains(errorLabel) {
            stack.removeArrangedSubview(errorLabel)
            errorLabel.removeFromSuperview()
        }
    }
}
