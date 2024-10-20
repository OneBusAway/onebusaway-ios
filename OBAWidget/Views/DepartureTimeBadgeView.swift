//
//  DepartureTimeBadgeView.swift
//  OBAWidget
//
//  Created by Manu on 2024-10-14.
//

import SwiftUI
import WidgetKit
import OBAKitCore


struct DepartureTimeBadgeView: View {
    
    let arrivalDeparture: ArrivalDeparture
    let formatters: Formatters
    
    
    private var displayText: String {
        formatters.shortFormattedTime(
            untilMinutes: arrivalDeparture.arrivalDepartureMinutes,
            temporalState: arrivalDeparture.temporalState
        )
    }
    
    
    private var accessibilityLabel: String {
        formatters.explanationForArrivalDeparture(
            tempuraState: arrivalDeparture.temporalState,
            arrivalDepartureStatus: arrivalDeparture.arrivalDepartureStatus,
            arrivalDepartureMinutes: arrivalDeparture.arrivalDepartureMinutes
        )
    }
    
    private var backgroundColor: Color {
        Color(formatters.backgroundColorForScheduleStatus(arrivalDeparture.scheduleStatus))
        
    }
    
    
    var body: some View {
        VStack{
            Text("\(displayText)")
                .font(.system(size: 13))
                .padding(.horizontal, 3)
                .padding(.vertical, 4)
                .frame(width: 40, height: 25)
                .foregroundColor(.white)
                .background(backgroundColor)
                .cornerRadius(8)
                .accessibilityLabel(accessibilityLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
       
    }
}


