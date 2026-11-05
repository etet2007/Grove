import Foundation
import Markdown

/// Converts a CommonMark/GFM tree to a closed set of HTML elements. Repository HTML
/// is always escaped, and images never trigger file or network requests.
enum MarkdownPreview {
    static func supports(_ path: String) -> Bool {
        ["md", "markdown", "mdown", "mkd"].contains((path as NSString).pathExtension.lowercased())
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    static func body(_ source: String) -> String { render(Document(parsing: source)) }

    private static func render(_ node: Markup) -> String {
        func children() -> String { node.children.map(render).joined() }
        switch node {
        case let text as Markdown.Text:
            return escape(text.string).replacingOccurrences(of: "==([^=\n]+)==", with: "<mark>$1</mark>", options: .regularExpression)
        case let heading as Heading:
            let anchor = heading.plainText.lowercased().replacingOccurrences(of: " ", with: "-")
            return "<h\(heading.level) id=\"\(escape(anchor))\">\(children())</h\(heading.level)>"
        case is Paragraph: return "<p>\(children())</p>"
        case is Strong: return "<strong>\(children())</strong>"
        case is Emphasis: return "<em>\(children())</em>"
        case is Strikethrough: return "<del>\(children())</del>"
        case let code as InlineCode: return "<code>\(escape(code.code))</code>"
        case let code as CodeBlock:
            let language = code.language.map { "<div class=\"language\">\(escape($0))</div>" } ?? ""
            return "<div class=\"code-block\">\(language)<pre><code>\(highlight(code.code, language: code.language))</code></pre></div>"
        case is BlockQuote: return "<blockquote>\(children())</blockquote>"
        case is UnorderedList: return "<ul>\(children())</ul>"
        case let list as OrderedList: return "<ol start=\"\(list.startIndex)\">\(children())</ol>"
        case let item as ListItem:
            let checkbox = item.checkbox.map { "<input type=\"checkbox\" disabled\($0 == .checked ? " checked" : "")> " } ?? ""
            let taskClass = item.checkbox == nil ? "" : " class=\"task\""
            return "<li\(taskClass)>\(checkbox)\(children())</li>"
        case is ThematicBreak: return "<hr>"
        case is SoftBreak: return "\n"
        case is LineBreak: return "<br>"
        case let link as Markdown.Link:
            guard let destination = link.destination,
                  destination.hasPrefix("#") || ["https", "http", "mailto"].contains(URL(string: destination)?.scheme?.lowercased() ?? "") else {
                return children()
            }
            return "<a href=\"\(escape(destination))\">\(children())</a>"
        case let image as Markdown.Image:
            return "<span class=\"image-placeholder\">▧ \(escape(image.plainText))</span>"
        case let html as HTMLBlock: return "<pre>\(escape(html.rawHTML))</pre>"
        case let html as InlineHTML: return escape(html.rawHTML)
        case let table as Table:
            func row(_ cells: MarkupChildren, tag: String) -> String {
                "<tr>" + cells.enumerated().map { index, cell in
                    let alignment = index < table.columnAlignments.count ? table.columnAlignments[index] : nil
                    let value: String
                    switch alignment { case .center: value = "center"; case .right: value = "right"; default: value = "left" }
                    return "<\(tag) style=\"text-align:\(value)\">\(cell.children.map(render).joined())</\(tag)>"
                }.joined() + "</tr>"
            }
            return "<div class=\"table-scroll\"><table><thead>\(row(table.head.children, tag: "th"))</thead><tbody>"
                + table.body.children.map { row($0.children, tag: "td") }.joined() + "</tbody></table></div>"
        default: return children()
        }
    }

    private static func highlight(_ source: String, language: String?) -> String {
        let aliases = ["javascript": "js", "typescript": "ts", "python": "py", "kotlin": "kt", "shell": "sh",
                       "bash": "sh", "c++": "cpp", "csharp": "cs", "objective-c": "m"]
        let name = language?.split(separator: " ").first.map(String.init)?.lowercased() ?? ""
        var lexer = SyntaxHighlighter(path: "code." + (aliases[name] ?? name))
        return source.components(separatedBy: "\n").map { line in
            let text = line as NSString
            var cursor = 0
            var output = ""
            for token in lexer.tokens(in: line) {
                output += escape(text.substring(with: NSRange(location: cursor, length: token.range.location - cursor)))
                let kind: String
                switch token.kind {
                case .keyword: kind = "keyword"
                case .string: kind = "string"
                case .comment: kind = "comment"
                case .number: kind = "number"
                case .type, .tag: kind = "type"
                case .function: kind = "function"
                case .bracket(let depth): kind = "bracket" + String(depth % 3)
                }
                output += "<span class=\"syntax-\(kind)\">\(escape(text.substring(with: token.range)))</span>"
                cursor = NSMaxRange(token.range)
            }
            return output + escape(text.substring(from: cursor))
        }.joined(separator: "\n")
    }

    static func document(body: String, fontSize: Double) -> String {
        let size = 16 * AppTypography.scale(for: fontSize)
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'none'; base-uri 'none'; form-action 'none'">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        :root{color-scheme:dark}*{box-sizing:border-box}html{background:#252626;color:#dcdee4}
        body{margin:0;font:\(size)px/1.8 -apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif;overflow-wrap:anywhere}
        article{max-width:980px;margin:0 auto;padding:32px 36px 80px}article>:first-child{margin-top:0}
        h1,h2,h3,h4,h5,h6{line-height:1.4;font-weight:700;margin:1.8em 0 .85em}
        h1{color:#d87580;font-size:2em}h2{color:#e9c777;font-size:1.55em}h3{color:#e9c777;font-size:1.25em}
        h4,h5,h6{color:#b8a2dc;font-size:1.1em}p{margin:.85em 0}strong{color:#e9c777;font-weight:650}
        a{color:#88c9dc;text-decoration:none}a:hover{text-decoration:underline}em{color:#c6b1e3}
        code{font: .9em/1.6 ui-monospace,SFMono-Regular,Menlo,monospace;color:#8bc8d5;background:#343b43;padding:.15em .38em;border-radius:4px;box-decoration-break:clone}
        .code-block{margin:1.3em 0;background:#202122;border:1px solid #3b3e42;border-radius:8px;overflow:hidden}
        .language{font-size:.75em;color:#a7abb5;padding:7px 16px;border-bottom:1px solid #36383b}
        pre{overflow:auto;padding:16px;line-height:1.65;white-space:pre;overflow-wrap:normal;margin:0}pre code{background:none;padding:0;color:#d2d6de}
        .syntax-keyword{color:#c78afa}.syntax-string{color:#edb87d}.syntax-comment{color:#7ba86b}.syntax-number{color:#91ccb5}
        .syntax-type{color:#66c2d9}.syntax-function{color:#dbd19c}.syntax-bracket0{color:#facf57}.syntax-bracket1{color:#b88ff0}.syntax-bracket2{color:#59baf7}
        ul,ol{padding-left:1.7em;margin:.8em 0}li{padding-left:.15em;margin:.3em 0}li>p{margin:.25em 0}li::marker{color:#a7abb5}
        li>ul,li>ol{margin:.2em 0}li.task{list-style:none}li.task>p:first-of-type{display:inline}input[type=checkbox]{accent-color:#88c9dc;margin-right:.4em}
        blockquote{border-left:3px solid #88c9dc;background:#2b3033;margin:1.2em 0;padding:.3em 1.1em;color:#bfc6cf;border-radius:0 6px 6px 0}
        hr{border:0;border-top:1px solid #484b50;margin:2em 0}mark{background:#655b36;color:#f4dda1;border-radius:3px;padding:.1em .2em}
        .table-scroll{overflow-x:auto;margin:1.4em 0}table{border-collapse:collapse;min-width:100%;font-size:.93em}
        th,td{border:1px solid #484b50;padding:10px 14px;min-width:90px;vertical-align:top}th{background:#303337;color:#e9c777;text-align:left}
        tr:nth-child(even){background:#2a2c2e}.image-placeholder{display:inline-block;color:#9299a6;border:1px dashed #555b64;padding:4px 10px;border-radius:4px}
        ::selection{background:#694754;color:#fff}@media(max-width:600px){article{padding:24px 20px 60px}}
        </style></head><body><article>\(body)</article></body></html>
        """
    }
}
