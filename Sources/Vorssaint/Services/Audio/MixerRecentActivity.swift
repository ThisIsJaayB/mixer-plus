// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Remembers when each mixer row last made sound, so "Hide inactive apps" can
/// keep a row for a while after it goes quiet instead of dropping it the
/// moment a track ends or a video pauses.
///
/// Pure bookkeeping: the caller supplies the clock, and nothing here touches
/// audio, timers or preferences.
struct MixerRecentActivity {
    /// How long a quiet row may stay, in seconds, as offered in the options.
    static let lingerChoices = [10, 30, 60, 300]
    static let defaultLinger = 30

    /// A stored value that is not one of the choices falls back to the default,
    /// so a damaged or hand-edited preference cannot pin rows forever.
    static func sanitizedLinger(_ seconds: Int) -> Int {
        lingerChoices.contains(seconds) ? seconds : defaultLinger
    }

    /// When each row was last heard. A playing row holds the time it was last
    /// seen playing; `observe` stamps it again the moment it stops.
    private var lastHeard: [String: Double] = [:]
    private var playing: Set<String> = []

    /// Records one snapshot of the mixer's rows. Rows that left the mixer are
    /// forgotten, so the map never outgrows the running apps.
    mutating func observe(playing nowPlaying: Set<String>, present: Set<String>, now: Double) {
        if lastHeard.count > present.count || !lastHeard.keys.allSatisfy(present.contains) {
            lastHeard = lastHeard.filter { present.contains($0.key) }
        }
        // A row that just stopped is stamped now: its time to linger runs from
        // the silence, not from whenever it happened to start.
        for id in playing.union(nowPlaying) where present.contains(id) {
            lastHeard[id] = now
        }
        playing = nowPlaying.intersection(present)
    }

    /// The rows that are playing or went quiet less than `linger` seconds ago.
    func recent(now: Double, linger: Int) -> Set<String> {
        var result = playing
        for (id, heard) in lastHeard where now - heard < Double(linger) {
            result.insert(id)
        }
        return result
    }

    /// When the next quiet row runs out of time, or nil when none is waiting.
    func nextExpiry(now: Double, linger: Int) -> Double? {
        lastHeard.lazy
            .filter { !playing.contains($0.key) }
            .map { $0.value + Double(linger) }
            .filter { $0 > now }
            .min()
    }
}
