import MicKeeperCore
import SwiftUI

/// Content of the menu bar popover.
struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel
    let openWindow: () -> Void
    let openSettings: () -> Void
    let quit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 10)
            MenuDivider()
            SectionLabel(text: tr("menu.section"))
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 4)
            if model.rows.isEmpty {
                Text(tr("list.empty"))
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(model.rows) { row in
                        MenuDeviceRow(row: row) { model.useNow(uid: row.uid) }
                    }
                }
                .padding(.horizontal, 6)
            }
            MenuDivider()
            HStack {
                Text(tr("autoSwitch"))
                Spacer()
                AccentSwitch(isOn: Binding(get: { model.autoSwitch }, set: { model.setAutoSwitch($0) }),
                             label: tr("autoSwitch"))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            MenuDivider()
            VStack(spacing: 0) {
                MenuActionRow(title: tr("menu.settings"), shortcut: "⌘,", action: openSettings)
                    .keyboardShortcut(",", modifiers: .command)
                MenuActionRow(title: tr("menu.open"), shortcut: "⌘O", action: openWindow)
                    .keyboardShortcut("o", modifiers: .command)
                MenuActionRow(title: tr("menu.quit"), shortcut: "⌘Q", action: quit)
                    .keyboardShortcut("q", modifiers: .command)
            }
            .padding(.horizontal, 6)
        }
        .padding(.vertical, 6)
        .frame(width: 320)
        .font(Theme.Font.base)
        .foregroundStyle(Theme.text)
        .background(Theme.popoverBg)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Logo.Tile(size: 28, cornerRadius: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text("MicKeeper").font(.system(size: 13, weight: .semibold))
                Text(tr("menu.using", model.currentDefault?.name ?? tr("menu.noMic")))
                    .font(Theme.Font.meta)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.85)
            }
            .layoutPriority(1)
            Spacer(minLength: 6)
            Text(model.autoSwitch ? tr("menu.active") : tr("menu.paused"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(model.autoSwitch ? Theme.accentText : Theme.pausedText)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(model.autoSwitch ? Theme.accentSoft : Theme.pausedBg))
                .fixedSize()
        }
    }
}

private struct MenuDivider: View {
    var body: some View {
        Rectangle().fill(Theme.border).frame(height: 1).padding(.vertical, 6)
    }
}

/// One microphone. Clicking an enabled, connected one makes it #1 and uses it now.
private struct MenuDeviceRow: View {
    let row: DeviceRow
    let action: () -> Void
    @State private var hovering = false

    private var selectable: Bool { row.isEnabled && row.isConnected }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 14)
                    .opacity(row.isCurrentDefault ? 1 : 0)
                Text(row.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(meta)
                    .font(Theme.Font.meta)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .layoutPriority(-1)
                Spacer(minLength: 8)
                Text("\(row.position)")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(hovering && selectable ? Theme.selectedRow : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!selectable)
        .opacity(selectable ? 1 : 0.45)
        .onHover { hovering = $0 }
        .help(selectable ? tr("row.useNow.help") : "")
    }

    private var meta: String {
        if !row.isConnected { return tr("row.disconnected") }
        if !row.isEnabled { return tr("row.disabled") }
        return row.transportType.localizedName
    }
}

private struct MenuActionRow: View {
    let title: String
    let shortcut: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Text(shortcut).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(hovering ? Theme.selectedRow : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
