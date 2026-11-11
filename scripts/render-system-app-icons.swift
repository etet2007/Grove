import AppKit
import Foundation

// Native document opened and saved by Icon Composer 27.2. Glass is disabled
// for the already shaded artwork; Composer still renders the outer tile rim.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let requestedDestination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let destination: URL
if requestedDestination.pathExtension == "bundle" {
    guard let resources = Bundle(url: requestedDestination)?.resourceURL else {
        fatalError("Cannot locate resource directory in \(requestedDestination.path)")
    }
    destination = resources.appendingPathComponent("SystemAppIcons", isDirectory: true)
} else {
    destination = requestedDestination
}
let developer = Process()
developer.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
developer.arguments = ["-p"]
let pipe = Pipe()
developer.standardOutput = pipe
try developer.run()
let developerPath = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    .trimmingCharacters(in: .whitespacesAndNewlines)
developer.waitUntilExit()
let tool = URL(fileURLWithPath: developerPath)
    .appendingPathComponent("../Applications/Icon Composer.app/Contents/Executables/ictool").standardizedFileURL
guard developer.terminationStatus == 0, FileManager.default.isExecutableFile(atPath: tool.path) else {
    fatalError("Icon Composer ictool is required. Select full Xcode with xcode-select.")
}

let concepts: [(String, String, CGFloat, CGFloat)] = [
    ("glass-green", "design/icon-exploration/2026-11-03-green-grove/B-glass-sculpted-green.png", 0.12, 0),
    ("muted-green", "design/icon-exploration/2026-11-03-green-grove/A2-muted-green.png", 0.124, 18.0 / 896),
    ("folded-grove", "design/icon-exploration/2026-11-05-materials/folded-single-tree.png", 0.12, 0),
    ("sculpted-grove", "design/icon-exploration/2026-11-05-materials/sculpted-single-tree.png", 0.12, 0),
    ("spring", "design/icon-exploration/2026-11-05-seasons/spring.png", 0.12, 0),
    ("summer", "design/icon-exploration/2026-11-05-seasons/summer.png", 0.12, 0),
    ("autumn", "design/icon-exploration/2026-11-05-seasons/autumn.png", 0.12, 0),
    ("winter", "design/icon-exploration/2026-11-05-seasons/winter.png", 0.12, 0)
]
let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("GroveComposer-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temporary) }
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

for (name, path, inset, bleed) in concepts {
    let source = NSImage(contentsOf: root.appendingPathComponent(path))!
        .cgImage(forProposedRect: nil, context: nil, hints: nil)!
    let crop = CGRect(x: CGFloat(source.width) * inset, y: CGFloat(source.height) * inset,
        width: CGFloat(source.width) * (1 - inset * 2), height: CGFloat(source.height) * (1 - inset * 2))
    let artwork = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    artwork.interpolationQuality = .high
    // Full-bleed input: Composer supplies the corners, avoiding double masks.
    artwork.draw(source.cropping(to: crop)!, in: CGRect(x: 0, y: 0, width: 1024, height: 1024)
        .insetBy(dx: -1024 * bleed, dy: -1024 * bleed))
    let document = temporary.appendingPathComponent(name + ".icon")
    try FileManager.default.copyItem(at: root.appendingPathComponent("design/icon-composer/Grove.icon"), to: document)
    try NSBitmapImageRep(cgImage: artwork.makeImage()!).representation(using: .png, properties: [:])!
        .write(to: document.appendingPathComponent("Assets/Artwork.png"))

    let preview = temporary.appendingPathComponent(name + ".png")
    let process = Process()
    process.executableURL = tool
    process.arguments = [document.path, "--export-image", "--output-file", preview.path,
        "--platform", "macOS", "--rendition", "Default", "--width", "1024", "--height", "1024",
        "--scale", "1", "--design-generation", "26"]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0, let icon = NSImage(contentsOf: preview) else {
        fatalError("Icon Composer export failed for \(name)")
    }

    // ictool's macOS preview fills its canvas. Add only transparent padding;
    // 824/1024 matches the observed default icon's 412/512 width on Tahoe.
    // Keep the native exported rim intact rather than clipping it again.
    let pixels = 256 // 128 pt Dock content at Retina scale.
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    let margin = CGFloat(pixels) * 100 / 1024
    icon.draw(in: NSRect(x: margin, y: margin,
        width: CGFloat(pixels) - margin * 2, height: CGFloat(pixels) - margin * 2))
    NSGraphicsContext.restoreGraphicsState()
    bitmap.size = NSSize(width: 128, height: 128)
    guard let center = bitmap.colorAt(x: pixels / 2, y: pixels / 2), center.alphaComponent > 0.99 else {
        fatalError("Incomplete icon for \(name)")
    }
    // AppKit decodes JPEG 2000 natively, including its alpha channel. A single
    // 256 px lossy rendition avoids shipping six oversized uncompressed copies.
    try bitmap.representation(using: .jpeg2000, properties: [.compressionFactor: 0.7])!
        .write(to: destination.appendingPathComponent(name + ".jp2"))
    let legacyTIFF = destination.appendingPathComponent(name + ".tiff")
    if FileManager.default.fileExists(atPath: legacyTIFF.path) {
        try FileManager.default.removeItem(at: legacyTIFF)
    }
    print("Rendered compact Composer icon: \(name)")
}

if requestedDestination.pathExtension == "bundle" {
    // Full-resolution sources stay in the repository and SwiftPM development
    // bundle. Packaged apps use Composer variants and the main ICNS exclusively.
    let originals = destination.deletingLastPathComponent().appendingPathComponent("AppIcons")
    if FileManager.default.fileExists(atPath: originals.path) {
        try FileManager.default.removeItem(at: originals)
    }
}
