import SwiftUI

/// 아이젠하워 매트릭스: 드래그로 사분면 이동
struct MatrixView: View {
    @Environment(\.theme) private var theme
    @Environment(TodoStore.self) private var store
    @Environment(ChatController.self) private var chat
    @Environment(FloatingController.self) private var floating

    @State private var range: MatrixRange = .week
    @State private var showDone = false
    @State private var tagFilter: String?

    var body: some View {
        let items = store.matrixItems(range: range)
            .filter { showDone || !$0.isDone }
            .filter { tagFilter == nil || $0.tags.contains(tagFilter!) }
        VStack(alignment: .leading, spacing: 14) {
            header.padding(.horizontal, 24)

            HStack(alignment: .top, spacing: 16) {
                unsortedTray(items.filter { $0.quadrant == nil })
                    .frame(width: 240)

                VStack(spacing: 4) {
                    HStack {
                        Spacer()
                        Label("긴급함", systemImage: "bolt.fill").font(theme.font(11, .heavy))
                        Spacer()
                        Label("덜 긴급", systemImage: "hourglass").font(theme.font(11, .heavy))
                        Spacer()
                    }
                    .foregroundStyle(theme.textMuted)
                    .padding(.leading, 24)

                    HStack(spacing: 6) {
                        VStack {
                            Spacer()
                            Text("중요함").font(theme.font(11, .heavy)).fixedSize().rotationEffect(.degrees(-90))
                            Spacer()
                            Text("덜 중요").font(theme.font(11, .heavy)).fixedSize().rotationEffect(.degrees(-90))
                            Spacer()
                        }
                        .foregroundStyle(theme.textMuted)
                        .frame(width: 18)

                        Grid(horizontalSpacing: 14, verticalSpacing: 14) {
                            GridRow {
                                QuadrantPanel(quadrant: .doFirst, items: items.filter { $0.quadrant == .doFirst }, tag: tagFilter)
                                QuadrantPanel(quadrant: .schedule, items: items.filter { $0.quadrant == .schedule }, tag: tagFilter)
                            }
                            GridRow {
                                QuadrantPanel(quadrant: .delegate, items: items.filter { $0.quadrant == .delegate }, tag: tagFilter)
                                QuadrantPanel(quadrant: .eliminate, items: items.filter { $0.quadrant == .eliminate }, tag: tagFilter)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("아이젠하워 매트릭스").font(theme.titleFont(28)).foregroundStyle(theme.text)
                Text("할일을 끌어다 사분면에 놓으세요 · 긴급도 × 중요도").font(theme.font(13, .bold)).foregroundStyle(theme.textMuted)
            }
            Spacer()
            Menu {
                Button("모든 태그") { tagFilter = nil }
                Divider()
                ForEach(store.allTags, id: \.self) { tag in
                    Button("#\(tag)") { tagFilter = tag }
                }
            } label: {
                Label(tagFilter.map { "#\($0)" } ?? "모든 태그", systemImage: "tag")
            }
            .frame(width: 130)
            .help("태그로 걸러 보기")
            Toggle("완료 포함", isOn: $showDone).toggleStyle(.switch).controlSize(.small)
                .font(theme.font(12, .bold))
            RetroSegmented(options: MatrixRange.allCases, selection: $range) { $0.label }
                .frame(width: 280)
            Button {
                floating.showChat()
                chat.briefing(.priorities)
            } label: {
                Label("AI 우선순위", systemImage: "wand.and.stars")
            }
            .buttonStyle(.retro(.primary, compact: true))
            .disabled(chat.isBusy)
        }
        .padding(.top, 16)
    }

    private func unsortedTray(_ items: [TodoItem]) -> some View {
        RetroWindow("미분류 \(items.count)", symbol: "tray.full.fill", tint: theme.textMuted) {
            EmptyView()
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if items.isEmpty { EmptyHint(text: "모두 분류했어요! 🎉") }
                    ForEach(items) { t in TodoRowView(todo: t, compact: true, showDate: true) }
                }
                .padding(8)
            }
            QuickAddBar(placeholder: "할일 추가", defaultDate: Date(), compact: true).padding(8)
        }
        .todoDropTarget { id in store.setQuadrant(id, nil) }
    }
}

struct QuadrantPanel: View {
    @Environment(\.theme) private var theme
    @Environment(TodoStore.self) private var store
    let quadrant: Quadrant
    let items: [TodoItem]
    var tag: String?
    @State private var targeted = false

    var body: some View {
        let color = theme.quadrantColor(quadrant)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: quadrant.symbol)
                Text("\(quadrant.shortLabel) · \(quadrant.title)").font(theme.font(13, .heavy))
                Text(quadrant.subtitle).font(theme.font(10.5, .bold)).opacity(0.85)
                Spacer()
                Text("\(items.count)").font(theme.font(12, .heavy))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(color)
            Rectangle().fill(theme.border).frame(height: theme.borderWidth)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if items.isEmpty {
                        Text(hint).font(theme.font(11.5)).foregroundStyle(theme.textMuted)
                            .frame(maxWidth: .infinity).padding(.vertical, 20)
                    }
                    ForEach(items) { t in TodoRowView(todo: t, compact: true, showDate: true, showQuadrant: false) }
                }
                .padding(8)
            }
            QuickAddBar(placeholder: "\(quadrant.title)에 추가", defaultDate: Date(), defaultQuadrant: quadrant,
                        defaultTags: tag.map { [$0] } ?? [], compact: true)
                .padding(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(targeted ? color.opacity(0.25) : color.opacity(theme.isDark ? 0.12 : 0.06))
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: theme.cornerRadius).strokeBorder(targeted ? color : theme.border, lineWidth: theme.borderWidth * (targeted ? 1.6 : 1)))
        .background(RoundedRectangle(cornerRadius: theme.cornerRadius).fill(theme.shadow).offset(x: theme.shadowOffset, y: theme.shadowOffset))
        .todoDropTarget(isTargeted: $targeted) { id in store.setQuadrant(id, quadrant) }
        .animation(.easeOut(duration: 0.12), value: targeted)
    }

    private var hint: String {
        switch quadrant {
        case .doFirst: "마감이 코앞인 중요한 일"
        case .schedule: "장기적으로 중요한 일 — 시간을 확보하세요"
        case .delegate: "급하지만 남이 해도 되는 일"
        case .eliminate: "과감히 버려도 되는 일"
        }
    }
}
