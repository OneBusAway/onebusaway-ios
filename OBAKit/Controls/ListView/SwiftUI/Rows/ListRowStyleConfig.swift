//
//  ListRowStyleValues.swift
//  OBAKit
//
//  Created by Mohamed Sliem on 07/05/2026.
//


// MARK: - ListRowStyleValues

public struct ListRowStyleValues {
    public var titleFont: Font = .body
    public var titleColor: Color = .primary
    public var subtitleFont: Font = .footnote
    public var subtitleColor: Color = .secondary
    public var valueFont: Font = .body
    public var valueColor: Color = .secondary

    public init(
        titleFont: Font = .body,
        titleColor: Color = .primary,
        subtitleFont: Font = .footnote,
        subtitleColor: Color = .secondary,
        valueFont: Font = .body,
        valueColor: Color = .secondary
    ) {
        self.titleFont = titleFont
        self.titleColor = titleColor
        self.subtitleFont = subtitleFont
        self.subtitleColor = subtitleColor
        self.valueFont = valueFont
        self.valueColor = valueColor
    }
}

extension EnvironmentValues {
    @Entry var listRowStyle: ListRowStyleValues = ListRowStyleValues()
}

extension View {
    /// Sets all row style values at once for all descendant list rows.
    public func rowStyle(_ values: ListRowStyleValues) -> some View {
        environment(\.listRowStyle, values)
    }
}

// MARK: - ListRowImageConfiguration
public struct ListRowImageConfiguration {
    /// Tint color applied to the image.
    public var color: Color
    /// Font used to scale SF Symbols. `nil` inherits from the surrounding context.
    public var font: Font?
    /// Rendering mode. `nil` defers to the image's own rendering mode.
    public var renderingMode: Image.TemplateRenderingMode?

    /// Default configuration: secondary color, no size override, automatic rendering.
    public static let `default` = ListRowImageConfiguration()

    public init(
        color: Color = .secondary,
        font: Font? = nil,
        renderingMode: Image.TemplateRenderingMode? = nil
    ) {
        self.color = color
        self.font = font
        self.renderingMode = renderingMode
    }
}

// MARK: - ListRowAccessory

/// Trailing accessory decoration for built-in list rows.
public enum ListRowAccessory {
    case none
    case disclosureIndicator
    case checkmark
}

extension ListRowAccessory: View {
    @ViewBuilder
    public var body: some View {
        switch self {
        case .none:
            EmptyView()
        case .disclosureIndicator:
            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color(ThemeColors.shared.brand))
                .accessibilityHidden(true)
        case .checkmark:
            Image(systemName: "checkmark")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
        }
    }
}
