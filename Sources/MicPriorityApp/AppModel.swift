import Foundation
import MicPriorityCore

/// UI state for the app. Owns the enforcer and mirrors its snapshots on the main thread.
@MainActor
final class AppModel: ObservableObject {
    enum Status: Equatable {
        case keeping, adjusting, paused, noneAvailable, failed(String)
    }

    @Published private(set) var rows: [DeviceRow] = []
    @Published private(set) var currentDefault: AudioDevice?
    @Published private(set) var status: Status = .adjusting
    @Published private(set) var autoSwitch: Bool
    @Published private(set) var autoDisableBluetooth: Bool

    var hasDisconnected: Bool { rows.contains { !$0.isConnected } }
    /// Connected microphones the user disabled (e.g. AirPods), shown as ignored in the status card.
    var ignoredNames: [String] { rows.filter { $0.isConnected && !$0.isEnabled }.map(\.name) }

    private let enforcer: PriorityEnforcer
    private let watcher: ConfigFileWatcher
    private let defaults: UserDefaults
    private var config: PriorityConfig
    private var available: [AudioDevice] = []
    private var lastDecision: EnforcerDecision?

    private static let autoSwitchKey = "autoSwitchEnabled"

    init(system: AudioSystem = AudioDeviceService(), store: ConfigStore = ConfigStore(), defaults: UserDefaults = .standard) {
        let config = (try? store.load()) ?? PriorityConfig()
        let autoSwitch = defaults.object(forKey: Self.autoSwitchKey) as? Bool ?? true
        let enforcer = PriorityEnforcer(system: system, config: config, store: store, isEnforcing: autoSwitch)

        self.config = config
        self.defaults = defaults
        self.autoSwitch = autoSwitch
        self.autoDisableBluetooth = config.autoDisableBluetoothMics
        self.enforcer = enforcer
        // Edits from the CLI (same config.json) flow back into the running app.
        self.watcher = ConfigFileWatcher(store: store) { [weak enforcer] in enforcer?.reloadConfig($0) }

        enforcer.onSnapshot = { [weak self] snapshot in
            DispatchQueue.main.async { self?.apply(snapshot) }
        }
        enforcer.start()
        watcher.start()
    }

    // MARK: Actions

    func setAutoSwitch(_ on: Bool) {
        autoSwitch = on
        defaults.set(on, forKey: Self.autoSwitchKey)
        enforcer.setEnforcing(on)
        refresh()
    }

    func setAutoDisableBluetooth(_ on: Bool) {
        change { $0.autoDisableBluetoothMics = on }
    }

    func setEnabled(_ enabled: Bool, uid: String) {
        change { $0.setEnabled(enabled, uid: uid) }
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        change { $0.move(fromOffsets: source, toOffset: destination) }
    }

    func removeDisconnected() {
        let available = self.available
        change { $0.forgetDisconnected(available: available) }
    }

    // MARK: Private

    /// Applies the change locally right away (so the UI does not flicker) and hands it to the enforcer.
    private func change(_ mutation: @escaping (inout PriorityConfig) -> Void) {
        mutation(&config)
        refresh()
        enforcer.updateConfig(mutation)
    }

    private func apply(_ snapshot: EnforcerSnapshot) {
        config = snapshot.config
        available = snapshot.available
        currentDefault = snapshot.currentDefault
        lastDecision = snapshot.decision
        refresh()
    }

    private func refresh() {
        let newRows = DeviceRow.rows(config: config, available: available, currentDefaultUID: currentDefault?.uid)
        if newRows != rows { rows = newRows }
        if autoDisableBluetooth != config.autoDisableBluetoothMics {
            autoDisableBluetooth = config.autoDisableBluetoothMics
        }
        status = computeStatus()
    }

    private func computeStatus() -> Status {
        guard autoSwitch else { return .paused }
        if case .failed(_, let error) = lastDecision { return .failed(error) }
        guard let preferred = PriorityEngine.chooseDevice(available: available, config: config) else {
            return .noneAvailable
        }
        return preferred.uid == currentDefault?.uid ? .keeping : .adjusting
    }
}
