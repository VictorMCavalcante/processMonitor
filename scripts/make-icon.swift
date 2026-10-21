import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.icns")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    let s = CGFloat(px) / 1024
    cg.translateBy(x: 0, y: CGFloat(px))
    cg.scaleBy(x: s, y: -s)
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let gradient = NSGradient(starting: color(0x9A55FF), ending: color(0x7426F0))!
    let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
    gradient.draw(in: shape, angle: -90)
    let u = body.width / 96
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: body.minX + x * u, y: body.minY + y * u) }
    let pulse = NSBezierPath()
    pulse.move(to: p(18, 54))
    for (x, y) in [(34, 54), (41, 36), (52, 66), (59, 46), (78, 46)] as [(CGFloat, CGFloat)] { pulse.line(to: p(x, y)) }
    pulse.lineWidth = 6 * u
    pulse.lineCapStyle = .round
    pulse.lineJoinStyle = .round
    color(0xFFFFFF).setStroke()
    pulse.stroke()
    color(0xD9C7FF, 0.85).setStroke()
    for (i, x) in [18, 33, 48, 63, 78].enumerated() {
        let tick = NSBezierPath()
        tick.move(to: p(CGFloat(x), i % 2 == 0 ? 74 : 76))
        tick.line(to: p(CGFloat(x), 80))
        tick.lineWidth = 3 * u
        tick.lineCapStyle = .round
        tick.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try task.run()
task.waitUntilExit()
try? render(1024).write(to: out.deletingPathExtension().appendingPathExtension("png"))
print(task.terminationStatus == 0 ? "ok \(out.path)" : "iconutil failed")
