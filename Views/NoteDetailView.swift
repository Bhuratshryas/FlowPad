import SwiftData
import SwiftUI

struct NoteDetailView: View {
    @Bindable var note: VoiceNote
    var audioService: AudioService
    @Environment(\.modelContext) private var modelContext
    @State private var showCopiedToast = false
    @State private var copiedLabel = ""
    @FocusState private var titleFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var isSummarizing = false
    @State private var isSuggestingTitle = false
    @State private var showNoteChat = false
    @State private var showAddRecording = false
    @State private var showUpdateSummaryAlert = false
    @State private var recordingsExpanded = true
    @State private var newSummaryAddition = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                askAboutNoteBar
                titleField
                metadataRow
                if note.hasAudio { recordingsSection }
                divider

                if note.isProcessing {
                    processingSection
                    divider
                }

                if let summary = note.summary, !summary.isEmpty {
                    summaryBlock(summary)
                    divider
                }
                if !note.keyHighlights.isEmpty {
                    keyHighlightsSection
                    divider
                }
                if !note.actionItemTexts.isEmpty {
                    actionItemsSection
                    divider
                }
                if showUserSummaryAdditionsSection {
                    userSummaryAdditionsSection
                    divider
                }
                if !note.isProcessing && hasContentForSummary && (note.summary == nil || note.summary?.isEmpty == true) {
                    generateSummarySection
                    divider
                }

                if !note.combinedTranscript.isEmpty {
                    sectionBlock(label: "Transcript", icon: "text.quote", text: note.combinedTranscript)
                    divider
                }
                if let written = note.writtenContent, !written.isEmpty || !note.attachedImageFileNames.isEmpty {
                    writtenNoteSection(written: note.writtenContent ?? "")
                    divider
                }

                Spacer(minLength: 100)
            }
            .padding(.horizontal, 20)
        }
        .background(AppTheme.surfaceRaised)
        .preferredColorScheme(.light)
        .toolbarColorScheme(.light, for: .navigationBar)
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
        .sheet(isPresented: $showNoteChat) {
            NoteChatView(note: note, context: noteContextForChat)
        }
        .fullScreenCover(isPresented: $showAddRecording) {
            RecordingView(dismissAfterSave: true) { recording in
                appendRecordingToNote(recording)
                showAddRecording = false
            }
        }
        .alert("Update summary?", isPresented: $showUpdateSummaryAlert) {
            Button("Update") {
                Task { await updateSummaryFromAllRecordings() }
            }
            Button("Later", role: .cancel) { }
        } message: {
            Text("New recording added. Update summary and action items from all recordings?")
        }
        .onDisappear {
            audioService.stopPlayback()
            try? modelContext.save()
        }
    }

    private var hasContextForChat: Bool {
        !noteContextForChat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var noteContextForChat: String {
        let transcriptPart = note.combinedTranscript.isEmpty ? nil : note.combinedTranscript
        let additionsBlock: String? = {
            guard !note.userSummaryAdditions.isEmpty else { return nil }
            return "Your additions:\n" + note.userSummaryAdditions.map { "• \($0)" }.joined(separator: "\n")
        }()
        return [note.summary, additionsBlock, transcriptPart, note.writtenContent]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    /// “Ask about this note” bar – always visible at top for consistent UI; opens chat when context is ready.
    private var askAboutNoteBar: some View {
        Button {
            guard hasContextForChat else { return }
            showNoteChat = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.body)
                    .foregroundStyle(hasContextForChat ? AppTheme.accent : AppTheme.textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ask about this note")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    if !hasContextForChat {
                        Text("Available after transcription")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.textTertiary)
                    } else if note.hasChatHistory {
                        Text("Previous messages are saved with this note")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .padding(.horizontal, AppTheme.spacingM)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radiusCard, style: .continuous)
                    .fill(AppTheme.surfaceBase)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.radiusCard, style: .continuous)
                            .strokeBorder(AppTheme.borderSubtle, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!hasContextForChat)
        .padding(.bottom, 16)
    }

    // MARK: - Title

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Title", text: $note.title, axis: .vertical)
                .font(.title.bold())
                .foregroundStyle(AppTheme.textPrimary)
                .focused($titleFocused)
                .submitLabel(.done)
            if let content = note.contentForSummary, !content.isEmpty, !note.isProcessing {
                Button {
                    suggestTitle()
                } label: {
                    HStack(spacing: 6) {
                        if isSuggestingTitle {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "wand.and.stars")
                                .font(.subheadline)
                        }
                        Text("Suggest title")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(AppTheme.accent)
                }
                .buttonStyle(.plain)
                .disabled(isSuggestingTitle)
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var hasContentForSummary: Bool {
        guard let c = note.contentForSummary, !c.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return true
    }

    private var showUserSummaryAdditionsSection: Bool {
        hasContentForSummary || !note.userSummaryAdditions.isEmpty
    }

    private func suggestTitle() {
        guard let content = note.contentForSummary, !content.isEmpty else { return }
        isSuggestingTitle = true
        Task {
            let title = await SummarizationService.shared.generateTwoWordTitle(content)
            await MainActor.run {
                if !title.isEmpty { note.title = title }
                isSuggestingTitle = false
                try? modelContext.save()
            }
        }
    }

    // MARK: - Generate summary (on demand)

    private var generateSummarySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Summary", systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .padding(.top, 16)
            if isSummarizing {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(AppTheme.textPrimary)
                    Text("Generating summary…")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textPrimary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            } else {
                Button {
                    generateSummary()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "wand.and.stars")
                            .font(.body.weight(.medium))
                        Text("Generate summary")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(AppTheme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppTheme.accent.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(AppTheme.accent.opacity(0.25), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 12)
    }

    private func generateSummary() {
        let content = summaryInputText
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isSummarizing = true
        Task {
            let structured = await SummarizationService.shared.generateStructuredSummary(content)
            await MainActor.run {
                note.summary = structured.summary
                note.keyHighlights = structured.keyHighlights
                note.actionItemTexts = structured.actionItems
                note.actionItemDone = Array(repeating: false, count: structured.actionItems.count)
                isSummarizing = false
                try? modelContext.save()
            }
        }
    }

    // MARK: - Metadata

    private var metadataRow: some View {
        HStack(spacing: 14) {
            Text(note.createdAt, format: .dateTime.weekday(.wide).month(.abbreviated).day().hour().minute())
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
            Spacer()
            if note.hasAudio {
                Text(formatTime(note.totalDuration))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(.bottom, 20)
    }

    // MARK: - Recordings (multiple per note, in dropdown)

    private var recordingsSection: some View {
        let count = note.allRecordingURLsAndDurations.count
        let header = HStack {
            Label("Recordings", systemImage: "waveform.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
            Spacer()
            Text("\(count) \(count == 1 ? "recording" : "recordings") · \(formatTime(note.totalDuration))")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.vertical, 4)

        return DisclosureGroup(isExpanded: $recordingsExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(note.allRecordingURLsAndDurations.enumerated()), id: \.offset) { index, item in
                    singlePlayerBar(url: item.url, duration: item.duration, label: "Recording \(index + 1)")
                }
                Button {
                    showAddRecording = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                        Text("Add recording")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(AppTheme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(AppTheme.accent, style: StrokeStyle(lineWidth: 2, dash: [6]))
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)
        } label: {
            header
        }
        .tint(AppTheme.textPrimary)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.surfaceBase)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(AppTheme.borderSubtle, lineWidth: 1)
                )
        )
        .padding(.bottom, 8)
    }

    private func singlePlayerBar(url: URL, duration: TimeInterval, label: String) -> some View {
        HStack(spacing: 12) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                audioService.togglePlayback(url: url)
            } label: {
                Image(systemName: audioService.isPlaying(url: url) ? "pause.fill" : "play.fill")
                    .font(.body)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(AppTheme.accent, in: Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(label)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                    Spacer(minLength: 8)
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        audioService.cyclePlaybackSpeed()
                    } label: {
                        Text(audioService.playbackRate >= 1.75 ? "2×" : "1×")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(AppTheme.accent)
                            .frame(minWidth: 28)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(AppTheme.accent.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.accent)
                    }
                }
                StaticWaveformView(
                    progress: duration > 0 && audioService.isPlaying(url: url) ? audioService.currentPlaybackTime / duration : 0
                )
                HStack {
                    Text(formatTime(audioService.isPlaying(url: url) ? audioService.currentPlaybackTime : 0))
                    Spacer()
                    Text(formatTime(duration))
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(AppTheme.textPrimary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.surfaceBase)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(AppTheme.borderSubtle, lineWidth: 1)
                )
        )
    }

    private func appendRecordingToNote(_ recording: (fileName: String, duration: TimeInterval)) {
        note.additionalAudioFileNames = (note.additionalAudioFileNames ?? []) + [recording.fileName]
        note.additionalDurations = (note.additionalDurations ?? []) + [recording.duration]
        note.additionalTranscripts = (note.additionalTranscripts ?? []) + [""] // placeholder until transcribed
        note.isProcessing = true
        try? modelContext.save()
        Task { await transcribeAndResummarizeLastRecording() }
    }

    @MainActor
    private func transcribeAndResummarizeLastRecording() async {
        let addNames = note.additionalAudioFileNames ?? []
        let addTranscripts = note.additionalTranscripts ?? []
        guard addNames.indices.contains(addTranscripts.count - 1) else { return }
        let idx = addTranscripts.count - 1
        let fileName = addNames[idx]
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = docs.appendingPathComponent(fileName)
        guard await TranscriptionService.shared.requestAuthorization() else {
            var t = note.additionalTranscripts ?? []
            if t.indices.contains(idx) { t[idx] = "Transcription not authorized" }
            note.additionalTranscripts = t
            note.isProcessing = false
            try? modelContext.save()
            return
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            var t = note.additionalTranscripts ?? []
            if t.indices.contains(idx) { t[idx] = "Transcription failed: file not found" }
            note.additionalTranscripts = t
            note.isProcessing = false
            try? modelContext.save()
            return
        }
        do {
            let transcript = try await TranscriptionService.shared.transcribe(audioURL: url)
            var t = note.additionalTranscripts ?? []
            if t.indices.contains(idx) { t[idx] = transcript }; note.additionalTranscripts = t
        } catch {
            var t = note.additionalTranscripts ?? []
            if t.indices.contains(idx) { t[idx] = "Transcription failed: \(error.localizedDescription)" }
            note.additionalTranscripts = t
        }
        note.isProcessing = false
        try? modelContext.save()
        await MainActor.run {
            showUpdateSummaryAlert = true
        }
    }

    @MainActor
    private func updateSummaryFromAllRecordings() async {
        let combined = summaryInputText
        guard !combined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isSummarizing = true
        let structured = await SummarizationService.shared.generateStructuredSummary(combined)
        note.summary = structured.summary
        note.keyHighlights = structured.keyHighlights
        note.actionItemTexts = structured.actionItems
        note.actionItemDone = Array(repeating: false, count: structured.actionItems.count)
        isSummarizing = false
        try? modelContext.save()
    }

    // MARK: - Summary block (paragraph)

    private func summaryBlock(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader("Summary", icon: "sparkles")
                Spacer()
                if !isSummarizing && hasContentForSummary {
                    Button {
                        generateSummary()
                    } label: {
                        Label("Regenerate", systemImage: "arrow.clockwise")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    copy(text.replacingOccurrences(of: "**", with: ""), label: "Summary")
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textPrimary)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 16)
            Text(text.replacingOccurrences(of: "**", with: ""))
                .font(.body)
                .foregroundStyle(AppTheme.textPrimary)
                .textSelection(.enabled)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 16)
    }

    // MARK: - Key Highlights

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.textPrimary)
    }

    private var keyHighlightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Key Highlights", icon: "list.bullet")
                .padding(.top, 16)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(note.keyHighlights.enumerated()), id: \.offset) { _, bullet in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 5))
                            .foregroundStyle(AppTheme.accent)
                        Text(bullet)
                            .font(.body)
                            .foregroundStyle(AppTheme.textPrimary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .padding(.bottom, 12)
    }

    // MARK: - Action Items (with checkboxes)

    private var actionItemsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Action Items", icon: "checklist")
                .padding(.top, 16)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(note.actionItemTexts.enumerated()), id: \.offset) { index, text in
                    let isDone = index < note.actionItemDone.count ? note.actionItemDone[index] : false
                    Button {
                        note.toggleActionItemDone(at: index)
                        try? modelContext.save()
                    } label: {
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(isDone ? AppTheme.accent : AppTheme.textPrimary)
                            Text(text)
                                .font(.body)
                                .strikethrough(isDone)
                                .foregroundStyle(AppTheme.textPrimary)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(AppTheme.surfaceBase)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(AppTheme.borderSubtle, lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.bottom, 12)
    }

    // MARK: - Your additions (user summary points)

    private var userSummaryAdditionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("Your additions", systemImage: "pencil.and.outline")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Text("Add points to your summary")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .padding(.top, 16)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(note.userSummaryAdditions.enumerated()), id: \.offset) { index, line in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 5))
                            .foregroundStyle(AppTheme.accent.opacity(0.55))
                        Text(line)
                            .font(.body)
                            .foregroundStyle(AppTheme.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            removeUserSummaryAddition(at: index)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.textTertiary)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 8)
                    .padding(.leading, 12)
                    .padding(.trailing, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AppTheme.surfaceBase)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(AppTheme.borderSubtle, lineWidth: 1)
                            )
                    )
                }

                HStack(alignment: .bottom, spacing: 10) {
                    TextField("Add a point…", text: $newSummaryAddition, axis: .vertical)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1 ... 4)
                    Button {
                        addUserSummaryAddition()
                    } label: {
                        Text("Add")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(canAddUserSummaryPoint ? AppTheme.accent : AppTheme.textTertiary.opacity(0.35))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canAddUserSummaryPoint)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppTheme.surfaceBase)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(AppTheme.borderSubtle, lineWidth: 1)
                        )
                )
            }
        }
        .padding(.bottom, 12)
    }

    private var canAddUserSummaryPoint: Bool {
        !newSummaryAddition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func addUserSummaryAddition() {
        let t = newSummaryAddition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        note.userSummaryAdditions.append(t)
        newSummaryAddition = ""
        try? modelContext.save()
    }

    private func removeUserSummaryAddition(at index: Int) {
        guard note.userSummaryAdditions.indices.contains(index) else { return }
        note.userSummaryAdditions.remove(at: index)
        try? modelContext.save()
    }

    // MARK: - Written note (Markdown + images)

    private func writtenNoteSection(written: String) -> some View {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Note", systemImage: "doc.text")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                if !written.isEmpty {
                    Button {
                        copy(written, label: "Note")
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 16)
            if !written.isEmpty {
                markdownView(written)
                    .padding(.bottom, 4)
            }
            if !note.attachedImageFileNames.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                    ForEach(note.attachedImageFileNames, id: \.self) { name in
                        let url = docs.appendingPathComponent(name)
                        if let data = try? Data(contentsOf: url),
                           let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(minWidth: 100, minHeight: 100)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
            }
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func markdownView(_ raw: String) -> some View {
        if let attr = try? AttributedString(markdown: raw) {
            Text(attr)
                .font(.body)
                .foregroundStyle(AppTheme.textPrimary)
                .textSelection(.enabled)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(raw)
                .font(.body)
                .foregroundStyle(AppTheme.textPrimary)
                .textSelection(.enabled)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Section Block (Transcript)

    private func sectionBlock(label: String, icon: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(label, systemImage: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Button {
                    copy(text, label: label)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textPrimary)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 16)
            Text(text)
                .font(.body)
                .foregroundStyle(AppTheme.textPrimary)
                .textSelection(.enabled)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Processing

    private var processingSection: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
                .tint(AppTheme.textPrimary)
            Text("Transcribing…")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textPrimary)
        }
        .padding(.vertical, 20)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                note.isPinned.toggle()
                try? modelContext.save()
            } label: {
                Image(systemName: note.isPinned ? "pin.fill" : "pin")
                    .foregroundStyle(note.isPinned ? AppTheme.pin : AppTheme.accent)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if let summary = note.summary {
                    Button { copy(summary, label: "Summary") } label: {
                        Label("Copy Summary", systemImage: "doc.on.doc")
                    }
                }
                if !note.combinedTranscript.isEmpty {
                    Button { copy(note.combinedTranscript, label: "Transcript") } label: {
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
                    .foregroundStyle(AppTheme.accent)
            }
        }
        ToolbarItem(placement: .keyboard) {
            HStack {
                Spacer()
                Button("Done") { titleFocused = false }
                    .fontWeight(.semibold)
                    .foregroundStyle(AppTheme.textPrimary)
            }
        }
    }

    // MARK: - Divider

    private var divider: some View {
        Rectangle()
            .fill(AppTheme.border)
            .frame(height: 1)
            .padding(.vertical, AppTheme.spacingS)
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
        if let s = note.summary { parts.append("Summary:\n\(s)") }
        if !note.keyHighlights.isEmpty {
            parts.append("Key Highlights:\n" + note.keyHighlights.map { "• \($0)" }.joined(separator: "\n"))
        }
        if !note.actionItemTexts.isEmpty {
            parts.append("Action Items:\n" + note.actionItemTexts.enumerated().map { i in
                (i.offset < note.actionItemDone.count && note.actionItemDone[i.offset] ? "☑ " : "☐ ") + note.actionItemTexts[i.offset]
            }.joined(separator: "\n"))
        }
        if !note.userSummaryAdditions.isEmpty {
            parts.append("Your additions:\n" + note.userSummaryAdditions.map { "• \($0)" }.joined(separator: "\n"))
        }
        if !note.combinedTranscript.isEmpty { parts.append("Transcript:\n\(note.combinedTranscript)") }
        if let w = note.writtenContent { parts.append("Note:\n\(w)") }
        return parts.joined(separator: "\n\n")
    }

    private var summaryInputText: String {
        [note.combinedTranscript, note.writtenContent]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private func copy(_ text: String, label: String) {
        UIPasteboard.general.string = text
        copiedLabel = label
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { showCopiedToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { showCopiedToast = false }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let m = Int(time) / 60
        let s = Int(time) % 60
        return String(format: "%d:%02d", m, s)
    }
}
