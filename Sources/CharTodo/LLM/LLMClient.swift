import Foundation

struct LLMMessage: Equatable {
    enum Role: String { case user, assistant }
    var role: Role
    var content: String
}

protocol LLMClient {
    /// 응답 텍스트 조각을 순서대로 흘려보낸다.
    func stream(system: String, messages: [LLMMessage]) -> AsyncThrowingStream<String, Error>
}

enum LLMError: LocalizedError {
    case missingKey(String)
    case missingModel
    case badURL(String)
    case http(Int, String)
    case server(String)
    case claudeNotFound
    case process(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case let .missingKey(name): "\(name) API 키가 없어요. 설정 > AI 에서 입력해 주세요."
        case .missingModel: "모델이 선택되지 않았어요. 설정 > AI 에서 모델을 골라 주세요."
        case let .badURL(u): "주소가 올바르지 않아요: \(u)"
        case let .http(code, body): "서버 오류 (\(code)): \(body.prefix(300))"
        case let .server(msg): msg
        case .claudeNotFound: "Claude Code CLI(claude)를 찾지 못했어요. 설치 후 `claude` 로 로그인하거나 설정에서 경로를 지정해 주세요."
        case let .process(msg): "Claude Code 실행 오류: \(msg.prefix(400))"
        case let .network(msg): msg
        }
    }
}

enum LLMClientFactory {
    static func make(_ config: LLMConfig) throws -> LLMClient {
        switch config.provider {
        case .ollama:
            guard !config.ollamaModel.trimmed.isEmpty else { throw LLMError.missingModel }
            return OllamaClient(baseURL: config.ollamaBaseURL, model: config.ollamaModel, maxTokens: config.maxTokens)
        case .openAICompatible:
            guard !config.openAIModel.trimmed.isEmpty else { throw LLMError.missingModel }
            return OpenAICompatibleClient(baseURL: config.openAIBaseURL, apiKey: KeychainStore.get(KeychainStore.openAIAccount),
                                          model: config.openAIModel, maxTokens: config.maxTokens)
        case .anthropic:
            guard let key = KeychainStore.get(KeychainStore.anthropicAccount), !key.isEmpty else {
                throw LLMError.missingKey("Anthropic")
            }
            return AnthropicClient(apiKey: key, model: config.anthropicModel, effort: config.anthropicEffort)
        case .claudeCode:
            guard let path = ClaudeCodeLocator.locate(custom: config.claudeCodePath) else { throw LLMError.claudeNotFound }
            return ClaudeCodeClient(executable: path, model: config.claudeCodeModel)
        }
    }
}

// MARK: - HTTP 공통

enum HTTP {
    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 300  // 로컬 모델은 첫 토큰까지 오래 걸릴 수 있다
        c.timeoutIntervalForResource = 900
        return URLSession(configuration: c)
    }()

    static func url(_ base: String, _ path: String) throws -> URL {
        var b = base.trimmed
        while b.hasSuffix("/") { b.removeLast() }
        guard let url = URL(string: b + path), url.scheme != nil else { throw LLMError.badURL(base) }
        return url
    }

    static func jsonRequest(_ url: URL, body: [String: Any], headers: [String: String] = [:]) throws -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    /// 스트리밍 요청 → 줄 단위 시퀀스. 2xx가 아니면 본문을 읽어 에러로 던진다.
    /// URLError를 원인과 해결 방법이 담긴 한국어 메시지로 바꾼다.
    static func friendly(_ error: Error, url: URL?) -> Error {
        guard let e = error as? URLError else { return error }
        let host = url?.host ?? "서버"
        let msg: String
        switch e.code {
        case .appTransportSecurityRequiresSecureConnection:
            msg = "보안 정책 때문에 http://\(host) 에 연결하지 못했어요. 최신 빌드로 다시 실행해 주세요."
        case .cannotConnectToHost:
            msg = "\(host) 에 연결할 수 없어요. 서버가 켜져 있는지, 포트가 맞는지 확인해 주세요.\n홈서버 Ollama라면 서버에서 OLLAMA_HOST=0.0.0.0 으로 실행해야 외부(다른 기기)에서 접속돼요."
        case .cannotFindHost, .dnsLookupFailed:
            msg = "\(host) 주소를 찾을 수 없어요. 서버 주소(도메인/IP)를 확인해 주세요."
        case .timedOut:
            msg = "\(host) 응답 시간이 초과됐어요. 네트워크 연결이나 방화벽/포트포워딩을 확인해 주세요."
        case .notConnectedToInternet, .networkConnectionLost:
            msg = "네트워크 연결이 끊겼어요. 인터넷/VPN 연결을 확인해 주세요."
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateNotYetValid:
            msg = "\(host) 의 HTTPS 인증서를 신뢰할 수 없어요. 자체 서명 인증서라면 http:// 주소로 접속해 보세요."
        case .cancelled:
            return CancellationError()
        default:
            msg = "네트워크 오류: \(e.localizedDescription)"
        }
        return LLMError.network(msg)
    }

    static func lines(_ request: URLRequest) async throws -> AsyncLineSequence<URLSession.AsyncBytes> {
        let bytes: URLSession.AsyncBytes, response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            throw friendly(error, url: request.url)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            var body = ""
            for try await line in bytes.lines {
                body += line
                if body.count > 2000 { break }
            }
            throw LLMError.http(http.statusCode, extractErrorMessage(body))
        }
        return bytes.lines
    }

    static func getJSON(_ url: URL, headers: [String: String] = [:]) async throws -> Any {
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw friendly(error, url: url)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LLMError.http(http.statusCode, extractErrorMessage(String(decoding: data, as: UTF8.self)))
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    static func extractErrorMessage(_ body: String) -> String {
        guard let data = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return body }
        if let err = obj["error"] as? [String: Any], let msg = err["message"] as? String { return msg }
        if let msg = obj["error"] as? String { return msg }
        if let msg = obj["message"] as? String { return msg }
        return body
    }

    static func parseJSONObject(_ s: String) -> [String: Any]? {
        guard let data = s.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

/// 비동기 작업을 AsyncThrowingStream으로 감싸고 취소를 전파한다.
func makeStream(_ body: @escaping @Sendable (AsyncThrowingStream<String, Error>.Continuation) async throws -> Void)
    -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            do {
                try await body(continuation)
                continuation.finish()
            } catch is CancellationError {
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}

// MARK: - 모델 목록

enum ModelLister {
    static func ollamaModels(baseURL: String) async throws -> [String] {
        let obj = try await HTTP.getJSON(try HTTP.url(baseURL, "/api/tags"))
        let models = (obj as? [String: Any])?["models"] as? [[String: Any]] ?? []
        return models.compactMap { $0["name"] as? String }.sorted()
    }

    static func openAIModels(baseURL: String, apiKey: String?) async throws -> [String] {
        var headers: [String: String] = [:]
        if let apiKey, !apiKey.isEmpty { headers["Authorization"] = "Bearer \(apiKey)" }
        let obj = try await HTTP.getJSON(try HTTP.url(baseURL, "/models"), headers: headers)
        let data = (obj as? [String: Any])?["data"] as? [[String: Any]] ?? []
        return data.compactMap { $0["id"] as? String }.sorted()
    }

    static func anthropicModels(apiKey: String) async throws -> [String] {
        let obj = try await HTTP.getJSON(URL(string: "https://api.anthropic.com/v1/models?limit=100")!,
                                         headers: ["x-api-key": apiKey, "anthropic-version": "2023-06-01"])
        let data = (obj as? [String: Any])?["data"] as? [[String: Any]] ?? []
        return data.compactMap { $0["id"] as? String }
    }
}
