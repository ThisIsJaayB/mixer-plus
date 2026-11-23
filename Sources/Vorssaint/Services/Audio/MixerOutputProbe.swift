// SPDX-License-Identifier: GPL-3.0-or-later

import Accelerate
import CoreAudio
import Darwin

/// Measures what an engine is about to play: the loudest sample of each
/// side, after effects, the fader and the pan. This is what a mixing desk's
/// channel meter shows, and what a listen-only tap on the app cannot see.
///
/// It measures only while a meter is on screen. The audio thread reads one
/// flag and, when it is set, writes two floats; nothing is allocated or
/// locked, and with the flag clear the cost is that one read.
final class MixerOutputProbe {
    private var metering: Int32 = 0
    private var left: Int32 = 0
    private var right: Int32 = 0

    /// Any thread. Turning it off also clears what was measured.
    var isMetering: Bool {
        get { OSAtomicAdd32Barrier(0, &metering) != 0 }
        set {
            Self.store(newValue ? 1 : 0, in: &metering)
            if !newValue {
                Self.store(0, in: &left)
                Self.store(0, in: &right)
            }
        }
    }

    /// Each side's loudest sample since the last call, 0 (silence) upwards.
    /// A block landing at the same moment may be missed, which a meter
    /// refreshed many times a second cannot show.
    func takePeaks() -> (left: Float, right: Float) {
        let peaks = (Self.float(&left), Self.float(&right))
        if peaks.0 != 0 { Self.store(0, in: &left) }
        if peaks.1 != 0 { Self.store(0, in: &right) }
        return peaks
    }

    /// Audio thread. Looks at the first two channels of the `frames` just
    /// rendered; one channel alone counts for both sides.
    func measure(_ output: UnsafeMutableAudioBufferListPointer, frames: Int) {
        guard OSAtomicAdd32Barrier(0, &metering) != 0, frames > 0 else { return }
        var index = 0
        var peaks: (Float, Float) = (0, 0)
        var sides = 0
        for buffer in output where buffer.mNumberChannels > 0 {
            let channels = Int(buffer.mNumberChannels)
            defer { index += channels }
            guard index < 2 else { break }
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let count = vDSP_Length(min(frames, Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels)))
            for channel in 0..<min(channels, 2 - index) {
                var peak: Float = 0
                vDSP_maxmgv(data + channel, vDSP_Stride(channels), &peak, count)
                if index + channel == 0 { peaks.0 = peak } else { peaks.1 = peak }
                sides += 1
            }
        }
        guard sides > 0 else { return }
        if sides == 1 { peaks.1 = peaks.0 }
        // Only this thread raises a peak, so a read then a write is enough.
        if peaks.0 > Self.float(&left) { Self.store(Int32(bitPattern: peaks.0.bitPattern), in: &left) }
        if peaks.1 > Self.float(&right) { Self.store(Int32(bitPattern: peaks.1.bitPattern), in: &right) }
    }

    private static func float(_ bits: inout Int32) -> Float {
        Float(bitPattern: UInt32(bitPattern: OSAtomicAdd32Barrier(0, &bits)))
    }

    private static func store(_ value: Int32, in bits: inout Int32) {
        while true {
            let current = OSAtomicAdd32Barrier(0, &bits)
            if OSAtomicCompareAndSwap32Barrier(current, value, &bits) { return }
        }
    }
}
