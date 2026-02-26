import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

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
    
    init() {}
    init(status: String) { self.status = status }
    
    func perform() async throws -> some IntentResult {
        for activity in Activity<ClassActivityAttributes>.activities {
            var updatedState = activity.content.state
            updatedState.attendanceStatus = status
            await activity.update(ActivityContent(state: updatedState, staleDate: nil))
        }
        return .result()
    }
}

// MARK: - 3. The Main Widget Configuration
struct ClassActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ClassActivityAttributes.self) { context in
            // MARK: - Lock Screen UI
            // This view now handles the logic to switch between the 3 states
            ClassLiveActivityContentView(context: context, isLockScreen: true)
                .activityBackgroundTint(.black)
            
        } dynamicIsland: { context in
            DynamicIsland {
                // MARK: - Expanded UI
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 0) {
                        // 1. Header (Icon + Name)
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
                        
                        // 2. Main Content (Reused logic)
                        ClassLiveActivityContentView(context: context, isLockScreen: false)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
                }
                
            } compactLeading: {
                // MARK: Compact Leading (Icon)
                Image(systemName: "timer")
                    .fontWeight(.bold)
                    // MUST be Solid Blue for performance
                    .foregroundStyle(.blue)
                
            } compactTrailing: {
                // MARK: Compact Trailing (Timer)
                // Wrapped in HStack to prevent layout jitter
                HStack(alignment: .center) {
                    Text(timerInterval: context.state.startTime...context.state.endTime, countsDown: true)
                        .monospacedDigit()
                        .font(.system(size: 13, weight: .semibold))
                        // MUST be Solid Blue (No Gradient) to tick smoothly
                        .foregroundStyle(.blue)
                        .multilineTextAlignment(.center)
                }
                .frame(width: 64) // Fixed width prevents clipping
                
            } minimal: {
                // MARK: Minimal (Tiny Timer)
                Text(timerInterval: context.state.startTime...context.state.endTime, countsDown: true)
                    .monospacedDigit()
                    .font(.system(size: 8, weight: .bold))
                    // MUST be Solid Blue
                    .foregroundStyle(.blue)
                    .multilineTextAlignment(.center)
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

// SCENARIO 1: Ongoing Class (Original Design with Correct Alignment)
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
                // Restored .frame(minWidth: 70) and .multilineTextAlignment(.center)
                VStack(spacing: 0) {
                    Text("Class ends in").font(isLockScreen ? .caption2 : .system(size: 9)).foregroundStyle(.gray)
                    Text(context.state.endTime, style: .timer)
                        .font(isLockScreen ? .caption : .system(size: 11))
                        .fontWeight(.bold).monospacedDigit().foregroundStyle(.white)
                        .multilineTextAlignment(.center) // <--- ALIGNMENT RESTORED
                }
                .frame(minWidth: 70) // <--- ALIGNMENT FRAME RESTORED
                
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
                AttendanceButton(label: "Select", value: "Select", currentStatus: context.state.attendanceStatus, color: Color.gray.gradient, height: isLockScreen ? 30 : 26)
                AttendanceButton(label: "Present", value: "Present", currentStatus: context.state.attendanceStatus, color: Color.green.gradient, height: isLockScreen ? 30 : 26)
                AttendanceButton(label: "Absent", value: "Absent", currentStatus: context.state.attendanceStatus, color: Color.red.gradient, height: isLockScreen ? 30 : 26)
            }
        }
        .padding(isLockScreen ? 14 : 0)
    }
}

// SCENARIO 2: Break Time (Next Class Countdown)
struct BreakTimeView: View {
    let context: ActivityViewContext<ClassActivityAttributes>
    var isLockScreen: Bool
    
    // Helper to check if the timer has crossed 0:00
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
                // CHANGED: Dynamic label based on if the break is over
                Text(isLate ? "Late by:" : "Next class starts in:")
                    .font(.caption2)
                    .foregroundStyle(isLate ? .red : .gray) // Turns red if late
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
    let color: AnyGradient
    let height: CGFloat
    
    var isSelected: Bool { currentStatus == value }
    
    var body: some View {
        Button(intent: UpdateAttendanceIntent(status: value)) {
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

// Preview 1: Lock Screen (Ongoing Class)
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

// Preview 2: Lock Screen (Break Time)
#Preview("Lock Screen - Break", as: .content, using: ClassActivityAttributes(subjectName: "Operating Systems")) {
    ClassActivityWidget()
} contentStates: {
    ClassActivityAttributes.ContentState(
        sessionType: .breakTime, // Flag triggers Break UI
        currentRoom: "N/A", nextRoom: "D-202",
        startTime: Date(), endTime: Date().addingTimeInterval(900), // 15 min break
        attendanceStatus: "Select"
    )
}

// Preview 3: Lock Screen (Day Ended)
#Preview("Lock Screen - End", as: .content, using: ClassActivityAttributes(subjectName: "")) {
    ClassActivityWidget()
} contentStates: {
    ClassActivityAttributes.ContentState(
        sessionType: .dayEnded, // Flag triggers End UI
        currentRoom: "", nextRoom: "",
        startTime: Date(), endTime: Date(),
        attendanceStatus: ""
    )
}

// Preview 4: Dynamic Island (Compact)
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
