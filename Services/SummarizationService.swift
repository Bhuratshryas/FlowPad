import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

struct StructuredSummary {
    var summary: String
    var keyHighlights: [String]
    var actionItems: [String]
}

final class SummarizationService: @unchecked Sendable {
    static let shared = SummarizationService()
    private let llmChunkCharacterLimit = 3500

    private init() {}

    func summarize(_ text: String) async -> String {
        let s = await generateStructuredSummary(text)
        return s.summary
    }

    /// Two-word title for the note (e.g. "Team Standup", "Project Ideas").
    func generateTwoWordTitle(_ text: String) async -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "New Note" }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), let result = await generateTwoWordTitleWithLLM(trimmed) {
            return result
        }
        #endif
        return fallbackTitle(from: trimmed)
    }

    /// Answer a question about the note using the given context (summary + transcript/content).
    func ask(question: String, context: String) async -> String {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let c = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !c.isEmpty else { return "" }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), let result = await askWithLLM(question: q, context: c) {
            return result
        }
        #endif
        return "Ask is available when Apple Intelligence is enabled on this device."
    }

    /// Summary paragraph, key highlights, and action items.
    func generateStructuredSummary(_ text: String) async -> StructuredSummary {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return StructuredSummary(summary: "", keyHighlights: [], actionItems: [])
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), let result = await generateStructuredSummaryWithLLM(trimmed) {
            return result
        }
        #endif
        return fallbackStructuredSummary(trimmed)
    }

    // MARK: - Apple Foundation Models (on-device LLM, iOS 26+, Apple Intelligence)

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func generateTwoWordTitleWithLLM(_ text: String) async -> String? {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return nil }
        let instructions = Instructions("""
            You output exactly two words that capture the main topic of the following note. No punctuation, no extra words. Only the two words, title case.
            """)
        let session = LanguageModelSession(instructions: instructions)
        let input = String(text.prefix(1500))
        do {
            let response = try await session.respond(to: input)
            let raw = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            let words = raw.split(separator: " ").prefix(2).map(String.init)
            return words.joined(separator: " ").isEmpty ? nil : words.joined(separator: " ")
        } catch {
            return nil
        }
    }

    @available(iOS 26.0, *)
    private func generateStructuredSummaryWithLLM(_ text: String) async -> StructuredSummary? {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return nil }
        let instructions = Instructions("""
            You analyze a voice or written note and output exactly three sections in this format. Use only the labels below.

            SUMMARY:
            (One short paragraph, 1-3 sentences.)

            KEY HIGHLIGHTS:
            • (bullet 1)
            • (bullet 2)
            • (up to 5 bullets)

            ACTION ITEMS:
            • (action 1)
            • (action 2)
            • (up to 5 action items; start each with •)

            Output nothing else. No extra text before or after these sections.
            """)
        let chunks = chunkText(text, maxCharacters: llmChunkCharacterLimit)
        if chunks.count <= 1 {
            return await generateStructuredSummaryChunkWithLLM(text, instructions: instructions)
        }

        var chunkOutputs: [String] = []
        for chunk in chunks {
            if let partial = await generateStructuredSummaryChunkWithLLM(chunk, instructions: instructions) {
                var block = "SUMMARY: \(partial.summary)"
                if !partial.keyHighlights.isEmpty {
                    block += "\nKEY HIGHLIGHTS:\n" + partial.keyHighlights.map { "• \($0)" }.joined(separator: "\n")
                }
                if !partial.actionItems.isEmpty {
                    block += "\nACTION ITEMS:\n" + partial.actionItems.map { "• \($0)" }.joined(separator: "\n")
                }
                chunkOutputs.append(block)
            }
        }

        guard !chunkOutputs.isEmpty else {
            return nil
        }

        let combinedPrompt = """
        Combine the following chunk-level summaries into one final summary for the complete note.
        Keep all important decisions, commitments, and action items.

        \(chunkOutputs.joined(separator: "\n\n---\n\n"))
        """
        return await generateStructuredSummaryChunkWithLLM(combinedPrompt, instructions: instructions)
    }

    @available(iOS 26.0, *)
    private func generateStructuredSummaryChunkWithLLM(
        _ text: String,
        instructions: Instructions
    ) async -> StructuredSummary? {
        let session = LanguageModelSession(instructions: instructions)
        do {
            let response = try await session.respond(to: text)
            return parseStructuredOutput(response.content)
        } catch {
            return nil
        }
    }

    private func parseStructuredOutput(_ raw: String) -> StructuredSummary {
        var summary = ""
        var keyHighlights: [String] = []
        var actionItems: [String] = []
        let lines = raw.components(separatedBy: .newlines)
        var section = ""
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.uppercased().hasPrefix("SUMMARY:") {
                section = "summary"
                let rest = t.dropFirst("SUMMARY:".count).trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty { summary = rest }
                continue
            }
            if t.uppercased().hasPrefix("KEY HIGHLIGHTS:") {
                section = "highlights"
                let rest = t.dropFirst("KEY HIGHLIGHTS:".count).trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty, rest.hasPrefix("•") { keyHighlights.append(cleanBullet(rest)) }
                continue
            }
            if t.uppercased().hasPrefix("ACTION ITEMS:") {
                section = "items"
                let rest = t.dropFirst("ACTION ITEMS:".count).trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty, rest.hasPrefix("•") { actionItems.append(cleanBullet(rest)) }
                continue
            }
            if section == "summary", !t.isEmpty {
                summary = summary.isEmpty ? t : "\(summary) \(t)"
            } else if section == "highlights", t.hasPrefix("•") {
                keyHighlights.append(cleanBullet(t))
            } else if section == "items", t.hasPrefix("•") {
                actionItems.append(cleanBullet(t))
            }
        }
        return StructuredSummary(
            summary: summary.isEmpty ? raw.components(separatedBy: .newlines).first ?? "" : summary,
            keyHighlights: keyHighlights.isEmpty && summary.isEmpty ? extractiveSummarize(raw).components(separatedBy: .newlines).map { cleanBullet($0) }.filter { !$0.isEmpty } : keyHighlights,
            actionItems: actionItems
        )
    }

    private func cleanBullet(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        for prefix in ["•", "-", "*", "·"] {
            if t.hasPrefix(prefix) {
                t = String(t.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }
        return t
    }

    @available(iOS 26.0, *)
    private func askWithLLM(question: String, context: String) async -> String? {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return nil }
        let instructions = Instructions("""
            You answer the user's question about the following note. Use only the note content below. Be concise and helpful (1–4 sentences). If the note doesn't contain enough information, say so briefly.
            """)
        let session = LanguageModelSession(instructions: instructions)
        let prompt = "Note:\n\(String(context.prefix(12000)))\n\nQuestion: \(question)"
        do {
            let response = try await session.respond(to: prompt)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    #endif

    private func fallbackTitle(from text: String) -> String {
        var first = ""
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { sub, _, _, stop in
            if let s = sub?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                first = String(s.prefix(50))
                stop = true
            }
        }
        let words = first.split(separator: " ").prefix(2).map(String.init)
        return words.joined(separator: " ").isEmpty ? "New Note" : words.joined(separator: " ")
    }

    private func fallbackStructuredSummary(_ text: String) -> StructuredSummary {
        let bullets = extractiveSummarize(text)
        let lines = bullets.components(separatedBy: .newlines).map { cleanBullet($0) }.filter { !$0.isEmpty }
        let summary = lines.first ?? compressSentence(text)
        return StructuredSummary(
            summary: "• \(summary)",
            keyHighlights: Array(lines.prefix(5)),
            actionItems: []
        )
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func summarizeWithAppleLLM(_ text: String) async -> String? {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return nil }
        let instructions = Instructions("""
            You summarize voice note transcripts. Output 3-5 bullet points, each starting with "• ".
            Keep each point under 12 words. Highlight the single most important word per point in **bold**.
            Do not copy full sentences from the transcript. Output only the bullet points, nothing else.
            """)
        let session = LanguageModelSession(instructions: instructions)
        let input = String(text.prefix(4000))
        do {
            let response = try await session.respond(to: input)
            return response.content
        } catch {
            return nil
        }
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

    private func chunkText(_ text: String, maxCharacters: Int) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxCharacters else { return [trimmed] }

        func splitOversized(_ s: String) -> [String] {
            guard s.count > maxCharacters else { return [s] }
            var out: [String] = []
            var i = s.startIndex
            while i < s.endIndex {
                let j = s.index(i, offsetBy: maxCharacters, limitedBy: s.endIndex) ?? s.endIndex
                let part = String(s[i..<j]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !part.isEmpty { out.append(part) }
                i = j
            }
            return out.isEmpty ? [String(s.prefix(maxCharacters))] : out
        }

        var chunks: [String] = []
        var current = ""
        for sentence in splitSentences(trimmed) {
            for piece in splitOversized(sentence) {
                if current.isEmpty {
                    current = piece
                    continue
                }
                if current.count + piece.count + 1 <= maxCharacters {
                    current += " " + piece
                } else {
                    chunks.append(current)
                    current = piece
                }
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}
