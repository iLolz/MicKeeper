// Renders the MicKeeper app icon (same geometry as Resources/logo.svg) into an .iconset
// and builds Resources/AppIcon.icns.
//
//   swift scripts/make-icon.swift
//
// At 16 and 32 px the stand (arc + stem) is dropped and the shield and capsule are bolder.
import AppKit
import CoreGraphics

struct Variant {
    var shieldStroke: CGFloat
    var capsule: CGRect
    var capsuleRadius: CGFloat
    var showStand: Bool

    static let full = Variant(shieldStroke: 44, capsule: CGRect(x: 460, y: 352, width: 104, height: 200), capsuleRadius: 52, showStand: true)
    static let px32 = Variant(shieldStroke: 64, capsule: CGRect(x: 450, y: 352, width: 124, height: 220), capsuleRadius: 62, showStand: false)
    static let px16 = Variant(shieldStroke: 80, capsule: CGRect(x: 440, y: 352, width: 144, height: 240), capsuleRadius: 72, showStand: false)

    static func forPixels(_ px: Int) -> Variant { px <= 16 ? .px16 : px <= 32 ? .px32 : .full }
}

func shieldPath() -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 512, y: 236))
    p.addLine(to: CGPoint(x: 736, y: 312))
    p.addLine(to: CGPoint(x: 736, y: 516))
    p.addCurve(to: CGPoint(x: 512, y: 806), control1: CGPoint(x: 736, y: 656), control2: CGPoint(x: 640, y: 752))
    p.addCurve(to: CGPoint(x: 288, y: 516), control1: CGPoint(x: 384, y: 752), control2: CGPoint(x: 288, y: 656))
    p.addLine(to: CGPoint(x: 288, y: 312))
    p.closeSubpath()
    return p
}

func render(pixels: Int) -> Data {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Work in the SVG's 1024 coordinate space with y pointing down.
    let scale = CGFloat(pixels) / 1024
    ctx.translateBy(x: 0, y: CGFloat(pixels))
    ctx.scaleBy(x: scale, y: -scale)
    ctx.setShouldAntialias(true)

    let v = Variant.forPixels(pixels)
    let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

    // Squircle background and its subtle top highlight.
    ctx.addPath(CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 185, cornerHeight: 185, transform: nil))
    ctx.setFillColor(CGColor(srgbRed: 0x0A / 255, green: 0x7F / 255, blue: 0x64 / 255, alpha: 1))
    ctx.fillPath()
    ctx.addPath(CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 412), cornerWidth: 185, cornerHeight: 185, transform: nil))
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.06))
    ctx.fillPath()

    // Shield outline.
    ctx.addPath(shieldPath())
    ctx.setStrokeColor(white)
    ctx.setLineWidth(v.shieldStroke)
    ctx.setLineJoin(.round)
    ctx.strokePath()

    // Mic capsule.
    ctx.addPath(CGPath(roundedRect: v.capsule, cornerWidth: v.capsuleRadius, cornerHeight: v.capsuleRadius, transform: nil))
    ctx.setFillColor(white)
    ctx.fillPath()

    // Stand: a half circle under the capsule, then the stem.
    if v.showStand {
        ctx.setLineWidth(34)
        ctx.setLineCap(.round)
        // In this y-down space, going from 180° to 0° "clockwise: true" passes through the bottom.
        ctx.addArc(center: CGPoint(x: 512, y: 500), radius: 106, startAngle: .pi, endAngle: 0, clockwise: true)
        ctx.strokePath()
        ctx.move(to: CGPoint(x: 512, y: 606))
        ctx.addLine(to: CGPoint(x: 512, y: 660))
        ctx.strokePath()
    }

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("MicKeeper-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for size in [16, 32, 128, 256, 512] {
    try render(pixels: size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(pixels: size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
try render(pixels: 1024).write(to: root.appendingPathComponent("Resources/AppIcon-1024.png"))

let output = root.appendingPathComponent("Resources/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Wrote \(output.path)")
