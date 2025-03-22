//
//  ComplicationController.swift
//  OBAKit
//
//  Created by Prince Yadav on 06/03/25.
//

import ClockKit

class ComplicationController: NSObject, CLKComplicationDataSource {
    func getComplicationDescriptors(handler: @escaping ([CLKComplicationDescriptor]) -> Void) {
        let descriptors = [
            CLKComplicationDescriptor(
                identifier: "complication",
                displayName: "OneBusAway",
                supportedFamilies: [.modularSmall, .circularSmall, .graphicCircular] // Adjust as needed
            )
        ]
        handler(descriptors)
    }

    func getCurrentTimelineEntry(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTimelineEntry?) -> Void) {
        let template = createTemplate(for: complication, text: "5 min")
        let entry = CLKComplicationTimelineEntry(date: Date(), complicationTemplate: template)
        handler(entry)
    }

    func getTimelineEntries(for complication: CLKComplication, after date: Date, limit: Int, withHandler handler: @escaping ([CLKComplicationTimelineEntry]?) -> Void) {
        var entries: [CLKComplicationTimelineEntry] = []
        
        for i in 1...limit {
            let newDate = date.addingTimeInterval(Double(i) * 60)
            let template = createTemplate(for: complication, text: "\(i * 5) min")
            let entry = CLKComplicationTimelineEntry(date: newDate, complicationTemplate: template)
            entries.append(entry)
        }

        handler(entries)
    }

    func getPrivacyBehavior(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationPrivacyBehavior) -> Void) {
        handler(.showOnLockScreen)
    }

    private func createTemplate(for complication: CLKComplication, text: String) -> CLKComplicationTemplate {
        switch complication.family {
        case .modularSmall:
            let template = CLKComplicationTemplateModularSmallSimpleText()
            template.textProvider = CLKSimpleTextProvider(text: text)
            return template
        case .circularSmall:
            let template = CLKComplicationTemplateCircularSmallSimpleText()
            template.textProvider = CLKSimpleTextProvider(text: text)
            return template
        case .graphicCircular:
            let template = CLKComplicationTemplateGraphicCircularStackText()
            template.line1TextProvider = CLKSimpleTextProvider(text: "Bus")
            template.line2TextProvider = CLKSimpleTextProvider(text: text)
            return template
        default:
            return CLKComplicationTemplateModularSmallSimpleText() // Fallback
        }
    }
}
