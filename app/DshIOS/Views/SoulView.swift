import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// 「灵魂」: how the agent talks. Kept on the device and written into the engine's
/// user-global `AGENTS.md`, which `dsh-agent-instructions` loads into every session.
enum Soul {
    static let languageKey = "dsh.soul.language"
    static let toneKey = "dsh.soul.tone"
    static let personaKey = "dsh.soul.persona"

    static let automatic = "auto"
    static let chinese = "zh"
    static let english = "en"

    static let gentle = "gentle"
    static let direct = "direct"

    /// Marks the file as ours: an AGENTS.md without it is never overwritten.
    static let marker = "<!-- dsh-soul -->"

    static let defaultPersona = """
你是操作者的长期搭档，做工程、排障、写代码、查资料。

说话：先给结论，再给依据。不确定就直说不确定，不编造 API、路径、版本号或行号。
给代码时：完整、能跑，用他给的文件名、目录名和参数名；说明放在代码之后。
给方案时：先说清楚代价和风险，再给推荐选项；有更简单的做法就直说。
不做没被要求的推销，不复述他的话，不在每段结尾加总结。
"""

    static var fileURL: URL { EnginePaths.dshHome.appendingPathComponent("AGENTS.md") }

    static func document(persona: String, language: String, tone: String) -> String {
        var parts = [marker, "# 人格", persona.trimmingCharacters(in: .whitespacesAndNewlines)]
        switch language {
        case chinese: parts.append("## 语言\n始终用简体中文回答。")
        case english: parts.append("## 语言\nAlways answer in English.")
        default: parts.append("## 语言\n用用户所用语言回答；用户换语言时跟着换。")
        }
        switch tone {
        case direct: parts.append("## 语气\n直接、克制，不客套，不表演热情。")
        default: parts.append("## 语气\n语气温和，先讲结论再讲细节，不夸张。")
        }
        return parts.joined(separator: "\n\n") + "\n"
    }

    enum WriteError: LocalizedError {
        case foreignFile
        case emptyPersona

        var errorDescription: String? {
            switch self {
            case .foreignFile: "已有不是这里生成的 AGENTS.md，没有覆盖。"
            case .emptyPersona: "人格提示词是空的。"
            }
        }
    }

    static func write(persona: String, language: String, tone: String) throws {
        let trimmed = persona.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw WriteError.emptyPersona }
        let url = fileURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let existing = try? String(contentsOf: url, encoding: .utf8), !existing.hasPrefix(marker) {
            throw WriteError.foreignFile
        }
        try document(persona: trimmed, language: language, tone: tone)
            .write(to: url, atomically: true, encoding: .utf8)
        UserDefaults.standard.set(trimmed, forKey: personaKey)
    }

    static var persona: String {
        UserDefaults.standard.string(forKey: personaKey) ?? defaultPersona
    }
}

/// 设置 → 模型 → 灵魂.
struct SoulView: View {
    @AppStorage(Soul.languageKey) private var language = Soul.automatic
    @AppStorage(Soul.toneKey) private var tone = Soul.gentle
    @State private var persona = Soul.persona
    @State private var importing = false
    @State private var notice: String?
    @State private var failure: String?

    var body: some View {
        Form {
            Section {
                Picker("回复语言", selection: $language) {
                    Text("自动").tag(Soul.automatic)
                    Text("中文").tag(Soul.chinese)
                    Text("英文").tag(Soul.english)
                }
                Picker("语气", selection: $tone) {
                    Text("温和").tag(Soul.gentle)
                    Text("直接").tag(Soul.direct)
                }
            } header: {
                Text("风格")
            } footer: {
                Text("语气只有两档。语言影响每一轮的回复，自动跟随你说话的语言。")
            }
            .groupedRow()

            Section {
                TextEditor(text: $persona)
                    .font(.callout)
                    .frame(minHeight: 240)
                    .scrollContentBackground(.hidden)
            } header: {
                HStack {
                    Text("人格提示词")
                    Spacer()
                    Text("\(persona.count) 字")
                }
            } footer: {
                Text("写进引擎的用户级 AGENTS.md，每个新会话开始时加载。导入会替换当前内容。")
            }
            .groupedRow()

            Section {
                Button("从 md / txt 导入") { importing = true }
            } footer: {
                Text("支持 .md 和 .txt，UTF-8。导入会替换上面的内容，点右上角「保存」才写入。")
            }
            .groupedRow()
        }
        .groupedList()
        .navigationTitle("灵魂")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Palette.ink)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }.fontWeight(.semibold)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: Self.importTypes, allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                read(url)
            case .failure(let error):
                failure = error.localizedDescription
            }
        }
        .alert("已保存", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text("下次新会话开始生效；已经在跑的会话不受影响。")
        }
        .alert("保存失败", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
    }

    /// `.md` is its own type; `.plainText` alone does not offer it in the picker.
    private static var importTypes: [UTType] {
        var types: [UTType] = [.plainText, .text]
        if let markdown = UTType(filenameExtension: "md") { types.insert(markdown, at: 0) }
        return types
    }

    /// 选择器给的是 security-scoped URL：先整份拷进沙盒，再按 UTF-8 / UTF-16 / Latin-1 依次试。
    private func read(_ url: URL) {
        RunLog.note("导入人格文件 \(url.lastPathComponent)")
        do {
            let staged = try PickedFile.stage(url)
            guard let text = PickedFile.text(at: staged) else {
                RunLog.note("人格文件解码失败 \(url.lastPathComponent)")
                failure = String(localized: "读不了这个文件：请另存为 UTF-8 的 md / txt。")
                return
            }
            persona = text
            RunLog.note("人格文件导入成功，\(text.count) 字")
        } catch {
            RunLog.note("人格文件读取失败", error: error)
            failure = error.localizedDescription
        }
    }

    private func save() {
        do {
            try Soul.write(persona: persona, language: language, tone: tone)
            notice = "已保存"
        } catch {
            failure = error.localizedDescription
        }
    }
}
