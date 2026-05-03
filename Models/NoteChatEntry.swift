import Foundation
import SwiftData

@Model
final class NoteChatEntry {
    var id: UUID
    var createdAt: Date
    var isUser: Bool
    var text: String
    var note: VoiceNote?

    init(note: VoiceNote, isUser: Bool, text: String) {
        self.id = UUID()
        self.createdAt = Date()
        self.isUser = isUser
        self.text = text
        self.note = note
    }
}
