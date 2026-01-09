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

    @AppStorage("notificationsEnabled")
    private var notificationsEnabled: Bool = false

    @AppStorage("notificationLeadMinutes")
    private var notificationLeadMinutes: Int = 10

    private init() {}

    // MARK: - Authorization

    /// Call this when your app first launches
    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                print("Notification authorization error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Scheduling

    /// Schedules repeating weekly notifications for all classes in a subject
    func scheduleNotifications(for subject: Subject) async {

        // Respect user preference
        guard notificationsEnabled else {
            await cancelNotifications(for: subject)
            return
        }

        // Ensure no duplicates
        await cancelNotifications(for: subject)

        guard let schedules = subject.schedules, !schedules.isEmpty else { return }

        let subjectPrefix = subject.id.uuidString
        let calendar = Calendar.current

        for schedule in schedules {
            guard
                let classTimes = schedule.classTimes,
                let weekday = dayToWeekday(schedule.day)
            else { continue }

            for classTime in classTimes {
                guard let startTime = classTime.startTime else { continue }

                let components = calendar.dateComponents([.hour, .minute], from: startTime)
                guard let hour = components.hour,
                      let minute = components.minute else { continue }

                // MARK: Exact Class Start Notification

                let exactContent = UNMutableNotificationContent()
                exactContent.title = subject.name
                exactContent.body = startedBody(room: classTime.roomNumber)
                exactContent.sound = .default

                var exactTriggerDate = DateComponents()
                exactTriggerDate.weekday = weekday
                exactTriggerDate.hour = hour
                exactTriggerDate.minute = minute

                let exactTrigger = UNCalendarNotificationTrigger(
                    dateMatching: exactTriggerDate,
                    repeats: true
                )

                let exactIdentifier =
                "\(subjectPrefix)_\(schedule.id.uuidString)_\(classTime.id.uuidString)_exact"

                let exactRequest = UNNotificationRequest(
                    identifier: exactIdentifier,
                    content: exactContent,
                    trigger: exactTrigger
                )

                do {
                    try await center.add(exactRequest)

                    // MARK: Upcoming Notification (X minutes before)

                    let priorMinutes = notificationLeadMinutes
                    guard priorMinutes > 0 else { continue }

                    let today = Date()
                    guard
                        let baseDate = calendar.date(
                            bySettingHour: hour,
                            minute: minute,
                            second: 0,
                            of: today
                        ),
                        let shiftedDate = calendar.date(
                            byAdding: .minute,
                            value: -priorMinutes,
                            to: baseDate
                        )
                    else { continue }

                    var priorTriggerDate = DateComponents()
                    priorTriggerDate.weekday = weekday

                    // Handle day wrap (e.g. 00:05 → previous day)
                    if !calendar.isDate(baseDate, inSameDayAs: shiftedDate) {
                        var prevDay = weekday - 1
                        if prevDay < 1 { prevDay = 7 }
                        priorTriggerDate.weekday = prevDay
                    }

                    let shiftedComponents = calendar.dateComponents([.hour, .minute], from: shiftedDate)
                    priorTriggerDate.hour = shiftedComponents.hour
                    priorTriggerDate.minute = shiftedComponents.minute

                    let preContent = UNMutableNotificationContent()
                    preContent.title = subject.name
                    preContent.body = upcomingBody(
                        room: classTime.roomNumber,
                        minutes: priorMinutes
                    )
                    preContent.sound = .default

                    let preTrigger = UNCalendarNotificationTrigger(
                        dateMatching: priorTriggerDate,
                        repeats: true
                    )

                    let preIdentifier =
                    "\(subjectPrefix)_\(schedule.id.uuidString)_\(classTime.id.uuidString)_pre"

                    let preRequest = UNNotificationRequest(
                        identifier: preIdentifier,
                        content: preContent,
                        trigger: preTrigger
                    )

                    try await center.add(preRequest)

                } catch {
                    print("Failed to schedule notification: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Cancellation

    func cancelNotifications(for subject: Subject) async {
        await cancelNotifications(for: subject.id.uuidString)
    }

    func cancelNotifications(for subjectID: String) async {
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(subjectID) }

        if !identifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }

    // MARK: - Helpers

    private func startedBody(room: String?) -> String {
        guard let room, !room.isEmpty else {
            return "📚 Class has started."
        }
        return "📚 Head to Room \(room) — class has started."
    }

    private func upcomingBody(room: String?, minutes: Int) -> String {
        guard let room, !room.isEmpty else {
            return "⏰ Class starts in \(minutes) minutes."
        }
        return "⏰ Head to Room \(room) in \(minutes) minutes."
    }

    /// Converts weekday string to Calendar weekday (1 = Sunday)
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
