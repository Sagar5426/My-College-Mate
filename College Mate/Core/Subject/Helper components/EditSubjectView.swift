import SwiftUI
import SwiftData

struct EditSubjectView: View {
    @Environment(\.modelContext) private var modelContext
    @Query var subjects: [Subject]
    @Bindable var subject: Subject
    @Binding var isShowingEditSubjectView: Bool
    
    @State private var originalSubjectName: String = ""
    
    // Alert States
    @State private var isShowingAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    
    let daysOfWeek = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    let characterLimit = 20
    
    @State private var selectedDays: Set<String> = []
    @State private var classTimes: [String: [ClassPeriodTime]] = [:]
    @State private var classCount: [String: Int] = [:]
    
    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient.appBackground.ignoresSafeArea()
                Form {
                    Section(header: Text("Subject Details")) {
                        TextField("Subject Name (Max 20 Characters)", text: $subject.name)
                            .onChange(of: subject.name) {
                                if subject.name.count > characterLimit {
                                    subject.name = String(subject.name.prefix(characterLimit))
                                }
                            }
                        if subject.name.count >= characterLimit {
                            Text("Maximum character limit reached")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    FirstSubjectDatePicker(startDateOfSubject: $subject.startDateOfSubject)
                    
                    MinimumAttendenceStepper(MinimumAttendancePercentage: Binding<Int>(
                        get: { Int(subject.attendance?.minimumPercentageRequirement ?? 75.0) },
                        set: { subject.attendance?.minimumPercentageRequirement = Double($0) }
                    ))
                    
                    ClassScheduleSection(
                        daysOfWeek: daysOfWeek,
                        selectedDays: $selectedDays,
                        classTimes: $classTimes,
                        classCount: $classCount
                    )
                }
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .onAppear {
                    // Capture the original name when the view appears
                    originalSubjectName = subject.name
                    populateExistingData()
                }
                .navigationTitle("Edit Subject")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            validateAndSaveChanges()
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
    
    private func validateAndSaveChanges() {
        var errors: [String] = []
        
        // 1. Validate Name
        let trimmedName = subject.name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if trimmedName.isEmpty {
            errors.append("• Subject Name is required.")
        }
        
        // 2. Validate Duplicates (Excluding self)
        if !trimmedName.isEmpty {
            let lowercasedNew = trimmedName.lowercased()
            let hasDuplicate = subjects.contains { other in
                if other.persistentModelID == subject.persistentModelID { return false }
                // Explicit CharacterSet fixes the inference error
                return other.name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).lowercased() == lowercasedNew
            }
            if hasDuplicate {
                errors.append("• A subject with this name already exists.")
            }
        }
        
        // 3. Validate Days
        if selectedDays.isEmpty {
            errors.append("• Please select at least one day for classes.")
        }
        
        // 4. Validate Room Number & Time Logic
        for day in selectedDays {
            if let times = classTimes[day] {
                for (index, time) in times.enumerated() {
                    // Room Validation
                    if time.roomNumber.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                        errors.append("• Room number missing for \(day) (Class \(index + 1)).")
                    }
                    
                    // Time Validation
                    if let start = time.startTime, let end = time.endTime {
                        if start >= end {
                             errors.append("• End time cannot be before or equal to start time for \(day) (Class \(index + 1)).")
                        }
                    }
                }
            }
        }
        
        // Check for Errors
        if !errors.isEmpty {
            alertTitle = "Validation Error"
            alertMessage = "Please correct the following issues:\n\n" + errors.joined(separator: "\n")
            isShowingAlert = true
            
            // Revert name if invalid
            if trimmedName.isEmpty || errors.contains(where: { $0.contains("exists") }) {
                subject.name = originalSubjectName
            }
            return
        }

        // --- Logic if validation passes ---
        
        let newName = trimmedName
        let nameChanged = newName.lowercased() != originalSubjectName.lowercased()
        
        // 1. If name changed, move files FIRST before saving the new name to the model permanently
        if nameChanged {
            moveFilesToNewFolder(oldName: originalSubjectName, newName: newName)
        }
        
        // 2. Update Model
        subject.name = newName
        saveUpdatedData()
        
        isShowingEditSubjectView = false
    }
    
    private func populateExistingData() {
        for schedule in (subject.schedules ?? []) {
            selectedDays.insert(schedule.day)
            classTimes[schedule.day] = (schedule.classTimes ?? []).map { classTime in
                // Uses the shared struct from ClassTime.swift which now supports ID
                ClassPeriodTime(
                    id: classTime.id,
                    startTime: classTime.startTime,
                    endTime: classTime.endTime,
                    roomNumber: classTime.roomNumber
                )
            }
            classCount[schedule.day] = (schedule.classTimes ?? []).count
        }
    }
    
    private func saveUpdatedData() {
        // We do NOT completely replace subject.schedules.
        // We selectively update, add, or remove to preserve IDs.
        
        // 1. Remove schedules for days that are no longer selected
        if let existingSchedules = subject.schedules {
            for i in stride(from: existingSchedules.count - 1, through: 0, by: -1) {
                let schedule = existingSchedules[i]
                if !selectedDays.contains(schedule.day) {
                    modelContext.delete(schedule)
                }
            }
        }
        
        // 2. Update or Create schedules for selected days
        for day in selectedDays {
            // Find existing schedule for this day or create new
            let schedule: Schedule
            if let existing = (subject.schedules ?? []).first(where: { $0.day == day }) {
                schedule = existing
            } else {
                schedule = Schedule(day: day)
                subject.schedules?.append(schedule)
            }
            
            // Get the new configuration from UI
            let uiTimes = classTimes[day] ?? []
            
            // Prepare the new list of ClassTimes
            var updatedClassTimes: [ClassTime] = []
            
            for uiTime in uiTimes {
                // Check if we can reuse an existing ClassTime
                // We reuse it IF:
                // 1. We have an ID
                // 2. The start and end times match (User requested reset if time changes)
                
                if let id = uiTime.id,
                   let existingClassTime = (schedule.classTimes ?? []).first(where: { $0.id == id }),
                   areDatesEqual(d1: existingClassTime.startTime, d2: uiTime.startTime),
                   areDatesEqual(d1: existingClassTime.endTime, d2: uiTime.endTime) {
                    
                    // SAME CLASS: Update details (Room), keep ID (Attendance Preserved)
                    existingClassTime.roomNumber = uiTime.roomNumber
                    updatedClassTimes.append(existingClassTime)
                    
                } else {
                    // CHANGED CLASS or NEW CLASS: Create new (New ID = Reset Attendance)
                    let newClassTime = ClassTime(
                        startTime: uiTime.startTime,
                        endTime: uiTime.endTime,
                        date: Date(),
                        roomNumber: uiTime.roomNumber
                    )
                    updatedClassTimes.append(newClassTime)
                }
            }
            
            // Update the schedule's class list
            schedule.classTimes = updatedClassTimes
        }
        
        let subjectToSchedule = subject
        Task {
            await NotificationManager.shared.scheduleNotifications(for: subjectToSchedule)
        }
    }
    
    // Helper to compare times ignoring milliseconds/seconds drift if necessary
    private func areDatesEqual(d1: Date?, d2: Date?) -> Bool {
        guard let d1 = d1, let d2 = d2 else { return false }
        // Simple equality check
        return d1 == d2
    }
}

// MARK: Helper Views
extension EditSubjectView {
    
    /// Renames the subject folder on disk to match the new subject name.
    func moveFilesToNewFolder(oldName: String, newName: String) {
        let fileManager = FileManager.default
        let oldFolderURL = FileDataService.baseFolder.appendingPathComponent(oldName)
        let newFolderURL = FileDataService.baseFolder.appendingPathComponent(newName)
        
        // 1. Check if the old folder exists
        guard fileManager.fileExists(atPath: oldFolderURL.path) else {
            return // Nothing to move
        }
        
        // 2. Check if the new folder already exists (edge case)
        if fileManager.fileExists(atPath: newFolderURL.path) {
            do {
                // If it's empty, delete it so we can rename the old one to this name
                let contents = try fileManager.contentsOfDirectory(atPath: newFolderURL.path)
                if contents.isEmpty {
                    try fileManager.removeItem(at: newFolderURL)
                } else {
                    // If new folder exists and isn't empty, we must move contents manually (Merge)
                    // This is a fallback, but the atomic move (rename) below is preferred.
                    for file in try fileManager.contentsOfDirectory(at: oldFolderURL, includingPropertiesForKeys: nil) {
                        let target = newFolderURL.appendingPathComponent(file.lastPathComponent)
                        if !fileManager.fileExists(atPath: target.path) {
                            try fileManager.moveItem(at: file, to: target)
                        }
                    }
                    // Clean up old folder
                    try? fileManager.removeItem(at: oldFolderURL)
                    return
                }
            } catch {
                print("Error handling existing destination folder: \(error)")
                return
            }
        }
        
        // 3. Perform atomic rename (Move directory)
        do {
            try fileManager.moveItem(at: oldFolderURL, to: newFolderURL)
            print("Successfully renamed folder from \(oldName) to \(newName)")
        } catch {
            print("Failed to rename folder: \(error.localizedDescription)")
        }
    }
    
    func getFolderURL(for subjectName: String) -> URL {
        return FileDataService.baseFolder.appendingPathComponent(subjectName)
    }
}
