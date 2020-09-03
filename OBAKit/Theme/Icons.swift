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
        configureForTabIcon(systemImage(named: "map", fallback: "map"))
    }

    /// The Map tab selected icon, for apps using a tab bar UI metaphor.
    public class var mapSelectedTabIcon: UIImage {
        configureForTabIcon(systemImage(named: "map.fill", fallback: "map_selected"))
    }

    /// The Recent tab icon, for apps using a tab bar UI metaphor.
    public class var recentTabIcon: UIImage {
        configureForTabIcon(systemImage(named: "clock", fallback: "recent"))
    }

    /// The Recent tab selected icon, for apps using a tab bar UI metaphor.
    public class var recentSelectedTabIcon: UIImage {
        configureForTabIcon(systemImage(named: "clock.fill", fallback: "recent_selected"))
    }

    /// The Bookmarks tab icon, for apps using a tab bar UI metaphor.
    public class var bookmarksTabIcon: UIImage {
        configureForTabIcon(systemImage(named: "bookmark", fallback: "bookmark"))
    }

    /// The Bookmarks tab selected icon, for apps using a tab bar UI metaphor.
    public class var bookmarksSelectedTabIcon: UIImage {
        configureForTabIcon(systemImage(named: "bookmark.fill", fallback: "bookmark_selected"))
    }

    /// A More tab icon, for apps using a tab bar UI metaphor.
    public class var moreTabIcon: UIImage {
        configureForTabIcon(systemImage(named: "ellipsis.circle", fallback: "more"))
    }

    /// A More tab selected icon, for apps using a tab bar UI metaphor.
    public class var moreSelectedTabIcon: UIImage {
        configureForTabIcon(systemImage(named: "ellipsis.circle.fill", fallback: "more_selected"))
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
        let image = systemImage(named: "chevron.right", fallback: "chevron")
        if #available(iOS 13, *) {
            return image
                .withTintColor(.systemGray, renderingMode: .alwaysOriginal)
                .withConfiguration(UIImage.SymbolConfiguration.init(weight: .bold))
        } else {
            return image
        }
    }

    /// A checkmark icon.
    public class var checkmark: UIImage {
        systemImage(named: "checkmark", fallback: "checkmark")
    }

    /// An 'info' (i) button
    public class var info: UIImage {
        systemImage(named: "info.circle", fallback: "info")
    }

    // MARK: - Actions

    /// A circular close button
    public class var closeCircle: UIImage {
        systemImage(named: "xmark.circle.fill", fallback: "close_circle")
    }

    /// A refresh icon.
    public class var refresh: UIImage {
        configureForButtonIcon(systemImage(named: "arrow.clockwise", fallback: "refresh"))
    }

    /// A filter icon.
    public class var filter: UIImage {
        configureForButtonIcon(systemImage(named: "line.horizontal.3.decrease", fallback: "filter"))
    }

    public class var addAlarm: UIImage {
        imageNamed("add_alarm")
    }

    /// An ellipsis (...) in a circle.
    public class var showMore: UIImage {
        systemImage(named: "ellipsis.circle.fill", fallback: "show_more")
    }

    // MARK: - Bookmarks

    /// An icon used to represent bookmarked stops and trips.
    public class var bookmarkIcon: UIImage {
        imageNamed("bookmark_icon")     // Use asset catalog image, don't use system image.
    }

    /// An icon used to indicate that tapping on it will add a bookmark to the app.
    public class var addBookmark: UIImage {
        systemImage(named: "bookmark.circle", fallback: "favorited")
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
        imageNamed("error_outline")
    }

    /// A larger version of the navigation arrow icon used for the map tab.
    ///
    /// The apparent size of this image is 48x48pt.
    public class var nearMe: UIImage {
        configureForButtonIcon(systemImage(named: "location.fill", fallback: "near_me"))
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
        systemImage(named: "exclamationmark.circle.fill", fallback: "unread_alert")
    }

    public class var readAlert: UIImage {
        systemImage(named: "exclamationmark.circle", fallback: "read_alert")
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

    /// On iOS 13+, this applies the configuration used for generating tab bar icons. On iOS 12, this does nothing and returns its input.
    private class func configureForTabIcon(_ image: UIImage) -> UIImage {
        if #available(iOS 13, *) {
            let config = UIImage.SymbolConfiguration(textStyle: .headline, scale: .medium)
            return image.applyingSymbolConfiguration(config)!
        } else {
            return image
        }
    }

    /// On iOS 13+, this applies the configuration used for generating button icons. On iOS 12, this does nothing and returns its input.
    private class func configureForButtonIcon(_ image: UIImage) -> UIImage {
        if #available(iOS 13, *) {
            return image.applyingSymbolConfiguration(.init(pointSize: 16))!
        } else {
            return image
        }
    }

    /// Tries to get the specified system image. If the image cannot be initialized, it will use the fallback name.
    private static func systemImage(named systemName: String, fallback: String) -> UIImage {
        if #available(iOS 13, *) {
            return UIImage(systemName: systemName) ?? imageNamed(fallback)
        } else {
            return imageNamed(fallback)
        }
    }

    private static func imageNamed(_ name: String) -> UIImage {
        UIImage(named: name, in: Bundle(for: self), compatibleWith: nil)!
    }
}
