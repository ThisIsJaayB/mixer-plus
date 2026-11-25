// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

extension MixerMeterLevel {
    /// An app fader's level in dB, from the curve the engine plays it with.
    static func faderReadout(volume: Double) -> String {
        let gain = MixerRoutingSupport.gain(forVolume: volume)
        return readout(gain > 0 ? 20 * log10(gain) : floorDB)
    }
}

/// A desk's vertical fader: a slim channel, a cap that slides along it, and
/// optionally the levels the positions stand for.
struct MixerVerticalFader: View {
    @Binding var value: Double
    let maximum: Double
    /// dB marks beside the track. Only where the level's curve is known.
    let showsScale: Bool
    let isBoosting: Bool
    let accessibilityLabel: String
    @Environment(\.colorScheme) private var colorScheme

    private static let capWidth: CGFloat = 22
    /// The levels marked on an app's fader, top to bottom.
    private static let marks: [(label: String, volume: Double)] = [
        ("6", 2), ("0", 1), ("6", MixerRoutingSupport.volume(forGain: 0.5012)),
        ("12", MixerRoutingSupport.volume(forGain: 0.2512)),
        ("24", MixerRoutingSupport.volume(forGain: 0.0631)), ("∞", 0),
    ]

    private var travel: CGFloat { MixerDeskMetrics.faderHeight - MixerDeskMetrics.capHeight }
    private func offset(forVolume volume: Double) -> CGFloat {
        travel * (1 - CGFloat(MixerFaderScale.position(forVolume: volume, maximum: maximum)))
    }

    var body: some View {
        HStack(spacing: 1) {
            if showsScale { scale.frame(width: 12) }
            ZStack(alignment: .top) {
                Capsule()
                    .fill(colorScheme == .dark ? Color.black.opacity(0.55) : Color.primary.opacity(0.18))
                    .frame(width: 4)
                    .padding(.vertical, MixerDeskMetrics.capHeight / 2 - 2)
                cap.offset(y: offset(forVolume: value))
            }
            .frame(width: Self.capWidth, height: MixerDeskMetrics.faderHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local).onChanged { gesture in
                    let place = 1 - Double((gesture.location.y - MixerDeskMetrics.capHeight / 2) / travel)
                    value = MixerFaderScale.draggedVolume(atPosition: place, maximum: maximum)
                }
            )
            .overlay(SliderScrollArea(value: $value, range: 0...maximum, doubleClickValue: maximum > 1 ? 1 : nil))
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue("\(MixerRoutingSupport.displayPercent(forVolume: value))%")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(maximum, value + 0.05)
            case .decrement: value = max(0, value - 0.05)
            @unknown default: break
            }
        }
    }

    private var scale: some View {
        ZStack(alignment: .topTrailing) {
            ForEach(Array(Self.marks.enumerated()), id: \.offset) { _, mark in
                Text(mark.label)
                    .font(.system(size: 7, weight: mark.volume == 1 ? .bold : .regular, design: .rounded))
                    .foregroundStyle(mark.volume == 1 ? Color.primary.opacity(0.8) : Color.secondary.opacity(0.75))
                    .frame(height: 8)
                    .offset(y: offset(forVolume: mark.volume) + MixerDeskMetrics.capHeight / 2 - 4)
            }
        }
        .frame(height: MixerDeskMetrics.faderHeight, alignment: .top)
        .accessibilityHidden(true)
    }

    private var cap: some View {
        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
            .fill(LinearGradient(colors: [Color(white: 0.96), Color(white: 0.72), Color(white: 0.9)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(Rectangle().fill(isBoosting ? Color.orange : Color.black.opacity(0.55)).frame(height: 1.5))
            .overlay(RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                .strokeBorder(Color.black.opacity(0.35), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.45), radius: 1.5, y: 1)
            .frame(width: Self.capWidth, height: MixerDeskMetrics.capHeight)
    }
}

/// A strip's meter: one bar per side, rising from the bottom.
struct MixerStereoMeter: NSViewRepresentable {
    let meterID: String

    func makeNSView(context: Context) -> MixerStereoMeterView { MixerStereoMeterView(meterID: meterID) }

    func updateNSView(_ view: MixerStereoMeterView, context: Context) {
        guard view.meterID != meterID else { return }
        view.meterID = meterID
        MixerLevelMeters.shared.sync()
    }
}

/// Each side is a dark slot with a gradient masked to the level's height. A
/// refresh moves two mask edges and touches nothing else on the panel.
final class MixerStereoMeterView: NSView, MixerMeterDisplay {
    var meterID: String
    private lazy var visibility = MixerMeterVisibility(self)
    private let slots = [CALayer(), CALayer()]
    private let bars = [CAGradientLayer(), CAGradientLayer()]
    private let masks = [CALayer(), CALayer()]
    private var levels = [0.0, 0.0]
    private var hot = [false, false]

    private static let normalColors = [NSColor.systemGreen, .systemGreen, .systemYellow, .systemYellow]
        .map(\.cgColor)
    private static let hotColors = Array(repeating: NSColor.systemRed.cgColor, count: 4)

    init(meterID: String) {
        self.meterID = meterID
        super.init(frame: .zero)
        wantsLayer = true
        for side in 0..<2 {
            slots[side].backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
            slots[side].cornerRadius = 1.5
            bars[side].startPoint = CGPoint(x: 0.5, y: 0)
            bars[side].endPoint = CGPoint(x: 0.5, y: 1)
            bars[side].locations = [0, 0.8, 0.8, 1]
            bars[side].colors = Self.normalColors
            bars[side].cornerRadius = 1.5
            masks[side].backgroundColor = NSColor.black.cgColor
            masks[side].anchorPoint = .zero
            bars[side].mask = masks[side]
            layer?.addSublayer(slots[side])
            layer?.addSublayer(bars[side])
        }
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        visibility.windowChanged()
    }

    override func layout() {
        super.layout()
        withoutAnimation {
            let width = (bounds.width - 1) / 2
            for side in 0..<2 {
                let frame = CGRect(x: CGFloat(side) * (width + 1), y: 0, width: width, height: bounds.height)
                slots[side].frame = frame
                bars[side].frame = frame
                placeMask(side)
            }
        }
    }

    func show(left: MixerMeterLevel, right: MixerMeterLevel) {
        let next = [left, right]
        guard next.map(\.level) != levels || next.map(\.isHot) != hot else { return }
        withoutAnimation {
            for side in 0..<2 {
                levels[side] = next[side].level
                if hot[side] != next[side].isHot {
                    hot[side] = next[side].isHot
                    bars[side].colors = hot[side] ? Self.hotColors : Self.normalColors
                }
                placeMask(side)
            }
        }
    }

    private func placeMask(_ side: Int) {
        masks[side].frame = CGRect(x: 0, y: 0, width: bars[side].bounds.width,
                                   height: bars[side].bounds.height * levels[side])
    }

    private func withoutAnimation(_ change: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        change()
        CATransaction.commit()
    }
}

/// The loudest recent peak of a strip, in dB, as a desk's yellow readout.
struct MixerPeakReadout: NSViewRepresentable {
    let meterID: String

    func makeNSView(context: Context) -> MixerPeakReadoutView { MixerPeakReadoutView(meterID: meterID) }

    func updateNSView(_ view: MixerPeakReadoutView, context: Context) {
        guard view.meterID != meterID else { return }
        view.meterID = meterID
        MixerLevelMeters.shared.sync()
    }
}

final class MixerPeakReadoutView: NSTextField, MixerMeterDisplay {
    var meterID: String
    private lazy var visibility = MixerMeterVisibility(self)
    private var shown = ""

    init(meterID: String) {
        self.meterID = meterID
        super.init(frame: .zero)
        isEditable = false
        isSelectable = false
        isBordered = false
        drawsBackground = false
        alignment = .center
        font = .monospacedDigitSystemFont(ofSize: 8, weight: .semibold)
        textColor = .systemYellow
        lineBreakMode = .byClipping
        stringValue = MixerMeterLevel.readout(MixerMeterLevel.floorDB)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        visibility.windowChanged()
    }

    func show(left: MixerMeterLevel, right: MixerMeterLevel) {
        let held = max(left.heldDB, right.heldDB)
        let text = MixerMeterLevel.readout(held)
        guard text != shown else { return }
        shown = text
        stringValue = text
        textColor = held >= MixerMeterLevel.hotDB ? .systemRed : .systemYellow
    }
}

/// The M and S of a strip: a small key that lights while it is on.
struct MixerDeskKey: View {
    let letter: String
    let isOn: Bool
    let tint: Color
    let help: String
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Text(letter)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(isOn ? Color.black.opacity(0.85) : Color.secondary)
                .frame(width: 23, height: 16)
                .background(RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(isOn ? tint : Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// A colour for an app's strip, taken from its icon, the way a desk's
/// channels are told apart at a glance.
enum MixerStripColor {
    private static var cache: [pid_t: Color] = [:]

    static func color(for pid: pid_t, icon: NSImage) -> Color {
        if let cached = cache[pid] { return cached }
        let color = average(of: icon) ?? .gray
        if cache.count > 256 { cache.removeAll() }
        cache[pid] = color
        return color
    }

    /// The icon drawn very small, averaged over the pixels that are not
    /// transparent or near grey, then made vivid enough to read as a colour.
    private static func average(of icon: NSImage) -> Color? {
        let side = 12
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: side * 4, bitsPerPixel: 32),
              let context = NSGraphicsContext(bitmapImageRep: bitmap), let data = bitmap.bitmapData else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        icon.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()

        var red = 0.0, green = 0.0, blue = 0.0, weight = 0.0
        for pixel in 0..<(side * side) {
            let alpha = Double(data[pixel * 4 + 3]) / 255
            guard alpha > 0.5 else { continue }
            let r = Double(data[pixel * 4]) / 255, g = Double(data[pixel * 4 + 1]) / 255
            let b = Double(data[pixel * 4 + 2]) / 255
            // Colourful pixels count for more than the white or grey around them.
            let chroma = max(r, g, b) - min(r, g, b) + 0.05
            red += r * chroma; green += g * chroma; blue += b * chroma; weight += chroma
        }
        guard weight > 0 else { return nil }
        let base = NSColor(deviceRed: red / weight, green: green / weight, blue: blue / weight, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        base.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        guard saturation > 0.08 else { return Color(white: 0.6) }
        return Color(hue: Double(hue), saturation: Double(max(saturation, 0.6)), brightness: Double(max(brightness, 0.85)))
    }
}
