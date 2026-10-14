import Foundation

struct CommitAgentLaunch {
    let executable: String
    let arguments: [String]
    let directory: String
    let environment = ["GIT_OPTIONAL_LOCKS": "0", "GIT_TERMINAL_PROMPT": "0"]

    static func prepare(snapshot: CommitSnapshot, preferences: CommitPreferences, skill: URL,
                        temporary: URL, schema: String) throws -> CommitAgentLaunch {
        var arguments: [String]
        let result = temporary.appendingPathComponent("result.json")
        switch preferences.kind {
        case .codex:
            let schemaURL = temporary.appendingPathComponent("schema.json")
            try Data(schema.utf8).write(to: schemaURL)
            arguments = ["--ask-for-approval", "never", "exec", "--json", "--sandbox", "read-only", "--ephemeral",
                         "--output-schema", schemaURL.path, "--output-last-message", result.path, "-"]
        case .claude:
            arguments = ["--print", "--permission-mode", "plan", "--tools", "Read,Grep,Glob,Bash",
                         "--disallowedTools", "Edit,Write", "--output-format", "stream-json", "--verbose", "--include-partial-messages",
                         "--json-schema", schema, "--no-session-persistence",
                         "--strict-mcp-config", "--mcp-config", #"{"mcpServers":{}}"#]
        case .omp:
            // Non-interactive OMP otherwise asks for every bash call, including
            // git status/diff. Only the selected tools are exposed, and the OS
            // profile below still denies writes to the checkout and Git data.
            let config = temporary.appendingPathComponent("read-only-tools.yml")
            try Data("tools:\n  approval:\n    bash: allow\n".utf8).write(to: config)
            arguments = ["--print", "--mode=json", "--tools=read,grep,glob,bash", "--approval-mode=write",
                         "--config=\(config.path)", "--no-extensions", "--no-lsp", "--no-pty", "--no-session"]
        }
        if !preferences.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if preferences.kind == .codex { arguments.insert(contentsOf: ["--model", preferences.model], at: arguments.count - 1) }
            else { arguments += ["--model", preferences.model] }
        }
        // Codex already applies its native read-only sandbox to tool processes.
        // macOS cannot apply that sandbox from inside another sandbox-exec run.
        if preferences.kind == .codex {
            return CommitAgentLaunch(executable: preferences.executable, arguments: arguments, directory: snapshot.checkout)
        }
        let gitDirectory = try CommitProcess.gitText(["rev-parse", "--absolute-git-dir"], in: snapshot.checkout)
        let commonDirectory = try CommitProcess.gitText(["rev-parse", "--path-format=absolute", "--git-common-dir"], in: snapshot.checkout)
        let profile = readOnlyProfile(protectedPaths: [snapshot.checkout, gitDirectory, commonDirectory], protectedFiles: [skill.path])
        let profileURL = temporary.appendingPathComponent("read-only.sb")
        try Data(profile.utf8).write(to: profileURL)
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/sandbox-exec") else {
            throw CommitFailure.message(AppLocalization.text("无法启用 Agent 的只读执行环境。"))
        }
        return CommitAgentLaunch(executable: "/usr/bin/sandbox-exec",
                                 arguments: ["-f", profileURL.path, preferences.executable] + arguments,
                                 directory: snapshot.checkout)
    }

    // CLI auth/session caches remain usable. The repository, every worktree's
    // shared Git data, and the selected skill override even a writable cache path.
    static func readOnlyProfile(protectedPaths: [String], protectedFiles: [String] = []) -> String {
        func quoted(_ path: String) -> String {
            // SBPL matches physical paths. Foundation can retain /var aliases
            // on macOS, which would silently fail to protect a temp checkout.
            let canonical = path.withCString { source -> String in
                guard let resolved = realpath(source, nil) else { return URL(fileURLWithPath: path).standardizedFileURL.path }
                defer { free(resolved) }
                return String(cString: resolved)
            }
            return "\"" + canonical.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r").replacingOccurrences(of: "\t", with: "\\t") + "\""
        }
        return """
        (version 1)
        (allow default)
        \(protectedPaths.map { "(deny file-write* (subpath \(quoted($0))))" }.joined(separator: "\n"))
        \(protectedFiles.map { "(deny file-write* (literal \(quoted($0))))" }.joined(separator: "\n"))
        """
    }
}
