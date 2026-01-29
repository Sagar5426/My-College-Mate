import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

// 1. Define the Data Structure
struct ClassActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var currentRoom: String
        var nextRoom: String
        var startTime: Date
        var endTime: Date
        
        // Track the selected status
        // Options: "Select", "Present", "Absent"
        var attendanceStatus: String
    }
    // Static data
    var subjectName: String
}

// 2. Intent to handle button taps
struct UpdateAttendanceIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Update Attendance"
    
    // Accept the status we want to switch to
    @Parameter(title: "Status")
    var status: String
    
    init() {}
    
    init(status: String) {
        self.status = status
    }
    
    func perform() async throws -> some IntentResult {
        // 1. Iterate through all running Class Activities
        for activity in Activity<ClassActivityAttributes>.activities {
            
            // 2. Copy the CURRENT state so we don't lose the Room/Time info
            var updatedState = activity.content.state
            
            // 3. Update ONLY the attendance status
            updatedState.attendanceStatus = status
            
            // 4. Create the new content payload
            let updatedContent = ActivityContent(state: updatedState, staleDate: nil)
            
            // 5. Push the update to the UI
            await activity.update(updatedContent)
        }
        
        return .result()
    }
}

// 3. The Widget View
struct ClassActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ClassActivityAttributes.self) { context in
            ClassLiveActivityContentView(context: context)
                .activityBackgroundTint(.black)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                            ClassLiveActivityContentView(context: context)
                }
            } compactLeading: {
                    Image(systemName: "clock")
                        .fontWeight(.bold)
                        .foregroundStyle(.blue.gradient)

            } compactTrailing: {
                Text(context.state.endTime, style: .timer)
                        .foregroundStyle(.blue.gradient)
                        .frame(maxWidth: 60)

                } minimal: {
                    Text(context.state.endTime, style: .timer)
                        .font(.system(size: 9, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.blue.gradient)
                }
            }

    }
}

// 4. Helper View Component for the Menu Buttons
struct AttendanceButton: View {
    let label: String
    let value: String
    let currentStatus: String
    let color: AnyGradient
    
    var isSelected: Bool {
        currentStatus == value
    }
    
    var body: some View {
        Button(intent: UpdateAttendanceIntent(status: value)) {
            ZStack {
                // Background Logic
                if isSelected {
                    Capsule()
                        .fill(color == Color.gray.gradient ? Color.white.gradient : color)
                } else {
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                        .background(Color.white.opacity(0.05).clipShape(Capsule()))
                }
                
                // Text Logic
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(isSelected ? (color == Color.gray.gradient ? Color.black.gradient : Color.black.gradient) : Color.white.gradient)
            }
            .frame(height: 36)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview("Lock Screen", as: .content, using: ClassActivityAttributes(subjectName: "Internet Of Things")) {
    ClassActivityWidget()
} contentStates: {
    ClassActivityAttributes.ContentState(
        currentRoom: "302-A",
        nextRoom: "D-312",
        startTime: Date(),
        endTime: Date().addingTimeInterval(3600),
        attendanceStatus: "Select"
    )
    
    ClassActivityAttributes.ContentState(
        currentRoom: "302-A",
        nextRoom: "D-312",
        startTime: Date(),
        endTime: Date().addingTimeInterval(3600),
        attendanceStatus: "Present"
    )
}

#Preview("Island Expanded", as: .dynamicIsland(.expanded), using: ClassActivityAttributes(subjectName: "Computer Science")) {
    ClassActivityWidget()
} contentStates: {
    ClassActivityAttributes.ContentState(
        currentRoom: "302-A",
        nextRoom: "Lab-1",
        startTime: Date(),
        endTime: Date().addingTimeInterval(3600),
        attendanceStatus: "Select"
    )
}

#Preview("Island Compact", as: .dynamicIsland(.minimal), using: ClassActivityAttributes(subjectName: "Computer Science")) {
    ClassActivityWidget()
} contentStates: {
    ClassActivityAttributes.ContentState(
        currentRoom: "302-A",
        nextRoom: "Lab-1",
        startTime: Date(),
        endTime: Date().addingTimeInterval(3600),
        attendanceStatus: "Select"
    )
}


extension ClassActivityWidget {
    struct ClassLiveActivityContentView: View {
        let context: ActivityViewContext<ClassActivityAttributes>

        var body: some View {
            VStack(spacing: 0) {

                // Header
                HStack(spacing: 6) {
                    Image("CollegeHat")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .background(Color.white.gradient)
                        .cornerRadius(20)

                    Text("My College Mate")
                        .font(.caption)
                        .fontWeight(.heavy)
                        .foregroundStyle(.white)

                    Spacer()
                }
                .padding(.bottom, 8)
                .padding(.top, 4)

                // Rooms + Countdown (FIXED)
                HStack {
                    // Current Room
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Current Room")
                            .font(.caption2)
                            .foregroundStyle(.gray)
                        Text(context.state.currentRoom)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    // ⬇️ CENTERED TIMER (this was the bug)
                    VStack(spacing: 2) {
                        Text("Class ends in")
                            .font(.caption2)
                            .foregroundStyle(.gray)

                        Text(context.state.endTime, style: .timer)
                            .font(.caption)
                            .fontWeight(.bold)
                            .monospacedDigit()   // 🔥 critical
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                    }
                    .frame(minWidth: 80) // stabilizes center column

                    Spacer()

                    // Next Room
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Next Room")
                            .font(.caption2)
                            .foregroundStyle(.gray)
                        Text(context.state.nextRoom)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                    }
                }

                // Subject + timing (UNCHANGED – already correct)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Start")
                            .font(.caption2)
                            .foregroundStyle(.gray)
                        Text(context.state.startTime, style: .time)
                            .font(.caption)
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    Text(context.attributes.subjectName)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("End")
                            .font(.caption2)
                            .foregroundStyle(.gray)
                        Text(context.state.endTime, style: .time)
                            .font(.caption)
                            .foregroundStyle(.white)
                    }
                }
                .padding(.vertical, 12)

                // Buttons
                HStack(spacing: 10) {
                    AttendanceButton(
                        label: "Select",
                        value: "Select",
                        currentStatus: context.state.attendanceStatus,
                        color: Color.gray.gradient
                    )

                    AttendanceButton(
                        label: "Present",
                        value: "Present",
                        currentStatus: context.state.attendanceStatus,
                        color: Color.green.gradient
                    )

                    AttendanceButton(
                        label: "Absent",
                        value: "Absent",
                        currentStatus: context.state.attendanceStatus,
                        color: Color.red.gradient
                    )
                }
            }
            .padding(16)
        }
    }


}
