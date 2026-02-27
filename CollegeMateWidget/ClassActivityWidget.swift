import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents
import SwiftData // Required for SharedModelContainer

// MARK: - 1. Data Model & Attributes
struct ClassActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // The flag to switch between designs
        enum SessionType: String, Codable {
            case ongoingClass  // 1. Class is happening
            case breakTime     // 2. Break between classes
            case dayEnded      // 3. No more classes today
        }
        
        var sessionType: SessionType = .ongoingClass
        
        var currentRoom: String
        var nextRoom: String
        var startTime: Date
        var endTime: Date
        var attendanceStatus: String // "Select", "Present", "Absent"
        var isLate: Bool = false
    }
    
    var subjectName: String
}

// MARK: - 2. Intent (Button Action)
struct UpdateAttendanceIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Update Attendance"
    
    @Parameter(title: "Status") var status: String
    @Parameter(title: "Subject Name") var subjectName: String
    
    init() {}
    
    init(status: String, subjectName: String) {
        self.status = status
        self.subjectName = subjectName
    }
    
    func perform() async throws -> some IntentResult {
        // 1. Find the CURRENT status from the active Live Activity to know what we are changing from
        var previousStatus = "Select"
        for activity in Activity<ClassActivityAttributes>.activities {
            if activity.attributes.subjectName == subjectName {
                previousStatus = activity.content.state.attendanceStatus
            }
        }
        
        // If the user tapped the button that is already selected, do nothing
        guard previousStatus != status else { return .result() }
        
        // 2. Safely update SwiftData
        do {
            let container = try SharedModelContainer.make()
            let context = ModelContext(container)
            
            let targetSubjectName = self.subjectName
            let descriptor = FetchDescriptor<Subject>(predicate: #Predicate { $0.name == targetSubjectName })
            
            if let subject = try context.fetch(descriptor).first {
                
                // --- A. DETERMINE THE LOG MESSAGE ---
                var logMessage = ""
                if status == "Present" {
                    logMessage = "Marked as Present"
                } else if status == "Absent" {
                    logMessage = "Marked as Absent"
                } else if status == "Select" {
                    if previousStatus == "Present" {
                        logMessage = "Present status reverted"
                    } else if previousStatus == "Absent" {
                        logMessage = "Absent status reverted"
                    }
                }
                
                // Add the log entry
                if !logMessage.isEmpty {
                    let log = AttendanceLogEntry(timestamp: Date(), subjectName: targetSubjectName, action: logMessage)
                    subject.logs.append(log)
                }
                
                // --- B. UPDATE ATTENDANCE COUNTS ---
                // Step 1: Revert the math from the previous status
                if previousStatus == "Present" {
                    subject.attendance?.attendedClasses = max(0, (subject.attendance?.attendedClasses ?? 0) - 1)
                    subject.attendance?.totalClasses = max(0, (subject.attendance?.totalClasses ?? 0) - 1)
                } else if previousStatus == "Absent" {
                    subject.attendance?.totalClasses = max(0, (subject.attendance?.totalClasses ?? 0) - 1)
                }
                
                // Step 2: Apply the math for the new status
                if status == "Present" {
                    subject.attendance?.attendedClasses = (subject.attendance?.attendedClasses ?? 0) + 1
                    subject.attendance?.totalClasses = (subject.attendance?.totalClasses ?? 0) + 1
                } else if status == "Absent" {
                    subject.attendance?.totalClasses = (subject.attendance?.totalClasses ?? 0) + 1
                }
                
                // Save the changes
                try context.save()
                
                // Signal the main app that Widget data has changed!
                if let defaults = UserDefaults(suiteName: "group.com.sagarjangra.College-Mate") {
                    defaults.set(Date().timeIntervalSince1970, forKey: "widgetAttendanceUpdate")
                }
            }
        } catch {
            print("Widget Database Error: \(error.localizedDescription)")
        }

        // 3. Update the Live Activity UI
        for activity in Activity<ClassActivityAttributes>.activities {
            if activity.attributes.subjectName == subjectName {
                var updatedState = activity.content.state
                updatedState.attendanceStatus = status
                await activity.update(ActivityContent(state: updatedState, staleDate: nil))
            }
        }
        return .result()
    }
}

// MARK: - 3. The Main Widget Configuration
struct ClassActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ClassActivityAttributes.self) { context in
            // MARK: - Lock Screen UI
            ClassLiveActivityContentView(context: context, isLockScreen: true)
                .activityBackgroundTint(.black)
            
        } dynamicIsland: { context in
            DynamicIsland {
                // MARK: - Expanded UI
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 0) {
                        // Header (Icon + Name)
                        HStack(spacing: 6) {
                            Image("CollegeHat")
                                .resizable().scaledToFit().frame(width: 16, height: 16)
                                .background(Color.white.gradient)
                                .clipShape(Circle())
                            
                            Text("My College Mate")
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(.white)
                                .fixedSize()
                            
                            Spacer()
                        }
                        .padding(.bottom, 6)
                        
                        // Main Content
                        ClassLiveActivityContentView(context: context, isLockScreen: false)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
                }
                
            } compactLeading: {
                // MARK: Compact Leading (Icon)
                Image(systemName: "timer")
                    .fontWeight(.bold)
                    .foregroundStyle(.blue)
                
            } compactTrailing: {
                // MARK: Compact Trailing (Timer)
                HStack(alignment: .center) {
                    Text(timerInterval: context.state.startTime...context.state.endTime, countsDown: true)
                        .monospacedDigit()
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.blue)
                        .multilineTextAlignment(.center)
                        .padding(.leading, 2)
                }
                .frame(width: 64)
                
            } minimal: {
                // MARK: Minimal (Tiny Timer)
                Text(timerInterval: context.state.startTime...context.state.endTime, countsDown: true)
                    .monospacedDigit()
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.blue)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
    }
}

// MARK: - 4. Content Logic (The Switcher)
extension ClassActivityWidget {
    struct ClassLiveActivityContentView: View {
        let context: ActivityViewContext<ClassActivityAttributes>
        var isLockScreen: Bool
        
        var body: some View {
            // Switch designs based on the session state
            switch context.state.sessionType {
            case .ongoingClass:
                OngoingClassView(context: context, isLockScreen: isLockScreen)
            case .breakTime:
                BreakTimeView(context: context, isLockScreen: isLockScreen)
            case .dayEnded:
                DayEndedView(context: context, isLockScreen: isLockScreen)
            }
        }
    }
}

// MARK: - 5. Scenario Views

// SCENARIO 1: Ongoing Class
struct OngoingClassView: View {
    let context: ActivityViewContext<ClassActivityAttributes>
    var isLockScreen: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header (Only for Lock Screen)
            if isLockScreen {
                HStack(spacing: 6) {
                    Image("CollegeHat")
                        .resizable().scaledToFit().frame(width:25, height: 25)
                        .background(Color.white.gradient).clipShape(Circle())
                    Text("My College Mate").font(.caption).fontWeight(.heavy).foregroundStyle(.white)
                    Spacer()
                }
                .padding(.bottom, 4)
            }
            
            // Info Row (Room | Timer | Room)
            HStack(alignment: .top) {
                // Left: Current Room
                VStack(alignment: .leading, spacing: 0) {
                    Text("Current Room").font(isLockScreen ? .caption2 : .system(size: 9)).foregroundStyle(.gray)
                    Text(context.state.currentRoom).font(isLockScreen ? .caption : .system(size: 11)).fontWeight(.bold).foregroundStyle(.white)
                }
                
                Spacer()
                
                // Center: Timer
                VStack(spacing: 0) {
                    Text("Class ends in").font(isLockScreen ? .caption2 : .system(size: 9)).foregroundStyle(.gray)
                    Text(context.state.endTime, style: .timer)
                        .font(isLockScreen ? .caption : .system(size: 11))
                        .fontWeight(.bold).monospacedDigit().foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                }
                .frame(minWidth: 70)
                
                Spacer()
                
                // Right: Next Room
                VStack(alignment: .trailing, spacing: 0) {
                    Text("Next Room").font(isLockScreen ? .caption2 : .system(size: 9)).foregroundStyle(.gray)
                    Text(context.state.nextRoom).font(isLockScreen ? .caption : .system(size: 11)).fontWeight(.bold).foregroundStyle(.white)
                }
            }
            
            Spacer().frame(height: isLockScreen ? nil : 4)
            
            // Subject Name
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Start").font(isLockScreen ? .caption2 : .system(size: 9)).foregroundStyle(.gray)
                    Text(context.state.startTime, style: .time).font(isLockScreen ? .caption : .system(size: 10)).foregroundStyle(.white)
                }
                Spacer()
                Text(context.attributes.subjectName)
                    .font(isLockScreen ? .headline : .system(size: 14))
                    .fontWeight(.bold).foregroundStyle(.white).lineLimit(1)
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("End").font(isLockScreen ? .caption2 : .system(size: 9)).foregroundStyle(.gray)
                    Text(context.state.endTime, style: .time).font(isLockScreen ? .caption : .system(size: 10)).foregroundStyle(.white)
                }
            }
            .padding(.vertical, isLockScreen ? 8 : 4)
            
            // Buttons
            HStack(spacing: 8) {
                AttendanceButton(label: "Select", value: "Select", currentStatus: context.state.attendanceStatus, subjectName: context.attributes.subjectName, color: Color.gray.gradient, height: isLockScreen ? 30 : 26)
                
                AttendanceButton(label: "Present", value: "Present", currentStatus: context.state.attendanceStatus, subjectName: context.attributes.subjectName, color: Color.green.gradient, height: isLockScreen ? 30 : 26)
                
                AttendanceButton(label: "Absent", value: "Absent", currentStatus: context.state.attendanceStatus, subjectName: context.attributes.subjectName, color: Color.red.gradient, height: isLockScreen ? 30 : 26)
            }
        }
        .padding(isLockScreen ? 14 : 0)
    }
}

// SCENARIO 2: Break Time
struct BreakTimeView: View {
    let context: ActivityViewContext<ClassActivityAttributes>
    var isLockScreen: Bool
    
    var isLate: Bool {
        Date() > context.state.endTime
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "cup.and.saucer.fill").foregroundStyle(.orange)
                Text("Break Time").font(.caption).fontWeight(.heavy).foregroundStyle(.orange)
                Spacer()
                Text(isLate ? "Late by:" : "Next class starts in:")
                    .font(.caption2)
                    .foregroundStyle(isLate ? .red : .gray)
                    .bold()
            }
            .padding(.bottom, 8)
            
            HStack(alignment: .center) {
                // Next Subject Info
                VStack(alignment: .leading, spacing: 2) {
                    Text("UP NEXT").font(.caption2).fontWeight(.bold).foregroundStyle(.gray)
                    Text(context.attributes.subjectName)
                        .font(.headline).fontWeight(.bold).foregroundStyle(.white)
                    HStack {
                        Image(systemName: "location.fill").font(.caption2).foregroundStyle(.gray)
                        Text(context.state.nextRoom).font(.caption).foregroundStyle(.gray)
                    }
                }
                Spacer()
                // Big Countdown to Start
                VStack(alignment: .trailing) {
                    Text(context.state.endTime, style: .timer)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isLate ? .red : .orange)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(isLockScreen ? 14 : 0)
    }
}

// SCENARIO 3: Day Ended
struct DayEndedView: View {
    let context: ActivityViewContext<ClassActivityAttributes>
    var isLockScreen: Bool
    
    var body: some View {
        HStack(spacing: 15) {
            ZStack {
                Circle().fill(Color.green.opacity(0.2)).frame(width: 44, height: 44)
                Image(systemName: "checkmark.seal.fill").font(.title2).foregroundStyle(.green)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("All Caught Up!").font(.headline).fontWeight(.heavy).foregroundStyle(.white)
                Text("No more classes today.").font(.caption).foregroundStyle(.gray)
            }
            Spacer()
        }
        .padding(isLockScreen ? 14 : 0)
    }
}

// Helper: Attendance Button
struct AttendanceButton: View {
    let label: String
    let value: String
    let currentStatus: String
    let subjectName: String // Added property
    let color: AnyGradient
    let height: CGFloat
    
    var isSelected: Bool { currentStatus == value }
    
    var body: some View {
        Button(intent: UpdateAttendanceIntent(status: value, subjectName: subjectName)) {
            ZStack {
                if isSelected {
                    Capsule().fill(color == Color.gray.gradient ? Color.white.gradient : color)
                } else {
                    Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                        .background(Color.white.opacity(0.05).clipShape(Capsule()))
                }
                Text(label)
                    .font(.system(size: height * 0.4))
                    .fontWeight(.bold)
                    .foregroundStyle(isSelected ? (color == Color.gray.gradient ? Color.black.gradient : Color.black.gradient) : Color.white.gradient)
            }
            .frame(height: height)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 6. All Previews

#Preview("Lock Screen - Active", as: .content, using: ClassActivityAttributes(subjectName: "Computer Networks")) {
    ClassActivityWidget()
} contentStates: {
    ClassActivityAttributes.ContentState(
        sessionType: .ongoingClass,
        currentRoom: "302-A", nextRoom: "Lab-1",
        startTime: Date(), endTime: Date().addingTimeInterval(3600),
        attendanceStatus: "Select"
    )
}

#Preview("Lock Screen - Break", as: .content, using: ClassActivityAttributes(subjectName: "Operating Systems")) {
    ClassActivityWidget()
} contentStates: {
    ClassActivityAttributes.ContentState(
        sessionType: .breakTime,
        currentRoom: "N/A", nextRoom: "D-202",
        startTime: Date(), endTime: Date().addingTimeInterval(900),
        attendanceStatus: "Select"
    )
}

#Preview("Lock Screen - End", as: .content, using: ClassActivityAttributes(subjectName: "")) {
    ClassActivityWidget()
} contentStates: {
    ClassActivityAttributes.ContentState(
        sessionType: .dayEnded,
        currentRoom: "", nextRoom: "",
        startTime: Date(), endTime: Date(),
        attendanceStatus: ""
    )
}

#Preview("Island Compact", as: .dynamicIsland(.compact), using: ClassActivityAttributes(subjectName: "CS")) {
    ClassActivityWidget()
} contentStates: {
    ClassActivityAttributes.ContentState(
        sessionType: .ongoingClass,
        currentRoom: "302", nextRoom: "303",
        startTime: Date(), endTime: Date().addingTimeInterval(3600),
        attendanceStatus: "Select"
    )
}
