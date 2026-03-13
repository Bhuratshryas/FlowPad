import SwiftData
import SwiftUI

struct NoteDetailView: View {
    @Bindable var note: VoiceNote
    @State private var audioService = AudioService()
    @State private var showCopiedToast = false
    @State private var copiedLabel = ""
    @FocusState private var titleFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                titleField
                metadataRow
                playerBar
                divider

                if note.isProcessing {
                    processingSection
                }

                if let summary = note.summary, !summary.isEmpty {
                    summarySection(summary)
                    divider
                }

                if let transcript = note.transcript, !transcript.isEmpty {
                    sectionBlock(
                        label: "Transcript",
                        icon: "text.quote",
                        text: transcript
                    )
                }

                Spacer(minLength: 80)
            }
            .padding(.horizontal, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarItems }
        .overlay(alignment: .top) {
            if showCopiedToast {
                toast
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .onDisappear {
            audioService.stopPlayback()
        }
    }

    // MARK: - Title (tap to edit, like Notes app)

    private var titleField: some View {
        TextField("Title", text: $note.title, axis: .vertical)
            .font(.title.bold())
            .focused($titleFocused)
            .submitLabel(.done)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    // MARK: - Metadata

    private var metadataRow: some View {
        HStack(spacing: 14) {
            Text(note.createdAt, format: .dateTime.weekday(.wide).month(.abbreviated).day().hour().minute())
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()

            Text(note.formattedDuration)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 16)
    }

    // MARK: - Compact Audio Player

    private var playerBar: some View {
        HStack(spacing: 12) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                audioService.togglePlayback(url: note.audioURL)
            } label: {
                Image(systemName: audioService.isPlaying ? "pause.fill" : "play.fill")
                    .font(.body)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor, in: Circle())
                    .contentTransition(.symbolEffect(.replace))
            }

            VStack(alignment: .leading, spacing: 4) {
                StaticWaveformView(
                    progress: note.duration > 0
                        ? audioService.currentPlaybackTime / note.duration
                        : 0
                )

                HStack {
                    Text(formatTime(audioService.isPlaying ? audioService.currentPlaybackTime : 0))
                    Spacer()
                    Text(formatTime(note.duration))
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .padding(.bottom, 8)
    }

    // MARK: - Section Block

    private func sectionBlock(label: String, icon: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(label, systemImage: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    copy(text, label: label)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 16)

            Text(text)
                .font(.body)
                .textSelection(.enabled)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Rich Summary

    private func summarySection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Summary", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    copy(text.replacingOccurrences(of: "**", with: ""), label: "Summary")
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 16)

            let bullets = parseBullets(text)
            if bullets.isEmpty {
                renderRichLine(text)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(bullets.enumerated()), id: \.offset) { _, bullet in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 6, height: 6)
                                .offset(y: 1)

                            renderRichLine(bullet)
                        }
                    }
                }
            }
        }
        .padding(.bottom, 8)
    }

    private func parseBullets(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { line in
                var cleaned = line.trimmingCharacters(in: .whitespaces)
                for prefix in ["• ", "- ", "* ", "· "] {
                    if cleaned.hasPrefix(prefix) {
                        cleaned = String(cleaned.dropFirst(prefix.count))
                        break
                    }
                }
                return cleaned
            }
            .filter { !$0.isEmpty }
    }

    private func renderRichLine(_ text: String) -> some View {
        let parts = parseInlineBold(text)
        return parts.reduce(Text("")) { result, part in
            if part.isBold {
                return result + Text(part.text).fontWeight(.semibold).foregroundColor(.primary)
            } else {
                return result + Text(part.text).foregroundColor(.secondary)
            }
        }
        .font(.body)
        .lineSpacing(2)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }

    private struct RichPart {
        let text: String
        let isBold: Bool
    }

    private func parseInlineBold(_ input: String) -> [RichPart] {
        var parts: [RichPart] = []
        var remaining = input

        while let startRange = remaining.range(of: "**") {
            let before = String(remaining[remaining.startIndex ..< startRange.lowerBound])
            if !before.isEmpty { parts.append(RichPart(text: before, isBold: false)) }

            let afterStart = remaining[startRange.upperBound...]
            if let endRange = afterStart.range(of: "**") {
                let boldText = String(afterStart[afterStart.startIndex ..< endRange.lowerBound])
                parts.append(RichPart(text: boldText, isBold: true))
                remaining = String(afterStart[endRange.upperBound...])
            } else {
                remaining = String(afterStart)
                break
            }
        }

        if !remaining.isEmpty {
            parts.append(RichPart(text: remaining, isBold: false))
        }

        return parts.isEmpty ? [RichPart(text: input, isBold: false)] : parts
    }

    // MARK: - Processing

    private var processingSection: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text("Transcribing & summarizing...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 20)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if let summary = note.summary {
                    Button { copy(summary, label: "Summary") } label: {
                        Label("Copy Summary", systemImage: "doc.on.doc")
                    }
                }

                if let transcript = note.transcript {
                    Button { copy(transcript, label: "Transcript") } label: {
                        Label("Copy Transcript", systemImage: "doc.on.clipboard")
                    }
                }

                Button { copy(shareableText, label: "All") } label: {
                    Label("Copy All", systemImage: "square.on.square")
                }

                Divider()

                ShareLink(item: shareableText) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .symbolRenderingMode(.hierarchical)
            }
        }

        ToolbarItem(placement: .keyboard) {
            HStack {
                Spacer()
                Button("Done") { titleFocused = false }
                    .fontWeight(.semibold)
            }
        }
    }

    // MARK: - Divider

    private var divider: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(height: 0.5)
            .padding(.vertical, 4)
    }

    // MARK: - Toast

    private var toast: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.caption.bold())
            Text("\(copiedLabel) copied")
                .font(.subheadline.weight(.medium))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        .padding(.top, 4)
    }

    // MARK: - Helpers

    private var shareableText: String {
        var parts = [note.title]
        if let summary = note.summary { parts.append("\nSummary:\n\(summary)") }
        if let transcript = note.transcript { parts.append("\nTranscript:\n\(transcript)") }
        return parts.joined(separator: "\n")
    }

    private func copy(_ text: String, label: String) {
        UIPasteboard.general.string = text
        copiedLabel = label
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            showCopiedToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                showCopiedToast = false
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let m = Int(time) / 60
        let s = Int(time) % 60
        return String(format: "%d:%02d", m, s)
    }
}
