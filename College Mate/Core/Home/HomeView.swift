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
    
    // MARK: - Live Activity Sync Properties
    @State private var refreshID = UUID()
    @AppStorage("widgetAttendanceUpdate", store: UserDefaults(suiteName: SharedAppGroup.id)) private var widgetAttendanceUpdate: Double = 0
    @State private var lastSyncTime: Double = 0
    
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
        .id(refreshID) // Forces the views to reload SwiftData when this ID changes
        .tint(.cyan)
        .environment(\.colorScheme, .dark)
        .sensoryFeedback(.selection, trigger: selectedTab)
        .onAppear {
            refreshLiveActivity()
            lastSyncTime = widgetAttendanceUpdate // Initialize the sync tracker
        }
        // 1. Listen for app state changes (coming back from background)
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                refreshLiveActivity()
                
                // Detect if the Widget updated the database while the app was closed/in background
                if widgetAttendanceUpdate > lastSyncTime {
                    refreshID = UUID() // Triggers UI to fetch fresh SwiftData
                    lastSyncTime = widgetAttendanceUpdate
                }
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
                Task {
                    for activity in Activity<ClassActivityAttributes>.activities {
                        await activity.end(nil, dismissalPolicy: .immediate)
                    }
                }
                return
            }
            
            // 2. Fetch & sort today's classes
            let todayClasses = getTodaysClasses()
            
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
                var end = normalizedTime(for: item.classTime.endTime)
                
                // FIX: If the class crosses midnight (PM to AM), move the end time to the next day
                if end < start {
                    end = Calendar.current.date(byAdding: .day, value: 1, to: end) ?? end
                }
                
                if now >= start && now <= end {
                    currentClass = item
                } else if start > now && nextClass == nil {
                    nextClass = item
                }
            }
            
            // 4. Check if it's been more than 1 hour since the last class ended
            if currentClass == nil && nextClass == nil, let lastClass = todayClasses.last {
                let lastClassStart = normalizedTime(for: lastClass.classTime.startTime)
                var lastClassEnd = normalizedTime(for: lastClass.classTime.endTime)
                
                // Apply the midnight fix here as well
                if lastClassEnd < lastClassStart {
                    lastClassEnd = Calendar.current.date(byAdding: .day, value: 1, to: lastClassEnd) ?? lastClassEnd
                }
                
                if now > lastClassEnd.addingTimeInterval(3600) { // 3600 seconds = 1 hour
                    Task {
                        for activity in Activity<ClassActivityAttributes>.activities {
                            await activity.end(nil, dismissalPolicy: .immediate)
                        }
                    }
                    return
                }
            }
            
            // 5. Build State Variables based on the ActivityWidget UI Scenarios
            let sessionType: ClassActivityAttributes.ContentState.SessionType
            let subjectName: String
            let currentRoom: String
            let nextRoom: String
            let startTime: Date
            let endTime: Date
            
            var currentAttendanceStatus = "Select"
            
            if let current = currentClass {
                // SCENARIO 1: Class is happening right now
                sessionType = .ongoingClass
                subjectName = current.0.name
                currentRoom = current.1.roomNumber
                nextRoom = nextClass?.1.roomNumber ?? "None"
                startTime = normalizedTime(for: current.1.startTime)
                
                // Ensure the UI also knows if the end time is tomorrow
                var end = normalizedTime(for: current.1.endTime)
                if end < startTime {
                    end = Calendar.current.date(byAdding: .day, value: 1, to: end) ?? end
                }
                endTime = end
                
                if let existingActivity = Activity<ClassActivityAttributes>.activities.first(where: { $0.attributes.subjectName == subjectName }) {
                    if existingActivity.content.state.startTime == startTime {
                        currentAttendanceStatus = existingActivity.content.state.attendanceStatus
                    }
                }
                
            } else if let next = nextClass {
                // SCENARIO 2: On break, waiting for the next class
                sessionType = .breakTime
                subjectName = next.0.name
                currentRoom = "N/A"
                nextRoom = next.1.roomNumber
                startTime = Date()
                endTime = normalizedTime(for: next.1.startTime)
                
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
                
                // Schedule an automatic refresh to kill the widget 1 hour after the last class
                if let lastClass = todayClasses.last {
                    let lastClassStart = normalizedTime(for: lastClass.classTime.startTime)
                    var lastClassEnd = normalizedTime(for: lastClass.classTime.endTime)
                    
                    if lastClassEnd < lastClassStart {
                        lastClassEnd = Calendar.current.date(byAdding: .day, value: 1, to: lastClassEnd) ?? lastClassEnd
                    }
                    
                    let killTime = lastClassEnd.addingTimeInterval(3600)
                    let timeUntilKill = killTime.timeIntervalSinceNow
                    
                    if timeUntilKill > 0 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + timeUntilKill) {
                            self.refreshLiveActivity()
                        }
                    }
                }
            }
            
            // 6. Request or Update the Activity
            let attributes = ClassActivityAttributes(subjectName: subjectName)
            let state = ClassActivityAttributes.ContentState(
                sessionType: sessionType,
                currentRoom: currentRoom,
                nextRoom: nextRoom,
                startTime: startTime,
                endTime: endTime,
                attendanceStatus: currentAttendanceStatus,
                isLate: Date() > endTime
            )
            let content = ActivityContent(state: state, staleDate: nil)
            
            Task {
                if let currentActivity = Activity<ClassActivityAttributes>.activities.first {
                    await currentActivity.update(content)
                } else {
                    do {
                        _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
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
