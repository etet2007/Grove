import Foundation
import CryptoKit

enum CommitScope: String, CaseIterable, Identifiable {
    case staged = "已暂存", all = "全部修改"
    var id: String { rawValue }
}

struct CommitFileSnapshot: Equatable {
    let path: String
    let patch: String
    let fingerprint: String
    let indexEntry: Data
}

struct CommitSnapshot {
    let checkout: String
    let branch: String
    let head: String
    let indexPath: String
    let indexData: Data?
    let status: Data
    let scope: CommitScope
    let files: [CommitFileSnapshot]
    let watched: [String: String]

    static let diffOptions = ["--no-color", "--no-ext-diff", "--no-textconv", "--binary", "--no-renames", "--full-index"]

    static func capture(checkout: String, scope: CommitScope, progress: CommitActivitySink? = nil) throws -> CommitSnapshot {
        progress?(CommitActivity(AppLocalization.text("读取仓库修改"), detail: checkout))
        let path = try GitClient.canonicalRepository(at: checkout)
        let branch = try CommitProcess.gitText(["symbolic-ref", "--quiet", "HEAD"], in: path)
        let head = try currentHead(path)
        let indexPath = try CommitProcess.gitText(["rev-parse", "--path-format=absolute", "--git-path", "index"], in: path)
        try checkOperation(path)
        let indexData = try readIndex(indexPath)
        let status = try statusData(path)
        let records = try parseStatus(status)
        guard !records.isEmpty else { throw CommitFailure.message(AppLocalization.text("没有可提交的修改。")) }
        guard !records.contains(where: { ["DD", "AU", "UD", "UA", "DU", "AA", "UU"].contains($0.code) }) else {
            throw CommitFailure.message(AppLocalization.text("请先解决仓库冲突，再准备提交。"))
        }
        let entries = try CommitProcess.git(["ls-files", "--stage", "-z"], in: path)
        var indexEntries: [String: Data] = [:]
        for record in entries.split(separator: 0) {
            guard let tab = record.firstIndex(of: 9) else { continue }
            let metadata = String(decoding: record[..<tab], as: UTF8.self).split(separator: " ")
            guard metadata.count == 3 else { continue }
            let name = String(decoding: record[record.index(after: tab)...], as: UTF8.self)
            if records.contains(where: { $0.path == name }), metadata[0] == "160000" {
                throw CommitFailure.message(AppLocalization.text("第一版暂不支持提交子模块修改。"))
            }
            indexEntries[name] = Data("\(metadata[0]) \(metadata[1])\t\(name)\0".utf8)
        }
        var watched: [String: String] = [:]
        for record in records { watched[record.path] = try fingerprint(record.path, in: path) }
        let selected = records.filter { scope == .all || ($0.code.first != " " && $0.code.first != "?") }
        var files: [CommitFileSnapshot] = []
        for record in selected {
            progress?(CommitActivity(AppLocalization.text("读取文件 diff"), detail: record.path))
            if scope == .all && head.isEmpty && watched[record.path] == "absent" { continue }
            let patch: Data
            if scope == .all && (record.code == "??" || head.isEmpty) {
                patch = try CommitProcess.git(["diff", "--no-index"] + diffOptions + ["--", "/dev/null", record.path],
                                              in: path, accepting: [0, 1])
            } else {
                var args = ["diff"] + diffOptions
                if scope == .staged { args += ["--cached"] }
                if !head.isEmpty { args += [head] }
                patch = try CommitProcess.git(args + ["--", record.path], in: path)
            }
            // A work file reverted to HEAD may still have a staged change; it has no all-scope diff.
            guard !patch.isEmpty else { continue }
            files.append(CommitFileSnapshot(path: record.path, patch: String(decoding: patch, as: UTF8.self),
                                             fingerprint: watched[record.path]!,
                                             indexEntry: indexEntries[record.path] ?? Data("0 \(String(repeating: "0", count: 40))\t\(record.path)\0".utf8)))
        }
        guard !files.isEmpty else { throw CommitFailure.message(AppLocalization.text("当前范围没有可提交的修改。")) }
        let snapshot = CommitSnapshot(checkout: path, branch: branch, head: head, indexPath: indexPath,
                                      indexData: indexData, status: status, scope: scope, files: files,
                                      watched: watched)
        try snapshot.validate()
        return snapshot
    }

    func validate(head expectedHead: String? = nil, index expectedIndex: Data? = nil, afterCommit: Bool = false) throws {
        try Self.checkOperation(checkout)
        guard try Self.currentHead(checkout) == (expectedHead ?? head),
              try CommitProcess.gitText(["symbolic-ref", "--quiet", "HEAD"], in: checkout) == branch,
              try Self.readIndex(indexPath) == (afterCommit ? expectedIndex : indexData) else {
            throw CommitFailure.message(AppLocalization.text("分支、HEAD 或暂存区已变化，请重新准备提交。"))
        }
        if !afterCommit, try Self.statusData(checkout) != status {
            throw CommitFailure.message(AppLocalization.text("文件列表已变化，请重新准备提交。"))
        }
        for (path, expected) in watched {
            guard try Self.fingerprint(path, in: checkout) == expected else {
                throw CommitFailure.message(AppLocalization.text("工作文件已变化，请重新准备提交：%@", path))
            }
        }
    }

    static func currentHead(_ path: String) throws -> String {
        let result = try CommitProcess.run("/usr/bin/git", ["rev-parse", "--verify", "HEAD"], in: path)
        if result.status != 0 {
            // Only an unborn branch is accepted; malformed refs are an error.
            let branch = try CommitProcess.gitText(["symbolic-ref", "HEAD"], in: path)
            _ = try CommitProcess.git(["show-ref", "--verify", "--quiet", branch], in: path, accepting: [1])
            return ""
        }
        return String(decoding: result.data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func readIndex(_ path: String) throws -> Data? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return try Data(contentsOf: URL(fileURLWithPath: path))
    }

    static func statusData(_ path: String) throws -> Data {
        try CommitProcess.git(["status", "--porcelain=v1", "-z", "--untracked-files=all", "--no-renames"], in: path)
    }

    static func parseStatus(_ data: Data) throws -> [(code: String, path: String)] {
        try data.split(separator: 0).map { record in
            guard record.count > 3, let text = String(data: record, encoding: .utf8) else {
                throw CommitFailure.message(AppLocalization.text("暂不支持非 UTF-8 文件名。"))
            }
            let path = String(text.dropFirst(3))
            guard !path.hasPrefix("/"), !path.split(separator: "/").contains(".."),
                  !path.split(separator: "/").contains(".git") else {
                throw CommitFailure.message(AppLocalization.text("无效的提交文件路径。"))
            }
            return (String(text.prefix(2)), path)
        }
    }

    static func fingerprint(_ path: String, in checkout: String) throws -> String {
        let url = URL(fileURLWithPath: checkout).appendingPathComponent(path)
        let parent = url.deletingLastPathComponent().resolvingSymlinksInPath().path
        guard parent == checkout || parent.hasPrefix(checkout + "/") else {
            throw CommitFailure.message(AppLocalization.text("文件路径位于 checkout 外。"))
        }
        // lstat semantics: dangling symlinks are valid tracked files too.
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return "absent" }
        let type = attributes[.type] as? FileAttributeType
        var hasher = SHA256()
        if type == .typeSymbolicLink {
            hasher.update(data: Data(try FileManager.default.destinationOfSymbolicLink(atPath: url.path).utf8))
        } else {
            guard type == .typeRegular else {
                throw CommitFailure.message(AppLocalization.text("暂不支持提交目录或子模块：%@", path))
            }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
                try Task.checkCancellation()
                hasher.update(data: chunk)
            }
        }
        return "\(type?.rawValue ?? ""):\(attributes[.posixPermissions] ?? ""):" + hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func checkOperation(_ path: String) throws {
        let gitDirectory = try CommitProcess.gitText(["rev-parse", "--absolute-git-dir"], in: path)
        for marker in ["MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "rebase-merge", "rebase-apply", "sequencer"] {
            let location = URL(fileURLWithPath: gitDirectory).appendingPathComponent(marker).path
            guard !FileManager.default.fileExists(atPath: location) else {
                throw CommitFailure.message(AppLocalization.text("请先完成当前 merge、rebase 或 cherry-pick 操作。"))
            }
        }
    }
}

// Shared across windows. Branch switch and discard also acquire this reservation.
enum CheckoutOperationLock {
    private static let lock = NSLock()
    private static var paths: Set<String> = []
    private static var appUpdateReserved = false

    static func beginAppUpdate() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard paths.isEmpty, !appUpdateReserved else { return false }
        appUpdateReserved = true
        return true
    }

    static func endAppUpdate() {
        lock.lock(); defer { lock.unlock() }
        appUpdateReserved = false
    }
    private static func key(_ path: String) -> String {
        // Linked worktrees share remote refs and configuration; serialize their writes too.
        let common = try? CommitProcess.gitText(["rev-parse", "--path-format=absolute", "--git-common-dir"], in: path)
        return URL(fileURLWithPath: common ?? path).resolvingSymlinksInPath().path
    }
    static func acquire(_ path: String) -> Bool {
        let key = key(path)
        lock.lock(); defer { lock.unlock() }
        guard !appUpdateReserved else { return false }
        return paths.insert(key).inserted
    }
    static func release(_ path: String) {
        let key = key(path)
        lock.lock(); defer { lock.unlock() }
        paths.remove(key)
    }
}

struct CommitExecutionResult {
    var hashes: [String] = []
    var failure: String?
}

enum CommitExecutor {
    static func execute(_ plan: CommitPlan, snapshot: CommitSnapshot, progress: CommitActivitySink? = nil) -> CommitExecutionResult {
        var result = CommitExecutionResult()
        guard CheckoutOperationLock.acquire(snapshot.checkout) else {
            result.failure = AppLocalization.text("此 checkout 正在执行其他操作。")
            return result
        }
        defer { CheckoutOperationLock.release(snapshot.checkout) }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("MyGitCommit-\(UUID())")
        defer { try? FileManager.default.removeItem(at: temporary) }
        // Own the standard index lock for the entire sequence; never delete somebody else's lock.
        let lockPath = snapshot.indexPath + ".lock"
        var lockFD: Int32 = -1
        var attemptedParent: String?
        defer { if lockFD >= 0 { close(lockFD); try? FileManager.default.removeItem(atPath: lockPath) } }
        do {
            try plan.validate(available: Set(snapshot.files.map(\.path)))
            lockFD = open(lockPath, O_WRONLY | O_CREAT | O_EXCL, 0o600)
            guard lockFD >= 0 else { throw CommitFailure.message(AppLocalization.text("暂存区已被其他 Git 操作锁定。")) }
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
            var expectedHead = snapshot.head
            var expectedIndex = snapshot.indexData
            for (number, commit) in plan.commits.enumerated() {
                let detail = AppLocalization.text("第 %ld/%ld 笔：%@", number + 1, plan.commits.count, commit.message.components(separatedBy: "\n").first ?? "")
                try CommitTimedStep.run("校验仓库状态", detail: detail, progress: progress) {
                    try snapshot.validate(head: expectedHead, index: expectedIndex, afterCommit: !result.hashes.isEmpty)
                }
                progress?(CommitActivity(AppLocalization.text("准备提交内容"), detail: detail))
                let index = temporary.appendingPathComponent(UUID().uuidString).path
                _ = try CommitProcess.git(expectedHead.isEmpty ? ["read-tree", "--empty"] : ["read-tree", expectedHead], in: snapshot.checkout, index: index)
                if snapshot.scope == .staged {
                    let entries = commit.paths.reduce(into: Data()) { data, path in data.append(snapshot.files.first { $0.path == path }!.indexEntry) }
                    _ = try CommitProcess.git(["update-index", "-z", "--index-info"], in: snapshot.checkout, index: index, input: entries)
                } else {
                    _ = try CommitProcess.git(["add", "-A", "--"] + commit.paths, in: snapshot.checkout, index: index)
                }
                // Compare exactly what Git will commit with the diff that the user approved.
                progress?(CommitActivity(AppLocalization.text("核对提交 diff"), detail: detail))
                for path in commit.paths {
                    var args = ["diff"] + CommitSnapshot.diffOptions + ["--cached"]
                    if !expectedHead.isEmpty { args += [expectedHead] }
                    let patch = try CommitProcess.git(args + ["--", path], in: snapshot.checkout, index: index)
                    guard String(decoding: patch, as: UTF8.self) == snapshot.files.first(where: { $0.path == path })!.patch else {
                        throw CommitFailure.message(AppLocalization.text("实际提交内容与预览不同，请重新准备：%@", path))
                    }
                }
                let tree = try CommitProcess.gitText(["write-tree"], in: snapshot.checkout, index: index)
                let message = temporary.appendingPathComponent("message.txt")
                try Data(commit.message.utf8).write(to: message)
                try snapshot.validate(head: expectedHead, index: expectedIndex, afterCommit: !result.hashes.isEmpty)
                // Hooks and signing remain enabled. No retry that bypasses either.
                attemptedParent = expectedHead
                let decoder = CommitPlainOutputDecoder(progress: progress)
                let output = try CommitTimedStep.run("执行 Git 提交（含 hook 和签名）", detail: detail, progress: progress) {
                    defer { decoder.finish() }
                    return try CommitProcess.run("/usr/bin/git", ["commit", "--cleanup=verbatim", "--file", message.path],
                                                  in: snapshot.checkout, environment: ["GIT_INDEX_FILE": index, "GIT_LITERAL_PATHSPECS": "1"],
                                                  onOutput: progress == nil ? nil : decoder.feed)
                }
                let newHead = try CommitSnapshot.currentHead(snapshot.checkout)
                if newHead != expectedHead { result.hashes.append(newHead) }
                guard output.status == 0, newHead != expectedHead else {
                    throw CommitFailure.message(output.diagnostic + String(decoding: output.data, as: UTF8.self))
                }
                let actualTree = try CommitProcess.gitText(["rev-parse", "HEAD^{tree}"], in: snapshot.checkout)
                let parent = try CommitProcess.gitText(["rev-list", "--parents", "-n", "1", "HEAD"], in: snapshot.checkout).split(separator: " ").dropFirst().map(String.init)
                guard actualTree == tree, parent == (expectedHead.isEmpty ? [] : [expectedHead]) else {
                    throw CommitFailure.message(AppLocalization.text("提交已产生，但 hook 或外部操作改变了提交内容；已停止后续提交，请检查仓库。"))
                }
                guard try CommitSnapshot.readIndex(snapshot.indexPath) == expectedIndex else {
                    throw CommitFailure.message(AppLocalization.text("提交已产生，但真实暂存区已变化；已停止，请检查仓库。"))
                }
                // Start from the original real index, then clear only paths actually committed.
                progress?(CommitActivity(AppLocalization.text("保留未提交的暂存内容"), detail: detail))
                let reconciled = temporary.appendingPathComponent("real-index-\(UUID())").path
                if let expectedIndex { try expectedIndex.write(to: URL(fileURLWithPath: reconciled)) }
                else { _ = try CommitProcess.git(["read-tree", "--empty"], in: snapshot.checkout, index: reconciled) }
                _ = try CommitProcess.git(["reset", "-q", newHead, "--"] + commit.paths, in: snapshot.checkout, index: reconciled)
                expectedIndex = try Data(contentsOf: URL(fileURLWithPath: reconciled))
                try expectedIndex!.write(to: URL(fileURLWithPath: snapshot.indexPath), options: .atomic)
                expectedHead = newHead
                try snapshot.validate(head: expectedHead, index: expectedIndex, afterCommit: true)
                attemptedParent = nil
                progress?(CommitActivity(AppLocalization.text("已完成第 %ld/%ld 笔提交", number + 1, plan.commits.count), detail: newHead, kind: .completed))
            }
        } catch {
            // A timeout or failed post-commit hook can occur after Git has moved HEAD.
            if let attemptedParent, let head = try? CommitSnapshot.currentHead(snapshot.checkout), !head.isEmpty,
               head != attemptedParent, result.hashes.last != head { result.hashes.append(head) }
            result.failure = error.localizedDescription
        }
        return result
    }
}
