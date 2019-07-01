//
//  UIKit.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/25/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import UIKit
import MobileCoreServices

// MARK: - UIAlertAction
extension UIAlertAction {

    /// An alert action for cancelling an alert controller.
    public class var cancelAction: UIAlertAction {
        return UIAlertAction(title: Strings.cancel, style: .cancel, handler: nil)
    }
}

// MARK: - UIAlertController
extension UIAlertController {

    /// Creates a `UIAlertController` designed to ask the user if they want to delete something or cancel.
    /// - Parameter title: The title of the controller.
    /// - Parameter handler: The closure called when the Delete button is pressed.
    ///
    /// - Note: No callback is invoked when the Cancel button is pressed.
    public class func deletionAlert(title: String, handler: @escaping ((UIAlertAction) -> Void)) -> UIAlertController {
        let controller = UIAlertController(title: title, message: nil, preferredStyle: .alert)

        controller.addAction(UIAlertAction.cancelAction)
        controller.addAction(UIAlertAction(title: Strings.delete, style: .destructive, handler: handler))

        return controller
    }
}

// MARK: - UIBarButtonItem
extension UIBarButtonItem {

    /// Convenience property for creating a `flexibleSpace`-type bar button item.
    public class var flexibleSpace: UIBarButtonItem {
        return UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
    }
}

// Adapted from https://cocoacasts.com/from-hex-to-uicolor-and-back-in-swift
public extension UIColor {

    // MARK: - Initialization

    /// Initialize a `UIColor` object with a hex string. Supports either "#FFFFFF" or "FFFFFF" styles.
    ///
    /// - Parameter hex: The hex string to turn into a `UIColor`.
    convenience init?(hex: String?) {
        guard let hex = hex else {
            return nil
        }

        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt32 = 0

        var r: CGFloat = 0.0
        var g: CGFloat = 0.0
        var b: CGFloat = 0.0
        var a: CGFloat = 1.0

        let length = hexSanitized.count

        guard Scanner(string: hexSanitized).scanHexInt32(&rgb) else { return nil }

        if length == 6 {
            r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
            g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
            b = CGFloat(rgb & 0x0000FF) / 255.0

        } else if length == 8 {
            r = CGFloat((rgb & 0xFF000000) >> 24) / 255.0
            g = CGFloat((rgb & 0x00FF0000) >> 16) / 255.0
            b = CGFloat((rgb & 0x0000FF00) >> 8) / 255.0
            a = CGFloat(rgb & 0x000000FF) / 255.0

        } else {
            return nil
        }

        self.init(red: r, green: g, blue: b, alpha: a)
    }

    // MARK: - Computed Properties

    var toHex: String? {
        return toHex()
    }

    // MARK: - From UIColor to String

    func toHex(alpha: Bool = false) -> String? {
        guard let components = cgColor.components, components.count >= 3 else {
            return nil
        }

        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        var a = Float(1.0)

        if components.count >= 4 {
            a = Float(components[3])
        }

        if alpha {
            return String(format: "%02lX%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255), lroundf(a * 255))
        }
        else {
            return String(format: "%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
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

// MARK: - UIEdgeInsets

public extension UIEdgeInsets {

    /// Provides a way to bridge between libraries that use the deprecated `UIEdgeInsets` struct and `NSDirectionalEdgeInsets`.
    ///
    /// - Parameter directionalInsets: Edge insets
    init(directionalInsets: NSDirectionalEdgeInsets) {
        self.init(top: directionalInsets.top, left: directionalInsets.leading, bottom: directionalInsets.bottom, right: directionalInsets.trailing)
    }
}

// MARK: - UIImage

// Adapted from https://gist.github.com/lynfogeek/4b6ce0117fb0acdabe229f6d8759a139
public extension UIImage {

    // colorize image with given tint color
    // this is similar to Photoshop's "Color" layer blend mode
    // this is perfect for non-greyscale source images, and images that have both highlights and shadows that should be preserved
    // white will stay white and black will stay black as the lightness of the image is preserved
    func tint(tintColor: UIColor) -> UIImage {
        return modifiedImage { context, rect in
            // draw black background - workaround to preserve color of partially transparent pixels
            context.setBlendMode(.normal)
            UIColor.black.setFill()
            context.fill(rect)

            // draw original image
            context.setBlendMode(.normal)
            context.draw(self.cgImage!, in: rect)

            // tint image (loosing alpha) - the luminosity of the original image is preserved
            context.setBlendMode(.color)
            tintColor.setFill()
            context.fill(rect)

            // mask by alpha values of original image
            context.setBlendMode(.destinationIn)
            context.draw(self.cgImage!, in: rect)
        }
    }

    func overlay(color: UIColor) -> UIImage {
        return modifiedImage { (context, rect) in
            context.setBlendMode(.normal)
            UIColor.black.setFill()
            context.fill(rect)

            // draw original image
            context.setBlendMode(.normal)
            context.draw(self.cgImage!, in: rect)

            UIColor(white: 0.0, alpha: 0.4).setFill()
            context.fill(rect)
        }
    }

    private func modifiedImage(draw: (CGContext, CGRect) -> Void) -> UIImage {
        // using scale correctly preserves retina images
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        let context: CGContext! = UIGraphicsGetCurrentContext()
        assert(context != nil)

        // correctly rotate image
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1.0, y: -1.0)

        let rect = CGRect(x: 0.0, y: 0.0, width: size.width, height: size.height)

        draw(context, rect)

        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image!
    }
}

// MARK: - UIPasteboard

public extension UIPasteboard {

    private var UTTypeRTF: String {
        (kUTTypeRTF as String)
    }

    private var UTTypePlainText: String {
        (kUTTypeUTF8PlainText as String)
    }

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

        items = [[UTTypeRTF: rtfString, UTTypePlainText: attributedString.string]]
    }
}


// MARK: - UIViewController

extension UIViewController {

    /// True if this controller's `toolbarItems` property has one or more bar button items, and false if it does not.
    public var hasToolbarItems: Bool {
        let count = toolbarItems?.count ?? 0
        return count > 0
    }
}

// MARK: - UIStackView

extension UIStackView {
    /// Creates a horizontal axis stack view
    ///
    /// - Parameter views: The arranged subviews
    /// - Returns: The horizontal stack view.
    public class func horizontalStack(arrangedSubviews views: [UIView]) -> UIStackView {
        return stack(axis: .horizontal, arrangedSubviews: views)
    }

    /// Creates a vertical axis stack view
    ///
    /// - Parameter views: The arranged subviews
    /// - Returns: The vertical stack view.
    public class func verticalStack(arangedSubviews views: [UIView]) -> UIStackView {
        return stack(axis: .vertical, arrangedSubviews: views)
    }

    private class func stack(axis: NSLayoutConstraint.Axis, arrangedSubviews views: [UIView]) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = axis
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
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
        setOverrideTraitCollection(nil, forChild: controller)
        controller.removeFromParent()
    }

    /// Prepare a view controller to be added to `self` as a child controller.
    ///
    /// - Note: This method requires you to manually set `controller.view`'s frame, add it to a parent view, and call `didMove()`.
    ///
    /// - Parameters:
    ///   - controller: The child controller
    ///   - config: A block that allows you to prepare your controller's view: insert it into a parent view, set its frame.
    func prepareChildController(_ controller: UIViewController, block: () -> Void) {
        controller.willMove(toParent: self)
        setOverrideTraitCollection(traitCollection, forChild: controller)
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
