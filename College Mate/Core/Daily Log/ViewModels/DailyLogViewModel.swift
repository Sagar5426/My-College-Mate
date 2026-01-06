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
            item.record.isHoliday = newHolidayState
            
            if newHolidayState {
                if item.record.status != "Canceled" {
                    updateAttendance(for: item.record, in: item.subject, to: "Canceled")
                }
            }
        }
        // Refresh to check if the day is still a holiday (it will be)
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
        
        // Trigger UI refresh if needed
        objectWillChange.send()
    }
    
    // MARK - Private Helper Methods
    
    private func refreshDailyClasses() {
        let dayOfWeek = selectedDate.formatted(Date.FormatStyle().weekday(.wide))
        var items: [DailyClassItem] = []
        
        // 1. Filter Subjects relevant to today
        let todaySubjects = allSubjects.filter { subject in
            selectedDate >= subject.startDateOfSubject
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
