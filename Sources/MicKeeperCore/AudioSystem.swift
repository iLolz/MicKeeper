import Foundation

/// A change reported by the audio system.
public enum AudioChangeEvent: Equatable, Sendable {
    /// Devices were added or removed.
    case devicesChanged
    /// The system default input device changed.
    case defaultInputChanged
}

public enum AudioSystemError: Error, CustomStringConvertible {
    case deviceNotFound(uid: String)
    case coreAudio(status: Int32, operation: String)

    public var description: String {
        switch self {
        case .deviceNotFound(let uid): return "No input device with uid \(uid)"
        case .coreAudio(let status, let operation): return "\(operation) failed (OSStatus \(status))"
        }
    }
}

/// Abstraction over the audio hardware so the engine can be tested without devices.
public protocol AudioSystem: AnyObject {
    func listInputDevices() -> [AudioDevice]
    func currentDefaultInput() -> AudioDevice?
    func setDefaultInput(uid: String) throws
    /// Starts delivering change events. Calling again replaces the handler.
    func startListening(_ handler: @escaping (AudioChangeEvent) -> Void)
    func stopListening()
}

public extension AudioSystem {
    /// Change events as an AsyncStream. Listening stops when the stream is terminated.
    func changeEvents() -> AsyncStream<AudioChangeEvent> {
        AsyncStream { continuation in
            startListening { continuation.yield($0) }
            continuation.onTermination = { [weak self] _ in self?.stopListening() }
        }
    }
}
