//
//  Icons.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 1/2/19.
//  Copyright © 2019 OneBusAway. All rights reserved.
//

import UIKit

public class Icons: NSObject {

    // MARK: - Tab Icons

    /// The Map tab icon, for apps using a tab bar UI metaphor.
    public class var mapTabIcon: UIImage {
        return imageNamed("map")
    }

    /// The Recent tab icon, for apps using a tab bar UI metaphor.
    public class var recentTabIcon: UIImage {
        return imageNamed("recent")
    }

    /// The Bookmarks tab icon, for apps using a tab bar UI metaphor.
    public class var bookmarksTabIcon: UIImage {
        return imageNamed("bookmarks")
    }

    /// The Settings tab icon, for apps using a tab bar UI metaphor.
    public class var settingsTabIcon: UIImage {
        return imageNamed("settings")
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
        return imageNamed("chevron")
    }

    /// A checkmark icon.
    public class var checkmark: UIImage {
        return imageNamed("checkmark")
    }

    /// An 'info' (i) button
    public class var info: UIImage {
        return imageNamed("info")
    }

    // MARK: - Actions

    /// A circular close button
    public class var closeCircle: UIImage {
        return imageNamed("close_circle")
    }

    /// A refresh icon.
    public class var refresh: UIImage {
        return imageNamed("refresh")
    }

    /// A filter icon.
    public class var filter: UIImage {
        return imageNamed("filter")
    }

    // MARK: - Favorites

    /// A filled-in star icon
    public class var favorited: UIImage {
        return imageNamed("favorited")
    }

    /// A not-filled-in star icon
    public class var unfavorited: UIImage {
        return imageNamed("unfavorited")
    }

    // MARK: - Heading

    /// A gradient arc image that can be used to show the user's heading.
    public class var userHeading: UIImage {
        return imageNamed("user_heading")
    }

    /// A gradient arc image that can be used to show a vehicle's heading.
    public class var vehicleHeading: UIImage {
        return imageNamed("vehicle_heading")
    }

    // MARK: - Branding

    /// A large 'header'-style version of the OBA icon/logo.
    public class var header: UIImage {
        return imageNamed("header")
    }

    // MARK: - Transport Icons

    /// Generates an appropriate icon from the specified route type.
    ///
    /// - Parameter routeType: The route type from which to generate an image.
    /// - Returns: An image representing the route type.
    public class func transportIcon(from routeType: RouteType) -> UIImage {
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
        return imageNamed("busTransport")
    }

    /// A transport icon depicting a ferry.
    public class var ferryTransport: UIImage {
        return imageNamed("ferryTransport")
    }

    /// A transport icon depicting a light rail train.
    public class var lightRailTransport: UIImage {
        return imageNamed("lightRailTransport")
    }

    /// A transport icon depicting a train.
    public class var trainTransport: UIImage {
        return imageNamed("trainTransport")
    }

    /// A transport icon depicting a person walking.
    public class var walkTransport: UIImage {
        return imageNamed("walkTransport")
    }

    // MARK: - Private Helpers

    private static func imageNamed(_ name: String) -> UIImage {
        return UIImage(named: name, in: Bundle(for: self), compatibleWith: nil)!
    }
}
