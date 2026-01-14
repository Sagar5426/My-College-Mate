import SwiftUI
import SwiftData
import CoreHaptics

struct AddSubjectView: View {
    
    @Environment(\.modelContext) var modelContext
    @Query var subjects: [Subject]
    @Binding var isShowingAddSubjectView: Bool
    
    @State private var subjectName = ""
    @State private var startDateOfSubject: Date = .now
    @State private var MinimumAttendancePercentage: Int = 75
    @State private var selectedDays: Set<String> = []
    @State private var classTimes: [String: [ClassPeriodTime]] = [:]
    @State private var classCount: [String: Int] = [:]
    
    // Alert States
    @State private var isShowingAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    
    private let characterLimit = 20
    
    let daysOfWeek = [
        "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient.appBackground.ignoresSafeArea()
                Form {
                    SubjectDetailsSection(subjectName: $subjectName)
                    FirstSubjectDatePicker(startDateOfSubject: $startDateOfSubject)
                    MinimumAttendenceStepper(MinimumAttendancePercentage: $MinimumAttendancePercentage)
                    ClassScheduleSection(
                        daysOfWeek: daysOfWeek,
                        selectedDays: $selectedDays,
                        classTimes: $classTimes,
                        classCount: $classCount
                    )
                }
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .navigationTitle("Add Subject")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") {
                            validateAndSave()
                        }
                        .tint(.blue)
                    }
                    
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel", systemImage: "xmark") {
                            isShowingAddSubjectView = false
                        }
                    }
                }
                .alert(alertTitle, isPresented: $isShowingAlert) {
                    Button("OK") { }
                } message: {
                    Text(alertMessage)
                }
            }
        }
    }
    
    private func validateAndSave() {
        var errors: [String] = []
        
        // 1. Validate Name
        let trimmedName = subjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            errors.append("• Subject Name is required.")
        }
        
        // 2. Validate Duplicate Name
        let hasDuplicate = subjects.contains {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == trimmedName.lowercased()
        }
        if hasDuplicate {
            errors.append("• A subject with this name already exists.")
        }
        
        // 3. Validate Days Selection
        if selectedDays.isEmpty {
            errors.append("• Please select at least one day for classes.")
        }
        
        // 4. Validate Class Details (Room & Time)
        for day in selectedDays {
            if let times = classTimes[day] {
                for (index, time) in times.enumerated() {
                    // Check Room Number
                    if time.roomNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        errors.append("• Room number missing for \(day) (Class \(index + 1)).")
                    }
                    
                    // Check Time Logic
                    if let start = time.startTime, let end = time.endTime {
                        if start >= end {
                            errors.append("• End time cannot be before or equal to start time for \(day) (Class \(index + 1)).")
                        }
                    }
                }
            }
        }
        
        // Show Alert if Errors Exist
        if !errors.isEmpty {
            alertTitle = "Validation Error"
            alertMessage = "Please correct the following issues:\n\n" + errors.joined(separator: "\n")
            isShowingAlert = true
            return
        }
        
        // Proceed to Save if valid
        saveSubject(normalizedName: trimmedName)
    }
    
    private func saveSubject(normalizedName: String) {
        let newSubject = Subject(name: normalizedName)
        newSubject.startDateOfSubject = Calendar.current.startOfDay(for: startDateOfSubject)
        
        // 1. Initialize optional Attendance
        let newAttendance = Attendance()
        newAttendance.minimumPercentageRequirement = Double(MinimumAttendancePercentage)
        newSubject.attendance = newAttendance
        
        // 2. Initialize optional Schedules array
        newSubject.schedules = []

        // Create schedules for the selected days
        for day in selectedDays {
            let newSchedule = Schedule(day: day)
            newSchedule.classTimes = []

            if let times = classTimes[day] {
                for time in times {
                    let newClassTime = ClassTime(
                        startTime: time.startTime,
                        endTime: time.endTime,
                        date: Date(),
                        roomNumber: time.roomNumber
                    )
                    newSchedule.classTimes?.append(newClassTime)
                }
            }
            newSubject.schedules?.append(newSchedule)
        }
        
        modelContext.insert(newSubject)
        
        let subjectToSchedule = newSubject
        Task {
            await NotificationManager.shared.scheduleNotifications(for: subjectToSchedule)
        }
        
        // Reset and Dismiss
        subjectName = ""
        selectedDays.removeAll()
        classTimes.removeAll()
        classCount.removeAll()
        
        FileDataService.createSubjectFolder(for: newSubject)
        print("Subject saved successfully.")
        isShowingAddSubjectView = false
    }
}

// MARK: Helper Views
struct SubjectDetailsSection: View {
    @Binding var subjectName: String
    let characterLimit = 20

    var body: some View {
        Section(header: Text("Subject Details")) {
            TextField("Subject Name (Max 20 Characters)", text: $subjectName)
                .onChange(of: subjectName) {
                    if subjectName.count > characterLimit {
                        subjectName = String(subjectName.prefix(characterLimit))
                    }
                }
            if subjectName.count >= characterLimit {
                Text("Maximum character limit reached")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}

struct ClassScheduleSection: View {
    let daysOfWeek: [String]
    @Binding var selectedDays: Set<String>
    @Binding var classTimes: [String: [ClassPeriodTime]]
    @Binding var classCount: [String: Int]
    
    var body: some View {
        Section(header: Text("Select days on which you have classes")) {
            ForEach(daysOfWeek, id: \.self) { day in
                DayRowView(
                    day: day,
                    isSelected: Binding(
                        get: { selectedDays.contains(day) },
                        set: { isSelected in
                            if isSelected {
                                selectedDays.insert(day)
                                let now = Date()
                                let oneHourLater = Calendar.current.date(byAdding: .hour, value: 1, to: now)!
                                classTimes[day] = [ClassPeriodTime(startTime: now, endTime: oneHourLater)]
                                classCount[day] = 1
                            } else {
                                selectedDays.remove(day)
                                classTimes[day] = nil
                                classCount[day] = nil
                            }
                        }
                    ),
                    times: Binding(
                        get: { classTimes[day] ?? [ClassPeriodTime(startTime: Date(), endTime: nil)] },
                        set: { classTimes[day] = $0 }
                    ),
                    count: Binding(
                        get: { classCount[day] ?? 1 },
                        set: { classCount[day] = $0 }
                    )
                )
            }
        }
    }
}

struct DayRowView: View {
    let day: String
    @Binding var isSelected: Bool
    @Binding var times: [ClassPeriodTime]
    @Binding var count: Int
    
    var body: some View {
        VStack(alignment: .leading) {
            Toggle(day, isOn: $isSelected)
            
            if isSelected {
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Text("How many times do you have this class in a day?")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .bold()
                    
                    Picker("Number of Classes", selection: Binding(
                        get: { count },
                        set: { newValue in
                            if newValue > times.count {
                                // Initialize new slots with valid times
                                let now = Date()
                                let later = Calendar.current.date(byAdding: .hour, value: 1, to: now)!
                                let newItems = Array(repeating: ClassPeriodTime(startTime: now, endTime: later), count: newValue - times.count)
                                times.append(contentsOf: newItems)
                            } else {
                                times.removeLast(times.count - newValue)
                            }
                            count = newValue
                        }
                    )) {
                        ForEach(1..<6) { num in
                            Text("\(num)").tag(num)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    ForEach(0..<count, id: \.self) { index in
                        Divider()
                        VStack(alignment: .leading) {
                            Text("\(ordinalNumber(for: index + 1)) Class Timing")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .bold()
                            
                            TextField("Room Number (Required)", text: Binding(
                                get: { times[index].roomNumber },
                                set: { times[index].roomNumber = $0 }
                            ))
                            .padding(8)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 5)

                            HStack(alignment: .bottom) {
                                VStack {
                                    Text("Start Time")
                                    DatePicker("", selection: Binding(
                                        get: { times[index].startTime ?? Date() },
                                        set: { times[index].startTime = $0 }
                                    ), displayedComponents: .hourAndMinute)
                                    .labelsHidden()
                                }
                                Spacer()
                                VStack {
                                    Text("End Time")
                                    DatePicker("", selection: Binding(
                                        get: { times[index].endTime ?? Date() },
                                        set: { times[index].endTime = $0 }
                                    ), displayedComponents: .hourAndMinute)
                                    .labelsHidden()
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }
            }
        }
    }
    
    private func ordinalNumber(for number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
}

struct FirstSubjectDatePicker: View {
    @Binding var startDateOfSubject: Date
    var body: some View {
        Section("Select the date of your first class") {
            DatePicker("First Class Date", selection: $startDateOfSubject, displayedComponents: [.date])
                .datePickerStyle(.compact)
        }
    }
}

struct MinimumAttendenceStepper: View {
    @Binding var MinimumAttendancePercentage: Int
    
    var body: some View {
        Section("Minimum Attendance Requirement") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Attendance Requirement")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                HStack {
                    Spacer()
                    Text("\(MinimumAttendancePercentage)%")
                        .font(.title3)
                        .bold()
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.blue.opacity(0.1))
                        )
                        .frame(minWidth: 70)
                    
                    Spacer()
                    Spacer()
                    
                    Stepper("", value: $MinimumAttendancePercentage, in: 5...100, step: 5)
                        .labelsHidden()
                        .sensoryFeedback(.increase, trigger: MinimumAttendancePercentage)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
