import SwiftUI
import SwiftData

// A helper struct to flatten the hierarchy for sorting
struct DailyClassItem: Identifiable {
    let id: UUID
    let subject: Subject
    let classTime: ClassTime
    let record: AttendanceRecord
}

@MainActor
class DailyLogViewModel: ObservableObject {
    
    // MARK: - Properties
    @Published var selectedDate = Date() {
        didSet {
            refreshDailyClasses()
        }
    }
    @Published var isHoliday = false
    @Published var isShowingDatePicker = false
    @Published var isShowingProfileView = false
    
    // Flattened list sorted by time
    @Published var dailyClasses: [DailyClassItem] = []
    
    private var allSubjects: [Subject] = []
    private var modelContext: ModelContext?
    
    // MARK: - Initializer
    init() {}
    
    // MARK: - New Computed Properties for Bulk Actions
    var totalClassesCount: Int {
            dailyClasses.count
        }
        
    // Counts classes that are either Present or Absent (excludes N/A)
    var markedClassesCount: Int {
        dailyClasses.filter { $0.record.status == "Attended" || $0.record.status == "Not Attended" }.count
    }
        
    // Helper to determine the state of the Toggle Button
    var areAllMarkedPresent: Bool {
        guard !dailyClasses.isEmpty else { return false }
        return dailyClasses.allSatisfy { $0.record.status == "Attended" }
    }
    
    // MARK: - Public Methods
    
    func setup(subjects: [Subject], modelContext: ModelContext) {
        self.allSubjects = subjects
        self.modelContext = modelContext
        refreshDailyClasses()
    }

    func moveToPreviousDay() {
        selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
    }
    
    func moveToNextDay() {
        let today = Calendar.current.startOfDay(for: Date())
        let nextDay = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate)
        
        if nextDay <= today {
            selectedDate = nextDay
        }
    }
    
    func toggleHoliday() {
        let newHolidayState = !isHoliday
        
        // Update all classes in the current view
        for item in dailyClasses {
            // 1. Update the holiday flag
            item.record.isHoliday = newHolidayState
            
            // 2. Handle Logic for Marking as Holiday
            if newHolidayState {
                
                // Check if this specific class is currently marked (Present/Absent)
                let wasMarked = (item.record.status == "Attended" || item.record.status == "Not Attended")
                
                // Generate specific log message per subject
                let logMessage = wasMarked
                    ? "Marked as Holiday. Attendance reverted."
                    : "Marked as Holiday"
                
                if item.record.status != "Canceled" {
                    // Update status to Canceled and pass the specific log message
                    updateAttendance(for: item.record, in: item.subject, to: "Canceled", customLogMessage: logMessage)
                } else {
                    // If status is ALREADY "Canceled", updateAttendance won't run.
                    // We must manually add the log so the user knows the holiday was marked.
                    let log = AttendanceLogEntry(timestamp: Date(), subjectName: item.subject.name, action: logMessage)
                    item.subject.logs.append(log)
                }
            }
        }
        
        // Refresh to check if the day is still a holiday (it will be)
        checkHolidayStatus()
    }
    
    // MARK: - New Bulk Update Method
        
        func toggleAllAttendance() {
            // If ALL are currently "Attended", switch ALL to "Not Attended" (Absent).
            // Otherwise (if mixed, all Absent, or all N/A), switch ALL to "Attended" (Present).
            let newStatus = areAllMarkedPresent ? "Not Attended" : "Attended"
            
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            
            withAnimation {
                for item in dailyClasses {
                    // Only update if the status is actually changing to avoid unnecessary processing
                    if item.record.status != newStatus {
                        updateAttendance(for: item.record, in: item.subject, to: newStatus)
                    }
                }
            }
        }
    
    
    // --- Core Attendance Logic ---
    
    func record(for classTime: ClassTime, in subject: Subject) -> AttendanceRecord {
        let targetDate = Calendar.current.startOfDay(for: selectedDate)
        
        if let existingRecord = (subject.records ?? []).first(where: { $0.classTimeID == classTime.id && Calendar.current.isDate($0.date, inSameDayAs: targetDate) }) {
            return existingRecord
        } else {
            let isDayAlreadyHoliday = isHoliday(on: targetDate)
            let newRecord = AttendanceRecord(date: targetDate, status: "Canceled", classTimeID: classTime.id, isHoliday: isDayAlreadyHoliday)
            newRecord.subject = subject
            modelContext?.insert(newRecord)
            return newRecord
        }
    }
    
    // --- Custom log message support ---
    func updateAttendance(for record: AttendanceRecord, in subject: Subject, to newStatus: String, customLogMessage: String? = nil) {
            let oldStatus = record.status
            guard oldStatus != newStatus else { return }

            // Attendance Calculation Logic
            if newStatus == "Attended" {
                if oldStatus == "Not Attended" {
                    subject.attendance?.attendedClasses += 1
                }
                else if oldStatus == "Canceled" {
                    subject.attendance?.attendedClasses += 1
                    subject.attendance?.totalClasses += 1
                }
            } else if newStatus == "Not Attended" {
                if oldStatus == "Attended" {
                    // FIX: Prevent negative values
                    subject.attendance?.attendedClasses = max(0, (subject.attendance?.attendedClasses ?? 0) - 1)
                }
                else if oldStatus == "Canceled" {
                    subject.attendance?.totalClasses += 1
                }
            } else if newStatus == "Canceled" {
                if oldStatus == "Attended" {
                    // FIX: Prevent negative values for both attended and total
                    subject.attendance?.attendedClasses = max(0, (subject.attendance?.attendedClasses ?? 0) - 1)
                    subject.attendance?.totalClasses = max(0, (subject.attendance?.totalClasses ?? 0) - 1)
                } else if oldStatus == "Not Attended" {
                    // FIX: Prevent negative values for total
                    subject.attendance?.totalClasses = max(0, (subject.attendance?.totalClasses ?? 0) - 1)
                }
            }
            
            record.status = newStatus
            
            // --- Enhanced Descriptive Logs ---
            var logAction = ""
            
            if let customMessage = customLogMessage {
                logAction = customMessage
            } else if newStatus == "Attended" {
                logAction = "Marked as Present"
            } else if newStatus == "Not Attended" {
                logAction = "Marked as Absent"
            } else if newStatus == "Canceled" {
                // Context-aware messages for cancellation/reset
                if record.isHoliday {
                    logAction = "Marked as Holiday"
                } else if oldStatus == "Attended" {
                    logAction = "Present status reverted"
                } else if oldStatus == "Not Attended" {
                    logAction = "Absent status reverted"
                } else {
                    logAction = "Decision reverted"
                }
            } else {
                // Fallback for any other future statuses
                logAction = "Status updated to \(newStatus)"
            }
            
            let log = AttendanceLogEntry(timestamp: Date(), subjectName: subject.name, action: logAction)
            
            subject.logs.append(log)
            
            // Trigger UI refresh if needed
            objectWillChange.send()
        }
    
    // MARK - Private Helper Methods
    
    private func refreshDailyClasses() {
        let dayOfWeek = selectedDate.formatted(Date.FormatStyle().weekday(.wide))
        var items: [DailyClassItem] = []
        
        // FIX: Normalize both dates to Start of Day to ignore time components
        let calendar = Calendar.current
        let startOfSelectedDate = calendar.startOfDay(for: selectedDate)
        
        // 1. Filter Subjects relevant to today
        let todaySubjects = allSubjects.filter { subject in
            let startOfSubjectDate = calendar.startOfDay(for: subject.startDateOfSubject)
            return startOfSelectedDate >= startOfSubjectDate
        }
        
        // 2. Flatten Schedules
        for subject in todaySubjects {
            for schedule in (subject.schedules ?? []) where schedule.day == dayOfWeek {
                for classTime in (schedule.classTimes ?? []) {
                    // Fetch or Create Record
                    let rec = self.record(for: classTime, in: subject)
                    items.append(DailyClassItem(id: classTime.id, subject: subject, classTime: classTime, record: rec))
                }
            }
        }
        
        // 3. Sort by Start Time
        items.sort {
            ($0.classTime.startTime ?? .distantPast) < ($1.classTime.startTime ?? .distantPast)
        }
        
        self.dailyClasses = items
        checkHolidayStatus()
    }
    
    private func checkHolidayStatus() {
        self.isHoliday = isHoliday(on: selectedDate)
    }
    
    private func isHoliday(on date: Date) -> Bool {
        let targetDate = Calendar.current.startOfDay(for: date)
        // Check if ANY record on this day is marked as holiday.
        // Since we now have `dailyClasses`, we can check that if the date matches selectedDate
        if Calendar.current.isDate(date, inSameDayAs: selectedDate) {
             return dailyClasses.contains { $0.record.isHoliday }
        }
        
        // Fallback for other dates (scan all subjects)
        for subject in allSubjects {
            if (subject.records ?? []).contains(where: { Calendar.current.isDate($0.date, inSameDayAs: targetDate) && $0.isHoliday }) {
                return true
            }
        }
        return false
    }
}
