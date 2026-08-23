import Sparkle

@MainActor
protocol UpdateChecking: AnyObject {
    func checkForUpdates()
}

/// Owns the user-initiated signed update flow. Sparkle's separately sandboxed
/// services own network and installation work; MKV Magic has no network entitlement.
@MainActor
final class AppUpdateController: UpdateChecking {
    private let updaterController: SPUStandardUpdaterController

    init(startingUpdater: Bool = true) {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: startingUpdater,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
