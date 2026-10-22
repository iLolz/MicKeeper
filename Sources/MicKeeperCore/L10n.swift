import Foundation

/// Languages the UI is translated into, plus "follow the system".
public enum AppLanguage: String, CaseIterable, Codable, Sendable {
    case system
    case ptBR = "pt-BR"
    case en
    case es

    public static let translations: [AppLanguage] = [.ptBR, .en, .es]

    /// Name of the language in itself (nil for `.system`, whose label is localized).
    public var nativeName: String? {
        switch self {
        case .system: return nil
        case .ptBR: return "Português (Brasil)"
        case .en: return "English"
        case .es: return "Español"
        }
    }

    /// The concrete language to show. `.system` picks the first supported language in the
    /// user's preferred list (which includes a per-app choice made in System Settings), else English.
    public func resolved(preferred: [String] = Locale.preferredLanguages) -> AppLanguage {
        guard self == .system else { return self }
        for identifier in preferred {
            let code = identifier.lowercased()
            if code.hasPrefix("pt") { return .ptBR }
            if code.hasPrefix("es") { return .es }
            if code.hasPrefix("en") { return .en }
        }
        return .en
    }

    public var locale: Locale { Locale(identifier: resolved().rawValue) }
}

/// String lookup for one language, loaded straight from the `.strings` tables so the
/// language can change while the app runs (no restart, no AppleLanguages).
public final class L10n {
    /// The language the UI currently uses. Set by the app; read by `tr(_:)`.
    public static var current = L10n(language: AppLanguage.system.resolved())

    public let language: AppLanguage
    private let table: [String: String]
    private let fallback: [String: String]

    public init(language: AppLanguage) {
        let resolved = language.resolved()
        self.language = resolved
        self.table = Self.table(for: resolved)
        self.fallback = resolved == .ptBR ? [:] : Self.table(for: .ptBR)
    }

    /// Localized string for `key`, formatted with `arguments` (`%@`, `%d`).
    /// Falls back to Portuguese, then to the key itself.
    public func string(_ key: String, _ arguments: [CVarArg] = []) -> String {
        let format = table[key] ?? fallback[key] ?? key
        return arguments.isEmpty ? format : String(format: format, locale: Locale(identifier: language.rawValue), arguments: arguments)
    }

    /// The raw key/value table of a language (used by tests to check for missing translations).
    public static func table(for language: AppLanguage) -> [String: String] {
        guard let url = resourceBundle.url(forResource: "Localizable", withExtension: "strings",
                                           subdirectory: nil, localization: language.resolved().rawValue),
              let dict = NSDictionary(contentsOf: url) as? [String: String] else { return [:] }
        return dict
    }

    /// The bundle with the `.lproj` folders: inside the .app (Contents/Resources) when packaged,
    /// otherwise the SwiftPM resource bundle (`swift run`, tests).
    public static let resourceBundle: Bundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("MicKeeper_MicKeeperCore.bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return Bundle.module
    }()
}

/// Shorthand for `L10n.current.string(key, args)`.
public func tr(_ key: String, _ arguments: CVarArg...) -> String {
    L10n.current.string(key, arguments)
}
