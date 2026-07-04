//
//  WeatherDetailPopup.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// In-SwiftUI weather card for `MapPanelRootView`'s overlay layer. Lives outside
/// any UIKit modal hierarchy so it can coexist with the persistent floating sheet.
/// Dismisses via backdrop tap or the floating close button; card body is
/// interactive (the hourly strip scrolls) and never dismisses on tap.
///
/// `display` is read straight from the view model rather than a captured
/// snapshot, so a refresh that lands while the popup is open updates the card
/// under the user instead of stranding them on a frozen forecast. `isPresented`
/// is the dismissal channel — the popup never mutates the underlying data.
struct WeatherDetailPopup: View {
    let display: WeatherDisplay?
    @Binding var isPresented: Bool
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private let cardShape = RoundedRectangle(cornerRadius: 24, style: .continuous)

    /// `HStack` in iPhone landscape (where the floating sheet covers the bottom
    /// of the screen and a button parked below the card would be hidden);
    /// `VStack` otherwise. Switching via `AnyLayout` keeps the subview list
    /// identical so SwiftUI animates between the two arrangements.
    private var stackLayout: AnyLayout {
        verticalSizeClass == .compact
            ? AnyLayout(HStackLayout(alignment: .center, spacing: 16))
            : AnyLayout(VStackLayout(spacing: 16))
    }

    /// True only when there's something to render. If the VM drops weather
    /// data (e.g. region change) while the popup is open, this collapses to
    /// false so the dismiss animation runs and `isPresented` is reset.
    private var isShowing: Bool { isPresented && display != nil }

    var body: some View {
        ZStack {
            if let current = display, isPresented {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { dismiss() }

                stackLayout {
                    WeatherCard(display: current, shape: cardShape)
                    closeButton
                }
                .frame(maxWidth: 500)
                .padding(.horizontal, 16)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.25), value: isShowing)
        .onChange(of: display) { _, newValue in
            // Reset the presentation flag if the underlying data disappeared
            // (e.g. user crossed a region boundary while the popup was open).
            if newValue == nil && isPresented {
                isPresented = false
            }
        }
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(Strings.close))
        .background(.ultraThinMaterial, in: Circle())
        .clearGlassEffectIfAvailable(in: Circle())
    }

    private func dismiss() {
        isPresented = false
    }
}

// MARK: - Card

private struct WeatherCard: View {
    let display: WeatherDisplay
    let shape: RoundedRectangle

    var body: some View {
        VStack(spacing: 0) {
            HeaderRow(header: display.header)
                .padding(16)

            Divider()

            HourlyStrip(entries: display.hourly)
                .padding(.vertical, 12)

            Divider()

            StatsRow(stats: display.stats)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .background(.ultraThinMaterial, in: shape)
        .clearGlassEffectIfAvailable(in: shape)
    }
}

// MARK: - Header

private struct HeaderRow: View {
    let header: WeatherDisplay.Header

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            WeatherIcon(iconName: header.iconName, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(header.regionName)
                    .font(.title3.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(header.conditionSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(header.chanceOfRainText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(header.currentTemp)
                    .font(.system(size: 34, weight: .semibold))
                if let hilo = header.highLowText {
                    Text(hilo)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Hourly Strip

private struct HourlyStrip: View {
    let entries: [HourlyEntry]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 18) {
                ForEach(entries) { entry in
                    HourlyCell(entry: entry)
                }
            }
            .padding(.horizontal, 16)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct HourlyCell: View {
    let entry: HourlyEntry

    var body: some View {
        VStack(spacing: 6) {
            Text(entry.timeLabel)
                .font(.caption)
                .fontWeight(entry.isNow ? .bold : .regular)
                .foregroundStyle(entry.isNow ? .primary : .secondary)
            WeatherIcon(iconName: entry.iconName, size: 22)
            Text(entry.temp)
                .font(.subheadline)
                .fontWeight(entry.isNow ? .bold : .regular)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Stats Row

private struct StatsRow: View {
    let stats: WeatherDisplay.Stats

    var body: some View {
        HStack {
            stat(
                systemImage: "wind",
                tint: .secondary,
                value: stats.windText,
                label: OBALoc("weather.stat.wind", value: "Wind speed", comment: "VoiceOver label for the wind speed stat on the weather card.")
            )
            Spacer()
            stat(
                systemImage: "drop.fill",
                tint: .blue,
                value: stats.precipText,
                label: OBALoc("weather.stat.precip", value: "Chance of precipitation", comment: "VoiceOver label for the precipitation chance stat on the weather card.")
            )
            Spacer()
            stat(
                systemImage: "thermometer.medium",
                tint: .red,
                value: stats.feelsLikeText,
                label: OBALoc("weather.stat.feels_like", value: "Feels like", comment: "VoiceOver label for the feels-like temperature stat on the weather card.")
            )
        }
    }

    private func stat(systemImage: String, tint: Color, value: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(value)
                .font(.subheadline)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(label): \(value)"))
    }
}

// MARK: - Weather Icon

/// Pulls the SF Symbol name from `WeatherFormatter` (single source of truth) and
/// pairs it with a SwiftUI-only color palette. The palette lives here rather
/// than in OBAKitCore because `Color` isn't reachable from the extension-safe
/// core; `WeatherIconPalette.colors` is `internal` so tests can assert every
/// key in `WeatherFormatter.knownIconKeys` also has a palette entry.
private struct WeatherIcon: View {
    let iconName: String
    let size: CGFloat

    var body: some View {
        let symbol = WeatherFormatter.systemImageName(for: iconName)
        let palette = WeatherIconPalette.colors[iconName] ?? (.gray, .clear)
        Image(systemName: symbol)
            .symbolRenderingMode(.palette)
            .foregroundStyle(palette.primary, palette.secondary)
            .font(.system(size: size))
    }
}

enum WeatherIconPalette {
    static let colors: [String: (primary: Color, secondary: Color)] = [
        "clear-day": (.yellow, .orange),
        "clear-night": (.gray, .yellow),
        "partly-cloudy-day": (.yellow, .gray),
        "partly-cloudy-night": (.gray, .yellow),
        "cloudy": (.gray, .secondary),
        "rain": (.gray, .blue),
        "sleet": (.gray, .blue),
        "snow": (.gray, .white),
        "wind": (.gray, .clear),
        "fog": (.gray, .secondary)
    ]
}
