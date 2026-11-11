import AppKit
import Foundation

// Exercise Bundle's actual lookup, not merely filesystem existence: Xcode's
// resource bundles store assets below Contents/Resources, not the bundle root.
do {
    let application = URL(fileURLWithPath: CommandLine.arguments[1])
    let bundleURL = application.appendingPathComponent("Contents/Resources/Grove_Grove.bundle")
    guard let bundle = Bundle(url: bundleURL) else {
        throw NSError(domain: "GroveIconPackaging", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing Grove resource bundle"])
    }
    let names = ["glass-green", "muted-green", "folded-grove", "sculpted-grove", "spring", "summer", "autumn", "winter"]
    var totalBytes = 0
    for name in names {
        guard let url = bundle.url(forResource: name, withExtension: "jp2", subdirectory: "SystemAppIcons"),
              let image = NSImage(contentsOf: url),
              let bitmap = image.representations.first as? NSBitmapImageRep,
              bitmap.pixelsWide == 256, bitmap.pixelsHigh == 256, bitmap.hasAlpha,
              let corner = bitmap.colorAt(x: 0, y: 0), corner.alphaComponent < 0.01,
              let center = bitmap.colorAt(x: 128, y: 128), center.alphaComponent > 0.99 else {
            throw NSError(domain: "GroveIconPackaging", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Bundle cannot load transparent 256 px Composer icon for \(name)"])
        }
        totalBytes += try Data(contentsOf: url).count
        print("Verified Bundle icon: \(name)")
    }
    guard totalBytes < 512 * 1024,
          bundle.url(forResource: "glass-green", withExtension: "png", subdirectory: "AppIcons") == nil else {
        throw NSError(domain: "GroveIconPackaging", code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Packaged icons exceed size budget or include duplicate source artwork"])
    }
    print("Packaged alternate icons: \(totalBytes) bytes")
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
}
