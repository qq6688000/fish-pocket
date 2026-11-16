import SwiftUI
import UIKit

/// 添加文件：一张系统文件浏览界面的宿主，直接把选中的文件交给调用方。
///
/// 用它而不用 `.fileImporter`，是因为后者在 iOS 16 上只能被呈现一次：宿主视图还在
/// 关闭动画里时呈现请求会被丢弃，而且不会重试 —— 从 ＋ 托盘进来的那一瞬间正是这样，
/// 于是「选完什么都没发生」。`UIDocumentPickerViewController` 由我们自己持有、自己呈现、
/// 自己接结果，失败与取消都能看得见。
struct DocumentPickerView: UIViewControllerRepresentable {
    /// 可以多选。
    var allowsMultiple = false
    let onPick: ([URL]) -> Void
    let onFail: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = allowsMultiple
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let owner: DocumentPickerView
        init(_ owner: DocumentPickerView) { self.owner = owner }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            owner.onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            owner.onFail("")
        }
    }
}
