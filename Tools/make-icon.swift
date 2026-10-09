// Draws the Minicode app icon and writes Resources/AppIcon.icns (and a 1024px PNG next to it).
// Usage: swiftc Tools/make-icon.swift -o build/make-icon && build/make-icon Resources/AppIcon.icns
import AppKit

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Draws the icon on a 1024×1024 canvas (origin bottom-left), following Apple's icon grid.
func drawIcon() {
    // Tile: rounded square with a violet → blue gradient and a soft drop shadow.
    let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x000000, 0.35); shadow.shadowOffset = NSSize(width: 0, height: -12); shadow.shadowBlurRadius = 28
    shadow.set()
    color(0x6D4AFF).setFill(); tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [color(0x9B6BFF), color(0x6D4AFF), color(0x2F7BFF)], atLocations: [0, 0.45, 1], colorSpace: .sRGB)!
        .draw(in: tile, angle: -50)
    // Gentle top highlight.
    NSGradient(colors: [color(0xFFFFFF, 0.22), color(0xFFFFFF, 0)])!.draw(in: tile, angle: -90)

    // Page with a folded corner.
    let page = NSRect(x: 262, y: 190, width: 500, height: 630)
    let fold: CGFloat = 120, r: CGFloat = 44
    let sheet = NSBezierPath()
    sheet.move(to: NSPoint(x: page.minX + r, y: page.minY))
    sheet.line(to: NSPoint(x: page.maxX - r, y: page.minY))
    sheet.appendArc(withCenter: NSPoint(x: page.maxX - r, y: page.minY + r), radius: r, startAngle: 270, endAngle: 360)
    sheet.line(to: NSPoint(x: page.maxX, y: page.maxY - fold))
    sheet.line(to: NSPoint(x: page.maxX - fold, y: page.maxY))
    sheet.line(to: NSPoint(x: page.minX + r, y: page.maxY))
    sheet.appendArc(withCenter: NSPoint(x: page.minX + r, y: page.maxY - r), radius: r, startAngle: 90, endAngle: 180)
    sheet.line(to: NSPoint(x: page.minX, y: page.minY + r))
    sheet.appendArc(withCenter: NSPoint(x: page.minX + r, y: page.minY + r), radius: r, startAngle: 180, endAngle: 270)
    sheet.close()
    NSGraphicsContext.saveGraphicsState()
    let pageShadow = NSShadow()
    pageShadow.shadowColor = color(0x1B0F5C, 0.35); pageShadow.shadowOffset = NSSize(width: 0, height: -14); pageShadow.shadowBlurRadius = 36
    pageShadow.set()
    NSColor.white.setFill(); sheet.fill()
    NSGraphicsContext.restoreGraphicsState()

    let corner = NSBezierPath()
    corner.move(to: NSPoint(x: page.maxX - fold, y: page.maxY))
    corner.line(to: NSPoint(x: page.maxX - fold, y: page.maxY - fold + 26))
    corner.appendArc(withCenter: NSPoint(x: page.maxX - fold + 26, y: page.maxY - fold + 26), radius: 26, startAngle: 180, endAngle: 270)
    corner.line(to: NSPoint(x: page.maxX, y: page.maxY - fold))
    corner.close()
    color(0xD9CCFF).setFill(); corner.fill()

    // The mark: a bold "</>".
    let ink = color(0x24135F)
    let chevrons = NSBezierPath()
    chevrons.move(to: NSPoint(x: 405, y: 680)); chevrons.line(to: NSPoint(x: 330, y: 590)); chevrons.line(to: NSPoint(x: 405, y: 500))
    chevrons.move(to: NSPoint(x: 619, y: 680)); chevrons.line(to: NSPoint(x: 694, y: 590)); chevrons.line(to: NSPoint(x: 619, y: 500))
    chevrons.lineWidth = 46; chevrons.lineCapStyle = .round; chevrons.lineJoinStyle = .round
    ink.setStroke(); chevrons.stroke()
    let slash = NSBezierPath()
    slash.move(to: NSPoint(x: 552, y: 700)); slash.line(to: NSPoint(x: 472, y: 480))
    slash.lineWidth = 42; slash.lineCapStyle = .round
    color(0x6D4AFF).setStroke(); slash.stroke()

    // A few lines of "code", indented and tinted like highlighted syntax.
    let lines: [(CGFloat, CGFloat, UInt32)] = [(0, 230, 0xB9A6FF), (44, 290, 0xE3E0F0), (44, 190, 0xFFC9C4), (0, 120, 0xE3E0F0)]
    for (i, (indent, width, tint)) in lines.enumerated() {
        let y = 395 - CGFloat(i) * 52
        let bar = NSBezierPath(roundedRect: NSRect(x: 322 + indent, y: y, width: width, height: 24), xRadius: 12, yRadius: 12)
        color(tint).setFill(); bar.fill()
    }
}

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current!.imageInterpolation = .high
    let scale = CGFloat(size) / 1024
    NSAffineTransform(transform: { let t = NSAffineTransform(); t.scale(by: scale); return t }() as AffineTransform).concat()
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns"
let tmp = ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory()
let iconset = URL(fileURLWithPath: tmp).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try png(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try png(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try png(size: 1024).write(to: URL(fileURLWithPath: (output as NSString).deletingPathExtension + ".png"))

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output]
try task.run(); task.waitUntilExit()
exit(task.terminationStatus)
