import AppKit
import CoreGraphics
import Foundation

// Preserve the selected AI artwork; only apply the legacy macOS tile mask and padding.
let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources/GroveIcon.png")
let sourceURL = URL(fileURLWithPath: "Resources/GroveIcon-source.png")
guard let source = NSImage(contentsOf: sourceURL),
      let sourceImage = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("Unable to read icon artwork: \(sourceURL.path)")
}
let size = 1024
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: 0, space: colorSpace,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.interpolationQuality = .high
let tile = CGRect(x: 64, y: 64, width: 896, height: 896)
context.addPath(CGPath(roundedRect: tile, cornerWidth: 196, cornerHeight: 196, transform: nil))
context.clip()
context.draw(sourceImage, in: tile)
let representation = NSBitmapImageRep(cgImage: context.makeImage()!)
try representation.representation(using: .png, properties: [:])!.write(to: output)
