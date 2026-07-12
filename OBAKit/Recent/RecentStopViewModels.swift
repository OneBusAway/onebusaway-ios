//
//  RecentStopRowItems.swift
//  OBAKit
//
//  Created by Alan Chu on 11/3/20.
//

import OBAKitCore

/// A view model for use with OBAListView for displaying basic stop details.
///
/// This model uses a default content configuration, there is no need to register this
/// item with OBAListView before use.
struct StopRowItem: OBAListViewItem {
    let name: String
    let subtitle: String?

    let id: UUID = UUID()
    let stopID: Stop.ID
    let routeType: Route.RouteType

    var configuration: OBAListViewItemConfiguration {
        var config = OBAListRowConfiguration(
            image: Self.squircleTransportIcon(for: routeType),
            text: .attributed(styledTitle),
            secondaryText: .attributed(styledSubtitle),
            appearance: .subtitle,
            accessoryType: .disclosureIndicator)
        // The squircle icon is pre-rendered with its own colors; don't re-tint.
        config.imageConfig.tintColor = nil
        config.imageConfig.maximumSize = CGSize(width: Self.iconSize, height: Self.iconSize)

        return .custom(config)
    }

    private var styledTitle: NSAttributedString {
        NSAttributedString(string: name, attributes: [
            .font: UIFont.preferredFont(forTextStyle: .headline),
            .foregroundColor: UIColor.label
        ])
    }

    private var styledSubtitle: NSAttributedString? {
        guard let subtitle else { return nil }
        return NSAttributedString(string: subtitle, attributes: [
            .font: UIFont.preferredFont(forTextStyle: .body),
            .foregroundColor: UIColor.label
        ])
    }

    // MARK: - Squircle icon

    private static let iconSize: CGFloat = 40
    private static var iconCache = [Route.RouteType: UIImage]()

    /// The transport glyph in white over a brand-color gradient squircle,
    /// echoing the stop page's `RouteBadgeView` treatment.
    private static func squircleTransportIcon(for routeType: Route.RouteType) -> UIImage {
        if let cached = iconCache[routeType] { return cached }

        let rect = CGRect(x: 0, y: 0, width: iconSize, height: iconSize)
        let image = UIGraphicsImageRenderer(bounds: rect).image { context in
            let brand = ThemeColors.shared.brand
            UIBezierPath(roundedRect: rect, cornerRadius: iconSize * 0.28).addClip()

            let colors = [
                brand.blended(with: .white, amount: 0.18).cgColor,
                brand.blended(with: .black, amount: 0.12).cgColor
            ]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1]) {
                context.cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: rect.midX, y: rect.minY),
                    end: CGPoint(x: rect.midX, y: rect.maxY),
                    options: [])
            } else {
                brand.setFill()
                context.fill(rect)
            }

            let glyph = Icons.transportIcon(from: routeType).withTintColor(.white, renderingMode: .alwaysOriginal)
            let maxGlyphExtent = iconSize * 0.55
            let scale = min(maxGlyphExtent / glyph.size.width, maxGlyphExtent / glyph.size.height)
            let glyphSize = CGSize(width: glyph.size.width * scale, height: glyph.size.height * scale)
            glyph.draw(in: CGRect(
                x: rect.midX - glyphSize.width / 2.0,
                y: rect.midY - glyphSize.height / 2.0,
                width: glyphSize.width,
                height: glyphSize.height))
        }.withRenderingMode(.alwaysOriginal)

        iconCache[routeType] = image
        return image
    }

    let onSelectAction: OBAListViewAction<StopRowItem>?
    let onDeleteAction: OBAListViewAction<StopRowItem>?

    init(withStop stop: Stop,
         showDirectionInTitle: Bool = false,
         onSelect selectAction: OBAListViewAction<StopRowItem>?,
         onDelete deleteAction: OBAListViewAction<StopRowItem>?) {

        self.name = showDirectionInTitle ? stop.nameWithLocalizedDirectionAbbreviation : stop.name
        self.subtitle = stop.subtitle
        self.routeType = stop.prioritizedRouteTypeForDisplay

        self.stopID = stop.id
        self.onSelectAction = selectAction
        self.onDeleteAction = deleteAction
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(stopID)
        hasher.combine(name)
        hasher.combine(routeType)
    }

    static func == (lhs: StopRowItem, rhs: StopRowItem) -> Bool {
        return lhs.id == rhs.id &&
            lhs.stopID == rhs.stopID &&
            lhs.name == rhs.name &&
            lhs.routeType == rhs.routeType
    }
}

private extension UIColor {
    /// Linear blend toward `other` in RGB space; `amount` is clamped to 0...1.
    func blended(with other: UIColor, amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = max(0, min(1, amount))
        return UIColor(
            red: r1 + (r2 - r1) * t,
            green: g1 + (g2 - g1) * t,
            blue: b1 + (b2 - b1) * t,
            alpha: a1)
    }
}

extension RecentStopsViewController {
    struct AlarmViewModel: OBAListViewItem {
        let alarm: Alarm
        let deepLink: ArrivalDepartureDeepLink

        let title: String

        var id: URL { alarm.url }

        var configuration: OBAListViewItemConfiguration {
            return .custom(OBAListRowConfiguration(
                            text: .string(title),
                            appearance: .subtitle,
                            accessoryType: .disclosureIndicator))
        }

        let onSelectAction: OBAListViewAction<AlarmViewModel>?
        let onDeleteAction: OBAListViewAction<AlarmViewModel>?

        init?(withAlarm alarm: Alarm,
              onSelect selectAction: OBAListViewAction<AlarmViewModel>?,
              onDelete deleteAction: OBAListViewAction<AlarmViewModel>?) {
            guard let deepLink = alarm.deepLink else { return nil }
            self.alarm = alarm
            self.deepLink = deepLink
            self.title = deepLink.title

            self.onSelectAction = selectAction
            self.onDeleteAction = deleteAction
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
            hasher.combine(title)
            alarm.hash(into: &hasher)
            deepLink.hash(into: &hasher)
        }

        static func == (lhs: AlarmViewModel, rhs: AlarmViewModel) -> Bool {
            return lhs.alarm.isEqual(rhs.alarm) &&
                lhs.deepLink.isEqual(rhs.deepLink) &&
                lhs.title == rhs.title
        }
    }
}
