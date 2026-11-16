import SwiftUI
import UniformTypeIdentifiers

/// Sending a file into a conversation without depending on the ＋ tray → system picker path,
/// which on iOS 16 presents once and is dropped while its host sheet is still dismissing.
///
/// Two ways in, both driven by the app's own UI: pick something already in the app's
/// Documents folder (visited through the engine, since `~/Documents` is where Files puts
/// what is dropped on the app), or import from anywhere else once — the copy stays in the
/// composer's upload folder, so it can be sent again from the transcript.
struct FileChooserSheet: View {
    @EnvironmentObject private var app: AppModel
    let composer: ComposerModel
    let onPick: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var entries: [DirectoryPickerListing.Entry] = []
    @State private var path: String = EnginePaths.documents
    @State private var stack: [String] = []
    @State private var loading = false
    @State private var failure: String?
    @State private var importing = false
    @State private var busy: String?

    var body: some View {
        NavigationStack {
            List {
                if let failure {
                    Section {
                        Text(failure).font(.footnote).foregroundStyle(Palette.removed)
                        Button("重试") { Task { await load() } }
                    }
                    .groupedRow()
                }
                if loading && entries.isEmpty {
                    Section { ProgressView() }.groupedRow()
                } else if entries.isEmpty {
                    Section {
                        Text("这个文件夹里没有文件。可以在「文件」App 的「我的 iPhone ▸ Fish Pocket」里放入文件，或用下面的「从其他位置导入」。")
                            .font(.footnote)
                            .foregroundStyle(Palette.secondary)
                    }
                    .groupedRow()
                } else {
                    Section {
                        ForEach(entries) { entry in row(entry) }
                    } header: {
                        Text((path as NSString).lastPathComponent)
                    }
                    .groupedRow()
                }
                if let previous = stack.last {
                    Section {
                        Button {
                            path = previous
                            stack.removeLast()
                            Task { await load() }
                        } label: {
                            Label("上一级", systemImage: "arrow.up.left")
                        }
                    }
                    .groupedRow()
                }
                Section {
                    Button { importing = true } label: {
                        Label("从其他位置导入", systemImage: "folder.badge.plus")
                    }
                    if let busy {
                        Text("正在添加 \(busy)…").font(.footnote).foregroundStyle(Palette.secondary)
                    }
                } footer: {
                    Text("导入的文件会复制一份到本机，之后随时能发送。")
                }
                .groupedRow()
            }
            .groupedList()
            .navigationTitle("添加文件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(loading)
                }
            }
            .task { await load() }
            .refreshable { await load() }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    Task { await stageFromPicker(url) }
                case .failure(let error):
                    if (error as NSError).code != NSUserCancelledError {
                        failure = String(localized: "导入失败：\(error.localizedDescription)")
                    }
                }
            }
        }
        .tint(Palette.ink)
    }

    @ViewBuilder
    private func row(_ entry: DirectoryPickerListing.Entry) -> some View {
        Button {
            if entry.isDirectory {
                stack.append(path)
                path = entry.path
                Task { await load() }
            } else {
                Task { await stage(entry.path) }
            }
        } label: {
            HStack {
                Label(entry.name, systemImage: entry.isDirectory ? "folder" : icon(entry.name))
                    .foregroundStyle(Palette.ink)
                Spacer()
                if entry.isDirectory {
                    Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Palette.secondary)
                }
            }
        }
        .disabled(busy != nil)
    }

    private func icon(_ name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "webp", "heic": return "photo"
        case "zip", "gz", "xz", "tar", "deb": return "shippingbox"
        case "md", "txt", "json", "yml", "yaml": return "doc.text"
        default: return "doc"
        }
    }

    private func load() async {
        loading = true
        failure = nil
        defer { loading = false }
        do {
            let value = try await app.client.call("directoryPicker/list", ["path": .string(path)])
            let listing = DirectoryPickerListing(value)
            if !listing.path.isEmpty { path = listing.path }
            entries = listing.entries
                .filter { $0.name != "." && $0.name != ".." }
                .sorted { lhs, rhs in
                    if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
        } catch {
            failure = describeFailure(error)
        }
    }

    /// A file the engine can read (in Documents or under it): copy it aside, then attach.
    private func stage(_ filePath: String) async {
        let name = (filePath as NSString).lastPathComponent
        busy = name
        defer { busy = nil }
        do {
            let data = try await readLocal(filePath)
            let copy = try stash(data, name: name)
            await MainActor.run { composer.addStagedFile(copy) }
            onPick()
            dismiss()
        } catch {
            failure = String(localized: "「\(name)」添加失败：\(describeFailure(error))")
        }
    }

    /// The engine lists paths inside the app's own container, which the app can read directly.
    private func readLocal(_ filePath: String) async throws -> Data {
        try await Task.detached(priority: .userInitiated) { try Data(contentsOf: URL(fileURLWithPath: filePath)) }.value
    }

    private func stageFromPicker(_ url: URL) async {
        busy = url.lastPathComponent
        defer { busy = nil }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try await Task.detached(priority: .userInitiated) { try Data(contentsOf: url) }.value
            let copy = try stash(data, name: url.lastPathComponent)
            await MainActor.run { composer.addStagedFile(copy) }
            onPick()
            dismiss()
        } catch {
            failure = String(localized: "「\(url.lastPathComponent)」读取失败：\(error.localizedDescription)")
        }
    }

    private func stash(_ data: Data, name: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("uploads/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = folder.appendingPathComponent(name)
        try data.write(to: copy)
        return copy
    }
}

/// `directoryPicker/list` as the chooser needs it: name, path and whether it is a folder.
struct DirectoryPickerListing {
    struct Entry: Identifiable {
        let name: String
        let path: String
        let isDirectory: Bool
        var id: String { path }
    }

    let path: String
    let entries: [Entry]

    init(_ json: JSON) {
        path = json["path"].string ?? ""
        entries = json["entries"].array.compactMap { entry in
            guard let name = entry["name"].string, let entryPath = entry["path"].string else { return nil }
            let isDirectory = entry["isDirectory"].bool ?? entry["directory"].bool ?? false
            return Entry(name: name, path: entryPath, isDirectory: isDirectory)
        }
    }
}
