import SwiftUI
import SwiftData
import CoreData

struct DailyLogView: View {
    @Environment(\.modelContext) private var modelContext
    @Query var subjects: [Subject]
    
    @StateObject private var viewModel = DailyLogViewModel()
    @State private var viewID = UUID()
    
    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                LazyVStack(spacing: 16, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ControlPanelView(viewModel: viewModel)
                        Divider().padding(.vertical)
                        ClassesList(viewModel: viewModel)
                    } header: {
                        GeometryReader { proxy in
                            HeaderView(size: proxy.size, title: "Attendance 🙋", isShowingProfileView: $viewModel.isShowingProfileView)
                        }
                        .frame(height: 50)
                    }
                }
                .padding()
            }
            .id(viewID)
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
                            viewModel.selectedDate = start
                            viewModel.isShowingDatePicker = false
                            viewID = UUID()
                        },
                        onClose: {
                            viewModel.isShowingDatePicker = false
                            viewID = UUID()
                        }
                    )
                    .transition(.move(edge: .leading))
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange)) { notification in
                if !Thread.isMainThread {
                    DispatchQueue.main.async {
                        viewID = UUID()
                    }
                }
            }
        }
        .animation(.spring(duration: 0.4), value: viewModel.isShowingDatePicker)
        .onAppear {
            viewModel.setup(subjects: subjects, modelContext: modelContext)
        }
        .onChange(of: subjects) {
            viewModel.setup(subjects: subjects, modelContext: modelContext)
        }
    }
}

// MARK: - Control Panel View
struct ControlPanelView: View {
    @ObservedObject var viewModel: DailyLogViewModel
    
    private var isNextDayDisabled: Bool { Calendar.current.isDateInToday(viewModel.selectedDate) }
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button(action: {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    viewModel.moveToPreviousDay()
                }) {
                    Image(systemName: "chevron.left.circle.fill")
                }
                
                Spacer()
                
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
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Button(action: {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    viewModel.moveToNextDay()
                }) {
                    Image(systemName: "chevron.right.circle.fill")
                }
                .disabled(isNextDayDisabled)
                .opacity(isNextDayDisabled ? 0.5 : 1.0)
            }
            .font(.title)
            .foregroundStyle(.blue)
            
            if !viewModel.dailyClasses.isEmpty {
                Button(action: {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    viewModel.toggleHoliday()
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
        if viewModel.isHoliday {
            VStack(spacing: 10) {
                Image(systemName: "sun.max.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text("Enjoy your holiday!")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            .padding(.vertical, 50)
            
        } else if viewModel.dailyClasses.isEmpty {
            Text("No classes scheduled for this day.").font(.subheadline).foregroundColor(.gray).padding()
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
            }.padding()
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
    
    private var isAboveThreshold: Bool {
        percentage >= (subject.attendance?.minimumPercentageRequirement ?? 75.0)
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(subject.name)
                    .font(.title2)
                    .foregroundStyle(.primary)
                
                VStack(alignment: .leading, spacing: 4) {
                    if let start = classTime.startTime, let end = classTime.endTime {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption)
                            Text("\(formattedTime(start)) - \(formattedTime(end))")
                        }
                    }
                    
                    if !classTime.roomNumber.isEmpty {
                        Text("Room: \(classTime.roomNumber)")
                            .font(.subheadline)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                
                Text("Attendance: \(Int(percentage))%")
                    .font(.caption)
                    .foregroundColor(isAboveThreshold ? .green : .red)
                    .padding(.top, 2)
            }
            
            Spacer()
            
            Menu {
                Button("Attended") {
                    updateStatus(to: "Attended")
                }
                Button("Not Attended") {
                    updateStatus(to: "Not Attended")
                }
                Button("Canceled") {
                    updateStatus(to: "Canceled")
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(labelColor)
                        .frame(width: 50, height: 50)
                        .shadow(color: labelColor.opacity(0.3), radius: 3, x: 0, y: 2)
                    
                    Text(statusLetter)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.8)
                }
                .rotation3DEffect(
                    .degrees(rotation),
                    axis: (x: 0.0, y: 1.0, z: 0.0)
                )
                // [Modified] Slower animation (1.5s response) with slight delay
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
            
            // Just update rotation state; the modifier above handles the animation timing
            rotation += 360
            
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
