// SPDX-License-Identifier: GPL-3.0-or-later

import CoreAudio
import Foundation

/// The probe on an engine's output measures each side's loudest sample, only
/// while a meter is showing, and starts again each time it is read.
enum MixerOutputProbeTests {
    private static func measure(_ probe: MixerOutputProbe, _ samples: [Float], channels: UInt32, frames: Int) {
        var samples = samples
        samples.withUnsafeMutableBufferPointer { pointer in
            let list = AudioBufferList.allocate(maximumBuffers: 1)
            defer { free(list.unsafeMutablePointer) }
            list[0] = AudioBuffer(mNumberChannels: channels,
                                  mDataByteSize: UInt32(pointer.count * MemoryLayout<Float>.size),
                                  mData: pointer.baseAddress)
            probe.measure(list, frames: frames)
        }
    }

    static func run(_ suite: TestSuite) {
        let probe = MixerOutputProbe()
        measure(probe, [0.5, -0.9, 0.2, 0.1], channels: 2, frames: 2)
        suite.expect(probe.takePeaks() == (0, 0), "nothing is measured until a meter is showing")

        probe.isMetering = true
        measure(probe, [0.5, -0.9, 0.2, 0.1], channels: 2, frames: 2)
        let first = probe.takePeaks()
        suite.expect(first.left == 0.5 && first.right == 0.9, "each side keeps its own loudest sample, whatever its sign")
        suite.expect(probe.takePeaks() == (0, 0), "reading the peaks starts the measurement again")

        measure(probe, [0.1, 0.1], channels: 2, frames: 1)
        measure(probe, [0.7, 0.2], channels: 2, frames: 1)
        measure(probe, [0.3, 0.6], channels: 2, frames: 1)
        let held = probe.takePeaks()
        suite.expect(held.left == 0.7 && held.right == 0.6, "the loudest of several blocks is kept until it is read")

        measure(probe, [0.4, 0.8, 0.1], channels: 1, frames: 3)
        let mono = probe.takePeaks()
        suite.expect(mono.left == 0.8 && mono.right == 0.8, "one channel counts for both sides")

        measure(probe, [0.1, 0.2, 0.9, 0.9, 0.3, 0.4, 0.9, 0.9], channels: 4, frames: 2)
        let wide = probe.takePeaks()
        suite.expect(wide.left == 0.3 && wide.right == 0.4, "on a wider output only the front pair is measured")

        measure(probe, [0.2, 0.2, 0.95, 0.95], channels: 2, frames: 1)
        let short = probe.takePeaks()
        suite.expect(short.left == 0.2 && short.right == 0.2, "frames past the ones just rendered are not measured")
        measure(probe, [0.2, 0.2], channels: 2, frames: 64)
        suite.expect(probe.takePeaks().left == 0.2, "a frame count past the buffer stops at the buffer")

        measure(probe, [0.6, 0.6], channels: 2, frames: 1)
        probe.isMetering = false
        suite.expect(probe.takePeaks() == (0, 0) && !probe.isMetering, "turning the meter off clears what was measured")
        measure(probe, [0.6, 0.6], channels: 2, frames: 1)
        suite.expect(probe.takePeaks() == (0, 0), "and nothing more is measured while it is off")
    }
}
