// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// An app's pan, as the small rotary knob beside a mixing desk's fader.
///
/// Drag up or right to pan right, down or left to pan left; scroll over it
/// for the same. A drag that passes near the middle lands on centre, and a
/// double-click returns to it.
struct MixerPanKnob: View {
    @Binding var value: Double
    let strings: MixerPlusStrings
    let appName: String
    var size: CGFloat = 20
    @Environment(\.colorScheme) private var colorScheme
    /// The pan when the drag in progress began.
    @State private var dragStart: Double?

    /// The pointer travel, in points, that takes the knob from centre to one end.
    private static let dragTravel = 60.0
    /// How close to the middle a drag has to come to land on centre.
    private static let snapDistance = 0.06
    /// The pointer's sweep either side of straight up, in degrees.
    private static let sweep = 135.0

    private var isCentred: Bool { MixerBalance.isCentred(value) }
    private var readout: String {
        let amount = MixerBalance.displayValue(value)
        if amount == 0 { return strings.panCentre }
        return "\(amount < 0 ? strings.panLeft : strings.panRight) \(abs(amount))"
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(colorScheme == .dark ? Color.black.opacity(0.42) : Color.primary.opacity(0.12))
            // How far from centre, drawn from the top round to the pointer.
            Circle()
                .trim(from: 0, to: abs(value) * Self.sweep / 360)
                .rotation(.degrees(-90))
                .scale(x: value < 0 ? -1 : 1)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .padding(1)
            Circle()
                .fill(Color.white.opacity(colorScheme == .dark ? 0.26 : 0.8))
                .padding(size * 0.175)
            Capsule()
                .fill(isCentred ? Color.primary.opacity(0.75) : Color.accentColor)
                .frame(width: 1.5, height: size * 0.3)
                .offset(y: -size * 0.25)
                .rotationEffect(.degrees(value * Self.sweep))
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { gesture in
                    let start = dragStart ?? value
                    dragStart = start
                    let moved = Double(gesture.translation.width - gesture.translation.height) / Self.dragTravel
                    let pan = MixerBalance.sanitized(start + moved)
                    value = abs(pan) < Self.snapDistance ? 0 : pan
                }
                .onEnded { _ in dragStart = nil }
        )
        .overlay(SliderScrollArea(value: $value, range: -1...1, doubleClickValue: 0))
        .help("\(strings.pan): \(readout)")
        .accessibilityElement()
        .accessibilityLabel("\(strings.pan): \(appName)")
        .accessibilityValue(readout)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(1, value + 0.1)
            case .decrement: value = max(-1, value - 0.1)
            @unknown default: break
            }
        }
    }
}
