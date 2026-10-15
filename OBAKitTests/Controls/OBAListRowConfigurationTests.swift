//
//  OBAListRowConfigurationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import UIKit
@testable import OBAKit
@testable import OBAKitCore

@MainActor
@Suite(.serialized)
struct OBAListRowConfigurationTests {

    // MARK: - OBAListRowConfiguration Initialization & Properties

    /// Tests default property values of OBAListRowConfiguration upon initialization.
    @Test func testDefaultInitialization() {
        let config = OBAListRowConfiguration()
        #expect(config.formatters == nil)
        #expect(config.image == nil)
        #expect(config.imageConfig == OBAImageViewConfiguration())
        #expect(config.text == nil)
        #expect(config.secondaryText == nil)
        #expect(config.textConfig == OBALabelConfiguration())
        #expect(config.secondaryTextConfig == OBALabelConfiguration(textColor: .secondaryLabel))
        #expect(config.appearance == .default)
        #expect(config.accessoryType == .none)
    }

    /// Tests that minimum cell height varies appropriately by row appearance.
    @Test func testMinimumCellHeight() {
        var config = OBAListRowConfiguration()

        config.appearance = .header
        #expect(config.minimumCellHeight == 0)

        config.appearance = .default
        #expect(config.minimumCellHeight == 44.0)

        config.appearance = .subtitle
        #expect(config.minimumCellHeight == 44.0)

        config.appearance = .value
        #expect(config.minimumCellHeight == 44.0)
    }

    /// Tests base UIListContentConfiguration generation across appearances.
    @Test func testListConfigurationAppearances() {
        var config = OBAListRowConfiguration()

        config.appearance = .default
        _ = config.listConfiguration

        config.appearance = .subtitle
        _ = config.listConfiguration

        config.appearance = .value
        _ = config.listConfiguration

        config.appearance = .header
        _ = config.listConfiguration
    }

    /// Tests propagation of row configuration properties to UIListContentConfiguration.
    @Test func testListConfigurationPropertiesPropagation() {
        var config = OBAListRowConfiguration()
        let image = UIImage()
        config.image = image
        config.imageConfig = OBAImageViewConfiguration(tintColor: .systemRed, maximumSize: CGSize(width: 28, height: 28))
        config.text = .string("Primary Title")
        config.secondaryText = .string("Secondary Detail")
        config.textConfig = OBALabelConfiguration(textColor: .systemBlue, numberOfLines: 2, accessibilityNumberOfLines: 4)
        config.secondaryTextConfig = OBALabelConfiguration(textColor: .systemGray, numberOfLines: 1, accessibilityNumberOfLines: 2)
        config.appearance = .subtitle

        let listConfig = config.listConfiguration

        #expect(listConfig.image == image)
        #expect(listConfig.imageProperties.tintColor == .systemRed)
        #expect(listConfig.imageProperties.maximumSize == CGSize(width: 28, height: 28))
        #expect(listConfig.labelText == .string("Primary Title"))
        #expect(listConfig.secondaryLabelText == .string("Secondary Detail"))
        #expect(listConfig.textProperties.color == .systemBlue)
        #expect(listConfig.textProperties.numberOfLines == 2)
        #expect(listConfig.secondaryTextProperties.color == .systemGray)
        #expect(listConfig.secondaryTextProperties.numberOfLines == 1)
        #expect(listConfig.textToSecondaryTextVerticalPadding == ThemeMetrics.compactPadding)
    }

    /// Tests mapping from Accessory to UICellAccessory displayed state.
    @Test func testAccessoryCellAccessoryMapping() {
        #expect(OBAListRowConfiguration.Accessory.none.cellAccessory == nil)

        let checkmarkAccessory = OBAListRowConfiguration.Accessory.checkmark.cellAccessory
        #expect(checkmarkAccessory != nil)
        #expect(checkmarkAccessory?.displayedState == .always)

        let disclosureAccessory = OBAListRowConfiguration.Accessory.disclosureIndicator.cellAccessory
        #expect(disclosureAccessory != nil)
        #expect(disclosureAccessory?.displayedState == .always)
    }

    /// Tests equatable conformance across all mutable properties of OBAListRowConfiguration.
    @Test func testEquality() {
        let imageA = UIImage()
        let imageB = UIImage()

        let base = OBAListRowConfiguration(
            image: imageA,
            text: .string("Title"),
            secondaryText: .string("Subtitle"),
            appearance: .subtitle,
            accessoryType: .checkmark
        )

        let identical = base
        #expect(base == identical)

        var differentImage = base
        differentImage.image = imageB
        #expect(base != differentImage)

        var differentText = base
        differentText.text = .string("Changed")
        #expect(base != differentText)

        var differentSecondary = base
        differentSecondary.secondaryText = .string("Changed")
        #expect(base != differentSecondary)

        var differentAppearance = base
        differentAppearance.appearance = .default
        #expect(base != differentAppearance)

        var differentAccessory = base
        differentAccessory.accessoryType = .disclosureIndicator
        #expect(base != differentAccessory)

        var differentImageConfig = base
        differentImageConfig.imageConfig = .tinted(.red)
        #expect(base != differentImageConfig)

        var differentTextConfig = base
        differentTextConfig.textConfig = OBALabelConfiguration(textColor: .green)
        #expect(base != differentTextConfig)

        var differentSecTextConfig = base
        differentSecTextConfig.secondaryTextConfig = OBALabelConfiguration(textColor: .yellow)
        #expect(base != differentSecTextConfig)
    }

    // MARK: - LabelText

    /// Tests equality and hash consistency for LabelText string instances.
    @Test func testLabelTextStringEqualityAndHash() {
        let text1 = OBAListRowConfiguration.LabelText.string("Station")
        let text2 = OBAListRowConfiguration.LabelText.string("Station")
        let text3 = OBAListRowConfiguration.LabelText.string("Other")
        let nilText1 = OBAListRowConfiguration.LabelText.string(nil)
        let nilText2 = OBAListRowConfiguration.LabelText.string(nil)

        #expect(text1 == text2)
        #expect(text1.hashValue == text2.hashValue)
        #expect(text1 != text3)
        #expect(nilText1 == nilText2)
        #expect(nilText1.hashValue == nilText2.hashValue)
        #expect(text1 != nilText1)
    }

    /// Tests equality and hash consistency for LabelText attributed string instances.
    @Test func testLabelTextAttributedEqualityAndHash() {
        let attr1 = NSAttributedString(string: "Bold Station", attributes: [.strokeWidth: 2])
        let attr2 = NSAttributedString(string: "Bold Station", attributes: [.strokeWidth: 2])
        let attr3 = NSAttributedString(string: "Italic Station", attributes: [.obliqueness: 0.5])

        let label1 = OBAListRowConfiguration.LabelText.attributed(attr1)
        let label2 = OBAListRowConfiguration.LabelText.attributed(attr2)
        let label3 = OBAListRowConfiguration.LabelText.attributed(attr3)
        let nilAttr1 = OBAListRowConfiguration.LabelText.attributed(nil)
        let nilAttr2 = OBAListRowConfiguration.LabelText.attributed(nil)

        #expect(label1 == label2)
        #expect(label1.hashValue == label2.hashValue)
        #expect(label1 != label3)
        #expect(nilAttr1 == nilAttr2)
        #expect(nilAttr1.hashValue == nilAttr2.hashValue)
        #expect(label1 != nilAttr1)
    }

    /// Tests inequality when comparing string and attributed LabelText variants.
    @Test func testLabelTextCrossVariantInequality() {
        let stringVariant = OBAListRowConfiguration.LabelText.string("Route 44")
        let attributedVariant = OBAListRowConfiguration.LabelText.attributed(NSAttributedString(string: "Route 44"))

        #expect(stringVariant != attributedVariant)
    }

    // MARK: - OBAListRowSeparatorConfiguration

    /// Tests default, hidden, and inset convenience initializers for row separators.
    @Test func testSeparatorConfigurationInitializers() {
        let defaultSep = OBAListRowSeparatorConfiguration()
        #expect(defaultSep.showsSeparator == true)
        #expect(defaultSep.insets == .zero)

        let hiddenSep = OBAListRowSeparatorConfiguration.hidden()
        #expect(hiddenSep.showsSeparator == false)
        #expect(hiddenSep.insets == .zero)

        let customInsets = NSDirectionalEdgeInsets(top: 2, leading: 16, bottom: 4, trailing: 20)
        let insetSep = OBAListRowSeparatorConfiguration.withInset(top: 2, leading: 16, bottom: 4, trailing: 20)
        #expect(insetSep.showsSeparator == true)
        #expect(insetSep.insets == customInsets)

        #expect(defaultSep != hiddenSep)
        #expect(defaultSep != insetSep)
        #expect(defaultSep == OBAListRowSeparatorConfiguration(showsSeparator: true, insets: .zero))
    }

    /// Tests applying OBAListRowSeparatorConfiguration to UIListSeparatorConfiguration.
    @Test func testUIListSeparatorConfigurationApplying() {
        var listSepConfig = UIListSeparatorConfiguration(listAppearance: .plain)

        let visibleConfig = OBAListRowSeparatorConfiguration(
            showsSeparator: true,
            insets: NSDirectionalEdgeInsets(top: 1, leading: 10, bottom: 2, trailing: 12)
        )
        listSepConfig.applying(visibleConfig)
        #expect(listSepConfig.topSeparatorVisibility == .automatic)
        #expect(listSepConfig.bottomSeparatorVisibility == .automatic)
        #expect(listSepConfig.topSeparatorInsets == visibleConfig.insets)
        #expect(listSepConfig.bottomSeparatorInsets == visibleConfig.insets)

        let hiddenConfig = OBAListRowSeparatorConfiguration.hidden()
        listSepConfig.applying(hiddenConfig)
        #expect(listSepConfig.topSeparatorVisibility == .hidden)
        #expect(listSepConfig.bottomSeparatorVisibility == .hidden)
    }

    // MARK: - OBAImageViewConfiguration

    /// Tests initialization, sizing, tinting, and applying OBAImageViewConfiguration.
    @Test func testImageViewConfiguration() {
        let defaultConfig = OBAImageViewConfiguration()
        #expect(defaultConfig.tintColor == ThemeColors.shared.brand)
        #expect(defaultConfig.maximumSize == .zero)

        let tinted = OBAImageViewConfiguration.tinted(.systemPurple)
        #expect(tinted.tintColor == .systemPurple)
        #expect(tinted.maximumSize == .zero)

        let sized = OBAImageViewConfiguration.maximumSize(squared: 32.0)
        #expect(sized.tintColor == ThemeColors.shared.brand)
        #expect(sized.maximumSize == CGSize(width: 32.0, height: 32.0))

        #expect(tinted != sized)
        #expect(defaultConfig == OBAImageViewConfiguration(tintColor: ThemeColors.shared.brand, maximumSize: .zero))

        var contentConfig = UIListContentConfiguration.cell()
        sized.apply(to: &contentConfig)
        #expect(contentConfig.imageProperties.tintColor == ThemeColors.shared.brand)
        #expect(contentConfig.imageProperties.maximumSize == CGSize(width: 32.0, height: 32.0))
    }

    // MARK: - OBALabelConfiguration

    /// Tests default values and property application to text and secondary text.
    @Test func testLabelConfigurationDefaultsAndApply() {
        let defaultConfig = OBALabelConfiguration()
        #expect(defaultConfig.textColor == .label)
        #expect(defaultConfig.numberOfLines == 0)
        #expect(defaultConfig.accessibilityNumberOfLines == 0)

        var customConfig = OBALabelConfiguration()
        customConfig.textColor = .systemIndigo
        customConfig.numberOfLines = 3
        customConfig.accessibilityNumberOfLines = 6

        var contentConfig = UIListContentConfiguration.subtitleCell()
        customConfig.applyToText(&contentConfig)
        #expect(contentConfig.textProperties.color == .systemIndigo)
        #expect(contentConfig.textProperties.numberOfLines == 3)

        customConfig.applyToSecondaryText(&contentConfig)
        #expect(contentConfig.secondaryTextProperties.color == .systemIndigo)
        #expect(contentConfig.secondaryTextProperties.numberOfLines == 3)

        #expect(defaultConfig != customConfig)
    }

    /// Tests configuring UILabel styling and applying string, attributed, and nil text.
    @Test func testUILabelConfigurationAndSetText() {
        let label = UILabel()
        let config = OBALabelConfiguration(textColor: .systemTeal, numberOfLines: 4, accessibilityNumberOfLines: 8)
        label.configure(with: config)
        #expect(label.textColor == .systemTeal)
        #expect(label.numberOfLines == 4)

        label.setText(.string("Standard String"))
        #expect(label.text == "Standard String")

        let attr = NSAttributedString(string: "Attributed String", attributes: [.underlineStyle: NSUnderlineStyle.single.rawValue])
        label.setText(.attributed(attr))
        #expect(label.attributedText?.string == "Attributed String")

        label.setText(nil)
        #expect(label.text == nil)
        #expect(label.attributedText == nil)
    }

    /// Tests UIListContentConfiguration labelText and secondaryLabelText extensions.
    @Test func testUIListContentConfigurationLabelTextExtensions() {
        var contentConfig = UIListContentConfiguration.cell()

        contentConfig.labelText = .string("Primary Line")
        #expect(contentConfig.text == "Primary Line")
        #expect(contentConfig.labelText == .string("Primary Line"))

        let attr = NSAttributedString(string: "Attr Primary")
        contentConfig.labelText = .attributed(attr)
        #expect(contentConfig.attributedText == attr)

        contentConfig.secondaryLabelText = .string("Secondary Line")
        #expect(contentConfig.secondaryText == "Secondary Line")
        #expect(contentConfig.secondaryLabelText == .string("Secondary Line"))

        let secondaryAttr = NSAttributedString(string: "Attr Secondary")
        contentConfig.secondaryLabelText = .attributed(secondaryAttr)
        #expect(contentConfig.secondaryAttributedText == secondaryAttr)

        contentConfig.secondaryLabelText = nil
        #expect(contentConfig.secondaryText == nil)
        #expect(contentConfig.secondaryLabelText == nil)
    }

    // MARK: - OBAListSectionConfiguration

    /// Tests appearance and background color styling for OBAListSectionConfiguration.
    @Test func testListSectionConfiguration() {
        let defaultSection = OBAListSectionConfiguration()
        #expect(defaultSection.appearance == .plain)
        #expect(defaultSection.backgroundColor == nil)

        let insetGrouped = OBAListSectionConfiguration.appearance(.insetGrouped)
        #expect(insetGrouped.appearance == .insetGrouped)
        #expect(insetGrouped.backgroundColor == nil)

        let colored = OBAListSectionConfiguration(appearance: .insetGrouped, backgroundColor: .systemBackground)
        #expect(colored.backgroundColor == .systemBackground)

        let plainLayout = defaultSection.listConfiguration()
        #expect(plainLayout.appearance == .plain)
        #expect(plainLayout.backgroundColor == nil)

        let insetLayout = colored.listConfiguration()
        #expect(insetLayout.appearance == .insetGrouped)
        #expect(insetLayout.backgroundColor == .systemBackground)

        #expect(defaultSection == OBAListSectionConfiguration(appearance: .plain))
        #expect(defaultSection != insetGrouped)
        #expect(insetGrouped != colored)
    }

    // MARK: - OBAListRowView ViewModels

    /// Tests OBAListRowView.DefaultViewModel initialization and configuration conversion.
    @Test func testDefaultViewModel() {
        let stringModel = OBAListRowView.DefaultViewModel(
            title: "Departures",
            accessoryType: .none
        )
        #expect(stringModel.title == .string("Departures"))
        #expect(stringModel.accessoryType == .none)
        #expect(stringModel.image == nil)

        guard case let .custom(contentConfig) = stringModel.configuration,
              let rowConfig = contentConfig as? OBAListRowConfiguration else {
            Issue.record("Expected OBAListRowConfiguration inside .custom")
            return
        }
        #expect(rowConfig.appearance == .default)
        #expect(rowConfig.text == .string("Departures"))
        #expect(rowConfig.accessoryType == .none)

        let attrTitle = NSAttributedString(string: "Attributed Departures")
        let attrModel = OBAListRowView.DefaultViewModel(title: attrTitle)
        #expect(attrModel.title == .attributed(attrTitle))
        #expect(attrModel.accessoryType == .disclosureIndicator)

        #expect(stringModel != attrModel)
    }

    /// Tests OBAListRowView.SubtitleViewModel initialization and configuration conversion.
    @Test func testSubtitleViewModel() {
        let stringModel = OBAListRowView.SubtitleViewModel(
            title: "Stop #1234",
            subtitle: "Northbound to Downtown",
            accessoryType: .disclosureIndicator
        )
        #expect(stringModel.title == .string("Stop #1234"))
        #expect(stringModel.subtitle == .string("Northbound to Downtown"))

        guard case let .custom(contentConfig) = stringModel.configuration,
              let rowConfig = contentConfig as? OBAListRowConfiguration else {
            Issue.record("Expected OBAListRowConfiguration inside .custom")
            return
        }
        #expect(rowConfig.appearance == .subtitle)
        #expect(rowConfig.text == .string("Stop #1234"))
        #expect(rowConfig.secondaryText == .string("Northbound to Downtown"))
        #expect(rowConfig.accessoryType == .disclosureIndicator)

        let attrTitle = NSAttributedString(string: "Stop Attributed")
        let attrSubtitle = NSAttributedString(string: "Details Attributed")
        let attrModel = OBAListRowView.SubtitleViewModel(
            title: attrTitle,
            subtitle: attrSubtitle
        )
        #expect(attrModel.title == .attributed(attrTitle))
        #expect(attrModel.subtitle == .attributed(attrSubtitle))

        let labelModel = OBAListRowView.SubtitleViewModel(
            image: nil,
            title: .string("Label Title"),
            subtitle: nil,
            accessoryType: .none
        )
        #expect(labelModel.title == .string("Label Title"))
        #expect(labelModel.subtitle == nil)
        #expect(labelModel.accessoryType == .none)
    }

    /// Tests OBAListRowView.ValueViewModel initialization and configuration conversion.
    @Test func testValueViewModel() {
        let stringModel = OBAListRowView.ValueViewModel(
            title: "Transfer Fare",
            subtitle: "$2.75",
            accessoryType: .disclosureIndicator
        )
        #expect(stringModel.title == .string("Transfer Fare"))
        #expect(stringModel.subtitle == .string("$2.75"))
        #expect(stringModel.accessoryType == .disclosureIndicator)

        guard case let .custom(contentConfig) = stringModel.configuration,
              let rowConfig = contentConfig as? OBAListRowConfiguration else {
            Issue.record("Expected OBAListRowConfiguration inside .custom")
            return
        }
        #expect(rowConfig.appearance == .value)
        #expect(rowConfig.text == .string("Transfer Fare"))
        #expect(rowConfig.secondaryText == .string("$2.75"))
        #expect(rowConfig.accessoryType == .disclosureIndicator)

        let attrTitle = NSAttributedString(string: "Fare Title")
        let attrSubtitle = NSAttributedString(string: "$0.00")
        let attrModel = OBAListRowView.ValueViewModel(
            title: attrTitle,
            subtitle: attrSubtitle
        )
        #expect(attrModel.title == .attributed(attrTitle))
        #expect(attrModel.subtitle == .attributed(attrSubtitle))

        let labelModel = OBAListRowView.ValueViewModel(
            image: nil,
            title: .string("Direct Title"),
            subtitle: .string("Direct Subtitle"),
            accessoryType: .none
        )
        #expect(labelModel.title == .string("Direct Title"))
        #expect(labelModel.subtitle == .string("Direct Subtitle"))
        #expect(labelModel.accessoryType == .none)
    }
}
