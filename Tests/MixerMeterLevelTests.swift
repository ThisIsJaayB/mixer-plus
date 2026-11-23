// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A mixer row's meter jumps to a louder peak, falls back at a steady rate,
/// and never leaves the range it is drawn in.
enum MixerMeterLevelTests {
    static func run(_ suite: TestSuite) {
        var meter = MixerMeterLevel()
        suite.expect(meter.level == 0 && meter.isAtRest && !meter.isHot, "a new meter is empty")

        meter.advance(peak: 1, elapsed: 0.1)
        suite.expectClose(meter.level, 1, "full scale fills the meter at once")
        suite.expect(meter.isHot && !meter.isAtRest, "full scale reaches the limiter's range")

        meter.advance(peak: 0, elapsed: 0.5)
        suite.expectClose(Double(meter.shownDB), -10, "silence lets the meter fall 20 dB a second")
        suite.expect(!meter.isHot, "a falling meter is no longer hot")
        meter.advance(peak: 0.1, elapsed: 0.5)
        suite.expectClose(Double(meter.shownDB), -20, "a quieter peak does not hold the meter up", tol: 0.001)
        meter.advance(peak: 0.5, elapsed: 0.1)
        suite.expectClose(Double(meter.shownDB), Double(20 * log10(Float(0.5))),
                          "a louder peak takes over at once", tol: 0.001)
        suite.expectClose(meter.level, 0.9, "minus 6 dB draws nine tenths of the bar", tol: 0.005)

        meter.advance(peak: 0, elapsed: 10)
        suite.expect(meter.level == 0 && meter.isAtRest, "a long silence empties the meter")

        meter.advance(peak: 4, elapsed: 0.1)
        suite.expect(meter.level == 1 && meter.shownDB == 0, "a boosted peak cannot overfill the meter")
        for bad in [Float.nan, .infinity, -1] {
            var broken = MixerMeterLevel()
            broken.advance(peak: bad, elapsed: 0.1)
            suite.expect(broken.level == 0 && broken.isAtRest, "a peak of \(bad) draws nothing")
        }
        var early = MixerMeterLevel()
        early.advance(peak: 0.5, elapsed: -3)
        suite.expectClose(early.level, 0.9, "a clock that ran backwards cannot raise the meter", tol: 0.005)

        meter = MixerMeterLevel()
        meter.advance(peak: 0.0005, elapsed: 0.1)
        suite.expect(meter.level == 0, "a peak under the floor draws nothing")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.mixerShowLevelMeters] as? Bool == true,
                     "level meters are on unless turned off, and backed up with the other settings")
    }
}
