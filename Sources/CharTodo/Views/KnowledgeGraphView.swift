import SwiftUI

/// 회의록 지식그래프 보기. 노드를 누르면 연결된 회의·개체를 옆 패널에 보여 준다.
struct KnowledgeGraphView: View {
    enum Scope: String, CaseIterable {
        case entities, all
        var label: String { self == .entities ? "회의 ↔ 개체" : "전체 (안건·결정·할일 포함)" }
    }

    @Environment(\.theme) private var theme
    @Environment(MeetingStore.self) private var meetings
    @Binding var selectedNodeID: String?
    var onOpenMeeting: (UUID) -> Void

    @State private var scope: Scope = .entities
    @State private var hiddenKinds: Set<KGNodeKind> = []
    @State private var query = ""
    @State private var layout: [String: CGPoint] = [:]
    @State private var zoom: CGFloat = 1
    @State private var zoomStart: CGFloat?
    @State private var pan: CGSize = .zero
    @State private var panStart: CGSize?

    /// 너무 많으면 연결 많은 노드만 그린다
    private let maxNodes = 220

    var body: some View {
        let graph = meetings.graph
        let visible = visibleGraph(graph)
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 8) {
                toolbar
                if graph.isEmpty {
                    EmptyHint(text: "회의록을 넣고 AI 정리를 하면 지식그래프가 만들어져요", symbol: "point.3.connected.trianglepath.dotted")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .retroCard()
                } else {
                    canvas(graph, visible)
                        .retroCard(fill: theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius))
                }
            }
            sidePanel(graph)
                .frame(width: 260)
        }
        .task(id: visible.key) {
            let ids = visible.nodes.map(\.id), links = visible.links
            layout = await Task.detached(priority: .userInitiated) {
                GraphLayout.compute(ids: ids, links: links)
            }.value
        }
        .onAppear {
            // 밖에서 고른 노드가 지금 범위에 없으면 전체 보기로
            if let id = selectedNodeID, let n = graph.node(id), !n.kind.isEntity, n.kind != .meeting { scope = .all }
        }
    }

    // MARK: 보이는 부분

    private struct Visible {
        var nodes: [KGNode]
        var links: [(String, String)]
        var key: String
    }

    private func visibleGraph(_ g: KnowledgeGraph) -> Visible {
        var nodes = g.nodes.values.filter { n in
            (scope == .all || n.kind == .meeting || n.kind.isEntity) && !hiddenKinds.contains(n.kind)
        }
        if nodes.count > maxNodes {
            nodes = Array(nodes.sorted { (g.degree($0.id), $0.id) > (g.degree($1.id), $1.id) }.prefix(maxNodes))
        }
        nodes.sort { $0.id < $1.id }
        let ids = Set(nodes.map(\.id))
        var seen = Set<String>()
        var links: [(String, String)] = []
        for e in g.edges where ids.contains(e.source) && ids.contains(e.target) {
            let pair = e.source < e.target ? (e.source, e.target) : (e.target, e.source)
            if seen.insert(pair.0 + "|" + pair.1).inserted { links.append(pair) }
        }
        return Visible(nodes: nodes, links: links, key: "\(ids.sorted().joined(separator: ","))#\(links.count)")
    }

    // MARK: 도구 막대

    private var toolbar: some View {
        HStack(spacing: 8) {
            RetroSegmented(options: Scope.allCases, selection: $scope) { $0.label }
                .frame(width: 330)
            TextField("노드 찾기", text: $query)
                .retroField()
                .frame(maxWidth: 200)
                .onSubmit { selectFirstMatch() }
            Spacer()
            HStack(spacing: 2) {
                IconButton(symbol: "minus.magnifyingglass", help: "축소") { zoom = max(0.4, zoom / 1.25) }
                IconButton(symbol: "plus.magnifyingglass", help: "확대") { zoom = min(4, zoom * 1.25) }
                IconButton(symbol: "arrow.up.left.and.down.right.magnifyingglass", help: "화면에 맞추기") {
                    zoom = 1
                    pan = .zero
                }
            }
        }
    }

    // MARK: 그래프

    private func canvas(_ graph: KnowledgeGraph, _ visible: Visible) -> some View {
        let selected = selectedNodeID
        let neighborIDs = Set(selected.map { graph.neighbors(of: $0).map(\.node.id) } ?? [])
        let q = KnowledgeGraph.normalize(query)
        let showAllLabels = visible.nodes.count <= 70
        return GeometryReader { geo in
            let size = geo.size
            let place: (String) -> CGPoint? = { id in
                guard let p = layout[id] else { return nil }
                let inset: CGFloat = 46
                let base = CGPoint(x: inset + p.x * max(1, size.width - inset * 2), y: inset + p.y * max(1, size.height - inset * 2))
                return CGPoint(x: size.width / 2 + (base.x - size.width / 2) * zoom + pan.width,
                               y: size.height / 2 + (base.y - size.height / 2) * zoom + pan.height)
            }
            ZStack {
                Canvas { ctx, _ in
                    for (a, b) in visible.links {
                        guard let p1 = place(a), let p2 = place(b) else { continue }
                        let lit = selected != nil && (a == selected || b == selected)
                        var path = Path()
                        path.move(to: p1)
                        path.addLine(to: p2)
                        let color = lit ? theme.accent : theme.textMuted.opacity(selected == nil ? 0.35 : 0.12)
                        ctx.stroke(path, with: .color(color), lineWidth: lit ? 2 : 1)
                    }
                }
                ForEach(visible.nodes) { n in
                    if let p = place(n.id) {
                        let isSelected = n.id == selected
                        let matched = !q.isEmpty && KnowledgeGraph.normalize(n.label).contains(q)
                        let dim = (selected != nil && !isSelected && !neighborIDs.contains(n.id)) || (!q.isEmpty && !matched)
                        let showLabel = showAllLabels || isSelected || matched || neighborIDs.contains(n.id)
                            || n.kind == .meeting || graph.degree(n.id) >= 3
                        nodeView(n, graph: graph, selected: isSelected, highlighted: matched, showLabel: showLabel)
                            .opacity(dim ? 0.22 : 1)
                            .position(p)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { selectedNodeID = nil }
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { v in
                        if panStart == nil { panStart = pan }
                        pan = CGSize(width: panStart!.width + v.translation.width, height: panStart!.height + v.translation.height)
                    }
                    .onEnded { _ in panStart = nil }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { v in
                        if zoomStart == nil { zoomStart = zoom }
                        zoom = min(4, max(0.4, zoomStart! * v.magnification))
                    }
                    .onEnded { _ in zoomStart = nil }
            )
            .overlay(alignment: .bottomLeading) {
                Text("노드 \(visible.nodes.count) · 연결 \(visible.links.count)  —  드래그로 이동, 핀치로 확대")
                    .font(theme.font(10)).foregroundStyle(theme.textMuted)
                    .padding(8)
            }
        }
    }

    private func radius(_ n: KGNode, _ graph: KnowledgeGraph) -> CGFloat {
        switch n.kind {
        case .meeting: 10
        case _ where n.kind.isEntity: 5 + CGFloat(min(n.meetingIDs.count, 6)) * 1.5
        default: 4.5
        }
    }

    private func nodeView(_ n: KGNode, graph: KnowledgeGraph, selected: Bool, highlighted: Bool, showLabel: Bool) -> some View {
        let d = radius(n, graph) * 2
        let color = Color(hex: n.kind.hex) ?? theme.accent
        return Button { selectedNodeID = selected ? nil : n.id } label: {
            ZStack {
                Circle().fill(color)
                Circle().strokeBorder(selected || highlighted ? theme.text : theme.border.opacity(0.8),
                                      lineWidth: selected ? 2.5 : (highlighted ? 2 : 1))
                if n.kind == .meeting {
                    Image(systemName: "person.3.fill").font(.system(size: 7, weight: .bold)).foregroundStyle(.white)
                }
            }
            .frame(width: d, height: d)
            .overlay(alignment: .top) {
                if showLabel {
                    Text(n.label)
                        .font(theme.font(n.kind == .meeting ? 10.5 : 10, selected ? .heavy : .semibold))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                        .frame(maxWidth: 130)
                        .padding(.horizontal, 3)
                        .background(RoundedRectangle(cornerRadius: 3).fill(theme.surface.opacity(0.85)))
                        .fixedSize()
                        .offset(y: d + 2)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Circle().inset(by: -4))
        }
        .buttonStyle(.plain)
        .help("\(n.kind.label) · \(n.label)")
    }

    // MARK: 옆 패널

    @ViewBuilder private func sidePanel(_ graph: KnowledgeGraph) -> some View {
        if let id = selectedNodeID, let n = graph.node(id) {
            nodePanel(n, graph)
        } else {
            overviewPanel(graph)
        }
    }

    private func nodePanel(_ n: KGNode, _ graph: KnowledgeGraph) -> some View {
        let byID = Dictionary(uniqueKeysWithValues: meetings.meetings.map { ($0.id, $0) })
        let related = n.meetingIDs.compactMap { byID[$0] }.sorted { $0.date > $1.date }
        let neighbors = groupedNeighbors(of: n.id, graph: graph, meetingsByID: byID)
        return RetroWindow(n.kind.label, symbol: n.kind.symbol) {
            Button { selectedNodeID = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).font(.system(size: 11, weight: .bold))
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(n.label).font(theme.font(15, .heavy)).textSelection(.enabled)
                    if n.kind == .meeting, let m = related.first {
                        Button { onOpenMeeting(m.id) } label: { Label("회의록 열기", systemImage: "doc.text") }
                            .buttonStyle(.retro(.primary, compact: true))
                    } else {
                        Text("회의 \(related.count)건에 등장").font(theme.font(11.5, .bold)).foregroundStyle(theme.textMuted)
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(related) { m in
                                Button { onOpenMeeting(m.id) } label: {
                                    HStack(spacing: 6) {
                                        Text(DateFormatters.monthDay.string(from: m.date)).font(theme.font(10.5, .heavy))
                                            .frame(width: 36, alignment: .leading)
                                        Text(m.title).font(theme.font(11.5)).lineLimit(1)
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                                    }
                                    .foregroundStyle(theme.text)
                                    .padding(.vertical, 3)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if !neighbors.isEmpty {
                        Rectangle().fill(theme.border.opacity(0.3)).frame(height: 1)
                        Text("연결 \(neighbors.count)").font(theme.font(11.5, .bold)).foregroundStyle(theme.textMuted)
                        ForEach(neighbors.prefix(80)) { item in
                            Button { selectedNodeID = item.node.id } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Image(systemName: item.node.kind.symbol).font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(Color(hex: item.node.kind.hex) ?? theme.accent)
                                        .frame(width: 12)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.node.label).font(theme.font(11.5)).lineLimit(2)
                                        Text(item.detail).font(theme.font(9.5)).foregroundStyle(theme.textMuted)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .foregroundStyle(theme.text)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(10)
            }
        }
    }

    private struct NeighborRow: Identifiable {
        var node: KGNode
        var relations: [String] = []
        var dates: [Date] = []
        var id: String { node.id }
        /// "사용, 언급 · 9/22, 10/6"
        var detail: String {
            relations.joined(separator: ", ")
                + (dates.isEmpty ? "" : " · " + dates.map { DateFormatters.monthDay.string(from: $0) }.joined(separator: ", "))
        }
    }

    /// 같은 이웃이 여러 회의·관계로 이어져 있으면 한 줄로 묶는다
    private func groupedNeighbors(of id: String, graph: KnowledgeGraph, meetingsByID: [UUID: MeetingNote]) -> [NeighborRow] {
        var rows: [String: NeighborRow] = [:]
        for (edge, node) in graph.neighbors(of: id) where node.kind != .meeting {
            var row = rows[node.id] ?? NeighborRow(node: node)
            if !row.relations.contains(edge.relation) { row.relations.append(edge.relation) }
            if let d = meetingsByID[edge.meetingID]?.date, !row.dates.contains(d) { row.dates.append(d) }
            rows[node.id] = row
        }
        return rows.values
            .map { r in var r = r; r.dates.sort(); return r }
            .sorted { ($0.node.kind.rawValue, $0.node.label) < ($1.node.kind.rawValue, $1.node.label) }
    }

    private func overviewPanel(_ graph: KnowledgeGraph) -> some View {
        let entityCount = graph.nodes.values.filter(\.kind.isEntity).count
        return RetroWindow("지식그래프", symbol: "point.3.connected.trianglepath.dotted") {
            EmptyView()
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("회의 \(meetings.meetings.count) · 개체 \(entityCount) · 연결 \(graph.edges.count)")
                        .font(theme.font(12, .bold))
                    let hubs = graph.hubs()
                    if !hubs.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("여러 회의에 자주 나온 것").font(theme.font(11.5, .bold)).foregroundStyle(theme.textMuted)
                            ForEach(hubs) { n in
                                Button { selectedNodeID = n.id } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: n.kind.symbol).font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(Color(hex: n.kind.hex) ?? theme.accent).frame(width: 12)
                                        Text(n.label).font(theme.font(12)).lineLimit(1)
                                        Spacer(minLength: 0)
                                        Text("회의 \(n.meetingIDs.count)").font(theme.font(10, .bold)).foregroundStyle(theme.textMuted)
                                    }
                                    .foregroundStyle(theme.text)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("범례 (눌러서 숨기기)").font(theme.font(11.5, .bold)).foregroundStyle(theme.textMuted)
                        FlowLayout(spacing: 4) {
                            ForEach(KGNodeKind.allCases.filter { scope == .all || $0 == .meeting || $0.isEntity }) { k in
                                Button {
                                    if hiddenKinds.contains(k) { hiddenKinds.remove(k) } else { hiddenKinds.insert(k) }
                                } label: {
                                    Chip(text: k.label, symbol: k.symbol, color: Color(hex: k.hex))
                                        .opacity(hiddenKinds.contains(k) ? 0.35 : 1)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Text("노드를 누르면 어떤 회의에서 무엇과 이어졌는지 보여요. 질문봇(⌘J)은 이 연결을 따라 관련 회의를 찾아 답해요.")
                        .font(theme.font(11)).foregroundStyle(theme.textMuted)
                }
                .padding(10)
            }
        }
    }

    private func selectFirstMatch() {
        let q = KnowledgeGraph.normalize(query)
        guard !q.isEmpty else { return }
        let g = meetings.graph
        if let n = g.nodes.values.filter({ KnowledgeGraph.normalize($0.label).contains(q) })
            .max(by: { g.degree($0.id) < g.degree($1.id) }) {
            if !n.kind.isEntity && n.kind != .meeting { scope = .all }
            selectedNodeID = n.id
        }
    }
}
