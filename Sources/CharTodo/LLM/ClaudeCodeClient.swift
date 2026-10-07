import Foundation

/// 로컬에 설치된 Claude Code CLI를 헤드리스(`claude -p`)로 실행해 응답을 받아온다.
/// Claude 구독 로그인 상태를 그대로 쓰므로 별도 API 키가 필요 없다.
struct ClaudeCodeClient: LLMClient {
    var executable: String
    var model: String

    static func arguments(system: String, model: String) -> [String] {
        var args = [
            "-p",
            "--output-format", "stream-json",
            "--verbose",
            "--include-partial-messages",
            "--tools", "",                // 도구 없이 대화만
            "--no-session-persistence",
            "--setting-sources", "",      // 사용자 훅/플러그인 로딩 생략 → 빠른 시작
            "--strict-mcp-config",        // MCP 서버 연결 생략
            "--system-prompt", system,
        ]
        if !model.trimmed.isEmpty { args += ["--model", model.trimmed] }
        return args
    }

    /// CLI는 단발성이므로 이전 대화를 하나의 프롬프트로 펼친다.
    static func flatten(_ messages: [LLMMessage]) -> String {
        guard messages.count > 1, let last = messages.last else { return messages.last?.content ?? "" }
        var out = "[이전 대화]\n"
        for m in messages.dropLast() {
            out += (m.role == .user ? "사용자: " : "어시스턴트: ") + m.content + "\n\n"
        }
        out += "[현재 메시지]\n" + last.content
        return out
    }

    func stream(system: String, messages: [LLMMessage]) -> AsyncThrowingStream<String, Error> {
        let executable = executable
        let args = Self.arguments(system: system, model: model)
        let prompt = Self.flatten(messages)
        return AsyncThrowingStream { cont in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = args
            process.currentDirectoryURL = Persistence.claudeWorkDir
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = ClaudeCodeLocator.extendedPATH
            env["NO_COLOR"] = "1"
            process.environment = env

            let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = stderr

            do {
                try process.run()
            } catch {
                cont.finish(throwing: LLMError.process(error.localizedDescription))
                return
            }
            stdin.fileHandleForWriting.write(Data(prompt.utf8))
            try? stdin.fileHandleForWriting.close()

            let task = Task {
                var parser = ClaudeStreamParser()
                do {
                    for try await line in stdout.fileHandleForReading.bytes.lines {
                        try Task.checkCancellation()
                        for event in parser.consume(line) {
                            switch event {
                            case let .text(t): cont.yield(t)
                            case let .error(msg): throw LLMError.server(msg)
                            }
                        }
                    }
                    process.waitUntilExit()
                    if process.terminationStatus != 0 && !parser.didYield {
                        let err = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                        throw LLMError.process(err.trimmed.isEmpty ? "종료 코드 \(process.terminationStatus)" : err)
                    }
                    cont.finish()
                } catch is CancellationError {
                    cont.finish()
                } catch {
                    cont.finish(throwing: error)
                }
            }
            cont.onTermination = { _ in
                task.cancel()
                if process.isRunning { process.terminate() }
            }
        }
    }
}

/// `--output-format stream-json` 출력 파서 (순수 로직 → 테스트 가능)
struct ClaudeStreamParser {
    enum Event: Equatable { case text(String), error(String) }

    private(set) var didYield = false
    private var sawPartial = false

    mutating func consume(_ line: String) -> [Event] {
        guard let obj = HTTP.parseJSONObject(line), let type = obj["type"] as? String else { return [] }
        switch type {
        case "stream_event":
            guard let event = obj["event"] as? [String: Any], event["type"] as? String == "content_block_delta",
                  let delta = event["delta"] as? [String: Any], delta["type"] as? String == "text_delta",
                  let text = delta["text"] as? String else { return [] }
            sawPartial = true
            didYield = true
            return [.text(text)]
        case "assistant":
            // 부분 메시지를 지원하지 않는 버전 대비: 완성된 메시지 본문 사용
            guard !sawPartial, let message = obj["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]] else { return [] }
            let text = content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined()
            guard !text.isEmpty else { return [] }
            // 오류 메시지가 assistant 형태로 오는 경우는 result에서 처리
            if message["model"] as? String == "<synthetic>" { return [] }
            didYield = true
            return [.text(text)]
        case "result":
            if obj["is_error"] as? Bool == true {
                return [.error((obj["result"] as? String) ?? "Claude Code 응답 오류")]
            }
            if !didYield, let text = obj["result"] as? String, !text.isEmpty {
                didYield = true
                return [.text(text)]
            }
            return []
        default:
            return []
        }
    }
}

enum ClaudeCodeLocator {
    static var home: String { NSHomeDirectory() }

    static var extendedPATH: String {
        let extra = ["\(home)/.local/bin", "\(home)/.claude/local", "/opt/homebrew/bin", "/usr/local/bin",
                     "\(home)/.npm-global/bin", "\(home)/.bun/bin", "\(home)/.volta/bin"]
        let current = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        return (extra + [current]).joined(separator: ":")
    }

    private static var cachedShellPath: String??

    /// 사용자 지정 경로 → 잘 알려진 설치 위치 → 로그인 셸 `command -v claude` 순으로 찾는다.
    static func locate(custom: String) -> String? {
        let fm = FileManager.default
        let c = (custom.trimmed as NSString).expandingTildeInPath
        if !c.isEmpty { return fm.isExecutableFile(atPath: c) ? c : nil }
        for path in candidates where fm.isExecutableFile(atPath: path) { return path }
        if cachedShellPath == nil { cachedShellPath = .some(shellLookup()) }
        if let p = cachedShellPath ?? nil { return p }
        return desktopBundled()
    }

    static var candidates: [String] {
        ["\(home)/.local/bin/claude", "\(home)/.claude/local/claude", "/opt/homebrew/bin/claude",
         "/usr/local/bin/claude", "\(home)/.npm-global/bin/claude", "\(home)/.bun/bin/claude"]
    }

    private static func shellLookup() -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", "command -v claude"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        let s = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmed
        return s.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: s) ? s : nil
    }

    /// Claude 데스크톱 앱에 포함된 CLI (최후의 수단)
    private static func desktopBundled() -> String? {
        let root = URL(fileURLWithPath: "\(home)/Library/Application Support/Claude/claude-code")
        guard let versions = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return nil }
        for v in versions.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
            guard let builds = try? FileManager.default.contentsOfDirectory(at: v, includingPropertiesForKeys: nil) else { continue }
            for b in builds {
                let p = b.appendingPathComponent("claude.app/Contents/MacOS/claude").path
                if FileManager.default.isExecutableFile(atPath: p) { return p }
            }
        }
        return nil
    }

    static func resetCache() { cachedShellPath = nil }
}
