import SwiftUI
import AppKit

@main
struct CharTodoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let env = AppEnvironment.shared

    var body: some Scene {
        Window("CharTodo", id: "main") {
            EnvRoot(env: env) { MainView() }
                .frame(minWidth: 1040, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1220, height: 800)
        .commands { AppCommands(env: env) }

        Settings {
            EnvRoot(env: env) { SettingsView() }
                .frame(width: 820, height: 680)
        }

        MenuBarExtra {
            EnvRoot(env: env) { MenuBarView() }
        } label: {
            Image(systemName: "checklist")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppEnvironment.shared.start()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { MainActor.assumeIsolated { AppEnvironment.shared.openMainWindow() } }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppEnvironment.shared.shutdown() }
    }

    /// chartodo:// 링크
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            for url in urls { AppEnvironment.shared.handle(url: url) }
        }
    }
}

struct AppCommands: Commands {
    let env: AppEnvironment

    var body: some Commands {
        CommandMenu("브리핑") {
            Button("오늘 브리핑 받기") {
                env.floating.showChat()
                env.chat.briefing(.today)
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            Button("질문봇 열기/닫기") { env.floating.toggleChat() }
                .keyboardShortcut("j", modifiers: [.command])
            Divider()
            Button("캐릭터 보이기/숨기기") { env.floating.toggleCharacter() }
                .keyboardShortcut("k", modifiers: [.command, .shift])
        }
        CommandMenu("커리어") {
            Button("career-support 열기") { env.career.open(.jobs) }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Menu("화면 바로 가기") {
                ForEach(CareerPage.allCases) { page in
                    Button(page.title) { env.career.open(page) }
                }
            }
            Divider()
            Button("공고 마감 다시 읽기") { Task { await env.career.sync(manual: true) } }
            Button("취업 할일 모아보기") { env.handle(url: URL(string: "chartodo://career")!) }
            Button("커리어 연동 설정…") { env.openSettings(tab: SettingsTab.career.rawValue) }
        }
        CommandGroup(after: .sidebar) {
            ForEach(Array(AppSection.allCases.enumerated()), id: \.offset) { idx, section in
                Button(section.title) {
                    NotificationCenter.default.post(name: .navigateRequest, object: section.rawValue)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(idx + 1)")), modifiers: .command)
            }
        }
    }
}
