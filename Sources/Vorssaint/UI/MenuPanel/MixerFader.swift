// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// An app's fader, in the style of a mixing desk: a dark channel with the
/// app's live level running inside it, a see-through cap that rides over the
/// meter, and a mark at 100% with the boost range to its right.
struct MixerFader: View {
    @Binding var value: Double
    let appID: String
    let maximum: Double
    let isBoosting: Bool
    let boostTint: Color
    let showsMeter: Bool
    let accessibilityLabel: String
    @Environment(\.colorScheme) private var colorScheme

    private static let height: CGFloat = 18
    private static let knob: CGFloat = 18
    /// The meter and the 100% mark sit this far inside the channel.
    private static let inset: CGFloat = 3

    private var position: CGFloat {
        CGFloat(MixerFaderScale.position(forVolume: value, maximum: maximum))
    }

    var body: some View {
        GeometryReader { proxy in
            let travel = max(proxy.size.width - Self.knob, 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(colorScheme == .dark ? Color.black.opacity(0.42) : Color.primary.opacity(0.12))
                if showsMeter {
                    MixerMeterBar(appID: appID)
                        .padding(Self.inset)
                        .allowsHitTesting(false)
                }
                Capsule()
                    .fill(isBoosting ? boostTint : Color.primary.opacity(0.55))
                    .frame(width: 1.5, height: Self.height - Self.inset * 2)
                    .offset(x: Self.knob / 2 + travel * MixerFaderScale.unityPosition - 0.75)
                cap.offset(x: travel * position)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { gesture in
                    let place = Double((gesture.location.x - Self.knob / 2) / travel)
                    value = MixerFaderScale.draggedVolume(atPosition: place, maximum: maximum)
                }
            )
        }
        .frame(height: Self.height)
        .overlay(SliderScrollArea(value: $value, range: 0...maximum, doubleClickValue: 1))
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

    /// See-through, so the level keeps moving underneath it.
    private var cap: some View {
        Circle()
            .fill(Color.white.opacity(colorScheme == .dark ? 0.34 : 0.78))
            .overlay(Circle().strokeBorder(
                isBoosting ? boostTint.opacity(0.9) : Color.white.opacity(colorScheme == .dark ? 0.45 : 0.9),
                lineWidth: isBoosting ? 1.4 : 1))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.22), radius: 1.5, y: 0.5)
            .frame(width: Self.knob, height: Self.knob)
    }
}
