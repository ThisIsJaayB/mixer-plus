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

/// The readout beside a fader holds the loudest recent peak for a moment,
/// then falls with the meter, and prints levels the way a desk does.
enum MixerMeterHoldTests {
    static func run(_ suite: TestSuite) {
        var meter = MixerMeterLevel()
        suite.expect(meter.heldDB == MixerMeterLevel.floorDB, "a new readout holds nothing")
        meter.advance(peak: 0.5, elapsed: 0.1)
        let held = meter.heldDB
        suite.expectClose(Double(held), Double(20 * log10(Float(0.5))), "a peak is held at its level", tol: 0.001)
        meter.advance(peak: 0, elapsed: 1)
        suite.expect(meter.heldDB == held && !meter.isAtRest, "the peak stays while the meter falls")
        meter.advance(peak: 0.25, elapsed: 0.3)
        suite.expect(meter.heldDB == held, "a quieter peak does not replace the held one")
        meter.advance(peak: 0, elapsed: 0.5)
        suite.expect(meter.heldDB < held, "after its time the held peak starts to fall")
        meter.advance(peak: 0.9, elapsed: 0.1)
        suite.expect(meter.heldDB > held, "a louder peak takes the readout at once")
        for _ in 0..<100 { meter.advance(peak: 0, elapsed: 0.1) }
        suite.expect(meter.heldDB == MixerMeterLevel.floorDB && meter.isAtRest,
                     "a long silence clears the readout, and only then is the meter at rest")
        meter.advance(peak: 9, elapsed: 0.1)
        suite.expect(meter.heldDB == 0, "a boosted peak is held at full scale, not above it")

        let mark = Locale.current.decimalSeparator ?? "."
        suite.expect(MixerMeterLevel.readout(0) == "0\(mark)0" && MixerMeterLevel.readout(-5.74) == "−5\(mark)7"
                        && MixerMeterLevel.readout(-17.4) == "−17" && MixerMeterLevel.readout(3.5) == "+3\(mark)5",
                     "levels print with one decimal near the top and whole numbers below −10")
        suite.expect(MixerMeterLevel.readout(-60) == "−∞" && MixerMeterLevel.readout(-.infinity) == "−∞"
                        && MixerMeterLevel.readout(.nan) == "−∞", "the floor and anything broken print as −∞")
        suite.expect(MixerMeterLevel.readout(-9.96) == "−10", "a level that rounds to −10 drops its decimal")

        // The output's meter sits after its fader.
        suite.expectClose(Double(MixerMeterLevel.outputGain(decibels: 0, volume: 1)), 1,
                          "an output at full volume passes the level unchanged")
        suite.expectClose(Double(MixerMeterLevel.outputGain(decibels: -20, volume: 0.5)), 0.1,
                          "an output that reports its level is read in decibels, whatever the slider says")
        suite.expectClose(Double(MixerMeterLevel.outputGain(decibels: -6.0206, volume: nil)), 0.5,
                          "minus six decibels halves the level", tol: 0.0005)
        suite.expect(MixerMeterLevel.outputGain(decibels: -.infinity, volume: 0.3) == 0,
                     "an output at the bottom of its range plays nothing")
        suite.expect(MixerMeterLevel.outputGain(decibels: 12, volume: 1) == 1,
                     "an output cannot raise the meter above the level it was given")
        suite.expectClose(Double(MixerMeterLevel.outputGain(decibels: nil, volume: 0.5)), 0.25,
                          "an output that reports no level is read from the slider, on the app faders' curve")
        suite.expect(MixerMeterLevel.outputGain(decibels: .nan, volume: 0.5) == 0.25,
                     "a level that is not a number falls back to the slider")
        suite.expect(MixerMeterLevel.outputGain(decibels: nil, volume: 0) == 0
                        && MixerMeterLevel.outputGain(decibels: nil, volume: 7) == 1
                        && MixerMeterLevel.outputGain(decibels: nil, volume: -2) == 0,
                     "a slider out of range is brought back to its ends")
        suite.expect(MixerMeterLevel.outputGain(decibels: nil, volume: nil) == 1
                        && MixerMeterLevel.outputGain(decibels: nil, volume: .nan) == 1,
                     "an output with no volume control at all leaves the level alone")
    }
}
