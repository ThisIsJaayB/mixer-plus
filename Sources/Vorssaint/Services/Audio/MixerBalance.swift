// SPDX-License-Identifier: GPL-3.0-or-later

import Accelerate
import CoreAudio
import Darwin

/// An app's pan, applied to what its engine has rendered.
///
/// It is a balance control: the far channel is turned down on a cosine curve
/// and the near one stays at full level. Centre therefore changes nothing,
/// and no position makes a channel louder, so the boost limiter that follows
/// never has more to do because of a pan.
///
/// The pan is one value any thread may replace; everything else is touched
/// only by the audio thread, which allocates nothing and takes no lock. Each
/// block slides from the gains of the last one to the new ones, so turning
/// the knob does not click.
final class MixerBalance {
    private var bits: Int32 = 0
    private var left: Float = 1
    private var right: Float = 1
    private var primed = false

    /// −1 (left) … 0 (centre) … +1 (right).
    var pan: Float {
        get { Float(bitPattern: UInt32(bitPattern: OSAtomicAdd32Barrier(0, &bits))) }
        set {
            let replacement = Int32(bitPattern: Float(Self.sanitized(Double(newValue))).bitPattern)
            while true {
                let current = OSAtomicAdd32Barrier(0, &bits)
                if OSAtomicCompareAndSwap32Barrier(current, replacement, &bits) { return }
            }
        }
    }

    /// A pan that is not a number is centre; one out of range is the nearest end.
    static func sanitized(_ pan: Double) -> Double {
        pan.isFinite ? min(max(pan, -1), 1) : 0
    }

    /// Whether a pan is close enough to centre to be centre: half a step of
    /// the −100…100 the knob shows, as `isUnity` allows a fader at 100%.
    static func isCentred(_ pan: Double) -> Bool {
        abs(sanitized(pan)) < 0.005
    }

    /// The pan as the knob reads it out: −100 (left) … 0 … 100 (right).
    static func displayValue(_ pan: Double) -> Int {
        Int((sanitized(pan) * 100).rounded())
    }

    /// The channel gains for a pan position.
    static func gains(pan: Float) -> (left: Float, right: Float) {
        let p = min(max(pan, -1), 1)
        return (p > 0 ? cos(p * .pi / 2) : 1, p < 0 ? cos(-p * .pi / 2) : 1)
    }

    /// Audio thread. Scales the first two output channels of the `frames`
    /// just rendered. With one channel to play on there is nothing to balance.
    func apply(to output: UnsafeMutableAudioBufferListPointer, frames: Int) {
        let target = Self.gains(pan: pan)
        let start = primed ? (left: left, right: right) : target
        primed = true
        left = target.left
        right = target.right
        guard start != (1, 1) || target != (1, 1), frames > 0 else { return }

        var first: (data: UnsafeMutablePointer<Float>, stride: Int)?
        var second: (data: UnsafeMutablePointer<Float>, stride: Int)?
        var index = 0
        var count = frames
        for buffer in output where buffer.mNumberChannels > 0 {
            let channels = Int(buffer.mNumberChannels)
            defer { index += channels }
            guard index < 2 else { break }
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { return }
            count = min(count, Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels))
            if index == 0 { first = (data, channels) }
            if index + channels > 1 { second = (data + (1 - index), channels) }
        }
        guard let first, let second, count > 0 else { return }
        Self.scale(first.data, stride: first.stride, count: count, from: start.left, to: target.left)
        Self.scale(second.data, stride: second.stride, count: count, from: start.right, to: target.right)
    }

    /// Multiplies one channel by a gain sliding from `start` to `end` across
    /// the block, the last sample exactly at `end`.
    private static func scale(_ data: UnsafeMutablePointer<Float>, stride: Int, count: Int,
                              from start: Float, to end: Float) {
        if start == end {
            guard end != 1 else { return }
            var gain = end
            vDSP_vsmul(data, vDSP_Stride(stride), &gain, data, vDSP_Stride(stride), vDSP_Length(count))
        } else {
            var step = (end - start) / Float(count)
            var ramp = start + step
            vDSP_vrampmul(data, vDSP_Stride(stride), &ramp, &step, data, vDSP_Stride(stride), vDSP_Length(count))
        }
    }
}
