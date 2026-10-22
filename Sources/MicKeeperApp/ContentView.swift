import MicKeeperCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmingRemoval = false
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                header
                StatusCard(device: model.currentDefault, status: model.status, ignored: model.ignoredNames)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(tr("list.title"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        Spacer()
                        Text(tr("list.dragHint"))
                            .font(Theme.Font.meta)
                            .foregroundStyle(Theme.muted)
                    }
                    DeviceListCard()
                }
                settings
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 20)

            footer
        }
        .font(Theme.Font.base)
        .foregroundStyle(Theme.text)
        // Fixed width; the height hugs the content so the window grows and shrinks with the list.
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        // The title bar inset (safe area) clears the traffic lights; only the background goes under it.
        .background(Theme.bg.ignoresSafeArea())
        .confirmationDialog(tr("remove.confirm.title"), isPresented: $confirmingRemoval) {
            Button(tr("remove.confirm.ok"), role: .destructive) { model.removeDisconnected() }
            Button(tr("common.cancel"), role: .cancel) {}
        } message: {
            Text(tr("remove.confirm.message"))
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Logo.Tile(size: 40, cornerRadius: 10)
                .fixedSize()
            VStack(alignment: .leading, spacing: 2) {
                Text("MicKeeper").font(Theme.Font.title)
                Text(tr("app.tagline"))
                    .foregroundStyle(Theme.muted)
            }
            .fixedSize()
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                Button(action: openSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 22, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(tr("header.settings.help"))
                .accessibilityLabel(tr("header.settings.help"))
                Text(tr("header.auto")).foregroundStyle(Theme.muted)
                AccentSwitch(isOn: Binding(get: { model.autoSwitch }, set: { model.setAutoSwitch($0) }),
                             label: tr("autoSwitch"))
                    .help(model.autoSwitch ? tr("autoSwitch.pause.help") : tr("autoSwitch.resume.help"))
            }
            .fixedSize()
        }
    }

    private var settings: some View {
        VStack(spacing: 0) {
            SettingRow(title: tr("setting.bluetooth.title"),
                       detail: tr("setting.bluetooth.detail"),
                       isOn: Binding(get: { model.autoDisableBluetooth }, set: { model.setAutoDisableBluetooth($0) }))
            Rectangle().fill(Theme.border).frame(height: 1)
            LaunchAtLoginRow()
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border))
    }

    private var footer: some View {
        HStack {
            Text(tr("footer.closeHint"))
                .font(Theme.Font.meta)
                .foregroundStyle(Theme.muted)
            Spacer()
            Button(tr("footer.removeDisconnected")) { confirmingRemoval = true }
                .controlSize(.small)
                .disabled(!model.hasDisconnected)
                .help(tr("footer.removeDisconnected.help"))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Theme.bg)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
    }
}

private struct LaunchAtLoginRow: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("login.title")).font(.system(size: 13, weight: .medium))
                Text(detail).font(Theme.Font.meta).foregroundStyle(hintColor)
                    .fixedSize(horizontal: false, vertical: true)
                if model.launchAtLogin.hint == .needsApproval {
                    Button(tr("login.openSettings")) { model.openLoginItemsSettings() }
                        .controlSize(.small)
                        .padding(.top, 4)
                }
            }
            Spacer()
            AccentSwitch(isOn: Binding(get: { model.launchAtLogin.isOn }, set: { model.setLaunchAtLogin($0) }),
                         label: tr("login.title"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshLaunchAtLogin()
        }
    }

    private var detail: String {
        switch model.launchAtLogin.hint {
        case .none: return tr("login.detail")
        case .needsApproval: return tr("login.needsApproval")
        case .notFound: return tr("login.notFound")
        case .error(let message): return tr("login.error", message)
        }
    }

    private var hintColor: Color {
        switch model.launchAtLogin.hint {
        case .none: return Theme.muted
        case .needsApproval, .notFound, .error: return Theme.pausedText
        }
    }
}

private struct SettingRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(Theme.Font.meta).foregroundStyle(Theme.muted)
            }
            .opacity(isEnabled ? 1 : 0.55)
            Spacer()
            AccentSwitch(isOn: $isOn, label: title)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct StatusCard: View {
    let device: AudioDevice?
    let status: AppModel.Status
    let ignored: [String]

    private var isActive: Bool { status == .keeping || status == .adjusting }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isActive ? "checkmark" : "pause.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(isActive ? Theme.accent : Theme.pausedDot))
            VStack(alignment: .leading, spacing: 3) {
                SectionLabel(text: label, color: isActive ? Theme.accentText : Theme.pausedText)
                Text(device?.name ?? tr("status.noMic"))
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(message)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(isActive ? Theme.accentSoft : Theme.pausedBg))
        .animation(.easeInOut(duration: 0.2), value: status)
    }

    private var label: String {
        switch status {
        case .keeping, .adjusting: return tr("status.label.inUse")
        case .paused: return tr("status.label.paused")
        case .noneAvailable: return tr("status.label.noPreferred")
        case .failed: return tr("status.label.failed")
        }
    }

    private var message: String {
        let base: String
        switch status {
        case .keeping: base = tr("status.keeping")
        case .adjusting: base = tr("status.adjusting")
        case .paused: return tr("status.pausedDetail")
        case .noneAvailable: return tr("status.noneAvailable")
        case .failed(let error): return tr("status.failedDetail", error)
        }
        switch ignored.count {
        case 0: return base
        case 1: return base + " " + tr("status.ignoringOne", ignored[0])
        default: return base + " " + tr("status.ignoringMany", ignored.count)
        }
    }
}

private struct DeviceListCard: View {
    @EnvironmentObject private var model: AppModel
    private let rowHeight: CGFloat = 53
    private let maxVisibleRows = 7

    var body: some View {
        Group {
            if model.rows.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "mic.slash").font(.system(size: 24)).foregroundStyle(Theme.faint)
                    Text(tr("list.empty")).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                List {
                    ForEach(model.rows) { row in
                        DeviceRowView(row: row) { model.setEnabled($0, uid: row.uid) }
                            .listRowInsets(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 14))
                            .listRowBackground(Theme.surface)
                            .listRowSeparator(.hidden)
                            .overlay(alignment: .bottom) {
                                if row.uid != model.rows.last?.uid {
                                    Rectangle().fill(Theme.border).frame(height: 1).padding(.leading, 34)
                                }
                            }
                            .contextMenu {
                                Button(row.isEnabled ? tr("row.disable") : tr("row.enable")) {
                                    model.setEnabled(!row.isEnabled, uid: row.uid)
                                }
                            }
                    }
                    .onMove { model.move(fromOffsets: $0, toOffset: $1) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, rowHeight)
                // Exactly as tall as the rows, up to `maxVisibleRows`; beyond that only the list scrolls.
                .frame(height: rowHeight * CGFloat(min(model.rows.count, maxVisibleRows)))
            }
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border))
    }
}

struct DeviceRowView: View {
    let row: DeviceRow
    let onToggle: (Bool) -> Void

    private var dimmed: Bool { !row.isEnabled || !row.isConnected }

    var body: some View {
        HStack(spacing: 10) {
            DragHandle()
                .help(tr("list.dragHint"))
            Text("\(row.position)")
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.muted)
                .frame(width: 14, alignment: .trailing)
            Image(systemName: row.transportType.symbolName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(row.isEnabled ? Theme.iconFg : Theme.faint)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(row.isEnabled ? Theme.iconBg : Color.clear))
                .opacity(row.isConnected ? 1 : 0.55)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if row.isCurrentDefault {
                        Text(tr("row.inUse"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.accentText)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Theme.accentSoft))
                    }
                }
                Text(meta)
                    .font(Theme.Font.meta)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            .opacity(dimmed ? 0.55 : 1)
            Spacer(minLength: 8)
            AccentSwitch(isOn: Binding(get: { row.isEnabled }, set: onToggle),
                         label: row.isEnabled ? tr("row.disableNamed", row.name) : tr("row.enableNamed", row.name))
        }
        .padding(.vertical, 8)
    }

    private var meta: String {
        var state = row.isConnected ? tr("row.connected") : tr("row.disconnected")
        if !row.isEnabled { state = tr("row.disabledSuffix", state) }
        return "\(row.transportType.localizedName) · \(state)"
    }
}

/// 2x3 grid of dots marking a draggable row.
private struct DragHandle: View {
    var body: some View {
        VStack(spacing: 2.5) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 2.5) {
                    Circle().frame(width: 3, height: 3)
                    Circle().frame(width: 3, height: 3)
                }
            }
        }
        .foregroundStyle(Theme.faint)
        .frame(width: 10)
    }
}
