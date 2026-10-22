import Foundation
import ServiceManagement

/// Login item registration status (mirrors `SMAppService.Status`).
public enum LoginItemStatus: Equatable, Sendable {
    case notRegistered, enabled, requiresApproval, notFound
}

/// Abstraction over `SMAppService.mainApp` so the logic can be tested.
public protocol LoginItemService: AnyObject {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
}

public final class SystemLoginItemService: LoginItemService {
    public init() {}

    public var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        default: return .notRegistered
        }
    }

    public func register() throws { try SMAppService.mainApp.register() }
    public func unregister() throws { try SMAppService.mainApp.unregister() }

    public static func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}

/// What the "Iniciar com o sistema" row shows.
public struct LaunchAtLoginState: Equatable, Sendable {
    public enum Hint: Equatable, Sendable {
        case none
        /// Registered, but the user must allow it in System Settings > Login Items.
        case needsApproval
        /// macOS cannot find the app bundle (e.g. not in a stable location).
        case notFound
        case error(String)
    }

    public var isOn: Bool
    public var hint: Hint

    public init(isOn: Bool, hint: Hint = .none) {
        self.isOn = isOn
        self.hint = hint
    }

    public init(status: LoginItemStatus) {
        switch status {
        case .enabled: self.init(isOn: true)
        case .requiresApproval: self.init(isOn: true, hint: .needsApproval)
        case .notFound: self.init(isOn: false, hint: .notFound)
        case .notRegistered: self.init(isOn: false)
        }
    }
}

/// Turns launch at login on or off and reports the resulting state.
public final class LaunchAtLoginController {
    private let service: LoginItemService

    public init(service: LoginItemService = SystemLoginItemService()) {
        self.service = service
    }

    public var state: LaunchAtLoginState { LaunchAtLoginState(status: service.status) }

    @discardableResult
    public func set(_ on: Bool) -> LaunchAtLoginState {
        do {
            if on { try service.register() } else { try service.unregister() }
            return state
        } catch {
            var result = state
            result.hint = .error(error.localizedDescription)
            return result
        }
    }
}
