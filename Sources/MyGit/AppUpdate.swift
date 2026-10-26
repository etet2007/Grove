import AppKit
import CryptoKit
import Security
import SwiftUI

struct AppUpdateManifest: Codable, Equatable {
    let version: String
    let build: Int
    let sha256: String
    let notes: String

    func validate() throws {
        guard !version.isEmpty, build > 0, sha256.count == 64,
              sha256.allSatisfy({ $0.isHexDigit && $0.isASCII }) else {
            throw UpdateFailure("更新清单无效。")
        }
    }
}

struct UpdateFailure: LocalizedError {
    let key: String
    init(_ key: String) { self.key = key }
    var errorDescription: String? { AppLocalization.text(key) }
}

struct PreparedAppUpdate {
    let directory: URL
    let manifest: AppUpdateManifest
    var archive: URL { directory.appendingPathComponent("MyGit.zip") }
}

enum AppUpdateService {
    // A fresh shallow clone tolerates rewritten release history. Never reuse a user's checkout.
    static func check(repository: String, branch: String, currentBuild: Int) throws -> PreparedAppUpdate? {
        let repository = repository.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repository.isEmpty, !repository.hasPrefix("-"),
              repository.hasPrefix("https://") || repository.hasPrefix("ssh://") ||
              repository.range(of: #"^[A-Za-z0-9._-]+@[A-Za-z0-9.-]+:.+$"#, options: .regularExpression) != nil ||
              repository.hasPrefix("/") || repository.hasPrefix("file://"),
              !branch.isEmpty, !branch.hasPrefix("-") else { throw UpdateFailure("请输入有效的 Git 仓库地址和分支。") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyGitUpdate-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        var keep = false
        defer { if !keep { try? FileManager.default.removeItem(at: root) } }
        let checkout = root.appendingPathComponent("repository")
        let output = try CommitProcess.run("/usr/bin/git", ["-c", "core.hooksPath=/dev/null",
            "-c", "protocol.allow=never", "-c", "protocol.https.allow=always", "-c", "protocol.ssh.allow=always",
            "-c", "protocol.file.allow=always", "clone", "--depth=1", "--single-branch", "--no-tags", "--no-checkout",
            "--branch", branch, "--", repository, checkout.path], in: root.path,
            environment: ["GIT_TERMINAL_PROMPT": "0", "GIT_SSH_COMMAND": "/usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=15"], timeout: 180)
        guard output.status == 0 else { throw UpdateFailure("无法读取更新仓库，请检查地址、分支及本机 Git 认证。") }
        let data = try CommitProcess.git(["show", "HEAD:latest.json"], in: checkout.path)
        guard data.count <= 64_000 else { throw UpdateFailure("更新清单无效。") }
        let manifest = try JSONDecoder().decode(AppUpdateManifest.self, from: data)
        try manifest.validate()
        guard manifest.build > currentBuild else { return nil }
        // Both files come from this clone's immutable HEAD, even if the remote changes now.
        let archive = try CommitProcess.git(["show", "HEAD:MyGit.zip"], in: checkout.path)
        try verifyArchive(archive, manifest: manifest)
        try archive.write(to: root.appendingPathComponent("MyGit.zip"), options: .atomic)
        try FileManager.default.removeItem(at: checkout)
        keep = true
        return PreparedAppUpdate(directory: root, manifest: manifest)
    }

    static func verifyArchive(_ data: Data, manifest: AppUpdateManifest) throws {
        try manifest.validate()
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard hash == manifest.sha256.lowercased() else { throw UpdateFailure("安装包校验失败，请重新检查更新。") }
    }

    static func prepareInstallation(_ update: PreparedAppUpdate, currentApp: URL) throws -> URL {
        guard currentApp.pathExtension == "app", FileManager.default.isWritableFile(atPath: currentApp.deletingLastPathComponent().path),
              !currentApp.path.hasPrefix("/Volumes/") else { throw UpdateFailure("请先将 MyGit 放到可写的应用目录，再更新。") }
        try verifyArchive(Data(contentsOf: update.archive), manifest: update.manifest)
        let extracted = update.directory.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
        // Validate paths before extraction; do not allow an archive to escape its staging directory.
        let types = try CommitProcess.run("/usr/bin/zipinfo", ["-l", update.archive.path], in: update.directory.path)
        guard types.status == 0, !String(decoding: types.data, as: UTF8.self).split(separator: "\n").contains(where: { $0.hasPrefix("l") }) else {
            throw UpdateFailure("安装包格式无效。")
        }
        let listing = try CommitProcess.run("/usr/bin/unzip", ["-Z1", update.archive.path], in: update.directory.path)
        let entries = String(decoding: listing.data, as: UTF8.self).split(separator: "\n")
        guard listing.status == 0, !entries.isEmpty, entries.allSatisfy({ entry in
            !entry.hasPrefix("/") && !entry.split(separator: "/").contains("..") &&
            (entry.hasPrefix("MyGit.app/") || entry.hasPrefix("__MACOSX/"))
        }) else { throw UpdateFailure("安装包格式无效。") }
        // Preserve bundle metadata; this minimal update format rejects symlinks.
        let output = try CommitProcess.run("/usr/bin/ditto", ["-x", "-k", update.archive.path, extracted.path], in: update.directory.path)
        guard output.status == 0 else { throw UpdateFailure("无法解压安装包。") }
        let app = extracted.appendingPathComponent("MyGit.app")
        guard let bundle = Bundle(url: app), bundle.bundleIdentifier == Bundle(url: currentApp)?.bundleIdentifier,
              bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String == String(update.manifest.build),
              bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == update.manifest.version else {
            throw UpdateFailure("安装包版本或应用标识不匹配。")
        }
        try verifySignature(app: app, currentApp: currentApp)
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        let binary = app.appendingPathComponent("Contents/MacOS/MyGit")
        let architectureCheck = try CommitProcess.run("/usr/bin/lipo", [binary.path, "-archs"], in: update.directory.path)
        let minimum = (bundle.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String ?? "14.0")
            .split(separator: ".").compactMap { Int($0) }
        let supported = String(decoding: architectureCheck.data, as: UTF8.self).split(whereSeparator: { $0.isWhitespace })
        let compatible = supported.contains { $0 == architecture || (architecture == "arm64" && $0 == "arm64e") || (architecture == "x86_64" && $0 == "x86_64h") }
        guard architectureCheck.status == 0, compatible, !minimum.isEmpty,
              ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: minimum[0],
                minorVersion: minimum.count > 1 ? minimum[1] : 0, patchVersion: minimum.count > 2 ? minimum[2] : 0)) else {
            throw UpdateFailure("新版应用不支持当前 Mac 或 macOS 版本。")
        }
        return app
    }

    static func verifySignature(app: URL, currentApp: URL) throws {
        var current: SecStaticCode?, candidate: SecStaticCode?, requirement: SecRequirement?
        let flags = SecCSFlags(rawValue: 0)
        guard SecStaticCodeCreateWithPath(currentApp as CFURL, flags, &current) == errSecSuccess,
              let current, SecCodeCopyDesignatedRequirement(current, flags, &requirement) == errSecSuccess,
              let requirement,
              SecStaticCodeCreateWithPath(app as CFURL, flags, &candidate) == errSecSuccess, let candidate,
              SecStaticCodeCheckValidity(candidate, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate), requirement) == errSecSuccess else {
            throw UpdateFailure("新版应用签名与当前应用不匹配，无法更新。")
        }
    }
}

@MainActor final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()
    @Published var busy = false
    @Published var message = ""
    @Published var available: PreparedAppUpdate?
    static let repositoryKey = "updateRepository"
    static let branchKey = "updateBranch"
    static var currentBuild: Int { Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0 }
    static var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development" }

    init() {
        let result = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs/MyGit/update-result")
        if let value = try? String(contentsOf: result) {
            if value.trimmingCharacters(in: .whitespacesAndNewlines) == "failure" {
                message = AppLocalization.text("上次更新未完成，已尝试保留或恢复旧版。详情见 ~/Library/Logs/MyGit/update.log。")
            }
            try? FileManager.default.removeItem(at: result)
        }
    }

    func clear() {
        if let available { try? FileManager.default.removeItem(at: available.directory) }
        available = nil; message = ""
    }

    func check(repository: String, branch: String) {
        guard !busy else { return }
        clear(); busy = true; message = AppLocalization.text("正在读取最新版本…")
        Task {
            do {
                let build = Self.currentBuild
                available = try await Task.detached { try AppUpdateService.check(repository: repository, branch: branch, currentBuild: build) }.value
                message = AppLocalization.text(available == nil ? "当前已是最新版本。" : "新版已准备好，可更新并重启。")
            } catch { message = error.localizedDescription }
            busy = false
        }
    }

    func install() {
        guard !busy, let update = available else { return }
        guard CheckoutOperationLock.beginAppUpdate() else { message = AppLocalization.text("请等待 Git 操作完成后再更新。"); return }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "dev.stephenlau.mygit").count <= 1 else {
            CheckoutOperationLock.endAppUpdate()
            message = AppLocalization.text("请先退出其他 MyGit 实例。"); return
        }
        busy = true; message = AppLocalization.text("正在校验并准备安装…")
        Task {
            do {
                let current = Bundle.main.bundleURL.resolvingSymlinksInPath()
                let app = try await Task.detached { try AppUpdateService.prepareInstallation(update, currentApp: current) }.value
                guard let source = Bundle.main.url(forResource: "install-update", withExtension: "sh") else { throw UpdateFailure("找不到更新安装程序。") }
                let helper = update.directory.appendingPathComponent("install-update.sh")
                try FileManager.default.copyItem(at: source, to: helper)
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = [helper.path, String(ProcessInfo.processInfo.processIdentifier), app.path, current.path, update.directory.path,
                    NSHomeDirectory() + "/Library/Logs/MyGit"]
                process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
                try process.run()
                NSApp.terminate(nil)
                // If termination is cancelled, stop the waiting helper before permitting another attempt.
                process.terminate()
                available = nil
                message = AppLocalization.text("退出被取消，请退出应用完成更新，或稍后重新检查。")
            } catch { message = error.localizedDescription }
            CheckoutOperationLock.endAppUpdate(); busy = false
        }
    }
}
