//
//  NotificationController.swift
//  OBAKit
//
//  Created by Prince Yadav on 06/03/25.
//


import WatchKit
import SwiftUI
import UserNotifications

class NotificationController: WKUserNotificationHostingController<NotificationView> {
    var arrival: Arrival?
    var stopName: String?
    
    override var body: NotificationView {
        return NotificationView(arrival: arrival, stopName: stopName)
    }
    
    override func didReceive(_ notification: UNNotification) {
        let content = notification.request.content
        let userInfo = content.userInfo
        
        // Extract arrival information from notification
        if let arrivalData = userInfo["arrivalData"] as? Data {
            self.arrival = try? JSONDecoder().decode(Arrival.self, from: arrivalData)
        }
        
        // Extract stop name
        self.stopName = userInfo["stopName"] as? String
    }
}

struct NotificationView: View {
    var arrival: Arrival?
    var stopName: String?
    
    var body: some View {
        VStack(spacing: 8) {
            if let arrival = arrival {
                Text(arrival.routeShortName)
                    .font(.headline)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(arrival.routeColor)
                    .foregroundColor(.white)
                    .cornerRadius(4)
                
                Text(arrival.headsign)
                    .font(.subheadline)
                
                if let stopName = stopName {
                    Text("Arriving at \(stopName)")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
                
                Text(arrival.minutesUntilArrival)
                    .font(.title2)
                    .foregroundColor(arrival.isLate ? .red : .green)
            } else {
                Text("Bus Arriving Soon")
                    .font(.headline)
                
                if let stopName = stopName {
                    Text("At \(stopName)")
                        .font(.subheadline)
                }
            }
        }
        .padding()
    }
}

struct NotificationView_Previews: PreviewProvider {
    static var previews: some View {
        NotificationView(
            arrival: Arrival.example,
            stopName: "University District"
        )
    }
}

