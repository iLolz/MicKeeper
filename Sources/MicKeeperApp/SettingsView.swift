import MicKeeperCore
import SwiftUI

/// Settings window content: for now, the interface language.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("settings.language")).font(.system(size: 13, weight: .medium))
                    Text(tr("settings.language.detail")).font(Theme.Font.meta).foregroundStyle(Theme.muted)
                        .fixedSize()
                }
                Spacer(minLength: 12)
                Picker(tr("settings.language"), selection: Binding(get: { model.languageChoice },
                                                                   set: { model.setLanguage($0) })) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(Self.label(for: language)).tag(language)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border))
        }
        .padding(20)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .font(Theme.Font.base)
        .foregroundStyle(Theme.text)
        .background(Theme.bg.ignoresSafeArea())
    }

    /// Each language in itself; "Automático" in the current UI language.
    static func label(for language: AppLanguage) -> String {
        language.nativeName ?? tr("language.system")
    }
}

/// Rebuilds its content when the language changes, so every `tr(...)` is re-read.
struct LocalizedRoot<Content: View>: View {
    @EnvironmentObject private var model: AppModel
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .id(model.language)
            .environment(\.locale, Locale(identifier: model.language.rawValue))
    }
}
