import SwiftData
import SwiftUI

struct NotesListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VoiceNote.createdAt, order: .reverse) private var notes: [VoiceNote]
    @State private var showRecording = false
    @State private var searchText = ""
    @State private var selectedNote: VoiceNote?

    private var filteredNotes: [VoiceNote] {
        guard !searchText.isEmpty else { return notes }
        return notes.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || ($0.summary ?? "").localizedCaseInsensitiveContains(searchText)
                || ($0.transcript ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    private var groupedNotes: [(key: String, notes: [VoiceNote])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredNotes) { note -> String in
            if calendar.isDateInToday(note.createdAt) { return "Today" }
            if calendar.isDateInYesterday(note.createdAt) { return "Yesterday" }
            let fmt = DateFormatter()
            fmt.dateStyle = .medium
            return fmt.string(from: note.createdAt)
        }

        let priority = ["Today": 0, "Yesterday": 1]
        return grouped
            .map { (key: $0.key, notes: $0.value) }
            .sorted { a, b in
                let pa = priority[a.key] ?? 2
                let pb = priority[b.key] ?? 2
                if pa != pb { return pa < pb }
                let da = a.notes.first?.createdAt ?? .distantPast
                let db = b.notes.first?.createdAt ?? .distantPast
                return da > db
            }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Group {
                    if notes.isEmpty {
                        emptyStateView
                    } else {
                        notesList
                    }
                }

                recordBar
            }
            .navigationTitle("Voice Notes")
            .searchable(text: $searchText, prompt: "Search")
            .fullScreenCover(isPresented: $showRecording) {
                RecordingView { recording in
                    createNote(from: recording)
                }
            }
            .navigationDestination(item: $selectedNote) { note in
                NoteDetailView(note: note)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showRecording = true
                    } label: {
                        Image(systemName: "mic.badge.plus")
                    }
                }
            }
        }
        .tint(Color.accentColor)
        .task {
            _ = await TranscriptionService.shared.requestAuthorization()
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Voice Notes", systemImage: "waveform.badge.mic")
        } description: {
            Text("Tap Record to capture and automatically summarize your thoughts.")
        }
    }

    // MARK: - Notes List

    private var notesList: some View {
        List {
            ForEach(groupedNotes, id: \.key) { section in
                Section(section.key) {
                    ForEach(section.notes) { note in
                        NoteRowView(note: note)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard !note.isProcessing else { return }
                                selectedNote = note
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deleteNote(note)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                if let summary = note.summary {
                                    Button {
                                        UIPasteboard.general.string = summary
                                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                                    } label: {
                                        Label("Copy", systemImage: "doc.on.doc")
                                    }
                                    .tint(Color.accentColor)
                                }
                            }
                            .contextMenu {
                                noteContextMenu(for: note)
                            }
                    }
                }
            }

            Color.clear
                .frame(height: 80)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func noteContextMenu(for note: VoiceNote) -> some View {
        if !note.isProcessing {
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

    // MARK: - Record Bar

    private var recordBar: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showRecording = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "mic.fill")
                    .font(.body.weight(.semibold))
                Text("Record")
                    .font(.body.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 32)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .fill(Color.accentColor)
                    .shadow(color: Color.accentColor.opacity(0.3), radius: 12, y: 4)
            )
        }
        .padding(.bottom, 20)
    }

    // MARK: - Actions

    private func deleteNote(_ note: VoiceNote) {
        try? FileManager.default.removeItem(at: note.audioURL)
        withAnimation { modelContext.delete(note) }
    }

    private func createNote(from recording: (fileName: String, duration: TimeInterval)) {
        let note = VoiceNote(
            audioFileName: recording.fileName,
            duration: recording.duration
        )
        modelContext.insert(note)
        Task { await processNote(note) }
    }

    @MainActor
    private func processNote(_ note: VoiceNote) async {
        do {
            let transcript = try await TranscriptionService.shared.transcribe(audioURL: note.audioURL)
            note.transcript = transcript

            let summary = await SummarizationService.shared.summarize(transcript)
            note.summary = summary

            note.title = generateTitle(from: transcript)
            note.isProcessing = false
        } catch {
            note.transcript = "Transcription failed: \(error.localizedDescription)"
            note.summary = nil
            note.title = "Recording \(note.formattedDate)"
            note.isProcessing = false
        }
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

// MARK: - Note Row (Apple Notes style)

struct NoteRowView: View {
    let note: VoiceNote

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(note.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)

                Spacer()

                if note.isProcessing {
                    ProgressView()
                        .controlSize(.mini)
                }
            }

            HStack(spacing: 0) {
                Text(note.formattedDate)
                    .foregroundStyle(.secondary)

                if let summary = note.summary {
                    Text("  ")
                    Text(cleanPreview(summary))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .font(.subheadline)

            if note.isProcessing {
                Text("Transcribing...")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.vertical, 4)
    }

    private func cleanPreview(_ text: String) -> String {
        let first = text.components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? text
        return first
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "• ", with: "")
            .replacingOccurrences(of: "- ", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}
