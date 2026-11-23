// SPDX-License-Identifier: GPL-3.0-or-later

import Accelerate
import CoreAudio
import Darwin

/// Something that processes an engine's rendered audio in place, such as a
/// chain of Audio Unit effects. `process` runs on the realtime audio thread:
/// it must not allocate, take a lock or wait.
protocol MixerInsertStage: AnyObject {
    func process(_ buffers: UnsafeMutableAudioBufferListPointer, frames: Int)
}

/// Where an engine's insert effects plug in, and the fader that follows them.
///
/// Effects sit before the fader, as on a mixing desk, so a compressor hears
/// the app at its own level whatever the slider says. With a stage in place
/// the engine therefore renders at unity, the stage runs, and the gain is
/// applied here afterwards. With no stage the engine applies the gain itself
/// while it renders, exactly as it did before effects existed, and this
/// object touches nothing.
///
/// The stage can be replaced while audio runs. It is held through one atomic
/// word: the audio thread loads whichever stage is current once per block,
/// and a replaced stage is released a second later, when no block can still
/// be using it. Everything else here is touched only by the audio thread.
final class MixerInserts {
    private final class Box {
        let stage: any MixerInsertStage
        init(_ stage: any MixerInsertStage) { self.stage = stage }
    }

    /// A retained `Unmanaged<Box>` as its bit pattern, or 0 for no stage.
    private var bits: Int64 = 0
    /// The gain this object put on the last block, which the next slides from.
    private var applied: Float = 1
    private var primed = false

    deinit { Self.release(OSAtomicAdd64Barrier(0, &bits)) }

    /// Any thread but the audio thread. Nil takes the effects out of the path.
    func setStage(_ stage: (any MixerInsertStage)?) {
        let replacement = stage.map { Int64(Int(bitPattern: Unmanaged.passRetained(Box($0)).toOpaque())) } ?? 0
        while true {
            let current = OSAtomicAdd64Barrier(0, &bits)
            guard OSAtomicCompareAndSwap64Barrier(current, replacement, &bits) else { continue }
            guard current != 0 else { return }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) { Self.release(current) }
            return
        }
    }

    private static func release(_ bits: Int64) {
        guard let pointer = UnsafeRawPointer(bitPattern: Int(bits)) else { return }
        Unmanaged<Box>.fromOpaque(pointer).release()
    }

    /// Audio thread, once per block. The answer decides both the gain the
    /// engine renders with and what `process` does, so a stage swapped in
    /// the middle of a block cannot apply the fader twice or not at all.
    func load() -> UnsafeRawPointer? {
        UnsafeRawPointer(bitPattern: Int(OSAtomicAdd64Barrier(0, &bits)))
    }

    /// The gain the engine should render with: its own when there are no
    /// effects, unity when the fader comes after them.
    static func renderGain(_ gain: Float, stage: UnsafeRawPointer?) -> Float {
        stage == nil ? gain : 1
    }

    /// Audio thread. Runs the stage `load` returned over the `frames` just
    /// rendered, then applies the fader. Moving between "no effects" and
    /// "effects" slides the gain from one side of the stage to the other, so
    /// adding the first effect or removing the last does not click.
    func process(_ stage: UnsafeRawPointer?, _ output: UnsafeMutableAudioBufferListPointer,
                 frames: Int, gain: Float) {
        if let stage {
            Unmanaged<Box>.fromOpaque(stage)._withUnsafeGuaranteedRef { $0.stage.process(output, frames: frames) }
        }
        let target: Float = stage == nil ? 1 : (gain.isFinite ? gain : 0)
        let start = primed ? applied : target
        primed = true
        applied = target
        guard start != 1 || target != 1, frames > 0 else { return }
        for buffer in output where buffer.mNumberChannels > 0 {
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let channels = Int(buffer.mNumberChannels)
            let count = min(frames, Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels))
            guard count > 0 else { continue }
            if start == target {
                var gain = target
                vDSP_vsmul(data, 1, &gain, data, 1, vDSP_Length(count * channels))
                continue
            }
            // vDSP leaves its start value where the ramp ended, so every
            // channel starts again from the same place.
            for channel in 0..<channels {
                var step = (target - start) / Float(count)
                var ramp = start + step
                vDSP_vrampmul(data + channel, vDSP_Stride(channels), &ramp, &step,
                              data + channel, vDSP_Stride(channels), vDSP_Length(count))
            }
        }
    }
}
