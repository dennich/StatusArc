import AppKit
import Sparkle

final class UpdateManager: NSObject, SPUUpdaterDelegate {
    private enum Constants {
        static let initialCheckDelay: TimeInterval = 5
        static let checkInterval: TimeInterval = 24 * 60 * 60
    }

    var onUpdateAvailabilityChanged: ((String?) -> Void)?

    private(set) var availableVersion: String?

    private var initialCheckTimer: Timer?
    private var periodicCheckTimer: Timer?
    private var hasStarted = false

    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    func configure(checkForUpdatesMenuItem item: NSMenuItem) {
        item.target = updaterController
        item.action = #selector(SPUStandardUpdaterController.checkForUpdates(_:))
    }

    func start() {
        guard !hasStarted else {
            return
        }

        hasStarted = true
        updaterController.startUpdater()

        let initialTimer = Timer(
            timeInterval: Constants.initialCheckDelay,
            target: self,
            selector: #selector(initialCheckTimerFired),
            userInfo: nil,
            repeats: false
        )
        initialCheckTimer = initialTimer
        RunLoop.main.add(initialTimer, forMode: .common)

        let periodicTimer = Timer(
            timeInterval: Constants.checkInterval,
            target: self,
            selector: #selector(periodicCheckTimerFired),
            userInfo: nil,
            repeats: true
        )
        periodicCheckTimer = periodicTimer
        RunLoop.main.add(periodicTimer, forMode: .common)
    }

    func stop() {
        initialCheckTimer?.invalidate()
        periodicCheckTimer?.invalidate()

        initialCheckTimer = nil
        periodicCheckTimer = nil
    }

    @objc private func initialCheckTimerFired() {
        initialCheckTimer = nil
        probeForUpdates()
    }

    @objc private func periodicCheckTimerFired() {
        probeForUpdates()
    }

    private func probeForUpdates() {
        let updater = updaterController.updater

        guard updater.canCheckForUpdates, !updater.sessionInProgress else {
            return
        }

        updater.checkForUpdateInformation()
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        setAvailableVersion(item.displayVersionString)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        setAvailableVersion(nil)
    }

    private func setAvailableVersion(_ version: String?) {
        guard availableVersion != version else {
            return
        }

        availableVersion = version
        onUpdateAvailabilityChanged?(version)
    }
}
