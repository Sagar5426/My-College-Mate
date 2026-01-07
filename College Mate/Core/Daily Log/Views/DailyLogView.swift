import SwiftUI
import SwiftData
import CoreData

struct DailyLogView: View {
    @Environment(\.modelContext) private var modelContext
    @Query var subjects: [Subject]
    
    @StateObject private var viewModel = DailyLogViewModel()
    
    // MARK: - Animation State
    @State private var viewID = UUID()
    @State private var slideDirection: SlideDirection = .forward
    
    enum SlideDirection {
        case forward
        case backward
    }
    
    // Custom asymmetric transition
    var customSlideTransition: AnyTransition {
        switch slideDirection {
        case .forward:
            return .asymmetric(
                insertion: .move(edge: .trailing),
                removal: .move(edge: .leading)
            )
        case .backward:
            return .asymmetric(
                insertion: .move(edge: .leading),
                removal: .move(edge: .trailing)
            )
        }
    }
    
    // Using a slightly more damped spring for stability
    var springAnimation: Animation {
        .spring(response: 0.5, dampingFraction: 0.8)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                LazyVStack(spacing: 16, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ControlPanelView(
                            viewModel: viewModel,
                            viewID: viewID,
                            transition: customSlideTransition,
                            onPrevious: animateToPreviousDay,
                            onNext: animateToNextDay
                        )
                        
                        Divider().padding(.vertical)
                        
                        ClassesList(viewModel: viewModel)
                            .id(viewID)
                            .transition(customSlideTransition)
                        
                    } header: {
                        GeometryReader { proxy in
                            HeaderView(size: proxy.size, title: "Attendance 🙋", isShowingProfileView: $viewModel.isShowingProfileView)
                        }
                        .frame(height: 50)
                    }
                }
                .padding()
            }
            .background(LinearGradient.appBackground.ignoresSafeArea())
            .blur(radius: viewModel.isShowingDatePicker ? 8 : 0)
            .disabled(viewModel.isShowingDatePicker)
            .fullScreenCover(isPresented: $viewModel.isShowingProfileView) {
                ProfileView(isShowingProfileView: $viewModel.isShowingProfileView)
            }
            .overlay {
                if viewModel.isShowingDatePicker {
                    DateFilterView(
                        start: viewModel.selectedDate,
                        onSubmit: { start in
                            animateDateJump(to: start)
                            viewModel.isShowingDatePicker = false
                        },
                        onClose: {
                            viewModel.isShowingDatePicker = false
                        }
                    )
                    .transition(.move(edge: .leading))
                }
            }
            // Handle CoreData notifications if needed
            .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange)) { _ in }
        }
        .animation(.spring(duration: 0.4), value: viewModel.isShowingDatePicker)
        .onAppear {
            viewModel.setup(subjects: subjects, modelContext: modelContext)
        }
        .onChange(of: subjects) {
            viewModel.setup(subjects: subjects, modelContext: modelContext)
        }
    }
    
    // MARK: - Animation Handlers
    
    func animateToPreviousDay() {
        slideDirection = .backward
        withAnimation(springAnimation) {
            viewModel.moveToPreviousDay()
            viewID = UUID()
        }
    }
    
    func animateToNextDay() {
        slideDirection = .forward
        withAnimation(springAnimation) {
            viewModel.moveToNextDay()
            viewID = UUID()
        }
    }
    
    func animateDateJump(to newDate: Date) {
        if newDate > viewModel.selectedDate {
            slideDirection = .forward
        } else {
            slideDirection = .backward
        }
        
        withAnimation(springAnimation) {
            viewModel.selectedDate = newDate
            viewID = UUID()
        }
    }
}

// MARK: - Control Panel View
struct ControlPanelView: View {
    @ObservedObject var viewModel: DailyLogViewModel
    
    let viewID: UUID
    let transition: AnyTransition
    
    var onPrevious: () -> Void
    var onNext: () -> Void
    
    private var isNextDayDisabled: Bool { Calendar.current.isDateInToday(viewModel.selectedDate) }
    
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 0) { // spacing 0 ensures strict control over layout
                
                // LEFT CHEVRON (Static)
                Button(action: {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    onPrevious()
                }) {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.title)
                        .padding(.trailing, 8)
                }
                
                ZStack {
                    Button(action: {
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        withAnimation(.snappy) {
                            viewModel.isShowingDatePicker.toggle()
                        }
                    }) {
                        Text(viewModel.selectedDate.formatted(.dateTime.day().month(.wide).year().weekday(.wide)))
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .id(viewID)
                            .transition(transition)
                            .frame(maxWidth: .infinity)                     }
                    .buttonStyle(.plain)
                }
                .frame(height: 30)
                .frame(maxWidth: .infinity)
                .compositingGroup()
                .clipped()
                
                // RIGHT CHEVRON (Static)
                Button(action: {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    onNext()
                }) {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.title)
                        .padding(.leading, 8)
                }
                .disabled(isNextDayDisabled)
                .opacity(isNextDayDisabled ? 0.5 : 1.0)
            }
            .foregroundStyle(.blue)
            
            if !viewModel.dailyClasses.isEmpty {
                Button(action: {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    withAnimation {
                        viewModel.toggleHoliday()
                    }
                }) {
                    Text(viewModel.isHoliday ? "Marked as Holiday" : "Mark Today as Holiday")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(viewModel.isHoliday ? .orange.opacity(0.8) : .gray.opacity(0.2))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .animation(.easeOut(duration: 0.25), value: viewModel.dailyClasses.isEmpty)
    }
}


// MARK: - Classes List
struct ClassesList: View {
    @ObservedObject var viewModel: DailyLogViewModel
    
    var body: some View {
        // ZStack ensures the layout container exists before/after transition
        // preventing the "double view" glitch where they fight for layout space.
        ZStack(alignment: .top) {
            if viewModel.isHoliday {
                VStack(spacing: 10) {
                    Image(systemName: "sun.max.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text("Enjoy your holiday!")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 50)
                
            } else if viewModel.dailyClasses.isEmpty {
                Text("No classes scheduled for this day.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(viewModel.dailyClasses) { item in
                        ClassAttendanceRow(
                            subject: item.subject,
                            classTime: item.classTime,
                            record: item.record,
                            viewModel: viewModel
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
        }
    }
}

// MARK: - Class Attendance Row (Unchanged)
struct ClassAttendanceRow: View {
    let subject: Subject
    let classTime: ClassTime
    let record: AttendanceRecord
    @ObservedObject var viewModel: DailyLogViewModel
    
    @State private var rotation: Double = 0.0
    
    private var percentage: Double {
        subject.attendance?.percentage ?? 0.0
    }
    
    private var isAboveThreshold: Bool {
        percentage >= (subject.attendance?.minimumPercentageRequirement ?? 75.0)
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(subject.name)
                    .font(.title2)
                    .foregroundStyle(.primary)
                
                VStack(alignment: .leading, spacing: 0) {
                    if let start = classTime.startTime, let end = classTime.endTime {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                            Text("\(formattedTime(start)) - \(formattedTime(end))")
                        }
                    }
                    
                    if !classTime.roomNumber.isEmpty {
                        Text("Room: \(classTime.roomNumber)")
                    }
                    
                    Text("Attendance: \(Int(percentage))%")
                        .foregroundColor(isAboveThreshold ? .green : .red)
                        .padding(.top, 2)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                
            }
            
            Spacer()
            
            Menu {
                Button("Attended") {
                    updateStatus(to: "Attended")
                }
                Button("Not Attended") {
                    updateStatus(to: "Not Attended")
                }
                Button("Select") { // Changed from "Canceled" to "Select"
                    updateStatus(to: "Canceled")
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(labelColor)
                        .frame(width: 56, height: 56)
                        .shadow(color: labelColor.opacity(0.3), radius: 3, x: 0, y: 2)
                    
                    Text(statusLetter)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.8)
                }
                .padding(12)

                .contentShape(Rectangle())
                .compositingGroup()
                
                .rotation3DEffect(
                    .degrees(rotation),
                    axis: (x: 0.0, y: 1.0, z: 0.0)
                )
                .animation(.spring(response: 1.5, dampingFraction: 0.6).delay(0.1), value: rotation)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(10)
    }
    
    private func updateStatus(to newStatus: String) {
        if record.status != newStatus {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            rotation = (rotation == 0 ? 360 : 0)
            viewModel.updateAttendance(for: record, in: subject, to: newStatus)
        }
    }
    
    private var labelColor: Color {
        switch record.status {
        case "Attended": return .green
        case "Not Attended": return .red
        case "Canceled": return .blue
        default: return .gray
        }
    }
    
    private var statusLetter: String {
        switch record.status {
        case "Attended": return "P"
        case "Not Attended": return "A"
        case "Canceled": return "N/A"
        default: return "?"
        }
    }
    
    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
