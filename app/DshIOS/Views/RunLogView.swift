import SwiftUI
import UIKit

/// 设置 → 运行日志: one report to hand over when something breaks.
/// Device and build, engine state, the last error, and the tail of the engine's console log.
struct RunLogView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var engine: NodeEngine
    @State private var text = ""
    @State private var export: URL?

    var body: some View {
        ScrollView {
            Text(text.isEmpty ? String(localized: "正在收集…") : text)
                .font(.caption2.monospaced())
                .foregroundStyle(Palette.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .background(Palette.grouped)
        .navigationTitle("运行日志")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("刷新")
                if let export { ShareLink(item: export) }
            }
        }
        .task { refresh() }
    }

    private func refresh() {
        let body = report()
        text = body
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fish-pocket-运行日志.txt")
        try? body.write(to: url, atomically: true, encoding: .utf8)
        export = url
    }

    private func report() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        var lines: [String] = []
        lines.append("Fish Pocket \(version) (\(build))")
        lines.append("iOS \(UIDevice.current.systemVersion) · \(UIDevice.current.model)")
        lines.append("引擎：\(engine.phase)")
        if let since = engine.startedAt {
            lines.append("引擎启动：\(since.formatted(date: .abbreviated, time: .standard))")
        }
        if engine.stalled { lines.append("引擎：启动超时") }
        lines.append("设置可写：\(app.settings.writable)")
        if let error = app.lastError, !error.isEmpty { lines.append("最近错误：\(error)") }
        lines.append("")
        lines.append("---- App 日志 ----")
        lines.append(RunLog.isEmpty ? "（没有记录）" : RunLog.text)
        lines.append("")
        lines.append("---- 引擎日志（末尾 400 行）----")
        lines.append(tail(of: engine.logFile, lines: 400))
        return lines.joined(separator: "\n")
    }

    private func tail(of url: URL, lines limit: Int) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "（读不到日志文件）" }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let window: UInt64 = 256 * 1024
        let start = size > window ? size - window : 0
        try? handle.seek(toOffset: start)
        let data = (try? handle.readToEnd()) ?? Data()
        let text = String(decoding: data, as: UTF8.self)
        let all = text.split(separator: "\n", omittingEmptySubsequences: false)
        return all.suffix(limit).joined(separator: "\n")
    }
}
