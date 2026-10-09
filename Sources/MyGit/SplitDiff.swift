import Foundation

enum DiffLineKind: Equatable {
    case context, removed, added, heading, hunk
}

struct DiffLine: Equatable {
    let number: Int?
    let text: String
    let kind: DiffLineKind
    let syntax: [SyntaxToken]

    init(number: Int?, text: String, kind: DiffLineKind, syntax: [SyntaxToken] = []) {
        self.number = number; self.text = text; self.kind = kind; self.syntax = syntax
    }
}

struct DiffRow: Identifiable, Equatable {
    let id: Int
    let old: DiffLine?
    let new: DiffLine?
}

struct SplitDiff {
    let rows: [DiffRow]
    let hasChanges: Bool
    let contentID = UUID()
    let estimatedContentWidth: CGFloat

    init(rows: [DiffRow], hasChanges: Bool) {
        self.rows = rows
        self.hasChanges = hasChanges
        var maximum = 0
        for row in rows {
            for line in [row.old, row.new] {
                guard let line else { continue }
                maximum = max(maximum, line.text.unicodeScalars.reduce(0) { $0 + ($1.value > 127 ? 2 : 1) })
            }
        }
        estimatedContentWidth = CGFloat(maximum) * 7.25 + 72
    }

    static func parse(_ patch: String) -> SplitDiff {
        var rows: [DiffRow] = []
        var removals: [DiffLine] = []
        var additions: [DiffLine] = []
        var oldNumber = 0
        var newNumber = 0
        var inHunk = false
        var hasChanges = false
        var oldHeader: String?
        var sawFileHeaders = false
        var oldSyntax = SyntaxHighlighter()
        var newSyntax = SyntaxHighlighter()

        func append(_ old: DiffLine?, _ new: DiffLine?) {
            rows.append(DiffRow(id: rows.count, old: old, new: new))
        }

        func flushChanges() {
            for index in 0..<max(removals.count, additions.count) {
                append(index < removals.count ? removals[index] : nil,
                       index < additions.count ? additions[index] : nil)
            }
            removals.removeAll()
            additions.removeAll()
        }

        for rawLine in patch.components(separatedBy: "\n").dropLast(patch.hasSuffix("\n") ? 1 : 0) {
            let line = String(rawLine)
            if line.hasPrefix("diff --git ") {
                flushChanges()
                inHunk = false
                sawFileHeaders = false
                oldHeader = nil
                oldSyntax = SyntaxHighlighter(); newSyntax = SyntaxHighlighter()
                if let separator = line.range(of: " b/", options: .backwards) {
                    append(DiffLine(number: nil, text: String(line[line.index(line.startIndex, offsetBy: 13)..<separator.lowerBound]), kind: .heading),
                           DiffLine(number: nil, text: String(line[separator.upperBound...]), kind: .heading))
                }
            } else if line.hasPrefix("@@ "), let ranges = hunkStarts(in: line) {
                flushChanges()
                if oldNumber != ranges.0 { oldSyntax.resetContext() }
                if newNumber != ranges.1 { newSyntax.resetContext() }
                oldNumber = ranges.0
                newNumber = ranges.1
                inHunk = true
                let heading = DiffLine(number: nil, text: line, kind: .hunk)
                append(heading, heading)
            } else if line.hasPrefix("--- "), !inHunk {
                flushChanges()
                inHunk = false
                oldHeader = line
                oldSyntax = SyntaxHighlighter(path: String(line.dropFirst(4)))
            } else if line.hasPrefix("+++ "), !inHunk {
                sawFileHeaders = true
                newSyntax = SyntaxHighlighter(path: String(line.dropFirst(4)))
                append(oldHeader.map { DiffLine(number: nil, text: $0, kind: .heading) },
                       DiffLine(number: nil, text: line, kind: .heading))
                oldHeader = nil
            } else if line.hasPrefix("\\ No newline at end of file") {
                continue
            } else if inHunk || (sawFileHeaders && line.hasPrefix("+")) {
                if !inHunk { inHunk = true; oldNumber = 0; newNumber = 1 }
                switch line.first {
                case " ":
                    flushChanges()
                    let text = String(line.dropFirst())
                    append(DiffLine(number: oldNumber, text: text, kind: .context, syntax: oldSyntax.tokens(in: text)),
                           DiffLine(number: newNumber, text: text, kind: .context, syntax: newSyntax.tokens(in: text)))
                    oldNumber += 1
                    newNumber += 1
                case "-":
                    let text = String(line.dropFirst())
                    removals.append(DiffLine(number: oldNumber, text: text, kind: .removed, syntax: oldSyntax.tokens(in: text)))
                    oldNumber += 1
                    hasChanges = true
                case "+":
                    let text = String(line.dropFirst())
                    additions.append(DiffLine(number: newNumber, text: text, kind: .added, syntax: newSyntax.tokens(in: text)))
                    newNumber += 1
                    hasChanges = true
                default:
                    flushChanges()
                    inHunk = false
                }
            } else if line.hasPrefix("Binary files ") || line.hasPrefix("GIT binary patch") {
                let heading = DiffLine(number: nil, text: line, kind: .heading)
                append(heading, heading)
            }
        }
        flushChanges()
        return SplitDiff(rows: rows, hasChanges: hasChanges)
    }

    private static func hunkStarts(in line: String) -> (Int, Int)? {
        let pattern = #"^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@"#
        guard let match = line.range(of: pattern, options: .regularExpression),
              let oldRange = line.range(of: #"(?<=@@ -)\d+"#, options: .regularExpression),
              let newRange = line.range(of: #"(?<=\+)\d+(?=(?:,\d+)? @@)"#, options: .regularExpression),
              match.lowerBound == line.startIndex,
              let old = Int(line[oldRange]), let new = Int(line[newRange]) else { return nil }
        return (old, new)
    }
}
