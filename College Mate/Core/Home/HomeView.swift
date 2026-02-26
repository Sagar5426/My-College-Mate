//  HomeView.swift
//  College Mate

import SwiftUI
import SwiftData
import ActivityKit

struct HomeView: View {
    @EnvironmentObject var authService: AuthenticationService
    @Query var subjects: [Subject]
    @State private var selectedTab = "Subjects"
    
    // Tracks when the app comes to the foreground to update the Live Activity
    @Environment(\.scenePhase) var scenePhase
    
    var body: some View {
        TabView(selection: $selectedTab) {
            
            VStack {
                SubjectsView()
            }
            .tabItem {
                Label("Subjects", systemImage: "book.closed")
            }
            .tag("Subjects")
            
            DailyLogView()
                .tabItem {
                    Label("Daily Log", systemImage: "calendar.circle.fill")
                }
                .tag("Daily Log")
            
            TimeTableView()
                .tabItem {
                    Label("TimeTable", systemImage: "calendar")
                }
                .tag("TimeTable")
            
        }
        .tint(.cyan)
        .environment(\.colorScheme, .dark)
        .sensoryFeedback(.selection, trigger: selectedTab)
        .onAppear {
            refreshLiveActivity()
        }
        // 1. Listen for app state changes (coming back from background)
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                refreshLiveActivity()
            }
        }
        // 2. Listen for the "Mark as Holiday" button press from DailyLogView
        .onReceive(NotificationCenter.default.publisher(for: .todayHolidayStateChanged)) { _ in
            refreshLiveActivity()
        }
    }
    
    // MARK: - Live Activity Logic
    
    func refreshLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        
        // 1. Check if TODAY is marked as a holiday natively using SwiftData
        if isTodayAHoliday() {
            // If it's a holiday, kill all active Live Activities instantly
            Task {
                for activity in Activity<ClassActivityAttributes>.activities {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
            return
        }
        
        // 2. Fetch & sort today's classes
        let todayClasses = getTodaysClasses()
        
        // If there are no classes today, end any lingering activities and stop
        if todayClasses.isEmpty {
            Task {
                for activity in Activity<ClassActivityAttributes>.activities {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
            return
        }
        
        let now = Date()
        var currentClass: (Subject, ClassTime)?
        var nextClass: (Subject, ClassTime)?
        
        // 3. Find the ongoing class and the upcoming class
        for item in todayClasses {
            let start = normalizedTime(for: item.classTime.startTime)
            let end = normalizedTime(for: item.classTime.endTime)
            
            if now >= start && now <= end {
                currentClass = item
            } else if start > now && nextClass == nil {
                nextClass = item
            }
        }
        
        // 4. Build State Variables based on the ActivityWidget UI Scenarios
        let sessionType: ClassActivityAttributes.ContentState.SessionType
        let subjectName: String
        let currentRoom: String
        let nextRoom: String
        let startTime: Date
        let endTime: Date
        
        if let current = currentClass {
            // SCENARIO 1: Class is happening right now
            sessionType = .ongoingClass
            subjectName = current.0.name
            currentRoom = current.1.roomNumber
            nextRoom = nextClass?.1.roomNumber ?? "None"
            startTime = normalizedTime(for: current.1.startTime)
            endTime = normalizedTime(for: current.1.endTime)
            
        } else if let next = nextClass {
            // SCENARIO 2: On break, waiting for the next class
            sessionType = .breakTime
            subjectName = next.0.name
            currentRoom = "N/A"
            nextRoom = next.1.roomNumber
            startTime = Date() // Break started right now
            endTime = normalizedTime(for: next.1.startTime) // Break ends when next class starts
            
            // Schedule an automatic refresh right as the break timer hits 0:00 to show "Late by:"
            let timeUntilBreakEnds = endTime.timeIntervalSinceNow
            if timeUntilBreakEnds > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + timeUntilBreakEnds) {
                    self.refreshLiveActivity()
                }
            }
            
        } else {
            // SCENARIO 3: All classes for today have ended
            sessionType = .dayEnded
            subjectName = "Done"
            currentRoom = ""
            nextRoom = ""
            startTime = Date()
            endTime = Date()
        }
        
        // 5. Request or Update the Activity
        let attributes = ClassActivityAttributes(subjectName: subjectName)
        let state = ClassActivityAttributes.ContentState(
            sessionType: sessionType,
            currentRoom: currentRoom,
            nextRoom: nextRoom,
            startTime: startTime,
            endTime: endTime,
            attendanceStatus: "Select",
            isLate: Date() > endTime // Will be true if the break timer has expired!
        )
        let content = ActivityContent(state: state, staleDate: nil)
        
        Task {
            if let currentActivity = Activity<ClassActivityAttributes>.activities.first {
                await currentActivity.update(content)
                print("Updated Activity: \(currentActivity.id)")
            } else {
                do {
                    let activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
                    print("Started New Activity: \(activity.id)")
                } catch {
                    print("Error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    /// Checks SwiftData to see if ANY subject record for TODAY is marked as `isHoliday == true`
    private func isTodayAHoliday() -> Bool {
        let today = Calendar.current.startOfDay(for: Date())
        
        for subject in subjects {
            if let records = subject.records {
                if records.contains(where: { Calendar.current.isDate($0.date, inSameDayAs: today) && $0.isHoliday }) {
                    return true
                }
            }
        }
        return false
    }
    
    /// Filters through your SwiftData `subjects` to pull all `ClassTime` objects assigned to today's day of the week.
    private func getTodaysClasses() -> [(subject: Subject, classTime: ClassTime)] {
        let todayString = currentDayString()
        var todaysClasses: [(subject: Subject, classTime: ClassTime)] = []
        
        // Ensure subject falls within its validity dates (start date is in the past)
        let todayStart = Calendar.current.startOfDay(for: Date())
        
        for subject in subjects {
            let subjectStart = Calendar.current.startOfDay(for: subject.startDateOfSubject)
            guard todayStart >= subjectStart else { continue }
            
            for schedule in subject.schedules ?? [] where schedule.day == todayString {
                for classTime in schedule.classTimes ?? [] {
                    todaysClasses.append((subject, classTime))
                }
            }
        }
        
        // Sort chronologically by start time
        todaysClasses.sort {
            normalizedTime(for: $0.classTime.startTime) < normalizedTime(for: $1.classTime.startTime)
        }
        return todaysClasses
    }
    
    /// Gets today's Day String to match the logic inside `TimeTableView.swift`
    private func currentDayString() -> String {
        let todayComponent = Calendar.current.component(.weekday, from: Date())
        switch todayComponent {
        case 2: return "Monday"
        case 3: return "Tuesday"
        case 4: return "Wednesday"
        case 5: return "Thursday"
        case 6: return "Friday"
        case 7: return "Saturday"
        case 1: return "Sunday"
        default: return ""
        }
    }
    
    /// Ensures `ClassTime` times are shifted onto *today's* actual date so `Date() >= start` works.
    private func normalizedTime(for timeDate: Date?) -> Date {
        guard let timeDate = timeDate else { return Date() }
        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute], from: timeDate)
        
        return calendar.date(bySettingHour: timeComponents.hour ?? 0,
                             minute: timeComponents.minute ?? 0,
                             second: 0,
                             of: Date()) ?? Date()
    }
}

// MARK: - Global Notification Definition
extension Notification.Name {
    // Allows DailyLogView to silently tell HomeView when the holiday state changes
    static let todayHolidayStateChanged = Notification.Name("todayHolidayStateChanged")
}
