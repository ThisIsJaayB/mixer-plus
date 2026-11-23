// SPDX-License-Identifier: GPL-3.0-or-later

import CoreAudio
import Foundation

/// An app's pan turns the far channel down and leaves the near one alone:
/// centre changes nothing, no position makes anything louder, and a change
/// slides across a block instead of stepping.
enum MixerBalanceTests {
    static func run(_ suite: TestSuite) {
        let centre = MixerBalance.gains(pan: 0)
        suite.expect(centre.left == 1 && centre.right == 1, "centre leaves both channels at full level")
        let right = MixerBalance.gains(pan: 1)
        suite.expectClose(Double(right.left), 0, "hard right silences the left channel", tol: 1e-6)
        suite.expect(right.right == 1, "hard right leaves the right channel alone")
        let left = MixerBalance.gains(pan: -1)
        suite.expectClose(Double(left.right), 0, "hard left silences the right channel", tol: 1e-6)
        suite.expect(left.left == 1, "hard left leaves the left channel alone")
        let half = MixerBalance.gains(pan: 0.5)
        suite.expectClose(Double(half.left), cos(Double.pi / 4), "half right follows the cosine curve", tol: 1e-6)
        for step in -20...20 {
            let gains = MixerBalance.gains(pan: Float(step) / 10)
            suite.expect(gains.left <= 1 && gains.right <= 1 && gains.left >= 0 && gains.right >= 0,
                         "a pan of \(step * 10) never boosts a channel or inverts it")
        }

        suite.expect(MixerBalance.sanitized(3) == 1 && MixerBalance.sanitized(-3) == -1
                        && MixerBalance.sanitized(.nan) == 0 && MixerBalance.sanitized(.infinity) == 0,
                     "a pan out of range or not a number is brought back")
        suite.expect(MixerBalance.isCentred(0.004) && !MixerBalance.isCentred(0.006) && MixerBalance.isCentred(.nan),
                     "a pan within half a step of the middle is centre")
        suite.expect(MixerBalance.displayValue(-0.3) == -30 && MixerBalance.displayValue(1) == 100
                        && MixerBalance.displayValue(.nan) == 0, "the knob reads out -100 to 100")

        let balance = MixerBalance()
        balance.pan = 5
        suite.expect(balance.pan == 1, "a stored pan is clamped")
        balance.pan = .nan
        suite.expect(balance.pan == 0, "a stored pan that is not a number is centre")

        // Interleaved stereo, the usual output.
        func render(_ balance: MixerBalance, frames: Int = 8) -> [Float] {
            var samples = [Float](repeating: 1, count: frames * 2)
            samples.withUnsafeMutableBufferPointer { pointer in
                let list = AudioBufferList.allocate(maximumBuffers: 1)
                defer { free(list.unsafeMutablePointer) }
                list[0] = AudioBuffer(mNumberChannels: 2,
                                      mDataByteSize: UInt32(frames * 2 * MemoryLayout<Float>.size),
                                      mData: pointer.baseAddress)
                balance.apply(to: list, frames: frames)
            }
            return samples
        }
        let untouched = MixerBalance()
        suite.expect(render(untouched).allSatisfy { $0 == 1 }, "a centred app's samples are not touched")

        let panned = MixerBalance()
        panned.pan = 1
        let first = render(panned)
        suite.expect(stride(from: 0, to: 16, by: 2).allSatisfy { abs(first[$0]) < 1e-6 }
                        && stride(from: 1, to: 16, by: 2).allSatisfy { first[$0] == 1 },
                     "an engine's first block plays at its pan, with nothing to slide from")

        let moving = MixerBalance()
        _ = render(moving)
        moving.pan = 1
        let slide = render(moving)
        let lefts = stride(from: 0, to: 16, by: 2).map { slide[$0] }
        suite.expect(lefts.first! < 1 && lefts.first! > 0.8 && abs(lefts.last!) < 1e-6
                        && zip(lefts, lefts.dropFirst()).allSatisfy { $0 > $1 },
                     "a pan change slides across the block and ends exactly on the new gain")
        let settled = render(moving)
        suite.expect(stride(from: 0, to: 16, by: 2).allSatisfy { abs(settled[$0]) < 1e-6 },
                     "the block after a change holds the new pan")
        moving.pan = 0
        _ = render(moving)
        suite.expect(render(moving).allSatisfy { $0 == 1 }, "back at centre the samples are untouched again")

        // Two mono buffers, as a device with separate channel streams gives.
        var leftChannel = [Float](repeating: 1, count: 8)
        var rightChannel = [Float](repeating: 1, count: 8)
        let split = MixerBalance()
        split.pan = -1
        leftChannel.withUnsafeMutableBufferPointer { l in
            rightChannel.withUnsafeMutableBufferPointer { r in
                let list = AudioBufferList.allocate(maximumBuffers: 2)
                defer { free(list.unsafeMutablePointer) }
                let bytes = UInt32(8 * MemoryLayout<Float>.size)
                list[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: bytes, mData: l.baseAddress)
                list[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: bytes, mData: r.baseAddress)
                split.apply(to: list, frames: 8)
            }
        }
        suite.expect(leftChannel.allSatisfy { $0 == 1 } && rightChannel.allSatisfy { abs($0) < 1e-6 },
                     "separate channel buffers are panned like interleaved ones")

        // One channel: nothing to balance, and nothing read past the buffer.
        var mono = [Float](repeating: 1, count: 8)
        let single = MixerBalance()
        single.pan = 1
        mono.withUnsafeMutableBufferPointer { pointer in
            let list = AudioBufferList.allocate(maximumBuffers: 1)
            defer { free(list.unsafeMutablePointer) }
            list[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(8 * MemoryLayout<Float>.size),
                                  mData: pointer.baseAddress)
            single.apply(to: list, frames: 8)
        }
        suite.expect(mono.allSatisfy { $0 == 1 }, "a single output channel is left alone")

        // More channels than two: only the front pair is balanced.
        var surround = [Float](repeating: 1, count: 4 * 4)
        let wide = MixerBalance()
        wide.pan = 1
        surround.withUnsafeMutableBufferPointer { pointer in
            let list = AudioBufferList.allocate(maximumBuffers: 1)
            defer { free(list.unsafeMutablePointer) }
            list[0] = AudioBuffer(mNumberChannels: 4, mDataByteSize: UInt32(16 * MemoryLayout<Float>.size),
                                  mData: pointer.baseAddress)
            // Asked for more frames than the buffer holds: it must stop at four.
            wide.apply(to: list, frames: 64)
        }
        suite.expect((0..<4).allSatisfy { abs(surround[$0 * 4]) < 1e-6 && surround[$0 * 4 + 1] == 1
                                            && surround[$0 * 4 + 2] == 1 && surround[$0 * 4 + 3] == 1 },
                     "on a wider output only the first two channels are panned")

        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.appPans),
                     "saved pans are backed up with the other mixer settings")
    }
}
