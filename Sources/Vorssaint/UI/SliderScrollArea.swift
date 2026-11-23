// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Enabled level controls receive the wheel before an enclosing horizontal strip.
protocol SliderScrollTarget: AnyObject {
    var acceptsSliderScroll: Bool { get }
}

extension SliderScroll {
    mutating func handle(_ event: NSEvent, current: Double, range: ClosedRange<Double>) -> Outcome {
        let phase: Phase
        if !event.momentumPhase.isEmpty { phase = .momentum }
        else if event.phase.contains(.began) { phase = .began }
        else if event.phase.contains(.mayBegin) { return .pass }
        else if !event.phase.intersection([.changed, .stationary]).isEmpty { phase = .changed }
        else if event.phase.isEmpty { phase = .none }
        else { phase = .ended }
        return handle(phase, dx: Double(event.scrollingDeltaX), dy: Double(event.scrollingDeltaY),
                      precise: event.hasPreciseScrollingDeltas, inverted: event.isDirectionInvertedFromDevice,
                      timestamp: event.timestamp, current: current, range: range)
    }

    /// A scroll the bar does not take goes on to the list around it.
    static func pass(_ event: NSEvent, from view: NSView, after pending: [NSEvent] = []) {
        guard let responder: NSResponder = view.enclosingScrollView ?? view.nextResponder else { return }
        for held in pending { responder.scrollWheel(with: held) }
        responder.scrollWheel(with: event)
    }
}

/// Laid over a SwiftUI slider, it takes scroll events and, when a reset value
/// is given, the second click of a double-click; every other click and drag
/// reaches the slider underneath.
struct SliderScrollArea: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    /// Where a double-click puts the slider; nil leaves double-clicks alone.
    var doubleClickValue: Double? = nil

    func makeNSView(context: Context) -> AreaView { AreaView() }

    func updateNSView(_ view: AreaView, context: Context) {
        view.area = self
        view.isEnabled = context.environment.isEnabled
    }

    final class AreaView: NSView, SliderScrollTarget {
        var area: SliderScrollArea?
        var isEnabled = true
        var acceptsSliderScroll: Bool { isEnabled && area != nil }
        private var scroll = SliderScroll()

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard NSApp.currentEvent?.type == .scrollWheel else { return nil }
            return super.hitTest(point)
        }

        /// Watches this app's own clicks while the view is in a window. The
        /// slider underneath tracks the mouse itself, so a click never reaches
        /// a view laid over it; the second click of a pair is taken here,
        /// before the slider can read it as a jump to that position.
        private var clickMonitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let clickMonitor {
                NSEvent.removeMonitor(clickMonitor)
                self.clickMonitor = nil
            }
            guard window != nil else { return }
            clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self, event.clickCount == 2, isEnabled, event.window === window,
                      let area, let reset = area.doubleClickValue,
                      bounds.contains(convert(event.locationInWindow, from: nil)) else { return event }
                area.value = reset
                return nil
            }
        }

        deinit {
            if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        }

        override func scrollWheel(with event: NSEvent) {
            guard let area, isEnabled else { return SliderScroll.pass(event, from: self) }
            switch scroll.handle(event, current: area.value, range: area.range) {
            case .pass: SliderScroll.pass(event, from: self)
            case .hold: break
            case .move(let value): area.value = value
            }
        }
    }
}
