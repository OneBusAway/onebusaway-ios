//
//  NotificationHandler.swift
//  OBAKit
//
//  Created by Prince Yadav on 06/03/25.
//


import WatchKit
import UserNotifications

class NotificationHandler: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Handle notification when app is in foreground
        completionHandler([.banner, .sound])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // Handle notification response
        let userInfo = response.notification.request.content.userInfo
        
        // Extract stop ID from notification
        if let stopId = userInfo["stopId"] as? String {
            // Open the app to the arrivals view for this stop
            // This would require coordination with the main app
        }
        
        completionHandler()
    }
    
    func scheduleArrivalNotification(for arrival: Arrival, stop: Stop) {
        // Check if notifications are enabled
        let enableNotifications = UserDefaults.standard.bool(forKey: "enableNotifications")
        guard enableNotifications else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Bus Arriving Soon"
        content.body = "\(arrival.routeShortName) to \(arrival.headsign) arriving at \(stop.name) in \(arrival.minutesUntilArrival)"
        content.sound = .default
        
        // Add user info to notification
        content.userInfo = [
            "stopId": stop.id,
            "routeId": arrival.routeId
        ]
        
        // Calculate trigger time (2 minutes before arrival)
        let arrivalTime = arrival.predictedArrivalTime ?? arrival.scheduledArrivalTime
        let triggerTime = arrivalTime.timeIntervalSinceNow - 120 // 2 minutes before
        
        // Only schedule if arrival is more than 2 minutes away
        guard triggerTime > 0 else { return }
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: triggerTime, repeats: false)
        
        // Create request
        let request = UNNotificationRequest(identifier: "arrival-\(arrival.id)", content: content, trigger: trigger)
        
        // Add request to notification center
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling notification: \(error.localizedDescription)")
            }
        }
    }
}

