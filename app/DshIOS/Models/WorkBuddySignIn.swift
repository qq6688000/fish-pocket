import Foundation
import Security

/// WorkBuddy / CodeBuddy 官方订阅接入。
///
/// 复刻 kwwk 的 `WorkBuddyOAuth`：WorkBuddy 的模型跑在一个 OpenAI 兼容端点
/// （`{endpoint}/v2/chat/completions`）下，账号用自己的 access token（JWT）
/// 认证，请求还要带 `X-User-Id` / `X-Domain`（企业账号再加 `X-Enterprise-Id`
/// / `X-Tenant-Id`）。登录走官方 web 页：先 `POST /v2/plugin/auth/state`
/// 拿登录页，用户在浏览器里登录，再每秒轮询 `token` 和 `account` 直到拿到
/// 凭据。全程不需要桌面 App、不需要第三方网关。
///
/// 登录成功后把凭据写成 `llm-pi-ai` 的一个 provider route（baseURL、api、
/// headers、models），并把它存进 `WORKBUDDY_API_KEY` / `WORKBUDDY_AI_API_KEY`
/// 凭据引用，DSH 的 `dsh-llm-pi-ai` 会把它注册为可配置 provider，开箱可用。
enum WorkBuddySite: Sendable, Hashable {
    /// 腾讯 CodeBuddy 的 China 版，在 copilot.tencent.com。
    case china
    /// WorkBuddy AI，国际版，在 www.workbuddy.ai。
    case international

    var route: String { self == .china ? "workbuddy-gateway" : "workbuddy-ai-gateway" }
    var displayName: String { self == .china ? "WorkBuddy" : "WorkBuddy AI" }
    var endpoint: String {
        self == .china ? "https://copilot.tencent.com" : "https://www.workbuddy.ai"
    }
    var platform: String { self == .china ? "workbuddy" : "workbuddy-ai" }
    /// Chats 的 API 根：`{endpoint}/v2`。
    var chatBaseURL: String { endpoint + "/v2" }
    /// 凭据引用名（环境变量），DSH 用它做 `Authorization: Bearer <access>`。
    var apiKeyEnv: String { self == .china ? "WORKBUDDY_API_KEY" : "WORKBUDDY_AI_API_KEY" }
    var host: String { URL(string: endpoint)?.host ?? "" }
}

/// WorkBuddy 登录拿到的凭据，外加请求要带的账号信息。
struct WorkBuddyCredentials: Sendable {
    var access: String
    var refresh: String
    var expiresAt: Date
    var uid: String
    var domain: String
    var accountName: String
    var enterpriseId: String?
}

/// WorkBuddy 登录 + 配置写入。纯逻辑；UI 侧负责打开 Safari 与显示进度。
@MainActor
enum WorkBuddySignIn {
    static let appVersion = "2.0.0"
    /// WorkBuddy 桌面版本号，请求以它发出；copilot.tencent.com 对不认识的
    /// User-Agent 会答业务码 10085。
    static let clientVersion = "5.5.6"
    static let userAgent = "WorkBuddy/\(clientVersion)"
    /// 登录页最多等这么久。
    static let signInWindow: TimeInterval = 5 * 60
    /// "还没就绪"的业务码：token 轮询 11217，account 轮询 12151。
    static let tokenPendingCode = 11217
    static let accountPendingCode = 12151
    /// access token 默认寿命一小时（端点没给时）。
    static let defaultLifetime: TimeInterval = 60 * 60

    /// WorkBuddy 的 JSON 请求头。
    private static let jsonHeaders = [
        "Content-Type": "application/json",
        "Accept": "application/json",
        "User-Agent": userAgent,
    ]

    /// WorkBuddy 的 `{code, msg, data}` 信封：code 0 成功，取 `data`。
    private struct Failure: Error, LocalizedError {
        let code: Int
        let status: Int
        let message: String
        var errorDescription: String? { message }
    }

    private enum SignInError: Error, LocalizedError {
        case invalidResponse(String)
        case timedOut
        case denied(String)
        var errorDescription: String? {
            switch self {
            case .invalidResponse(let text): text
            case .timedOut: "登录超时，请重试。"
            case .denied(let text): text
            }
        }
    }

    // MARK: - 第一步：请求登录页

    /// `POST /v2/plugin/auth/state?platform=` → `{state, authUrl}`，再把
    /// `version` 和 `loginSessionId` 拼进登录页。登录页在浏览器打开，用户
    /// 登录后 `poll` 才拿得到凭据。
    static func requestState(_ site: WorkBuddySite) async throws -> (state: String, authURL: URL) {
        let path = "/v2/plugin/auth/state?" + form(["platform": site.platform])
        let headers = [
            "X-No-Authorization": "true",
            "X-No-User-Id": "true",
            "X-No-Enterprise-Id": "true",
            "X-No-Department-Info": "true",
        ]
        let data = try await call(site, method: "POST", path: path, headers: headers, body: Data("{}".utf8))
        guard let payload = data as? [String: Any],
              let state = payload["state"] as? String, !state.isEmpty,
              var page = (payload["authUrl"] as? String).flatMap(URLComponents.init(string:)),
              page.scheme == "https" else {
            throw SignInError.invalidResponse("\(site.displayName) 没有给出登录页")
        }
        var items = page.queryItems ?? []
        items.removeAll { $0.name == "version" || $0.name == "loginSessionId" }
        items.append(URLQueryItem(name: "version", value: appVersion))
        items.append(URLQueryItem(name: "loginSessionId", value: randomHex(32)))
        page.queryItems = items
        guard let authURL = page.url else { throw SignInError.invalidResponse("\(site.displayName) 登录页地址无效") }
        return (state, authURL)
    }

    // MARK: - 第二步：轮询凭据

    /// 用户登录后每秒轮询 token 和 account，直到都拿到或超时。
    static func poll(_ site: WorkBuddySite, state: String) async throws -> WorkBuddyCredentials {
        let deadline = Date().addingTimeInterval(signInWindow)
        let query = form(["state": state])
        let token = try await pollValue(site, path: "/v2/plugin/auth/token?" + query,
                                        pendingCode: tokenPendingCode, deadline: deadline)
        guard let access = token["accessToken"] as? String, !access.isEmpty else {
            throw SignInError.invalidResponse("\(site.displayName) 没有给出 token")
        }
        let refresh = token["refreshToken"] as? String ?? ""
        let expiresAt = expiry(token, now: Date())
        var domain = (token["domain"] as? String).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        if domain.isEmpty { domain = site.host }

        let accountHeaders = [
            "Authorization": "Bearer \(access)",
            "X-Domain": domain,
            "X-No-User-Id": "true",
            "X-No-Enterprise-Id": "true",
        ]
        let account = try await pollValue(site, path: "/v2/plugin/login/account?" + query,
                                          pendingCode: accountPendingCode, deadline: deadline,
                                          headers: accountHeaders)
        guard let uid = account["uid"] as? String, !uid.isEmpty else {
            throw SignInError.invalidResponse("\(site.displayName) 没有给出账号")
        }
        let names = [account["nickname"], account["phoneNumber"]].compactMap { $0 as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let accountName = names.first { !$0.isEmpty } ?? uid
        let enterprise = await enterpriseId(site, account: account, bearer: access, domain: domain)
        return WorkBuddyCredentials(
            access: access, refresh: refresh, expiresAt: expiresAt, uid: uid,
            domain: domain, accountName: accountName,
            enterpriseId: enterprise.isEmpty ? nil : enterprise
        )
    }

    // MARK: - 第三步：写 provider 配置

    /// 把凭据写成 `llm-pi-ai providers.<route>`，并把 access token 存进
    /// `apiKeyEnv` 凭据。DSH 会把 route 注册为可配置 provider，开箱可用。
    static func apply(_ settings: SettingsMirror, site: WorkBuddySite, credentials: WorkBuddyCredentials) async throws {
        var headers: [String: String] = [
            "X-User-Id": credentials.uid,
            "X-Domain": credentials.domain,
            "User-Agent": userAgent,
            "Accept": "application/json",
        ]
        if let enterprise = credentials.enterpriseId {
            headers["X-Enterprise-Id"] = enterprise
            headers["X-Tenant-Id"] = enterprise
        }
        let profile: JSON = [
            "displayName": .string(site.displayName + " 账号"),
            "api": .string("openai-completions"),
            "baseURL": .string(site.chatBaseURL),
            "apiKeyEnv": .string(site.apiKeyEnv),
            "headers": .object(headers.mapValues { .string($0) }),
            "models": .array(WorkBuddyModels.all.map { $0.profile }),
        ]
        try await settings.set("llm-pi-ai", ["providers", site.route], profile)
        try await settings.setCredential(site.apiKeyEnv, credentials.access)
    }

    // MARK: - 刷新 token

    /// `POST /v2/plugin/auth/token/refresh`（`X-Refresh-Token` 头）换新
    /// access token，并写回凭据。过期后由调度调用。
    static func refresh(_ settings: SettingsMirror, site: WorkBuddySite, credentials: WorkBuddyCredentials) async throws {
        var headers = jsonHeaders
        headers["X-Refresh-Token"] = credentials.refresh
        headers["X-Auth-Refresh-Source"] = "plugin"
        headers["X-Domain"] = credentials.domain
        if let enterprise = credentials.enterpriseId {
            headers["X-Enterprise-Id"] = enterprise
            headers["X-Tenant-Id"] = enterprise
        }
        let data = try await call(site, method: "POST", path: "/v2/plugin/auth/token/refresh",
                                  headers: headers, body: Data("{}".utf8))
        guard let token = data as? [String: Any],
              let access = token["accessToken"] as? String, !access.isEmpty else {
            throw SignInError.invalidResponse("\(site.displayName) 没有给出新 token")
        }
        try await settings.setCredential(site.apiKeyEnv, access)
    }

    // MARK: - 内部

    /// 轮询一个 `{code,msg,data}` 端点直到 `data` 非空；WorkBuddy 的
    /// "还没就绪"码、408、429 都继续等，其余失败结束。
    private static func pollValue(_ site: WorkBuddySite, path: String, pendingCode: Int,
                                  deadline: Date, headers: [String: String] = [:]) async throws -> [String: Any] {
        var consecutiveErrors = 0
        while true {
            try Task.checkCancellation()
            if Date() > deadline { throw SignInError.timedOut }
            do {
                let data = try await call(site, method: "GET", path: path, headers: headers)
                consecutiveErrors = 0
                if let answer = data as? [String: Any], !answer.isEmpty { return answer }
            } catch let failure as Failure {
                consecutiveErrors = 0
                if failure.code == pendingCode || failure.status == 408 || failure.status == 429 {
                    try? await Task.sleep(for: .seconds(1))
                    continue
                }
                throw SignInError.denied("\(site.displayName): \(failure.message)")
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                consecutiveErrors += 1
                if consecutiveErrors >= 3 {
                    throw SignInError.denied("\(site.displayName) 登录轮询失败：\(error.localizedDescription)")
                }
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// 企业账号的 `enterpriseId`：账号自带，或查 `/v2/plugin/accounts`。
    private static func enterpriseId(_ site: WorkBuddySite, account: [String: Any],
                                     bearer: String, domain: String) async -> String {
        let own = trimmed(account["enterpriseId"])
        if !own.isEmpty { return own }
        let type = trimmed(account["type"]).lowercased()
        if type.isEmpty || type == "personal" { return "" }
        let headers = [
            "Authorization": "Bearer \(bearer)",
            "X-Domain": domain,
            "X-User-Id": trimmed(account["uid"]),
        ]
        guard let listed = try? await call(site, method: "GET", path: "/v2/plugin/accounts", headers: headers),
              let accounts = listed as? [String: Any] else { return "" }
        let mine = ((accounts["accounts"] as? [[String: Any]] ?? [])).filter {
            ($0["uid"] as? String) == (account["uid"] as? String) && !trimmed($0["enterpriseId"]).isEmpty
        }
        let sameType = mine.filter { trimmed($0["type"]).lowercased() == type }
        let pick = sameType.count == 1 ? sameType[0] : mine.first ?? [:]
        return trimmed(pick["enterpriseId"])
    }

    /// `{code,msg,data}`：code 0 返回 `data`，否则抛 `Failure`。
    private static func call(_ site: WorkBuddySite, method: String, path: String,
                             headers: [String: String] = [:], body: Data? = nil) async throws -> Any? {
        guard let url = URL(string: site.endpoint + path) else { throw SignInError.invalidResponse("地址无效") }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = method
        request.httpBody = body
        var all = jsonHeaders
        for (name, value) in headers { all[name] = value }
        request.allHTTPHeaderFields = all
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let envelope = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
        let code = (envelope["code"] as? Int) ?? ((envelope["code"] as? String).flatMap(Int.init)) ?? 0
        let message = envelope["msg"] as? String ?? ""
        if code != 0 {
            throw Failure(code: code, status: status, message: message.isEmpty ? "error \(code)" : message)
        }
        guard (200..<300).contains(status) else {
            throw Failure(code: 0, status: status, message: message.isEmpty ? "HTTP \(status)" : message)
        }
        let payload = envelope["data"]
        return (payload is NSNull) ? nil : payload
    }

    /// token 的到期时间：`expiresAt`（毫秒）、`expiresIn`（秒），或 JWT exp。
    private static func expiry(_ token: [String: Any], now: Date) -> Date {
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        if let at = int64(token["expiresAt"]), at > 0 { return Date(timeIntervalSince1970: Double(at) / 1000) }
        if let inSeconds = int64(token["expiresIn"]), inSeconds > 0 { return now.addingTimeInterval(Double(inSeconds)) }
        if let access = token["accessToken"] as? String, let exp = jwtExpiry(access) { return exp }
        return now.addingTimeInterval(defaultLifetime)
    }

    /// 从 JWT 的 `exp` 拿到期时间（秒）。
    private static func jwtExpiry(_ token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2, let data = Data(base64Encoded: base64Pad(String(parts[1]))) else { return nil }
        let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard let exp = int64(payload?["exp"]) else { return nil }
        return Date(timeIntervalSince1970: Double(exp))
    }

    private static func base64Pad(_ segment: String) -> String {
        var value = segment
        while value.count % 4 != 0 { value += "=" }
        return value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    }

    private static func int64(_ value: Any?) -> Int64? {
        switch value {
        case let number as Int: Int64(number)
        case let number as Int64: number
        case let number as Double: Int64(number)
        case let text as String: Int64(text)
        default: nil
        }
    }

    private static func trimmed(_ value: Any?) -> String {
        ((value as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `application/x-www-form-urlencoded` 查询串。
    private static func form(_ fields: [String: String]) -> String {
        fields.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0.value)" }
            .joined(separator: "&")
    }

    private static func randomHex(_ count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count / 2)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

/// WorkBuddy 的模型目录（来自 kwwk 的 workbuddy-models.json），转成 DSH
/// `llm-pi-ai` 的 `PiAiModelProfile`。
enum WorkBuddyModels {
    struct Model {
        let id: String
        let name: String
        let contextWindow: Int
        let reasoning: Bool
        /// 推理等级的 wire 拼写；`nil` 值表示该等级不可选。
        let efforts: [String: String?]?

        var profile: JSON {
            var object: [String: JSON] = [
                "id": .string(id),
                "name": .string(name),
                "contextWindow": .number(Double(contextWindow)),
                "input": .array([.string("text")]),
            ]
            if reasoning, let efforts {
                object["reasoningEfforts"] = .object(efforts.mapValues { value in
                    if let value { return .string(value) }
                    return .null
                })
            } else {
                object["reasoningEfforts"] = .bool(false)
            }
            return .object(object)
        }
    }

    static let all: [Model] = [
        Model(id: "auto", name: "Auto", contextWindow: 168_000, reasoning: false, efforts: nil),
        Model(id: "hy4-preview-f", name: "Hy4 preview", contextWindow: 1_000_000, reasoning: true, efforts: ["high": "high"]),
        Model(id: "hy3", name: "Hy3", contextWindow: 192_000, reasoning: true, efforts: ["high": "high", "low": "low"]),
        Model(id: "hy3-x", name: "Hy3-X", contextWindow: 192_000, reasoning: true, efforts: ["high": "high", "low": "low"]),
        Model(id: "deepseek-v4.1-flash", name: "Deepseek-V4.1-Flash", contextWindow: 1_000_000, reasoning: false, efforts: nil),
        Model(id: "glm-5.3", name: "GLM-5.3", contextWindow: 1_000_000, reasoning: true, efforts: ["high": "high", "low": "low", "max": "max"]),
        Model(id: "glm-5.3-flash", name: "GLM-5.3-Flash", contextWindow: 1_000_000, reasoning: true, efforts: ["high": "high", "low": "low", "max": "max"]),
        Model(id: "glm-5.2", name: "GLM-5.2", contextWindow: 1_000_000, reasoning: true, efforts: ["high": "high", "xhigh": "xhigh"]),
        Model(id: "glm-5.1", name: "GLM-5.1", contextWindow: 200_000, reasoning: false, efforts: nil),
        Model(id: "glm-5v-turbo", name: "GLM-5v-Turbo", contextWindow: 200_000, reasoning: false, efforts: nil),
        Model(id: "minimax-m3", name: "MiniMax-M3", contextWindow: 512_000, reasoning: false, efforts: nil),
        Model(id: "kimi-k3-1", name: "Kimi-K3", contextWindow: 1_000_000, reasoning: true, efforts: ["high": "high", "low": "low", "xhigh": "xhigh"]),
        Model(id: "kimi-k2.7", name: "Kimi-K2.7-Code", contextWindow: 256_000, reasoning: false, efforts: nil),
        Model(id: "kimi-k2.6", name: "Kimi-K2.6", contextWindow: 256_000, reasoning: false, efforts: nil),
        Model(id: "deepseek-v4-pro", name: "Deepseek-V4-Pro", contextWindow: 1_000_000, reasoning: true, efforts: ["high": "high", "xhigh": "xhigh", "off": "none"]),
    ]
}
