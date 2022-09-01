//
//  ActivityIndicatedButton.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit

/// A button can be replaced with an activity indicator.
public class ActivityIndicatedButton: UIView {
    public struct Configuration: Equatable {
        /// The text to display in the title.
        var text: String

        /// Image to display alongside the text when using the large content viewer.
        var largeContentImage: UIImage?

        /// Upon tapping the button, the view displays an activity indicator until the `config` is updated.
        var showsActivityIndicatorOnTap: Bool

        var action: VoidBlock

        /// - parameter text: The localized string to display in the title.
        /// - parameter largeContentImage: Image to display alongside the text when using the large content viewer. Optional, but recommended.
        /// - parameter showsActivityIndicatorOnTap: On tap, the button is replaced by activity indicator. It is recommended you set this to `true` for async operations that may take a while or should be atomic.
        /// - parameter action: The action to perform when the button is tapped.
        public init(text: String,
                    largeContentImage: UIImage?,
                    showsActivityIndicatorOnTap: Bool = true,
                    action: @escaping VoidBlock) {
            self.text = text
            self.largeContentImage = largeContentImage
            self.showsActivityIndicatorOnTap = showsActivityIndicatorOnTap
            self.action = action
        }

        public static func == (lhs: Configuration, rhs: Configuration) -> Bool {
            return lhs.text == rhs.text &&
                lhs.largeContentImage == rhs.largeContentImage &&
                lhs.showsActivityIndicatorOnTap == rhs.showsActivityIndicatorOnTap
        }
    }

    // MARK: - State
    public var config: Configuration? {
        didSet {
            DispatchQueue.main.async {
                self.configureView()
            }
        }
    }

    // MARK: - UI
    fileprivate lazy var button: UIButton = {
        let button = UIButton()
        button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        button.setTitleColor(ThemeColors.shared.brand, for: .normal)
        button.addTarget(self, action: #selector(buttonDidTap), for: .touchUpInside)

        button.scalesLargeContentImage = true
        button.showsLargeContentViewer = true
        button.addInteraction(UILargeContentViewerInteraction())

        return button
    }()

    fileprivate let chevron: UIImageView = {
        let view = UIImageView(image: UIImage(systemName: "chevron.compact.down"))
        view.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .headline)
        view.tintColor = ThemeColors.shared.brand
        return view
    }()

    fileprivate let activityIndicator: UIActivityIndicatorView = {
        let activityIndicator = UIActivityIndicatorView(style: .medium)
        activityIndicator.hidesWhenStopped = true
        return activityIndicator
    }()

    // MARK: - Initializers
    public init(config: Configuration? = nil) {
        self.config = config
        super.init(frame: .zero)
        let stackView = UIStackView.stack(axis: .vertical,
                                          distribution: .fill,
                                          alignment: .center,
                                          arrangedSubviews: [button, chevron, activityIndicator])
        stackView.setCustomSpacing(0, after: button)
        addSubview(stackView)
        stackView.pinToSuperview(.edges)

        configureView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UI methods
    public func prepareForReuse() {
        self.config = nil
    }

    public func showActivityIndicator() {
        self.button.isHidden = true
        self.chevron.isHidden = true
        self.activityIndicator.startAnimating()
    }

    public func hideActivityIndicator() {
        self.button.isHidden = false
        self.chevron.isHidden = false
        self.activityIndicator.stopAnimating()
    }

    func configureView() {
        self.activityIndicator.stopAnimating()
        self.button.isHidden = false
        self.chevron.isHidden = false

        // If there is no config, then hide the view to prevent Voiceover interaction.
        self.isHidden = self.config == nil

        self.button.setTitle(config?.text, for: .normal)
        self.button.largeContentImage = config?.largeContentImage

        self.layoutIfNeeded()
    }

    @objc func buttonDidTap(_ sender: UIButton) {
        guard let config = self.config else { return }
        config.action()

        guard config.showsActivityIndicatorOnTap else { return }
        showActivityIndicator()
    }
}
