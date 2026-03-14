import Foundation
import SwiftData

@Model
final class VoiceNote {
    var id: UUID
    var title: String
    /// Non-empty for voice notes; empty for written-only notes.
    var audioFileName: String
    var transcript: String?
    /// Main summary paragraph (structured summary).
    var summary: String?
    /// Key highlights (bullets). Optional for migration from older records.
    var keyHighlights: [String]
    /// Action item text.
    var actionItemTexts: [String]
    /// Completed state for each action item.
    var actionItemDone: [Bool]
    /// Body text for written notes (nil for voice notes). Supports Markdown (headings, bullets).
    var writtenContent: String?
    /// Image file names for attached photos (stored in Documents).
    var attachedImageFileNames: [String]
    var isPinned: Bool
    var createdAt: Date
    var duration: TimeInterval
    var isProcessing: Bool

    init(
        title: String = "New Note",
        audioFileName: String = "",
        duration: TimeInterval = 0,
        transcript: String? = nil,
        summary: String? = nil,
        keyHighlights: [String] = [],
        actionItemTexts: [String] = [],
        actionItemDone: [Bool] = [],
        writtenContent: String? = nil,
        attachedImageFileNames: [String] = [],
        isPinned: Bool = false
    ) {
        self.id = UUID()
        self.title = title
        self.audioFileName = audioFileName
        self.duration = duration
        self.transcript = transcript
        self.summary = summary
        self.keyHighlights = keyHighlights
        self.actionItemTexts = actionItemTexts
        self.actionItemDone = actionItemDone
        self.writtenContent = writtenContent
        self.attachedImageFileNames = attachedImageFileNames
        self.isPinned = isPinned
        self.createdAt = Date()
        self.isProcessing = writtenContent != nil ? false : true
    }

    func imageURLs(in documentsURL: URL) -> [URL] {
        attachedImageFileNames.map { documentsURL.appendingPathComponent($0) }
    }

    var hasAudio: Bool { !audioFileName.isEmpty }

    var audioURL: URL? {
        guard hasAudio else { return nil }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(audioFileName)
    }

    /// Content used for summarization (transcript or written body).
    var contentForSummary: String? {
        if let t = transcript, !t.isEmpty { return t }
        return writtenContent
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

    func toggleActionItemDone(at index: Int) {
        guard index >= 0, index < actionItemDone.count else { return }
        actionItemDone[index].toggle()
    }
}
