// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// "Hide inactive apps" keeps a row for a while after it goes quiet. The time
/// runs from the moment the sound stopped, and a row that left the mixer is
/// forgotten.
enum MixerRecentActivityTests {
    static func run(_ suite: TestSuite) {
        var activity = MixerRecentActivity()
        suite.expect(activity.recent(now: 0, linger: 30).isEmpty && activity.nextExpiry(now: 0, linger: 30) == nil,
                     "nothing is recent before any app has been heard")

        activity.observe(playing: ["music"], present: ["music", "mail"], now: 100)
        suite.expect(activity.recent(now: 100, linger: 30) == ["music"],
                     "a playing app is recent and a silent one is not")
        suite.expect(activity.recent(now: 5000, linger: 30) == ["music"],
                     "an app stays recent for as long as it keeps playing")
        suite.expect(activity.nextExpiry(now: 5000, linger: 30) == nil,
                     "a playing app has no time to run out")

        // It played from 100 to 700; the thirty seconds start at 700.
        activity.observe(playing: [], present: ["music", "mail"], now: 700)
        suite.expect(activity.recent(now: 729, linger: 30) == ["music"],
                     "the time to linger runs from when the sound stopped")
        suite.expect(activity.recent(now: 730, linger: 30).isEmpty,
                     "a quiet app leaves once its time is up")
        suite.expectClose(activity.nextExpiry(now: 700, linger: 30) ?? -1, 730,
                          "the next wake is when the quiet app expires")
        suite.expect(activity.nextExpiry(now: 731, linger: 30) == nil,
                     "an expired app asks for no further wake")
        suite.expect(activity.recent(now: 750, linger: 60) == ["music"],
                     "a longer choice keeps the same app listed")

        activity.observe(playing: ["music"], present: ["music", "mail"], now: 720)
        activity.observe(playing: [], present: ["music", "mail"], now: 725)
        suite.expect(activity.recent(now: 750, linger: 30) == ["music"],
                     "playing again restarts the time to linger")

        activity.observe(playing: ["mail"], present: ["mail"], now: 726)
        suite.expect(activity.recent(now: 727, linger: 30) == ["mail"],
                     "an app that quit is forgotten at once")
        activity.observe(playing: ["ghost"], present: ["mail"], now: 728)
        suite.expect(!activity.recent(now: 728, linger: 30).contains("ghost"),
                     "a row the mixer does not list is never recent")

        suite.expect(MixerRecentActivity.lingerChoices.contains(MixerRecentActivity.defaultLinger),
                     "the default time to linger is one of the choices")
        suite.expect(MixerRecentActivity.sanitizedLinger(60) == 60
                        && MixerRecentActivity.sanitizedLinger(0) == MixerRecentActivity.defaultLinger
                        && MixerRecentActivity.sanitizedLinger(-5) == MixerRecentActivity.defaultLinger
                        && MixerRecentActivity.sanitizedLinger(999_999) == MixerRecentActivity.defaultLinger,
                     "a stored time that is not offered falls back to the default")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.mixerInactiveAppLingerSeconds] as? Int
                        == MixerRecentActivity.defaultLinger,
                     "the time to linger is registered, so it is backed up with the other settings")
    }
}
