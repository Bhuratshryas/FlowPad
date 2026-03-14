import AVFoundation
import Foundation

@Observable
final class AudioService: NSObject, @unchecked Sendable {
    var isRecording = false
    var isPaused = false
    var isPlaying = false
    var recordingTime: TimeInterval = 0
    var currentPlaybackTime: TimeInterval = 0
    var meterLevel: Float = 0

    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var playbackURL: URL?
    private var meterTimer: Timer?
    private var playbackTimer: Timer?
    private var startTime: Date?
    private var accumulatedRecordingTime: TimeInterval = 0
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
                options: [.defaultToSpeaker, .allowBluetoothHFP]
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
            accumulatedRecordingTime = 0
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            isRecording = true
            isPaused = false
            startTime = Date()
            beginMeterUpdates()
        } catch {
            print("Recording failed to start: \(error)")
        }

        return fileName
    }

    func pauseRecording() {
        guard isRecording, !isPaused, let recorder = audioRecorder, recorder.isRecording else { return }
        accumulatedRecordingTime = recordingTime
        recorder.pause()
        meterTimer?.invalidate()
        meterTimer = nil
        startTime = nil
        isPaused = true
    }

    func resumeRecording() {
        guard isRecording, isPaused, let recorder = audioRecorder else { return }
        recorder.record()
        startTime = Date()
        isPaused = false
        beginMeterUpdates()
    }

    func stopRecording() -> (fileName: String, duration: TimeInterval) {
        let duration = recordingTime
        let fileName = currentFileName ?? ""

        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
        isPaused = false
        meterTimer?.invalidate()
        meterTimer = nil
        recordingTime = 0
        accumulatedRecordingTime = 0
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
        isPaused = false
        meterTimer?.invalidate()
        meterTimer = nil
        recordingTime = 0
        accumulatedRecordingTime = 0
        startTime = nil
        meterLevel = 0
        currentFileName = nil
    }

    // MARK: - Playback

    func play(url: URL) {
        stopPlayback()
        let fileURL = url.standardizedFileURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("Playback failed: file not found at \(fileURL.path)")
            return
        }
        if Thread.isMainThread {
            performPlay(url: fileURL)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.performPlay(url: fileURL)
            }
        }
    }

    private func performPlay(url: URL) {
        assert(Thread.isMainThread, "performPlay must run on main thread")
        do {
            let session = AVAudioSession.sharedInstance()
            // Keep playAndRecord so we don’t fight with recording; ensure playback can route to speaker
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let player = try AVAudioPlayer(contentsOf: url)
            audioPlayer = player
            player.delegate = self
            player.prepareToPlay()
            if !player.play() {
                print("Playback failed: play() returned false")
                return
            }
            playbackURL = url
            isPlaying = true
            beginPlaybackUpdates()
        } catch {
            print("Playback failed: \(error)")
        }
    }

    func stopPlayback() {
        if Thread.isMainThread {
            performStopPlayback()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.performStopPlayback()
            }
        }
    }

    private func performStopPlayback() {
        assert(Thread.isMainThread, "performStopPlayback must run on main thread")
        playbackTimer?.invalidate()
        playbackTimer = nil
        audioPlayer?.stop()
        audioPlayer = nil
        playbackURL = nil
        isPlaying = false
        currentPlaybackTime = 0
    }

    /// True when the given URL is the one currently playing.
    func isPlaying(url: URL) -> Bool {
        guard isPlaying, let current = playbackURL else { return false }
        return current.standardizedFileURL == url.standardizedFileURL
    }

    func togglePlayback(url: URL) {
        if isPlaying(url: url) {
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
                self.recordingTime = self.accumulatedRecordingTime + Date().timeIntervalSince(start)
            }
        }
    }

    private func beginPlaybackUpdates() {
        let timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let player = self.audioPlayer else { return }
            let time = player.currentTime
            if Thread.isMainThread {
                self.currentPlaybackTime = time
            } else {
                DispatchQueue.main.async { self.currentPlaybackTime = time }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        playbackTimer = timer
    }

    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
}

extension AudioService: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully _: Bool) {
        // Delegate can be called on a background thread; always update state on main.
        DispatchQueue.main.async { [weak self] in
            self?.performStopPlayback()
        }
    }
}
