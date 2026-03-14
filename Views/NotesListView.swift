import SwiftData
import SwiftUI

struct NotesListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VoiceNote.createdAt, order: .reverse) private var notes: [VoiceNote]
    @State private var showRecording = false
    @State private var showWriteNote = false
    @State private var searchText = ""
    @State private var selectedNote: VoiceNote?
    @State private var showRecordingSavedToast = false
    @State private var noteToOpenAfterWrite: VoiceNote?
    @State private var audioService = AudioService()

    private var filteredNotes: [VoiceNote] {
        guard !searchText.isEmpty else { return notes }
        return notes.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || ($0.summary ?? "").localizedCaseInsensitiveContains(searchText)
                || ($0.transcript ?? "").localizedCaseInsensitiveContains(searchText)
                || ($0.writtenContent ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    private var groupedNotes: [(key: String, notes: [VoiceNote])] {
        let pinned = filteredNotes.filter(\.isPinned).sorted { $0.createdAt > $1.createdAt }
        let unpinned = filteredNotes.filter { !$0.isPinned }
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: unpinned) { note -> String in
            if calendar.isDateInToday(note.createdAt) { return "Today" }
            if calendar.isDateInYesterday(note.createdAt) { return "Yesterday" }
            let fmt = DateFormatter()
            fmt.dateStyle = .medium
            return fmt.string(from: note.createdAt)
        }
        let priority = ["Today": 0, "Yesterday": 1]
        var sections: [(key: String, notes: [VoiceNote])] = []
        if !pinned.isEmpty {
            sections.append(("Pinned", pinned))
        }
        let rest = grouped
            .map { (key: $0.key, notes: $0.value) }
            .sorted { a, b in
                let pa = priority[a.key] ?? 2
                let pb = priority[b.key] ?? 2
                if pa != pb { return pa < pb }
                let da = a.notes.first?.createdAt ?? .distantPast
                let db = b.notes.first?.createdAt ?? .distantPast
                return da > db
            }
        sections.append(contentsOf: rest)
        return sections
    }

    var body: some View {
        NavigationStack {
            Group {
                if notes.isEmpty {
                    emptyStateView
                } else {
                    notesList
                }
            }
            .background(AppTheme.surfaceBase)
            .preferredColorScheme(.light)
            .toolbarColorScheme(.light, for: .navigationBar)
            .navigationTitle("Notes")
            .searchable(text: $searchText, prompt: "Search notes")
            .fullScreenCover(isPresented: $showRecording) {
                RecordingView(dismissAfterSave: true) { recording in
                    createVoiceNote(from: recording)
                    showRecording = false
                }
            }
            .overlay(alignment: .top) {
                if showRecordingSavedToast {
                    recordingSavedToast
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(10)
                }
            }
            .sheet(isPresented: $showWriteNote, onDismiss: {
                if let note = noteToOpenAfterWrite {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        selectedNote = note
                    }
                    noteToOpenAfterWrite = nil
                }
            }) {
                WriteNoteView { title, body, imageFileNames in
                    noteToOpenAfterWrite = createWrittenNote(title: title, body: body, imageFileNames: imageFileNames)
                }
            }
            .navigationDestination(item: $selectedNote) { note in
                NoteDetailView(note: note, audioService: audioService)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showRecording = true
                        } label: {
                            Label("Record", systemImage: "mic.fill")
                        }
                        Button {
                            showWriteNote = true
                        } label: {
                            Label("Write Note", systemImage: "square.and.pencil")
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(AppTheme.surfaceOverlay)
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(AppTheme.accent)
                        }
                        .frame(width: 32, height: 32)
                    }
                }
            }
        }
        .tint(AppTheme.accent)
        .task {
            _ = await TranscriptionService.shared.requestAuthorization()
        }
    }

    // MARK: - Recording saved toast

    private var recordingSavedToast: some View {
        HStack(spacing: AppTheme.spacingS) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.white)
            Text("Recording saved")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, AppTheme.spacingL)
        .padding(.vertical, 12)
        .background(Capsule().fill(AppTheme.accent))
        .padding(.top, AppTheme.spacingS)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "note.text")
                .font(.system(size: 56, weight: .ultraLight))
                .foregroundStyle(AppTheme.textTertiary)
            Text("No Notes")
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
            Text("Record a voice note or write a note to get started.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Notes List (Notes-app style)

    private var notesList: some View {
        List {
            ForEach(groupedNotes, id: \.key) { section in
                Section {
                    ForEach(section.notes) { note in
                        NoteRowView(note: note)
                            .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                            .listRowBackground(
                                RoundedRectangle(cornerRadius: AppTheme.radiusCard, style: .continuous)
                                    .fill(AppTheme.surfaceRaised)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: AppTheme.radiusCard, style: .continuous)
                                            .strokeBorder(AppTheme.borderSubtle, lineWidth: 0.5)
                                    )
                            )
                            .listRowSeparator(.hidden)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedNote = note
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deleteNote(note)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .tint(.red)
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    togglePin(note)
                                } label: {
                                    Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin")
                                }
                                .tint(.orange)
                                if let summary = note.summary {
                                    Button {
                                        UIPasteboard.general.string = summary
                                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                                    } label: {
                                        Label("Copy", systemImage: "doc.on.doc")
                                    }
                                    .tint(AppTheme.accent)
                                }
                            }
                            .contextMenu {
                                noteContextMenu(for: note)
                            }
                    }
                } header: {
                    Text(section.key.uppercased())
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(AppTheme.textTertiary)
                        .padding(.top, 22)
                        .padding(.bottom, 6)
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Color.clear
                .frame(height: 32)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.surfaceBase)
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func noteContextMenu(for note: VoiceNote) -> some View {
        if !note.isProcessing {
            Button {
                togglePin(note)
            } label: {
                Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin")
            }
            if let summary = note.summary {
                Button {
                    UIPasteboard.general.string = summary
                } label: {
                    Label("Copy Summary", systemImage: "doc.on.doc")
                }
            }
            if let transcript = note.transcript {
                Button {
                    UIPasteboard.general.string = transcript
                } label: {
                    Label("Copy Transcript", systemImage: "doc.on.clipboard")
                }
            }
            Divider()
            Button(role: .destructive) {
                deleteNote(note)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Actions

    private func deleteNote(_ note: VoiceNote) {
        if note.hasAudio, let url = note.audioURL {
            try? FileManager.default.removeItem(at: url)
        }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        for name in note.attachedImageFileNames {
            try? FileManager.default.removeItem(at: docs.appendingPathComponent(name))
        }
        withAnimation { modelContext.delete(note) }
    }

    private func togglePin(_ note: VoiceNote) {
        note.isPinned.toggle()
        try? modelContext.save()
    }

    private func createVoiceNote(from recording: (fileName: String, duration: TimeInterval)) {
        let note = VoiceNote(
            title: "New Recording",
            audioFileName: recording.fileName,
            duration: recording.duration
        )
        modelContext.insert(note)
        do {
            try modelContext.save()
        } catch {
            // If save fails (e.g. schema), note may still appear in memory
        }
        selectedNote = note
        showRecordingSavedToast = true
        Task { await processVoiceNote(note) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            showRecordingSavedToast = false
        }
    }

    @discardableResult
    private func createWrittenNote(title: String, body: String, imageFileNames: [String] = []) -> VoiceNote? {
        let note = VoiceNote(
            title: title.isEmpty ? "New Note" : title,
            writtenContent: body.isEmpty ? nil : body,
            attachedImageFileNames: imageFileNames
        )
        modelContext.insert(note)
        do {
            try modelContext.save()
            return note
        } catch {
            return nil
        }
    }

    @MainActor
    private func processVoiceNote(_ note: VoiceNote) async {
        guard await TranscriptionService.shared.requestAuthorization() else { note.isProcessing = false; return }
        do {
            guard let url = note.audioURL else { note.isProcessing = false; return }
            let transcript = try await TranscriptionService.shared.transcribe(audioURL: url)
            note.transcript = transcript
            note.title = generateTitle(from: transcript)
            note.isProcessing = false
        } catch {
            note.transcript = "Transcription failed: \(error.localizedDescription)"
            note.title = "Recording \(note.formattedDate)"
            note.isProcessing = false
        }
        try? modelContext.save()
    }

    private func generateTitle(from text: String) -> String {
        let limit = 44
        var first = ""
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { sub, _, _, stop in
            if let s = sub?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                first = s
                stop = true
            }
        }
        guard !first.isEmpty else { return "New Recording" }
        guard first.count > limit else { return first }
        let truncated = String(first.prefix(limit))
        if let space = truncated.lastIndex(of: " ") {
            return String(truncated[..<space]) + "..."
        }
        return truncated + "..."
    }
}

// MARK: - Note Row (Notes-app style)

struct NoteRowView: View {
    let note: VoiceNote

    private var previewText: String {
        if let s = note.summary, !s.isEmpty { return cleanPreview(s) }
        if let t = note.transcript, !t.isEmpty { return cleanPreview(t) }
        if let w = note.writtenContent, !w.isEmpty { return cleanPreview(w) }
        return ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AppTheme.pin)
                }
                Text(note.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if note.isProcessing {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.9)
                        .tint(AppTheme.textTertiary)
                }
            }
            if !previewText.isEmpty {
                Text(previewText)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineSpacing(2)
                    .lineLimit(2)
            }
            HStack(spacing: 0) {
                Text(note.formattedDate)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(AppTheme.textTertiary)
                if note.hasAudio {
                    Text(" · \(note.formattedDuration)")
                        .font(.system(size: 13, weight: .regular).monospacedDigit())
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func cleanPreview(_ text: String) -> String {
        let first = text.components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? text
        let cleaned = first
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "• ", with: "")
            .trimmingCharacters(in: .whitespaces)
        let truncated = String(cleaned.prefix(120))
        return truncated + (cleaned.count > 120 ? "…" : "")
    }
}
