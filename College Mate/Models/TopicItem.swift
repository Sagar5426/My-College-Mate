import Foundation
import SwiftData

@Model
class TopicItem {
    // CloudKit Requirement: All properties must have a default value or be optional.
    var id: UUID = UUID()
    var text: String = ""
    var isCompleted: Bool = false
    var createdAt: Date = Date()
    
    // Relationship back to Subject (already optional, so this is fine)
    var subject: Subject?
    
    init(text: String, isCompleted: Bool = false) {
        self.id = UUID()
        self.text = text
        self.isCompleted = isCompleted
        self.createdAt = Date()
    }
}
