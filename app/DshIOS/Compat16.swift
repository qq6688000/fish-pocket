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
import Combine

// MARK: - Animation.smoothSpring  (was .snappy, iOS 17)

extension Animation {
    /// iOS 17's `.snappy`. Response 0.32 / damping 0.82 is the closest stable equivalent.
    static var smoothSpring: Animation {
        if #available(iOS 17.0, *) { return .snappy }
        return .spring(response: 0.32, dampingFraction: 0.82)
    }

    static func smoothSpring(duration: TimeInterval, extraBounce: Double = 0) -> Animation {
        if #available(iOS 17.0, *) { return .snappy(duration: duration, extraBounce: extraBounce) }
        return .spring(response: max(0.01, duration), dampingFraction: max(0.6, 1.0 - extraBounce * 0.4))
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
    @ViewBuilder
    func sheetCornerRadius(_ radius: CGFloat) -> some View {
        if #available(iOS 16.4, *) { presentationCornerRadius(radius) }
        else { background(SheetAppearance(cornerRadius: radius, background: nil)) }
    }

    @ViewBuilder
    func sheetBackground(_ color: Color) -> some View {
        if #available(iOS 16.4, *) { presentationBackground(color) }
        else { background(SheetAppearance(cornerRadius: nil, background: color)) }
    }

    /// UIKit's undimmed detent also permits touches through to the presenting page.
    @ViewBuilder
    func sheetBackgroundTappable(_ enabled: Bool = true) -> some View {
        if #available(iOS 16.4, *) {
            presentationBackgroundInteraction(enabled ? .enabled : .disabled)
        } else {
            background(SheetInteraction16(enabled: enabled))
        }
    }
}

// MARK: - Scroll: scrollBounceBehavior (iOS 16.4)

enum ScrollBounce16 {
    case automatic
    case always
    case basedOnSize
}

extension View {
    /// Was `.scrollBounceBehavior(...)`: `alwaysBounceVertical` on the enclosing UIScrollView.
    @ViewBuilder
    func scrollBounce(_ behavior: ScrollBounce16) -> some View {
        if #available(iOS 16.4, *) {
            switch behavior {
            case .automatic: scrollBounceBehavior(.automatic)
            case .always: scrollBounceBehavior(.always)
            case .basedOnSize: scrollBounceBehavior(.basedOnSize)
            }
        } else { background(CompatScrollProbe(bounce: behavior)) }
    }
}

// MARK: - defaultScrollAnchor (iOS 17)

extension View {
    /// iOS 16 uses the underlying scroll view to apply its initial content offset.
    @ViewBuilder
    func scrollAnchor16(_ anchor: UnitPoint) -> some View {
        if #available(iOS 17.0, *) {
            defaultScrollAnchor(anchor)
        } else {
            background(CompatScrollProbe(anchor: anchor))
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

// MARK: - Change observation (distinct name avoids iOS 17 overload resolution)
extension View {
    func compatOnChange<Value: Equatable>(of value: Value, initial: Bool = false,
                                          _ action: @escaping (Value, Value) -> Void) -> some View {
        modifier(CompatChangeModifier(value: value, initial: initial, action: action))
    }

    func compatOnChange<Value: Equatable>(of value: Value, initial: Bool = false,
                                          _ action: @escaping () -> Void) -> some View {
        compatOnChange(of: value, initial: initial) { _, _ in action() }
    }

    func compatOnChange<Value: Equatable>(of value: Value, initial: Bool = false,
                                          _ action: @escaping (Value) -> Void) -> some View {
        compatOnChange(of: value, initial: initial) { _, new in action(new) }
    }
}

private struct CompatChangeModifier<Value: Equatable>: ViewModifier {
    let value: Value
    let initial: Bool
    let action: (Value, Value) -> Void
    @State private var previous: Value

    init(value: Value, initial: Bool, action: @escaping (Value, Value) -> Void) {
        self.value = value
        self.initial = initial
        self.action = action
        _previous = State(initialValue: value)
    }

    func body(content: Content) -> some View {
        content.onAppear {
            previous = value
            if initial { action(value, value) }
        }.onChange(of: value) { new in
            let old = previous
            previous = new
            action(old, new)
        }
    }
}

// A lazily-created session/browser/terminal needs both stable storage and a subscription.
// @State<Object?> alone stores the reference but does not observe Combine changes.
@propertyWrapper
struct OptionalObservedObject<Object: ObservableObject>: DynamicProperty {
    @StateObject private var storage: Storage

    init(wrappedValue: Object? = nil) {
        _storage = StateObject(wrappedValue: Storage(wrappedValue))
    }

    var wrappedValue: Object? {
        get { storage.value }
        nonmutating set { storage.value = newValue }
    }

    var projectedValue: Binding<Object?> {
        Binding(get: { storage.value }, set: { storage.value = $0 })
    }

    final class Storage: ObservableObject {
        @Published var value: Object? {
            didSet { subscribe() }
        }
        private var subscription: AnyCancellable?

        init(_ value: Object?) {
            self.value = value
            subscribe()
        }

        private func subscribe() {
            subscription = value?.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
        }
    }
}

extension View {
    @ViewBuilder
    func symbolBounce16<Value: Equatable>(value: Value) -> some View {
        if #available(iOS 17.0, *) {
            symbolEffect(.bounce, value: value)
        } else {
            modifier(CompatSymbolBounce(value: value))
        }
    }

    @ViewBuilder
    func numericText16() -> some View {
        if #available(iOS 17.0, *) { contentTransition(.numericText()) }
        else { contentTransition(.opacity) }
    }

    func inspector16<Panel: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Panel) -> some View {
        modifier(WorkbenchInspector(isPresented: isPresented, panel: content))
    }

    @ViewBuilder
    func inspectorColumnWidth16(min: CGFloat, ideal: CGFloat, max: CGFloat) -> some View {
        if #available(iOS 17.0, *) { inspectorColumnWidth(min: min, ideal: ideal, max: max) }
        else { frame(minWidth: min, idealWidth: ideal, maxWidth: max) }
    }

    @ViewBuilder
    func scrollClipDisabled16() -> some View {
        if #available(iOS 17.0, *) { scrollClipDisabled() }
        else { background(CompatScrollProbe(clips: false)) }
    }

    @ViewBuilder
    func scrollIndicatorsFlash16(onAppear: Bool) -> some View {
        if #available(iOS 17.0, *) { scrollIndicatorsFlash(onAppear: onAppear) }
        else { background(CompatScrollProbe(flash: onAppear)) }
    }
}

private struct CompatSymbolBounce<Value: Equatable>: ViewModifier {
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var raised = false
    func body(content: Content) -> some View {
        content.offset(y: raised ? -5 : 0)
            .compatOnChange(of: value) { _, _ in
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 0.12)) { raised = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.45)) { raised = false }
                }
            }
    }
}

// MARK: - UIScrollView backports
struct CompatScrollMetrics: Equatable {
    var contentHeight: CGFloat
    var distance: CGFloat
}

/// Finds the SwiftUI scroll view without replacing its delegate, gestures, or data source.
/// KVO observes layout and scrolling, so live output follows only while the reader is at its end.
struct CompatScrollProbe: UIViewRepresentable {
    var anchor: UnitPoint? = nil
    var clips: Bool? = nil
    var flash = false
    var bounce: ScrollBounce16? = nil
    var metrics: ((CompatScrollMetrics) -> Void)? = nil

    func makeUIView(context: Context) -> Probe {
        let view = Probe()
        view.isUserInteractionEnabled = false
        view.configure(self)
        return view
    }

    func updateUIView(_ view: Probe, context: Context) { view.configure(self) }

    final class Probe: UIView {
        var config = CompatScrollProbe()
        weak var scroll: UIScrollView?
        var observations: [NSKeyValueObservation] = []
        var anchored = false
        var flashed = false
        var scheduled = false
        var lastMetrics: CompatScrollMetrics?

        func configure(_ config: CompatScrollProbe) {
            self.config = config
            schedule()
        }

        override func didMoveToWindow() { super.didMoveToWindow(); schedule() }
        override func layoutSubviews() { super.layoutSubviews(); schedule() }

        private func schedule() {
            guard !scheduled else { return }
            scheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.scheduled = false
                self.apply()
            }
        }

        private func resolve() -> UIScrollView? {
            var ancestor = superview
            // Prefer the containing scroll when the probe is in its content.
            while let view = ancestor {
                if let scroll = view as? UIScrollView { return scroll }
                ancestor = view.superview
            }
            // A background on ScrollView is a sibling of its UIKit scroll view.
            ancestor = superview
            for _ in 0..<5 {
                guard let view = ancestor else { break }
                var queue = view.subviews
                while !queue.isEmpty {
                    let child = queue.removeFirst()
                    if child === self { continue }
                    if let scroll = child as? UIScrollView { return scroll }
                    queue.append(contentsOf: child.subviews)
                }
                ancestor = view.superview
            }
            return nil
        }

        func apply() {
            guard window != nil, let found = scroll ?? resolve() else { return }
            if scroll !== found {
                scroll = found
                observations = [
                    found.observe(\.contentSize, options: [.new]) { [weak self] _, _ in self?.schedule() },
                    found.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in self?.schedule() },
                    found.observe(\.bounds, options: [.new]) { [weak self] _, _ in self?.schedule() }
                ]
            }
            if let clips = config.clips { found.clipsToBounds = clips }
            if let bounce = config.bounce {
                switch bounce {
                case .automatic: break
                case .always: found.alwaysBounceVertical = true
                case .basedOnSize:
                    found.alwaysBounceVertical = false
                    found.alwaysBounceHorizontal = false
                }
            }
            if let anchor = config.anchor, !anchored, found.contentSize.height > 0, found.bounds.height > 0 {
                anchored = true
                let inset = found.adjustedContentInset
                let x = -inset.left + max(0, found.contentSize.width + inset.left + inset.right - found.bounds.width) * anchor.x
                let y = -inset.top + max(0, found.contentSize.height + inset.top + inset.bottom - found.bounds.height) * anchor.y
                found.setContentOffset(CGPoint(x: x, y: y), animated: false)
            }
            if config.flash, !flashed { flashed = true; found.flashScrollIndicators() }
            let new = CompatScrollMetrics(contentHeight: found.contentSize.height,
                distance: found.contentSize.height + found.adjustedContentInset.bottom - found.contentOffset.y - found.bounds.height)
            if new != lastMetrics {
                lastMetrics = new
                config.metrics?(new)
            }
        }
    }
}

private struct SheetInteraction16: UIViewControllerRepresentable {
    let enabled: Bool
    func makeUIViewController(context: Context) -> Probe { Probe() }
    func updateUIViewController(_ controller: Probe, context: Context) {
        controller.enabled = enabled
        DispatchQueue.main.async { controller.apply() }
    }
    final class Probe: UIViewController {
        var enabled = true
        override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); apply() }
        func apply() {
            var current: UIViewController? = self
            while let controller = current {
                if let sheet = controller.presentationController as? UISheetPresentationController {
                    sheet.largestUndimmedDetentIdentifier = enabled ? .large : nil
                    return
                }
                current = controller.parent
            }
        }
    }
}

// The character picker uses a triggered rest / pop / rest sequence.
extension View {
    func phaseAnimator16<Trigger: Equatable, Animated: View>(
        _ phases: [Bool], trigger: Trigger,
        @ViewBuilder content: @escaping (Self, Bool) -> Animated,
        animation: @escaping (Bool) -> Animation?
    ) -> some View {
        CompatBoolPhase(base: self, trigger: trigger, transform: content, animation: animation)
    }
}

private struct CompatBoolPhase<Trigger: Equatable, Base: View, Animated: View>: View {
    let base: Base
    let trigger: Trigger
    let transform: (Base, Bool) -> Animated
    let animation: (Bool) -> Animation?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var popped = false
    @State private var serial = 0

    @ViewBuilder var body: some View {
        if #available(iOS 17.0, *) {
            base.phaseAnimator([false, true], trigger: trigger, content: { _, phase in transform(base, phase) }, animation: animation)
        } else {
            transform(base, popped).compatOnChange(of: trigger) { _, _ in
                guard !reduceMotion else { return }
                serial += 1
                let token = serial
                withAnimation(animation(true)) { popped = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                    guard token == serial else { return }
                    withAnimation(animation(false)) { popped = false }
                }
            }
        }
    }
}
