import AppKit
import SwiftUI

enum FinderAction {
    // Historical and deleted files may be absent in the current checkout.
    // Open the closest existing parent in that case.
    static func existingURL(for path: String) -> URL? {
        var url = URL(fileURLWithPath: path).standardizedFileURL
        while !FileManager.default.fileExists(atPath: url.path) {
            let parent = url.deletingLastPathComponent()
            guard parent != url else { return nil }
            url = parent
        }
        return url
    }

    static func open(_ path: String) {
        guard let url = existingURL(for: path) else { return }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }
        if isDirectory.boolValue {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}

struct FinderMenuItem: View {
    let path: String?

    var body: some View {
        Button {
            if let path { FinderAction.open(path) }
        } label: {
            Label("在 Finder 中打开", systemImage: "folder")
        }
        .disabled(path == nil)
    }
}

extension View {
    func finderContextMenu(path: String?) -> some View {
        contextMenu { FinderMenuItem(path: path) }
    }

    func fileContextMenu(path: String?, filePath: String) -> some View {
        contextMenu {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString((filePath as NSString).lastPathComponent, forType: .string)
            } label: {
                Label("复制文件名", systemImage: "doc.on.doc")
            }
            Divider()
            FinderMenuItem(path: path)
        }
    }
}
