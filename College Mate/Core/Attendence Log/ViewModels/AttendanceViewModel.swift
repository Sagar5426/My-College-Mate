import SwiftUI
import SwiftData

@MainActor
class AttendanceViewModel: ObservableObject {
    
    // MARK: - Properties
    @Published var selectedDate = Date() {
        didSet {
            filterScheduledSubjects()
            checkHolidayStatus()
        }
    }
    @Published var isHoliday = false
    @Published var isShowingDatePicker = false
    @Published var isShowingProfileView = false
    @Published var scheduledSubjects: [Subject] = []
    
    private var allSubjects: [Subject] = []
    private var modelContext: ModelContext?
    
    // MARK: - Initializer
    init() {}
    
    // MARK: - Public Methods
    
    func setup(subjects: [Subject], modelContext: ModelContext) {
        self.allSubjects = subjects
        self.modelContext = modelContext
        filterScheduledSubjects()
        checkHolidayStatus()
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
    
    /// Toggles the holiday status for all classes on the selected date.
    func toggleHoliday() {
        let newHolidayState = !isHoliday
        
        // Find all classes scheduled for this day.
        for subject in scheduledSubjects {
            for schedule in (subject.schedules ?? []) where schedule.day == selectedDate.formatted(.dateTime.weekday(.wide)) {
                for classTime in (schedule.classTimes ?? []) {
                    let record = self.record(for: classTime, in: subject)
                    record.isHoliday = newHolidayState
                    
                    if newHolidayState {
                        if record.status != "Canceled" {
                            updateAttendance(for: record, in: subject, to: "Canceled")
                        }
                    }
                }
            }
        }
        checkHolidayStatus()
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
    
    func updateAttendance(for record: AttendanceRecord, in subject: Subject, to newStatus: String) {
        let oldStatus = record.status
        guard oldStatus != newStatus else { return }

        // Attendance Calculation Logic
        if newStatus == "Attended" {
            if oldStatus == "Not Attended" { subject.attendance?.attendedClasses += 1 }
            else if oldStatus == "Canceled" {
                subject.attendance?.attendedClasses += 1
                subject.attendance?.totalClasses += 1
            }
        } else if newStatus == "Not Attended" {
            if oldStatus == "Attended" { subject.attendance?.attendedClasses -= 1 }
            else if oldStatus == "Canceled" { subject.attendance?.totalClasses += 1 }
        } else if newStatus == "Canceled" {
            if oldStatus == "Attended" {
                subject.attendance?.attendedClasses -= 1
                subject.attendance?.totalClasses -= 1
            } else if oldStatus == "Not Attended" {
                subject.attendance?.totalClasses -= 1
            }
        }
        
        record.status = newStatus
        
        let logAction = newStatus == "Attended" ? "+ Attended" : (newStatus == "Not Attended" ? "- Missed" : (newStatus == "Holiday" ? "🌴 Holiday" : "ø Canceled"))
        let log = AttendanceLogEntry(timestamp: Date(), subjectName: subject.name, action: logAction)
        
        subject.logs.append(log)
    }
    
    // MARK - Private Helper Methods
    
    /// Checks if any class record for the selected date is marked as a holiday.
    private func checkHolidayStatus() {
        self.isHoliday = isHoliday(on: selectedDate)
    }
    
    /// A reusable function to check the holiday status of any given date from the database.
    private func isHoliday(on date: Date) -> Bool {
        let targetDate = Calendar.current.startOfDay(for: date)
        for subject in allSubjects {
            if (subject.records ?? []).contains(where: { Calendar.current.isDate($0.date, inSameDayAs: targetDate) && $0.isHoliday }) {
                return true
            }
        }
        return false
    }
    
    private func filterScheduledSubjects() {
        let dayOfWeek = selectedDate.formatted(Date.FormatStyle().weekday(.wide))
        scheduledSubjects = allSubjects.filter { subject in
            guard selectedDate >= subject.startDateOfSubject else { return false }
            return (subject.schedules ?? []).contains { $0.day == dayOfWeek }
        }
    }
}
