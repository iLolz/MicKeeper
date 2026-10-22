import Foundation

/// A microphone the app has seen at least once.
public struct KnownDevice: Codable, Equatable, Identifiable, Sendable {
    public var uid: String
    /// Name the device had the last time it was seen.
    public var name: String
    public var transportType: TransportType

    public var id: String { uid }

    public init(uid: String, name: String, transportType: TransportType) {
        self.uid = uid
        self.name = name
        self.transportType = transportType
    }

    public init(_ device: AudioDevice) {
        self.init(uid: device.uid, name: device.name, transportType: device.transportType)
    }
}

/// User preferences: priority order (first = most preferred) and disabled microphones.
public struct PriorityConfig: Codable, Equatable, Sendable {
    public var devices: [KnownDevice]
    public var disabledUIDs: Set<String>
    /// When true, Bluetooth microphones seen for the first time start disabled.
    public var autoDisableBluetoothMics: Bool

    public init(devices: [KnownDevice] = [], disabledUIDs: Set<String> = [], autoDisableBluetoothMics: Bool = true) {
        self.devices = devices
        self.disabledUIDs = disabledUIDs
        self.autoDisableBluetoothMics = autoDisableBluetoothMics
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        devices = try c.decodeIfPresent([KnownDevice].self, forKey: .devices) ?? []
        disabledUIDs = try c.decodeIfPresent(Set<String>.self, forKey: .disabledUIDs) ?? []
        autoDisableBluetoothMics = try c.decodeIfPresent(Bool.self, forKey: .autoDisableBluetoothMics) ?? true
    }

    public func isEnabled(uid: String) -> Bool { !disabledUIDs.contains(uid) }

    public func position(of uid: String) -> Int? { devices.firstIndex { $0.uid == uid } }

    /// Appends devices not seen before (disabling new Bluetooth mics when configured)
    /// and refreshes the stored name/transport of known ones.
    /// On first run (empty list) the initial order is seeded by transport: built-in, USB, other,
    /// iPhone, Bluetooth, virtual, so the enforcer does not jump to an arbitrary device.
    /// - Returns: the devices that were added.
    @discardableResult
    public mutating func register(_ available: [AudioDevice]) -> [KnownDevice] {
        var ordered = available
        if devices.isEmpty {
            ordered = available.enumerated()
                .sorted { ($0.element.transportType.defaultRank, $0.offset) < ($1.element.transportType.defaultRank, $1.offset) }
                .map(\.element)
        }
        var added: [KnownDevice] = []
        for device in ordered {
            if let index = position(of: device.uid) {
                devices[index].name = device.name
                devices[index].transportType = device.transportType
            } else {
                let known = KnownDevice(device)
                devices.append(known)
                if autoDisableBluetoothMics && device.isBluetooth {
                    disabledUIDs.insert(device.uid)
                }
                added.append(known)
            }
        }
        return added
    }

    /// Moves a device to a zero-based position (clamped to the list bounds).
    public mutating func move(uid: String, to newIndex: Int) {
        guard let index = position(of: uid) else { return }
        let device = devices.remove(at: index)
        devices.insert(device, at: min(max(newIndex, 0), devices.count))
    }

    /// Same signature as SwiftUI's `onMove`.
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.map { devices[$0] }
        var remaining = devices.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt = destination - source.filter { $0 < destination }.count
        remaining.insert(contentsOf: moving, at: min(max(insertAt, 0), remaining.count))
        devices = remaining
    }

    public mutating func setEnabled(_ enabled: Bool, uid: String) {
        if enabled { disabledUIDs.remove(uid) } else { disabledUIDs.insert(uid) }
    }

    public mutating func forget(uid: String) {
        devices.removeAll { $0.uid == uid }
        disabledUIDs.remove(uid)
    }

    /// Removes every known device that is not in `available`.
    /// A removed device that reconnects is treated as new again.
    public mutating func forgetDisconnected(available: [AudioDevice]) {
        let connected = Set(available.map(\.uid))
        for known in devices where !connected.contains(known.uid) {
            forget(uid: known.uid)
        }
    }
}

/// Reads and writes the config as JSON.
public final class ConfigStore {
    public let url: URL

    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MicPriority", isDirectory: true).appendingPathComponent("config.json")
    }

    public init(url: URL = ConfigStore.defaultURL) {
        self.url = url
    }

    /// Returns the saved config, or a default one if the file does not exist.
    public func load() throws -> PriorityConfig {
        guard FileManager.default.fileExists(atPath: url.path) else { return PriorityConfig() }
        return try JSONDecoder().decode(PriorityConfig.self, from: Data(contentsOf: url))
    }

    public func save(_ config: PriorityConfig) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: url, options: .atomic)
    }
}
