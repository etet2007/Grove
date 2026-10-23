import SwiftUI

/// Layout is computed once for the loaded history, never separately for visible rows.
/// Empty slots stay in place until the rightmost lane ends, keeping long lines stable.
struct CommitGraph {
    struct Lane: Equatable {
        let hash: String
        let color: Int
    }
    struct Edge: Equatable {
        let from: Int
        let to: Int
        let color: Int
    }
    struct Row {
        let commit: Commit
        let lane: Int
        let color: Int
        let incoming: [Edge]
        let outgoing: [Edge]
    }
    let rows: [Row]
    let laneCount: Int

    struct Track: Identifiable {
        let id: Int
        let branches: [String]

        var title: String {
            branches.isEmpty ? AppLocalization.text("历史线 %d", id + 1) : branches.joined(separator: ", ")
        }
        var help: String {
            branches.isEmpty
                ? AppLocalization.text("这条历史线上没有可用的本地分支标签；分支可能已删除，或分支指向的提交不在当前历史中。")
                : AppLocalization.text("这条历史线上的本地分支引用：%@。颜色用于区分轨道，不表示所有提交只属于这些分支。", branches.joined(separator: ", "))
        }
    }

    let tracks: [Track]

    init(commits: [Commit]) {
        var lanes: [Lane?] = []
        var nextColor = 0
        var rows: [Row] = []
        var width = 1
        for commit in commits {
            let index: Int
            let hasIncoming = lanes.contains { $0?.hash == commit.hash }
            if let existing = lanes.firstIndex(where: { $0?.hash == commit.hash }) {
                index = existing
            } else {
                index = lanes.firstIndex(of: nil) ?? lanes.count
                if index == lanes.count { lanes.append(nil) }
                lanes[index] = Lane(hash: commit.hash, color: nextColor)
                nextColor += 1
            }
            let color = lanes[index]!.color
            let incoming = lanes.enumerated().compactMap { offset, lane in
                lane.map { Edge(from: offset, to: offset, color: $0.color) }
            }.filter { $0.from != index || hasIncoming }
            lanes[index] = nil
            var outgoing = lanes.enumerated().compactMap { offset, lane in
                lane.map { Edge(from: offset, to: offset, color: $0.color) }
            }
            for (parentIndex, hash) in commit.parents.enumerated() {
                let target: Int
                if let existing = lanes.firstIndex(where: { $0?.hash == hash }) {
                    target = existing
                } else {
                    target = lanes.firstIndex(of: nil) ?? lanes.count
                    if target == lanes.count { lanes.append(nil) }
                    lanes[target] = Lane(hash: hash, color: parentIndex == 0 ? color : nextColor)
                    if parentIndex != 0 { nextColor += 1 }
                }
                outgoing.append(Edge(from: index, to: target,
                                     color: parentIndex == 0 ? color : lanes[target]!.color))
            }
            width = max(width, lanes.count, index + 1)
            rows.append(Row(commit: commit, lane: index, color: color,
                            incoming: incoming, outgoing: outgoing))
            while lanes.last == .some(nil) { lanes.removeLast() }
        }
        self.rows = rows
        laneCount = width
        var branches: [Int: Set<String>] = [:]
        for row in rows {
            branches[row.color, default: []].formUnion(row.commit.branchNames)
            for edge in row.incoming + row.outgoing {
                if branches[edge.color] == nil { branches[edge.color] = [] }
            }
        }
        tracks = branches.keys.sorted().map { Track(id: $0, branches: branches[$0]!.sorted()) }
    }

    /// Restore each repository's Git topology after the combined timeline's date sort.
    /// Kahn ordering uses the original date order as the tie breaker for independent nodes.
    static func topologicalOrder(_ commits: [Commit]) -> [Commit] {
        let indices = Dictionary(uniqueKeysWithValues: commits.enumerated().map { ($0.element.hash, $0.offset) })
        var children = Array(repeating: 0, count: commits.count)
        for commit in commits {
            for parent in commit.parents {
                if let index = indices[parent] { children[index] += 1 }
            }
        }
        var ready = Set(children.indices.filter { children[$0] == 0 })
        var result: [Commit] = []
        while let index = ready.min() {
            ready.remove(index)
            let commit = commits[index]
            result.append(commit)
            for parent in commit.parents {
                if let parentIndex = indices[parent] {
                    children[parentIndex] -= 1
                    if children[parentIndex] == 0 { ready.insert(parentIndex) }
                }
            }
        }
        return result
    }
}

struct CommitGraphCell: View {
    let row: CommitGraph.Row
    let laneCount: Int
    let scale: CGFloat
    let tracks: [CommitGraph.Track]

    private static let colors: [Color] = [
        Color(red: 0.40, green: 0.62, blue: 0.94),
        Color(red: 0.49, green: 0.74, blue: 0.43),
        Color(red: 0.90, green: 0.71, blue: 0.33),
        Color(red: 0.88, green: 0.43, blue: 0.47),
        Color(red: 0.39, green: 0.75, blue: 0.77),
        Color(red: 0.75, green: 0.57, blue: 0.86)
    ]

    static func color(_ index: Int) -> Color {
        if index < colors.count { return colors[index] }
        return Color(hue: (Double(index) * 0.61803398875).truncatingRemainder(dividingBy: 1),
                     saturation: 0.48, brightness: 0.84)
    }

    var body: some View {
        Canvas { context, size in
            let middle = size.height / 2
            func x(_ lane: Int) -> CGFloat { (7 + CGFloat(lane) * 12) * scale }
            func draw(_ edge: CommitGraph.Edge, incoming: Bool) {
                var path = Path()
                let start = CGPoint(x: x(edge.from), y: incoming ? 0 : middle)
                let end = CGPoint(x: x(edge.to), y: incoming ? middle : size.height)
                path.move(to: start)
                path.addLine(to: end)
                context.stroke(path, with: .color(Self.color(edge.color)),
                               style: StrokeStyle(lineWidth: 1.5 * scale, lineCap: .round))
            }
            for edge in row.incoming { draw(edge, incoming: true) }
            for edge in row.outgoing { draw(edge, incoming: false) }
            let rect = CGRect(x: x(row.lane) - 3.5 * scale, y: middle - 3.5 * scale,
                              width: 7 * scale, height: 7 * scale)
            let node = row.commit.parents.count > 1 ? Path(rect) : Path(ellipseIn: rect)
            context.fill(node, with: .color(Self.color(row.color)))
        }
        .frame(width: CGFloat(laneCount * 12 + 2) * scale)
        .overlay {
            CommitGraphTooltip(row: row, tracks: tracks, scale: scale)
        }
        .accessibilityHidden(true)
    }
}

/// Shares drawing coordinates with the Canvas, including diagonal merge segments.
struct CommitGraphHitMap {
    struct Segment {
        let start: CGPoint
        let end: CGPoint
        let color: Int

        func distance(to point: CGPoint) -> CGFloat {
            let dx = end.x - start.x, dy = end.y - start.y
            let length = dx * dx + dy * dy
            let t = length == 0 ? 0 : min(1, max(0, ((point.x - start.x) * dx + (point.y - start.y) * dy) / length))
            return hypot(point.x - start.x - t * dx, point.y - start.y - t * dy)
        }

        var bounds: CGRect {
            CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                   width: abs(end.x - start.x), height: abs(end.y - start.y))
        }
    }
    let segments: [Segment]
    let node: CGPoint
    let nodeColor: Int
    let scale: CGFloat

    init(row: CommitGraph.Row, height: CGFloat, scale: CGFloat) {
        self.scale = scale
        let middle = height / 2
        func x(_ lane: Int) -> CGFloat { (7 + CGFloat(lane) * 12) * scale }
        node = CGPoint(x: x(row.lane), y: middle)
        nodeColor = row.color
        segments = row.incoming.map {
            Segment(start: CGPoint(x: x($0.from), y: 0),
                    end: CGPoint(x: x($0.to), y: middle), color: $0.color)
        } + row.outgoing.map {
            Segment(start: CGPoint(x: x($0.from), y: middle),
                    end: CGPoint(x: x($0.to), y: height), color: $0.color)
        }
    }

    func color(at point: CGPoint) -> Int? {
        // Prefer the commit node at a junction; elsewhere select the closest line.
        if hypot(point.x - node.x, point.y - node.y) <= 4 * scale { return nodeColor }
        guard let nearest = segments.min(by: { $0.distance(to: point) < $1.distance(to: point) }),
              nearest.distance(to: point) <= 3 * scale else { return nil }
        return nearest.color
    }
}

private struct CommitGraphTooltip: NSViewRepresentable {
    let row: CommitGraph.Row
    let tracks: [CommitGraph.Track]
    let scale: CGFloat

    func makeNSView(context: Context) -> TooltipView { TooltipView() }

    func updateNSView(_ view: TooltipView, context: Context) {
        view.row = row
        view.tracks = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        view.scale = scale
        view.installTooltips()
    }

    final class TooltipView: NSView, NSViewToolTipOwner {
        var row: CommitGraph.Row?
        var tracks: [Int: CommitGraph.Track] = [:]
        var scale: CGFloat = 1
        override var isFlipped: Bool { true }

        // Tooltips use AppKit's registered regions; clicks continue to the commit row.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            installTooltips()
        }

        func installTooltips() {
            removeAllToolTips()
            guard let row, bounds.height > 0 else { return }
            let map = CommitGraphHitMap(row: row, height: bounds.height, scale: scale)
            let regions = map.segments.map { $0.bounds.insetBy(dx: -3 * scale, dy: -3 * scale) }
                + [CGRect(x: map.node.x - 4 * scale, y: map.node.y - 4 * scale,
                          width: 8 * scale, height: 8 * scale)]
            for region in regions {
                let visible = region.intersection(bounds)
                if !visible.isEmpty { addToolTip(visible, owner: self, userData: nil) }
            }
        }

        func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag,
                  point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
            guard let row,
                  let color = CommitGraphHitMap(row: row, height: bounds.height, scale: scale).color(at: point),
                  let track = tracks[color] else { return "" }
            return track.branches.isEmpty ? "\(track.title)\n\(track.help)"
                : AppLocalization.text("本地分支：%@", track.branches.joined(separator: ", "))
        }
    }
}
