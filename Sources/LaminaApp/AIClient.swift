import Foundation
import LaminaCore
import Security

enum AIProvider: String, CaseIterable, Identifiable {
    case gemini, openai, claude, grok, deepseek, qwen, kimi, glm, doubao, custom
    var id: String { rawValue }

    var title: String {
        switch self {
        case .gemini: return "Gemini"
        case .openai: return "OpenAI"
        case .claude: return "Claude"
        case .grok: return "xAI Grok"
        case .deepseek: return "DeepSeek"
        case .qwen: return "通义千问"
        case .kimi: return "Kimi"
        case .glm: return "智谱 GLM"
        case .doubao: return "豆包"
        case .custom: return "自定义"
        }
    }

    /// Official SVG shipped in the app bundle. Nil when the vendor did not publish an SVG we could retrieve.
    var brandAsset: String? {
        switch self {
        case .gemini: return "gemini"
        case .openai: return "openai"
        case .claude: return "claude"
        case .deepseek: return "deepseek"
        default: return nil
        }
    }

    var monogram: String {
        switch self {
        case .gemini: return "Ge"
        case .openai: return "OA"
        case .claude: return "C"
        case .grok: return "x"
        case .deepseek: return "DS"
        case .qwen: return "千"
        case .kimi: return "K"
        case .glm: return "G"
        case .doubao: return "豆"
        case .custom: return "URL"
        }
    }

    var tint: (Double, Double, Double) {
        switch self {
        case .gemini: return (0.26, 0.45, 0.96)
        case .openai: return (0.09, 0.09, 0.10)
        case .claude: return (0.80, 0.42, 0.28)
        case .grok: return (0.12, 0.12, 0.12)
        case .deepseek: return (0.15, 0.39, 0.92)
        case .qwen: return (0.38, 0.27, 0.86)
        case .kimi: return (0.10, 0.55, 0.48)
        case .glm: return (0.18, 0.36, 0.85)
        case .doubao: return (0.20, 0.62, 0.38)
        case .custom: return (0.35, 0.35, 0.38)
        }
    }

    var defaultModel: String {
        switch self {
        case .gemini: return "gemini-2.5-flash"
        case .openai: return "gpt-4o-mini"
        case .claude: return "claude-sonnet-4-5"
        case .grok: return "grok-4"
        case .deepseek: return "deepseek-chat"
        case .qwen: return "qwen-plus"
        case .kimi: return "moonshot-v1-auto"
        case .glm: return "glm-4-flash"
        case .doubao: return "doubao-pro-32k"
        case .custom: return "gpt-4o-mini"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta"
        case .openai: return "https://api.openai.com/v1"
        case .claude: return "https://api.anthropic.com/v1"
        case .grok: return "https://api.x.ai/v1"
        case .deepseek: return "https://api.deepseek.com/v1"
        case .qwen: return "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .kimi: return "https://api.moonshot.cn/v1"
        case .glm: return "https://open.bigmodel.cn/api/paas/v4"
        case .doubao: return "https://ark.cn-beijing.volces.com/api/v3"
        case .custom: return "https://api.openai.com/v1"
        }
    }

    var usesAnthropic: Bool { self == .claude }
    var usesGemini: Bool { self == .gemini }
}

enum KeychainStore {
    static func save(account: String, secret: String) {
        let service = "app.moxian.lamina.ai"
        let data = Data(secret.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(insert as CFDictionary, nil)
    }

    static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.moxian.lamina.ai",
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let secret = String(data: data, encoding: .utf8) else { return nil }
        return secret
    }
}

struct AISettings {
    var provider: AIProvider
    var models: [String: String]
    var customBaseURL: String

    static let defaultsKey = "lamina.ai.settings"

    static func load() -> AISettings {
        let stored = UserDefaults.standard.dictionary(forKey: defaultsKey) ?? [:]
        let provider = AIProvider(rawValue: stored["provider"] as? String ?? "") ?? .gemini
        let models = stored["models"] as? [String: String] ?? [:]
        let custom = stored["customBaseURL"] as? String ?? AIProvider.custom.defaultBaseURL
        return AISettings(provider: provider, models: models, customBaseURL: custom)
    }

    func save() {
        UserDefaults.standard.set([
            "provider": provider.rawValue,
            "models": models,
            "customBaseURL": customBaseURL
        ], forKey: Self.defaultsKey)
    }

    func model(for provider: AIProvider) -> String {
        let value = models[provider.rawValue] ?? ""
        return value.isEmpty ? provider.defaultModel : value
    }

    func baseURL(for provider: AIProvider) -> String {
        if provider == .custom { return customBaseURL.isEmpty ? provider.defaultBaseURL : customBaseURL }
        return provider.defaultBaseURL
    }
}

enum AIClientError: LocalizedError {
    case missingKey
    case badStatus(Int, String)
    case empty

    var errorDescription: String? {
        switch self {
        case .missingKey: return "还没有这个服务的 API 密钥。密钥只写进登录钥匙串。"
        case .badStatus(let code, let body): return "请求失败（\(code)）。\(body)"
        case .empty: return "服务没有返回文本。"
        }
    }
}

enum AIClient {
    static func complete(settings: AISettings, prompt: String) async throws -> String {
        let provider = settings.provider
        guard let key = KeychainStore.load(account: provider.rawValue), !key.isEmpty else {
            throw AIClientError.missingKey
        }
        if provider.usesGemini {
            return try await gemini(base: settings.baseURL(for: provider), model: settings.model(for: provider), key: key, prompt: prompt)
        }
        if provider.usesAnthropic {
            return try await anthropic(base: settings.baseURL(for: provider), model: settings.model(for: provider), key: key, prompt: prompt)
        }
        return try await chat(base: settings.baseURL(for: provider), model: settings.model(for: provider), key: key, prompt: prompt)
    }

    private static func gemini(base: String, model: String, key: String, prompt: String) async throws -> String {
        let encoded = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
        guard let url = URL(string: "\(trim(base))/models/\(encoded):generateContent?key=\(key)") else {
            throw AIClientError.badStatus(0, "Gemini 地址无效")
        }
        let body: [String: Any] = ["contents": [["parts": [["text": prompt]]]]]
        let json = try await post(url, headers: ["Content-Type": "application/json"], body: body)
        let candidates = json["candidates"] as? [[String: Any]]
        let content = candidates?.first?["content"] as? [String: Any]
        let parts = content?["parts"] as? [[String: Any]]
        let text = parts?.compactMap { $0["text"] as? String }.joined() ?? ""
        if text.isEmpty { throw AIClientError.empty }
        return text
    }

    private static func anthropic(base: String, model: String, key: String, prompt: String) async throws -> String {
        guard let url = URL(string: "\(trim(base))/messages") else {
            throw AIClientError.badStatus(0, "Claude 地址无效")
        }
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "messages": [["role": "user", "content": prompt]]
        ]
        let json = try await post(url, headers: [
            "Content-Type": "application/json",
            "x-api-key": key,
            "anthropic-version": "2023-06-01"
        ], body: body)
        let content = json["content"] as? [[String: Any]]
        let text = content?.compactMap { $0["text"] as? String }.joined() ?? ""
        if text.isEmpty { throw AIClientError.empty }
        return text
    }

    private static func chat(base: String, model: String, key: String, prompt: String) async throws -> String {
        guard let url = URL(string: "\(trim(base))/chat/completions") else {
            throw AIClientError.badStatus(0, "接口地址无效")
        }
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": prompt]]
        ]
        let json = try await post(url, headers: [
            "Content-Type": "application/json",
            "Authorization": "Bearer \(key)"
        ], body: body)
        let choices = json["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        let text = message?["content"] as? String ?? ""
        if text.isEmpty { throw AIClientError.empty }
        return text
    }

    private static func post(_ url: URL, headers: [String: String], body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if !(200...299).contains(status) {
            let snippet = String(data: data.prefix(400), encoding: .utf8) ?? ""
            throw AIClientError.badStatus(status, snippet)
        }
        return object
    }

    private static func trim(_ base: String) -> String {
        base.hasSuffix("/") ? String(base.dropLast()) : base
    }
}
