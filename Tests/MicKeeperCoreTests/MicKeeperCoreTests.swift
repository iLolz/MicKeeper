import XCTest
@testable import MicKeeperCore

final class MockAudioSystem: AudioSystem {
    private let lock = NSLock()
    private var _devices: [AudioDevice]
    private var _defaultUID: String?
    private var handler: ((AudioChangeEvent) -> Void)?
    private(set) var setDefaultCalls: [String] = []

    init(devices: [AudioDevice], defaultUID: String?) {
        _devices = devices
        _defaultUID = defaultUID
    }

    var devices: [AudioDevice] {
        get { lock.withLock { _devices } }
        set { lock.withLock { _devices = newValue } }
    }

    var defaultUID: String? {
        get { lock.withLock { _defaultUID } }
        set { lock.withLock { _defaultUID = newValue } }
    }

    func listInputDevices() -> [AudioDevice] { devices }

    func currentDefaultInput() -> AudioDevice? {
        let uid = defaultUID
        return devices.first { $0.uid == uid }
    }

    func setDefaultInput(uid: String) throws {
        guard devices.contains(where: { $0.uid == uid }) else { throw AudioSystemError.deviceNotFound(uid: uid) }
        lock.withLock { setDefaultCalls.append(uid) }
        defaultUID = uid
        handler?(.defaultInputChanged)
    }

    func startListening(_ handler: @escaping (AudioChangeEvent) -> Void) { self.handler = handler }
    func stopListening() { handler = nil }

    /// Simulates the OS reacting to a hardware change.
    func emit(_ event: AudioChangeEvent) { handler?(event) }

    var setDefaultCallCount: Int { lock.withLock { setDefaultCalls.count } }
}

let builtIn = AudioDevice(id: 1, uid: "builtin", name: "MacBook Microphone", transportType: .builtIn)
let usb = AudioDevice(id: 2, uid: "usb", name: "USB Mic", transportType: .usb)
let airpods = AudioDevice(id: 3, uid: "airpods", name: "AirPods", transportType: .bluetooth)
let bleHeadset = AudioDevice(id: 4, uid: "ble", name: "BLE Headset", transportType: .bluetoothLE)

final class ChooseDeviceTests: XCTestCase {
    func config(_ devices: [AudioDevice], disabled: Set<String> = []) -> PriorityConfig {
        PriorityConfig(devices: devices.map(KnownDevice.init), disabledUIDs: disabled)
    }

    func testPicksFirstAvailableInPriorityOrder() {
        let cfg = config([usb, builtIn, airpods])
        XCTAssertEqual(PriorityEngine.chooseDevice(available: [airpods, builtIn, usb], config: cfg), usb)
    }

    func testFallsBackWhenFirstIsUnavailable() {
        let cfg = config([usb, builtIn, airpods])
        XCTAssertEqual(PriorityEngine.chooseDevice(available: [airpods, builtIn], config: cfg), builtIn)
    }

    func testSkipsDisabledDevices() {
        let cfg = config([airpods, builtIn], disabled: ["airpods"])
        XCTAssertEqual(PriorityEngine.chooseDevice(available: [airpods, builtIn], config: cfg), builtIn)
    }

    func testReturnsNilWhenOnlyDisabledDevicesAvailable() {
        let cfg = config([builtIn, airpods], disabled: ["airpods"])
        XCTAssertNil(PriorityEngine.chooseDevice(available: [airpods], config: cfg))
    }

    func testReturnsNilWhenNothingAvailable() {
        XCTAssertNil(PriorityEngine.chooseDevice(available: [], config: config([builtIn])))
    }

    func testIgnoresDevicesNotInConfig() {
        XCTAssertNil(PriorityEngine.chooseDevice(available: [usb], config: config([builtIn])))
    }

    func testSkipsDevicesThatAreNotAlive() {
        var deadUSB = usb
        deadUSB.isAlive = false
        let cfg = config([usb, builtIn])
        XCTAssertEqual(PriorityEngine.chooseDevice(available: [deadUSB, builtIn], config: cfg), builtIn)
    }

    func testMatchesByUIDEvenWhenDeviceIDChanges() {
        var reconnected = usb
        reconnected.id = 99
        XCTAssertEqual(PriorityEngine.chooseDevice(available: [reconnected], config: config([usb]))?.id, 99)
    }
}

final class RegisterDevicesTests: XCTestCase {
    func testNewDevicesAreAppendedInOrder() {
        var cfg = PriorityConfig(devices: [KnownDevice(builtIn)])
        let added = cfg.register([builtIn, usb])
        XCTAssertEqual(added.map(\.uid), ["usb"])
        XCTAssertEqual(cfg.devices.map(\.uid), ["builtin", "usb"])
        XCTAssertTrue(cfg.isEnabled(uid: "usb"))
    }

    func testNewBluetoothDevicesAreDisabledByDefault() {
        var cfg = PriorityConfig()
        cfg.register([builtIn, airpods, bleHeadset])
        XCTAssertEqual(cfg.devices.map(\.uid), ["builtin", "airpods", "ble"])
        XCTAssertTrue(cfg.isEnabled(uid: "builtin"))
        XCTAssertFalse(cfg.isEnabled(uid: "airpods"))
        XCTAssertFalse(cfg.isEnabled(uid: "ble"))
    }

    func testFirstRunSeedsOrderByTransport() {
        let iphone = AudioDevice(id: 5, uid: "iphone", name: "iPhone", transportType: .continuity)
        let teams = AudioDevice(id: 6, uid: "teams", name: "Teams Audio", transportType: .virtual)
        var cfg = PriorityConfig()
        cfg.register([iphone, teams, airpods, builtIn, usb])
        XCTAssertEqual(cfg.devices.map(\.uid), ["builtin", "usb", "iphone", "airpods", "teams"])

        // Later additions are appended regardless of transport.
        let otherBuiltIn = AudioDevice(id: 7, uid: "builtin2", name: "Another", transportType: .builtIn)
        cfg.register([otherBuiltIn])
        XCTAssertEqual(cfg.devices.last?.uid, "builtin2")
    }

    func testBluetoothStaysEnabledWhenAutoDisableIsOff() {
        var cfg = PriorityConfig(autoDisableBluetoothMics: false)
        cfg.register([airpods])
        XCTAssertTrue(cfg.isEnabled(uid: "airpods"))
    }

    func testKnownBluetoothDeviceIsNotDisabledAgain() {
        var cfg = PriorityConfig()
        cfg.register([airpods])
        cfg.setEnabled(true, uid: "airpods")
        let added = cfg.register([airpods])
        XCTAssertTrue(added.isEmpty)
        XCTAssertTrue(cfg.isEnabled(uid: "airpods"))
    }

    func testKnownDeviceNameIsRefreshed() {
        var cfg = PriorityConfig(devices: [KnownDevice(builtIn)])
        var renamed = builtIn
        renamed.name = "Renamed"
        cfg.register([renamed])
        XCTAssertEqual(cfg.devices.first?.name, "Renamed")
    }

    func testMoveAndSwiftUIStyleMove() {
        var cfg = PriorityConfig(devices: [builtIn, usb, airpods].map(KnownDevice.init))
        cfg.move(uid: "airpods", to: 0)
        XCTAssertEqual(cfg.devices.map(\.uid), ["airpods", "builtin", "usb"])
        cfg.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        XCTAssertEqual(cfg.devices.map(\.uid), ["builtin", "usb", "airpods"])
    }

    func testDecodesOldConfigWithoutAutoDisableFlag() throws {
        let json = #"{"devices":[],"disabledUIDs":[]}"#
        let cfg = try JSONDecoder().decode(PriorityConfig.self, from: Data(json.utf8))
        XCTAssertTrue(cfg.autoDisableBluetoothMics)
    }

    func testConfigStoreRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("config.json")
        let store = ConfigStore(url: url)
        XCTAssertEqual(try store.load(), PriorityConfig())
        var cfg = PriorityConfig()
        cfg.register([builtIn, airpods])
        try store.save(cfg)
        XCTAssertEqual(try store.load(), cfg)
    }
}

final class EnforcerTests: XCTestCase {
    func testSwitchesBackWhenBluetoothHeadsetTakesOver() {
        let mock = MockAudioSystem(devices: [builtIn], defaultUID: "builtin")
        let enforcer = PriorityEnforcer(system: mock, config: PriorityConfig(), debounce: 0.05)
        let switched = expectation(description: "switched back to built-in")
        var decisions: [EnforcerDecision] = []
        enforcer.onDecision = { decision in
            decisions.append(decision)
            if case .switched(_, let to) = decision, to.uid == "builtin" { switched.fulfill() }
        }
        enforcer.start()
        enforcer.evaluateNow()

        // Headset connects and macOS makes it the default input.
        mock.devices = [builtIn, airpods]
        mock.defaultUID = "airpods"
        mock.emit(.devicesChanged)
        mock.emit(.defaultInputChanged)

        wait(for: [switched], timeout: 2)
        enforcer.stop()
        XCTAssertEqual(mock.defaultUID, "builtin")
        XCTAssertEqual(mock.setDefaultCalls, ["builtin"])
        XCTAssertFalse(enforcer.currentConfig.isEnabled(uid: "airpods"))
    }

    func testDoesNotLoopOnItsOwnWrite() {
        let mock = MockAudioSystem(devices: [builtIn, usb], defaultUID: "builtin")
        let cfg = PriorityConfig(devices: [usb, builtIn].map(KnownDevice.init))
        let enforcer = PriorityEnforcer(system: mock, config: cfg, debounce: 0.05)
        enforcer.start()

        // Give the initial pass and any (incorrect) follow-up passes time to run.
        let settle = expectation(description: "settle")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { settle.fulfill() }
        wait(for: [settle], timeout: 2)
        enforcer.stop()

        XCTAssertEqual(mock.defaultUID, "usb")
        XCTAssertEqual(mock.setDefaultCallCount, 1)
    }

    func testLeavesSystemAloneWhenNoEnabledDeviceIsAvailable() {
        let mock = MockAudioSystem(devices: [airpods], defaultUID: "airpods")
        let enforcer = PriorityEnforcer(system: mock, config: PriorityConfig())
        let decided = expectation(description: "decision")
        enforcer.onDecision = { decision in
            XCTAssertEqual(decision, .noEnabledDeviceAvailable(current: airpods))
            decided.fulfill()
        }
        enforcer.start()
        wait(for: [decided], timeout: 2)
        enforcer.stop()
        XCTAssertEqual(mock.setDefaultCallCount, 0)
    }

    func testDebounceCoalescesBurstsOfEvents() {
        let mock = MockAudioSystem(devices: [builtIn], defaultUID: "builtin")
        let enforcer = PriorityEnforcer(system: mock, config: PriorityConfig(), debounce: 0.2)
        let lock = NSLock()
        var count = 0
        enforcer.onDecision = { _ in lock.withLock { count += 1 } }
        enforcer.start()
        for _ in 0..<10 { mock.emit(.devicesChanged) }

        let settle = expectation(description: "settle")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.6) { settle.fulfill() }
        wait(for: [settle], timeout: 2)
        enforcer.stop()
        // One initial pass on start plus one debounced pass for the burst.
        XCTAssertEqual(lock.withLock { count }, 2)
    }
}

final class DeviceRowTests: XCTestCase {
    func testRowsFollowPriorityOrderWithLiveState() {
        var cfg = PriorityConfig()
        cfg.register([builtIn, usb, airpods])
        var renamedUSB = usb
        renamedUSB.name = "USB Mic (renamed)"
        let rows = DeviceRow.rows(config: cfg, available: [airpods, renamedUSB], currentDefaultUID: "usb")

        XCTAssertEqual(rows.map(\.uid), ["builtin", "usb", "airpods"])
        XCTAssertEqual(rows.map(\.position), [1, 2, 3])
        XCTAssertEqual(rows.map(\.isConnected), [false, true, true])
        XCTAssertEqual(rows.map(\.isEnabled), [true, true, false])
        XCTAssertEqual(rows.map(\.isCurrentDefault), [false, true, false])
        XCTAssertEqual(rows[1].name, "USB Mic (renamed)")
        XCTAssertEqual(rows[0].name, "MacBook Microphone")
    }

    func testDeadDevicesShowAsDisconnected() {
        var dead = usb
        dead.isAlive = false
        let cfg = PriorityConfig(devices: [KnownDevice(usb)])
        XCTAssertFalse(DeviceRow.rows(config: cfg, available: [dead], currentDefaultUID: nil)[0].isConnected)
    }

    func testForgetDisconnected() {
        var cfg = PriorityConfig()
        cfg.register([builtIn, usb, airpods])
        cfg.forgetDisconnected(available: [builtIn])
        XCTAssertEqual(cfg.devices.map(\.uid), ["builtin"])
        XCTAssertTrue(cfg.disabledUIDs.isEmpty)

        // A forgotten Bluetooth device that comes back is treated as new (appended, disabled).
        cfg.register([builtIn, airpods])
        XCTAssertEqual(cfg.devices.map(\.uid), ["builtin", "airpods"])
        XCTAssertFalse(cfg.isEnabled(uid: "airpods"))
    }
}

final class EnforcerStateTests: XCTestCase {
    func testPausedDoesNotSwitchButStillReports() {
        let mock = MockAudioSystem(devices: [builtIn, airpods], defaultUID: "airpods")
        let enforcer = PriorityEnforcer(system: mock, config: PriorityConfig(), isEnforcing: false, debounce: 0.05)
        let snapshot = expectation(description: "snapshot")
        var received: EnforcerSnapshot?
        enforcer.onSnapshot = { received = $0; snapshot.fulfill() }
        enforcer.start()
        wait(for: [snapshot], timeout: 2)
        enforcer.stop()

        XCTAssertEqual(mock.setDefaultCallCount, 0)
        XCTAssertEqual(received?.decision, .paused(current: airpods))
        XCTAssertEqual(received?.preferred, builtIn)
        XCTAssertEqual(received?.config.devices.count, 2)
        XCTAssertEqual(received?.rows.first(where: \.isCurrentDefault)?.uid, "airpods")
    }

    func testResumingSwitchesBack() {
        let mock = MockAudioSystem(devices: [builtIn, airpods], defaultUID: "airpods")
        let enforcer = PriorityEnforcer(system: mock, config: PriorityConfig(), isEnforcing: false, debounce: 0.05)
        let switched = expectation(description: "switched")
        enforcer.onSnapshot = { snapshot in
            if case .switched = snapshot.decision {
                XCTAssertEqual(snapshot.currentDefault, builtIn)
                XCTAssertTrue(snapshot.isEnforcing)
                switched.fulfill()
            }
        }
        enforcer.start()
        enforcer.setEnforcing(true)
        wait(for: [switched], timeout: 2)
        enforcer.stop()
        XCTAssertEqual(mock.defaultUID, "builtin")
    }

    func testUpdateConfigPersistsAndReloadDoesNot() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("config.json")
        let store = ConfigStore(url: url)
        let mock = MockAudioSystem(devices: [builtIn, usb], defaultUID: "builtin")
        let enforcer = PriorityEnforcer(system: mock, config: PriorityConfig(), store: store, debounce: 0.05)
        enforcer.start()

        enforcer.updateConfig { $0.move(uid: "usb", to: 0) }
        _ = enforcer.currentConfig // waits for the queue to drain the update
        XCTAssertEqual(try store.load().devices.map(\.uid), ["usb", "builtin"])

        var external = enforcer.currentConfig
        external.setEnabled(false, uid: "usb")
        enforcer.reloadConfig(external)
        _ = enforcer.currentConfig
        enforcer.stop()

        XCTAssertFalse(enforcer.currentConfig.isEnabled(uid: "usb"))
        XCTAssertTrue(try store.load().isEnabled(uid: "usb"), "reload must not write back to disk")
        XCTAssertEqual(mock.defaultUID, "builtin", "reload re-evaluates with the new config")
    }
}

final class ConfigFileWatcherTests: XCTestCase {
    func testReportsChangesWrittenByAnotherProcess() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("config.json")
        let store = ConfigStore(url: url)
        try store.save(PriorityConfig())

        let changed = expectation(description: "change seen")
        let watcher = ConfigFileWatcher(store: store) { config in
            if config.devices.map(\.uid) == ["usb"] { changed.fulfill() }
        }
        watcher.start()

        var cfg = PriorityConfig()
        cfg.register([usb])
        try ConfigStore(url: url).save(cfg)
        wait(for: [changed], timeout: 3)
        watcher.stop()
    }
}

final class ConfigMigrationTests: XCTestCase {
    private func tempURL(_ folder: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(folder).appendingPathComponent("config.json")
    }

    func testCopiesLegacyConfigWhenNewOneIsMissing() throws {
        let legacy = ConfigStore(url: tempURL("MicPriority"))
        var cfg = PriorityConfig()
        cfg.register([builtIn, airpods])
        try legacy.save(cfg)

        let store = ConfigStore(url: tempURL("MicKeeper"))
        XCTAssertTrue(store.migrateIfNeeded(from: legacy.url))
        XCTAssertEqual(try store.load(), cfg)
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.url.path), "legacy file is kept")
    }

    func testDoesNotOverwriteExistingConfig() throws {
        let legacy = ConfigStore(url: tempURL("MicPriority"))
        var old = PriorityConfig()
        old.register([airpods])
        try legacy.save(old)

        let store = ConfigStore(url: tempURL("MicKeeper"))
        var current = PriorityConfig()
        current.register([builtIn])
        try store.save(current)

        XCTAssertFalse(store.migrateIfNeeded(from: legacy.url))
        XCTAssertEqual(try store.load(), current)
    }

    func testNoLegacyConfigIsANoOp() {
        let store = ConfigStore(url: tempURL("MicKeeper"))
        XCTAssertFalse(store.migrateIfNeeded(from: tempURL("MicPriority")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url.path))
    }
}

final class UseNowTests: XCTestCase {
    func testPromoteMovesToTopAndEnables() {
        var cfg = PriorityConfig()
        cfg.register([builtIn, usb, airpods])
        cfg.promote(uid: "airpods")
        XCTAssertEqual(cfg.devices.map(\.uid), ["airpods", "builtin", "usb"])
        XCTAssertTrue(cfg.isEnabled(uid: "airpods"))
    }

    func testSwitchNowWorksWhilePausedWithoutLooping() {
        let mock = MockAudioSystem(devices: [builtIn, usb], defaultUID: "builtin")
        let enforcer = PriorityEnforcer(system: mock, config: PriorityConfig(), isEnforcing: false, debounce: 0.05)
        enforcer.start()
        enforcer.switchNow(toUID: "usb")

        let settle = expectation(description: "settle")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) { settle.fulfill() }
        wait(for: [settle], timeout: 2)
        enforcer.stop()

        XCTAssertEqual(mock.defaultUID, "usb")
        XCTAssertEqual(mock.setDefaultCalls, ["usb"])
    }
}

final class MockLoginItemService: LoginItemService {
    var status: LoginItemStatus = .notRegistered
    var statusAfterRegister: LoginItemStatus = .enabled
    var error: Error?

    func register() throws {
        if let error { throw error }
        status = statusAfterRegister
    }

    func unregister() throws {
        if let error { throw error }
        status = .notRegistered
    }
}

final class LaunchAtLoginTests: XCTestCase {
    func testStateMapping() {
        XCTAssertEqual(LaunchAtLoginState(status: .enabled), LaunchAtLoginState(isOn: true))
        XCTAssertEqual(LaunchAtLoginState(status: .notRegistered), LaunchAtLoginState(isOn: false))
        XCTAssertEqual(LaunchAtLoginState(status: .requiresApproval), LaunchAtLoginState(isOn: true, hint: .needsApproval))
        XCTAssertEqual(LaunchAtLoginState(status: .notFound), LaunchAtLoginState(isOn: false, hint: .notFound))
    }

    func testTurningOnAndOff() {
        let service = MockLoginItemService()
        let controller = LaunchAtLoginController(service: service)
        XCTAssertEqual(controller.set(true), LaunchAtLoginState(isOn: true))
        XCTAssertEqual(controller.set(false), LaunchAtLoginState(isOn: false))
    }

    func testTurningOnThatNeedsApproval() {
        let service = MockLoginItemService()
        service.statusAfterRegister = .requiresApproval
        let state = LaunchAtLoginController(service: service).set(true)
        XCTAssertTrue(state.isOn)
        XCTAssertEqual(state.hint, .needsApproval)
    }

    func testErrorKeepsRealStatusAndReportsMessage() {
        struct Failure: LocalizedError { var errorDescription: String? { "Operation not permitted" } }
        let service = MockLoginItemService()
        service.error = Failure()
        let state = LaunchAtLoginController(service: service).set(true)
        XCTAssertFalse(state.isOn)
        XCTAssertEqual(state.hint, .error("Operation not permitted"))
    }
}

final class LocalizationTests: XCTestCase {
    func testEveryKeyExistsInAllLanguages() {
        let tables = AppLanguage.translations.map { ($0, L10n.table(for: $0)) }
        let allKeys = tables.reduce(into: Set<String>()) { $0.formUnion($1.1.keys) }
        XCTAssertGreaterThan(allKeys.count, 50)
        for (language, table) in tables {
            let missing = allKeys.subtracting(table.keys).sorted()
            XCTAssertTrue(missing.isEmpty, "\(language.rawValue) is missing: \(missing)")
            for (key, value) in table {
                XCTAssertFalse(value.trimmingCharacters(in: .whitespaces).isEmpty, "\(language.rawValue): empty \(key)")
            }
        }
    }

    func testFormatPlaceholdersMatchAcrossLanguages() throws {
        let pattern = try NSRegularExpression(pattern: "%[@d]")
        func placeholders(_ s: String) -> [String] {
            pattern.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { (s as NSString).substring(with: $0.range) }
        }
        let base = L10n.table(for: .ptBR)
        for language in [AppLanguage.en, .es] {
            for (key, value) in L10n.table(for: language) {
                XCTAssertEqual(placeholders(value), placeholders(base[key] ?? ""), "\(language.rawValue): \(key)")
            }
        }
    }

    func testLookupAndFormatting() {
        XCTAssertEqual(L10n(language: .en).string("row.inUse"), "In use")
        XCTAssertEqual(L10n(language: .es).string("row.inUse"), "En uso")
        XCTAssertEqual(L10n(language: .ptBR).string("row.inUse"), "Em uso")
        XCTAssertEqual(L10n(language: .en).string("menu.using", ["AirPods"]), "Using AirPods")
        XCTAssertEqual(L10n(language: .es).string("status.ignoringMany", [3]), "Ignorando 3 micrófonos desactivados.")
        XCTAssertEqual(L10n(language: .en).string("no.such.key"), "no.such.key")
    }

    func testSystemLanguageResolution() {
        XCTAssertEqual(AppLanguage.system.resolved(preferred: ["pt-PT"]), .ptBR)
        XCTAssertEqual(AppLanguage.system.resolved(preferred: ["fr-FR", "es-MX", "en-US"]), .es)
        XCTAssertEqual(AppLanguage.system.resolved(preferred: ["en-GB"]), .en)
        XCTAssertEqual(AppLanguage.system.resolved(preferred: ["de-DE"]), .en)
        XCTAssertEqual(AppLanguage.es.resolved(preferred: ["pt-BR"]), .es)
    }
}
