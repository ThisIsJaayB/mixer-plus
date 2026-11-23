// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// A level meter drawn inside a mixer fader's channel: green, yellow towards
/// full scale, and all red while the app reaches the limiter.
struct MixerMeterBar: NSViewRepresentable {
    let appID: String

    func makeNSView(context: Context) -> MixerMeterView { MixerMeterView(appID: appID) }

    func updateNSView(_ view: MixerMeterView, context: Context) {
        guard view.meterID != appID else { return }
        view.meterID = appID
        MixerLevelMeters.shared.sync()
    }
}

/// Two Core Animation layers: a full-width gradient, masked to the level's
/// length. A refresh only moves the mask's edge, so the panel around it is
/// never laid out again for a meter.
///
/// One bar for both sides: it shows whichever is louder.
final class MixerMeterView: NSView, MixerMeterDisplay {
    var meterID: String
    private lazy var visibility = MixerMeterVisibility(self)

    private let gradient = CAGradientLayer()
    private let mask = CALayer()
    private var level = 0.0
    private var isHot = false

    private static let normalColors = [NSColor.systemGreen, .systemGreen, .systemYellow, .systemYellow]
        .map { $0.withAlphaComponent(0.9).cgColor }
    private static let hotColors = Array(repeating: NSColor.systemRed.withAlphaComponent(0.9).cgColor, count: 4)

    init(appID: String) {
        meterID = appID
        super.init(frame: .zero)
        wantsLayer = true
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        // A hard change of colour, as on a desk's meter, not a blend.
        gradient.locations = [0, 0.8, 0.8, 1]
        gradient.colors = Self.normalColors
        mask.backgroundColor = NSColor.black.cgColor
        mask.anchorPoint = .zero
        gradient.mask = mask
        layer?.addSublayer(gradient)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Clicks, drags and scrolls belong to the fader in front.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        visibility.windowChanged()
    }

    func show(left: MixerMeterLevel, right: MixerMeterLevel) {
        show(level: max(left.level, right.level), isHot: left.isHot || right.isHot)
    }

    override func layout() {
        super.layout()
        withoutAnimation {
            gradient.frame = bounds
            mask.cornerRadius = bounds.height / 2
            placeMask()
        }
    }

    private func show(level: Double, isHot: Bool) {
        guard level != self.level || isHot != self.isHot else { return }
        self.level = level
        withoutAnimation {
            if isHot != self.isHot {
                self.isHot = isHot
                gradient.colors = isHot ? Self.hotColors : Self.normalColors
            }
            placeMask()
        }
    }

    private func placeMask() {
        // Never shorter than it is tall, so the rounded end stays round.
        let width = level > 0 ? max(gradient.bounds.width * level, gradient.bounds.height) : 0
        mask.frame = CGRect(x: 0, y: 0, width: width, height: gradient.bounds.height)
    }

    private func withoutAnimation(_ change: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        change()
        CATransaction.commit()
    }
}
