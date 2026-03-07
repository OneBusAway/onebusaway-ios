//
//  UIKitExtensions+OBAKitCore.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore
import MobileCoreServices
import UniformTypeIdentifiers

// MARK: - Scrollable

public protocol Scrollable where Self: UIViewController {
    var scrollView: UIScrollView { get }
}

// MARK: - UIAlertAction

public extension UIAlertAction {

    /// An alert action for cancelling an alert controller.
    class var cancelAction: UIAlertAction {
        return UIAlertAction(title: Strings.cancel, style: .cancel, handler: nil)
    }

    /// An alert action for dismissing an alert controller.
    class var dismissAction: UIAlertAction {
        return UIAlertAction(title: Strings.dismiss, style: .default, handler: nil)
    }
}

// MARK: - UIAlertController

public extension UIAlertController {

    /// Creates a `UIAlertController` designed to ask the user if they want to delete something or cancel.
    /// - Parameter title: The title of the controller.
    /// - Parameter handler: The closure called when the Delete button is pressed.
    ///
    /// - Note: No callback is invoked when the Cancel button is pressed.
    class func deletionAlert(title: String, handler: @escaping ((UIAlertAction) -> Void)) -> UIAlertController {
        let controller = UIAlertController(title: title, message: nil, preferredStyle: .alert)

        controller.addAction(UIAlertAction.cancelAction)
        controller.addAction(UIAlertAction(title: Strings.delete, style: .destructive, handler: handler))

        return controller
    }

    /// Convenience method for adding a `UIAlertAction` to the receiver.
    /// - Parameter title: The action title.
    /// - Parameter style: The style of the action.
    /// - Parameter handler: The callback for when the action is invoked by the user.
    func addAction(title: String, style: UIAlertAction.Style = .default, handler: ((UIAlertAction) -> Void)?) {
        addAction(UIAlertAction(title: title, style: style, handler: handler))
    }
}

// MARK: - UIBarButtonItem

public extension UIBarButtonItem {

    /// Convenience property for creating a `flexibleSpace`-type bar button item.
    class var flexibleSpace: UIBarButtonItem {
        return UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
    }

    /// A generic 'Back' button to use in cases where your view controller's title is too long.
    class var backButton: UIBarButtonItem {
        return UIBarButtonItem(title: Strings.back, style: .plain, target: nil, action: nil)
    }
}

// MARK: - UICollectionView

public extension UICollectionView {

    /// A sorted list of all visible collection view cells.
    var sortedVisibleCells: [UICollectionViewCell] {
        indexPathsForVisibleItems.sorted().compactMap { path in
            return cellForItem(at: path)
        }
    }
}

// MARK: - UIDevice

public extension UIDevice {

    /// Returns the device's model identifier. e.g. an iPhone XS is `iPhone11,2`.
    ///
    /// - Note: derived from [https://stackoverflow.com/questions/11197509/how-to-get-device-make-and-model-on-ios/11197770#11197770](https://stackoverflow.com/questions/11197509/how-to-get-device-make-and-model-on-ios/11197770#11197770)
    var modelName: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }
}

// MARK: - UIImage

// Adapted from https://gist.github.com/lynfogeek/4b6ce0117fb0acdabe229f6d8759a139
public extension UIImage {

    /// Draws `image` onto `baseImage` at `point`.
    /// - Parameter image: The top image.
    /// - Parameter baseImage: The base image. Determines the size of the returned image.
    /// - Parameter point: The point at which to draw `image`.
    static func draw(image: UIImage, onto baseImage: UIImage, at point: CGPoint) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(baseImage.size, true, baseImage.scale)
        baseImage.draw(at: .zero)
        image.draw(at: point)

        let composite = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return composite!
    }

    /// Darkens the image by 50%.
    ///
    /// Adapted from https://gist.github.com/mxcl/61c2b95f85dcfe4a058d25a9047e72e6
    func darkened() -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        defer { UIGraphicsEndImageContext() }

        guard let ctx = UIGraphicsGetCurrentContext(), let cgImage = cgImage else {
            return self
        }

        // flip the image, or result appears flipped
        ctx.scaleBy(x: 1.0, y: -1.0)
        ctx.translateBy(x: 0, y: -size.height)

        let rect = CGRect(origin: .zero, size: size)
        ctx.draw(cgImage, in: rect)
        UIColor(white: 0, alpha: 0.5).setFill()
        ctx.fill(rect)

        return UIGraphicsGetImageFromCurrentImageContext()!
    }

    /// Colorize the image with the given tint color.
    /// - Parameter color: The tint color.
    func tinted(color: UIColor, alpha: CGFloat = 1.0) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        defer { UIGraphicsEndImageContext() }

        color.setFill()

        let bounds = CGRect(origin: .zero, size: size)
        UIRectFill(bounds)
        draw(in: bounds, blendMode: .destinationIn, alpha: alpha)

        return UIGraphicsGetImageFromCurrentImageContext()!
    }
}

// MARK: - UIPasteboard

public extension UIPasteboard {
    /// A convenience method for setting the pasteboard to an attributed string as RTF data.
    /// - Parameter attributedString: The attributed string to which the pasteboard will be set.
    /// - Note: adapted from [https://stackoverflow.com/a/21911997/136839](https://stackoverflow.com/a/21911997/136839)
    func set(attributedString: NSAttributedString?) {
        guard
            let attributedString = attributedString,
            let rtfData = try? attributedString.data(
                from: NSRange(location: 0, length: attributedString.length),
                documentAttributes: [NSAttributedString.DocumentAttributeKey.documentType: NSAttributedString.DocumentType.rtf]),
            let rtfString = NSString(data: rtfData, encoding: String.Encoding.utf8.rawValue)
        else { return }

        items = [[UTType.rtf.identifier: rtfString, UTType.plainText.identifier: attributedString.string]]
    }
}

// MARK: - UIStackView

public extension UIStackView {
    /// Creates a horizontal axis stack view
    ///
    /// - Parameter views: The arranged subviews
    /// - Returns: The horizontal stack view.
    class func horizontalStack(arrangedSubviews views: [UIView]) -> UIStackView {
        return stack(axis: .horizontal, arrangedSubviews: views)
    }

    /// Creates a vertical axis stack view
    ///
    /// - Parameter views: The arranged subviews
    /// - Returns: The vertical stack view.
    class func verticalStack(arrangedSubviews views: [UIView]) -> UIStackView {
        return stack(axis: .vertical, arrangedSubviews: views)
    }

    /// Creates a stack view with the specified parameters.
    ///
    /// - Parameter axis: This property determines the orientation of the arranged views. Assigning the `.vertical` value creates a column of views. Assigning the `.horizontal` value creates a row. The default value is `.horizontal`.
    /// - Parameter distribution: This property determines how the stack view lays out its arranged views along its axis. The default value is `.fill`. For a list of possible values, see `UIStackView.Distribution`.
    /// - Parameter alignment: This property determines how the stack view lays out its arranged views perpendicularly to its axis. The default value is `.fill`. For a list of possible values, see `UIStackView.Alignment`.
    /// - Parameter views: The arranged subviews
    /// - Returns: The stack view configured with the specified parameters.
    class func stack(axis: NSLayoutConstraint.Axis = .horizontal,
                     distribution: UIStackView.Distribution = .fill,
                     alignment: UIStackView.Alignment = .fill,
                     arrangedSubviews views: [UIView]) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = axis
        stack.distribution = distribution
        stack.alignment = alignment
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }
}
