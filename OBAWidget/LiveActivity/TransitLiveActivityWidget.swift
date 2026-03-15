//
//  TransitLiveActivityWidget.swift
//  OBAWidget
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import ActivityKit
import OBAKitCore
import SwiftUI
import WidgetKit

// MARK: - Widget

@available(iOS 16.2, *)
struct TransitLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TransitArrivalAttributes.self) { context in
            LockScreenBanner(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color(.systemBackground))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    DILeading(attributes: context.attributes, state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    DITrailing(state: context.state)
                }
                DynamicIslandExpandedRegion(.center) {
                    DICenter(attributes: context.attributes, state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    DIBottom(attributes: context.attributes, state: context.state)
                }
            } compactLeading: {
                DICompactLeading(attributes: context.attributes, state: context.state)
            } compactTrailing: {
                DICompactTrailing(state: context.state)
            } minimal: {
                DIMinimal(state: context.state)
            }
            .widgetURL(deepLinkURL(for: context.attributes))
        }
    }

    private func deepLinkURL(for attributes: TransitArrivalAttributes) -> URL {
        let router = URLSchemeRouter(scheme: Bundle.main.extensionURLScheme!)
        return router.encodeViewStop(stopID: attributes.stopID, regionID: attributes.regionIdentifier)
    }
}

// MARK: - Design Tokens

@available(iOS 16.2, *)
private extension ScheduleStatusState {
    var color: Color {
        switch self {
        case .onTime:  return Color(red: 0.13, green: 0.84, blue: 0.46)
        case .delayed: return Color(red: 1.00, green: 0.28, blue: 0.22)
        case .early:   return Color(red: 0.20, green: 0.60, blue: 1.00)
        case .unknown: return Color(white: 0.55)
        }
    }

    var label: String {
        switch self {
        case .onTime:  return "On Time"
        case .delayed: return "Delayed"
        case .early:   return "Early"
        case .unknown: return "Scheduled"
        }
    }

    var symbol: String {
        switch self {
        case .onTime:  return "checkmark.circle.fill"
        case .delayed: return "exclamationmark.circle.fill"
        case .early:   return "arrow.up.circle.fill"
        case .unknown: return "clock.fill"
        }
    }
}

// MARK: - Shared Atoms

/// Resizes a UIImage to the given pixel size.
private func resizeLogoImage(_ image: UIImage, to size: CGSize) -> UIImage? {
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { _ in
        image.draw(in: CGRect(origin: .zero, size: size))
    }
}

/// App logo badge — uses UIImage pre-resize pattern required for Live Activity rendering.
@available(iOS 16.2, *)
private struct AppIconBadge: View {
    var size: CGFloat = 22

    var body: some View {
        let screenScale = UIScreen.main.scale
        let targetSize = CGSize(width: size * screenScale, height: size * screenScale)

        if let raw = UIImage(named: "Logo"),
           let resized = resizeLogoImage(raw, to: targetSize),
           let cgImage = resized.cgImage {
            let displayImage = UIImage(cgImage: cgImage, scale: screenScale, orientation: .up)
            Image(uiImage: displayImage)
                .renderingMode(.original)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .fixedSize()
                .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
        } else {
            Image(systemName: "bus.fill")
                .font(.system(size: size * 0.55, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Color.green,
                            in: RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
        }
    }
}

/// Same logo for compact/minimal contexts.
@available(iOS 16.2, *)
private struct AppLogoMark: View {
    var size: CGFloat = 18
    var color: Color = .white

    var body: some View {
        let screenScale = UIScreen.main.scale
        let targetSize = CGSize(width: size * screenScale, height: size * screenScale)

        if let raw = UIImage(named: "Logo"),
           let resized = resizeLogoImage(raw, to: targetSize),
           let cgImage = resized.cgImage {
            let displayImage = UIImage(cgImage: cgImage, scale: screenScale, orientation: .up)
            Image(uiImage: displayImage)
                .renderingMode(.original)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .fixedSize()
                .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
        } else {
            Image(systemName: "bus.fill")
                .font(.system(size: size * 0.7, weight: .bold))
                .foregroundStyle(color)
                .frame(width: size, height: size)
        }
    }
}

@available(iOS 16.2, *)
private struct RoutePill: View {
    let route: String
    let status: ScheduleStatusState
    var fontSize: CGFloat = 13

    var body: some View {
        Text(route)
            .font(.system(size: fontSize, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, fontSize * 0.65)
            .padding(.vertical, fontSize * 0.28)
            .background(status.color, in: Capsule())
    }
}

/// Animated countdown — adapts to dark/light context.
@available(iOS 16.2, *)
private struct Countdown: View {
    let state: TransitArrivalAttributes.ContentState
    var numberSize: CGFloat = 34
    var unitSize: CGFloat = 13
    var onDark: Bool = false

    private var isUrgent: Bool { state.minutesUntilArrival >= 1 && state.minutesUntilArrival <= 2 }

    var body: some View {
        if state.minutesUntilArrival <= 0 {
            Text("NOW")
                .font(.system(size: numberSize * 0.72, weight: .black, design: .rounded))
                .foregroundStyle(state.scheduleStatus.color)
        } else {
            HStack(alignment: .lastTextBaseline, spacing: 1) {
                Text("\(state.minutesUntilArrival)")
                    .font(.system(size: numberSize, weight: .black, design: .rounded))
                    .foregroundStyle(isUrgent ? state.scheduleStatus.color : (onDark ? .white : Color.primary))
                    .contentTransition(.numericText(countsDown: true))
                Text("min")
                    .font(.system(size: unitSize, weight: .semibold))
                    .foregroundStyle(onDark ? Color.white.opacity(0.45) : Color.secondary)
            }
        }
    }
}

// MARK: - Progress Track

@available(iOS 16.2, *)
private struct ProgressTrack: View {
    let state: TransitArrivalAttributes.ContentState
    var height: CGFloat = 6
    var showMarker: Bool = true
    var onDark: Bool = false

    private let window: Double = 30

    private var fill: Double {
        guard state.minutesUntilArrival > 0 else { return 1 }
        return max(0.04, min(0.97, 1 - Double(state.minutesUntilArrival) / window))
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let trackColor = onDark ? Color.white.opacity(0.10) : Color.primary.opacity(0.08)

            ZStack(alignment: .leading) {
                // Track
                Capsule().fill(trackColor).frame(height: height)

                // Filled gradient
                Capsule()
                    .fill(LinearGradient(
                        colors: [state.scheduleStatus.color.opacity(0.55), state.scheduleStatus.color],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .frame(width: w * CGFloat(fill), height: height)
                    .shadow(color: state.scheduleStatus.color.opacity(0.45), radius: 3)
                    .animation(.easeInOut(duration: 0.5), value: fill)

                // Tick marks
                ForEach([0.25, 0.50, 0.75], id: \.self) { pct in
                    Capsule()
                        .fill(fill >= pct
                              ? Color.white.opacity(0.22)
                              : (onDark ? Color.white.opacity(0.15) : Color.primary.opacity(0.12)))
                        .frame(width: 1.5, height: height + 2)
                        .offset(x: w * CGFloat(pct) - 0.75)
                }

                // Bus marker
                if showMarker && fill < 0.97 {
                    Image(systemName: "bus.fill")
                        .font(.system(size: height + 4, weight: .bold))
                        .foregroundStyle(state.scheduleStatus.color)
                        .shadow(color: state.scheduleStatus.color.opacity(0.65), radius: 3)
                        .offset(x: max(0, w * CGFloat(fill) - (height + 4) / 2))
                        .animation(.easeInOut(duration: 0.5), value: fill)
                }

                // Destination pin
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: height + 5, weight: .semibold))
                    .foregroundStyle(onDark ? Color.white.opacity(0.35) : Color.secondary.opacity(0.45))
                    .offset(x: w - (height + 5))
            }
        }
        .frame(height: height + 8)
    }
}

// MARK: - Stop Map View

@available(iOS 16.2, *)
private struct StopMapView: View {
    let state: TransitArrivalAttributes.ContentState
    var size: CGFloat = 76
    var cornerRadius: CGFloat = 14

    var body: some View {
        ZStack {
            if let data = state.mapImageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                // Stop pin overlay on top of the map
                Circle()
                    .fill(Color(red: 0.13, green: 0.84, blue: 0.46))
                    .frame(width: size * 0.18, height: size * 0.18)
                    .shadow(color: .black.opacity(0.4), radius: 2)
            } else {
                Color(red: 0.09, green: 0.10, blue: 0.12)
                Image(systemName: "map.fill")
                    .font(.system(size: size * 0.28, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.15))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }
}

// MARK: - Lock Screen Banner
//
//  ┌──────────────────────────────────────────────────────────┐
//  │ [Icon] [PILL]  Headsign                        38 min   │
//  │                Bus · University District    ● On Time   │
//  │ 📍 Stop Name                              🕐 4:32 PM   │
//  │  🚌 ─────────────────────────────────────────── 📍     │
//  └──────────────────────────────────────────────────────────┘

@available(iOS 16.2, *)
struct LockScreenBanner: View {
    let attributes: TransitArrivalAttributes
    let state: TransitArrivalAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Row 1 — icon + pill (left) | countdown only (right)
            HStack(alignment: .center, spacing: 8) {
                AppIconBadge(size: 22)
                RoutePill(route: attributes.routeShortName, status: state.scheduleStatus, fontSize: 13)
                Spacer()
                Countdown(state: state, numberSize: 32, unitSize: 12)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // Row 2 — headsign (left) + status label (right), same line
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(attributes.tripHeadsign)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(state.isPredicted ? state.scheduleStatus.label : "Scheduled")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(state.isPredicted ? state.scheduleStatus.color : .secondary)
                    .fixedSize()
            }
            .padding(.horizontal, 16)
            .padding(.top, 5)

            // Row 3 — stop name + arrival time
            HStack(spacing: 0) {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Text(attributes.stopName)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if state.minutesUntilArrival > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "clock")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        Text(state.arrivalDepartureDate, style: .time)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 5)

            // Row 4 — progress track
            ProgressTrack(state: state, height: 6, showMarker: true, onDark: false)
                .padding(.horizontal, 16)
                .padding(.top, 7)
                .padding(.bottom, 10)
        }
    }
}

// MARK: - Dynamic Island: Expanded
//
//  ┌─[leading]──────────[center]──────[trailing]─┐
//  │  [AppIcon]          Headsign      [Map 76×76]│
//  │  [49 pill]          → Direction              │
//  │  ✓ On Time          4:32 PM                  │
//  │  ● Live                                      │
//  ├─[bottom]────────────────────────────────────┤
//  │  🚌 ─────────────────────────────────── 📍  │
//  │  📍 Stop Name              🕐 4:32 PM        │
//  │  ● Real-time               7 min away        │
//  └─────────────────────────────────────────────┘

@available(iOS 16.2, *)
private struct DILeading: View {
    let attributes: TransitArrivalAttributes
    let state: TransitArrivalAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Row 1: App icon only
            AppIconBadge(size: 22)

            // Row 2: Route pill
            RoutePill(route: attributes.routeShortName,
                      status: state.scheduleStatus, fontSize: 11)

            // Row 3: Status label — fills the gap between pill and bottom bar
            HStack(spacing: 3) {
                Image(systemName: state.scheduleStatus.symbol)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(state.scheduleStatus.color)
                Text(state.scheduleStatus.label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(state.scheduleStatus.color)
                    .fixedSize()
            }
        }
        .padding(.leading, 6)
        .padding(.vertical, 8)
    }
}

@available(iOS 16.2, *)
private struct DITrailing: View {
    let state: TransitArrivalAttributes.ContentState

    var body: some View {
        StopMapView(state: state, size: 72, cornerRadius: 13)
            .padding(.trailing, 4)
            .padding(.vertical, 4)
    }
}

@available(iOS 16.2, *)
private struct DICenter: View {
    let attributes: TransitArrivalAttributes
    let state: TransitArrivalAttributes.ContentState

    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            Text(attributes.tripHeadsign)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)

            // Arrival time + live/scheduled dot
            HStack(spacing: 4) {
                Circle()
                    .fill(state.isPredicted ? state.scheduleStatus.color : Color.white.opacity(0.25))
                    .frame(width: 5, height: 5)
                Text(state.arrivalDepartureDate, style: .time)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.60))
            }
        }
        .padding(.vertical, 8)
    }
}

@available(iOS 16.2, *)
private struct DIBottom: View {
    let attributes: TransitArrivalAttributes
    let state: TransitArrivalAttributes.ContentState

    var body: some View {
        VStack(spacing: 3) {
            // Stop name (left) + countdown (right)
            HStack(spacing: 0) {
                HStack(spacing: 3) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.white.opacity(0.28))
                    Text(attributes.stopName)
                        .font(.system(size: 9))
                        .foregroundStyle(Color.white.opacity(0.50))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Minutes countdown — right-aligned
                if state.minutesUntilArrival <= 0 {
                    Text("Now")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(state.scheduleStatus.color)
                } else {
                    HStack(alignment: .lastTextBaseline, spacing: 1) {
                        Text("\(state.minutesUntilArrival)")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundStyle(state.minutesUntilArrival <= 2 ? state.scheduleStatus.color : .white)
                            .contentTransition(.numericText(countsDown: true))
                        Text("min")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.45))
                    }
                }
            }
            .padding(.horizontal, 12)

            // Progress bar
            ProgressTrack(state: state, height: 5, showMarker: true, onDark: true)
                .frame(height: 13)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
        }
    }
}

// MARK: - Dynamic Island: Compact
//
// Leading : status-colored bus icon + route pill, flush to the notch
// Trailing: progress arc (sized to pill height) wrapping the countdown, flush to edge

@available(iOS 16.2, *)
private struct DICompactLeading: View {
    let attributes: TransitArrivalAttributes
    let state: TransitArrivalAttributes.ContentState

    var body: some View {
        HStack(spacing: 4) {
            AppLogoMark(size: 16)
            RoutePill(route: attributes.routeShortName,
                      status: state.scheduleStatus, fontSize: 11)
        }
        .padding(.leading, 4)
        .padding(.trailing, 2)
    }
}

@available(iOS 16.2, *)
private struct DICompactTrailing: View {
    let state: TransitArrivalAttributes.ContentState

    private var progress: Double {
        guard state.minutesUntilArrival > 0 else { return 1 }
        return max(0.04, min(1, 1 - Double(state.minutesUntilArrival) / 30.0))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 2)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(state.scheduleStatus.color,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: progress)
            if state.minutesUntilArrival <= 0 {
                Text("!")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundStyle(state.scheduleStatus.color)
            } else {
                Text("\(state.minutesUntilArrival)")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(state.minutesUntilArrival <= 2
                                     ? state.scheduleStatus.color : .white)
                    .contentTransition(.numericText(countsDown: true))
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(width: 22, height: 22)
        .padding(.leading, 6)
    }
}

// MARK: - Dynamic Island: Minimal

@available(iOS 16.2, *)
private struct DIMinimal: View {
    let state: TransitArrivalAttributes.ContentState

    private var progress: Double {
        guard state.minutesUntilArrival > 0 else { return 1 }
        return max(0.04, min(1, 1 - Double(state.minutesUntilArrival) / 30.0))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.10), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    state.scheduleStatus.color,
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: state.scheduleStatus.color.opacity(0.55), radius: 2)
                .animation(.easeInOut(duration: 0.5), value: progress)

            if state.minutesUntilArrival <= 0 {
                AppLogoMark(size: 13, color: state.scheduleStatus.color)
            } else {
                Text("\(state.minutesUntilArrival)")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(countsDown: true))
            }
        }
        .frame(width: 26, height: 26)
    }
}

// MARK: - Preview Helpers

@available(iOS 16.2, *)
private extension TransitArrivalAttributes {
    static func make(
        stop: String = "E Pine St & 15th Ave",
        route: String = "49",
        headsign: String = "University District",
        stopID: String = "1_75403",
        region: Int = 1,
        lat: Double = 47.6152,
        lon: Double = -122.3145
    ) -> TransitArrivalAttributes {
        TransitArrivalAttributes(
            stopName: stop, routeShortName: route,
            tripHeadsign: headsign, stopID: stopID, regionIdentifier: region,
            stopLatitude: lat, stopLongitude: lon
        )
    }
}

@available(iOS 16.2, *)
private extension TransitArrivalAttributes.ContentState {
    static func arriving(in minutes: Int, predicted: Bool = true, status: ScheduleStatusState = .onTime) -> Self {
        .init(arrivalDepartureDate: Date().addingTimeInterval(TimeInterval(minutes * 60)),
              minutesUntilArrival: minutes, isPredicted: predicted, scheduleStatus: status)
    }
    static var now: Self       { arriving(in: 0) }
    static var onTime: Self    { arriving(in: 7) }
    static var delayed: Self   { arriving(in: 12, status: .delayed) }
    static var early: Self     { arriving(in: 3, status: .early) }
    static var scheduled: Self { arriving(in: 20, predicted: false, status: .unknown) }
    static var urgent: Self    { arriving(in: 1) }
}

// MARK: - WidgetKit Previews

@available(iOS 16.2, *)
#Preview("Lock Screen — All States", as: .content, using: TransitArrivalAttributes.make()) {
    TransitLiveActivityWidget()
} contentStates: {
    TransitArrivalAttributes.ContentState.onTime
    TransitArrivalAttributes.ContentState.delayed
    TransitArrivalAttributes.ContentState.early
    TransitArrivalAttributes.ContentState.urgent
    TransitArrivalAttributes.ContentState.now
    TransitArrivalAttributes.ContentState.scheduled
}

@available(iOS 16.2, *)
#Preview("Lock Screen — Ferry", as: .content, using: TransitArrivalAttributes.make(
    stop: "Colman Dock / Ferry Terminal",
    route: "WSF",
    headsign: "Bainbridge Island",
    lat: 47.6024, lon: -122.3385
)) {
    TransitLiveActivityWidget()
} contentStates: {
    TransitArrivalAttributes.ContentState.arriving(in: 4, status: .onTime)
    TransitArrivalAttributes.ContentState.arriving(in: 0)
}

@available(iOS 16.2, *)
#Preview("Dynamic Island — Expanded", as: .dynamicIsland(.expanded), using: TransitArrivalAttributes.make()) {
    TransitLiveActivityWidget()
} contentStates: {
    TransitArrivalAttributes.ContentState.onTime
    TransitArrivalAttributes.ContentState.delayed
    TransitArrivalAttributes.ContentState.urgent
    TransitArrivalAttributes.ContentState.now
}

@available(iOS 16.2, *)
#Preview("Dynamic Island — Compact", as: .dynamicIsland(.compact), using: TransitArrivalAttributes.make()) {
    TransitLiveActivityWidget()
} contentStates: {
    TransitArrivalAttributes.ContentState.onTime
    TransitArrivalAttributes.ContentState.early
    TransitArrivalAttributes.ContentState.urgent
    TransitArrivalAttributes.ContentState.now
}

@available(iOS 16.2, *)
#Preview("Dynamic Island — Minimal", as: .dynamicIsland(.minimal), using: TransitArrivalAttributes.make()) {
    TransitLiveActivityWidget()
} contentStates: {
    TransitArrivalAttributes.ContentState.onTime
    TransitArrivalAttributes.ContentState.delayed
    TransitArrivalAttributes.ContentState.urgent
    TransitArrivalAttributes.ContentState.now
}
