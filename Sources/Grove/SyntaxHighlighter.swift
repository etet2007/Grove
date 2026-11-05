import SwiftUI

enum SyntaxKind: Equatable {
    case keyword, string, comment, number, type, function, tag, bracket(Int)

    var color: Color {
        switch self {
        case .keyword: Color(red: 0.78, green: 0.54, blue: 0.98)
        case .string: Color(red: 0.93, green: 0.72, blue: 0.49)
        case .comment: Color(red: 0.48, green: 0.66, blue: 0.42)
        case .number: Color(red: 0.57, green: 0.80, blue: 0.71)
        case .type, .tag: Color(red: 0.40, green: 0.76, blue: 0.85)
        case .function: Color(red: 0.86, green: 0.82, blue: 0.61)
        case .bracket(let depth):
            switch depth % 3 {
            case 0: Color(red: 0.98, green: 0.81, blue: 0.34)
            case 1: Color(red: 0.72, green: 0.56, blue: 0.94)
            default: Color(red: 0.35, green: 0.73, blue: 0.97)
            }
        }
    }
}

struct SyntaxToken: Equatable {
    let range: NSRange
    let kind: SyntaxKind
}

/// A local lexer over the displayed patch; never reads files or changes the code text.
struct SyntaxHighlighter {
    enum Language { case plain, cStyle, swift, script, json, markup }
    var language: Language = .plain
    private var blockEnd: [UInt16]?
    private var quoteEnd: [UInt16]?
    private var depth = 0
    private var inTag = false

    init(path: String = "") {
        let path = CommitPatch.decodePath(path)
        switch (path as NSString).pathExtension.lowercased() {
        case "c", "h", "cc", "cpp", "hpp", "cxx", "m", "mm", "java", "kt", "kts", "gradle", "js", "jsx", "ts", "tsx", "cs", "css", "rs", "go": language = .cStyle
        case "swift": language = .swift
        case "py", "sh", "bash", "zsh", "yml", "yaml", "rb": language = .script
        case "json", "jsonc": language = .json
        case "xml", "plist", "html", "htm", "svg": language = .markup
        default: language = .plain
        }
    }

    mutating func resetContext() {
        blockEnd = nil; quoteEnd = nil; depth = 0; inTag = false
    }

    mutating func tokens(in text: String) -> [SyntaxToken] {
        guard language != .plain else { return [] }
        let units = Array(text.utf16)
        var result: [SyntaxToken] = []
        var i = 0
        func matches(_ pattern: [UInt16], at start: Int) -> Bool {
            start + pattern.count <= units.count && units[start..<start + pattern.count].elementsEqual(pattern)
        }
        func emit(_ start: Int, _ end: Int, _ kind: SyntaxKind) {
            guard end > start else { return }
            result.append(SyntaxToken(range: NSRange(location: start, length: end - start), kind: kind))
        }
        func identifier(_ unit: UInt16) -> Bool {
            (65...90).contains(unit) || (97...122).contains(unit) || unit == 95 || unit == 36 || unit >= 128
        }
        while i < units.count {
            let start = i
            if let end = blockEnd {
                while i < units.count && !matches(end, at: i) { i += 1 }
                if i < units.count { i += end.count; blockEnd = nil }
                emit(start, i, .comment)
                continue
            }
            if let end = quoteEnd {
                while i < units.count {
                    if units[i] == 92 { i = min(units.count, i + 2) }
                    else if matches(end, at: i) { i += end.count; quoteEnd = nil; break }
                    else { i += 1 }
                }
                emit(start, i, .string)
                continue
            }
            if language == .markup && matches(Array("<!--".utf16), at: i) {
                blockEnd = Array("-->".utf16)
                i += 4
                while i < units.count && !matches(blockEnd!, at: i) { i += 1 }
                if i < units.count { i += 3; blockEnd = nil }
                emit(start, i, .comment)
            } else if language != .markup && (matches([47, 47], at: i) || (language == .script && units[i] == 35)) {
                emit(i, units.count, .comment); i = units.count
            } else if language != .markup && language != .script && matches([47, 42], at: i) {
                blockEnd = [42, 47]; i += 2
                while i < units.count && !matches([42, 47], at: i) { i += 1 }
                if i < units.count { i += 2; blockEnd = nil }
                emit(start, i, .comment)
            } else if units[i] == 34 || units[i] == 39 || (language == .cStyle && units[i] == 96) {
                let quote = units[i]
                let triple = language != .markup && matches([quote, quote, quote], at: i)
                let end: [UInt16] = triple ? [quote, quote, quote] : [quote]
                i += end.count
                var closed = false
                while i < units.count {
                    if units[i] == 92 { i = min(units.count, i + 2) }
                    else if matches(end, at: i) { i += end.count; closed = true; break }
                    else { i += 1 }
                }
                if !closed && (triple || quote == 96 || language == .markup) { quoteEnd = end }
                emit(start, i, .string)
            } else if language == .markup && units[i] == 60 {
                inTag = true; i += 1
                if i < units.count && units[i] == 47 { i += 1 }
                while i < units.count && (identifier(units[i]) || units[i] == 58 || units[i] == 45) { i += 1 }
                emit(start, i, .tag)
            } else if language == .markup && units[i] == 62 {
                inTag = false; i += 1; emit(start, i, .tag)
            } else if identifier(units[i]) && (language != .markup || inTag) {
                i += 1
                while i < units.count && (identifier(units[i]) || (48...57).contains(units[i]) || (language == .markup && (units[i] == 58 || units[i] == 45))) { i += 1 }
                let word = String(decoding: units[start..<i], as: UTF16.self)
                if Self.keywords.contains(word) { emit(start, i, .keyword) }
                else if language == .markup { emit(start, i, .type) }
                else if (65...90).contains(units[start]) { emit(start, i, .type) }
                else {
                    var next = i
                    while next < units.count && (units[next] == 32 || units[next] == 9) { next += 1 }
                    if next < units.count && units[next] == 40 { emit(start, i, .function) }
                }
            } else if (48...57).contains(units[i]) && language != .markup {
                i += 1
                while i < units.count && ((48...57).contains(units[i]) || (65...70).contains(units[i]) || (97...102).contains(units[i]) || [46, 95, 120, 88].contains(units[i])) { i += 1 }
                emit(start, i, .number)
            } else if language != .markup && [40, 91, 123].contains(units[i]) {
                emit(i, i + 1, .bracket(depth)); depth += 1; i += 1
            } else if language != .markup && [41, 93, 125].contains(units[i]) {
                depth = max(0, depth - 1); emit(i, i + 1, .bracket(depth)); i += 1
            } else { i += 1 }
        }
        return result
    }

    private static let keywords = Set("abstract actor as async await auto bool boolean break case catch char class const continue def default defer delete do double else enum export extends false final float for func fun guard if implements import in inline int interface internal is let long namespace new nil null nullptr object open operator override package private protected protocol public return self short signed static string struct super suspend switch template this throw throws true try typealias typedef typeof unsigned using val var virtual void volatile when while yield None True False and or not from lambda pass with include define".split(separator: " ").map(String.init))

    static func attributed(_ text: String, tokens: [SyntaxToken]) -> AttributedString {
        var result = AttributedString(text)
        for token in tokens {
            guard let range = Range(token.range, in: text),
                  let start = AttributedString.Index(range.lowerBound, within: result),
                  let end = AttributedString.Index(range.upperBound, within: result) else { continue }
            result[start..<end].foregroundColor = token.kind.color
        }
        return result
    }

    static func patch(_ text: String) -> AttributedString {
        var result = AttributedString()
        var old = SyntaxHighlighter()
        var new = SyntaxHighlighter()
        var inHunk = false
        let lines = text.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            if Task.isCancelled { break }
            var highlighted = AttributedString(line)
            if line.hasPrefix("diff --git ") {
                inHunk = false; old = SyntaxHighlighter(); new = SyntaxHighlighter()
            } else if line.hasPrefix("@@ ") {
                inHunk = true; old.resetContext(); new.resetContext()
                highlighted.foregroundColor = .secondary
            } else if !inHunk && line.hasPrefix("--- ") {
                old = SyntaxHighlighter(path: String(line.dropFirst(4)))
            } else if !inHunk && line.hasPrefix("+++ ") {
                new = SyntaxHighlighter(path: String(line.dropFirst(4)))
            } else if inHunk, let prefix = line.first, ["+", "-", " "].contains(prefix) {
                let code = String(line.dropFirst())
                let tokens: [SyntaxToken]
                switch prefix {
                case "+": tokens = new.tokens(in: code)
                case "-": tokens = old.tokens(in: code)
                default:
                    _ = old.tokens(in: code)
                    tokens = new.tokens(in: code)
                }
                var marker = AttributedString(String(prefix))
                if prefix == "+" { marker.foregroundColor = .green }
                if prefix == "-" { marker.foregroundColor = .red }
                highlighted = marker + attributed(code, tokens: tokens)
                if prefix == "+" { highlighted.backgroundColor = Color.green.opacity(0.17) }
                if prefix == "-" { highlighted.backgroundColor = Color.red.opacity(0.17) }
            }
            result += highlighted
            if index < lines.count - 1 { result += AttributedString("\n") }
        }
        return result
    }
}

struct HighlightedPatchText: View {
    let text: String
    @State private var highlighted: AttributedString?

    var body: some View {
        Text(highlighted ?? AttributedString(text))
            .appFont(size: 12, design: .monospaced)
            .textSelection(.enabled)
            .task(id: text) {
                highlighted = nil
                let task = Task.detached(priority: .utility) { SyntaxHighlighter.patch(text) }
                await withTaskCancellationHandler {
                    let value = await task.value
                    guard !Task.isCancelled else { return }
                    highlighted = value
                } onCancel: {
                    task.cancel()
                }
            }
    }
}
