import Foundation
import CoreServices
import Darwin

// Watch only explicitly registered repositories, their worktrees and Git metadata.
@MainActor final class RepositoryChangeMonitor {
    private var stream: FSEventStreamRef?
    private var roots: [String] = []
    var onChange: (([String]) -> Void)?

    func watch(_ paths: [String]) {
        let paths = Array(Set(paths.map { canonicalFilesystemPath($0) })).sorted()
        guard paths != roots else { return }
        stop()
        roots = paths
        guard !paths.isEmpty else { return }
        var context = FSEventStreamContext(version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let flags = kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot
        stream = FSEventStreamCreate(nil, { _, info, count, eventPaths, eventFlags, _ in
            guard let info else { return }
            let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
            // The stream runs on the main queue, as does its owner.
            MainActor.assumeIsolated {
                let monitor = Unmanaged<RepositoryChangeMonitor>.fromOpaque(info).takeUnretainedValue()
                let rescanFlags = kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped |
                    kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagRootChanged
                let needsRescan = (0..<count).contains { eventFlags[$0] & FSEventStreamEventFlags(rescanFlags) != 0 }
                monitor.onChange?(needsRescan ? monitor.roots : paths)
            }
        }, &context, paths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.2, FSEventStreamCreateFlags(flags))
        if let stream {
            FSEventStreamSetDispatchQueue(stream, .main)
            if !FSEventStreamStart(stream) { stop() }
        }
    }

    private func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}

func pathIsInside(_ path: String, root: String) -> Bool {
    path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
}

// Linked worktrees use a .git file pointing to metadata outside their checkout.
func gitMetadataRoot(in checkout: String) -> String {
    let marker = URL(fileURLWithPath: checkout).appendingPathComponent(".git")
    guard let text = try? String(contentsOf: marker, encoding: .utf8), text.hasPrefix("gitdir: ") else {
        return canonicalFilesystemPath(marker.path)
    }
    let path = String(text.dropFirst(8)).trimmingCharacters(in: .whitespacesAndNewlines)
    let directory = URL(fileURLWithPath: path, isDirectory: true, relativeTo: URL(fileURLWithPath: checkout, isDirectory: true)).standardizedFileURL
    if let common = try? String(contentsOf: directory.appendingPathComponent("commondir"), encoding: .utf8) {
        return canonicalFilesystemPath(URL(fileURLWithPath: common.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: directory).standardizedFileURL.path)
    }
    return canonicalFilesystemPath(directory.path)
}

// Foundation may shorten /private/var to /var; Git and FSEvents use realpath.
// Resolve the nearest surviving ancestor for deletion/atomic-save events.
func canonicalFilesystemPath(_ path: String) -> String {
    let url = URL(fileURLWithPath: path).standardizedFileURL
    if let resolved = realpath(url.path, nil) {
        defer { free(resolved) }
        return String(cString: resolved)
    }
    let parent = url.deletingLastPathComponent()
    guard parent.path != url.path else { return url.path }
    let root = canonicalFilesystemPath(parent.path)
    return (root == "/" ? root : root + "/") + url.lastPathComponent
}
