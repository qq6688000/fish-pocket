import Foundation

/// A subscription vendor the user already pays for, reached with a token from its own
/// client. Added from 模型 → 添加模型提供商 as a custom `llm-pi-ai` route: the address and
/// protocol are filled in, so only the token is left to paste. The credential header
/// follows from the protocol in pi-ai itself (`x-api-key` for anthropic-messages,
/// `Authorization: Bearer` otherwise), so no header is declared here.
struct ProviderPreset: Identifiable {
    let id: String
    let name: String
    let baseURL: String
    /// `llm-pi-ai` protocol id.
    let api: String
    /// Where the user gets a token, opened in Safari.
    let tokenPage: URL?
    let tokenLabel: String
    let tokenHint: String
    let note: String

    static let all: [ProviderPreset] = [workbuddy, trae, raccoon]

    /// Tencent's CodeBuddy/WorkBuddy: the personal console mints the key.
    static let workbuddy = ProviderPreset(
        id: "workbuddy",
        name: "WorkBuddy",
        baseURL: "https://copilot.tencent.com",
        api: "anthropic-messages",
        tokenPage: URL(string: "https://copilot.tencent.com/profile/keys"),
        tokenLabel: "API Key",
        tokenHint: "sk-…",
        note: "在 copilot.tencent.com 个人控制台生成 Key 后粘贴。地址与协议已填好；点“模型”可从服务端拉取列表，拉不到就手动填模型 id。"
    )

    /// Trae CN: the client's own Cloud-IDE-JWT.
    static let trae = ProviderPreset(
        id: "trae",
        name: "Trae CN",
        baseURL: "https://trae-api-cn.mchost.guru/api/agent/v3",
        api: "openai-chat-completions",
        tokenPage: URL(string: "https://www.trae.cn"),
        tokenLabel: "Cloud-IDE-JWT",
        tokenHint: "eyJhbGciOi…",
        note: "Trae 没有开放 API Key，只能填客户端令牌，过期后需重新获取。模型名请按客户端实际提供的填写。"
    )

    /// SenseTime's Raccoon: the web workspace's own session token.
    static let raccoon = ProviderPreset(
        id: "raccoon",
        name: "小浣熊（商汤）",
        baseURL: "https://xiaohuanxiong.com/api/web/b/v1",
        api: "openai-chat-completions",
        tokenPage: URL(string: "https://www.xiaohuanxiong.com/work"),
        tokenLabel: "xhx_token",
        tokenHint: "令牌",
        note: "小浣熊没有开放 Key，令牌需从登录后的网页会话取得，过期后需重新获取。模型名请按实际可用的填写。"
    )
}
