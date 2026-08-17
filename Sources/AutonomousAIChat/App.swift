import SwiftUI

@main
struct AutonomousAIChatApp: App {
    @StateObject private var preferences: Preferences
    @StateObject private var viewModel: ChatViewModel
    private let appUpdater = AppUpdater.shared

    init() {
        let preferences = Preferences()
        _preferences = StateObject(wrappedValue: preferences)
        _viewModel = StateObject(wrappedValue: ChatViewModel(preferences: preferences))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(preferences)
                .environmentObject(viewModel)
                .frame(minWidth: 700, minHeight: 560)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 900, height: 700)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Nach Updates suchen…") {
                    appUpdater.checkForUpdates()
                }
                .disabled(!appUpdater.canCheckForUpdates)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(preferences)
                .environmentObject(viewModel)
        }
    }
}
