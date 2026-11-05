import Foundation
import SwiftUI

struct CommitActivity: Identifiable {
    enum Kind { case phase, output, delta, completed }
    let id = UUID()
    let date = Date()
    let kind: Kind
    let title: String
    var detail: String

    init(_ title: String, detail: String = "", kind: Kind = .phase) {
        self.title = title; self.detail = detail; self.kind = kind
    }
}

typealias CommitActivitySink = (CommitActivity) -> Void

enum CommitTimedStep {
    static func run<T>(_ title: String, detail: String = "", progress: CommitActivitySink?, body: () throws -> T) throws -> T {
        let title = AppLocalization.text(title)
        progress?(CommitActivity(title, detail: detail))
        let start = Date()
        do {
            let value = try body()
            progress?(CommitActivity(title, detail: AppLocalization.text("完成，耗时 %.2f 秒", Date().timeIntervalSince(start)), kind: .output))
            return value
        } catch {
            progress?(CommitActivity(title, detail: AppLocalization.text("失败，耗时 %.2f 秒", Date().timeIntervalSince(start)), kind: .output))
            throw error
        }
    }
}

final class CommitPlainOutputDecoder {
    private var buffers: [Int: Data] = [:]
    private let progress: CommitActivitySink?
    init(progress: CommitActivitySink?) { self.progress = progress }
    func feed(_ stream: CommitProcess.Stream, _ chunk: Data) {
        let key = stream == .stdout ? 0 : 1
        var buffer = buffers[key] ?? Data(); buffer.append(chunk)
        while let newline = buffer.firstIndex(of: 10) {
            emit(Data(buffer[..<newline])); buffer.removeSubrange(...newline)
        }
        buffers[key] = Data(buffer.suffix(64_000))
    }
    func finish() { for data in buffers.values where !data.isEmpty { emit(data) }; buffers.removeAll() }
    private func emit(_ data: Data) {
        progress?(CommitActivity(AppLocalization.text("Git 输出"), detail: CommitOutputText.clean(String(decoding: data, as: UTF8.self)), kind: .output))
    }
}

enum CommitOutputText {
    static func clean(_ text: String) -> String {
        var value = text.replacingOccurrences(of: #"\u001B\[[0-?]*[ -/]*[@-~]"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"(?i)(Bearer\s+)[A-Za-z0-9._~+/=-]+"#, with: "$1<REDACTED>", options: .regularExpression)
        value = value.replacingOccurrences(of: #"sk-[A-Za-z0-9_-]{8,}"#, with: "<REDACTED>", options: .regularExpression)
        value = value.replacingOccurrences(of: #"(?i)(https?://)[^\s/@]+@"#, with: "$1<REDACTED>@", options: .regularExpression)
        return value
    }
}

// JSONL framing is kept as bytes so split UTF-8 characters and partial events are safe.
final class CommitAgentActivityDecoder {
    private let kind: CommitAgentKind
    private let sink: CommitActivitySink
    private var buffers: [Int: Data] = [:]
    private var sawTextDelta = false

    init(kind: CommitAgentKind, sink: @escaping CommitActivitySink) { self.kind = kind; self.sink = sink }

    func feed(_ stream: CommitProcess.Stream, _ data: Data) {
        let key = stream == .stdout ? 0 : 1
        var buffer = buffers[key] ?? Data()
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 10) {
            consume(Data(buffer[..<newline]), stderr: key == 1)
            buffer.removeSubrange(...newline)
        }
        // Bound malformed/non-JSON diagnostics without retaining an unlimited partial line.
        if buffer.count > 1_000_000 { buffer = Data(buffer.suffix(1_000_000)) }
        buffers[key] = buffer
    }

    func finish() {
        for key in [0, 1] { if let data = buffers[key], !data.isEmpty { consume(data, stderr: key == 1) } }
        buffers.removeAll()
    }

    private func emit(_ title: String, _ detail: String = "", kind: CommitActivity.Kind = .phase) {
        sink(CommitActivity(AppLocalization.text(title), detail: CommitOutputText.clean(detail), kind: kind))
    }

    private func consume(_ data: Data, stderr: Bool) {
        guard !data.isEmpty else { return }
        guard !stderr, let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            emit("Agent 日志", String(decoding: data, as: UTF8.self), kind: .output); return
        }
        let type = event["type"] as? String ?? ""
        switch kind {
        case .codex:
            if type == "thread.started" { emit("Agent 已启动") }
            if type == "turn.started" { emit("Agent 正在分析改动") }
            if type == "turn.completed" { emit("Agent 已完成生成") }
            if type == "error" || type == "turn.failed" {
                let error = event["error"] as? [String: Any]
                emit("Agent 日志", event["message"] as? String ?? error?["message"] as? String ?? type, kind: .output)
            }
            if let item = event["item"] as? [String: Any] {
                let itemType = item["type"] as? String
                if itemType == "command_execution" {
                    emit("Agent 执行命令", item["command"] as? String ?? "")
                    if let output = item["aggregated_output"] as? String, !output.isEmpty { emit("Agent 日志", output, kind: .output) }
                }
                if type == "item.completed", let text = item["text"] as? String {
                    if itemType == "reasoning" { emit("Agent 分析摘要", text, kind: .output) }
                    if itemType == "agent_message" { emit("Agent 输出", text, kind: .output) }
                }
            }
        case .claude:
            if type == "system", event["subtype"] as? String == "init" { emit("Agent 已启动", event["model"] as? String ?? "") }
            if type == "stream_event", let inner = event["event"] as? [String: Any] {
                if inner["type"] as? String == "message_start" { sawTextDelta = false; emit("Agent 正在分析改动") }
                if let delta = inner["delta"] as? [String: Any], delta["type"] as? String == "text_delta",
                   let text = delta["text"] as? String { sawTextDelta = true; emit("Agent 输出", text, kind: .delta) }
                if let block = inner["content_block"] as? [String: Any], block["type"] as? String == "tool_use" {
                    emit("Agent 正在读取仓库", block["name"] as? String ?? "")
                }
            }
            if type == "assistant", let message = event["message"] as? [String: Any],
               let blocks = message["content"] as? [[String: Any]] {
                for block in blocks where block["type"] as? String == "tool_use" {
                    let name = block["name"] as? String ?? ""
                    let input = block["input"] as? [String: Any] ?? [:]
                    emit("Agent 正在读取仓库", name + ": " + (input["command"] as? String ?? input["file_path"] as? String ?? input["pattern"] as? String ?? ""))
                }
                let text = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined()
                if !sawTextDelta && !text.isEmpty { emit("Agent 输出", text, kind: .output) }
            }
            if type == "result" {
                if event["is_error"] as? Bool == true { emit("Agent 日志", event["result"] as? String ?? "", kind: .output) }
                else { emit("Agent 已完成生成") }
            }
        case .omp:
            if type == "agent_start" { emit("Agent 已启动") }
            if type == "message_start", let message = event["message"] as? [String: Any], message["role"] as? String == "assistant" {
                sawTextDelta = false; emit("Agent 正在分析改动")
            }
            if type == "message_update", let inner = event["assistantMessageEvent"] as? [String: Any] {
                if inner["type"] as? String == "text_delta", let text = inner["delta"] as? String {
                    sawTextDelta = true; emit("Agent 输出", text, kind: .delta)
                }
                // Private thinking deltas are never copied into the activity view.
            }
            if type == "tool_execution_start" {
                let args = event["args"] as? [String: Any] ?? [:]
                let detail = args["command"] as? String ?? args["path"] as? String ?? args["pattern"] as? String ?? ""
                emit("Agent 正在读取仓库", (event["toolName"] as? String ?? "") + ": " + detail)
            }
            if type == "tool_execution_end", let result = event["result"] as? [String: Any], let blocks = result["content"] as? [[String: Any]] {
                let text = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined(separator: "\n")
                if !text.isEmpty { emit("Agent 读取结果", String(text.prefix(6000)), kind: .output) }
            }
            if type == "message_end", !sawTextDelta, let message = event["message"] as? [String: Any],
               message["role"] as? String == "assistant", let blocks = message["content"] as? [[String: Any]] {
                let text = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined()
                if !text.isEmpty { emit("Agent 输出", text, kind: .output) }
            }
            if type == "agent_end" { emit("Agent 已完成生成") }
        }
    }
}

@MainActor final class CommitActivityLog: ObservableObject {
    @Published private(set) var events: [CommitActivity] = []
    @Published private(set) var stage = ""
    @Published private(set) var running = false
    @Published private(set) var started: Date?
    private(set) var ended: Date?
    // Ignore late callbacks from a canceled or superseded run.
    private var generation = UUID()

    func begin(_ title: String) -> CommitActivitySink {
        generation = UUID()
        let token = generation
        events = []; stage = AppLocalization.text(title); running = true; started = Date(); ended = nil
        append(CommitActivity(stage))
        return { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token, self.running else { return }
                self.append(event)
            }
        }
    }

    func append(_ event: CommitActivity) {
        if event.kind == .phase || event.kind == .completed { stage = event.title }
        var event = event
        event.detail = String(CommitOutputText.clean(event.detail).prefix(6000))
        if event.kind == .delta, let last = events.indices.last, events[last].kind == .delta {
            events[last].detail = String(CommitOutputText.clean(events[last].detail + event.detail).suffix(6000))
        } else { events.append(event) }
        while events.count > 150 || events.reduce(0, { $0 + $1.detail.count }) > 60_000 { events.removeFirst() }
    }

    func finish(_ title: String) {
        running = false; ended = Date(); append(CommitActivity(AppLocalization.text(title), kind: .completed))
    }
}

struct CommitActivityView: View {
    @ObservedObject var log: CommitActivityLog
    @State private var expanded = true
    @State private var follow = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if log.running { ProgressView().controlSize(.small) }
                Text(verbatim: log.stage).font(.system(size: 12, weight: .medium))
                Spacer()
                if let start = log.started {
                    TimelineView(.periodic(from: start, by: 1)) { context in
                        Text(AppLocalization.text("已用 %.1f 秒", max(0, (log.ended ?? context.date).timeIntervalSince(start))))
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
                Button(AppLocalization.text(expanded ? "收起执行详情" : "展开执行详情")) { expanded.toggle() }
            }
            if expanded {
                HStack {
                    Text("实时执行详情").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Toggle("跟随最新输出", isOn: $follow).toggleStyle(.checkbox).font(.caption)
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(log.events) { event in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 8) {
                                        Text(verbatim: event.date.formatted(date: .omitted, time: .standard)).foregroundStyle(.secondary)
                                        Text(verbatim: event.title)
                                    }.font(.system(size: 10, design: .monospaced))
                                    if !event.detail.isEmpty {
                                        Text(verbatim: event.detail).font(.system(size: 11, design: .monospaced))
                                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }.id(event.id)
                            }
                            Color.clear.frame(height: 1).id("activity-bottom")
                        }.padding(10)
                    }
                    .frame(height: log.running ? 150 : 100)
                    .background(WorkbenchStyle.background, in: RoundedRectangle(cornerRadius: 6))
                    .onChange(of: log.events.last?.id) { _, _ in if follow { proxy.scrollTo("activity-bottom", anchor: .bottom) } }
                    .onChange(of: log.events.last?.detail) { _, _ in if follow { proxy.scrollTo("activity-bottom", anchor: .bottom) } }
                }
            }
        }
        .padding(12).background(WorkbenchStyle.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }
}
