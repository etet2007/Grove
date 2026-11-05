import Foundation

/// Converts self-contained Android vectors to SVG. Never resolves project resources or entities.
enum VectorDrawablePreview {
    struct Unsupported: LocalizedError {
        let reason: String
        var errorDescription: String? { AppLocalization.text("矢量图无法预览：%@。请切换统一视图查看 XML。", reason) }
    }

    static func convert(_ data: Data) -> Result<String, Error>? {
        guard data.count <= 2_000_000 else { return nil }
        guard let source = String(data: data, encoding: .utf8) else { return nil }
        let looksLikeVector = source.range(of: #"<vector(?:\s|>)"#, options: .regularExpression) != nil
        guard !source.contains("<!DOCTYPE"), !source.contains("<!ENTITY") else {
            return looksLikeVector ? .failure(Unsupported(reason: AppLocalization.text("不支持 XML 实体声明"))) : nil
        }
        do {
            let document = try XMLDocument(data: data, options: [.nodeLoadExternalEntitiesNever])
            guard let root = document.rootElement(), root.name == "vector" else { return nil }
            return .success(try Converter().render(root))
        } catch {
            return looksLikeVector ? .failure(error is Unsupported ? error : Unsupported(reason: AppLocalization.text("XML 格式无效"))) : nil
        }
    }

    private final class Converter {
        private var nextID = 0
        private let android = "http://schemas.android.com/apk/res/android"

        private func value(_ node: XMLElement, _ name: String) -> String? {
            node.attribute(forLocalName: name, uri: android)?.stringValue
        }

        private func number(_ node: XMLElement, _ name: String, _ fallback: Double = 0) throws -> Double {
            guard let raw = value(node, name) else { return fallback }
            guard let value = Double(raw), value.isFinite else { throw unsupported(name) }
            return value
        }

        private func unsupported(_ name: String) -> Unsupported {
            Unsupported(reason: AppLocalization.text("不支持的属性或资源：%@", name))
        }

        private func escaped(_ value: String) -> String {
            value.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
        }

        private func color(_ raw: String) throws -> (String, Double) {
            guard raw.hasPrefix("#") else { throw unsupported(raw) }
            let hex = String(raw.dropFirst())
            guard [3, 4, 6, 8].contains(hex.count), hex.allSatisfy({ $0.isHexDigit && $0.isASCII }) else { throw unsupported(raw) }
            let expanded = hex.count <= 4 ? hex.map { "\($0)\($0)" }.joined() : hex
            if expanded.count == 8 {
                return ("#" + String(expanded.suffix(6)), Double(Int(expanded.prefix(2), radix: 16)!) / 255)
            }
            return ("#" + expanded, 1)
        }

        func render(_ root: XMLElement) throws -> String {
            let width = try number(root, "viewportWidth"), height = try number(root, "viewportHeight")
            guard width > 0, height > 0 else { throw unsupported("viewportWidth / viewportHeight") }
            if value(root, "tint") != nil { throw unsupported("tint") }
            // Android scales the viewport to the intrinsic drawable bounds, even if their ratios differ.
            func dimension(_ name: String, fallback: Double) throws -> Double {
                guard let raw = value(root, name) else { return fallback }
                let numeric = raw.replacingOccurrences(of: #"(?:dp|dip|px)$"#, with: "", options: .regularExpression)
                guard let result = Double(numeric), result.isFinite, result > 0 else { throw unsupported(name) }
                return result
            }
            let intrinsicWidth = try dimension("width", fallback: width)
            let intrinsicHeight = try dimension("height", fallback: height)
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(intrinsicWidth)\" height=\"\(intrinsicHeight)\" viewBox=\"0 0 \(width) \(height)\" preserveAspectRatio=\"none\"><g opacity=\"\(try number(root, "alpha", 1))\">\(try children(root))</g></svg>"
        }

        private func children(_ parent: XMLElement) throws -> String {
            var result = "", clips = 0
            for node in parent.children ?? [] {
                guard let element = node as? XMLElement else { continue }
                switch element.name {
                case "group":
                    let px = try number(element, "pivotX"), py = try number(element, "pivotY")
                    let tx = try number(element, "translateX"), ty = try number(element, "translateY")
                    let angle = try number(element, "rotation")
                    let sx = try number(element, "scaleX", 1), sy = try number(element, "scaleY", 1)
                    result += "<g transform=\"translate(\(tx + px) \(ty + py)) rotate(\(angle)) scale(\(sx) \(sy)) translate(\(-px) \(-py))\">\(try children(element))</g>"
                case "path": result += try path(element)
                case "clip-path":
                    nextID += 1
                    let id = "clip\(nextID)"
                    result += "<defs><clipPath id=\"\(id)\"><path d=\"\(try pathData(element))\" clip-rule=\"\(try fillRule(element))\"/></clipPath></defs><g clip-path=\"url(#\(id))\">"
                    clips += 1
                default: throw unsupported(element.name ?? "element")
                }
            }
            return result + String(repeating: "</g>", count: clips)
        }

        private func pathData(_ node: XMLElement) throws -> String {
            guard let data = value(node, "pathData"), !data.isEmpty else { throw unsupported("pathData") }
            // Android and SVG use the same path commands; escape attribute content regardless.
            guard data.range(of: #"^[MmZzLlHhVvCcSsQqTtAa0-9eE.,+\s-]+$"#, options: .regularExpression) != nil else { throw unsupported("pathData") }
            return escaped(data)
        }

        private func fillRule(_ node: XMLElement) throws -> String {
            switch value(node, "fillType") ?? "nonZero" {
            case "nonZero", "0": return "nonzero"
            case "evenOdd", "1": return "evenodd"
            default: throw unsupported("fillType")
            }
        }

        private func path(_ node: XMLElement) throws -> String {
            guard try number(node, "trimPathStart") == 0,
                  try number(node, "trimPathEnd", 1) == 1,
                  try number(node, "trimPathOffset") == 0 else { throw unsupported("trimPath") }
            var definitions = "", attributes = ""
            for (androidName, svgName) in [("fillColor", "fill"), ("strokeColor", "stroke")] {
                let gradients = (node.children ?? []).compactMap { $0 as? XMLElement }.filter {
                    $0.localName == "attr" && $0.uri == "http://schemas.android.com/aapt"
                        && $0.attribute(forName: "name")?.stringValue == "android:\(androidName)"
                }
                if let attr = gradients.first {
                    guard gradients.count == 1, let gradient = attr.children?.compactMap({ $0 as? XMLElement }).first,
                          gradient.name == "gradient" else { throw unsupported("aapt:attr") }
                    let (id, svg) = try gradientSVG(gradient)
                    definitions += svg
                    attributes += " \(svgName)=\"url(#\(id))\" \(svgName)-opacity=\"\(try number(node, svgName + "Alpha", 1))\""
                } else {
                    let (rgb, alpha) = try color(value(node, androidName) ?? "#00000000")
                    attributes += " \(svgName)=\"\(rgb)\" \(svgName)-opacity=\"\(alpha * (try number(node, svgName + "Alpha", 1)))\""
                }
            }
            for child in (node.children ?? []).compactMap({ $0 as? XMLElement }) {
                guard child.localName == "attr", child.uri == "http://schemas.android.com/aapt",
                      ["android:fillColor", "android:strokeColor"].contains(child.attribute(forName: "name")?.stringValue ?? "") else { throw unsupported(child.name ?? "element") }
            }
            attributes += " stroke-width=\"\(try number(node, "strokeWidth"))\" stroke-miterlimit=\"\(try number(node, "strokeMiterLimit", 4))\" fill-rule=\"\(try fillRule(node))\""
            for (key, svgKey, allowed, fallback) in [
                ("strokeLineCap", "stroke-linecap", ["butt", "round", "square"], "butt"),
                ("strokeLineJoin", "stroke-linejoin", ["miter", "round", "bevel"], "miter")
            ] {
                let raw = value(node, key) ?? fallback
                guard allowed.contains(raw) else { throw unsupported(key) }
                attributes += " \(svgKey)=\"\(raw)\""
            }
            return "<defs>\(definitions)</defs><path d=\"\(try pathData(node))\"\(attributes)/>"
        }

        private func gradientSVG(_ node: XMLElement) throws -> (String, String) {
            nextID += 1
            let id = "gradient\(nextID)"
            let type = value(node, "type") ?? "linear"
            let tag: String, geometry: String
            switch type {
            case "linear", "0":
                tag = "linearGradient"
                geometry = "x1=\"\(try number(node, "startX"))\" y1=\"\(try number(node, "startY"))\" x2=\"\(try number(node, "endX"))\" y2=\"\(try number(node, "endY"))\""
            case "radial", "1":
                tag = "radialGradient"
                let radius = try number(node, "gradientRadius")
                guard radius > 0 else { throw unsupported("gradientRadius") }
                geometry = "cx=\"\(try number(node, "centerX"))\" cy=\"\(try number(node, "centerY"))\" r=\"\(radius)\""
            default: throw unsupported("gradient type")
            }
            let spread: String
            switch value(node, "tileMode") ?? "clamp" {
            case "clamp", "0": spread = "pad"
            case "repeat", "1": spread = "repeat"
            case "mirror", "2": spread = "reflect"
            default: throw unsupported("tileMode")
            }
            var stops: [(Double, String)] = []
            for child in (node.children ?? []).compactMap({ $0 as? XMLElement }) {
                guard child.name == "item", let raw = value(child, "color") else { throw unsupported("gradient item") }
                stops.append((try number(child, "offset"), raw))
            }
            if stops.isEmpty {
                stops = [(0, value(node, "startColor") ?? "#00000000")]
                if let center = value(node, "centerColor") { stops.append((0.5, center)) }
                stops.append((1, value(node, "endColor") ?? "#00000000"))
            }
            var content = "", previous = -Double.infinity
            for (offset, raw) in stops {
                guard (0...1).contains(offset), offset >= previous else { throw unsupported("gradient offset") }
                previous = offset
                let (rgb, alpha) = try color(raw)
                content += "<stop offset=\"\(offset)\" stop-color=\"\(rgb)\" stop-opacity=\"\(alpha)\"/>"
            }
            return (id, "<\(tag) id=\"\(id)\" gradientUnits=\"userSpaceOnUse\" spreadMethod=\"\(spread)\" \(geometry)>\(content)</\(tag)>")
        }
    }
}
