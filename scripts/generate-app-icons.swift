import AppKit
import Foundation

// Package the existing concepts without changing their artwork. All choices use
// the same 1024 px canvas, 896 px tile and macOS corner/padding treatment.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let output = root.appendingPathComponent("Sources/Grove/Resources/AppIcons")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let concepts: [(String, String, CGFloat)] = [
    ("glass-green", "design/icon-exploration/2026-11-03-green-grove/B-glass-sculpted-green.png", 0.12),
    ("muted-green", "design/icon-exploration/2026-11-03-green-grove/A2-muted-green.png", 0.124),
    ("folded-grove", "design/icon-exploration/2026-11-05-materials/folded-single-tree.png", 0.12),
    ("sculpted-grove", "design/icon-exploration/2026-11-05-materials/sculpted-single-tree.png", 0.12),
    ("spring", "design/icon-exploration/2026-11-05-seasons/spring.png", 0.12),
    ("summer", "design/icon-exploration/2026-11-05-seasons/summer.png", 0.12),
    ("autumn", "design/icon-exploration/2026-11-05-seasons/autumn.png", 0.12),
    ("winter", "design/icon-exploration/2026-11-05-seasons/winter.png", 0.12)
]
let original = try Data(contentsOf: root.appendingPathComponent("Resources/GroveIcon.png"))
try original.write(to: output.appendingPathComponent("vector-green.png"))

for (name, path, inset) in concepts {
    let image = NSImage(contentsOf: root.appendingPathComponent(path))!
    let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    let crop = CGRect(x: CGFloat(source.width) * inset, y: CGFloat(source.height) * inset,
                      width: CGFloat(source.width) * (1 - inset * 2), height: CGFloat(source.height) * (1 - inset * 2))
    let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high
    let tile = CGRect(x: 64, y: 64, width: 896, height: 896)
    context.addPath(CGPath(roundedRect: tile, cornerWidth: 196, cornerHeight: 196, transform: nil))
    context.clip()
    // The muted concept has larger baked corners; bleed its artwork slightly
    // past the mask so its off-white presentation surround cannot form a rim.
    let drawingRect = name == "muted-green" ? tile.insetBy(dx: -18, dy: -18) : tile
    context.draw(source.cropping(to: crop)!, in: drawingRect)
    let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
}
