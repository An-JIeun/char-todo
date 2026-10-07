import Foundation

/// ~/Library/Application Support/CharTodo 아래 JSON 파일로 저장한다.
enum Persistence {
    static var baseURL: URL = {
        let fm = FileManager.default
        // 개발·스냅샷용: 데이터 폴더를 바꿔 실행할 수 있다.
        if let custom = ProcessInfo.processInfo.environment["CHARTODO_DATA_DIR"], !custom.isEmpty {
            let dir = URL(fileURLWithPath: custom, isDirectory: true)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = support.appendingPathComponent("CharTodo", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static var characterDir: URL {
        let dir = baseURL.appendingPathComponent("character", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var claudeWorkDir: URL {
        let dir = baseURL.appendingPathComponent("claude-workdir", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func url(_ name: String) -> URL { baseURL.appendingPathComponent(name) }

    static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        let url = url(name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            // 손상된 파일은 백업해 두고 새로 시작한다.
            let backup = url.deletingPathExtension().appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: url, to: backup)
            NSLog("CharTodo: failed to decode \(name): \(error)")
            return nil
        }
    }

    static func save<T: Encodable>(_ value: T, to name: String) {
        do {
            let data = try encoder.encode(value)
            try data.write(to: url(name), options: .atomic)
        } catch {
            NSLog("CharTodo: failed to save \(name): \(error)")
        }
    }
}

/// 연속 변경을 묶어서 한 번만 저장한다.
@MainActor
final class Debouncer {
    private var work: DispatchWorkItem?
    private let delay: TimeInterval

    init(delay: TimeInterval) { self.delay = delay }

    func schedule(_ action: @escaping () -> Void) {
        work?.cancel()
        let item = DispatchWorkItem(block: action)
        work = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    func flush(_ action: () -> Void) {
        work?.cancel()
        work = nil
        action()
    }
}
