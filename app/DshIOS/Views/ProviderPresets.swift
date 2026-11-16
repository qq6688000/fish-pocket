import Foundation

/// A subscription vendor reached from 模型 → 添加模型提供商 → 订阅账号.
///
/// None of the three publishes an OAuth authorization-code flow a third-party app could
/// complete, so there is nothing to redirect back into the app. Each does have a browser
/// sign-in, though, and the session cookie that sign-in leaves behind is the credential —
/// so the sheet runs the vendor's own sign-in page inside the app and reads that cookie
/// only after the page has reached the signed-in destination, never on the landing page.
struct ProviderPreset: Identifiable {
    let id: String
    let name: String
    /// `llm-pi-ai` protocol id: decides which request header carries the credential.
    let api: String
    let tokenLabel: String
    /// The vendor's sign-in page (not its home page — those only offer 下载/在线使用).
    let signInURL: URL
    /// A URL prefix the page must have reached for the sign-in to count. Chosen as a page
    /// only a signed-in session can see.
    let signedInPrefix: String
    /// Cookie names that carry the session, most specific first.
    let cookieNames: [String]
    /// The model route this vendor exposes, when it exposes one.
    let baseURL: String?
    /// Where an API key can be minted, when the vendor has a console.
    let keyPage: URL?
    let note: String

    static let all: [ProviderPreset] = [workbuddy, trae, raccoon]

    /// Tencent CodeBuddy / WorkBuddy. Its sign-in is OneID (WeChat, phone, QQ, mailbox, SSO),
    /// and its console mints a real API key — the one route of the three that can always
    /// answer a request.
    static let workbuddy = ProviderPreset(
        id: "workbuddy",
        name: "WorkBuddy",
        api: "anthropic-messages",
        tokenLabel: "API Key",
        signInURL: URL(string: "https://www.workbuddy.cn/login/?platform=website&state=2&product=workbuddy")!,
        signedInPrefix: "https://copilot.tencent.com",
        cookieNames: ["codebuddy_session", "session_2", "session", "oneid_token"],
        baseURL: "https://copilot.tencent.com",
        keyPage: URL(string: "https://copilot.tencent.com/profile/keys"),
        note: "可在应用内登录，登录后自动跳转到控制台并取回凭据。控制台也能直接生成 API Key，那个不会过期，更稳。"
    )

    /// Trae CN. Signed in through ByteDance Passport; the session lives in the
    /// `X-Cloudide-Session` cookie, and the token the IDE uses is `Cloud-IDE-JWT`.
    static let trae = ProviderPreset(
        id: "trae",
        name: "Trae CN",
        api: "openai-chat-completions",
        tokenLabel: "Cloud-IDE-JWT",
        signInURL: URL(string: "https://www.trae.cn/login")!,
        signedInPrefix: "https://www.trae.cn/dashboard",
        cookieNames: ["X-Cloudide-Session", "sessionid", "sid_ucp_v1"],
        baseURL: "https://trae-api-cn.mchost.guru/api/agent/v3",
        keyPage: nil,
        note: "可在应用内登录，进入工作台后取回会话凭据。Trae 未开放 API，模型调用走客户端专用接口，仍需客户端令牌才能对话。"
    )

    /// SenseTime Raccoon. SMS or WeChat sign-in on the web workspace; no developer API.
    static let raccoon = ProviderPreset(
        id: "raccoon",
        name: "小浣熊（商汤）",
        api: "openai-chat-completions",
        tokenLabel: "xhx_token",
        signInURL: URL(string: "https://www.xiaohuanxiong.com/login")!,
        signedInPrefix: "https://www.xiaohuanxiong.com/work",
        cookieNames: ["xhx_token", "raccoon_token"],
        baseURL: "https://xiaohuanxiong.com",
        keyPage: nil,
        note: "可在应用内登录，进入工作台后取回会话凭据。小浣熊没有对外开放的模型接口，凭据只对其自身网页有效。"
    )
}
