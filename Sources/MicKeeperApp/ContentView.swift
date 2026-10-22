import MicKeeperCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmingRemoval = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                header
                StatusCard(device: model.currentDefault, status: model.status, ignored: model.ignoredNames)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Ordem de prioridade")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        Spacer()
                        Text("Arraste para reordenar")
                            .font(Theme.Font.meta)
                            .foregroundStyle(Theme.muted)
                    }
                    DeviceListCard()
                }
                settings
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            // Room for the traffic lights, which sit over the content (hidden title bar).
            .padding(.top, 38)
            .padding(.bottom, 16)

            footer
        }
        .font(Theme.Font.base)
        .foregroundStyle(Theme.text)
        .background(Theme.bg)
        .confirmationDialog("Remover os microfones desconectados da lista?", isPresented: $confirmingRemoval) {
            Button("Remover", role: .destructive) { model.removeDisconnected() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se um deles conectar de novo, ele volta para o fim da lista.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "mic.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.accent))
            VStack(alignment: .leading, spacing: 2) {
                Text("MicKeeper").font(Theme.Font.title)
                Text("Seu microfone preferido, sempre.")
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            HStack(spacing: 8) {
                Text("Automático").foregroundStyle(Theme.muted)
                AccentSwitch(isOn: Binding(get: { model.autoSwitch }, set: { model.setAutoSwitch($0) }),
                             label: "Troca automática")
                    .help(model.autoSwitch ? "Pausar a troca automática" : "Retomar a troca automática")
            }
        }
    }

    private var settings: some View {
        VStack(spacing: 0) {
            SettingRow(title: "Desativar microfones Bluetooth novos",
                       detail: "Fones conectados pela primeira vez entram desligados.",
                       isOn: Binding(get: { model.autoDisableBluetooth }, set: { model.setAutoDisableBluetooth($0) }))
            Rectangle().fill(Theme.border).frame(height: 1)
            // Wired up in step 3 (SMAppService).
            SettingRow(title: "Iniciar com o sistema",
                       detail: "Disponível em breve.",
                       isOn: .constant(false))
                .disabled(true)
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border))
    }

    private var footer: some View {
        HStack {
            Text("Ao fechar, fica na barra de menus")
                .font(Theme.Font.meta)
                .foregroundStyle(Theme.muted)
            Spacer()
            Button("Remover desconectados") { confirmingRemoval = true }
                .controlSize(.small)
                .disabled(!model.hasDisconnected)
                .help("Tira da lista os microfones que não estão conectados agora")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Theme.bg)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
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
                Text(device?.name ?? "Nenhum microfone")
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
        case .keeping, .adjusting: return "Em uso agora"
        case .paused: return "Pausado"
        case .noneAvailable: return "Sem microfone preferido"
        case .failed: return "Erro ao trocar"
        }
    }

    private var message: String {
        let base: String
        switch status {
        case .keeping: base = "Mantendo sua preferência."
        case .adjusting: base = "Ajustando para sua preferência…"
        case .paused: return "O macOS escolhe o microfone sozinho."
        case .noneAvailable: return "Nenhum microfone ativo está conectado. O macOS escolhe sozinho."
        case .failed(let error): return "Não foi possível trocar o microfone (\(error))."
        }
        switch ignored.count {
        case 0: return base
        case 1: return "\(base) Ignorando \(ignored[0]), que está desativado."
        default: return "\(base) Ignorando \(ignored.count) microfones desativados."
        }
    }
}

private struct DeviceListCard: View {
    @EnvironmentObject private var model: AppModel
    private let rowHeight: CGFloat = 53

    var body: some View {
        Group {
            if model.rows.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "mic.slash").font(.system(size: 24)).foregroundStyle(Theme.faint)
                    Text("Nenhum microfone encontrado").foregroundStyle(Theme.muted)
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
                                Button(row.isEnabled ? "Desativar" : "Ativar") {
                                    model.setEnabled(!row.isEnabled, uid: row.uid)
                                }
                            }
                    }
                    .onMove { model.move(fromOffsets: $0, toOffset: $1) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, rowHeight)
                // Grow with the rows; scroll only when the window is too short for all of them.
                .frame(minHeight: rowHeight * CGFloat(min(model.rows.count, 3)),
                       maxHeight: rowHeight * CGFloat(model.rows.count))
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
                .help("Arraste para reordenar")
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
                        Text("Em uso")
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
                         label: row.isEnabled ? "Desativar \(row.name)" : "Ativar \(row.name)")
        }
        .padding(.vertical, 8)
    }

    private var meta: String {
        var state = row.isConnected ? "Conectado" : "Desconectado"
        if !row.isEnabled { state += ", desativado" }
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
