import SwiftUI
import SafariServices

/// WorkBuddy / WorkBuddy AI 订阅登录页。
///
/// 复刻 kwwk 的浏览器登录：请求官方登录页 → 在 App 内的 Safari 打开 →
/// 用户在官方页登录 → 后台每秒轮询 token 和 account → 拿到凭据后写进
/// `llm-pi-ai` 的 provider 配置。登录页与 DeepSeek 一样在系统 Safari，
/// 本 App 读不到密码，只拿访问令牌。
struct WorkBuddyLoginView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var site: WorkBuddySite = .china
    @State private var safari: SFSafariViewController?
    @State private var waiting = false
    @State private var message: String?
    @State private var failed: String?
    @State private var task: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("服务", selection: $site) {
                        Text("WorkBuddy（腾讯）").tag(WorkBuddySite.china)
                        Text("WorkBuddy AI（国际）").tag(WorkBuddySite.international)
                    }
                } header: {
                    Text("订阅服务")
                } footer: {
                    Text("腾讯 CodeBuddy 在 copilot.tencent.com，国际版 WorkBuddy AI 在 www.workbuddy.ai。两者的订阅、账号、模型互不相通。")
                }

                Section {
                    if waiting {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("等待在浏览器里登录……")
                        }
                    }
                    if let message {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }
                    if let failed {
                        Text(failed).font(.footnote).foregroundStyle(.red)
                    }
                } header: {
                    Text("登录")
                }

                Section {
                    Button {
                        start()
                    } label: {
                        if waiting { ProgressView().controlSize(.small) }
                        Text(waiting ? "登录中……" : "登录 \(site.displayName)")
                    }
                    .disabled(waiting)
                    if waiting {
                        Button("取消", role: .cancel) { cancel() }
                    }
                } footer: {
                    Text("登录在 \(site.displayName) 官方页面完成，本 App 读不到你的登录信息。登录成功后自动把该服务的模型写进「模型」页，开箱可用。")
                }
            }
            .navigationTitle("登录 WorkBuddy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
            .onDisappear { cancel() }
        }
    }

    private func start() {
        failed = nil
        message = nil
        waiting = true
        let site = self.site
        task = Task {
            do {
                let (state, url) = try await WorkBuddySignIn.requestState(site)
                guard !Task.isCancelled else { return }
                message = "登录页已打开，请在浏览器里完成登录……"
                openSafari(url)
                let credentials = try await WorkBuddySignIn.poll(site, state: state)
                guard !Task.isCancelled else { return }
                try await WorkBuddySignIn.apply(app.settings, site: site, credentials: credentials)
                Haptics.success()
                let open = safari?.presentingViewController != nil
                closeSafari()
                waiting = false
                if open { try? await Task.sleep(for: .milliseconds(450)) }
                dismiss()
            } catch {
                guard !Task.isCancelled else { return }
                waiting = false
                failed = error.localizedDescription
                Haptics.error()
            }
        }
    }

    private func cancel() {
        task?.cancel()
        task = nil
        waiting = false
        closeSafari()
    }

    private func openSafari(_ url: URL) {
        InAppSafari.close(safari)
        safari = InAppSafari.open(url)
    }

    private func closeSafari() {
        InAppSafari.close(safari)
        safari = nil
    }
}
