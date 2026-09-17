import AppKit

let paper = NSColor(calibratedRed: 0.973, green: 0.957, blue: 0.933, alpha: 1)
let seal = NSColor(calibratedRed: 0.545, green: 0.173, blue: 0.255, alpha: 1)

func drawIcon(in rect: NSRect) {
    NSGraphicsContext.current?.compositingOperation = .copy
    NSColor.clear.setFill()
    rect.fill()
    NSGraphicsContext.current?.compositingOperation = .sourceOver

    let size = rect.width
    let inset = size * 0.08
    let outer = rect.insetBy(dx: inset, dy: inset)
    let inner = outer.insetBy(dx: size * 0.055, dy: size * 0.055)
    let outerRadius = size * 0.16
    let innerRadius = size * 0.12

    let outerPath = NSBezierPath(roundedRect: outer, xRadius: outerRadius, yRadius: outerRadius)
    paper.setFill()
    outerPath.fill()

    seal.setStroke()
    outerPath.lineWidth = max(1.2, size * 0.028)
    outerPath.stroke()

    let innerPath = NSBezierPath(roundedRect: inner, xRadius: innerRadius, yRadius: innerRadius)
    innerPath.lineWidth = max(1.6, size * 0.038)
    innerPath.stroke()

    let fontSize = size * 0.38
    let font = NSFont(name: "Iowan Old Style", size: fontSize)
        ?? NSFont.systemFont(ofSize: fontSize, weight: .semibold)
    let text = "Aa" as NSString
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: seal,
    ]
    let textSize = text.size(withAttributes: attributes)
    let point = NSPoint(
        x: rect.midX - textSize.width / 2,
        y: rect.midY - textSize.height / 2 + size * 0.02
    )
    text.draw(at: point, withAttributes: attributes)
}

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    drawIcon(in: NSRect(x: 0, y: 0, width: CGFloat(size), height: CGFloat(size)))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = root.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]
for (name, size) in sizes {
    try png(size: size).write(to: iconset.appendingPathComponent(name))
}

let icns = root.appendingPathComponent("AppIcon.icns")
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", "-o", icns.path, iconset.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    fputs("iconutil failed\n", stderr)
    exit(1)
}
try? FileManager.default.removeItem(at: iconset)
print("Wrote \(icns.path)")
