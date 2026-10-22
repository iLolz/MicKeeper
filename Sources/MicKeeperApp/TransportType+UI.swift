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

    var localizedName: String { tr("transport.\(rawValue)") }
}
