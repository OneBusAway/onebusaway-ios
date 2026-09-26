//
//  OnDemandDockBarView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import OBAKitCore
import SwiftUI
import UIKit

/// One page of the docked bar (spec 3.4 States per page).
struct OnDemandDockBarPage: Identifiable, Equatable {

    enum Trailing: Equatable {
        case call(URL)
        case bookOnline(URL)
        /// Inside with no contact details.
        case detail
        /// Outside: centre the map on the nearest boundary point.
        case panToEdge(CLLocationCoordinate2D)
        /// Outside with neither a server point nor client geometry.
        case none

        static func == (lhs: Trailing, rhs: Trailing) -> Bool {
            switch (lhs, rhs) {
            case (.call(let left), .call(let right)), (.bookOnline(let left), .bookOnline(let right)): return left == right
            case (.detail, .detail), (.none, .none): return true
            case (.panToEdge(let left), .panToEdge(let right)): return left.latitude == right.latitude && left.longitude == right.longitude
            default: return false
            }
        }
    }

    let match: OnDemandServiceMatch
    /// The service name; nil when the title is unknown and the name takes its place.
    let eyebrow: String?
    let title: String
    let backgroundColor: UIColor
    /// The service's zone colour, which the thumbnail placeholder disc keeps
    /// even when the page itself is outside gray (spec 3.4).
    let serviceColor: UIColor
    let textColor: UIColor
    let trailing: Trailing

    var id: String { match.id }

    var trailingSystemImage: String? {
        switch trailing {
        case .call: return "phone.fill"
        case .bookOnline: return "arrow.up.right.square"
        case .detail, .panToEdge: return "chevron.right"
        case .none: return nil
        }
    }

    var trailingAccessibilityLabel: String? {
        switch trailing {
        case .call: return String(format: Strings.onDemandBarCallFormat, match.service.name)
        case .bookOnline: return Strings.onDemandBookOnline
        case .detail: return Strings.onDemandCardDetails
        case .panToEdge: return Strings.onDemandBarShowEdge
        case .none: return nil
        }
    }

    init(match: OnDemandServiceMatch, edge: OnDemandEdge?, color: UIColor, copy: OnDemandCopy) {
        self.match = match
        let title = copy.forService(match.service).barTitle(for: match, edge: edge)
        eyebrow = title == nil ? nil : match.service.name
        self.title = title ?? match.service.name
        serviceColor = color
        if match.isInside {
            backgroundColor = color
            textColor = OnDemandServiceColors.textColor(for: match.service, on: color)
            switch OnDemandZoneCardModel.primaryAction(for: match.service) {
            case .call(let url): trailing = .call(url)
            case .bookOnline(let url): trailing = .bookOnline(url)
            case nil: trailing = .detail
            }
        } else {
            backgroundColor = ThemeColors.shared.onDemandOutside
            textColor = .white
            trailing = edge.map { .panToEdge($0.point) } ?? .none
        }
    }
}

/// The bar's content: pages in the shared sort, the thumbnail rings once
/// every page's full geometry has arrived, and the badge rule.
struct OnDemandDockBarModel: Equatable {
    let pages: [OnDemandDockBarPage]
    let probePoint: CLLocationCoordinate2D
    /// Nil until every stacked service's geometry is cached, or when any fetch failed.
    let thumbnailRings: [OnDemandThumbnailRing]?
    /// Every current inside and nearby match (`pickerCandidates(from:)`): the
    /// long-press picker lists these, not just the bar's stack (spec 3.5).
    let pickerMatches: [OnDemandServiceMatch]

    var showsBadge: Bool { pages.count > 1 }

    /// The long-press picker's list: the inside and nearby matches. `isNearby`
    /// carries the 5,000 m rule, so a far stop-radius match stays out.
    static func pickerCandidates(from matches: [OnDemandServiceMatch]) -> [OnDemandServiceMatch] {
        matches.filter { $0.isInside || $0.isNearby }
    }

    func badge(forPageAt index: Int) -> String {
        OnDemandCopy.badge(index: index + 1, count: pages.count)
    }

    /// The bar is one VoiceOver element (spec 3.4): the page's eyebrow and title.
    func accessibilityLabel(forPageAt index: Int) -> String {
        guard pages.indices.contains(index) else { return "" }
        let page = pages[index]
        return [page.eyebrow, page.title].compactMap { $0 }.joined(separator: ", ")
    }

    /// The bar long-press (and its accessibility action) opens the nearby picker.
    func pickerRequest(source: ProbeSource) -> OnDemandPickerRequest {
        OnDemandPickerRequest(matches: pickerMatches, scope: .nearby, source: source, coordinate: probePoint)
    }

    init(
        matches: [OnDemandServiceMatch],
        pickerMatches: [OnDemandServiceMatch],
        probePoint: CLLocationCoordinate2D,
        edges: [String: OnDemandEdge],
        fullAreas: [String: [ServiceArea]],
        failedGeometry: Set<String>,
        colors: [String: UIColor],
        copy: OnDemandCopy
    ) {
        let sorted = sortedSoonestUsable(matches)
        pages = sorted.map { match in
            OnDemandDockBarPage(
                match: match,
                edge: edges[match.id],
                color: colors[match.id] ?? OnDemandServiceColors.baseColor(for: match.service),
                copy: copy
            )
        }
        self.probePoint = probePoint
        self.pickerMatches = pickerMatches

        let allLoaded = sorted.allSatisfy { fullAreas[$0.id] != nil && !failedGeometry.contains($0.id) }
        guard allLoaded, !sorted.isEmpty else {
            thumbnailRings = nil
            return
        }
        thumbnailRings = sorted.flatMap { match -> [OnDemandThumbnailRing] in
            let color = colors[match.id] ?? OnDemandServiceColors.baseColor(for: match.service)
            return (fullAreas[match.id] ?? []).flatMap(\.polygons).flatMap { $0 }.map { OnDemandThumbnailRing(points: $0, color: color) }
        }
    }

    static func == (lhs: OnDemandDockBarModel, rhs: OnDemandDockBarModel) -> Bool {
        lhs.pages == rhs.pages
            && lhs.thumbnailRings == rhs.thumbnailRings
            && lhs.pickerMatches == rhs.pickerMatches
            && lhs.probePoint.latitude == rhs.probePoint.latitude
            && lhs.probePoint.longitude == rhs.probePoint.longitude
    }
}

/// Spec 3.4: a 72 pt paged bar with the thumbnail, eyebrow, title and one
/// trailing button per page; page dots below when there is more than one.
struct OnDemandDockBarView: View {
    let model: OnDemandDockBarModel
    let locationCheck: OnDemandLocationCheck
    let actions: OnDemandDockActions
    let onPageChange: (String) -> Void

    @State private var selectedPageID: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let cornerRadius: CGFloat = 20
    private static let padding: CGFloat = 8
    private static let minimumHeight: CGFloat = 72
    private static let trailingButtonSize = OnDemandZoneCardView.minimumTouchTarget
    private static let longPressDuration = 0.5
    private static let dotSize: CGFloat = 7
    private static let dotColor = Color(red: 0xc7 / 255.0, green: 0xc7 / 255.0, blue: 0xcc / 255.0)
    private static let currentDotColor = Color(red: 0x3a / 255.0, green: 0x3a / 255.0, blue: 0x3c / 255.0)
    private static let badgeBackground = Color(red: 0x3a / 255.0, green: 0x3a / 255.0, blue: 0x3c / 255.0).opacity(0.9)

    private var selectedIndex: Int {
        model.pages.firstIndex { $0.id == selectedPageID } ?? 0
    }

    private var currentPage: OnDemandDockBarPage? {
        model.pages.indices.contains(selectedIndex) ? model.pages[selectedIndex] : nil
    }

    private var pickerRequest: OnDemandPickerRequest {
        model.pickerRequest(source: locationCheck.source)
    }

    var body: some View {
        VStack(spacing: 6) {
            TabView(selection: $selectedPageID) {
                ForEach(Array(model.pages.enumerated()), id: \.element.id) { index, page in
                    pageView(page, index: index)
                        .tag(Optional(page.id))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(minHeight: Self.minimumHeight)
            .fixedSize(horizontal: false, vertical: true)

            if model.pages.count > 1 {
                HStack(spacing: 6) {
                    ForEach(Array(model.pages.enumerated()), id: \.element.id) { index, _ in
                        Circle()
                            .fill(index == selectedIndex ? Self.currentDotColor : Self.dotColor)
                            .frame(width: Self.dotSize, height: Self.dotSize)
                    }
                }
                .accessibilityHidden(true)
            }
        }
        .onAppear {
            if selectedPageID == nil { selectedPageID = model.pages.first?.id }
        }
        .onChange(of: selectedPageID) { _, newValue in
            if let newValue { onPageChange(newValue) }
        }
        .onChange(of: model.pages.map(\.id)) { _, ids in
            if let selectedPageID, !ids.contains(selectedPageID) { self.selectedPageID = ids.first }
        }
        // Spec 3.4 / ruling F9: one adjustable element. The buttons' labels
        // become its custom actions, so the children stay out of the tree.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel(forPageAt: selectedIndex))
        .accessibilityValue(model.showsBadge ? model.badge(forPageAt: selectedIndex) : "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            if let currentPage { actions.openDetail(currentPage.match, locationCheck) }
        }
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: select(offset: 1)
            case .decrement: select(offset: -1)
            @unknown default: break
            }
        }
        .accessibilityActions {
            Button(Strings.onDemandBarZoomOut) { actions.zoomOut(model.pages.map(\.match)) }
            if let currentPage, let trailingLabel = currentPage.trailingAccessibilityLabel {
                Button(trailingLabel) { performTrailing(currentPage) }
            }
            Button(Strings.onDemandBarMoreServices) { actions.openPicker(pickerRequest) }
        }
    }

    private func select(offset: Int) {
        let target = selectedIndex + offset
        guard model.pages.indices.contains(target) else { return }
        selectedPageID = model.pages[target].id
    }

    private func pageView(_ page: OnDemandDockBarPage, index: Int) -> some View {
        HStack(spacing: 12) {
            Button { actions.zoomOut(model.pages.map(\.match)) } label: {
                OnDemandZoneThumbnailView(rings: model.thumbnailRings, probePoint: model.probePoint, placeholderColor: page.serviceColor)
                    .overlay(alignment: .bottomLeading) {
                        if model.showsBadge {
                            Text(model.badge(forPageAt: index))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Self.badgeBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(.white, lineWidth: 1))
                                .offset(x: -2, y: 2)
                        }
                    }
            }
            .buttonStyle(.plain)

            Button { actions.openDetail(page.match, locationCheck) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    if let eyebrow = page.eyebrow {
                        Text(eyebrow).font(.caption.weight(.semibold)).opacity(0.85).lineLimit(1)
                    }
                    Text(page.title)
                        .font(.headline.weight(.bold))
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            trailingButton(page)
        }
        .foregroundStyle(Color(uiColor: page.textColor))
        .padding(Self.padding)
        .background(Color(uiColor: page.backgroundColor), in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        // High priority so a long press over the thumbnail, title or trailing
        // button opens the picker instead of firing that button on release; a
        // quick tap fails the long press and still reaches the button, and a
        // drag past the long press's distance limit still pages the TabView.
        .highPriorityGesture(
            LongPressGesture(minimumDuration: Self.longPressDuration).onEnded { _ in
                actions.openPicker(pickerRequest)
            }
        )
    }

    private func performTrailing(_ page: OnDemandDockBarPage) {
        switch page.trailing {
        case .call(let url): actions.call(url)
        case .bookOnline(let url): actions.openURL(url)
        case .detail: actions.openDetail(page.match, locationCheck)
        case .panToEdge(let point): actions.panTo(point)
        case .none: break
        }
    }

    @ViewBuilder
    private func trailingButton(_ page: OnDemandDockBarPage) -> some View {
        if let systemImage = page.trailingSystemImage {
            Button { performTrailing(page) } label: {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .frame(width: Self.trailingButtonSize, height: Self.trailingButtonSize)
                    .background(.white.opacity(0.2), in: Circle())
            }
            .buttonStyle(.plain)
        }
    }
}
