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
        func expectedBase(from base: UIListContentConfiguration) -> UIListContentConfiguration {
            var expected = base
            expected.image = nil
            OBAImageViewConfiguration().apply(to: &expected)
            expected.labelText = nil
            OBALabelConfiguration().applyToText(&expected)
            expected.secondaryLabelText = nil
            OBALabelConfiguration(textColor: .secondaryLabel).applyToSecondaryText(&expected)
            expected.textToSecondaryTextVerticalPadding = ThemeMetrics.compactPadding
            return expected
        }

        var config = OBAListRowConfiguration()

        config.appearance = .default
        let defaultConfig = config.listConfiguration
        #expect(defaultConfig == expectedBase(from: .cell()))
        #expect(defaultConfig.textProperties.font == UIListContentConfiguration.cell().textProperties.font)

        config.appearance = .subtitle
        let subtitleConfig = config.listConfiguration
        #expect(subtitleConfig == expectedBase(from: .subtitleCell()))
        #expect(subtitleConfig.secondaryTextProperties.font == UIListContentConfiguration.subtitleCell().secondaryTextProperties.font)

        config.appearance = .value
        let valueConfig = config.listConfiguration
        #expect(valueConfig == expectedBase(from: .valueCell()))
        #expect(valueConfig.secondaryTextProperties.font == UIListContentConfiguration.valueCell().secondaryTextProperties.font)

        config.appearance = .header
        let headerConfig = config.listConfiguration
        #expect(headerConfig == expectedBase(from: .header()))
        #expect(headerConfig.textProperties.font == UIListContentConfiguration.header().textProperties.font)

        #expect(defaultConfig != subtitleConfig)
        #expect(defaultConfig != valueConfig)
        #expect(defaultConfig != headerConfig)
        #expect(subtitleConfig != valueConfig)
        #expect(subtitleConfig != headerConfig)
        #expect(valueConfig != headerConfig)
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

    /// Tests mapping from Accessory to UICellAccessory.
    @Test func testAccessoryCellAccessoryMapping() {
        #expect(OBAListRowConfiguration.Accessory.none.cellAccessory == nil)
        #expect(OBAListRowConfiguration.Accessory.checkmark.cellAccessory != nil)
        #expect(OBAListRowConfiguration.Accessory.disclosureIndicator.cellAccessory != nil)
    }

    /// Tests equatable conformance across all mutable properties of OBAListRowConfiguration.
    @Test func testEquality() {
        let image = UIImage()

        let base = OBAListRowConfiguration(
            image: image,
            text: .string("Title"),
            secondaryText: .string("Subtitle"),
            appearance: .subtitle,
            accessoryType: .checkmark
        )

        let identical = base
        #expect(base == identical)

        var differentImage = base
        differentImage.image = nil
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
        var stringConfig = UIListContentConfiguration.cell()

        stringConfig.labelText = .string("Primary Line")
        #expect(stringConfig.text == "Primary Line")
        #expect(stringConfig.labelText == .string("Primary Line"))

        stringConfig.secondaryLabelText = .string("Secondary Line")
        #expect(stringConfig.secondaryText == "Secondary Line")
        #expect(stringConfig.secondaryLabelText == .string("Secondary Line"))

        stringConfig.secondaryLabelText = nil
        #expect(stringConfig.secondaryText == nil)
        #expect(stringConfig.secondaryLabelText == nil)

        var attrConfig = UIListContentConfiguration.cell()
        let attr = NSAttributedString(string: "Attr Primary", attributes: [.underlineStyle: NSUnderlineStyle.single.rawValue])
        attrConfig.labelText = .attributed(attr)
        #expect(attrConfig.attributedText?.string == "Attr Primary")
        let primaryUnderline = attrConfig.attributedText?.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int
        #expect(primaryUnderline == NSUnderlineStyle.single.rawValue)

        let secondaryAttr = NSAttributedString(string: "Attr Secondary", attributes: [.strokeWidth: 2])
        attrConfig.secondaryLabelText = .attributed(secondaryAttr)
        #expect(attrConfig.secondaryAttributedText?.string == "Attr Secondary")
        let secondaryStroke = attrConfig.secondaryAttributedText?.attribute(.strokeWidth, at: 0, effectiveRange: nil) as? Int
        #expect(secondaryStroke == 2)
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

        // Test onSelectAction execution
        var actionExecuted = false
        var executedModelTitle: String?
        let onSelect: OBAListViewAction<OBAListRowView.DefaultViewModel> = { model in
            actionExecuted = true
            executedModelTitle = model.title.text
        }
        let actionModel = OBAListRowView.DefaultViewModel(
            title: "Tappable Row",
            accessoryType: .disclosureIndicator,
            onSelectAction: onSelect
        )
        #expect(actionModel.onSelectAction != nil)
        actionModel.onSelectAction?(actionModel)
        #expect(actionExecuted == true)
        #expect(executedModelTitle == "Tappable Row")

        // Test attributed title with onSelectAction
        var attrActionExecuted = false
        let attrActionModel = OBAListRowView.DefaultViewModel(
            title: attrTitle,
            accessoryType: .checkmark,
            onSelectAction: { _ in attrActionExecuted = true }
        )
        attrActionModel.onSelectAction?(attrActionModel)
        #expect(attrActionExecuted == true)

        // Test image assignment and configuration forwarding
        var imageModel = OBAListRowView.DefaultViewModel(title: "With Image")
        let testImage = UIImage(systemName: "bus")
        imageModel.image = testImage
        #expect(imageModel.image == testImage)
        guard case let .custom(imgContentConfig) = imageModel.configuration,
              let imgRowConfig = imgContentConfig as? OBAListRowConfiguration else {
            Issue.record("Expected OBAListRowConfiguration inside .custom")
            return
        }
        #expect(imgRowConfig.image == testImage)

        // Test equality and hashing: distinct UUIDs should mean inequality
        let modelA = OBAListRowView.DefaultViewModel(title: "Equal Check")
        let modelB = OBAListRowView.DefaultViewModel(title: "Equal Check")
        #expect(modelA.id != modelB.id)
        #expect(modelA != modelB)
        #expect(modelA == modelA)
        #expect(modelA.hashValue == modelA.hashValue)
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

        // Verify accessoryType forwarding across string and attributed initializers (#1561)
        let stringNone = OBAListRowView.SubtitleViewModel(title: "Stop #1234", subtitle: "Northbound", accessoryType: .none)
        #expect(stringNone.accessoryType == .none)
        #expect(rowConfiguration(from: stringNone)?.accessoryType == OBAListRowConfiguration.Accessory.none)

        let stringCheckmark = OBAListRowView.SubtitleViewModel(title: "Stop #1234", subtitle: "Northbound", accessoryType: .checkmark)
        #expect(stringCheckmark.accessoryType == .checkmark)
        #expect(rowConfiguration(from: stringCheckmark)?.accessoryType == .checkmark)

        let attrNone = OBAListRowView.SubtitleViewModel(title: attrTitle, subtitle: attrSubtitle, accessoryType: .none)
        #expect(attrNone.accessoryType == .none)
        #expect(rowConfiguration(from: attrNone)?.accessoryType == OBAListRowConfiguration.Accessory.none)

        let attrCheckmark = OBAListRowView.SubtitleViewModel(title: attrTitle, subtitle: attrSubtitle, accessoryType: .checkmark)
        #expect(attrCheckmark.accessoryType == .checkmark)
        #expect(rowConfiguration(from: attrCheckmark)?.accessoryType == .checkmark)

        // Test onSelectAction execution on SubtitleViewModel
        var subtitleActionExecuted = false
        var executedSubtitleText: String?
        let onSelectSubtitle: OBAListViewAction<OBAListRowView.SubtitleViewModel> = { model in
            subtitleActionExecuted = true
            executedSubtitleText = model.subtitle?.text
        }
        let subtitleActionModel = OBAListRowView.SubtitleViewModel(
            title: "Route 10",
            subtitle: "To Capitol Hill",
            accessoryType: .disclosureIndicator,
            onSelectAction: onSelectSubtitle
        )
        #expect(subtitleActionModel.onSelectAction != nil)
        subtitleActionModel.onSelectAction?(subtitleActionModel)
        #expect(subtitleActionExecuted == true)
        #expect(executedSubtitleText == "To Capitol Hill")

        // Test attributed SubtitleViewModel with onSelectAction
        var attrSubActionExecuted = false
        let attrSubActionModel = OBAListRowView.SubtitleViewModel(
            title: attrTitle,
            subtitle: attrSubtitle,
            accessoryType: .detailButton,
            onSelectAction: { _ in attrSubActionExecuted = true }
        )
        attrSubActionModel.onSelectAction?(attrSubActionModel)
        #expect(attrSubActionExecuted == true)

        // Test image assignment and forwarding on SubtitleViewModel
        var subImageModel = OBAListRowView.SubtitleViewModel(title: "With Image", subtitle: "Image Subtitle")
        let subImage = UIImage(systemName: "tram")
        subImageModel.image = subImage
        #expect(subImageModel.image == subImage)
        guard case let .custom(subImgContentConfig) = subImageModel.configuration,
              let subImgRowConfig = subImgContentConfig as? OBAListRowConfiguration else {
            Issue.record("Expected OBAListRowConfiguration inside .custom")
            return
        }
        #expect(subImgRowConfig.image == subImage)

        // Test equality and hashing on SubtitleViewModel
        let subA = OBAListRowView.SubtitleViewModel(title: "Same", subtitle: "Sub")
        let subB = OBAListRowView.SubtitleViewModel(title: "Same", subtitle: "Sub")
        #expect(subA.id != subB.id)
        #expect(subA != subB)
        #expect(subA == subA)
        #expect(subA.hashValue == subA.hashValue)
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

        // Verify accessoryType forwarding across string and attributed initializers (#1561)
        let stringNone = OBAListRowView.ValueViewModel(title: "Transfer Fare", subtitle: "$2.75", accessoryType: .none)
        #expect(stringNone.accessoryType == .none)
        #expect(rowConfiguration(from: stringNone)?.accessoryType == OBAListRowConfiguration.Accessory.none)

        let stringCheckmark = OBAListRowView.ValueViewModel(title: "Transfer Fare", subtitle: "$2.75", accessoryType: .checkmark)
        #expect(stringCheckmark.accessoryType == .checkmark)
        #expect(rowConfiguration(from: stringCheckmark)?.accessoryType == .checkmark)

        let attrNone = OBAListRowView.ValueViewModel(title: attrTitle, subtitle: attrSubtitle, accessoryType: .none)
        #expect(attrNone.accessoryType == .none)
        #expect(rowConfiguration(from: attrNone)?.accessoryType == OBAListRowConfiguration.Accessory.none)

        let attrCheckmark = OBAListRowView.ValueViewModel(title: attrTitle, subtitle: attrSubtitle, accessoryType: .checkmark)
        #expect(attrCheckmark.accessoryType == .checkmark)
        #expect(rowConfiguration(from: attrCheckmark)?.accessoryType == .checkmark)

        // Test onSelectAction execution on ValueViewModel
        var valueActionExecuted = false
        var executedValueTitle: String?
        let onSelectValue: OBAListViewAction<OBAListRowView.ValueViewModel> = { model in
            valueActionExecuted = true
            executedValueTitle = model.title.text
        }
        let valueActionModel = OBAListRowView.ValueViewModel(
            title: "Adult Fare",
            subtitle: "$3.00",
            accessoryType: .disclosureIndicator,
            onSelectAction: onSelectValue
        )
        #expect(valueActionModel.onSelectAction != nil)
        valueActionModel.onSelectAction?(valueActionModel)
        #expect(valueActionExecuted == true)
        #expect(executedValueTitle == "Adult Fare")

        // Test attributed ValueViewModel with onSelectAction
        var attrValActionExecuted = false
        let attrValActionModel = OBAListRowView.ValueViewModel(
            title: attrTitle,
            subtitle: attrSubtitle,
            accessoryType: .detailButton,
            onSelectAction: { _ in attrValActionExecuted = true }
        )
        attrValActionModel.onSelectAction?(attrValActionModel)
        #expect(attrValActionExecuted == true)

        // Test image assignment and forwarding on ValueViewModel
        var valImageModel = OBAListRowView.ValueViewModel(title: "With Image", subtitle: "Image Subtitle")
        let valImage = UIImage(systemName: "creditcard")
        valImageModel.image = valImage
        #expect(valImageModel.image == valImage)
        guard case let .custom(valImgContentConfig) = valImageModel.configuration,
              let valImgRowConfig = valImgContentConfig as? OBAListRowConfiguration else {
            Issue.record("Expected OBAListRowConfiguration inside .custom")
            return
        }
        #expect(valImgRowConfig.image == valImage)

        // Test equality and hashing on ValueViewModel
        let valA = OBAListRowView.ValueViewModel(title: "Same", subtitle: "Val")
        let valB = OBAListRowView.ValueViewModel(title: "Same", subtitle: "Val")
        #expect(valA.id != valB.id)
        #expect(valA != valB)
        #expect(valA == valA)
        #expect(valA.hashValue == valA.hashValue)
    }

    // MARK: - Helpers

    private func rowConfiguration(from item: any OBAListViewItem) -> OBAListRowConfiguration? {
        guard case let .custom(config) = item.configuration else { return nil }
        return config as? OBAListRowConfiguration
    }
}
