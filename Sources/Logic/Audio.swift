import Foundation
import AVFoundation
import Speech
import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Storage

enum AudioStore {
    static var directory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Recordings", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    static func delete(_ name: String?) {
        guard let name else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }

    static func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}

// MARK: - Recorder

final class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false
    @Published var elapsed: TimeInterval = 0
    @Published var levels: [CGFloat] = Array(repeating: 0.05, count: 36)

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private(set) var fileName: String?

    func requestPermission(_ done: @escaping (Bool) -> Void) {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async { done(granted) }
        }
    }

    @discardableResult
    func start() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let name = "debrief-\(Int(Date().timeIntervalSince1970)).m4a"
            let url = AudioStore.directory.appendingPathComponent(name)
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let r = try AVAudioRecorder(url: url, settings: settings)
            r.isMeteringEnabled = true
            r.delegate = self
            guard r.record() else { return false }
            recorder = r
            fileName = name
            elapsed = 0
            isRecording = true
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
                self?.tick()
            }
            return true
        } catch {
            return false
        }
    }

    private func tick() {
        guard let r = recorder, r.isRecording else { return }
        r.updateMeters()
        let power = r.averagePower(forChannel: 0)
        let level = CGFloat(max(0.05, min(1.0, (power + 50) / 50)))
        var next = levels
        next.removeFirst()
        next.append(level)
        levels = next
        elapsed = r.currentTime
    }

    /// Stops and returns (file name, duration in seconds).
    func stop() -> (String, Double)? {
        guard let r = recorder else { return nil }
        let duration = r.currentTime
        r.stop()
        timer?.invalidate()
        timer = nil
        recorder = nil
        isRecording = false
        levels = Array(repeating: 0.05, count: 36)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        guard let name = fileName else { return nil }
        return (name, duration)
    }

    func cancel() {
        _ = stop()
        AudioStore.delete(fileName)
        fileName = nil
    }
}

// MARK: - Player

final class AudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var progress: Double = 0
    private var player: AVAudioPlayer?
    private var timer: Timer?

    func toggle(url: URL) {
        if isPlaying {
            player?.pause()
            isPlaying = false
            timer?.invalidate()
            return
        }
        do {
            if player == nil || player?.url != url {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                try AVAudioSession.sharedInstance().setActive(true)
                let p = try AVAudioPlayer(contentsOf: url)
                p.delegate = self
                player = p
            }
            player?.play()
            isPlaying = true
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self, let p = self.player, p.duration > 0 else { return }
                self.progress = p.currentTime / p.duration
            }
        } catch {
            isPlaying = false
        }
    }

    func stop() {
        player?.stop()
        timer?.invalidate()
        isPlaying = false
        progress = 0
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.timer?.invalidate()
            self.isPlaying = false
            self.progress = 0
        }
    }
}

// MARK: - Transcription (on device when supported)

final class TranscriptionJob {
    var recognizer: SFSpeechRecognizer?
    var task: SFSpeechRecognitionTask?
}

enum Transcriber {
    static func requestAuth() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }

    static func transcribe(url: URL, localeID: String) async -> String {
        guard await requestAuth() else { return "" }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeID)), recognizer.isAvailable else {
            return ""
        }
        let job = TranscriptionJob()
        job.recognizer = recognizer
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        let text: String = await withCheckedContinuation { cont in
            var finished = false
            job.task = recognizer.recognitionTask(with: request) { result, error in
                if finished { return }
                if let result, result.isFinal {
                    finished = true
                    cont.resume(returning: result.bestTranscription.formattedString)
                } else if error != nil {
                    finished = true
                    cont.resume(returning: "")
                }
            }
        }
        withExtendedLifetime(job) {}
        return text
    }
}

// MARK: - Insights (tags, products, summary)

enum VisitInsights {
    static let tagKeywords: [String: [String]] = [
        "Samples given": ["sample"],
        "Follow-up needed": ["follow up", "follow-up", "next visit", "call back", "come back", "remind"],
        "Asked for study": ["study", "studies", "paper", "trial", "publication", "data on"],
        "Objection": ["concern", "objection", "expensive", "price", "side effect", "not convinced", "prefers"],
        "Positive": ["agreed", "positive", "will prescribe", "interested", "convinced", "happy with"],
        "Materials given": ["brochure", "leaflet", "material", "booklet"]
    ]

    static func detectTags(in text: String) -> Set<String> {
        let lower = text.lowercased()
        var found = Set<String>()
        for (tag, words) in tagKeywords where words.contains(where: { lower.contains($0) }) {
            found.insert(tag)
        }
        return found
    }

    static func detectProducts(in text: String, products: [String]) -> Set<String> {
        let lower = text.lowercased()
        return Set(products.filter { lower.contains($0.lowercased()) })
    }

    static func quickSummary(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        var sentences: [String] = []
        trimmed.enumerateSubstrings(in: trimmed.startIndex..., options: .bySentences) { sub, _, _, stop in
            if let sub { sentences.append(sub.trimmingCharacters(in: .whitespaces)) }
            if sentences.count >= 2 { stop = true }
        }
        let s = sentences.joined(separator: " ")
        return s.isEmpty ? String(trimmed.prefix(200)) : s
    }
}

enum Summarizer {
    /// Uses Apple Intelligence on supported iPhones (iOS 26+). Returns nil when not available.
    static func summarize(_ transcript: String) async -> String? {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > 40 else { return nil }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else { return nil }
            do {
                let session = LanguageModelSession(instructions: "You summarize a pharmaceutical sales rep's spoken debrief recorded right after a doctor visit. Reply with 2 to 4 short bullet points: what was discussed, what the doctor asked for, and the next step. No preamble, no headings.")
                let response = try await session.respond(to: text)
                let out = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                return out.isEmpty ? nil : out
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }
}
