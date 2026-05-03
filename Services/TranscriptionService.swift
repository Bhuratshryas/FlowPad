import Foundation
import AVFoundation
@preconcurrency import Speech

final class TranscriptionService: @unchecked Sendable {
    static let shared = TranscriptionService()

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    private init() {}

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func transcribe(audioURL: URL) async throws -> String {
        guard let recognizer, recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }

        let segments = try await segmentAudioIfNeeded(audioURL)
        defer {
            for segment in segments where segment != audioURL {
                try? FileManager.default.removeItem(at: segment)
            }
        }

        var transcriptParts: [String] = []
        for segmentURL in segments {
            let part = try await transcribeSingleFile(segmentURL, recognizer: recognizer)
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                transcriptParts.append(trimmed)
            }
        }
        return transcriptParts.joined(separator: "\n\n")
    }

    private func transcribeSingleFile(_ audioURL: URL, recognizer: SFSpeechRecognizer) async throws -> String {
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        request.requiresOnDeviceRecognition = false

        return try await withCheckedThrowingContinuation { continuation in
            let recognitionState = SpeechRecognitionState()

            let speechTask = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    recognitionState.resume(throwing: error, continuation: continuation)
                    return
                }
                guard let result else { return }
                if result.isFinal {
                    let text = result.bestTranscription.formattedString
                    recognitionState.resume(returning: text, continuation: continuation)
                }
            }
            recognitionState.setTask(speechTask)

            // Avoid hanging forever if Speech never delivers a final result.
            let timeoutSeconds: TimeInterval = 20 * 60
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeoutSeconds) {
                recognitionState.cancelTask()
                recognitionState.resume(throwing: TranscriptionError.recognitionTimedOut, continuation: continuation)
            }
        }
    }

    private func segmentAudioIfNeeded(_ audioURL: URL) async throws -> [URL] {
        let asset = AVURLAsset(url: audioURL)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        guard durationSeconds.isFinite, durationSeconds > 0 else { return [audioURL] }

        // Split long recordings to avoid Speech framework timeouts on very long files.
        let maxSegmentDuration: Double = 12 * 60
        guard durationSeconds > maxSegmentDuration else { return [audioURL] }

        var outputURLs: [URL] = []
        var start: Double = 0
        var index = 0

        while start < durationSeconds {
            let end = min(start + maxSegmentDuration, durationSeconds)
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("voxnote-segment-\(UUID().uuidString)-\(index).m4a")
            try await exportSegment(
                from: asset,
                start: start,
                end: end,
                outputURL: fileURL
            )
            outputURLs.append(fileURL)
            start = end
            index += 1
        }

        return outputURLs.isEmpty ? [audioURL] : outputURLs
    }

    private func exportSegment(from asset: AVURLAsset, start: Double, end: Double, outputURL: URL) async throws {
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw TranscriptionError.exportFailed
        }
        try? FileManager.default.removeItem(at: outputURL)
        let startCM = CMTime(seconds: start, preferredTimescale: 600)
        let durationCM = CMTime(seconds: max(0, end - start), preferredTimescale: 600)
        export.timeRange = CMTimeRange(start: startCM, duration: durationCM)
        try await export.export(to: outputURL, as: .m4a)
    }

    private final class SpeechRecognitionState: @unchecked Sendable {
        private let lock = NSLock()
        private var hasResumed = false
        private var task: SFSpeechRecognitionTask?

        func setTask(_ task: SFSpeechRecognitionTask) {
            lock.lock()
            self.task = task
            lock.unlock()
        }

        func cancelTask() {
            lock.lock()
            let task = task
            lock.unlock()
            task?.cancel()
        }

        func resume(returning text: String, continuation: CheckedContinuation<String, any Error>) {
            guard markResumed() else { return }
            continuation.resume(returning: text)
        }

        func resume(throwing error: any Error, continuation: CheckedContinuation<String, any Error>) {
            guard markResumed() else { return }
            continuation.resume(throwing: error)
        }

        private func markResumed() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !hasResumed else { return false }
            hasResumed = true
            return true
        }
    }

    enum TranscriptionError: LocalizedError {
        case recognizerUnavailable
        case exportFailed
        case recognitionTimedOut

        var errorDescription: String? {
            switch self {
            case .recognizerUnavailable:
                return "Speech recognition is not available."
            case .exportFailed:
                return "Could not prepare audio for transcription."
            case .recognitionTimedOut:
                return "Speech recognition took too long for this segment."
            }
        }
    }
}
