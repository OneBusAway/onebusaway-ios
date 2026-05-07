//
//  ListRow.swift
//  OBAKit
//

import SwiftUI
import OBAKitCore

// MARK: - ListRowStyleValues

/// Environment-delivered style defaults for built-in list rows.
///
/// Set once on a container — all descendant rows inherit the values automatically.
/// Per-row `Font?` / `Color?` parameters take precedence over environment defaults.
///
///     ListView { ... }
///         .rowTitleFont(.headline)
///         .rowSubtitleColor(.blue)
///
public struct ListRowStyleValues {
    public var titleFont: Font = .body
    public var titleColor: Color = .primary
    public var subtitleFont: Font = .footnote
    public var subtitleColor: Color = .secondary
    public var valueFont: Font = .body
    public var valueColor: Color = .secondary

    public init() {}
}

private struct ListRowStyleKey: EnvironmentKey {
    static let defaultValue = ListRowStyleValues()
}

extension EnvironmentValues {
    var listRowStyle: ListRowStyleValues {
        get { self[ListRowStyleKey.self] }
        set { self[ListRowStyleKey.self] = newValue }
    }
}

extension View {
    /// Sets the title font for all descendant list rows that inherit environment style.
    public func rowTitleFont(_ font: Font) -> some View {
        transformEnvironment(\.listRowStyle) { $0.titleFont = font }
    }

    /// Sets the title foreground color for all descendant list rows that inherit environment style.
    public func rowTitleColor(_ color: Color) -> some View {
        transformEnvironment(\.listRowStyle) { $0.titleColor = color }
    }

    /// Sets the subtitle font for all descendant list rows that inherit environment style.
    public func rowSubtitleFont(_ font: Font) -> some View {
        transformEnvironment(\.listRowStyle) { $0.subtitleFont = font }
    }

    /// Sets the subtitle foreground color for all descendant list rows that inherit environment style.
    public func rowSubtitleColor(_ color: Color) -> some View {
        transformEnvironment(\.listRowStyle) { $0.subtitleColor = color }
    }

    /// Sets the value font for all descendant list rows that inherit environment style.
    public func rowValueFont(_ font: Font) -> some View {
        transformEnvironment(\.listRowStyle) { $0.valueFont = font }
    }

    /// Sets the value foreground color for all descendant list rows that inherit environment style.
    public func rowValueColor(_ color: Color) -> some View {
        transformEnvironment(\.listRowStyle) { $0.valueColor = color }
    }
}

// MARK: - ListRowImageConfiguration

/// Controls how a leading image is displayed in a list row.
///
///     // Tinted SF Symbol at a custom size
///     ListRowImageConfiguration(color: .accentColor, font: .title2)
///
///     // Force template rendering so `color` always applies
///     ListRowImageConfiguration(color: .orange, renderingMode: .template)
///
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
        case .checkmark:
            Image(systemName: "checkmark")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tint)
        }
    }
}

// MARK: - OBAListAction

/// A value type describing a single user-initiated action on a list item
/// (tap, swipe button, or context menu entry).
///
///     OBAListAction(title: "Bookmark", image: Image(systemName: "bookmark"), tintColor: .orange) {
///         bookmark(stop)
///     }
///
public struct OBAListAction: Identifiable {

    // MARK: Stored Properties

    public let id = UUID()
    public let title: String
    public let image: Image?
    public let role: ButtonRole?
    public let tintColor: Color?
    public let handler: () -> Void

    // MARK: Init

    public init(
        title: String,
        image: Image? = nil,
        role: ButtonRole? = nil,
        tintColor: Color? = nil,
        handler: @escaping () -> Void
    ) {
        self.title = title
        self.image = image
        self.role = role
        self.tintColor = tintColor
        self.handler = handler
    }
}

// MARK: - OBAListElement

/// A protocol for view models that want automatic action wiring via `.obaItemActions(for:)`.
///
/// Conforming types declare their tap, swipe, and context-menu actions as data. The
/// `OBAItemActionModifier` translates them into native SwiftUI modifiers at render time.
///
///     struct RouteViewModel: OBAListElement {
///         let id: String
///         let name: String
///         var trailingSwipeActions: [OBAListAction] {
///             [OBAListAction(title: "Delete", role: .destructive) { delete(self) }]
///         }
///     }
///
public protocol OBAListElement: Identifiable {
    var onTapAction: (() -> Void)? { get }
    var leadingSwipeActions: [OBAListAction] { get }
    var trailingSwipeActions: [OBAListAction] { get }
    var contextMenuActions: [OBAListAction] { get }
}

public extension OBAListElement {
    var onTapAction: (() -> Void)? { nil }
    var leadingSwipeActions: [OBAListAction] { [] }
    var trailingSwipeActions: [OBAListAction] { [] }
    var contextMenuActions: [OBAListAction] { [] }
}

// MARK: - ListRowLayout

/// Shared HStack container used by all built-in row types.
///
/// Handles the leading image (via `ListRowImageConfiguration`) and trailing accessory.
/// Callers provide the middle content — including any `Spacer` needed for alignment.
///
/// Exposed as `public` so that custom row views can reuse the same image/accessory chrome:
///
///     struct ArrivalDepartureRow: View {
///         var body: some View {
///             ListRowLayout(image: nil, imageConfiguration: .default, accessory: .disclosureIndicator) {
///                 VStack(alignment: .leading) { ... }
///                 Spacer(minLength: 0)
///             }
///         }
///     }
///
public struct ListRowLayout<TextContent: View>: View {

    // MARK: Stored Properties

    let image: Image?
    let imageConfiguration: ListRowImageConfiguration
    let accessory: ListRowAccessory
    let textContent: TextContent

    // MARK: Init

    public init(
        image: Image?,
        imageConfiguration: ListRowImageConfiguration,
        accessory: ListRowAccessory,
        @ViewBuilder textContent: () -> TextContent
    ) {
        self.image = image
        self.imageConfiguration = imageConfiguration
        self.accessory = accessory
        self.textContent = textContent()
    }

    // MARK: Body

    public var body: some View {
        HStack(spacing: 12) {
            imageView
            textContent
            accessory
        }
    }

    // MARK: Private Views

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

// MARK: - ListRow

/// A single-line list row with a title, optional leading image, and trailing accessory.
///
/// Mirrors `OBAListRowView.DefaultViewModel`.
///
/// Font and color default to environment values set via `.rowTitleFont(_:)` /
/// `.rowTitleColor(_:)`. Pass explicit values to override per row:
///
///     ListRow(title: "Route 5")
///
///     ListRow(
///         title: "Agency",
///         image: Image(systemName: "bus"),
///         titleFont: .headline,
///         imageConfiguration: ListRowImageConfiguration(color: .accentColor, font: .title3),
///         accessory: .disclosureIndicator
///     )
public struct ListRow: View {

    // MARK: Stored Properties

    private let title: String
    private let image: Image?
    private let titleFont: Font?
    private let titleColor: Color?
    private let imageConfiguration: ListRowImageConfiguration
    private let accessory: ListRowAccessory

    // MARK: Environment

    @Environment(\.listRowStyle) private var rowStyle

    // MARK: Init

    public init(
        title: String,
        image: Image? = nil,
        titleFont: Font? = nil,
        titleColor: Color? = nil,
        imageConfiguration: ListRowImageConfiguration = .default,
        accessory: ListRowAccessory = .disclosureIndicator
    ) {
        self.title = title
        self.image = image
        self.titleFont = titleFont
        self.titleColor = titleColor
        self.imageConfiguration = imageConfiguration
        self.accessory = accessory
    }

    // MARK: Body

    public var body: some View {
        ListRowLayout(image: image, imageConfiguration: imageConfiguration, accessory: accessory) {
            Text(title)
                .font(titleFont ?? rowStyle.titleFont)
                .foregroundStyle(titleColor ?? rowStyle.titleColor)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Previews

#Preview {
    List {
        ListRow(title: "Default row")
        ListRow(title: "With image", image: Image(systemName: "bus"))
        ListRow(title: "Custom font & color", titleFont: .headline, titleColor: .accentColor)
        ListRow(
            title: "Custom image config",
            image: Image(systemName: "star.fill"),
            imageConfiguration: ListRowImageConfiguration(color: .orange, font: .title3)
        )
        ListRow(title: "Checkmark", accessory: .checkmark)
        ListRow(title: "No accessory", accessory: .none)
    }
}

#Preview("Environment style") {
    List {
        ListRow(title: "Inherits headline font")
        ListRow(title: "Per-row override", titleFont: .caption, titleColor: .secondary)
    }
    .rowTitleFont(.headline)
}
