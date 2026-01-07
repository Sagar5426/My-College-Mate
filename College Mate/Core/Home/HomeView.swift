//
//  HomeView.swift
//  College Mate
//
//  Created by Sagar Jangra on 03/01/2025.
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @EnvironmentObject var authService: AuthenticationService
    @Query var subjects: [Subject]
    
    @State private var selectedTab = "Subjects"
    
    var body: some View {
        
        TabView(selection: $selectedTab) {
            
            SubjectsView()
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
}


#Preview {
    HomeView()
}
