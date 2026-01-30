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
        var attendanceStatus: String // "Select", "Present", "Absent"
    }
    var subjectName: String
}

// 2. Intent to handle button taps
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

// 3. The Widget View
struct ClassActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ClassActivityAttributes.self) { context in
            // MARK: - Lock Screen UI
            ClassLiveActivityContentView(context: context, isLockScreen: true)
                .activityBackgroundTint(.black)
            
        } dynamicIsland: { context in
            DynamicIsland {
                // MARK: - Expanded UI
                
                // We move the Header to the .bottom region (as the first item)
                // This gives it full width so it won't clip.
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
                                .fixedSize() // Prevents text compression
                            
                            Spacer()
                        }
                        .padding(.bottom, 6) // Spacing between header and content
                        
                        // 2. Main Content
                        ClassLiveActivityContentView(context: context, isLockScreen: false)
                    }
                    // Apply padding here to avoid corner clipping
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
                }
                
            } compactLeading: {
                Image(systemName: "timer").fontWeight(.bold).foregroundStyle(.blue.gradient)
            } compactTrailing: {
                Text(context.state.endTime, style: .timer)
                    .foregroundStyle(.blue.gradient)
                    .frame(maxWidth: 50)
            } minimal: {
                Text(context.state.endTime, style: .timer)
                    .font(.system(size: 9, weight: .bold)).monospacedDigit()
                    .foregroundStyle(.blue.gradient)
            }
        }
    }
}

// 4. Shared Content View
extension ClassActivityWidget {
    struct ClassLiveActivityContentView: View {
        let context: ActivityViewContext<ClassActivityAttributes>
        var isLockScreen: Bool
        
        var body: some View {
            VStack(spacing: 0) {
                
                // HEADER (Only for Lock Screen; Island handles it externally)
                if isLockScreen {
                    HStack(spacing: 6) {
                        Image("CollegeHat")
                            .resizable().scaledToFit().frame(width:25, height: 25)
                            .background(Color.white.gradient)
                            .clipShape(Circle())
                        Text("My College Mate")
                            .font(.caption).fontWeight(.heavy).foregroundStyle(.white)
                        Spacer()
                    }
                    .padding(.bottom, 4)
                }
                
                // ROW 1: ROOMS & TIMER
                HStack(alignment: .top) {
                    // Current Room
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Current Room")
                            .font(isLockScreen ? .caption2 : .system(size: 9))
                            .foregroundStyle(.gray)
                        Text(context.state.currentRoom)
                            .font(isLockScreen ? .caption : .system(size: 11))
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    
                    // Center Timer
                    VStack(spacing: 0) {
                        Text("Class ends in")
                            .font(isLockScreen ? .caption2 : .system(size: 9))
                            .foregroundStyle(.gray)
                        Text(context.state.endTime, style: .timer)
                            .font(isLockScreen ? .caption : .system(size: 11))
                            .fontWeight(.bold).monospacedDigit()
                            .foregroundStyle(.white).multilineTextAlignment(.center)
                    }
                    .frame(minWidth: 70)
                    
                    Spacer()
                    
                    // Next Room
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("Next Room")
                            .font(isLockScreen ? .caption2 : .system(size: 9))
                            .foregroundStyle(.gray)
                        Text(context.state.nextRoom)
                            .font(isLockScreen ? .caption : .system(size: 11))
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                    }
                }
                
                // SPACER
                if isLockScreen {
                    Spacer()
                } else {
                    Spacer().frame(height: 4)
                }
                
                // ROW 2: INFO
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
                
                // ROW 3: BUTTONS
                HStack(spacing: 8) {
                    AttendanceButton(
                        label: "Select", value: "Select",
                        currentStatus: context.state.attendanceStatus,
                        color: Color.gray.gradient,
                        height: isLockScreen ? 30 : 26
                    )
                    AttendanceButton(
                        label: "Present", value: "Present",
                        currentStatus: context.state.attendanceStatus,
                        color: Color.green.gradient,
                        height: isLockScreen ? 30 : 26
                    )
                    AttendanceButton(
                        label: "Absent", value: "Absent",
                        currentStatus: context.state.attendanceStatus,
                        color: Color.red.gradient,
                        height: isLockScreen ? 30 : 26
                    )
                }
            }
            // PADDING LOGIC
            // Lock Screen uses internal padding.
            // Island uses 0 internal padding (handled by wrapper) to prevent double padding.
            .padding(isLockScreen ? 14 : 0)
        }
    }
}

// 5. Attendance Button
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

// MARK: - Previews
#Preview("Lock Screen", as: .content, using: ClassActivityAttributes(subjectName: "Internet of things")) {
    ClassActivityWidget()
} contentStates: {
    ClassActivityAttributes.ContentState(currentRoom: "302-A", nextRoom: "D-312", startTime: Date(), endTime: Date().addingTimeInterval(3600), attendanceStatus: "Select")
}

#Preview("Island Expanded", as: .dynamicIsland(.expanded), using: ClassActivityAttributes(subjectName: "CS")) {
    ClassActivityWidget()
} contentStates: {
    ClassActivityAttributes.ContentState(currentRoom: "302-A", nextRoom: "Lab-1", startTime: Date(), endTime: Date().addingTimeInterval(3600), attendanceStatus: "Select")
}

// 3. Preview for Dynamic Island (Compact)
#Preview("Island Compact", as: .dynamicIsland(.compact), using: ClassActivityAttributes(subjectName: "Computer Science")) {
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
