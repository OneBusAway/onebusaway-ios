//
//  ListRow.swift
//  OBAKit
//

import SwiftUI
import OBAKitCore


// MARK: - ListRow

/// A flexible list row supporting a title, optional subtitle, optional trailing value,
/// an optional leading image, and a trailing accessory.
public struct ListRow: View {

    private let title: String
    private let subtitle: String?
    private let value: String?
    private let image: Image?
    private let titleFont: Font?
    private let titleColor: Color?
    private let subtitleFont: Font?
    private let subtitleColor: Color?
    private let valueFont: Font?
    private let valueColor: Color?
    private let imageConfiguration: ListRowImageConfiguration
    private let accessory: ListRowAccessory

    @Environment(\.listRowStyle) private var rowStyle

    // MARK: Init

    public init(
        title: String,
        subtitle: String? = nil,
        value: String? = nil,
        image: Image? = nil,
        titleFont: Font? = nil,
        titleColor: Color? = nil,
        subtitleFont: Font? = nil,
        subtitleColor: Color? = nil,
        valueFont: Font? = nil,
        valueColor: Color? = nil,
        imageConfiguration: ListRowImageConfiguration = .default,
        accessory: ListRowAccessory = .none
    ) {
        self.title = title
        self.subtitle = subtitle
        self.value = value
        self.image = image
        self.titleFont = titleFont
        self.titleColor = titleColor
        self.subtitleFont = subtitleFont
        self.subtitleColor = subtitleColor
        self.valueFont = valueFont
        self.valueColor = valueColor
        self.imageConfiguration = imageConfiguration
        self.accessory = accessory
    }

    // MARK: Body

    public var body: some View {
        HStack(spacing: 12) {
            imageView

            leadingContent
            Spacer(minLength: 0)
            trailingContent

            accessory
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Private Views

    @ViewBuilder
    private var leadingContent: some View {
        if let subtitle {
            VStack(alignment: .leading, spacing: 2) {
                titleText
                Text(subtitle)
                    .font(subtitleFont ?? rowStyle.subtitleFont)
                    .foregroundStyle(subtitleColor ?? rowStyle.subtitleColor)
            }
        } else {
            titleText
        }
    }

    private var titleText: some View {
        Text(title)
            .font(titleFont ?? rowStyle.titleFont)
            .foregroundStyle(titleColor ?? rowStyle.titleColor)
    }

    @ViewBuilder
    private var trailingContent: some View {
        if let value {
            Text(value)
                .font(valueFont ?? rowStyle.valueFont)
                .foregroundStyle(valueColor ?? rowStyle.valueColor)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var imageView: some View {
        if let image {
            image
                .renderingMode(imageConfiguration.renderingMode)
                .foregroundStyle(imageConfiguration.color)
                .font(imageConfiguration.font)
        }
    }
}
