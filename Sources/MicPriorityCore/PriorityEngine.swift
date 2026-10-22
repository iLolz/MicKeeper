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
public enum EnforcerDecision: Equatable, Sendable, CustomStringConvertible {
    /// Auto-switching is paused; the system was left alone.
    case paused(current: AudioDevice?)
    /// No enabled device in the priority list is connected; the system was left alone.
    case noEnabledDeviceAvailable(current: AudioDevice?)
    case alreadyCorrect(AudioDevice)
    case switched(from: AudioDevice?, to: AudioDevice)
    case failed(target: AudioDevice, error: String)

    public var description: String {
        switch self {
        case .paused(let current):
            return "Paused; leaving default as \(current?.name ?? "none")"
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

/// Everything a UI needs to render after an enforcement pass.
public struct EnforcerSnapshot: Equatable, Sendable {
    public var config: PriorityConfig
    public var available: [AudioDevice]
    public var currentDefault: AudioDevice?
    public var isEnforcing: Bool
    public var decision: EnforcerDecision

    public init(config: PriorityConfig, available: [AudioDevice], currentDefault: AudioDevice?,
                isEnforcing: Bool, decision: EnforcerDecision) {
        self.config = config
        self.available = available
        self.currentDefault = currentDefault
        self.isEnforcing = isEnforcing
        self.decision = decision
    }

    /// The device the priority order points to right now (nil if none is enabled and connected).
    public var preferred: AudioDevice? { PriorityEngine.chooseDevice(available: available, config: config) }

    public var rows: [DeviceRow] {
        DeviceRow.rows(config: config, available: available, currentDefaultUID: currentDefault?.uid)
    }
}

/// Watches the audio system and keeps the default input on the highest-priority enabled device.
///
/// All work runs on a private serial queue; callbacks are delivered on that queue, so UI code
/// should hop to the main actor. While paused it keeps listening and registering devices
/// (so a UI stays current) but never changes the default input.
public final class PriorityEnforcer {
    public var onEvent: ((AudioChangeEvent) -> Void)?
    public var onDecision: ((EnforcerDecision) -> Void)?
    /// Called after every pass with the full state.
    public var onSnapshot: ((EnforcerSnapshot) -> Void)?
    /// Called whenever the config changes (new devices registered, `updateConfig` or `reloadConfig`).
    public var onConfigChange: ((PriorityConfig) -> Void)?

    private let system: AudioSystem
    private let store: ConfigStore?
    private let debounce: TimeInterval
    private let selfWriteWindow: TimeInterval
    private let queue = DispatchQueue(label: "com.alencar.micpriority.enforcer")
    private let logger = Logger(subsystem: Log.subsystem, category: "PriorityEnforcer")

    private var config: PriorityConfig
    private var isEnforcing: Bool
    private var pendingWork: DispatchWorkItem?
    private var pendingSelfWrite: (uid: String, until: Date)?
    private var isRunning = false

    public init(system: AudioSystem, config: PriorityConfig, store: ConfigStore? = nil,
                isEnforcing: Bool = true, debounce: TimeInterval = 0.4, selfWriteWindow: TimeInterval = 2.0) {
        self.system = system
        self.config = config
        self.store = store
        self.isEnforcing = isEnforcing
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

    /// Do not call from inside an enforcer callback.
    public func stop() {
        queue.sync {
            pendingWork?.cancel()
            pendingWork = nil
            system.stopListening()
            isRunning = false
            logger.info("Enforcer stopped")
        }
    }

    /// Pauses or resumes switching the default input, then re-evaluates.
    public func setEnforcing(_ enforcing: Bool) {
        queue.async { [self] in
            guard isEnforcing != enforcing else { return }
            isEnforcing = enforcing
            logger.info("Auto-switch \(enforcing ? "resumed" : "paused", privacy: .public)")
            evaluate()
        }
    }

    /// Changes the config, persists it, and re-evaluates immediately.
    public func updateConfig(_ change: @escaping (inout PriorityConfig) -> Void) {
        queue.async { [self] in
            change(&config)
            configDidChange(persist: true)
            evaluate()
        }
    }

    /// Replaces the config with one changed elsewhere (e.g. the file edited by the CLI).
    /// Does not write it back. No-op if nothing changed.
    public func reloadConfig(_ newConfig: PriorityConfig) {
        queue.async { [self] in
            guard newConfig != config else { return }
            logger.info("Config reloaded from disk")
            config = newConfig
            configDidChange(persist: false)
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
        if config != before { configDidChange(persist: true) }

        var current = system.currentDefaultInput()
        let decision: EnforcerDecision
        if !isEnforcing {
            decision = .paused(current: current)
        } else if let target = PriorityEngine.chooseDevice(available: available, config: config) {
            if current?.uid == target.uid {
                decision = .alreadyCorrect(target)
            } else {
                pendingSelfWrite = (target.uid, Date().addingTimeInterval(selfWriteWindow))
                do {
                    try system.setDefaultInput(uid: target.uid)
                    decision = .switched(from: current, to: target)
                    current = target
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
        onSnapshot?(EnforcerSnapshot(config: config, available: available, currentDefault: current,
                                     isEnforcing: isEnforcing, decision: decision))
    }

    private func configDidChange(persist: Bool) {
        if persist, let store {
            do { try store.save(config) } catch {
                logger.error("Failed to save config: \(String(describing: error), privacy: .public)")
            }
        }
        onConfigChange?(config)
    }
}
