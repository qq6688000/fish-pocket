import Foundation

/// A subscription vendor reached from 模型 → 添加模型提供商 → 订阅账号.
///
/// None of these three publishes an OAuth authorization-code flow a third-party app could
/// complete, so there is nothing to redirect back to the app. What each *does* have is a
/// browser sign-in that issues a session cookie; the sign-in sheet runs that page inside the
/// app and reads the cookie once the page is signed in. That cookie is then used as the
/// route's API key — the credential header follows from the protocol.
struct ProviderPreset: Identifiable {
    let id: String
    let name: String
    /// `llm-pi-ai` protocol id: decides where the credential goes.
    let api: String
    /// What an API key field is called for this vendor.
    let tokenLabel: String
    /// Where the in-app sign-in starts.
    let signInURL: URL
    /// Host prefix the page must reach before a cookie counts as signed in.
    let signedInPrefix: String
    /// Session cookie names, most specific first.
    let cookieNames: [String]
    /// The model API this vendor exposes, if any (`nil`: cookie only, no public route).
    let baseURL: String?
    /// Where the user creates an API key instead, if the vendor has one.
    let keyPage: URL?
    let note: String

    static let all: [ProviderPreset] = [workbuddy, trae, raccoon]

    /// Tencent CodeBuddy/WorkBuddy: OneID sign-in, and separately a personal console that
    /// mints a real API key — the only one of the three that can always serve a request.
    static let workbuddy = ProviderPreset(
        id: "workbuddy",
        name: "WorkBuddy",
        api: "anthropic-messages",
        tokenLabel: "API Key",
        signInURL: URL(string: "https://www.workbuddy.cn/login/?platform=website&state=2&product=workbuddy")!,
        signedInPrefix: "https://copilot.tencent.com",
        cookieNames: ["codebuddy_session", "session", "session_2", "oneid_token"],
        baseURL: "https://copilot.tencent.com",
        keyPage: URL(string: "https://copilot.tencent.com/profile/keys"),
        note: "可在应用内登录并带回会话凭据；也可直接到个人控制台生成 API Key，那个更稳、不会过期。"
    )

    /// Trae CN: ByteDance Passport sign-in. Its model routes are the IDE's own.
    static let trae = ProviderPreset(
        id: "trae",
        name: "Trae CN",
        api: "openai-chat-completions",
        tokenLabel: "Cloud-IDE-JWT",
        signInURL: URL(string: "https://www.trae.cn")!,
        signedInPrefix: "https://www.trae.cn",
        cookieNames: ["trae_session", "sessionid", "SessionID"],
        baseURL: "https://trae-api-cn.mchost.guru/api/agent/v3",
        keyPage: nil,
        note: "可在应用内登录并带回会话凭据。Trae 未开放 API，模型调用走客户端专用接口，可能需要客户端令牌。"
    )

    /// SenseTime Raccoon: SMS or WeChat sign-in on the web workspace.
    static let raccoon = ProviderPreset(
        id: "raccoon",
        name: "小浣熊（商汤）",
        api: "openai-chat-completions",
        tokenLabel: "xhx_token",
        signInURL: URL(string: "https://www.xiaohuanxiong.com/work")!,
        signedInPrefix: "https://www.xiaohuanxiong.com/work",
        cookieNames: ["xhx_token", "raccoon_token"],
        baseURL: "https://xiaohuanxiong.com",
        keyPage: nil,
        note: "可在应用内登录并带回会话凭据。小浣熊没有对外的模型接口，凭据只能用于其自身网页会话。"
    )
}
