import CoreAudio

/// How a device is connected to the Mac.
public enum TransportType: String, Codable, CaseIterable, Sendable {
    case builtIn, bluetooth, bluetoothLE, usb, virtual, aggregate
    /// iPhone microphone via Continuity.
    case continuity
    case other

    init(coreAudioValue value: UInt32) {
        switch value {
        case kAudioDeviceTransportTypeBuiltIn: self = .builtIn
        case kAudioDeviceTransportTypeBluetooth: self = .bluetooth
        case kAudioDeviceTransportTypeBluetoothLE: self = .bluetoothLE
        case kAudioDeviceTransportTypeUSB: self = .usb
        case kAudioDeviceTransportTypeVirtual: self = .virtual
        case kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeAutoAggregate: self = .aggregate
        case kAudioDeviceTransportTypeContinuityCaptureWired, kAudioDeviceTransportTypeContinuityCaptureWireless:
            self = .continuity
        default: self = .other
        }
    }

    public var isBluetooth: Bool { self == .bluetooth || self == .bluetoothLE }

    /// Order used to seed the priority list on first run (lower = more preferred).
    var defaultRank: Int {
        switch self {
        case .builtIn: return 0
        case .usb: return 1
        case .aggregate, .other: return 2
        case .continuity: return 3
        case .bluetooth, .bluetoothLE: return 4
        case .virtual: return 5
        }
    }

    public var displayName: String {
        switch self {
        case .builtIn: return "Built-in"
        case .bluetooth: return "Bluetooth"
        case .bluetoothLE: return "Bluetooth LE"
        case .usb: return "USB"
        case .virtual: return "Virtual"
        case .aggregate: return "Aggregate"
        case .continuity: return "iPhone (Continuity)"
        case .other: return "Other"
        }
    }
}

/// An audio device that has at least one input channel.
public struct AudioDevice: Identifiable, Hashable, Sendable {
    /// CoreAudio object id. Changes between connections; use `uid` as the stable key.
    public var id: AudioDeviceID
    /// Persistent unique id (kAudioDevicePropertyDeviceUID).
    public var uid: String
    public var name: String
    public var transportType: TransportType
    public var isAlive: Bool

    public init(id: AudioDeviceID, uid: String, name: String, transportType: TransportType, isAlive: Bool = true) {
        self.id = id
        self.uid = uid
        self.name = name
        self.transportType = transportType
        self.isAlive = isAlive
    }

    public var isBluetooth: Bool { transportType.isBluetooth }
}
