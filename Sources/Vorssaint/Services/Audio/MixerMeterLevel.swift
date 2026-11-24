// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// How a mixer row's level meter moves: up to a louder peak at once, back
/// down at a steady rate, so it reads as a level instead of a flicker.
///
/// Pure arithmetic; the caller supplies the peak and the time that passed.
struct MixerMeterLevel: Equatable {
    /// The quietest level drawn. Anything below is an empty meter.
    static let floorDB: Float = -60
    /// How fast the meter falls after a peak, in dB per second.
    static let fallRate: Float = 20
    /// From here up the meter turns red: 1 dB under full scale, where the
    /// mixer's limiter starts to work on a boosted app.
    static let hotDB: Float = -1
    /// The meter is drawn in steps of this size, so a change too small to
    /// see redraws nothing.
    static let resolution = 1.0 / 200

    /// What the meter shows, in dBFS.
    private(set) var shownDB = floorDB
    /// The bar's length, 0 (floor or quieter) to 1 (full scale).
    private(set) var level = 0.0
    private(set) var isHot = false
    /// The loudest recent peak, in dBFS, for the readout beside a fader: it
    /// stays for `holdTime` after it was reached, then falls with the meter.
    private(set) var heldDB = floorDB
    private var heldFor: Float = 0
    static let holdTime: Float = 1.5

    /// Whether the meter and its readout have fallen all the way back, so
    /// the reader behind them can go.
    var isAtRest: Bool { shownDB <= Self.floorDB && heldDB <= Self.floorDB }

    /// The gain an output's own volume control applies, for a meter that
    /// sits after it. The output's level in decibels is used when the device
    /// reports one. Otherwise the slider position is read on the curve the
    /// app faders use, which is close for outputs that say nothing.
    static func outputGain(decibels: Float?, volume: Double?) -> Float {
        if let decibels, !decibels.isNaN {
            // An output at the bottom of its range reports minus infinity.
            return decibels == -.infinity ? 0 : min(powf(10, decibels / 20), 1)
        }
        guard let volume, volume.isFinite else { return 1 }
        let level = Float(min(max(volume, 0), 1))
        return level * level
    }

    /// A level the way a desk prints it: one decimal near the top, whole
    /// numbers below −10, and −∞ at the floor.
    static func readout(_ db: Float) -> String {
        guard db.isFinite, db > floorDB else { return "−∞" }
        // The decimal mark follows the user's region, as a level does everywhere else.
        let text = String(format: abs(db) < 9.95 ? "%.1f" : "%.0f", locale: .current, abs(db))
        return (db < -0.05 ? "−" : db > 0.05 ? "+" : "") + text
    }

    /// Takes the loudest sample since the last call (0 silent, 1 full scale)
    /// and the seconds since then.
    mutating func advance(peak: Float, elapsed: Float) {
        let peakDB = peak > 0 && peak.isFinite ? max(20 * log10(peak), Self.floorDB) : Self.floorDB
        shownDB = min(max(peakDB, shownDB - Self.fallRate * max(elapsed, 0), Self.floorDB), 0)
        let fraction = Double((shownDB - Self.floorDB) / -Self.floorDB)
        level = (fraction / Self.resolution).rounded() * Self.resolution
        isHot = peakDB >= Self.hotDB

        let step = max(elapsed, 0)
        if peakDB >= heldDB {
            heldDB = min(peakDB, 0)
            heldFor = 0
        } else {
            heldFor += step
            if heldFor > Self.holdTime { heldDB = max(peakDB, heldDB - Self.fallRate * step, Self.floorDB) }
        }
    }
}
