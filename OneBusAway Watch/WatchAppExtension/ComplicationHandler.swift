//
//  ComplicationHandler.swift
//  OBAKit
//
//  Created by Prince Yadav on 06/03/25.
//


import WatchKit
import ClockKit

class ComplicationHandler: NSObject, CLKComplicationDataSource {
    // MARK: - Timeline Configuration
    
    func getSupportedTimeTravelDirections(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTimeTravelDirections) -> Void) {
        handler([.forward])
    }
    
    func getTimelineStartDate(for complication: CLKComplication, withHandler handler: @escaping (Date?) -> Void) {
        handler(Date())
    }
    
    func getTimelineEndDate(for complication: CLKComplication, withHandler handler: @escaping (Date?) -> Void) {
        // Return a date 2 hours in the future
        handler(Date().addingTimeInterval(2 * 60 * 60))
    }
    
    func getPrivacyBehavior(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationPrivacyBehavior) -> Void) {
        handler(.showOnLockScreen)
    }
    
    // MARK: - Timeline Population
    
    func getCurrentTimelineEntry(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTimelineEntry?) -> Void) {
        // Get the complication data
        getComplicationTemplate(for: complication) { template in
            if let template = template {
                let entry = CLKComplicationTimelineEntry(date: Date(), complicationTemplate: template)
                handler(entry)
            } else {
                handler(nil)
            }
        }
    }
    
    func getTimelineEntries(for complication: CLKComplication, after date: Date, limit: Int, withHandler handler: @escaping ([CLKComplicationTimelineEntry]?) -> Void) {
        // Create timeline entries for future arrivals
        var entries: [CLKComplicationTimelineEntry] = []
        
        // Load favorite stops and get arrivals
        if let data = UserDefaults.standard.data(forKey: "favoriteStops"),
           let favorites = try? JSONDecoder().decode([Stop].self, from: data),
           let firstFavorite = favorites.first {
            
            // In a real app, you would fetch arrivals from the API
            // For now, we'll create some sample entries
            let currentDate = Date()
            
            for i in 0..<min(limit, 5) {
                let futureDate = currentDate.addingTimeInterval(Double(i) * 15 * 60) // Every 15 minutes
                
                getComplicationTemplate(for: complication, at: futureDate) { template in
                    if let template = template {
                        let entry = CLKComplicationTimelineEntry(date: futureDate, complicationTemplate: template)
                        entries.append(entry)
                    }
                }
            }
        }
        
        handler(entries)
    }
    
    // MARK: - Sample Templates
    
    func getLocalizableSampleTemplate(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTemplate?) -> Void) {
        getComplicationTemplate(for: complication) { template in
            handler(template)
        }
    }
    
    // MARK: - Helper Methods
    
    private func getComplicationTemplate(for complication: CLKComplication, at date: Date = Date(), completion: @escaping (CLKComplicationTemplate?) -> Void) {
        // Create a template based on the complication family
        switch complication.family {
        case .modularSmall:
            let template = CLKComplicationTemplateModularSmallStackText()
            template.line1TextProvider = CLKSimpleTextProvider(text: "43")
            template.line2TextProvider = CLKSimpleTextProvider(text: "5 min")
            completion(template)
            
        case .modularLarge:
            let template = CLKComplicationTemplateModularLargeStandardBody()
            template.headerTextProvider = CLKSimpleTextProvider(text: "OneBusAway")
            template.body1TextProvider = CLKSimpleTextProvider(text: "Route 43")
            template.body2TextProvider = CLKSimpleTextProvider(text: "Arriving in 5 min")
            completion(template)
            
        case .utilitarianSmall:
            let template = CLKComplicationTemplateUtilitarianSmallFlat()
            template.textProvider = CLKSimpleTextProvider(text: "43: 5m")
            completion(template)
            
        case .utilitarianLarge:
            let template = CLKComplicationTemplateUtilitarianLargeFlat()
            template.textProvider = CLKSimpleTextProvider(text: "Route 43: 5 min")
            completion(template)
            
        case .circularSmall:
            let template = CLKComplicationTemplateCircularSmallStackText()
            template.line1TextProvider = CLKSimpleTextProvider(text: "43")
            template.line2TextProvider = CLKSimpleTextProvider(text: "5m")
            completion(template)
            
        case .extraLarge:
            let template = CLKComplicationTemplateExtraLargeStackText()
            template.line1TextProvider = CLKSimpleTextProvider(text: "43")
            template.line2TextProvider = CLKSimpleTextProvider(text: "5 min")
            completion(template)
            
        case .graphicCorner:
            let template = CLKComplicationTemplateGraphicCornerStackText()
            template.innerTextProvider = CLKSimpleTextProvider(text: "43")
            template.outerTextProvider = CLKSimpleTextProvider(text: "5 min")
            completion(template)
            
        case .graphicBezel:
            let circularTemplate = CLKComplicationTemplateGraphicCircularStackText()
            circularTemplate.line1TextProvider = CLKSimpleTextProvider(text: "43")
            circularTemplate.line2TextProvider = CLKSimpleTextProvider(text: "5m")
            
            let template = CLKComplicationTemplateGraphicBezelCircularText()
            template.circularTemplate = circularTemplate
            template.textProvider = CLKSimpleTextProvider(text: "Next bus in 5 minutes")
            completion(template)
            
        case .graphicCircular:
            let template = CLKComplicationTemplateGraphicCircularStackText()
            template.line1TextProvider = CLKSimpleTextProvider(text: "43")
            template.line2TextProvider = CLKSimpleTextProvider(text: "5m")
            completion(template)
            
        case .graphicRectangular:
            let template = CLKComplicationTemplateGraphicRectangularStandardBody()
            template.headerTextProvider = CLKSimpleTextProvider(text: "OneBusAway")
            template.body1TextProvider = CLKSimpleTextProvider(text: "Route 43")
            template.body2TextProvider = CLKSimpleTextProvider(text: "Arriving in 5 min")
            completion(template)
            
        default:
            completion(nil)
        }
    }
}

