//
//  PaddingLabel.swift
//  OBAKitCore
//
//  Created by Alan Chu on 8/16/20.
//

#if !os(watchOS)
import UIKit

public class PaddingLabel: UILabel {
    // MARK: - Properties
    public var insets: UIEdgeInsets
    public var cornerRadius: CGFloat {
        get { self.layer.cornerRadius }
        set {
            self.layer.cornerRadius = newValue
            self.layer.masksToBounds = newValue > 0
        }
    }

    override public var bounds: CGRect {
        didSet {
            // ensures this works within stack views if multi-line
            preferredMaxLayoutWidth = bounds.width - (insets.left + insets.right)
        }
    }

    // MARK: - Initializers

    public init(insets: UIEdgeInsets) {
        self.insets = insets
        super.init(frame: .zero)

        registerForTraitChanges()
    }

    override public init(frame: CGRect) {
        self.insets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        super.init(frame: frame)

        registerForTraitChanges()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    override public func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override public var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right,
                      height: size.height + insets.top + insets.bottom)
    }

    func registerForTraitChanges() {
        registerForTraitChanges([UITraitAccessibilityContrast.self]) { (self: Self, _) in
            self.configure()
        }
    }

    func configure() {
        let isHighContrast = traitCollection.accessibilityContrast == .high

        if let backgroundColor = self.backgroundColor {
            self.layer.borderWidth = isHighContrast ? 4.0 : 0.0
            self.layer.borderColor = isHighContrast ? backgroundColor.cgColor : UIColor.clear.cgColor
        }
    }
}
#endif
