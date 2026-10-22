import Foundation

/// One microphone in the priority list, combined with its live state, ready for display.
public struct DeviceRow: Identifiable, Equatable, Sendable {
    public var uid: String
    public var name: String
    public var transportType: TransportType
    /// 1-based position in the priority order.
    public var position: Int
    public var isConnected: Bool
    public var isEnabled: Bool
    public var isCurrentDefault: Bool

    public var id: String { uid }

    public init(uid: String, name: String, transportType: TransportType, position: Int,
                isConnected: Bool, isEnabled: Bool, isCurrentDefault: Bool) {
        self.uid = uid
        self.name = name
        self.transportType = transportType
        self.position = position
        self.isConnected = isConnected
        self.isEnabled = isEnabled
        self.isCurrentDefault = isCurrentDefault
    }

    /// Rows in priority order. Connected devices use their live name and transport.
    public static func rows(config: PriorityConfig, available: [AudioDevice], currentDefaultUID: String?) -> [DeviceRow] {
        let live = Dictionary(available.filter(\.isAlive).map { ($0.uid, $0) }, uniquingKeysWith: { first, _ in first })
        return config.devices.enumerated().map { index, known in
            let device = live[known.uid]
            return DeviceRow(
                uid: known.uid,
                name: device?.name ?? known.name,
                transportType: device?.transportType ?? known.transportType,
                position: index + 1,
                isConnected: device != nil,
                isEnabled: config.isEnabled(uid: known.uid),
                isCurrentDefault: known.uid == currentDefaultUID)
        }
    }
}
