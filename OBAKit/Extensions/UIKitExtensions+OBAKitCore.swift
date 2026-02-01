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

// MARK: - UIFont

public extension UIFont {
    /// Returns a bold version of `self`.
    var bold: UIFont {
        return withTraits(traits: .traitBold)
    }

    /// Returns an italic version of `self`.
    var italic: UIFont {
        return withTraits(traits: .traitItalic)
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

// MARK: - UILabel

public extension UILabel {

    /// Resizes the label's height to fit its text, or—if it doesn't have text—a representative sample.
    func resizeHeightToFit() {
        let labelText: NSString

        if let text = self.text, text.count > 0 {
            labelText = text as NSString
        }
        else {
            labelText = "MWjy"
        }

        var attributes = [NSAttributedString.Key: Any]()
        attributes[NSAttributedString.Key.font] = font

        let rect = labelText.boundingRect(with: CGSize(width: frame.width, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], attributes: attributes, context: nil)

        frame.size.height = rect.height
    }

    /// Creates a new autolayout `UILabel` that attempts to maintain full visibility. This means it will adjust
    /// its font size, font scale, then font tightening to maintain visibilty. It also adapts to the user's content
    /// size setting, provided you specify a valid `UIFont`.
    /// - parameter font: The font to set for this label. It is recommended that you use
    ///     `.preferredFont` so it will adjust for content size. The default is `.preferredFont(forTextStyle: .body)`.
    /// - parameter textColor: The text color to set. The default is `.label`.
    /// - parameter numberOfLines: The number of lines to set for this label. The default is `0`.
    /// - parameter minimumScaleFactor: The smallest multiplier for the current font size that
    ///     yields an acceptable font size to use when displaying the label’s text. The default is `1`, which means the font won't scale by default.
    class func obaLabel(font: UIFont = .preferredFont(forTextStyle: .body),
                        textColor: UIColor = ThemeColors.shared.label,
                        numberOfLines: Int = 0,
                        minimumScaleFactor: CGFloat = 1) -> Self {
        let label = Self.autolayoutNew()
        label.font = font
        label.textColor = textColor
        label.numberOfLines = numberOfLines
        label.minimumScaleFactor = minimumScaleFactor
        label.allowsDefaultTighteningForTruncation = true
        label.adjustsFontForContentSizeCategory = true
        label.adjustsFontSizeToFitWidth = true
        return label
    }
}

// MARK: - UILayoutPriority

extension UILayoutPriority {
    static func + (lhs: UILayoutPriority, rhs: Float) -> UILayoutPriority {
        return UILayoutPriority(lhs.rawValue + rhs)
    }

    static func - (lhs: UILayoutPriority, rhs: Float) -> UILayoutPriority {
        return UILayoutPriority(lhs.rawValue - rhs)
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

    /// A helper for creating stack views.
    ///
    /// - Parameter axis: The axis (horizontal or vertical) for the stack view.
    /// - Parameter distribution: The distribution of the stack view.
    /// - Parameter alignment: The alignment of the stack view.
    /// - Parameter views: The arranged subviews.
    /// - Returns: The stack view.
    public class func stack(axis: NSLayoutConstraint.Axis, distribution: UIStackView.Distribution = .fill, alignment: UIStackView.Alignment = .fill, arrangedSubviews views: [UIView]) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: views)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = axis
        stack.distribution = distribution
        stack.alignment = alignment
        return stack
    }

    /// Removes all subviews from the receiver's `arrangedSubviews` list and from the view hierarchy.
    func removeAllArrangedSubviews() {
        for view in arrangedSubviews {
            removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }
}

// MARK: - UIView

public extension UIView {
    /// Helper method that makes it easier to call `setContentHuggingPriority` for both of the receiver's axes.
    /// - Parameters:
    ///   - horizontal: The horizontal content hugging priority. Pass in `nil` to leave it at its default.
    ///   - vertical: The vertical content hugging priority. Pass in `nil` to leave it at its default.
    func setHugging(horizontal: UILayoutPriority? = nil, vertical: UILayoutPriority? = nil) {
        if let horizontal = horizontal {
            setContentHuggingPriority(horizontal, for: .horizontal)
        }

        if let vertical = vertical {
            setContentHuggingPriority(vertical, for: .vertical)
        }
    }

    /// Helper method that makes it easier to call `setContentCompressionResistancePriority` for both of the receiver's axes.
    /// - Parameters:
    ///   - horizontal: The horizontal content compression resistance priority. Pass in `nil` to leave it at its default.
    ///   - vertical: The vertical content compression resistance priority. Pass in `nil` to leave it at its default.
    func setCompressionResistance(horizontal: UILayoutPriority? = nil, vertical: UILayoutPriority? = nil) {
        if let horizontal = horizontal {
            setContentCompressionResistancePriority(horizontal, for: .horizontal)
        }

        if let vertical = vertical {
            setContentCompressionResistancePriority(vertical, for: .vertical)
        }
    }
}

// MARK: - UIViewController

public extension UIViewController {

    /// Returns the containing bundle for `self`. In a framework, this will not be `Bundle.main`.
    var bundle: Bundle {
        Bundle(for: type(of: self))
    }

    /// Use this to tell if the view controller has made it through `viewDidLoad()` and is currently on-screen.
    ///
    /// `true` if `isViewLoaded` is `true` and `view.window != nil`. `false` otherwise.
    var isLoadedAndOnScreen: Bool {
        isViewLoaded && view.window != nil
    }
}

// MARK: - UIViewController/Child Controller Containment

public extension UIViewController {

    /// Remove the child controller from `self`.
    ///
    /// - Parameter controller: The child controller to remove.
    func removeChildController(_ controller: UIViewController) {
        controller.willMove(toParent: nil)
        controller.view.removeFromSuperview()
        controller.removeFromParent()
    }

    /// Prepare a view controller to be added to `self` as a child controller.
    ///
    /// - Note: This method requires you to manually set `controller.view`'s frame, add it to a parent view, and call `didMove()`.
    ///
    /// - Parameters:
    ///   - controller: The child controller
    ///   - config: A block that allows you to prepare your controller's view: insert it into a parent view, set its frame.
    func prepareChildController(_ controller: UIViewController, block: VoidBlock) {
        controller.willMove(toParent: self)
        addChild(controller)
        block()
        controller.didMove(toParent: self)
    }

    /// Preferred to `addChild`. Adds the view controller to `self` as a child controller.
    ///
    /// - Parameters:
    ///   - controller: The child controller.
    ///   - view: Optional. The parent view for `controller.view`. Defaults to `self.view` if left unspecified.
    func addChildController(_ controller: UIViewController, to view: UIView? = nil) {
        let parentView: UIView = view ?? self.view

        prepareChildController(controller) {
            controller.view.frame = parentView.bounds
            parentView.addSubview(controller.view)
        }
    }
}

// MARK: - UIWindow

public extension UIWindow {

    /// Retrieve the top-most view controller in the receiver.
    ///
    /// - Returns: The top-most view controller.
    /// - Note: Derived from [Stack Overflow](https://stackoverflow.com/a/16443826).
    func topViewController() -> UIViewController? {
        var top = rootViewController
        while true {
            if let presented = top?.presentedViewController {
                top = presented
            }
            else if let nav = top as? UINavigationController {
                top = nav.visibleViewController
            }
            else if let tab = top as? UITabBarController {
                top = tab.selectedViewController
            }
            else {
                break
            }
        }
        return top
    }
}

// MARK: - UIViewController Topmost

public extension UIViewController {
    /// Recursively find the top-most view controller starting from `self`.
    func topMostViewController() -> UIViewController {
        if let presented = presentedViewController {
            return presented.topMostViewController()
        }

        if let navigation = self as? UINavigationController {
            return navigation.visibleViewController?.topMostViewController() ?? navigation
        }

        if let tab = self as? UITabBarController {
            return tab.selectedViewController?.topMostViewController() ?? tab
        }

        return self
    }
}
