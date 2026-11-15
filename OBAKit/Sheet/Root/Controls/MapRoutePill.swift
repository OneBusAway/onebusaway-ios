//
//  MapRoutePill.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import UIKit
import OBAKitCore

/// A stop's route numbers on the panel map: one pill per stop, split into a
/// segment per route by hairlines, e.g. `65 | 75 | 372 | +2`.
///
/// Accessibility: VoiceOver should skip the pill, because the pin's label
/// already reads the stop's full route list, not just what fits here. The
/// annotation that contains it does that (`accessibilityElement(children:
/// .ignore)`); hiding the pill itself didn't work inside a map annotation.
/// Text follows Dynamic Type up to xLarge and then stops growing, so labels
/// can't cover the map; Increase Contrast darkens the ring and dividers.
/// Nothing is conveyed by color alone.
struct MapRoutePill: View {
    let label: MapRouteLabel

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.displayScale) private var displayScale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The largest Dynamic Type size the pill grows to.
    static let maximumDynamicTypeSize = DynamicTypeSize.xLarge
    static let horizontalPadding: CGFloat = 6
    static let verticalPadding: CGFloat = 2
    static let cornerRadius: CGFloat = 5

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(label.segments.enumerated()), id: \.offset) { index, segment in
                Text(verbatim: segment)
                    .padding(.horizontal, Self.horizontalPadding)
                    .padding(.vertical, Self.verticalPadding)
                    .foregroundStyle(isOverflow(index) ? Color(uiColor: .secondaryLabel) : Color(uiColor: .label))
                    .background(isOverflow(index) ? Color(uiColor: .tertiarySystemFill) : .clear)
                    // The divider overlays the segment's leading edge rather
                    // than sitting between segments, so it takes its height
                    // from the text and adds no width.
                    .overlay(alignment: .leading) {
                        if index > 0 {
                            Rectangle()
                                .fill(dividerColor)
                                .frame(width: hairline)
                        }
                    }
            }
        }
        .fixedSize()
        .font(Font(Self.font(for: dynamicTypeSize)))
        .lineLimit(1)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(ringColor, lineWidth: hairline)
        }
        .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
    }

    private func isOverflow(_ index: Int) -> Bool {
        label.overflowText != nil && index == label.segments.count - 1
    }

    private var hairline: CGFloat { max(1 / displayScale, 0.5) }

    private var ringColor: Color {
        Color(uiColor: .label).opacity(contrast == .increased ? 0.55 : 0.16)
    }

    private var dividerColor: Color {
        Color(uiColor: .label).opacity(contrast == .increased ? 0.45 : 0.14)
    }

    // MARK: - Size estimate

    /// The pill's size, measured with the same font and padding as `body`, for
    /// label placement. Placement runs once per camera settle, before the pills
    /// lay out, so it can't wait for SwiftUI to measure them.
    static func estimatedSize(for label: MapRouteLabel, dynamicTypeSize: DynamicTypeSize) -> CGSize {
        let font = font(for: dynamicTypeSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let textWidth = label.segments.reduce(CGFloat(0)) { total, segment in
            total + ceil((segment as NSString).size(withAttributes: attributes).width)
        }
        let segmentCount = CGFloat(label.segments.count)
        let width = textWidth + segmentCount * horizontalPadding * 2
        let height = ceil(font.lineHeight) + verticalPadding * 2
        return CGSize(width: width, height: height)
    }

    /// Built fonts by Dynamic Type size, since layout measures every pill.
    @MainActor private static var fontCache: [DynamicTypeSize: UIFont] = [:]

    /// The pill's one font: caption-sized bold with monospaced digits, capped
    /// at `maximumDynamicTypeSize`. Both `body` and `estimatedSize` use it, so
    /// drawing and measuring can't drift apart.
    static func font(for dynamicTypeSize: DynamicTypeSize) -> UIFont {
        let size = min(dynamicTypeSize, maximumDynamicTypeSize)
        if let cached = fontCache[size] { return cached }
        let font = makeFont(for: size)
        fontCache[size] = font
        return font
    }

    private static func makeFont(for dynamicTypeSize: DynamicTypeSize) -> UIFont {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
        let base = UIFont.preferredFont(forTextStyle: .caption1, compatibleWith: traits)
        let bold = UIFont.systemFont(ofSize: base.pointSize, weight: .bold)
        let monospaced = bold.fontDescriptor.addingAttributes([
            .featureSettings: [[
                UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector
            ]]
        ])
        return UIFont(descriptor: monospaced, size: base.pointSize)
    }
}

#Preview("Route pills") {
    VStack(spacing: 12) {
        MapRoutePill(label: MapRouteLabel(routeNames: ["65", "75", "372"], overflowCount: 2))
        MapRoutePill(label: MapRouteLabel(routeNames: ["65", "372"], overflowCount: 0))
        MapRoutePill(label: MapRouteLabel(routeNames: ["1 Line"], overflowCount: 0))
    }
    .padding()
    .background(Color(uiColor: .systemGray5))
}

// MARK: - Placing a label beside a pin

extension View {
    /// Puts `label` on one side of this pin, `gap` points from its edge,
    /// without changing the pin's own frame (so the map still anchors the pin's
    /// center on the stop's coordinate).
    ///
    /// The sides are screen sides. Leading/trailing alignment flips in
    /// right-to-left layouts, so the placement is done left-to-right and
    /// `contentLayoutDirection` is put back for the label's own contents.
    @ViewBuilder
    func mapPinLabel<Label: View>(
        placement: MapStopLabelPlacement,
        gap: CGFloat = MapStopLabelLayout.gap,
        contentLayoutDirection: LayoutDirection,
        @ViewBuilder label: () -> Label
    ) -> some View {
        if let edges = MapPinLabelEdges(placement) {
            overlay(alignment: edges.pinEdge) {
                label()
                    .environment(\.layoutDirection, contentLayoutDirection)
                    .fixedSize()
                    .frame(
                        width: edges.isVertical ? nil : 0,
                        height: edges.isVertical ? 0 : nil,
                        alignment: edges.labelEdge
                    )
                    .offset(x: edges.direction.width * gap, y: edges.direction.height * gap)
            }
            .environment(\.layoutDirection, .leftToRight)
        } else {
            self
        }
    }
}

/// How `mapPinLabel` hangs a label off a pin: it aligns a zero-size frame to
/// one edge of the pin, lets the label hang off that frame away from the pin,
/// and nudges it out by the gap. (Custom alignment guides on the label were
/// ignored inside a map annotation, leaving labels on top of their pins.)
private struct MapPinLabelEdges {
    /// The pin edge the label sits against.
    let pinEdge: Alignment
    /// The label edge that touches it.
    let labelEdge: Alignment
    /// Unit vector pointing away from the pin.
    let direction: CGSize

    var isVertical: Bool { direction.width == 0 }

    /// `nil` for `.hidden`.
    init?(_ placement: MapStopLabelPlacement) {
        switch placement {
        case .below: (pinEdge, labelEdge, direction) = (.bottom, .top, CGSize(width: 0, height: 1))
        case .above: (pinEdge, labelEdge, direction) = (.top, .bottom, CGSize(width: 0, height: -1))
        case .left: (pinEdge, labelEdge, direction) = (.leading, .trailing, CGSize(width: -1, height: 0))
        case .right: (pinEdge, labelEdge, direction) = (.trailing, .leading, CGSize(width: 1, height: 0))
        case .hidden: return nil
        }
    }
}
