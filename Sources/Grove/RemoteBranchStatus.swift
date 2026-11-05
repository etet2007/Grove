import Foundation

// Local remote-tracking refs only. This never fetches or contacts the remote.
struct RemoteBranchStatus: Equatable {
    let upstream: String?
    let remote: String?
    let ahead: Int?
    let behind: Int?
    let missing: Bool
    var hasRemoteUpstream: Bool { upstream != nil && remote != nil && remote != "." }
    var diverged: Bool { (ahead ?? 0) > 0 && (behind ?? 0) > 0 }

    static func read(in checkout: String, branch: String?) throws -> Self {
        guard let branch else { return Self(upstream: nil, remote: nil, ahead: nil, behind: nil, missing: false) }
        let ref = "refs/heads/" + branch
        let format = "%(refname)%00%(upstream:short)%00%(upstream:remotename)%00%(upstream:track,nobracket)"
        let text = try GitClient.text(["for-each-ref", "--format=" + format, "--", ref], in: checkout)
        let fields = text.split(separator: "\n").map { $0.components(separatedBy: "\0") }
            .first { $0.first == ref }
        guard let fields, fields.count == 4, !fields[1].isEmpty else {
            return Self(upstream: nil, remote: nil, ahead: nil, behind: nil, missing: false)
        }
        let missing = fields[3] == "gone"
        var ahead = 0, behind = 0
        for value in fields[3].split(separator: ",") {
            let pair = value.split(whereSeparator: \.isWhitespace)
            if pair.count == 2, let count = Int(pair[1]) {
                if pair[0] == "ahead" { ahead = count }
                if pair[0] == "behind" { behind = count }
            }
        }
        return Self(upstream: fields[1], remote: fields[2].isEmpty ? nil : fields[2],
                    ahead: missing ? nil : ahead, behind: missing ? nil : behind, missing: missing)
    }

    func pending(_ operation: RemoteOperation) -> Int? {
        guard hasRemoteUpstream else { return nil }
        return operation == .push ? ahead : operation == .pull ? behind : nil
    }

    func help(_ operation: RemoteOperation) -> String {
        if operation == .fetch { return AppLocalization.text("Fetch：检查远端新提交并更新本地远端记录。") }
        guard hasRemoteUpstream else { return AppLocalization.text("%@：尚未配置远端 upstream。", operation.title) }
        guard !missing, let count = pending(operation) else {
            return AppLocalization.text("%@：本地尚无 upstream 记录，请先 Fetch。", operation.title)
        }
        let status = operation == .push ? AppLocalization.text("Push：%ld 个提交待推送至 %@。", count, upstream ?? "")
            : AppLocalization.text("Pull：%ld 个提交待拉取自 %@。", count, upstream ?? "")
        let divergence = diverged ? AppLocalization.text("分支已分叉，Pull 仅允许快进。") + "\n" : ""
        return status + "\n" + divergence + AppLocalization.text("基于本地远端记录；Fetch 后更新。")
    }
}
