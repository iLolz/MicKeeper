import XCTest
@testable import MicPriorityCore

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
