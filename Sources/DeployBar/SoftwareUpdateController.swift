import Combine
import Foundation
import Sparkle

enum SoftwareUpdateChannel: String, CaseIterable, Identifiable {
    case stable
    case beta

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stable:
            "Stable"
        case .beta:
            "Beta"
        }
    }

    var description: String {
        switch self {
        case .stable:
            "Receive only stable, production-ready releases."
        case .beta:
            "Receive beta releases as well as stable releases."
        }
    }

    var allowedSparkleChannels: Set<String> {
        switch self {
        case .stable:
            []
        case .beta:
            ["beta"]
        }
    }
}

enum SoftwareUpdateStatus: Equatable {
    case unavailable(String)
    case idle
    case checking
    case downloading(String)
    case downloaded(String)
    case readyToInstall(String)
    case installing
    case failed(String)

    var downloadedVersion: String? {
        switch self {
        case let .downloaded(version), let .readyToInstall(version):
            version
        case .unavailable, .idle, .checking, .downloading, .installing, .failed:
            nil
        }
    }

    var isDownloaded: Bool {
        downloadedVersion != nil
    }

    var readyToInstallVersion: String? {
        if case let .readyToInstall(version) = self {
            return version
        }
        return nil
    }

    var isReadyToInstall: Bool {
        readyToInstallVersion != nil
    }
}

@MainActor
final class SoftwareUpdateController: NSObject, ObservableObject {
    @Published private(set) var status: SoftwareUpdateStatus
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var automaticallyDownloadsUpdates = false
    @Published private(set) var allowsAutomaticUpdates = false
    @Published private(set) var lastUpdateCheckDate: Date?
    @Published private(set) var channel: SoftwareUpdateChannel

    private var updaterController: SPUStandardUpdaterController?
    private var observations: [NSKeyValueObservation] = []
    private var installDownloadedUpdateHandler: (() -> Void)?

    var isAvailable: Bool {
        if case .unavailable = status {
            return false
        }
        return updaterController != nil
    }

    var automaticUpdatesEnabled: Bool {
        automaticallyChecksForUpdates && automaticallyDownloadsUpdates
    }

    override init() {
        let storedChannel = UserDefaults.standard.string(forKey: Self.channelDefaultsKey)
            .flatMap(SoftwareUpdateChannel.init(rawValue:)) ?? .stable
        self.channel = storedChannel

        self.status = Self.hasRequiredSparkleConfiguration
            ? .idle
            : .unavailable("Updates are available in packaged builds with Sparkle configured.")
        self.updaterController = nil

        super.init()

        guard Self.hasRequiredSparkleConfiguration else { return }
        let updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        self.updaterController = updaterController

        configureObservers(for: updaterController.updater)

        do {
            try updaterController.updater.start()
            syncState(from: updaterController.updater)
        } catch {
            status = .unavailable(error.localizedDescription)
        }
    }

    func checkForUpdates() {
        guard let updater = updaterController?.updater, canCheckForUpdates else { return }
        status = .checking
        updater.checkForUpdates()
    }

    func setAutomaticUpdatesEnabled(_ isEnabled: Bool) {
        guard let updater = updaterController?.updater else { return }
        updater.automaticallyChecksForUpdates = isEnabled
        updater.automaticallyDownloadsUpdates = isEnabled
        syncState(from: updater)
    }

    func setChannel(_ channel: SoftwareUpdateChannel) {
        guard self.channel != channel else { return }
        self.channel = channel
        UserDefaults.standard.set(channel.rawValue, forKey: Self.channelDefaultsKey)
        updaterController?.updater.resetUpdateCycle()
    }

    func restartAndInstallDownloadedUpdate() {
        guard let installDownloadedUpdateHandler else { return }
        status = .installing
        installDownloadedUpdateHandler()
    }

    private func configureObservers(for updater: SPUUpdater) {
        observations = [
            updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                Task { @MainActor in
                    self?.canCheckForUpdates = updater.canCheckForUpdates
                }
            },
            updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                Task { @MainActor in
                    self?.automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
                }
            },
            updater.observe(\.automaticallyDownloadsUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                Task { @MainActor in
                    self?.automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
                }
            },
            updater.observe(\.allowsAutomaticUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                Task { @MainActor in
                    self?.allowsAutomaticUpdates = updater.allowsAutomaticUpdates
                }
            }
        ]
    }

    private func syncState(from updater: SPUUpdater) {
        canCheckForUpdates = updater.canCheckForUpdates
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
        allowsAutomaticUpdates = updater.allowsAutomaticUpdates
        lastUpdateCheckDate = updater.lastUpdateCheckDate
    }

    private static var hasRequiredSparkleConfiguration: Bool {
        let info = Bundle.main.infoDictionary ?? [:]
        guard let feedURL = info["SUFeedURL"] as? String, !feedURL.isEmpty else { return false }
        guard let publicKey = info["SUPublicEDKey"] as? String, !publicKey.isEmpty else { return false }
        return true
    }

    private static let channelDefaultsKey = "updates.channel"
}

extension SoftwareUpdateController: SPUUpdaterDelegate {
    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        channel.allowedSparkleChannels
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        status = updater.automaticallyDownloadsUpdates ? .downloading(item.displayVersionString) : .idle
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        if !status.isDownloaded {
            status = .idle
        }
        syncState(from: updater)
    }

    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        status = .downloading(item.displayVersionString)
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        status = installDownloadedUpdateHandler == nil
            ? .downloaded(item.displayVersionString)
            : .readyToInstall(item.displayVersionString)
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: any Error) {
        installDownloadedUpdateHandler = nil
        status = .failed(error.localizedDescription)
    }

    func userDidCancelDownload(_ updater: SPUUpdater) {
        installDownloadedUpdateHandler = nil
        status = .idle
    }

    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        installDownloadedUpdateHandler = immediateInstallHandler
        status = .readyToInstall(item.displayVersionString)
        return true
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        status = .installing
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        installDownloadedUpdateHandler = nil
        status = .failed(error.localizedDescription)
        syncState(from: updater)
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        syncState(from: updater)
        guard error == nil else { return }

        switch status {
        case .checking, .downloading:
            status = .idle
        case .unavailable, .idle, .downloaded, .readyToInstall, .installing, .failed:
            break
        }
    }
}
