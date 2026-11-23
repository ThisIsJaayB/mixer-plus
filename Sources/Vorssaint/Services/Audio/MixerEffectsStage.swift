// SPDX-License-Identifier: GPL-3.0-or-later

import Accelerate
import AVFoundation

/// Runs an app's chain of Audio Unit effects inside its mixer engine.
///
/// The effects live in a small AVAudioEngine in realtime manual rendering
/// mode: a source node feeds it the engine's audio, the effects are connected
/// in order, and the audio callback pulls the result. (Calling an Audio
/// Unit's render block directly fails with "no connection" for bridged
/// effects; the engine handles that.)
///
/// Effects are stereo. Each block copies the first two channels in and the
/// result back; any further channels pass through untouched. Every buffer is
/// allocated up front. If a render fails, or a block is longer than the
/// engine was set up for, the audio passes through unprocessed.
final class MixerEffectsStage: MixerInsertStage {
    /// The longest block the stage processes. Output devices rarely ask for
    /// more than 1024 frames; a longer block plays without effects.
    static let maximumFrames = 4096

    private let engine: AVAudioEngine
    private let units: [AVAudioUnit]
    private let render: AVAudioEngineManualRenderingBlock
    /// Left then right, `maximumFrames` each.
    private let input: UnsafeMutablePointer<Float>
    private let output: UnsafeMutablePointer<Float>
    private let outputList: UnsafeMutableAudioBufferListPointer

    /// Builds and starts the engine. An effect that cannot take stereo at
    /// this rate is left out (connecting it would raise an exception). Nil
    /// when none is usable.
    init?(units candidates: [AVAudioUnit], sampleRate: Double) {
        guard sampleRate > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else { return nil }
        let usable = candidates.filter { unit in
            let audioUnit = unit.auAudioUnit
            return audioUnit.inputBusses.count > 0 && audioUnit.outputBusses.count > 0
                && (try? audioUnit.inputBusses[0].setFormat(format)) != nil
                && (try? audioUnit.outputBusses[0].setFormat(format)) != nil
        }
        guard !usable.isEmpty else { return nil }

        let capacity = Self.maximumFrames
        let input = UnsafeMutablePointer<Float>.allocate(capacity: 2 * capacity)
        input.initialize(repeating: 0, count: 2 * capacity)
        let output = UnsafeMutablePointer<Float>.allocate(capacity: 2 * capacity)
        output.initialize(repeating: 0, count: 2 * capacity)
        let outputList = AudioBufferList.allocate(maximumBuffers: 2)
        let engine = AVAudioEngine()

        do {
            try engine.enableManualRenderingMode(.realtime, format: format,
                                                 maximumFrameCount: AVAudioFrameCount(capacity))
            let source = AVAudioSourceNode(format: format) { _, _, frameCount, bufferList in
                let list = UnsafeMutableAudioBufferListPointer(bufferList)
                let byteCount = min(Int(frameCount), capacity) * MemoryLayout<Float>.size
                for channel in 0..<min(list.count, 2) {
                    list[channel].mData?.copyMemory(from: input + channel * capacity, byteCount: byteCount)
                    list[channel].mDataByteSize = UInt32(byteCount)
                }
                return noErr
            }
            engine.attach(source)
            var previous: AVAudioNode = source
            for unit in usable {
                engine.attach(unit)
                engine.connect(previous, to: unit, format: format)
                previous = unit
            }
            engine.connect(previous, to: engine.mainMixerNode, format: format)
            try engine.start()
        } catch {
            input.deallocate()
            output.deallocate()
            free(outputList.unsafeMutablePointer)
            return nil
        }
        self.engine = engine
        self.units = usable
        self.input = input
        self.output = output
        self.outputList = outputList
        render = engine.manualRenderingBlock
    }

    deinit {
        input.deallocate()
        output.deallocate()
        free(outputList.unsafeMutablePointer)
    }

    /// Stops the engine and lets the effects go, so they can join a new one.
    /// Only once the audio thread can no longer be rendering this stage.
    func teardown() {
        engine.stop()
        for unit in units { engine.detach(unit) }
    }

    func process(_ buffers: UnsafeMutableAudioBufferListPointer, frames requested: Int) {
        // The first two channels, wherever they sit: one interleaved buffer
        // or a buffer each.
        var left: (data: UnsafeMutablePointer<Float>, stride: Int)?
        var right: (data: UnsafeMutablePointer<Float>, stride: Int)?
        var index = 0
        var frames = requested
        for buffer in buffers where buffer.mNumberChannels > 0 {
            let channels = Int(buffer.mNumberChannels)
            defer { index += channels }
            guard index < 2 else { break }
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { return }
            frames = min(frames, Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels))
            if index == 0 { left = (data, channels) }
            if index + channels > 1 { right = (data + (1 - index), channels) }
        }
        let capacity = Self.maximumFrames
        guard let left, frames > 0, frames <= capacity else { return }
        // One channel plays through both sides of the effects and takes the left back.
        let feed = right ?? left

        // Interleaved stereo, the usual case, splits in one vectorised call.
        let isInterleavedPair = right.map { $0.data == left.data + 1 && left.stride == 2 } ?? false
        if isInterleavedPair {
            var split = DSPSplitComplex(realp: input, imagp: input + capacity)
            left.data.withMemoryRebound(to: DSPComplex.self, capacity: frames) {
                vDSP_ctoz($0, 2, &split, 1, vDSP_Length(frames))
            }
        } else {
            for frame in 0..<frames {
                input[frame] = left.data[frame * left.stride]
                input[capacity + frame] = feed.data[frame * feed.stride]
            }
        }

        for channel in 0..<2 {
            outputList[channel] = AudioBuffer(mNumberChannels: 1,
                                              mDataByteSize: UInt32(frames * MemoryLayout<Float>.size),
                                              mData: UnsafeMutableRawPointer(output + channel * capacity))
        }
        var error: OSStatus = noErr
        guard render(AVAudioFrameCount(frames), outputList.unsafeMutablePointer, &error) == .success,
              let renderedLeft = outputList[0].mData?.assumingMemoryBound(to: Float.self) else { return }
        let renderedRight = outputList[1].mData?.assumingMemoryBound(to: Float.self) ?? renderedLeft

        if isInterleavedPair {
            var split = DSPSplitComplex(realp: renderedLeft, imagp: renderedRight)
            left.data.withMemoryRebound(to: DSPComplex.self, capacity: frames) {
                vDSP_ztoc(&split, 1, $0, 2, vDSP_Length(frames))
            }
            return
        }
        for frame in 0..<frames {
            left.data[frame * left.stride] = renderedLeft[frame]
        }
        if let right {
            for frame in 0..<frames {
                right.data[frame * right.stride] = renderedRight[frame]
            }
        }
    }
}
