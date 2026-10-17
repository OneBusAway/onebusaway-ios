//
//  MapToolbarItems.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore

/// The map's controls as navigation-controller toolbar items, which the system
/// stacks above the tab bar when it presents bars vertically (iPhone Duo).
///
/// Each item has an image, which a vertical bar requires, and a title for the
/// overflow menu. Titles reuse the hover bar buttons' accessibility labels.
final class MapToolbarItems {
    let location: UIBarButtonItem
    let mapLayers: UIBarButtonItem
    let weather: UIBarButtonItem
    let myTrip: UIBarButtonItem

    init(
        location: UIButton,
        mapLayers: UIButton,
        weather: UIButton,
        myTrip: UIButton,
        showsWeather: Bool
    ) {
        self.location = Self.item(mirroring: location)
        self.mapLayers = Self.item(mirroring: mapLayers)
        self.weather = Self.item(mirroring: weather)
        self.myTrip = Self.item(mirroring: myTrip)
        self.showsWeather = showsWeather
        self.weather.isHidden = true

        // The layers sheet and the location button are what riders reach for most;
        // the forecast is first to fold into the overflow menu.
        if #available(iOS 27.0, *) {
            self.weather.visibilityPriority = .low
            self.mapLayers.visibilityPriority = .high
        }
    }

    private let showsWeather: Bool

    /// In display order, top to bottom. Hidden items stay in the array; UIKit skips them.
    var items: [UIBarButtonItem] {
        showsWeather ? [location, mapLayers, weather, myTrip] : [location, mapLayers, myTrip]
    }

    /// An item that forwards to `button`'s own action, so the hover bar and the
    /// toolbar share one implementation of each control.
    private static func item(mirroring button: UIButton) -> UIBarButtonItem {
        let action = UIAction(title: button.accessibilityLabel ?? "") { [weak button] _ in
            button?.sendActions(for: .touchUpInside)
        }
        let item = UIBarButtonItem(primaryAction: action)
        item.image = button.image(for: .normal)
        item.accessibilityLabel = button.accessibilityLabel
        return item
    }

    // MARK: - State

    func setLocationAvailable(_ available: Bool) {
        location.isHidden = !available
    }

    func updateMapLayers(image: UIImage?, accessibilityValue: String?, layerCount: Int) {
        mapLayers.image = image
        mapLayers.accessibilityValue = accessibilityValue
        if #available(iOS 26.0, *) {
            if layerCount > 0 {
                var badge = UIBarButtonItem.Badge.count(layerCount)
                badge.backgroundColor = ThemeColors.shared.brand
                badge.foregroundColor = MapTypeButtonPresentation.badgeTextColor
                mapLayers.badge = badge
            } else {
                mapLayers.badge = nil
            }
        }
    }

    private var renderedWeather: (symbolName: String, temperature: String?)?

    /// Vertically only the image shows, so the temperature is drawn into it.
    func updateWeather(symbolName: String?, temperature: String?, accessibilityValue: String?) {
        weather.isHidden = symbolName == nil
        weather.accessibilityValue = accessibilityValue
        guard let symbolName, let symbol = UIImage(systemName: symbolName) else {
            renderedWeather = nil
            weather.image = nil
            return
        }
        if let renderedWeather, renderedWeather.symbolName == symbolName, renderedWeather.temperature == temperature { return }
        renderedWeather = (symbolName, temperature)
        weather.image = Self.weatherImage(symbol: symbol, temperature: temperature)
    }

    /// The condition symbol over the temperature, as one template image, to match
    /// the hover bar's stacked button.
    static func weatherImage(symbol: UIImage, temperature: String?) -> UIImage {
        guard let temperature, !temperature.isEmpty else { return symbol }

        let symbolSize = CGSize(width: 22, height: 17)
        let font = UIFont.systemFont(ofSize: 11, weight: .bold)
        let text = NSAttributedString(string: temperature, attributes: [.font: font, .foregroundColor: UIColor.black])
        let textSize = text.size()
        let spacing: CGFloat = 1
        let size = CGSize(
            width: ceil(max(symbolSize.width, textSize.width)),
            height: ceil(symbolSize.height + spacing + textSize.height)
        )

        let image = UIGraphicsImageRenderer(size: size).image { _ in
            let fitted = aspectFit(aspectRatio: symbol.size, insideRect: CGRect(
                x: (size.width - symbolSize.width) / 2, y: 0,
                width: symbolSize.width, height: symbolSize.height
            ))
            symbol.withTintColor(.black, renderingMode: .alwaysOriginal).draw(in: fitted)
            text.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: symbolSize.height + spacing))
        }
        return image.withRenderingMode(.alwaysTemplate)
    }
}

/// `AVMakeRect(aspectRatio:insideRect:)`, without importing AVFoundation for it.
private func aspectFit(aspectRatio: CGSize, insideRect rect: CGRect) -> CGRect {
    guard aspectRatio.width > 0, aspectRatio.height > 0 else { return rect }
    let scale = min(rect.width / aspectRatio.width, rect.height / aspectRatio.height)
    let size = CGSize(width: aspectRatio.width * scale, height: aspectRatio.height * scale)
    return CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
}
