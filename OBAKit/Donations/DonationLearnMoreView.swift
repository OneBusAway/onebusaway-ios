//
//  DonationRequestView.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 10/28/23.
//

import SwiftUI
import UIKit
import OBAKitCore

struct DonationLearnMoreView: View {
    @State var showFullExplanation = false
    @EnvironmentObject var donationModel: DonationModel
    @EnvironmentObject var analyticsModel: AnalyticsModel

    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button("Close") {
                analyticsModel.analytics?.reportEvent(pageURL: "app://localhost/donations", label: AnalyticsLabels.donationCanceled, value: nil)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .padding()
            .zIndex(2)

            List {
                buildHeaderImageSection()
                buildExplanationSection()
                buildDonateButton()
                buildPhotoCreditSection()
            }
            .listStyle(.plain)
        }
        .interactiveDismissDisabled() // disabled to make sure that we can always get analytics data for a user-initiated dismissal.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onFirstAppear {
            analyticsModel.analytics?.reportEvent(pageURL: "app://localhost/donations", label: AnalyticsLabels.donationLearnMoreShown, value: nil)
        }
    }

    private func buildDonateButton() -> some View {
        Button {
            donationModel.donate()
        } label: {
            Text("Donate on our Website")
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .buttonStyle(.borderedProminent)
        .fontWeight(.bold)
        .font(.title2)
    }

    func buildPhotoCreditSection() -> some View {
        Text("Photo by Timothy Neesam / License CC-BY-ND 2.0 (https://flickr.com/photos/neesam)")
            .font(.footnote)
            .foregroundStyle(.gray)
            .listRowSeparator(.hidden)
    }

    func buildExplanationSection() -> some View {
        Group {
            Text("Here's why we need your help").font(.title2).bold()
            Text("""
            We have big plans to improve OneBusAway, but we can't do it without your help. This app is currently built with 100% volunteer labor, and we need you to help us fund future development.

            As a key project of the Open Transit Software Foundation, a 501(c)(3) non-profit, we rely on the goodwill of users like you to keep running and making this software better.

            Every year, only a small fraction of our users donate, but every contribution, big or small, helps ensure that OneBusAway remains free, updated, and accessible to everyone. A small donation, even just the cost of one week of commuting, $27.50, can make all the difference.

            Your tax-deductible contribution ensures that OneBusAway remains free and accessible for everyone. Let's shape the future of transit together!

            Thank you,
            The OneBusAway Team
            """)
            .lineLimit(showFullExplanation ? nil : 3)

            if !showFullExplanation {
                Button {
                    showFullExplanation = true
                } label: {
                    Text("Read More...")
                        .foregroundColor(.accentColor)
                }
            }
        }
        .listRowSeparator(.hidden)
    }

    func buildHeaderImageSection() -> some View {
        GeometryReader { geometry in
            Image("wmata")
                .resizable()
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
        }
        .frame(height: 300)
        .padding(-20)
        .listRowSeparator(.hidden)
    }
}

//  #Preview {
//    abxoxo - needs environment object added.
//    DonationLearnMoreView()
//  }
