import Foundation
import os

public enum PriorityEngine {
    /// The first enabled device, in priority order, that is currently available and alive.
    /// Returns nil when none qualifies; in that case the system default should be left alone.
    public static func chooseDevice(available: [AudioDevice], config: PriorityConfig) -> AudioDevice? {
        let byUID = Dictionary(available.filter(\.isAlive).map { ($0.uid, $0) }, uniquingKeysWith: { first, _ in first })
        for known in config.devices where config.isEnabled(uid: known.uid) {
            if let device = byUID[known.uid] { return device }
        }
        return nil
    }
}

/// Outcome of one enforcement pass.
public enum EnforcerDecision: Equatable, CustomStringConvertible {
    /// No enabled device in the priority list is connected; the system was left alone.
    case noEnabledDeviceAvailable(current: AudioDevice?)
    case alreadyCorrect(AudioDevice)
    case switched(from: AudioDevice?, to: AudioDevice)
    case failed(target: AudioDevice, error: String)

    public var description: String {
        switch self {
        case .noEnabledDeviceAvailable(let current):
            return "No enabled microphone available; leaving default as \(current?.name ?? "none")"
        case .alreadyCorrect(let device):
            return "Default input already \(device.name)"
        case .switched(let from, let to):
            return "Switched default input from \(from?.name ?? "none") to \(to.name)"
        case .failed(let target, let error):
            return "Failed to switch to \(target.name): \(error)"
        }
    }
}

/// Watches the audio system and keeps the default input on the highest-priority enabled device.
///
/// All work runs on a private serial queue; callbacks are delivered on that queue, so UI code
/// should hop to the main actor.
public final class PriorityEnforcer {
    public var onEvent: ((AudioChangeEvent) -> Void)?
    public var onDecision: ((EnforcerDecision) -> Void)?
    /// Called whenever the config changes (new devices registered or `updateConfig` used).
    public var onConfigChange: ((PriorityConfig) -> Void)?

    private let system: AudioSystem
    private let store: ConfigStore?
    private let debounce: TimeInterval
    private let selfWriteWindow: TimeInterval
    private let queue = DispatchQueue(label: "com.alencar.micpriority.enforcer")
    private let logger = Logger(subsystem: Log.subsystem, category: "PriorityEnforcer")

    private var config: PriorityConfig
    private var pendingWork: DispatchWorkItem?
    private var pendingSelfWrite: (uid: String, until: Date)?
    private var isRunning = false

    public init(system: AudioSystem, config: PriorityConfig, store: ConfigStore? = nil,
                debounce: TimeInterval = 0.4, selfWriteWindow: TimeInterval = 2.0) {
        self.system = system
        self.config = config
        self.store = store
        self.debounce = debounce
        self.selfWriteWindow = selfWriteWindow
    }

    /// Current config. Do not call from inside an enforcer callback.
    public var currentConfig: PriorityConfig { queue.sync { config } }

    /// Registers the listeners (synchronously, so no event is missed) and runs a first pass.
    /// Do not call from inside an enforcer callback.
    public func start() {
        queue.sync {
            guard !isRunning else { return }
            isRunning = true
            logger.info("Enforcer started")
            system.startListening { [weak self] event in
                self?.queue.async { self?.handle(event) }
            }
            queue.async { [self] in evaluate() }
        }
    }

    public func stop() {
        queue.sync {
            pendingWork?.cancel()
            pendingWork = nil
            system.stopListening()
            isRunning = false
            logger.info("Enforcer stopped")
        }
    }

    /// Changes the config, persists it, and re-evaluates immediately.
    public func updateConfig(_ change: @escaping (inout PriorityConfig) -> Void) {
        queue.async { [self] in
            change(&config)
            configDidChange()
            evaluate()
        }
    }

    /// Runs an enforcement pass now, skipping the debounce.
    public func evaluateNow() {
        queue.async { [self] in evaluate() }
    }

    // MARK: Private (on queue)

    private func handle(_ event: AudioChangeEvent) {
        onEvent?(event)
        if event == .defaultInputChanged, let pending = pendingSelfWrite {
            pendingSelfWrite = nil
            if Date() < pending.until, system.currentDefaultInput()?.uid == pending.uid {
                logger.debug("Ignoring default-input change caused by our own write")
                return
            }
        }
        scheduleEvaluation()
    }

    private func scheduleEvaluation() {
        pendingWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.evaluate() }
        pendingWork = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }

    private func evaluate() {
        pendingWork = nil
        let available = system.listInputDevices()
        let before = config
        let added = config.register(available)
        for device in added {
            let state = config.isEnabled(uid: device.uid) ? "enabled" : "disabled"
            logger.info("New microphone \(device.name, privacy: .public) (\(device.transportType.rawValue, privacy: .public)) added as \(state, privacy: .public)")
        }
        if config != before { configDidChange() }

        let current = system.currentDefaultInput()
        let decision: EnforcerDecision
        if let target = PriorityEngine.chooseDevice(available: available, config: config) {
            if current?.uid == target.uid {
                decision = .alreadyCorrect(target)
            } else {
                pendingSelfWrite = (target.uid, Date().addingTimeInterval(selfWriteWindow))
                do {
                    try system.setDefaultInput(uid: target.uid)
                    decision = .switched(from: current, to: target)
                } catch {
                    pendingSelfWrite = nil
                    decision = .failed(target: target, error: String(describing: error))
                }
            }
        } else {
            decision = .noEnabledDeviceAvailable(current: current)
        }
        logger.info("\(decision.description, privacy: .public)")
        onDecision?(decision)
    }

    private func configDidChange() {
        if let store {
            do { try store.save(config) } catch {
                logger.error("Failed to save config: \(String(describing: error), privacy: .public)")
            }
        }
        onConfigChange?(config)
    }
}
