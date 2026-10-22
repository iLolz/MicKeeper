import AppKit
import SwiftUI

/// Design tokens shared by the window and (step 3) the menu bar popover.
/// Each color resolves to its light or dark variant from the current appearance.
enum Theme {
    static let bg = Color(light: 0xF5F5F7, dark: 0x1E1E20)
    static let surface = Color(light: 0xFFFFFF, dark: 0x2A2A2D)
    static let border = Color(light: 0xE2E2E7, dark: 0x3A3A3E)
    static let text = Color(light: 0x1D1D1F, dark: 0xF2F2F4)
    static let muted = Color(light: 0x6B6B70, dark: 0xA4A4AA)
    static let faint = Color(light: 0xB4B4BA, dark: 0x6A6A70)
    static let accent = Color(light: 0x0A7F64, dark: 0x2FBF8F)
    static let accentSoft = Color(light: 0xDDF2EA, dark: 0x173A2F)
    static let accentText = Color(light: 0x075F4B, dark: 0x5FE0B3)
    static let iconBg = Color(light: 0xEFEFF3, dark: 0x36363A)
    static let iconFg = Color(light: 0x3A3A3E, dark: 0xD8D8DC)
    static let switchOff = Color(light: 0xD6D6DB, dark: 0x4A4A4F)
    static let pausedBg = Color(light: 0xFBEFD9, dark: 0x3A3022)
    static let pausedDot = Color(light: 0xB26F0C, dark: 0xC98A2A)
    static let pausedText = Color(light: 0x8A5200, dark: 0xE9B25E)

    // Menu bar popover (step 3).
    static let popoverBg = Color(light: 0xF7F7F9, dark: 0x26262A)
    static let selectedRow = Color(light: 0xE9E9EE, dark: 0x33333A)

    enum Font {
        static let base = SwiftUI.Font.system(size: 13)
        static let title = SwiftUI.Font.system(size: 17, weight: .semibold)
        static let section = SwiftUI.Font.system(size: 11, weight: .semibold)
        static let meta = SwiftUI.Font.system(size: 12)
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

/// Uppercase, tracked, small label used for section and card captions.
struct SectionLabel: View {
    let text: String
    var color: Color = Theme.muted

    var body: some View {
        Text(text.uppercased())
            .font(Theme.Font.section)
            .tracking(0.6)
            .foregroundStyle(color)
    }
}

/// Switch drawn with the theme tokens (accent when on, switchOff when off), same in active and inactive windows.
struct AccentSwitch: View {
    @Binding var isOn: Bool
    var label: String
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Capsule()
                .fill(isOn ? Theme.accent : Theme.switchOff)
                .frame(width: 32, height: 19)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
                        .padding(2)
                }
                .animation(.easeInOut(duration: 0.15), value: isOn)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "Ligado" : "Desligado")
        .accessibilityAddTraits(.isButton)
    }
}
