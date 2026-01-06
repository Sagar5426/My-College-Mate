//
//  NotificationManager.swift
//  College Mate
//
//  Created by Sagar Jangra on 29/10/2025.
//

import Foundation
import UserNotifications
import SwiftData
import SwiftUI

@MainActor
class NotificationManager {
    
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()
    
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = false
    @AppStorage("notificationLeadMinutes") private var notificationLeadMinutes: Int = 10

    private init() {}

    /// Call this when your app first launches (e.g., in your App's init() or onAppear()).
    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Error requesting notification authorization: \(error.localizedDescription)")
            }
            if granted {
                print("Notification permission granted.")
            } else {
                print("Notification permission denied.")
            }
        }
    }

    /// Schedules repeating weekly notifications for all classes in a given subject.
    /// This method first cancels all existing notifications for the subject to prevent duplicates.
    func scheduleNotifications(for subject: Subject) async {
        // Respect user preference: if disabled, cancel and exit
        guard notificationsEnabled else {
            await cancelNotifications(for: subject)
            return
        }

        // Cancel existing to ensure clean slate
        await cancelNotifications(for: subject)
        
        guard let schedules = subject.schedules, !schedules.isEmpty else { return }

        let subjectPrefix = subject.id.uuidString

        for schedule in schedules {
            guard let classTimes = schedule.classTimes else { continue }
            guard let weekday = dayToWeekday(schedule.day) else { continue }

            for classTime in classTimes {
                guard let startTime = classTime.startTime else { continue }
                
                // Extract hour/minute from startTime
                let calendar = Calendar.current
                let components = calendar.dateComponents([.hour, .minute], from: startTime)
                guard let hour = components.hour, let minute = components.minute else { continue }
                
                // 1. Notification at exact class time
                let content = UNMutableNotificationContent()
                content.title = "Class Started: \(subject.name)"
                // Removed roomNo as it doesn't exist in the Schedule/ClassTime model
                content.body = "Your class is scheduled now."
                content.sound = .default
                
                var triggerDate = DateComponents()
                triggerDate.weekday = weekday
                triggerDate.hour = hour
                triggerDate.minute = minute
                
                let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: true)
                
                // Construct unique ID: SubjectUUID_ScheduleUUID_ClassTimeUUID_Exact
                // Including ClassTime UUID is important if a subject has multiple times on the same day
                let identifier = "\(subjectPrefix)_\(schedule.id.uuidString)_\(classTime.id.uuidString)_exact"
                let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                
                do {
                    try await center.add(request)
                    // print("Scheduled exact notification: \(identifier)")
                    
                    // 2. Notification X minutes prior
                    let priorMinutes = notificationLeadMinutes
                    guard priorMinutes > 0 else { continue }
                    
                    // Calculate prior time
                    // We need to handle potential hour wrapping (e.g. 10:05 - 10 mins = 09:55)
                    // The easiest way is to construct a dummy Date, subtract, then extract components.
                    // We use a known reference date's weekday/hour/minute to do the math.
                    
                    // Construct a date for "today" at that time, subtract, see result.
                    // Note: This ignores the specific "weekday" logic for the subtraction math, but time-of-day math is constant.
                    // e.g. 10:00 - 15min is always 09:45 regardless of day.
                    
                    let today = Date()
                    if let baseDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: today),
                       let priorDate = calendar.date(byAdding: .minute, value: -priorMinutes, to: baseDate) {
                        
                        _ = calendar.dateComponents([.hour, .minute], from: priorDate)
                        
                        var priorTriggerDate = DateComponents()
                        priorTriggerDate.weekday = weekday // Same day (assuming lead time < 24 hrs and doesn't cross midnight heavily in a way that changes weekday for most classes)
                        // Edge case: If class is Monday 00:05 and lead is 10 mins, it should be Sunday 23:55.
                        // Handling the day-wrap correctly:
                        if let exactDayDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: baseDate), // This is just a dummy
                           let shiftedDate = calendar.date(byAdding: .minute, value: -priorMinutes, to: exactDayDate) {
                             
                            // Check if day changed (e.g. pushed back to previous day)
                            if !calendar.isDate(exactDayDate, inSameDayAs: shiftedDate) {
                                 // Weekday needs to shift back by 1
                                 var prevDay = weekday - 1
                                 if prevDay < 1 { prevDay = 7 }
                                 priorTriggerDate.weekday = prevDay
                            }
                            
                            let shiftedComps = calendar.dateComponents([.hour, .minute], from: shiftedDate)
                            priorTriggerDate.hour = shiftedComps.hour
                            priorTriggerDate.minute = shiftedComps.minute
                        }
                        
                        let preContent = UNMutableNotificationContent()
                        preContent.title = "Upcoming Class: \(subject.name)"
                        // Removed roomNo
                        preContent.body = "Starts in \(priorMinutes) minutes."
                        preContent.sound = .default
                        
                        let preTrigger = UNCalendarNotificationTrigger(dateMatching: priorTriggerDate, repeats: true)
                        let preIdentifier = "\(subjectPrefix)_\(schedule.id.uuidString)_\(classTime.id.uuidString)_pre"
                        
                        let preRequest = UNNotificationRequest(identifier: preIdentifier, content: preContent, trigger: preTrigger)
                        
                        try await center.add(preRequest)
                        // print("Scheduled prior notification: \(preIdentifier)")
                    }

                } catch {
                    print("Failed to schedule notification \(identifier): \(error.localizedDescription)")
                }
            }
        }
    }

    /// Cancels all pending notifications for a specific subject object.
    func cancelNotifications(for subject: Subject) async {
        await cancelNotifications(for: subject.id.uuidString)
    }
    
    /// Cancels all pending notifications for a specific subject ID.
    /// Useful when the subject object might be deleted or invalidated.
    func cancelNotifications(for subjectID: String) async {
        let pendingRequests = await center.pendingNotificationRequests()
        
        let identifiersToCancel = pendingRequests
            .map { $0.identifier }
            .filter { $0.hasPrefix(subjectID) }
        
        if !identifiersToCancel.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: identifiersToCancel)
            print("Cancelled \(identifiersToCancel.count) notifications for subject ID: \(subjectID)")
        }
    }
    
    /// Helper to convert day string to weekday integer (1=Sunday, 2=Monday, etc.)
    private func dayToWeekday(_ day: String) -> Int? {
        switch day.lowercased() {
        case "sunday": return 1
        case "monday": return 2
        case "tuesday": return 3
        case "wednesday": return 4
        case "thursday": return 5
        case "friday": return 6
        case "saturday": return 7
        default: return nil
        }
    }
}
