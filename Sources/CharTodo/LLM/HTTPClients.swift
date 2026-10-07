import Foundation

/// Ollama 네이티브 API (/api/chat, NDJSON 스트리밍)
struct OllamaClient: LLMClient {
    var baseURL: String
    var model: String
    var maxTokens: Int

    func stream(system: String, messages: [LLMMessage]) -> AsyncThrowingStream<String, Error> {
        let baseURL = baseURL, model = model, maxTokens = maxTokens
        return makeStream { cont in
            var msgs: [[String: String]] = [["role": "system", "content": system]]
            msgs += messages.map { ["role": $0.role.rawValue, "content": $0.content] }
            let body: [String: Any] = [
                "model": model, "messages": msgs, "stream": true,
                "options": ["num_predict": maxTokens],
            ]
            let req = try HTTP.jsonRequest(try HTTP.url(baseURL, "/api/chat"), body: body)
            for try await line in try await HTTP.lines(req) {
                try Task.checkCancellation()
                guard let obj = HTTP.parseJSONObject(line) else { continue }
                if let err = obj["error"] as? String { throw LLMError.server(err) }
                if let msg = obj["message"] as? [String: Any], let text = msg["content"] as? String, !text.isEmpty {
                    cont.yield(text)
                }
                if obj["done"] as? Bool == true { break }
            }
        }
    }
}

/// OpenAI Chat Completions 호환 API (OpenAI, LM Studio, llama.cpp server, vLLM, OpenRouter …)
struct OpenAICompatibleClient: LLMClient {
    var baseURL: String
    var apiKey: String?
    var model: String
    var maxTokens: Int

    func stream(system: String, messages: [LLMMessage]) -> AsyncThrowingStream<String, Error> {
        let baseURL = baseURL, apiKey = apiKey, model = model, maxTokens = maxTokens
        return makeStream { cont in
            var msgs: [[String: String]] = [["role": "system", "content": system]]
            msgs += messages.map { ["role": $0.role.rawValue, "content": $0.content] }
            var body: [String: Any] = ["model": model, "messages": msgs, "stream": true]
            // 공식 OpenAI는 max_completion_tokens, 로컬 서버는 대부분 max_tokens를 쓴다.
            if baseURL.contains("api.openai.com") { body["max_completion_tokens"] = maxTokens } else { body["max_tokens"] = maxTokens }
            var headers: [String: String] = ["Accept": "text/event-stream"]
            if let apiKey, !apiKey.isEmpty { headers["Authorization"] = "Bearer \(apiKey)" }
            let req = try HTTP.jsonRequest(try HTTP.url(baseURL, "/chat/completions"), body: body, headers: headers)
            for try await line in try await HTTP.lines(req) {
                try Task.checkCancellation()
                guard line.hasPrefix("data:") else { continue }
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if payload == "[DONE]" { break }
                guard let obj = HTTP.parseJSONObject(payload) else { continue }
                if let err = obj["error"] as? [String: Any] { throw LLMError.server(err["message"] as? String ?? "알 수 없는 오류") }
                guard let choices = obj["choices"] as? [[String: Any]], let first = choices.first else { continue }
                if let delta = first["delta"] as? [String: Any], let text = delta["content"] as? String, !text.isEmpty {
                    cont.yield(text)
                }
            }
        }
    }
}

/// Anthropic Messages API (SSE 스트리밍)
struct AnthropicClient: LLMClient {
    var apiKey: String
    var model: String
    var effort: String

    /// 서버측 거절 폴백(fallbacks: "default")을 지원하는 모델
    static func supportsDefaultFallback(_ model: String) -> Bool {
        ["claude-opus-5-5", "claude-sonnet-5-5", "claude-fable-5-1", "claude-opus-5"].contains(model)
    }

    /// effort 파라미터를 받는 모델 (Haiku 4.5 등은 오류)
    static func supportsEffort(_ model: String) -> Bool {
        !(model.contains("haiku") || model.hasPrefix("claude-sonnet-4-5") || model.hasPrefix("claude-3"))
    }

    func requestBody(system: String, messages: [LLMMessage]) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "system": system,
            "stream": true,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
        ]
        if Self.supportsEffort(model), !effort.isEmpty {
            body["output_config"] = ["effort": effort]
        }
        if Self.supportsDefaultFallback(model) {
            body["fallbacks"] = "default"
        }
        return body
    }

    func stream(system: String, messages: [LLMMessage]) -> AsyncThrowingStream<String, Error> {
        let body = requestBody(system: system, messages: messages)
        let apiKey = apiKey, model = model
        return makeStream { cont in
            var headers = [
                "x-api-key": apiKey,
                "anthropic-version": "2023-06-01",
                "Accept": "text/event-stream",
            ]
            if AnthropicClient.supportsDefaultFallback(model) {
                headers["anthropic-beta"] = "server-side-fallback-2026-07-01"
            }
            let req = try HTTP.jsonRequest(URL(string: "https://api.anthropic.com/v1/messages")!, body: body, headers: headers)
            for try await line in try await HTTP.lines(req) {
                try Task.checkCancellation()
                guard line.hasPrefix("data:") else { continue }
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                guard let obj = HTTP.parseJSONObject(payload), let type = obj["type"] as? String else { continue }
                switch type {
                case "content_block_delta":
                    // thinking_delta 등은 무시하고 본문 텍스트만 흘려보낸다.
                    if let delta = obj["delta"] as? [String: Any], delta["type"] as? String == "text_delta",
                       let text = delta["text"] as? String {
                        cont.yield(text)
                    }
                case "message_delta":
                    if let delta = obj["delta"] as? [String: Any], delta["stop_reason"] as? String == "refusal" {
                        cont.yield("\n\n_(이 요청에는 답하기 어려워요.)_")
                    }
                case "error":
                    let msg = (obj["error"] as? [String: Any])?["message"] as? String ?? "알 수 없는 오류"
                    throw LLMError.server(msg)
                case "message_stop":
                    return
                default:
                    break
                }
            }
        }
    }
}
