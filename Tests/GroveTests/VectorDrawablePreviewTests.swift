import XCTest
@testable import Grove

final class VectorDrawablePreviewTests: XCTestCase {
    private func vector(_ body: String, attributes: String = "") -> Data {
        Data("""
        <vector xmlns:android="http://schemas.android.com/apk/res/android" xmlns:aapt="http://schemas.android.com/aapt"
        android:width="24dp" android:height="24dp" android:viewportWidth="24" android:viewportHeight="24" \(attributes)>\(body)</vector>
        """.utf8)
    }

    private func svg(_ data: Data) throws -> String {
        try XCTUnwrap(VectorDrawablePreview.convert(data)).get()
    }

    func testPathColorsAlphaAndEvenOdd() throws {
        let output = try svg(vector("""
        <path android:pathData="M0,0h24v24H0z" android:fillColor="#80FF0000" android:fillAlpha="0.5"
        android:fillType="evenOdd" android:strokeColor="#F00" android:strokeWidth="2" android:strokeLineCap="round"/>
        """))
        XCTAssertTrue(output.contains("fill=\"#FF0000\""))
        XCTAssertTrue(output.contains("fill-opacity=\"0.25098039215686274\""))
        XCTAssertTrue(output.contains("fill-rule=\"evenodd\""))
        XCTAssertTrue(output.contains("stroke-linecap=\"round\""))
        XCTAssertTrue(output.contains("viewBox=\"0 0 24.0 24.0\""))
    }

    func testGroupTransformsAndScopedClipping() throws {
        let output = try svg(vector("""
        <group android:pivotX="12" android:pivotY="12" android:rotation="90" android:translateX="2">
        <clip-path android:pathData="M0 0h12v12z"/>
        <path android:pathData="M0 0h24v24z" android:fillColor="#FFF"/>
        </group><path android:pathData="M0 0h2v2z" android:fillColor="#000"/>
        """))
        XCTAssertTrue(output.contains("translate(14.0 12.0) rotate(90.0) scale(1.0 1.0) translate(-12.0 -12.0)"))
        XCTAssertTrue(output.contains("clip-path=\"url(#clip1)\""))
        XCTAssertTrue(output.contains("</g></g><defs>"), "Clipping must end before the next sibling path")
    }

    func testAaptGradientAndARGBStops() throws {
        let output = try svg(vector("""
        <path android:pathData="M0 0h24v24z" android:fillAlpha="0.6">
        <aapt:attr name="android:fillColor"><gradient android:startX="0" android:endX="24" android:tileMode="mirror">
        <item android:offset="0" android:color="#00FF0000"/><item android:offset="1" android:color="#FF0000FF"/>
        </gradient></aapt:attr></path>
        """))
        XCTAssertTrue(output.contains("linearGradient"))
        XCTAssertTrue(output.contains("spreadMethod=\"reflect\""))
        XCTAssertTrue(output.contains("stop-opacity=\"0.0\""))
        XCTAssertTrue(output.contains("fill-opacity=\"0.6\""))
    }

    func testUnsupportedAndMalformedVectorsFailWhileOrdinaryXMLIsIgnored() throws {
        XCTAssertNil(VectorDrawablePreview.convert(Data("<resources><color name=\"a\">#FFF</color></resources>".utf8)))
        for data in [
            vector("<path android:pathData=\"M0 0h1\" android:fillColor=\"@color/icon\"/>"),
            vector("<path android:pathData=\"M0 0h1\" android:trimPathEnd=\"0.5\"/>"),
            vector("", attributes: "android:tint=\"?attr/colorControlNormal\""),
            Data("<vector xmlns:android=\"http://schemas.android.com/apk/res/android\"".utf8),
            Data("<!DOCTYPE vector [<!ENTITY x SYSTEM 'file:///etc/passwd'>]><vector>&x;</vector>".utf8)
        ] {
            XCTAssertThrowsError(try svg(data))
        }
    }

    func testGitPreviewReadsVectorVersionsAndLeavesOtherXMLAsText() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GroveVector-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try GitClient.text(["init", "-b", "main"], in: root.path)
        _ = try GitClient.text(["config", "user.name", "Test"], in: root.path)
        _ = try GitClient.text(["config", "user.email", "test@example.invalid"], in: root.path)
        let url = root.appendingPathComponent("icon.xml")
        let original = vector("<path android:pathData=\"M0 0h24v24z\" android:fillColor=\"#F00\"/>")
        let staged = vector("<path android:pathData=\"M0 0h24v24z\" android:fillColor=\"#0F0\"/>")
        let working = vector("<path android:pathData=\"M0 0h24v24z\" android:fillColor=\"#00F\"/>")
        try original.write(to: url)
        _ = try GitClient.text(["add", "."], in: root.path)
        _ = try GitClient.text(["commit", "-m", "vector"], in: root.path)
        try staged.write(to: url)
        _ = try GitClient.text(["add", "."], in: root.path)
        try working.write(to: url)
        let file = try XCTUnwrap(GitClient.changedFiles(in: root.path, repositoryID: UUID()).first)
        for (mode, old, new) in [(DiffMode.unstaged, staged, working), (.staged, original, staged), (.all, original, working)] {
            let preview = try XCTUnwrap(GitClient.imagePreview(for: file, in: root.path, mode: mode))
            XCTAssertEqual(preview.old.svgData, Data(try svg(old).utf8))
            XCTAssertEqual(preview.new.svgData, Data(try svg(new).utf8))
        }
        try FileManager.default.removeItem(at: url)
        let deleted = try XCTUnwrap(GitClient.imagePreview(for: file, in: root.path, mode: .unstaged))
        XCTAssertNotNil(deleted.old.svgData)
        XCTAssertNil(deleted.new.data)
        let normal = ChangedFile(repositoryID: UUID(), path: "layout.xml", indexStatus: "?", worktreeStatus: "?", isUntracked: true)
        try Data("<LinearLayout/>".utf8).write(to: root.appendingPathComponent(normal.path))
        XCTAssertNil(GitClient.imagePreview(for: normal, in: root.path, mode: .unstaged))
        try working.write(to: root.appendingPathComponent(normal.path))
        XCTAssertNotNil(GitClient.imagePreview(for: normal, in: root.path, mode: .unstaged)?.new.svgData)
    }

    func testSVGIsEmbeddedAsAnImageWithIsolatedPolicy() {
        let html = SVGPreviewView.html(Data("<svg><script>alert(1)</script></svg>".utf8))
        XCTAssertTrue(html.contains("default-src 'none'"))
        XCTAssertTrue(html.contains("script-src 'none'"))
        XCTAssertTrue(html.contains("data:image/svg+xml;base64,"))
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertFalse(html.contains("<object"))
    }
}
