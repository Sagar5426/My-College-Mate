//  HomeView.swift
//  College Mate

import SwiftUI
import SwiftData
import ActivityKit // Import this

struct HomeView: View {
    @EnvironmentObject var authService: AuthenticationService
    @Query var subjects: [Subject]
    @State private var selectedTab = "Subjects"
    
    var body: some View {
        // ZStack allows us to float a button or just add it to one of the views
        TabView(selection: $selectedTab) {
            
            VStack {
                SubjectsView()
                
                // TEMPORARY BUTTON TO START ACTIVITY
                Button("Start Live Clock") {
                    startLiveActivity()
                }
                .buttonStyle(.borderedProminent)
                .padding()
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
    }
    
    // Function to start the Live Activity
    func startLiveActivity() {
        // Check if activities are enabled
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        
        // Define the static data
        let attributes = ClassActivityAttributes(subjectName: "Computer Science")
        
        // Define the dynamic state
        let state = ClassActivityAttributes.ContentState(
            currentRoom: "302-A",
            nextRoom: "Lab-1",
            startTime: Date(),
            endTime: Date().addingTimeInterval(3600)
        )
        
        // FIX: Wrap the state in ActivityContent
        let content = ActivityContent(state: state, staleDate: nil)
        
        do {
            // Use the new request signature
            let activity = try Activity.request(
                attributes: attributes,
                content: content,  // Pass 'content' instead of 'contentState'
                pushType: nil
            )
            print("Started Activity: \(activity.id)")
        } catch {
            print("Error: \(error.localizedDescription)")
        }
    }
}
