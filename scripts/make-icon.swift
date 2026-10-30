// Draws the app icon and writes Resources/AppIcon.icns.
// Run from the repository root: swift scripts/make-icon.swift
import AppKit
import CoreGraphics

let size = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func render() -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Work in top-left coordinates.
    ctx.translateBy(x: 0, y: CGFloat(size))
    ctx.scaleBy(x: 1, y: -1)

    // macOS icon grid: an 824pt rounded square centred on the 1024 canvas.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(tilePath)
    ctx.setFillColor(color(0x1E4E8C))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                              colors: [color(0x2FC4A6), color(0x2276C9), color(0x1B3F86)] as CFArray,
                              locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: tile.minX, y: tile.minY),
                           end: CGPoint(x: tile.maxX, y: tile.maxY), options: [])

    // Dust being swept off: a little git graph of commits and a branch.
    ctx.setStrokeColor(color(0xFFFFFF, 0.75))
    ctx.setLineWidth(18)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: 215, y: 820))
    ctx.addLine(to: CGPoint(x: 215, y: 690))
    ctx.move(to: CGPoint(x: 215, y: 780))
    ctx.addCurve(to: CGPoint(x: 305, y: 670), control1: CGPoint(x: 215, y: 720),
                 control2: CGPoint(x: 305, y: 740))
    ctx.strokePath()
    ctx.setFillColor(color(0xFFFFFF, 0.9))
    for (x, y, r) in [(215.0, 820.0, 30.0), (215.0, 690.0, 25.0), (305.0, 670.0, 23.0)] {
        ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }
    // Sparkles where it's already clean.
    for (x, y, r) in [(700.0, 250.0, 34.0), (790.0, 340.0, 20.0)] {
        sparkle(ctx, center: CGPoint(x: x, y: y), radius: r)
    }

    // The broom, leaning over, bristles towards the dust.
    ctx.saveGState()
    ctx.translateBy(x: 590, y: 470)
    ctx.rotate(by: .pi / 5)
    ctx.scaleBy(x: 0.85, y: 0.85)
    ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 24, color: color(0x0A1E40, 0.45))
    // Handle.
    ctx.setFillColor(color(0xF4E3C3))
    ctx.addPath(CGPath(roundedRect: CGRect(x: -22, y: -380, width: 44, height: 360),
                       cornerWidth: 22, cornerHeight: 22, transform: nil))
    ctx.fillPath()
    // Bristles: a flared fan of strands.
    let strands = 9
    let top = 40.0, bottom = 300.0, topHalf = 125.0, bottomHalf = 190.0
    for i in 0..<strands {
        let a = Double(i) / Double(strands), b = Double(i + 1) / Double(strands)
        let gap = 0.035
        let t0 = -topHalf + 2 * topHalf * (a + gap / 2), t1 = -topHalf + 2 * topHalf * (b - gap / 2)
        let b0 = -bottomHalf + 2 * bottomHalf * (a + gap / 2), b1 = -bottomHalf + 2 * bottomHalf * (b - gap / 2)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: t0, y: top))
        path.addLine(to: CGPoint(x: t1, y: top))
        path.addLine(to: CGPoint(x: b1, y: bottom))
        path.addQuadCurve(to: CGPoint(x: b0, y: bottom), control: CGPoint(x: (b0 + b1) / 2, y: bottom + 8))
        path.closeSubpath()
        ctx.addPath(path)
    }
    ctx.setFillColor(color(0xF7C548))
    ctx.fillPath()
    // Binding.
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    ctx.setFillColor(color(0xD9483B))
    ctx.addPath(CGPath(roundedRect: CGRect(x: -135, y: -30, width: 270, height: 84),
                       cornerWidth: 20, cornerHeight: 20, transform: nil))
    ctx.fillPath()
    ctx.setFillColor(color(0xFFFFFF, 0.25))
    ctx.fill(CGRect(x: -135, y: 2, width: 270, height: 12))
    ctx.restoreGState()

    ctx.restoreGState()
    return ctx.makeImage()!
}

func sparkle(_ ctx: CGContext, center c: CGPoint, radius r: CGFloat) {
    let path = CGMutablePath()
    let inner = r * 0.28
    path.move(to: CGPoint(x: c.x, y: c.y - r))
    path.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + inner, y: c.y - inner))
    path.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + inner, y: c.y + inner))
    path.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - inner, y: c.y + inner))
    path.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - inner, y: c.y - inner))
    ctx.addPath(path)
    ctx.setFillColor(color(0xFFFFFF, 0.9))
    ctx.fillPath()
}

func writePNG(_ image: CGImage, pixels: Int, to url: URL) throws {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    let data = NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
    try data.write(to: url)
}

let image = render()
let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try writePNG(image, pixels: points, to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try writePNG(image, pixels: points * 2, to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
try fm.createDirectory(atPath: "Resources", withIntermediateDirectories: true)
try writePNG(image, pixels: 1024, to: URL(fileURLWithPath: "Resources/AppIcon.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Wrote Resources/AppIcon.icns and Resources/AppIcon.png")
