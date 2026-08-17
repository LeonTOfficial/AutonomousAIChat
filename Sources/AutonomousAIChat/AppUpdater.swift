import Foundation
import Sparkle

enum UpdateChannelPolicy {
    static let feedURL = URL(
        string: "https://raw.githubusercontent.com/LeonTOfficial/AutonomousAIChat/main/appcast.xml"
    )!
    static let publicEdKey = "XI4zReuhkT5oIylZw3eXkmtQArhooU4Q7fucZ8qndi8="
    static let scheduledCheckInterval: TimeInterval = 86_400
}

/// Owns Sparkle's updater for the complete application lifetime.
/// The public update key is stored in Info.plist; the private signing key never
/// enters the application bundle or project files.
@MainActor
final class AppUpdater: NSObject {
    static let shared = AppUpdater()

    private let controller: SPUStandardUpdaterController

    private override init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }

    var automaticallyChecksForUpdates: Bool {
        controller.updater.automaticallyChecksForUpdates
    }

    @objc func checkForUpdates(_ sender: Any? = nil) {
        controller.checkForUpdates(sender)
    }
}
