import Foundation

struct ImageDiffSide {
    let data: Data?
    let byteCount: Int?
    let message: String?
}

struct ImageDiffPreview {
    let old: ImageDiffSide
    let new: ImageDiffSide
}

enum GitError: LocalizedError {
    case command(String)
    case invalidRepository(String)

    var errorDescription: String? {
        switch self {
        case .command(let message), .invalidRepository(let message): message
        }
    }
}

// One read operation owns its child processes and command counts.
final class GitReadSession: @unchecked Sendable {
    private let lock = NSLock()
    private var commands: [String: Int] = [:]
    private var processes: [ObjectIdentifier: Process] = [:]
    private var cancelled = false

    func start(_ process: Process, command: String) throws {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled else { throw CancellationError() }
        try process.run()
        processes[ObjectIdentifier(process)] = process
        commands[command, default: 0] += 1
    }

    func finish(_ process: Process) {
        lock.lock(); defer { lock.unlock() }
        processes.removeValue(forKey: ObjectIdentifier(process))
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let running = Array(processes.values)
        lock.unlock()
        for process in running where process.isRunning { process.terminate() }
    }

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    var counts: [String: Int] {
        lock.lock(); defer { lock.unlock() }
        return commands
    }
}

struct GitClient {
    @TaskLocal static var readSession: GitReadSession?


    private static let gitURL = URL(fileURLWithPath: "/usr/bin/git")
    private static let imageExtensions: Set<String> = ["webp", "png", "jpg", "jpeg", "gif", "heic", "heif", "tif", "tiff", "bmp", "avif"]
    private static let imagePreviewLimit = 20_000_000

    static func run(_ args: [String], in directory: String) throws -> Data {
        try Task.checkCancellation()
        let process = Process()
        process.executableURL = gitURL
        process.arguments = ["-C", directory] + args
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            if let readSession { try readSession.start(process, command: args.first ?? "") }
            else { try process.run() }
        }
        catch { throw GitError.command(error.localizedDescription) }
        defer { readSession?.finish(process) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if readSession?.isCancelled == true { throw CancellationError() }
        try Task.checkCancellation()
        guard process.terminationStatus == 0 else {
            throw GitError.command(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return data
    }

    static func text(_ args: [String], in directory: String) throws -> String {
        String(decoding: try run(args, in: directory), as: UTF8.self)
    }

    static func canonicalRepository(at path: String) throws -> String {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
        let root = try text(["rev-parse", "--show-toplevel"], in: resolved).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !root.isEmpty else { throw GitError.invalidRepository(AppLocalization.text("不是有效的 Git 仓库：%@", path)) }
        return URL(fileURLWithPath: root).resolvingSymlinksInPath().standardizedFileURL.path
    }

    static func localBranches(in checkout: String) throws -> [LocalBranch] {
        let trees = try worktrees(in: checkout)
        let refs = try text(["for-each-ref", "--sort=refname", "--format=%(refname)", "refs/heads/"], in: checkout)
        return refs.split(whereSeparator: \.isNewline).map { ref in
            let name = String(ref.dropFirst("refs/heads/".count))
            return LocalBranch(name: name, checkoutPath: trees.first { $0.branch == name }?.path)
        }
    }

    static func switchBranch(_ branch: String, in checkout: String) throws {
        // Only existing local branches; never guess a remote, create a branch,
        // discard changes, or override another worktree's branch ownership.
        _ = try text(["show-ref", "--verify", "--", "refs/heads/" + branch], in: checkout)
        _ = try text(["switch", "--no-guess", "--no-recurse-submodules", "--", branch], in: checkout)
    }

    static func mergeRequestURL(in worktree: String, branch: String) -> URL? {
        let remotes = ((try? text(["remote"], in: worktree)) ?? "")
            .split(whereSeparator: \.isNewline).map(String.init)
        let upstream = try? text(["config", "--get", "branch.\(branch).remote"], in: worktree)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let remote = [upstream, "origin", remotes.count == 1 ? remotes.first : nil]
            .compactMap { $0 }
            .first { $0 != "." && remotes.contains($0) }
        guard let remote,
              let remoteURL = try? text(["remote", "get-url", remote], in: worktree)
                .trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return mergeRequestURL(remoteURL: remoteURL, branch: branch)
    }

    static func mergeRequestURL(remoteURL: String, branch: String) -> URL? {
        let remoteURL = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let components: URLComponents
        if let parsed = URLComponents(string: remoteURL),
           let scheme = parsed.scheme?.lowercased(), ["https", "http", "ssh"].contains(scheme) {
            components = parsed
        } else if let at = remoteURL.firstIndex(of: "@"),
                  let colon = remoteURL[remoteURL.index(after: at)...].firstIndex(of: ":") {
            let host = String(remoteURL[remoteURL.index(after: at)..<colon])
            let path = String(remoteURL[remoteURL.index(after: colon)...])
            guard !host.isEmpty, !path.isEmpty else { return nil }
            var parsed = URLComponents()
            parsed.scheme = "http"
            parsed.host = host
            parsed.path = "/" + path
            components = parsed
        } else {
            return nil
        }
        guard let host = components.host, !host.isEmpty else { return nil }
        var web = components
        if web.scheme == "ssh" || (web.scheme == "https" && web.port == 443) {
            web.port = nil
        }
        web.scheme = "http"
        web.user = nil
        web.password = nil
        web.fragment = nil
        let projectPath = web.path.hasSuffix(".git") ? String(web.path.dropLast(4)) : web.path
        guard projectPath.split(separator: "/").count >= 2 else { return nil }
        web.path = "/" + projectPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            + "/-/merge_requests/new"
        web.queryItems = [URLQueryItem(name: "merge_request[source_branch]", value: branch)]
        return web.url
    }

    static func worktrees(in repository: String) throws -> [Worktree] {
        let output = try text(["worktree", "list", "--porcelain"], in: repository)
        var result: [Worktree] = []
        var path: String?
        var branch: String?
        var head = ""
        var detached = false
        func finish() {
            guard let path else { return }
            result.append(Worktree(path: path, branch: branch, head: head,
                                   isPrimary: result.isEmpty, isDetached: detached))
        }
        for line in output.components(separatedBy: "\n") {
            if line.isEmpty {
                finish()
                path = nil; branch = nil; head = ""; detached = false
            } else if line.hasPrefix("worktree ") {
                path = String(line.dropFirst("worktree ".count))
            } else if line.hasPrefix("HEAD ") {
                head = String(line.dropFirst(5))
            } else if line.hasPrefix("branch refs/heads/") {
                branch = String(line.dropFirst("branch refs/heads/".count))
            } else if line == "detached" {
                detached = true
            }
        }
        if path != nil { finish() }
        return result.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func changedFiles(in worktree: String, repositoryID: UUID) throws -> [ChangedFile] {
        let data = try run(["status", "--porcelain=v1", "-z", "--untracked-files=all"], in: worktree)
        let bytes = [UInt8](data)
        var index = 0
        var files: [ChangedFile] = []
        while index + 3 <= bytes.count {
            let indexStatus = Character(UnicodeScalar(bytes[index]))
            let worktreeStatus = Character(UnicodeScalar(bytes[index + 1]))
            index += 3 // two status bytes and a space
            guard let end = bytes[index...].firstIndex(of: 0) else { break }
            let path = String(decoding: bytes[index..<end], as: UTF8.self)
            index = end + 1
            if indexStatus == "R" || indexStatus == "C" || worktreeStatus == "R" || worktreeStatus == "C" {
                if index < bytes.count, let previousEnd = bytes[index...].firstIndex(of: 0) {
                    index = previousEnd + 1 // destination path is already in `path`
                }
            }
            files.append(ChangedFile(repositoryID: repositoryID, path: path,
                                     indexStatus: indexStatus, worktreeStatus: worktreeStatus,
                                     isUntracked: indexStatus == "?" && worktreeStatus == "?"))
        }
        // Summarize tracked changes in two batched reads, including unborn HEADs.
        // Counts include both staged and unstaged edits, matching the status list.
        let staged = files.contains { !$0.isUntracked && $0.hasStaged }
            ? (try? run(["diff", "--cached", "--numstat", "-z", "--no-ext-diff", "--find-renames"], in: worktree)) ?? Data() : Data()
        let unstaged = files.contains { !$0.isUntracked && $0.hasUnstaged }
            ? (try? run(["diff", "--numstat", "-z", "--no-ext-diff", "--find-renames"], in: worktree)) ?? Data() : Data()
        var stats = parseNumstat(staged)
        for (path, value) in parseNumstat(unstaged) {
            let previous = stats[path]
            stats[path] = FileChangeStats(additions: (previous?.additions ?? 0) + value.additions,
                                          deletions: (previous?.deletions ?? 0) + value.deletions,
                                          isBinary: (previous?.isBinary ?? false) || value.isBinary)
        }
        for index in files.indices {
            if files[index].isUntracked {
                let url = URL(fileURLWithPath: worktree).appendingPathComponent(files[index].path)
                if let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber,
                   size.intValue <= 250_000, let data = try? Data(contentsOf: url) {
                    if !data.contains(0), String(data: data, encoding: .utf8) != nil {
                        let count = data.reduce(0) { $0 + ($1 == 10 ? 1 : 0) } + (data.isEmpty || data.last == 10 ? 0 : 1)
                        files[index].stats = FileChangeStats(additions: count, deletions: 0)
                    } else { files[index].stats = FileChangeStats(additions: 0, deletions: 0, isBinary: true) }
                }
            } else { files[index].stats = stats[files[index].path] }
        }
        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    static func parseNumstat(_ data: Data) -> [String: FileChangeStats] {
        let records = String(decoding: data, as: UTF8.self).components(separatedBy: "\0")
        var result: [String: FileChangeStats] = [:]
        var index = 0
        while index < records.count {
            let record = records[index]
            index += 1
            guard let first = record.firstIndex(of: "\t"),
                  let second = record[record.index(after: first)...].firstIndex(of: "\t") else { continue }
            let added = String(record[..<first])
            let removed = String(record[record.index(after: first)..<second])
            var path = String(record[record.index(after: second)...])
            if path.isEmpty {
                guard index + 1 < records.count else { break }
                path = records[index + 1] // rename: empty path, old path, new path
                index += 2
            }
            result[path] = FileChangeStats(additions: Int(added) ?? 0, deletions: Int(removed) ?? 0,
                                           isBinary: added == "-" || removed == "-")
        }
        return result
    }

    static func diff(for file: ChangedFile, in worktree: String, mode: DiffMode) throws -> String {
        if file.isUntracked {
            if mode == .staged { return AppLocalization.text("未跟踪文件没有已暂存修改。") }
            let url = URL(fileURLWithPath: worktree).appendingPathComponent(file.path)
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            if let size = attributes?[.size] as? NSNumber, size.intValue > 250_000 {
                return AppLocalization.text("Untracked file is too large to preview (%lld bytes).", size.intValue)
            }
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
                return AppLocalization.text("未跟踪文件无法作为 UTF-8 文本预览。")
            }
            var lines = contents.components(separatedBy: "\n")
            if contents.hasSuffix("\n") || contents.isEmpty { lines.removeLast() }
            guard !lines.isEmpty else { return AppLocalization.text("空文件") }
            return "--- /dev/null\n+++ b/\(file.path)\n@@ -0,0 +1,\(lines.count) @@\n"
                + lines.map { "+" + $0 + "\n" }.joined()
                + (contents.hasSuffix("\n") ? "" : "\\ No newline at end of file\n")
        }
        let args: [String]
        switch mode {
        case .unstaged: args = ["diff", "--no-ext-diff", "--no-textconv", "--", ":(literal)" + file.path]
        case .staged: args = ["diff", "--cached", "--no-ext-diff", "--no-textconv", "--", ":(literal)" + file.path]
        case .all: args = ["diff", "HEAD", "--no-ext-diff", "--no-textconv", "--", ":(literal)" + file.path]
        }
        let output = try text(args, in: worktree)
        return output.isEmpty ? AppLocalization.text("这一视图没有可显示的修改。") : output
    }

    static func imagePreview(for file: ChangedFile, in worktree: String, mode: DiffMode) -> ImageDiffPreview? {
        guard imageExtensions.contains(URL(fileURLWithPath: file.path).pathExtension.lowercased()) else { return nil }

        func blob(_ revision: String) -> ImageDiffSide {
            guard let sizeText = try? text(["cat-file", "-s", revision], in: worktree),
                  let size = Int(sizeText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return ImageDiffSide(data: nil, byteCount: nil, message: AppLocalization.text("此版本无文件"))
            }
            guard size <= imagePreviewLimit else {
                return ImageDiffSide(data: nil, byteCount: size, message: AppLocalization.text("图片超过 20 MB，暂不预览"))
            }
            guard let data = try? run(["cat-file", "blob", revision], in: worktree) else {
                return ImageDiffSide(data: nil, byteCount: size, message: AppLocalization.text("无法读取图片"))
            }
            return ImageDiffSide(data: data, byteCount: size, message: nil)
        }

        func workingFile() -> ImageDiffSide {
            let url = URL(fileURLWithPath: worktree).appendingPathComponent(file.path)
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = attributes[.size] as? NSNumber else {
                return ImageDiffSide(data: nil, byteCount: nil, message: AppLocalization.text("此版本无文件"))
            }
            guard size.intValue <= imagePreviewLimit else {
                return ImageDiffSide(data: nil, byteCount: size.intValue, message: AppLocalization.text("图片超过 20 MB，暂不预览"))
            }
            guard let data = try? Data(contentsOf: url) else {
                return ImageDiffSide(data: nil, byteCount: size.intValue, message: AppLocalization.text("无法读取图片"))
            }
            return ImageDiffSide(data: data, byteCount: size.intValue, message: nil)
        }

        if file.isUntracked {
            return ImageDiffPreview(old: ImageDiffSide(data: nil, byteCount: nil, message: AppLocalization.text("此版本无文件")),
                                    new: mode == .staged
                                        ? ImageDiffSide(data: nil, byteCount: nil, message: AppLocalization.text("未跟踪文件没有已暂存修改。"))
                                        : workingFile())
        }
        switch mode {
        case .unstaged: return ImageDiffPreview(old: blob(":" + file.path), new: workingFile())
        case .staged: return ImageDiffPreview(old: blob("HEAD:" + file.path), new: blob(":" + file.path))
        case .all: return ImageDiffPreview(old: blob("HEAD:" + file.path), new: workingFile())
        }
    }

    static func commits(in worktree: String, repositoryID: UUID, limit: Int, revision: String? = nil) throws -> [Commit] {
        let output = try text(["log", "-n", String(limit), "--pretty=format:%H%x1f%cn%x1f%ct%x1f%s%x1e"] + (revision.map { [$0] } ?? []), in: worktree)
        return output.split(separator: "\u{1e}").compactMap { record in
            let fields = record.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\u{1f}", omittingEmptySubsequences: false)
            guard fields.count == 4, let epoch = TimeInterval(fields[2]) else { return nil }
            return Commit(repositoryID: repositoryID, hash: String(fields[0]), committer: String(fields[1]),
                          date: Date(timeIntervalSince1970: epoch), subject: String(fields[3]))
        }
    }

    static func show(_ commit: Commit, in worktree: String) throws -> String {
        try text(["show", "--format=fuller", "--no-ext-diff", "--find-renames", commit.hash], in: worktree)
    }
}
