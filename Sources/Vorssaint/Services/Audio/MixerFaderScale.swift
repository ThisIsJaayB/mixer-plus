// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Where an app's volume sits along its fader.
///
/// The fader gives most of its length to 0–100%, where levels are set by
/// ear, and the rest to the boost above it, the way a mixing desk puts unity
/// well short of the top. Both stretches are linear in the volume.
enum MixerFaderScale {
    /// How far along the fader 100% sits, 0 (left end) to 1 (right end).
    static let unityPosition = 0.78
    /// A drag that passes this close to 100% lands on it, so unity is easy
    /// to find without the reset button.
    static let snapDistance = 0.012

    /// The volume at a place along the fader. `maximum` is the top of the
    /// boost range; with no boost the whole fader is 0–100%.
    static func volume(atPosition position: Double, maximum: Double) -> Double {
        guard position.isFinite, maximum > 1 else {
            return position.isFinite ? min(max(position, 0), 1) * min(max(maximum, 0), 1) : 0
        }
        let p = min(max(position, 0), 1)
        if p <= unityPosition { return p / unityPosition }
        return 1 + (p - unityPosition) / (1 - unityPosition) * (maximum - 1)
    }

    /// The place along the fader for a volume: the inverse of `volume`.
    static func position(forVolume volume: Double, maximum: Double) -> Double {
        guard volume.isFinite, maximum > 0 else { return 0 }
        let v = min(max(volume, 0), maximum)
        guard maximum > 1 else { return v / maximum }
        if v <= 1 { return v * unityPosition }
        return unityPosition + (v - 1) / (maximum - 1) * (1 - unityPosition)
    }

    /// The volume a drag to `position` asks for: exactly 100% near the mark.
    static func draggedVolume(atPosition position: Double, maximum: Double) -> Double {
        if maximum > 1, abs(position - unityPosition) < snapDistance { return 1 }
        return volume(atPosition: position, maximum: maximum)
    }
}

/// The measurements every strip of the mixer desk shares, so they line up.
enum MixerDeskMetrics {
    static let stripWidth: CGFloat = 58
    static let stripSpacing: CGFloat = 2
    static let faderHeight: CGFloat = 142
    static let capHeight: CGFloat = 30
    /// The panel's usual content width, and the widest the desk may make it.
    static let minimumWidth: CGFloat = 308
    static let maximumWidth: CGFloat = 488

    /// The width a desk of `strips` channels wants: the panel's own width
    /// while they fit, growing a strip at a time up to the maximum. Past
    /// that the app strips scroll sideways.
    static func width(forStrips strips: Int) -> CGFloat {
        let wanted = CGFloat(max(strips, 0)) * (stripWidth + stripSpacing) + 8
        return min(max(wanted, minimumWidth), maximumWidth)
    }
}
