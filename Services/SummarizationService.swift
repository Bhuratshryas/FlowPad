import Foundation

#if !targetEnvironment(simulator)
@preconcurrency import ZeticMLange
#endif

final class SummarizationService: @unchecked Sendable {
    static let shared = SummarizationService()

    private(set) var isModelLoaded = false
    private(set) var isLoadingModel = false
    private(set) var downloadProgress: Double = 0
    private(set) var loadError: String?

    #if !targetEnvironment(simulator)
    private var llmModel: ZeticMLangeLLMModel?
    #endif

    private let personalKey = "dev_73033372affb4a728c2df97683b6497d"
    private let modelName = "Steve/Medgemma-1.5-4b-it"

    private init() {}

    deinit {
        #if !targetEnvironment(simulator)
        llmModel?.forceDeinit()
        #endif
    }

    // MARK: - Model Lifecycle

    func loadModelIfNeeded() {
        guard !isModelLoaded, !isLoadingModel else { return }
        isLoadingModel = true
        loadError = nil
        downloadProgress = 0

        let svc = self
        Thread.detachNewThread {
            svc.loadModelSync()
        }
    }

    private func loadModelSync() {
        #if !targetEnvironment(simulator)
        do {
            let svc = self
            let model = try ZeticMLangeLLMModel(
                personalKey: personalKey,
                name: modelName,
                version: 1,
                modelMode: LLMModelMode.RUN_SPEED,
                onDownload: { progress in
                    DispatchQueue.main.async {
                        svc.downloadProgress = Double(progress)
                    }
                }
            )
            DispatchQueue.main.async {
                svc.llmModel = model
                svc.isModelLoaded = true
                svc.isLoadingModel = false
                svc.downloadProgress = 1.0
            }
        } catch {
            let svc = self
            DispatchQueue.main.async {
                svc.loadError = error.localizedDescription
                svc.isLoadingModel = false
            }
        }
        #else
        let svc = self
        DispatchQueue.main.async {
            svc.loadError = "Run on a real device for AI summarization."
            svc.isLoadingModel = false
        }
        #endif
    }

    // MARK: - Summarize

    func summarize(_ text: String) async -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if isLoadingModel {
            let deadline = Date().addingTimeInterval(120)
            while isLoadingModel && Date() < deadline {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }

        #if !targetEnvironment(simulator)
        if let result = await runLLM(trimmed) {
            return result
        }
        #endif

        return extractiveSummarize(trimmed)
    }

    // MARK: - LLM Inference (background thread, streaming tokens)

    #if !targetEnvironment(simulator)
    private func runLLM(_ text: String) async -> String? {
        guard let model = llmModel else { return nil }

        let prompt = """
        Extract 3-5 key points from this voice note transcript. \
        Format as bullet points starting with "• ". \
        Each point must be concise (under 12 words). \
        Highlight the single most important word per point in **bold**. \
        Do not copy full sentences from the transcript. \
        Only output the bullet points, nothing else.

        Transcript: \(String(text.prefix(1500)))
        """

        let result: String? = await withCheckedContinuation { continuation in
            Thread.detachNewThread {
                do {
                    try model.cleanUp()
                } catch {
                    // Safe to ignore if no previous context
                }

                do {
                    _ = try model.run(prompt)

                    var buffer = ""
                    while true {
                        let waitResult = model.waitForNextToken()
                        let token = waitResult.token
                        let generatedTokens = waitResult.generatedTokens

                        if generatedTokens == 0 {
                            break
                        }

                        buffer.append(token)
                    }

                    do {
                        try model.cleanUp()
                    } catch {
                        // Safe to ignore
                    }

                    let cleaned = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: cleaned.isEmpty ? nil : cleaned)
                } catch {
                    do {
                        try model.cleanUp()
                    } catch {
                        // Safe to ignore
                    }
                    continuation.resume(returning: nil)
                }
            }
        }
        return result
    }
    #endif

    // MARK: - Extractive Fallback

    private let stopWords: Set<String> = [
        "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
        "have", "has", "had", "do", "does", "did", "will", "would", "could",
        "should", "may", "might", "shall", "can", "need", "dare", "ought",
        "used", "to", "of", "in", "for", "on", "with", "at", "by", "from",
        "as", "into", "through", "during", "before", "after", "above", "below",
        "between", "out", "off", "over", "under", "again", "further", "then",
        "once", "here", "there", "when", "where", "why", "how", "all", "both",
        "each", "few", "more", "most", "other", "some", "such", "no", "nor",
        "not", "only", "own", "same", "so", "than", "too", "very", "just",
        "now", "and", "but", "or", "if", "while", "that", "this", "these",
        "those", "it", "its", "i", "me", "my", "we", "our", "you", "your",
        "he", "him", "his", "she", "her", "they", "them", "their", "what",
        "which", "who", "whom", "um", "uh", "like", "know", "think", "well",
        "yeah", "okay", "ok", "right", "going", "gonna", "got", "get", "don",
        "really", "actually", "basically", "just", "stuff", "thing", "things",
    ]

    private func extractiveSummarize(_ text: String) -> String {
        let sentences = splitSentences(text)
        guard sentences.count > 1 else {
            return "• \(compressSentence(text))"
        }

        let frequencies = wordFrequencies(in: text)
        var scored: [(index: Int, sentence: String, score: Double)] = sentences
            .enumerated()
            .map { index, sentence in
                var score = sentenceScore(sentence, frequencies: frequencies)
                if index == 0 { score *= 1.3 }
                if index == sentences.count - 1 { score *= 1.1 }
                let wordCount = sentence.split(separator: " ").count
                if wordCount < 4 { score *= 0.3 }
                if wordCount > 6 && wordCount < 25 { score *= 1.2 }
                return (index, sentence, score)
            }

        let targetCount = min(5, max(2, sentences.count * 3 / 10))
        scored.sort { $0.score > $1.score }

        let topKeywords = frequencies.sorted { $0.value > $1.value }.prefix(6).map(\.key)
        let keywordSet = Set(topKeywords)

        let selected = scored.prefix(targetCount)
            .sorted { $0.index < $1.index }
            .map { "• \(boldKeywords(compressSentence($0.sentence), keywords: keywordSet))" }

        return selected.joined(separator: "\n")
    }

    private func compressSentence(_ sentence: String) -> String {
        let fillers = [
            "I think that ", "I think ", "I was thinking ", "I mean ",
            "you know ", "I guess ", "so basically ", "basically ",
            "actually ", "like ", "well ", "so ", "and then ",
            "I was like ", "it's like ", "kind of ", "sort of ",
            "I feel like ", "to be honest ", "at the end of the day ",
            "the thing is ", "what I'm saying is ",
        ]
        var r = sentence
        for f in fillers where r.lowercased().hasPrefix(f.lowercased()) {
            r = String(r.dropFirst(f.count))
            r = r.prefix(1).uppercased() + r.dropFirst()
            break
        }
        let words = r.split(separator: " ")
        if words.count > 15 { r = words.prefix(14).joined(separator: " ") + "..." }
        return r.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func boldKeywords(_ text: String, keywords: Set<String>) -> String {
        var r = text
        for word in keywords.sorted(by: { $0.count > $1.count }).prefix(2) {
            let pat = "\\b\(NSRegularExpression.escapedPattern(for: word))\\b"
            if let re = try? NSRegularExpression(pattern: pat, options: .caseInsensitive),
               let m = re.firstMatch(in: r, range: NSRange(r.startIndex..., in: r)),
               let sr = Range(m.range, in: r)
            {
                r = r.replacingCharacters(in: sr, with: "**\(String(r[sr]))**")
            }
        }
        return r
    }

    private func splitSentences(_ text: String) -> [String] {
        var s: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { sub, _, _, _ in
            if let v = sub?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty { s.append(v) }
        }
        return s.isEmpty ? [text] : s
    }

    private func wordFrequencies(in text: String) -> [String: Int] {
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !stopWords.contains($0) && $0.count > 2 }
        var f: [String: Int] = [:]
        for w in words { f[w, default: 0] += 1 }
        return f
    }

    private func sentenceScore(_ sentence: String, frequencies: [String: Int]) -> Double {
        let words = sentence.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !stopWords.contains($0) }
        guard !words.isEmpty else { return 0 }
        return words.reduce(0.0) { $0 + Double(frequencies[$1] ?? 0) } / Double(words.count)
    }
}
