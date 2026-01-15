import Foundation
import SwiftData

@Model
class Subject {
    var id: UUID = UUID()
    var name: String = ""
    var startDateOfSubject: Date = Date()
    var logs: [AttendanceLogEntry] = []
    
    // MARK: - Relationships
    
    @Relationship(deleteRule: .cascade, inverse: \Schedule.subject)
    var schedules: [Schedule]?
    
    @Relationship(deleteRule: .cascade, inverse: \Attendance.subject)
    var attendance: Attendance?
    
    @Relationship(deleteRule: .cascade, inverse: \Note.subject)
    var notes: [Note]?
    
    @Relationship(deleteRule: .cascade, inverse: \AttendanceRecord.subject)
    var records: [AttendanceRecord]?
    
    @Relationship(deleteRule: .cascade, inverse: \Folder.subject)
    var rootFolders: [Folder]?
    
    @Relationship(deleteRule: .cascade, inverse: \FileMetadata.subject)
    var fileMetadata: [FileMetadata]?
    
    // REPLACED: ImportantTopicsNote string with a list of TopicItems
    @Relationship(deleteRule: .cascade, inverse: \TopicItem.subject)
    var topics: [TopicItem]? = []

    init(name: String, startDateOfSubject: Date = .now, schedules: [Schedule]? = [], attendance: Attendance? = Attendance(totalClasses: 0, attendedClasses: 0), notes: [Note]? = []) {
        self.id = UUID()
        self.name = name
        self.startDateOfSubject = startDateOfSubject
        self.schedules = schedules
        self.attendance = attendance
        self.notes = notes
    }
    
    init() {}
}
