import MicKeeperCore

extension TransportType {
    var symbolName: String {
        switch self {
        case .builtIn: return "laptopcomputer"
        case .bluetooth, .bluetoothLE: return "headphones"
        case .continuity: return "iphone"
        case .usb: return "cable.connector"
        case .virtual: return "waveform"
        case .aggregate: return "square.stack.3d.up"
        case .other: return "mic"
        }
    }

    var localizedName: String {
        switch self {
        case .builtIn: return "Embutido"
        case .bluetooth: return "Bluetooth"
        case .bluetoothLE: return "Bluetooth LE"
        case .continuity: return "iPhone"
        case .usb: return "USB"
        case .virtual: return "Virtual"
        case .aggregate: return "Agregado"
        case .other: return "Outro"
        }
    }
}
