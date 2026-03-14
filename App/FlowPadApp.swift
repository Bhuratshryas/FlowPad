import SwiftData
import SwiftUI

@main
struct FlowPadApp: App {
    init() {
        // App accent blue for nav bar icons/titles (#38B6FF)
        let accentBlue = UIColor(red: 56/255, green: 182/255, blue: 1, alpha: 1)
        UINavigationBar.appearance().tintColor = accentBlue
        UINavigationBar.appearance().largeTitleTextAttributes = [.foregroundColor: accentBlue]
        UINavigationBar.appearance().titleTextAttributes = [.foregroundColor: accentBlue]
        UISearchBar.appearance().tintColor = accentBlue
        UITextField.appearance(whenContainedInInstancesOf: [UISearchBar.self]).defaultTextAttributes = [.foregroundColor: accentBlue]
    }

    var body: some Scene {
        WindowGroup {
            NotesListView()
                .preferredColorScheme(.light)
        }
        .modelContainer(for: VoiceNote.self)
    }
}
