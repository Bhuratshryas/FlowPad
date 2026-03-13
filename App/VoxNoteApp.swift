import SwiftData
import SwiftUI

@main
struct VoxNoteApp: App {
    init() {
        SummarizationService.shared.loadModelIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            NotesListView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(for: VoiceNote.self)
    }
}
