import Foundation

enum GitError: LocalizedError {
    case command(String)
    case invalidRepository(String)

    var errorDescription: String? {
        switch self {
        case .command(let message), .invalidRepository(let message): message
        }
    }
}

struct GitClient {
    private static let gitURL = URL(fileURLWithPath: "/usr/bin/git")

    static func run(_ args: [String], in directory: String) throws -> Data {
        let process = Process()
        process.executableURL = gitURL
        process.arguments = ["-C", directory] + args
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() }
        catch { throw GitError.command(error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
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
        guard !root.isEmpty else { throw GitError.invalidRepository("不是有效的 Git 仓库：\(path)") }
        return URL(fileURLWithPath: root).resolvingSymlinksInPath().standardizedFileURL.path
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
        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    static func diff(for file: ChangedFile, in worktree: String, mode: DiffMode) throws -> String {
        if file.isUntracked {
            if mode == .staged { return "未跟踪文件没有已暂存修改。" }
            let url = URL(fileURLWithPath: worktree).appendingPathComponent(file.path)
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            if let size = attributes?[.size] as? NSNumber, size.intValue > 250_000 {
                return "未跟踪文件太大，暂不预览（\(size.intValue) 字节）。"
            }
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
                return "未跟踪文件无法作为 UTF-8 文本预览。"
            }
            return "--- /dev/null\n+++ b/\(file.path)\n" + contents.split(separator: "\n", omittingEmptySubsequences: false).map { "+" + $0 }.joined(separator: "\n")
        }
        let args: [String]
        switch mode {
        case .unstaged: args = ["diff", "--no-ext-diff", "--", file.path]
        case .staged: args = ["diff", "--cached", "--no-ext-diff", "--", file.path]
        case .all: args = ["diff", "HEAD", "--no-ext-diff", "--", file.path]
        }
        let output = try text(args, in: worktree)
        return output.isEmpty ? "这一视图没有可显示的修改。" : output
    }

    static func commits(in worktree: String, repositoryID: UUID, limit: Int) throws -> [Commit] {
        let output = try text(["log", "-n", String(limit), "--pretty=format:%H%x1f%an%x1f%at%x1f%s%x1e"], in: worktree)
        return output.split(separator: "\u{1e}").compactMap { record in
            let fields = record.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\u{1f}", omittingEmptySubsequences: false)
            guard fields.count == 4, let epoch = TimeInterval(fields[2]) else { return nil }
            return Commit(repositoryID: repositoryID, hash: String(fields[0]), author: String(fields[1]),
                          date: Date(timeIntervalSince1970: epoch), subject: String(fields[3]))
        }
    }

    static func show(_ commit: Commit, in worktree: String) throws -> String {
        try text(["show", "--format=fuller", "--no-ext-diff", "--find-renames", commit.hash], in: worktree)
    }
}
