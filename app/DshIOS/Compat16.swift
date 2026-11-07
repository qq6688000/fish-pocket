//
//  Compat16.swift
//  fish-pocket — iOS 16.0 backports for the SwiftUI/UIKit APIs the app uses from later systems.
//
//  Names that would collide with an SDK declaration (`Animation.snappy`,
//  `View.onGeometryChange`) are renamed instead of shadowed. `ContentUnavailableView`
//  keeps its name: a type declared in the app module wins over the imported one.
//

import SwiftUI
import UIKit

// MARK: - Animation.smoothSpring  (was .snappy, iOS 17)

extension Animation {
    /// iOS 17's `.snappy`. Response 0.32 / damping 0.82 is the closest stable equivalent.
    static var smoothSpring: Animation { .spring(response: 0.32, dampingFraction: 0.82) }

    static func smoothSpring(duration: TimeInterval, extraBounce: Double = 0) -> Animation {
        .spring(response: duration, dampingFraction: max(0.6, 1.0 - extraBounce * 0.4))
    }
}

// MARK: - measureGeometry(for:of:action:)  (was onGeometryChange, iOS 18)

extension View {
    /// iOS 18's `onGeometryChange(for:of:action:)`. Same signature, `transform` gets a
    /// `GeometryProxy`, so `.frame(in: .named(...))` call sites work unchanged.
    func measureGeometry<T: Equatable>(
        for type: T.Type,
        of transform: @escaping (GeometryProxy) -> T,
        action: @escaping (T) -> Void
    ) -> some View {
        modifier(GeometryChangeModifier(transform: transform, action: action))
    }
}

struct GeometryChangeModifier<T: Equatable>: ViewModifier {
    let transform: (GeometryProxy) -> T
    let action: (T) -> Void

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: GeometryChangeKey<T>.self, value: transform(proxy))
                }
            )
            .onPreferenceChange(GeometryChangeKey<T>.self) { value in
                if let value { action(value) }
            }
    }
}

struct GeometryChangeKey<T: Equatable>: PreferenceKey {
    static var defaultValue: T? { nil }
    static func reduce(value: inout T?, nextValue: () -> T?) {
        if let next = nextValue() { value = next }
    }
}

// MARK: - ContentUnavailableView (iOS 17)

struct ContentUnavailableView<Title: View, Description: View, Actions: View>: View {
    @ViewBuilder var label: Title
    @ViewBuilder var description: Description
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 10) {
            label
                .font(.title2.weight(.semibold))
                .foregroundStyle(Palette.ink)
            description
                .font(.subheadline)
                .foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.center)
            if ObjectIdentifier(Actions.self) != ObjectIdentifier(EmptyView.self) {
                actions.padding(.top, 6)
            }
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

extension ContentUnavailableView where Title == SwiftUI.Label<Text, Image>,
    Description == EmptyView, Actions == EmptyView {
    init(_ title: LocalizedStringKey, systemImage: String) {
        self.init(
            label: { SwiftUI.Label(title, systemImage: systemImage) },
            description: { EmptyView() },
            actions: { EmptyView() }
        )
    }
}

extension ContentUnavailableView where Title == SwiftUI.Label<Text, Image>,
    Description == Text, Actions == EmptyView {
    init(_ title: LocalizedStringKey, systemImage: String, description: Text) {
        self.init(
            label: { SwiftUI.Label(title, systemImage: systemImage) },
            description: { description },
            actions: { EmptyView() }
        )
    }
}

extension ContentUnavailableView where Actions == EmptyView {
    /// `ContentUnavailableView { label } description: { … }`
    init(@ViewBuilder label: () -> Title, @ViewBuilder description: () -> Description) {
        self.init(label: label, description: description, actions: { EmptyView() })
    }
}

extension ContentUnavailableView where Description == EmptyView {
    /// `ContentUnavailableView { label } actions: { … }`
    init(@ViewBuilder label: () -> Title, @ViewBuilder actions: () -> Actions) {
        self.init(label: label, description: { EmptyView() }, actions: actions)
    }
}

extension ContentUnavailableView where Title == SwiftUI.Label<Text, Image>,
    Description == Text, Actions == EmptyView {
    static func search(text: String?)
        -> ContentUnavailableView<SwiftUI.Label<Text, Image>, Text, EmptyView> {
        let query = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ContentUnavailableView<SwiftUI.Label<Text, Image>, Text, EmptyView>(
            label: { SwiftUI.Label("无结果", systemImage: "magnifyingglass") },
            description: { Text(query.isEmpty ? "没有找到结果" : "没有找到「\(query)」") },
            actions: { EmptyView() }
        )
    }
}

// MARK: - Sheets: presentationCornerRadius / presentationBackground (iOS 16.4)

struct SheetAppearance: UIViewControllerRepresentable {
    var cornerRadius: CGFloat?
    var background: Color?

    func makeUIViewController(context: Context) -> Probe {
        let probe = Probe()
        probe.cornerRadius = cornerRadius
        probe.background = background.map { UIColor($0) }
        return probe
    }

    func updateUIViewController(_ probe: Probe, context: Context) {
        probe.cornerRadius = cornerRadius
        probe.background = background.map { UIColor($0) }
        probe.apply()
    }

    final class Probe: UIViewController {
        var cornerRadius: CGFloat?
        var background: UIColor?

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            apply()
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            apply()
        }

        func apply() {
            var current: UIViewController? = self
            while let vc = current {
                if let sheet = vc.presentationController as? UISheetPresentationController {
                    if let cornerRadius, sheet.preferredCornerRadius != cornerRadius {
                        sheet.preferredCornerRadius = cornerRadius
                    }
                    if let background, vc.view.backgroundColor != background {
                        vc.view.backgroundColor = background
                    }
                    return
                }
                current = vc.parent
            }
        }
    }
}

extension View {
    func sheetCornerRadius(_ radius: CGFloat) -> some View {
        background(SheetAppearance(cornerRadius: radius, background: nil))
    }

    func sheetBackground(_ color: Color) -> some View {
        background(SheetAppearance(cornerRadius: nil, background: color))
    }

    /// Was `.presentationBackgroundInteraction(.enabled)` (iOS 16.4). No public equivalent
    /// below 16.4 — it needs a custom UIPresentationController with a passthrough container.
    func sheetBackgroundTappable(_ enabled: Bool = true) -> some View { self }
}

// MARK: - Scroll: scrollBounceBehavior (iOS 16.4)

enum ScrollBounce16 {
    case automatic
    case always
    case basedOnSize
}

extension View {
    /// Was `.scrollBounceBehavior(...)`: `alwaysBounceVertical` on the enclosing UIScrollView.
    func scrollBounce(_ behavior: ScrollBounce16) -> some View {
        background(ScrollBounceProbe(behavior: behavior))
    }
}

struct ScrollBounceProbe: UIViewRepresentable {
    let behavior: ScrollBounce16

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.behavior = behavior
        return view
    }

    func updateUIView(_ view: ProbeView, context: Context) {
        view.behavior = behavior
        view.apply()
    }

    final class ProbeView: UIView {
        var behavior: ScrollBounce16 = .automatic

        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
            DispatchQueue.main.async { [weak self] in self?.apply() }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            apply()
        }

        func apply() {
            var current: UIView? = superview
            while let view = current {
                if let scroll = view as? UIScrollView {
                    switch behavior {
                    case .automatic: break
                    case .always:
                        if !scroll.alwaysBounceVertical { scroll.alwaysBounceVertical = true }
                    case .basedOnSize:
                        if scroll.alwaysBounceVertical { scroll.alwaysBounceVertical = false }
                    }
                    return
                }
                current = view.superview
            }
        }
    }
}

// MARK: - defaultScrollAnchor (iOS 17)

extension View {
    /// iOS 17's `defaultScrollAnchor`. Below 17 the scroll view opens at its natural offset.
    @ViewBuilder
    func scrollAnchor16(_ anchor: UnitPoint) -> some View {
        if #available(iOS 17.0, *) {
            defaultScrollAnchor(anchor)
        } else {
            self
        }
    }
}

// MARK: - toolbar(removing: .sidebarToggle) (iOS 17)

extension View {
    @ViewBuilder
    func hideSidebarToggle16() -> some View {
        if #available(iOS 17.0, *) {
            toolbar(removing: .sidebarToggle)
        } else {
            self
        }
    }
}

// MARK: - inspector (iOS 17): the iPad workbench column

struct WorkbenchInspector<Panel: View>: ViewModifier {
    @Binding var isPresented: Bool
    @ViewBuilder var panel: () -> Panel

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.inspector(isPresented: $isPresented) {
                panel().inspectorColumnWidth(min: 320, ideal: 420, max: 640)
            }
        } else {
            content.sheet(isPresented: $isPresented) {
                NavigationStack { panel() }
            }
        }
    }
}
