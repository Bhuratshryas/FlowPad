import Foundation
import SwiftData

@Model
final class VoiceNote {
    var id: UUID
    var title: String
    var audioFileName: String
    var transcript: String?
    var summary: String?
    var createdAt: Date
    var duration: TimeInterval
    var isProcessing: Bool

    init(
        title: String = "New Recording",
        audioFileName: String,
        duration: TimeInterval,
        transcript: String? = nil,
        summary: String? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.audioFileName = audioFileName
        self.duration = duration
        self.transcript = transcript
        self.summary = summary
        self.createdAt = Date()
        self.isProcessing = true
    }

    var audioURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(audioFileName)
    }

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }

    var relativeDateString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }
}
