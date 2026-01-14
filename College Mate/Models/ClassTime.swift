import Foundation
import SwiftData

@Model
class ClassTime {
    var id: UUID = UUID()
    
    var date: Date?
    var startTime: Date?
    var endTime: Date?
    var roomNumber: String = ""
    
    var schedule: Schedule?
    
    init(startTime: Date? = nil, endTime: Date? = nil, date: Date? = Date(), roomNumber: String = "") {
        self.id = UUID()
        self.startTime = startTime
        self.endTime = endTime
        self.date = date
        self.roomNumber = roomNumber
    }
    
    init() {}
}

// MARK: - Shared Helper Struct
// Updated to include ID for editing support.
// Defaulting to nil ensures AddSubjectView (which doesn't use ID) still works.
struct ClassPeriodTime: Hashable {
    var id: UUID? = nil
    var startTime: Date?
    var endTime: Date?
    var roomNumber: String = ""
}
