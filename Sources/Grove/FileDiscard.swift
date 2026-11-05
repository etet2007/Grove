import Foundation
import SwiftUI
import Darwin

/// A confirmation binds complete working files to their exact index and checkout state.
struct FileDiscardRequest: Identifiable {
    let id = UUID()
    let checkouts: [Checkout]

    struct File {
        let path: String
        let fingerprint: String
        let untracked: Bool
    }
    struct Checkout {
        let path: String
        let head: String
        let branch: String
        let indexPath: String
        let index: Data?
        let files: [File]

        func validate() throws {
            try CommitSnapshot.checkOperation(path)
            guard try CommitSnapshot.currentHead(path) == head,
                  try FileDiscardRequest.branch(in: path) == branch,
                  try CommitSnapshot.readIndex(indexPath) == index else { throw DiffDiscard.staleError }
            for file in files {
                guard try FileDiscardRequest.fingerprint(file.path, in: path) == file.fingerprint else {
                    throw DiffDiscard.staleError
                }
            }
        }
    }

    var count: Int { checkouts.reduce(0) { $0 + $1.files.count } }
    private static func fingerprint(_ file: String, in checkout: String) throws -> String {
        let target = URL(fileURLWithPath: checkout).appendingPathComponent(file).standardizedFileURL
        let parent = target.deletingLastPathComponent()
        guard target.path.hasPrefix(checkout + "/"),
              parent.resolvingSymlinksInPath().path == parent.path else { throw DiffDiscard.staleError }
        return try CommitSnapshot.fingerprint(file, in: checkout)
    }

    private static func branch(in path: String) throws -> String {
        let data = try CommitProcess.git(["symbolic-ref", "--quiet", "HEAD"], in: path, accepting: [0, 1])
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func capture(_ targets: [(checkout: String, files: [ChangedFile])]) throws -> Self {
        let checkouts = try targets.map { target in
            let path = try GitClient.canonicalRepository(at: target.checkout)
            try CommitSnapshot.checkOperation(path)
            let head = try CommitSnapshot.currentHead(path)
            let branch = try FileDiscardRequest.branch(in: path)
            let indexPath = try GitClient.text(["rev-parse", "--path-format=absolute", "--git-path", "index"], in: path).trimmingCharacters(in: .newlines)
            let index = try CommitSnapshot.readIndex(indexPath)
            let files = try target.files.map { file in
                guard file.hasUnstaged, file.changeKind != .conflict,
                      !file.path.hasPrefix("/"),
                      !file.path.split(separator: "/").contains(where: { $0 == ".." || $0 == ".git" }) else {
                    throw DiffDiscard.staleError
                }
                let entry = try GitClient.text(["--literal-pathspecs", "ls-files", "--stage", "-z", "--", file.path], in: path)
                let records = entry.split(separator: "\0")
                if file.isUntracked {
                    guard entry.isEmpty else { throw DiffDiscard.staleError }
                } else {
                    let fields = records.first?.split(separator: "\t").first?.split(separator: " ") ?? []
                    guard records.count == 1, fields.count == 3, fields[2] == "0",
                          ["100644", "100755", "120000"].contains(String(fields[0])) else {
                        throw GitError.command(AppLocalization.text("此文件不支持整文件丢弃修改：%@", file.path))
                    }
                }
                let fingerprint = try FileDiscardRequest.fingerprint(file.path, in: path)
                guard !file.isUntracked || fingerprint != "absent" else { throw DiffDiscard.staleError }
                return File(path: file.path, fingerprint: fingerprint, untracked: file.isUntracked)
            }
            guard !files.isEmpty else { throw DiffDiscard.staleError }
            let checkout = Checkout(path: path, head: head, branch: branch, indexPath: indexPath, index: index, files: files)
            try checkout.validate()
            return checkout
        }
        guard !checkouts.isEmpty else { throw DiffDiscard.staleError }
        return Self(checkouts: checkouts)
    }

    func apply() throws {
        var locks: [(Int32, String)] = []
        var temporaryIndexes: [String: URL] = [:]
        defer {
            for url in temporaryIndexes.values {
                try? FileManager.default.removeItem(at: url)
                try? FileManager.default.removeItem(atPath: url.path + ".lock")
            }
            for (descriptor, path) in locks {
                close(descriptor)
                try? FileManager.default.removeItem(atPath: path)
            }
        }
        // Lock every index and validate the whole selection before changing the first file.
        for checkout in checkouts {
            let path = checkout.indexPath + ".lock"
            let descriptor = open(path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
            guard descriptor >= 0 else {
                throw GitError.command(AppLocalization.text("暂存区已被其他 Git 操作锁定。"))
            }
            locks.append((descriptor, path))
        }
        for checkout in checkouts {
            try checkout.validate()
            // Git restore also locks/refreshes its index. Give it an exact private
            // copy while retaining ownership of the real index lock throughout.
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("GroveDiscardIndex-\(UUID())")
            temporaryIndexes[checkout.path] = url
            if let index = checkout.index { try index.write(to: url, options: .atomic) }
        }
        var completed: [String] = []
        do {
            for checkout in checkouts {
                for file in checkout.files {
                    guard try CommitSnapshot.readIndex(checkout.indexPath) == checkout.index,
                          try CommitSnapshot.currentHead(checkout.path) == checkout.head,
                          try Self.branch(in: checkout.path) == checkout.branch,
                          try Self.fingerprint(file.path, in: checkout.path) == file.fingerprint else {
                        throw DiffDiscard.staleError
                    }
                    if file.untracked {
                        try FileManager.default.removeItem(at: URL(fileURLWithPath: checkout.path).appendingPathComponent(file.path))
                    } else {
                        _ = try CommitProcess.git(["restore", "--worktree", "--", file.path], in: checkout.path,
                                                  index: temporaryIndexes[checkout.path]!.path)
                    }
                    completed.append(checkout.path + "/" + file.path)
                }
            }
        } catch {
            if completed.isEmpty { throw error }
            throw GitError.command(AppLocalization.text("部分文件已丢弃，后续操作已停止。\n%@\n\n%@", completed.joined(separator: "\n"), error.localizedDescription))
        }
    }
}

struct FileDiscardConfirmation: View {
    let request: FileDiscardRequest
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("丢弃所选文件修改？").appFont(size: 16, weight: .semibold)
            Text(AppLocalization.text("丢弃 %ld 个文件的未暂存修改，恢复到暂存区版本。未跟踪文件将被删除，已暂存内容保留。此操作无法撤销。", request.count))
                .appFont(size: 12).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(request.checkouts.indices, id: \.self) { index in
                        let checkout = request.checkouts[index]
                        VStack(alignment: .leading, spacing: 6) {
                            Text(checkout.path).foregroundStyle(WorkbenchStyle.muted)
                            ForEach(checkout.files.indices, id: \.self) { fileIndex in
                                Text(checkout.files[fileIndex].path)
                            }
                        }
                    }
                }
                .appFont(size: 11, design: .monospaced)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            .background(WorkbenchStyle.background)
            .clipShape(RoundedRectangle(cornerRadius: WorkbenchStyle.controlRadius))
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(WorkbenchButtonStyle()).keyboardShortcut(.cancelAction)
                Button("丢弃", role: .destructive, action: onConfirm)
                    .buttonStyle(WorkbenchButtonStyle(emphasized: true)).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 560, height: 420)
        .background(WorkbenchStyle.sidebar).preferredColorScheme(.dark)
    }
}
