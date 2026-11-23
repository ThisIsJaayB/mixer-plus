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

    /// Whether the meter has fallen all the way back, so its reader can go.
    var isAtRest: Bool { shownDB <= Self.floorDB }

    /// Takes the loudest sample since the last call (0 silent, 1 full scale)
    /// and the seconds since then.
    mutating func advance(peak: Float, elapsed: Float) {
        let peakDB = peak > 0 && peak.isFinite ? max(20 * log10(peak), Self.floorDB) : Self.floorDB
        shownDB = min(max(peakDB, shownDB - Self.fallRate * max(elapsed, 0), Self.floorDB), 0)
        let fraction = Double((shownDB - Self.floorDB) / -Self.floorDB)
        level = (fraction / Self.resolution).rounded() * Self.resolution
        isHot = peakDB >= Self.hotDB
    }
}
