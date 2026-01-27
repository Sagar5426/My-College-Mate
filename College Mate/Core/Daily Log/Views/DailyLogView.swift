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
                        // 1. Navigation & Holiday Controls
                        ControlPanelView(
                            viewModel: viewModel,
                            viewID: viewID,
                            transition: customSlideTransition,
                            onPrevious: animateToPreviousDay,
                            onNext: animateToNextDay
                        )
                        
                        // 2. Grouped Bulk Actions & Divider
                        VStack(spacing: 4) {
                            if !viewModel.dailyClasses.isEmpty && !viewModel.isHoliday {
                                BulkActionRow(viewModel: viewModel)
                                    .padding(.horizontal, 8)
                                    .transition(.opacity)
                            }
                            
                            Divider()
                                .padding(.bottom, 8)
                        }
                        
                        // 3. Classes List
                        ClassesList(viewModel: viewModel)
                            .id(viewID)
                            .transition(customSlideTransition)
                        
                    } header: {
                        GeometryReader { proxy in
                            HeaderView(size: proxy.size, title: "Attendance", icon: .asset("student_hat", size: 28), isShowingProfileView: $viewModel.isShowingProfileView)
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

// MARK: - Bulk Action Row (Vertical Coin Rotation)
struct BulkActionRow: View {
    @ObservedObject var viewModel: DailyLogViewModel

    @State private var rotation: Double = 0
    @State private var isAnimating = false

    var body: some View {
        HStack {

            // Stats Info (UNCHANGED)
            VStack(alignment: .leading, spacing: 2) {
                Text("Total classes: \(viewModel.totalClassesCount)")
                Text("Marked classes: \(viewModel.markedClassesCount)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()

            Button {
                guard !isAnimating else { return }
                performVerticalFlip()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: viewModel.areAllMarkedPresent
                          ? "a.circle.fill"
                          : "p.circle.fill")
                        .font(.system(size: 22, weight: .bold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(
                            .white,
                            viewModel.areAllMarkedPresent ? .red : .green 
                        )

                    

                    Text(viewModel.areAllMarkedPresent
                         ? "Mark All Absent"
                         : "Mark All Present")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(viewModel.areAllMarkedPresent ? .red : .green)
                .rotation3DEffect(
                    .degrees(rotation),
                    axis: (x: 1, y: 0, z: 0)   // ✅ vertical rotation
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func performVerticalFlip() {
        isAnimating = true

        let totalDuration: Double = 1
        let halfDuration = totalDuration / 2

        // 1️⃣ Continuous 360° rotation (no spring = no pause)
        withAnimation(.easeInOut(duration: totalDuration)) {
            rotation += 360
        }

        // 2️⃣ Change label exactly at midpoint (invisible moment)
        DispatchQueue.main.asyncAfter(deadline: .now() + halfDuration) {
            viewModel.toggleAllAttendance()
        }

        // 3️⃣ Subtle spring settle at the end
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                rotation += 0.001
            }
            isAnimating = false
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
            // Date Navigation Row
            HStack(spacing: 0) {
                
                // LEFT CHEVRON
                Button(action: {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    onPrevious()
                }) {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.title)
                        .padding(.trailing, 8)
                }
                
                // CENTER DATE
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
                
                // RIGHT CHEVRON
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
            
            // Holiday Button
            if !viewModel.dailyClasses.isEmpty {
                Button(action: {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                                
                    // 1. Toggle the holiday state in the model
                    withAnimation {
                        viewModel.toggleHoliday()
                    }
                                
                    // 2. Handle Notifications
                    Task {
                        if viewModel.isHoliday {
                            // If user MARKED as holiday, cancel notifications for this specific date
                                        await NotificationManager.shared.cancelNotifications(on: viewModel.selectedDate)
                                    } else {
                                        // If user UNMARKED holiday, check current subjects and restore notifications for this date
                                        // We need access to the subjects list.
                                        // Since `ControlPanelView` doesn't have direct access to `subjects` query,
                                        // we rely on `viewModel` or pass it down.
                                        
                                        // Simplest fix: Re-schedule based on the `dailyClasses` the view model already knows about,
                                        // OR ideally, pass the full subject list if needed.
                                        // Assuming `viewModel.dailyClasses` contains enough info,
                                        // but actually NotificationManager needs the `Subject` object.
                                        
                                        // Strategy: Map the unique subjects from the daily classes
                                        let uniqueSubjects = Array(Set(viewModel.dailyClasses.map { $0.subject }))
                                        await NotificationManager.shared.rescheduleNotifications(for: uniqueSubjects, on: viewModel.selectedDate)
                                    }
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
        .animation(.spring(), value: viewModel.isHoliday)
    }
}


// MARK: - Classes List
struct ClassesList: View {
    @ObservedObject var viewModel: DailyLogViewModel
    
    var body: some View {
        ZStack(alignment: .top) {
            if viewModel.isHoliday {
                VStack(spacing: 10) {
                    LottieHelperView(size: .init(width: 250, height: 250))
                    Text("Enjoy your holiday!")
                        .font(.headline)
                        .foregroundColor(.gray)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 50)
                
            } else if viewModel.dailyClasses.isEmpty {
                VStack(spacing: 0) {
                    LottieHelperView(fileName: "Calendar.json", size: .init(width: 200, height: 200), animationScale: 2)
                    Text("No classes scheduled for this day.")
                        .font(.headline)
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .offset(y: -35)
                }
                .multilineTextAlignment(.center)
                .padding(.top, 100)
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

// MARK: - Class Attendance Row
struct ClassAttendanceRow: View {
    let subject: Subject
    let classTime: ClassTime
    let record: AttendanceRecord
    @ObservedObject var viewModel: DailyLogViewModel
    
    @State private var rotation: Double = 0.0
    
    private var percentage: Double {
        subject.attendance?.percentage ?? 0.0
    }
    
    private var attendanceColor: Color {
        guard let attendance = subject.attendance else { return .gray }
        let currentPercentage = attendance.percentage
        let minRequirement = attendance.minimumPercentageRequirement
        
        if currentPercentage >= minRequirement {
            return .green
        } else if currentPercentage <= (0.5 * minRequirement) {
            return .red
        } else {
            return .yellow
        }
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
                    
                    Text("Attendance: \(Int(min(percentage, 100.0).rounded()))%")
                        .foregroundColor(attendanceColor)
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
                Button("Select") {
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
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(10)
        // Trigger rotation on ANY status change
        .onChange(of: record.status) {
             withAnimation(.spring(response: 1.5, dampingFraction: 0.6)) {
                 rotation = (rotation == 0 ? 360 : 0)
             }
        }
    }
    
    private func updateStatus(to newStatus: String) {
        if record.status != newStatus {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
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
