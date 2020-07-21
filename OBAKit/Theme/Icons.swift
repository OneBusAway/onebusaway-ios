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
        imageNamed("map")
    }

    /// The Recent tab icon, for apps using a tab bar UI metaphor.
    public class var recentTabIcon: UIImage {
        imageNamed("recent")
    }

    /// The Bookmarks tab icon, for apps using a tab bar UI metaphor.
    public class var bookmarksTabIcon: UIImage {
        imageNamed("bookmarks")
    }

    /// A More tab icon, for apps using a tab bar UI metaphor.
    public class var moreTabIcon: UIImage {
        imageNamed("more")
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
        imageNamed("chevron")
    }

    /// A checkmark icon.
    public class var checkmark: UIImage {
        imageNamed("checkmark")
    }

    /// An 'info' (i) button
    public class var info: UIImage {
        imageNamed("info")
    }

    // MARK: - Actions

    /// A circular close button
    public class var closeCircle: UIImage {
        imageNamed("close_circle")
    }

    /// A refresh icon.
    public class var refresh: UIImage {
        imageNamed("refresh")
    }

    /// A filter icon.
    public class var filter: UIImage {
        imageNamed("filter")
    }

    public class var addAlarm: UIImage {
        imageNamed("add_alarm")
    }

    /// An ellipsis (...) in a circle.
    public class var showMore: UIImage {
        imageNamed("show_more")
    }

    // MARK: - Bookmarks

    /// An icon used to represent bookmarked stops and trips.
    public class var bookmark: UIImage {
        imageNamed("bookmark")
    }

    /// An icon used to indicate that tapping on it will add a bookmark to the app.
    public class var addBookmark: UIImage {
        imageNamed("favorited")
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
        imageNamed("near_me")
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

    private static func imageNamed(_ name: String) -> UIImage {
        UIImage(named: name, in: Bundle(for: self), compatibleWith: nil)!
    }
}
