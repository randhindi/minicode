// Draws the app icon and writes Resources/AppIcon.icns.
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

    // The Markdown mark: "M↓" in a rounded frame.
    let ink = color(0x24135F)
    let frame = NSBezierPath(roundedRect: NSRect(x: 322, y: 470, width: 380, height: 230), xRadius: 34, yRadius: 34)
    frame.lineWidth = 26; ink.setStroke(); frame.stroke()

    let m = NSBezierPath()
    m.move(to: NSPoint(x: 377, y: 525)); m.line(to: NSPoint(x: 377, y: 645))
    m.line(to: NSPoint(x: 432, y: 585)); m.line(to: NSPoint(x: 487, y: 645)); m.line(to: NSPoint(x: 487, y: 525))
    m.lineWidth = 30; m.lineJoinStyle = .round; m.lineCapStyle = .round; m.stroke()

    let shaft = NSBezierPath()
    shaft.move(to: NSPoint(x: 600, y: 645)); shaft.line(to: NSPoint(x: 600, y: 575))
    shaft.lineWidth = 30; shaft.lineCapStyle = .round; shaft.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 548, y: 590)); head.line(to: NSPoint(x: 652, y: 590)); head.line(to: NSPoint(x: 600, y: 520)); head.close()
    head.lineWidth = 10; head.lineJoinStyle = .round
    ink.setFill(); head.fill(); head.stroke()

    // A few lines of "rendered text".
    for (i, width) in [380, 310, 350, 240].enumerated() {
        let y = 395 - CGFloat(i) * 52
        let bar = NSBezierPath(roundedRect: NSRect(x: 322, y: y, width: CGFloat(width), height: 24), xRadius: 12, yRadius: 12)
        (i == 0 ? color(0xB9A6FF) : color(0xE3E0F0)).setFill(); bar.fill()
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
