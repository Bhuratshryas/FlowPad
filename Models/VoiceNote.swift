import Foundation
import SwiftData

@Model
final class VoiceNote {
    var id: UUID
    var title: String
    /// Non-empty for voice notes; empty for written-only notes.
    var audioFileName: String
    /// Additional recordings added to this note (same order as additionalDurations, additionalTranscripts). Nil for notes created before this feature.
    var additionalAudioFileNames: [String]?
    var transcript: String?
    /// Transcripts for each additional recording (filled after transcription). Nil for notes created before this feature.
    var additionalTranscripts: [String]?
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
    /// Durations for each additional recording (parallel to additionalAudioFileNames). Nil for notes created before this feature.
    var additionalDurations: [TimeInterval]?
    var isProcessing: Bool

    init(
        title: String = "New Note",
        audioFileName: String = "",
        additionalAudioFileNames: [String]? = nil,
        duration: TimeInterval = 0,
        additionalDurations: [TimeInterval]? = nil,
        transcript: String? = nil,
        additionalTranscripts: [String]? = nil,
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
        self.additionalAudioFileNames = additionalAudioFileNames ?? []
        self.duration = duration
        self.additionalDurations = additionalDurations ?? []
        self.transcript = transcript
        self.additionalTranscripts = additionalTranscripts ?? []
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

    /// All recordings in order: primary first, then additional. (url, duration)
    var allRecordingURLsAndDurations: [(url: URL, duration: TimeInterval)] {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        var out: [(URL, TimeInterval)] = []
        if !audioFileName.isEmpty {
            out.append((docs.appendingPathComponent(audioFileName), duration))
        }
        let addNames = additionalAudioFileNames ?? []
        let addDurations = additionalDurations ?? []
        for (i, name) in addNames.enumerated() {
            let dur = i < addDurations.count ? addDurations[i] : 0
            out.append((docs.appendingPathComponent(name), dur))
        }
        return out
    }

    /// Total duration of all recordings.
    var totalDuration: TimeInterval {
        duration + (additionalDurations ?? []).reduce(0, +)
    }

    /// Content used for summarization (combined transcript or written body).
    var contentForSummary: String? {
        let combined = combinedTranscript
        if !combined.isEmpty { return combined }
        return writtenContent
    }

    /// Combined transcript: primary + all additional, separated by newlines.
    var combinedTranscript: String {
        var parts: [String] = []
        if let t = transcript, !t.isEmpty { parts.append(t) }
        parts.append(contentsOf: (additionalTranscripts ?? []).filter { !$0.isEmpty })
        return parts.joined(separator: "\n\n")
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
