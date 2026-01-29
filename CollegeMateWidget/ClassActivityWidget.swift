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
    }
    // Static data (variables that don't change often)
    var subjectName: String
}

// 2. Define a Placeholder Intent for the Buttons
// (We need this because Live Activity buttons MUST perform an 'Intent')
struct PlaceholderIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Button Tap"
    
    // We can identify which button was tapped using this ID
    @Parameter(title: "Button ID")
    var buttonID: String
    
    init() {}
    
    init(id: String) {
        self.buttonID = id
    }
    
    func perform() async throws -> some IntentResult {
        // Logic will go here later
        print("Button \(buttonID) tapped")
        return .result()
    }
}

// 3. The Widget View
struct ClassActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ClassActivityAttributes.self) { context in
            // MARK: - Lock Screen / Banner UI
            VStack(spacing: 0) {
                
                // --- TOP ROW (Rooms) ---
                HStack(alignment: .top) {
                    // Top Leading: Current Room
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
                    VStack(alignment: .center, spacing: 2) {
                        Text("Class ends in")
                            .font(.caption2)
                            .foregroundStyle(.gray)
                        Text("30:34")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                    }
                    
                    Spacer()
                    
                    // Top Trailing: Next Room
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
                
                Spacer() // Pushes content to edges dynamically
                
                // --- MIDDLE ROW (Timing) ---
                HStack(alignment: .center) {
                    // Start Time
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Start")
                            .font(.caption2)
                            .foregroundStyle(.gray)
                        Text(context.state.startTime, style: .time)
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                    
                    Spacer()
                    
                    // End Time
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("End")
                            .font(.caption2)
                            .foregroundStyle(.gray)
                        Text(context.state.endTime, style: .time)
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                }
                .padding(.vertical, 8) // Reduced padding
                
                // --- BOTTOM ROW (Buttons) ---
                HStack(spacing: 15) {
                    // Button 1
                    Button(intent: PlaceholderIntent(id: "btn1")) {
                        ZStack {
                            Circle().fill(Color.white.opacity(0.15))
                            Image(systemName: "star.fill").font(.caption).foregroundStyle(.white)
                        }
                        .frame(width: 40, height: 40) // Fixed size to ensure fit
                    }
                    .buttonStyle(.plain) // Prevents default button borders
                    
                    // Button 2 (Wide Main Button)
                    Button(intent: PlaceholderIntent(id: "btn2")) {
                        ZStack {
                            Capsule().fill(Color.cyan)
                            Image(systemName: "checkmark").font(.headline).foregroundStyle(.black)
                        }
                        .frame(height: 40) // Reduced height slightly
                    }
                    .buttonStyle(.plain)
                    
                    // Button 3
                    Button(intent: PlaceholderIntent(id: "btn3")) {
                        ZStack {
                            Circle().fill(Color.white.opacity(0.15))
                            Image(systemName: "xmark").font(.caption).foregroundStyle(.white)
                        }
                        .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16) // Standard safe padding
            .activityBackgroundTint(Color.black.opacity(0.8))
            
        } dynamicIsland: { context in
            // MARK: - Dynamic Island Expanded
            // This ensures it looks good if expanded on iPhone 14/15 Pro
            DynamicIsland {
                // Expanded - Leading
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.currentRoom).font(.headline)
                }
                // Expanded - Trailing
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.nextRoom).font(.headline).foregroundStyle(.cyan)
                }
                // Expanded - Bottom (The Times)
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.startTime, style: .time)
                        Spacer()
                        Text(context.state.endTime, style: .time)
                    }
                    .padding(.top, 8)
                }
            } compactLeading: {
                Text(context.state.currentRoom)
            } compactTrailing: {
                Text(context.state.startTime, style: .time)
            } minimal: {
                Image(systemName: "clock")
            }
        }
    }
}

// MARK: - Previews

// 1. Preview for Lock Screen & Notification Center
#Preview("Lock Screen", as: .content, using: ClassActivityAttributes(subjectName: "Computer Science")) {
    ClassActivityWidget()
} contentStates: {
    ClassActivityAttributes.ContentState(
        currentRoom: "302-A",
        nextRoom: "D-312",
        startTime: Date(),
        endTime: Date().addingTimeInterval(3600)
    )
}

// 2. Preview for Dynamic Island (Expanded)
#Preview("Island Expanded", as: .dynamicIsland(.expanded), using: ClassActivityAttributes(subjectName: "Computer Science")) {
    ClassActivityWidget()
} contentStates: {
    ClassActivityAttributes.ContentState(
        currentRoom: "302-A",
        nextRoom: "Lab-1",
        startTime: Date(),
        endTime: Date().addingTimeInterval(3600)
    )
}

// 3. Preview for Dynamic Island (Compact)
#Preview("Island Compact", as: .dynamicIsland(.compact), using: ClassActivityAttributes(subjectName: "Computer Science")) {
    ClassActivityWidget()
} contentStates: {
    ClassActivityAttributes.ContentState(
        currentRoom: "302-A",
        nextRoom: "Lab-1",
        startTime: Date(),
        endTime: Date().addingTimeInterval(3600)
    )
}
