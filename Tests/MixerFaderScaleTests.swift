// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// An app's fader gives most of its length to 0–100% and the rest to the
/// boost. A place along it and the volume it stands for must agree both ways.
enum MixerFaderScaleTests {
    static func run(_ suite: TestSuite) {
        let unity = MixerFaderScale.unityPosition
        suite.expect(unity >= 0.75 && unity <= 0.8, "100% sits three quarters to four fifths of the way along")
        suite.expectClose(MixerFaderScale.volume(atPosition: 0, maximum: 2), 0, "the left end is silence")
        suite.expectClose(MixerFaderScale.volume(atPosition: unity, maximum: 2), 1, "the mark is exactly 100%")
        suite.expectClose(MixerFaderScale.volume(atPosition: 1, maximum: 2), 2, "the right end is the full boost")
        suite.expectClose(MixerFaderScale.volume(atPosition: unity / 2, maximum: 2), 0.5,
                          "half way to the mark is 50%")
        suite.expectClose(MixerFaderScale.volume(atPosition: (unity + 1) / 2, maximum: 2), 1.5,
                          "half way through the boost range is 150%")
        suite.expectClose(MixerFaderScale.position(forVolume: 1, maximum: 2), unity, "100% is drawn on the mark")
        suite.expectClose(MixerFaderScale.position(forVolume: 0.63, maximum: 2), 0.63 * unity,
                          "a level below 100% is drawn in proportion")

        for step in 0...40 {
            let volume = Double(step) / 20
            let place = MixerFaderScale.position(forVolume: volume, maximum: 2)
            suite.expectClose(MixerFaderScale.volume(atPosition: place, maximum: 2), volume,
                              "\(Int(volume * 100))% survives the trip to the fader and back")
        }
        suite.expect(MixerFaderScale.position(forVolume: 0.4, maximum: 2)
                        < MixerFaderScale.position(forVolume: 0.41, maximum: 2)
                        && MixerFaderScale.position(forVolume: 1.4, maximum: 2)
                        < MixerFaderScale.position(forVolume: 1.41, maximum: 2),
                     "a louder level is always farther right")

        suite.expectClose(MixerFaderScale.volume(atPosition: -3, maximum: 2), 0, "left of the fader is silence")
        suite.expectClose(MixerFaderScale.volume(atPosition: 9, maximum: 2), 2, "right of the fader is the maximum")
        suite.expectClose(MixerFaderScale.volume(atPosition: .nan, maximum: 2), 0, "no place at all is silence")
        suite.expectClose(MixerFaderScale.position(forVolume: 5, maximum: 2), 1, "a level over the maximum stops at the end")
        suite.expectClose(MixerFaderScale.position(forVolume: .infinity, maximum: 2), 0, "a broken level draws at the start")
        suite.expectClose(MixerFaderScale.volume(atPosition: 0.5, maximum: 1), 0.5,
                          "a fader with no boost is 0–100% end to end")
        suite.expectClose(MixerFaderScale.position(forVolume: 0.5, maximum: 1), 0.5,
                          "and draws a level in plain proportion")

        suite.expectClose(MixerFaderScale.draggedVolume(atPosition: unity + 0.008, maximum: 2), 1,
                          "a drag just past the mark lands on 100%")
        suite.expectClose(MixerFaderScale.draggedVolume(atPosition: unity - 0.008, maximum: 2), 1,
                          "a drag just short of the mark lands on 100%")
        suite.expect(MixerFaderScale.draggedVolume(atPosition: unity + 0.03, maximum: 2) > 1.05,
                     "a drag clear of the mark is a boost")
        suite.expect(MixerFaderScale.draggedVolume(atPosition: unity - 0.03, maximum: 2) < 0.97,
                     "a drag clear of the mark on the left is below 100%")
    }
}
