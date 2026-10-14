import SwiftUI
import AppKit

// MARK: - 사이드바 바로 가기

/// 사이드바의 career-support 바로 가기 카드
struct CareerShortcutCard: View {
    @Environment(\.theme) private var theme
    @Environment(CareerSupportService.self) private var career

    var body: some View {
        if career.isAvailable {
            HStack(spacing: 6) {
                Button { career.open(.jobs) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: career.isLaunching ? "hourglass" : "briefcase.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(theme.accent)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("career-support").font(theme.font(12.5, .heavy)).foregroundStyle(theme.text)
                            Text(subtitle).font(theme.font(9.5, .bold)).foregroundStyle(soonCount > 0 ? theme.accent : theme.textMuted)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.forward.square").font(.system(size: 12, weight: .bold)).foregroundStyle(theme.textMuted)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("career-support 열기 (⌘⇧C) — 꺼져 있으면 켜서 열어요")

                Menu { CareerMenuItems() } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("화면 바로 가기")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .retroCard()
        }
    }

    /// 7일 안에 마감되는 (지원 전) 공고 수
    private var soonCount: Int {
        let limit = Date().startOfDay.adding(days: 7)
        return career.upcoming.filter { $0.deadline.date <= limit }.count
    }

    private var subtitle: String {
        if career.isLaunching { return "켜는 중…" }
        if soonCount > 0 { return "마감 7일 내 \(soonCount)건" }
        return career.jobs.isEmpty ? "공고 · 전략 · 현황 바로 가기" : "공고 \(career.jobs.count)건"
    }
}

/// 메뉴 공용: career-support 화면 바로 가기
struct CareerMenuItems: View {
    var body: some View {
        let env = AppEnvironment.shared
        ForEach(CareerPage.allCases) { page in
            Button { env.career.open(page) } label: { Label(page.title, systemImage: page.symbol) }
        }
        Divider()
        Button { Task { await env.career.sync(manual: true) } } label: {
            Label("공고 마감 다시 읽기", systemImage: "arrow.triangle.2.circlepath")
        }
        Button { env.handle(url: URL(string: "chartodo://career")!) } label: {
            Label("취업 할일 모아보기", systemImage: "tag")
        }
        Button { env.openSettings(tab: SettingsTab.career.rawValue) } label: {
            Label("커리어 연동 설정…", systemImage: "gearshape")
        }
    }
}

// MARK: - 설정 → 커리어

struct CareerSettings: View {
    @Environment(\.theme) private var theme
    @Environment(SettingsStore.self) private var store
    @Environment(CareerSupportService.self) private var career

    /// 마감을 할일로 가져올 수 있는 상태 (지원 전)
    private let importableStatuses = ["관심", "지원예정"]

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(title: "career-support 연결", symbol: "briefcase.fill") {
                Text("채용 공고 수집·지원 관리 툴 career-support의 공고(jobs.xlsx)를 읽어 마감일을 할일로 가져오고, 웹 화면을 바로 열어요. 서버가 꺼져 있어도 공고는 읽을 수 있어요.")
                    .font(theme.font(11.5)).foregroundStyle(theme.textMuted)
                SettingRow(label: "폴더", help: store.settings.career.path.isEmpty ? "자동으로 찾았어요" : "직접 지정함") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(career.root ?? "찾지 못했어요 — 폴더를 지정해 주세요")
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(career.root == nil ? theme.accent : theme.text)
                            .lineLimit(1).truncationMode(.middle)
                        HStack(spacing: 6) {
                            Button("폴더 선택…") { choosePath() }.buttonStyle(.retro(.secondary, compact: true))
                            if !store.settings.career.path.isEmpty {
                                Button("자동 탐색") { store.settings.career.path = "" }.buttonStyle(.retro(.ghost, compact: true))
                            }
                            if let root = career.root {
                                Button("Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: root)) }
                                    .buttonStyle(.retro(.ghost, compact: true))
                            }
                        }
                    }
                }
                SettingRow(label: "상태") {
                    VStack(alignment: .leading, spacing: 6) {
                        statusLine
                        HStack(spacing: 6) {
                            Button {
                                Task { await career.sync(manual: true) }
                            } label: {
                                Label(career.isSyncing ? "읽는 중…" : "지금 읽기", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .buttonStyle(.retro(.primary, compact: true))
                            .disabled(career.isSyncing || career.root == nil)
                            Button { career.open(.jobs) } label: {
                                Label(career.isLaunching ? "켜는 중…" : "웹 열기", systemImage: "arrow.up.forward.app")
                            }
                            .buttonStyle(.retro(.secondary, compact: true))
                            .disabled(career.isLaunching || career.root == nil)
                        }
                    }
                }
            }

            SettingsCard(title: "공고 마감 → 할일", symbol: "tray.and.arrow.down.fill") {
                SettingRow(label: "마감일을 할일로 가져오기", help: "jobs.xlsx가 바뀌면 1분 안에 따라와요") {
                    Toggle("", isOn: $store.settings.career.syncEnabled).toggleStyle(.switch).labelsHidden()
                }
                SettingRow(label: "가져올 공고", help: "career-support의 지원 상태 기준") {
                    HStack(spacing: 6) {
                        ForEach(importableStatuses, id: \.self) { status in
                            let on = store.settings.career.statuses.contains(status)
                            Button {
                                if on { store.settings.career.statuses.removeAll { $0 == status } }
                                else { store.settings.career.statuses.append(status) }
                            } label: {
                                Chip(text: status, symbol: on ? "checkmark" : nil, color: theme.accent, filled: on)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                SettingRow(label: "붙일 태그") {
                    TextField("취업", text: $store.settings.career.tag).retroField().frame(width: 160)
                }
                SettingRow(label: "지원하면 완료 처리", help: "career-support에서 상태를 지원완료·서류합격·면접… 으로 바꾸면 할일도 체크돼요") {
                    Toggle("", isOn: $store.settings.career.completeWhenApplied).toggleStyle(.switch).labelsHidden()
                }
                SettingRow(label: "가져온 기록", help: "지운 할일은 다시 만들지 않아요. 기록을 지우면 다시 가져와요") {
                    Text("\(store.settings.career.imported.count)건").font(theme.font(12, .bold))
                    if !store.settings.career.imported.isEmpty {
                        Button("기록 지우기") { career.resetImported() }.buttonStyle(.retro(.ghost, compact: true))
                    }
                }
                Text("할일 제목은 '회사 지원 — 포지션', 날짜는 마감일(시각이 있으면 시각까지), 사분면은 Q2 계획하기로 들어가요. 할일의 '공고' 칩을 누르면 공고 페이지가 열려요.")
                    .font(theme.font(10.5)).foregroundStyle(theme.textMuted)
            }

            if !career.jobs.isEmpty {
                SettingsCard(title: "다가오는 마감", symbol: "calendar.badge.exclamationmark") {
                    let upcoming = career.upcoming
                    if upcoming.isEmpty {
                        EmptyHint(text: "지원 전 공고 중 마감이 남은 게 없어요")
                    }
                    ForEach(upcoming.prefix(10), id: \.job.key) { item in
                        upcomingRow(item.job, item.deadline)
                    }
                    let noDeadline = career.jobs.filter { !$0.isApplied && CareerDeadline.parse($0.deadline) == nil }.count
                    if noDeadline > 0 {
                        Text("마감일이 없는(상시·채용시) 공고 \(noDeadline)건은 할일로 만들지 않아요.")
                            .font(theme.font(10.5)).foregroundStyle(theme.textMuted)
                    }
                }
            }

            SettingsCard(title: "바로 가기", symbol: "arrow.up.forward.app.fill") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                    ForEach(CareerPage.allCases) { page in
                        Button { career.open(page) } label: {
                            Label(page.title, systemImage: page.symbol).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.retro(.secondary, compact: true))
                        .disabled(career.root == nil)
                    }
                }
                SettingRow(label: "꺼져 있으면 자동으로 켜기", help: "백엔드(run.py)와 프론트(Vite)를 켠 뒤 열어요") {
                    Toggle("", isOn: $store.settings.career.autoStartServers).toggleStyle(.switch).labelsHidden()
                }
                SettingRow(label: "CharTodo 끌 때 같이 끄기", help: "CharTodo가 켠 서버만 꺼요") {
                    Toggle("", isOn: $store.settings.career.stopServersOnQuit).toggleStyle(.switch).labelsHidden()
                }
                HStack(spacing: 6) {
                    if career.ownsServers {
                        Button("켜 둔 서버 끄기") { career.stopLaunchedServers() }.buttonStyle(.retro(.secondary, compact: true))
                    }
                    Button("실행 로그 폴더") { NSWorkspace.shared.open(CareerSupportService.logDir) }
                        .buttonStyle(.retro(.ghost, compact: true))
                }
                Text("어디서든 ⌘⇧C 로 열 수 있고, 메뉴바·캐릭터 우클릭 메뉴에도 있어요. 반대로 career-support 웹 상단의 'CharTodo' 링크(chartodo://career)를 누르면 이 앱의 취업 할일로 바로 와요.")
                    .font(theme.font(10.5)).foregroundStyle(theme.textMuted)
            }
        }
    }

    @ViewBuilder private var statusLine: some View {
        if let error = career.lastError {
            Text(error).font(theme.font(11.5)).foregroundStyle(theme.accent).fixedSize(horizontal: false, vertical: true)
        } else if let message = career.lastMessage {
            HStack(spacing: 4) {
                Text(message)
                if let at = career.lastSyncAt { Text("· \(DateFormatters.time.string(from: at))").foregroundStyle(theme.textMuted) }
            }
            .font(theme.font(11.5)).foregroundStyle(theme.accent2)
        } else {
            Text(career.root == nil ? "연결 안 됨" : "아직 읽지 않았어요").font(theme.font(11.5)).foregroundStyle(theme.textMuted)
        }
    }

    private func upcomingRow(_ job: CareerJob, _ d: CareerDeadline) -> some View {
        let days = AppCalendar.current.dateComponents([.day], from: Date().startOfDay, to: d.date).day ?? 0
        return HStack(spacing: 8) {
            Text(days == 0 ? "D-day" : "D-\(days)")
                .font(theme.font(10.5, .heavy))
                .foregroundStyle(days <= 3 ? theme.accent : theme.textMuted)
                .frame(width: 42, alignment: .leading)
            Text(DateFormatters.monthDay.string(from: d.date) + (d.time.map { " " + DateFormatters.time.string(from: $0) } ?? ""))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .frame(width: 82, alignment: .leading)
            Text(job.todoTitle).font(theme.font(12)).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            Chip(text: job.status.isEmpty ? "관심" : job.status)
            if let url = URL(string: job.link), !job.link.isEmpty {
                IconButton(symbol: "link", help: "공고 열기", size: 10) { NSWorkspace.shared.open(url) }
            }
        }
    }

    private func choosePath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "career-support 저장소 폴더를 골라 주세요 (backend·frontend가 들어 있는 폴더)"
        if let root = career.root { panel.directoryURL = URL(fileURLWithPath: root) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.settings.career.path = url.path
    }
}
