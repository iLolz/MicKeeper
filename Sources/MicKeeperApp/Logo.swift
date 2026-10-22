import AppKit
import SwiftUI

/// The MicKeeper mark (mic inside a shield), drawn from the same geometry as Resources/logo.svg.
enum Logo {
    /// White mark for the accent header tiles. The icon's squircle (x/y 100…924 of 1024) maps onto the tile.
    struct Glyph: View {
        var body: some View {
            Canvas { context, size in
                let scale = size.width / 824
                func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: (x - 100) * scale, y: (y - 100) * scale) }

                var shield = Path()
                shield.move(to: p(512, 236))
                shield.addLine(to: p(736, 312))
                shield.addLine(to: p(736, 516))
                shield.addCurve(to: p(512, 806), control1: p(736, 656), control2: p(640, 752))
                shield.addCurve(to: p(288, 516), control1: p(384, 752), control2: p(288, 656))
                shield.addLine(to: p(288, 312))
                shield.closeSubpath()
                context.stroke(shield, with: .color(.white),
                               style: StrokeStyle(lineWidth: max(44 * scale, 1.4), lineJoin: .round))

                let capsule = CGRect(origin: p(460, 352), size: CGSize(width: 104 * scale, height: 200 * scale))
                context.fill(Path(roundedRect: capsule, cornerRadius: 52 * scale), with: .color(.white))

                var stand = Path()
                stand.addArc(center: p(512, 500), radius: 106 * scale,
                             startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
                stand.move(to: p(512, 606))
                stand.addLine(to: p(512, 660))
                context.stroke(stand, with: .color(.white),
                               style: StrokeStyle(lineWidth: max(34 * scale, 1.2), lineCap: .round))
            }
        }
    }

    /// Accent rounded tile with the white mark, as in the window (40pt) and popover (28pt) headers.
    struct Tile: View {
        let size: CGFloat
        let cornerRadius: CGFloat

        var body: some View {
            Glyph()
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(Theme.accent))
                .accessibilityHidden(true)
        }
    }

    /// 18pt template image for the menu bar (24-unit artwork, 1.7 stroke). The paused variant is crossed out.
    static func menuBarImage(paused: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            let scale = rect.width / 24
            let transform = NSAffineTransform()
            transform.scale(by: scale)
            transform.concat()
            NSColor.black.set()

            let shield = NSBezierPath()
            shield.move(to: NSPoint(x: 12, y: 2.5))
            shield.line(to: NSPoint(x: 19.5, y: 5))
            shield.line(to: NSPoint(x: 19.5, y: 11))
            shield.curve(to: NSPoint(x: 12, y: 21.5), controlPoint1: NSPoint(x: 19.5, y: 16), controlPoint2: NSPoint(x: 16, y: 19.5))
            shield.curve(to: NSPoint(x: 4.5, y: 11), controlPoint1: NSPoint(x: 8, y: 19.5), controlPoint2: NSPoint(x: 4.5, y: 16))
            shield.line(to: NSPoint(x: 4.5, y: 5))
            shield.close()
            shield.lineWidth = 1.7
            shield.lineJoinStyle = .round
            shield.stroke()

            NSBezierPath(roundedRect: NSRect(x: 10.2, y: 7, width: 3.6, height: 6.4), xRadius: 1.8, yRadius: 1.8).fill()

            let stand = NSBezierPath()
            stand.appendArc(withCenter: NSPoint(x: 12, y: 11.6), radius: 3.4, startAngle: 180, endAngle: 0, clockwise: true)
            stand.move(to: NSPoint(x: 12, y: 15))
            stand.line(to: NSPoint(x: 12, y: 16.6))
            if paused {
                stand.move(to: NSPoint(x: 3, y: 3))
                stand.line(to: NSPoint(x: 21, y: 21))
            }
            stand.lineWidth = 1.7
            stand.lineCapStyle = .round
            stand.lineJoinStyle = .round
            stand.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
