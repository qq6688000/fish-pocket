import SwiftUI

/// Remote screens share one empty/error layout on every supported OS.
struct RemoteUnavailableView: View {
    private let label: AnyView
    private let detail: AnyView
    private let actions: AnyView

    init(_ title: LocalizedStringKey, systemImage: String, description: Text? = nil) {
        label = AnyView(Label(title, systemImage: systemImage))
        detail = AnyView(description)
        actions = AnyView(EmptyView())
    }

    init<LabelContent: View, Description: View, Actions: View>(
        @ViewBuilder label: () -> LabelContent,
        @ViewBuilder description: () -> Description,
        @ViewBuilder actions: () -> Actions
    ) {
        self.label = AnyView(label())
        detail = AnyView(description())
        self.actions = AnyView(actions())
    }

    static func search(text: String) -> Self {
        Self("没有搜索结果", systemImage: "magnifyingglass", description: Text("没有找到与「\(text)」匹配的内容。"))
    }

    var body: some View {
        VStack(spacing: 12) {
            label.font(.title3.weight(.semibold)).foregroundStyle(Palette.ink)
            detail.font(.subheadline).foregroundStyle(Palette.secondary)
            actions
        }
        .multilineTextAlignment(.center)
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum RemoteScrollBounce {
    case always, basedOnSize
}

extension View {
    @ViewBuilder
    func remoteScrollBounceBehavior(_ behavior: RemoteScrollBounce) -> some View {
        if #available(iOS 16.4, *) {
            switch behavior {
            case .always: scrollBounceBehavior(.always)
            case .basedOnSize: scrollBounceBehavior(.basedOnSize)
            }
        } else {
            // iOS 16.2/16.3 retain the platform's ordinary scroll bounce behavior.
            self
        }
    }

    @ViewBuilder
    func remoteBottomScrollAnchor() -> some View {
        if #available(iOS 17.0, *) {
            defaultScrollAnchor(.bottom)
        } else {
            self
        }
    }
}
