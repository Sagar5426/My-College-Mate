import Foundation
import UserNotifications
import SwiftData
import SwiftUI

@MainActor
class NotificationManager {

    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()

    @AppStorage("notificationsEnabled")
    private var notificationsEnabled: Bool = false

    @AppStorage("notificationLeadMinutes")
    private var notificationLeadMinutes: Int = 10

    private init() {}

    // MARK: - Authorization
    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification authorization error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Scheduling (Discrete 14-Day Window)

    /// Schedules discrete notifications for the next 14 days for a single subject
    func scheduleNotifications(for subject: Subject) async {
        guard notificationsEnabled else {
            await cancelNotifications(for: subject)
            return
        }

        // 1. Clear existing notifications for this subject to avoid duplicates
        await cancelNotifications(for: subject)

        guard let schedules = subject.schedules, !schedules.isEmpty else { return }

        // 2. Schedule for the next 14 days
        let calendar = Calendar.current
        let today = Date()
        
        // Loop through next 14 days
        for dayOffset in 0..<14 {
            guard let targetDate = calendar.date(byAdding: .day, value: dayOffset, to: today) else { continue }
            
            // Generate notifications for this specific date
            await scheduleNotifications(for: subject, on: targetDate)
        }
    }

    /// Helper to schedule notifications for a specific date (used by the loop and by DailyLogView)
    func scheduleNotifications(for subject: Subject, on date: Date) async {
        guard notificationsEnabled, let schedules = subject.schedules else { return }
        
        let calendar = Calendar.current
        let weekdayIndex = calendar.component(.weekday, from: date) // 1=Sun, 2=Mon...
        let dateString = dateFormatter.string(from: date) // For unique ID
        
        let subjectPrefix = subject.id.uuidString

        for schedule in schedules {
            // Check if this schedule runs on this weekday
            guard let scheduleWeekday = dayToWeekday(schedule.day),
                  scheduleWeekday == weekdayIndex,
                  let classTimes = schedule.classTimes else { continue }

            for classTime in classTimes {
                guard let startTime = classTime.startTime else { continue }

                let components = calendar.dateComponents([.hour, .minute], from: startTime)
                guard let hour = components.hour, let minute = components.minute else { continue }

                // --- 1. Exact Start Notification ---
                let exactContent = UNMutableNotificationContent()
                exactContent.title = subject.name
                exactContent.body = startedBody(room: classTime.roomNumber)
                exactContent.sound = .default

                var exactTriggerDate = DateComponents()
                exactTriggerDate.year = calendar.component(.year, from: date)
                exactTriggerDate.month = calendar.component(.month, from: date)
                exactTriggerDate.day = calendar.component(.day, from: date)
                exactTriggerDate.hour = hour
                exactTriggerDate.minute = minute

                let exactTrigger = UNCalendarNotificationTrigger(dateMatching: exactTriggerDate, repeats: false)
                
                // ID Format: SubjectID_ClassTimeID_YYYYMMDD_Type
                let exactIdentifier = "\(subjectPrefix)_\(classTime.id.uuidString)_\(dateString)_exact"

                let exactRequest = UNNotificationRequest(identifier: exactIdentifier, content: exactContent, trigger: exactTrigger)

                do {
                    try await center.add(exactRequest)
                    
                    // --- 2. Upcoming Notification ---
                    let priorMinutes = notificationLeadMinutes
                    if priorMinutes > 0 {
                        // Calculate pre-time
                        guard let classDate = calendar.date(from: exactTriggerDate),
                              let preDate = calendar.date(byAdding: .minute, value: -priorMinutes, to: classDate) else { continue }
                        
                        let preTriggerComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: preDate)
                        
                        let preContent = UNMutableNotificationContent()
                        preContent.title = subject.name
                        preContent.body = upcomingBody(room: classTime.roomNumber, minutes: priorMinutes)
                        preContent.sound = .default
                        
                        let preTrigger = UNCalendarNotificationTrigger(dateMatching: preTriggerComponents, repeats: false)
                        let preIdentifier = "\(subjectPrefix)_\(classTime.id.uuidString)_\(dateString)_pre"
                        
                        let preRequest = UNNotificationRequest(identifier: preIdentifier, content: preContent, trigger: preTrigger)
                        try await center.add(preRequest)
                    }
                    
                } catch {
                    print("Failed to schedule: \(error)")
                }
            }
        }
    }

    // MARK: - Cancellation Logic

    /// Cancel all notifications for a subject
    func cancelNotifications(for subject: Subject) async {
        await cancelNotifications(prefix: subject.id.uuidString)
    }

    /// Cancel notifications specifically for a certain date (used when marking Holiday)
    func cancelNotifications(on date: Date) async {
        let dateString = dateFormatter.string(from: date)
        let pending = await center.pendingNotificationRequests()
        
        // Filter IDs that contain the date string (e.g. "_20251027_")
        let idsToRemove = pending.map(\.identifier).filter { $0.contains("_\(dateString)_") }
        
        if !idsToRemove.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: idsToRemove)
            print("Cancelled \(idsToRemove.count) notifications for holiday on \(dateString)")
        }
    }
    
    // Internal helper for cancelling by ID prefix
    private func cancelNotifications(prefix: String) async {
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        if !identifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }

    // MARK: - Rescheduling Helper
    
    /// Reschedule notifications for a list of subjects on a specific date (used when un-marking Holiday)
    func rescheduleNotifications(for subjects: [Subject], on date: Date) async {
        for subject in subjects {
            await scheduleNotifications(for: subject, on: date)
        }
    }

    // MARK: - Helpers

    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd"
        return df
    }()

    private func startedBody(room: String?) -> String {
        guard let room, !room.isEmpty else { return "📚 Class has started." }
        return "📚 Head to Room \(room) — class has started."
    }

    private func upcomingBody(room: String?, minutes: Int) -> String {
        guard let room, !room.isEmpty else { return "⏰ Class starts in \(minutes) minutes." }
        return "⏰ Head to Room \(room) in \(minutes) minutes."
    }

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
