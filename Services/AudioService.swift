import AVFoundation
import Foundation

@Observable
final class AudioService: NSObject, @unchecked Sendable {
    var isRecording = false
    var isPlaying = false
    var recordingTime: TimeInterval = 0
    var currentPlaybackTime: TimeInterval = 0
    var meterLevel: Float = 0

    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var meterTimer: Timer?
    private var playbackTimer: Timer?
    private var startTime: Date?
    private var currentFileName: String?

    override init() {
        super.init()
        configureSession()
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetooth]
            )
            try session.setActive(true)
        } catch {
            print("Audio session configuration failed: \(error)")
        }
    }

    // MARK: - Recording

    @discardableResult
    func startRecording() -> String {
        let fileName = "\(UUID().uuidString).m4a"
        currentFileName = fileName
        let url = documentsDirectory.appendingPathComponent(fileName)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            isRecording = true
            startTime = Date()
            beginMeterUpdates()
        } catch {
            print("Recording failed to start: \(error)")
        }

        return fileName
    }

    func stopRecording() -> (fileName: String, duration: TimeInterval) {
        let duration = recordingTime
        let fileName = currentFileName ?? ""

        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
        meterTimer?.invalidate()
        meterTimer = nil
        recordingTime = 0
        startTime = nil
        meterLevel = 0

        return (fileName, duration)
    }

    func cancelRecording() {
        if let fileName = currentFileName {
            let url = documentsDirectory.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: url)
        }
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
        meterTimer?.invalidate()
        meterTimer = nil
        recordingTime = 0
        startTime = nil
        meterLevel = 0
        currentFileName = nil
    }

    // MARK: - Playback

    func play(url: URL) {
        stopPlayback()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.play()
            isPlaying = true
            beginPlaybackUpdates()
        } catch {
            print("Playback failed: \(error)")
        }
    }

    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
        currentPlaybackTime = 0
    }

    func togglePlayback(url: URL) {
        if isPlaying {
            stopPlayback()
        } else {
            play(url: url)
        }
    }

    var playbackProgress: Double {
        guard let player = audioPlayer, player.duration > 0 else { return 0 }
        return player.currentTime / player.duration
    }

    // MARK: - Timers

    private func beginMeterUpdates() {
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            guard let self, let recorder = self.audioRecorder else { return }
            recorder.updateMeters()
            let power = recorder.averagePower(forChannel: 0)
            self.meterLevel = max(0, (power + 50) / 50)

            if let start = self.startTime {
                self.recordingTime = Date().timeIntervalSince(start)
            }
        }
    }

    private func beginPlaybackUpdates() {
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let player = self.audioPlayer else { return }
            self.currentPlaybackTime = player.currentTime
        }
    }

    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
}

extension AudioService: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully _: Bool) {
        isPlaying = false
        playbackTimer?.invalidate()
        currentPlaybackTime = 0
    }
}
