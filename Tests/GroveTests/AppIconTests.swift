import AppKit
import XCTest
@testable import Grove

final class AppIconTests: XCTestCase {
    @MainActor func testSelectionRestoresOnRelaunchAndRejectsMissingArtwork() throws {
        let suite = "GroveIconTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let image = NSImage(size: NSSize(width: 32, height: 32))
        var applied = 0
        let controller = AppIconController(defaults: defaults, loadImage: { $0 == .winter ? nil : image },
                                           applyImage: { _ in applied += 1 })
        XCTAssertEqual(controller.selected, .vectorGreen)
        controller.select(.glassGreen)
        XCTAssertEqual(AppIcon.saved(in: defaults), .glassGreen)
        let relaunched = AppIconController(defaults: defaults, loadImage: { _ in image },
                                           applyImage: { _ in applied += 1 })
        relaunched.restore()
        XCTAssertEqual(relaunched.selected, .glassGreen)
        XCTAssertEqual(applied, 2)
        controller.select(.winter)
        XCTAssertEqual(controller.selected, .glassGreen)
        XCTAssertEqual(AppIcon.saved(in: defaults), .glassGreen)
        XCTAssertEqual(applied, 2)
        XCTAssertNotNil(controller.errorMessage)
        controller.select(.vectorGreen)
        XCTAssertEqual(AppIcon.saved(in: defaults), .vectorGreen)
        XCTAssertNil(controller.errorMessage)
        defaults.set("future-icon", forKey: AppIcon.preferenceKey)
        XCTAssertEqual(AppIcon.saved(in: defaults), .vectorGreen)
    }

    func testEveryBundledIconHasTransparentPaddingAndConsistentResolution() throws {
        for icon in AppIcon.allCases {
            let image = try XCTUnwrap(icon.image, icon.rawValue)
            let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
            XCTAssertEqual(cgImage.width, 1024, icon.rawValue)
            XCTAssertEqual(cgImage.height, 1024, icon.rawValue)
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x: 0, y: 0)).alphaComponent, 0.01, icon.rawValue)
            XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: 512, y: 512)).alphaComponent, 0.99, icon.rawValue)
        }
    }
}
