//
//  Icons.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore

/// Static accessors for icons available in the framework.
class Icons: NSObject {

    // MARK: - Tab Icons
    /// The Map tab icon, for apps using a tab bar UI metaphor.
    public class var mapTabIcon: UIImage {
        configureForTabIcon(systemImage(named: "map"))
    }

    /// The Map tab selected icon, for apps using a tab bar UI metaphor.
    public class var mapSelectedTabIcon: UIImage {
        configureForTabIcon(systemImage(named: "map.fill"))
    }

    /// The Recent tab icon, for apps using a tab bar UI metaphor.
    public class var recentTabIcon: UIImage {
        configureForTabIcon(systemImage(named: "clock"))
    }

    /// The Recent tab selected icon, for apps using a tab bar UI metaphor.
    public class var recentSelectedTabIcon: UIImage {
        configureForTabIcon(systemImage(named: "clock.fill"))
    }

    /// The Bookmarks tab icon, for apps using a tab bar UI metaphor.
    public class var bookmarksTabIcon: UIImage {
        configureForTabIcon(systemImage(named: "bookmark"))
    }

    /// The Bookmarks tab selected icon, for apps using a tab bar UI metaphor.
    public class var bookmarksSelectedTabIcon: UIImage {
        configureForTabIcon(systemImage(named: "bookmark.fill"))
    }

    /// A More tab icon, for apps using a tab bar UI metaphor.
    public class var moreTabIcon: UIImage {
        configureForTabIcon(systemImage(named: "ellipsis.circle"))
    }

    /// A More tab selected icon, for apps using a tab bar UI metaphor.
    public class var moreSelectedTabIcon: UIImage {
        configureForTabIcon(systemImage(named: "ellipsis.circle.fill"))
    }

    // MARK: - Table Accessories

    /// Provides `UIImage`s, where possible, for `UITableViewCell` accessories.
    ///
    /// - Parameter accessoryType: The type of table view cell accessory.
    /// - Returns: The image that maps to the `accessoryType`, where available.
    public class func from(accessoryType: UITableViewCell.AccessoryType) -> UIImage? {
        switch accessoryType {
        case .none: return nil
        case .disclosureIndicator: return chevron
        case .detailDisclosureButton: return chevron
        case .checkmark: return checkmark
        case .detailButton: return info
        @unknown default:
            return nil
        }
    }

    /// A right-pointing chevron arrow, like the kind used as a disclosure indicator on a table cell.
    public class var chevron: UIImage {
        return systemImage(named: "chevron.right")
                .withTintColor(.systemGray, renderingMode: .alwaysOriginal)
                .withConfiguration(UIImage.SymbolConfiguration.init(weight: .bold))
    }

    /// A checkmark icon.
    public class var checkmark: UIImage {
        systemImage(named: "checkmark")
    }

    /// An 'info' (i) button
    public class var info: UIImage {
        systemImage(named: "info.circle")
    }

    // MARK: - Actions

    /// A circular close button
    public class var closeCircle: UIImage {
        systemImage(named: "xmark.circle.fill")
    }

    /// A refresh icon.
    public class var refresh: UIImage {
        configureForButtonIcon(systemImage(named: "arrow.clockwise"))
    }

    /// A filter icon.
    public class var filter: UIImage {
        configureForButtonIcon(systemImage(named: "line.horizontal.3.decrease"))
    }

    public class var addAlarm: UIImage {
        imageNamed("add_alarm")
    }

    /// An ellipsis (...) in a circle.
    public class var showMore: UIImage {
        systemImage(named: "ellipsis.circle.fill")
    }

    public class var share: UIImage {
        systemImage(named: "square.and.arrow.up")
    }

    public class var shareFill: UIImage {
        systemImage(named: "square.and.arrow.up.fill")
    }

    public class var delete: UIImage {
        systemImage(named: "trash.fill")
    }

    // MARK: - Bookmarks

    /// An icon used to represent bookmarked stops and trips.
    public class var bookmarkIcon: UIImage {
        imageNamed("bookmark_icon")     // Use asset catalog image, don't use system image.
    }

    /// An icon used to indicate that tapping on it will add a bookmark to the app.
    public class var addBookmark: UIImage {
        configureForTabIcon(systemImage(named: "bookmark.fill"))
    }

    // MARK: - Heading

    /// A gradient arc image that can be used to show the user's heading.
    public class var userHeading: UIImage {
        imageNamed("user_heading")
    }

    /// A gradient arc image that can be used to show a vehicle's heading.
    public class var vehicleHeading: UIImage {
        imageNamed("vehicle_heading")
    }

    // MARK: - Branding

    /// A large 'header'-style version of the OBA icon/logo.
    public class var header: UIImage {
        imageNamed("header")
    }

    // MARK: - Miscellaneous

    /// An image used to represent an offline internet connection.
    public class var noInternet: UIImage {
        imageNamed("no_internet")
    }

    /// An image used to represent an error condition.
    public class var errorOutline: UIImage {
        systemImage(named: "exclamationmark.circle")
    }

    /// A larger version of the navigation arrow icon used for the map tab.
    ///
    /// The apparent size of this image is 48x48pt.
    public class var nearMe: UIImage {
        configureForButtonIcon(systemImage(named: "location.fill"))
    }

    // MARK: - Search Icons

    public class var route: UIImage {
        imageNamed("route")
    }

    public class var place: UIImage {
        imageNamed("place")
    }

    public class var stop: UIImage {
        imageNamed("stop")
    }

    // MARK: - Alerts
    public class var unreadAlert: UIImage {
        systemImage(named: "exclamationmark.circle.fill")
    }

    public class var readAlert: UIImage {
        systemImage(named: "exclamationmark.circle")
    }

    // MARK: - Transport Icons

    /// Generates an appropriate icon from the specified route type.
    ///
    /// - Parameter routeType: The route type from which to generate an image.
    /// - Returns: An image representing the route type.
    public class func transportIcon(from routeType: Route.RouteType) -> UIImage {
        switch routeType {
        case .lightRail: return lightRailTransport
        case .subway: return trainTransport
        case .rail: return trainTransport
        case .bus: return busTransport
        case .ferry: return ferryTransport
        default: return busTransport
        }
    }

    /// A transport icon depicting a bus.
    public class var busTransport: UIImage {
        imageNamed("busTransport")
    }

    /// A transport icon depicting a ferry.
    public class var ferryTransport: UIImage {
        imageNamed("ferryTransport")
    }

    /// A transport icon depicting a light rail train.
    public class var lightRailTransport: UIImage {
        imageNamed("lightRailTransport")
    }

    /// A transport icon depicting a train.
    public class var trainTransport: UIImage {
        imageNamed("trainTransport")
    }

    /// A transport icon depicting a person walking.
    public class var walkTransport: UIImage {
        imageNamed("walkTransport")
    }

    // MARK: - Private Helpers

    /// This applies the configuration used for generating tab bar icons.
    private class func configureForTabIcon(_ image: UIImage) -> UIImage {
        let config = UIImage.SymbolConfiguration(textStyle: .headline, scale: .medium)
        return image.applyingSymbolConfiguration(config)!
    }

    /// This applies the configuration used for generating button icons.
    private class func configureForButtonIcon(_ image: UIImage) -> UIImage {
        return image.applyingSymbolConfiguration(.init(pointSize: 16))!
    }

    private static func systemImage(named systemName: String) -> UIImage {
        return UIImage(systemName: systemName)!
    }

    private static func imageNamed(_ name: String) -> UIImage {
        UIImage(named: name, in: resourceBundle, compatibleWith: nil)!
    }

    private class var resourceBundle: Bundle {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle(for: self)
        #endif
    }
}
