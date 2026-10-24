import SwiftUI
import UIKit
import Observation
import os

private let foldLog = Logger(subsystem: "com.shadetracemap.shadetracemap", category: "fold")

// iPhone Duo support, written directly against UIKit's iOS 27.1 APIs:
//
//  - UIHingeInteraction / UIHinge        -> fold posture + hinge angle
//  - UIView.reservedRegions(kind:)       -> where the fold (division) is
//  - UITabBarController vertical bar     -> handled by the system: SwiftUI's
//                                           TabView moves to the side column
//                                           on its own (see RootView)
//
// The Flutter app needs the third-party `foldable` package for the first
// two (it looks the classes up by name at runtime) and ~200 lines in
// root_shell.dart / app_tab_bar.dart to imitate the third. Here the first two
// are ~100 lines of direct, compiler-checked API calls and the third is free.
//
// Everything is behind `#available(iOS 27.1, *)`; on any other device or iOS
// version `FoldState` simply stays `.folded` - the normal phone layout.

/// The app's three iPhone Duo experiences, keyed off the hinge posture.
enum DevicePosture: Equatable {
    /// Closed, on the outer display - or any device without a hinge.
    case folded
    /// Flat open on the inner display: the ShadeMap tab becomes a map
    /// workspace with its controls docked in a side panel.
    case unfolded
    /// Partly open (book or laptop pose): the Sun Path tab splits across
    /// the fold, sun arc on one side and its time controls on the other.
    case halfFolded
}

/// Live hinge state for the whole app, injected with `.environment(_:)`.
///
/// `@Observable` tracks reads per property, so a view that only reads
/// `posture` is not re-rendered as `angleDegrees` sweeps while the user
/// opens the device - no extra plumbing needed to avoid rebuild storms.
@MainActor
@Observable
final class FoldState {
    private(set) var hasHinge = false
    private(set) var posture: DevicePosture = .folded
    private(set) var angleDegrees: Double?
    /// Whether iOS wants tab bars in the iPhone Duo side column right now
    /// (outer display, or inner display in landscape). Read from the public
    /// `verticalBarEdge` trait, so no guessing about displays or cameras.
    /// Which side that column is on, or nil when bars stay horizontal.
    private(set) var verticalBarEdge: HorizontalEdge?
    var usesVerticalBar: Bool { verticalBarEdge != nil }

    fileprivate func setVerticalBarEdge(_ edge: HorizontalEdge?) {
        guard edge != verticalBarEdge else { return }
        foldLog.info("vertical bar edge: \(String(describing: edge), privacy: .public)")
        verticalBarEdge = edge
    }

    fileprivate func apply(status: DevicePosture?, angleRadians: Double?) {
        if status != posture || (status == nil) == hasHinge {
            foldLog.info("hinge: \(String(describing: status), privacy: .public) angle=\(angleRadians.map { $0 * 180 / .pi } ?? -1, privacy: .public)")
        }
        guard let status else {
            hasHinge = false
            angleDegrees = nil
            if posture != .folded { posture = .folded }
            return
        }
        hasHinge = true
        angleDegrees = angleRadians.map { $0 * 180 / .pi }
        if posture != status { posture = status }
    }
}

/// An invisible view that owns the `UIHingeInteraction` and feeds `FoldState`.
/// Attach once near the root: `.background(HingeObserver(state: fold))`.
struct HingeObserver: UIViewRepresentable {
    let state: FoldState

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        if #available(iOS 27.1, *) {
            let report: (UITraitCollection) -> Void = { [weak state] traits in
                let edge: HorizontalEdge?
                switch traits.verticalBarEdge {
                case .leading: edge = .leading
                case .trailing: edge = .trailing
                default: edge = nil
                }
                state?.setVerticalBarEdge(edge)
            }
            report(view.traitCollection)
            view.registerForTraitChanges(UITraitCollection.systemTraitsAffectingVerticalBarEdge) { (v: UIView, _: UITraitCollection) in
                report(v.traitCollection)
            }

            // Called with the initial state and on every change. A nil
            // `hinge` means this hierarchy has no hinge (normal iPhone, iPad).
            let interaction = UIHingeInteraction { [weak state] _, update in
                guard let state else { return }
                guard let hinge = update.hinge else {
                    state.apply(status: nil, angleRadians: nil)
                    return
                }
                let posture: DevicePosture
                switch hinge.status {
                case .fullyOpen: posture = .unfolded
                case .partiallyOpen: posture = .halfFolded
                case .closed, .unknown: posture = .folded
                @unknown default: posture = .folded
                }
                state.apply(status: posture, angleRadians: Double(hinge.angle))
            }
            view.addInteraction(interaction)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// Reports where the fold crosses this view, in this view's own coordinate
/// space - so a layout can leave the fold's band empty. Uses
/// `reservedRegions(kind: .division)`; nil when there's no fold here.
///
/// Use as `.background(FoldDivisionReader(posture: fold.posture) { rect = $0 })`.
struct FoldDivisionReader: UIViewRepresentable {
    /// Passed in only so a posture change triggers a fresh query.
    let posture: DevicePosture
    let onChange: (CGRect?) -> Void

    func makeUIView(context: Context) -> RegionView {
        let view = RegionView()
        view.onChange = onChange
        return view
    }

    func updateUIView(_ uiView: RegionView, context: Context) {
        uiView.onChange = onChange
        uiView.scheduleQueries()
    }

    final class RegionView: UIView {
        var onChange: ((CGRect?) -> Void)?
        private var last: CGRect??

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { fatalError() }

        override func layoutSubviews() {
            super.layoutSubviews()
            query()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            scheduleQueries()
        }

        /// The division can lag the hinge by about a second, so ask again a
        /// few times after a posture change rather than once.
        func scheduleQueries() {
            query()
            for delay in [0.3, 0.8, 1.5] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.query() }
            }
        }

        private func query() {
            var rect: CGRect?
            if #available(iOS 27.1, *) {
                rect = reservedRegions(kind: .division)
                    .first { $0.isActive && !$0.frame.isEmpty }?
                    .frame
            }
            guard last != .some(rect) else { return }
            last = .some(rect)
            foldLog.info("division: \(String(describing: rect), privacy: .public) in \(String(describing: self.bounds), privacy: .public)")
            onChange?(rect)
        }
    }
}

/// Reports the screen areas covered by hardware (the outer display's
/// camera), via `reservedRegions(kind: .occlusion)`, in this view's own
/// coordinate space - so the side tab bar can stay clear of the camera.
struct OcclusionReader: UIViewRepresentable {
    let onChange: ([CGRect]) -> Void

    func makeUIView(context: Context) -> RegionView {
        let view = RegionView()
        view.onChange = onChange
        return view
    }

    func updateUIView(_ uiView: RegionView, context: Context) {
        uiView.onChange = onChange
    }

    final class RegionView: UIView {
        var onChange: (([CGRect]) -> Void)?
        private var last: [CGRect]?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { fatalError() }

        override func layoutSubviews() {
            super.layoutSubviews()
            var rects: [CGRect] = []
            if #available(iOS 27.1, *) {
                rects = reservedRegions(kind: .occlusion).filter(\.isActive).map(\.frame)
            }
            guard rects != last else { return }
            last = rects
            foldLog.info("occlusion: \(String(describing: rects), privacy: .public)")
            onChange?(rects)
        }
    }
}
