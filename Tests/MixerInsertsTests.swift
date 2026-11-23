// SPDX-License-Identifier: GPL-3.0-or-later

import AudioToolbox
import CoreAudio
import Foundation

/// Insert effects sit before the fader. With none, the engine renders with
/// its own gain and the insert point touches nothing; with a stage, the
/// engine renders at unity, the stage runs, and the fader follows it.
enum MixerInsertsTests {
    /// Doubles every sample and counts its calls.
    private final class Doubler: MixerInsertStage {
        var calls = 0
        func process(_ buffers: UnsafeMutableAudioBufferListPointer, frames: Int) {
            calls += 1
            for buffer in buffers {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                for index in 0..<(frames * Int(buffer.mNumberChannels)) { data[index] *= 2 }
            }
        }
    }

    private static func block(_ inserts: MixerInserts, gain: Float, frames: Int = 8) -> [Float] {
        var samples = [Float](repeating: 1, count: frames * 2)
        samples.withUnsafeMutableBufferPointer { pointer in
            let list = AudioBufferList.allocate(maximumBuffers: 1)
            defer { free(list.unsafeMutablePointer) }
            list[0] = AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(frames * 2 * MemoryLayout<Float>.size),
                                  mData: pointer.baseAddress)
            let stage = inserts.load()
            // What the engine's render does with the gain it is told to use.
            let rendered = MixerInserts.renderGain(gain, stage: stage)
            for index in 0..<(frames * 2) { pointer[index] *= rendered }
            inserts.process(stage, list, frames: frames, gain: gain)
        }
        return samples
    }

    static func run(_ suite: TestSuite) {
        let empty = MixerInserts()
        suite.expect(empty.load() == nil, "an engine starts with no effects")
        suite.expect(MixerInserts.renderGain(0.5, stage: nil) == 0.5,
                     "with no effects the engine applies the fader itself, as before")
        suite.expect(block(empty, gain: 0.5).allSatisfy { $0 == 0.5 },
                     "with no effects the insert point leaves the audio alone")

        let inserts = MixerInserts()
        let doubler = Doubler()
        inserts.setStage(doubler)
        let stage = inserts.load()
        suite.expect(stage != nil && MixerInserts.renderGain(0.5, stage: stage) == 1,
                     "with effects the engine renders at unity, so they hear the app at its own level")
        let first = block(inserts, gain: 0.25)
        suite.expect(doubler.calls == 1, "the stage runs once per block")
        suite.expect(first.allSatisfy { abs($0 - 0.5) < 1e-6 },
                     "the fader follows the effects: 1 doubled, then a quarter")
        suite.expect(block(inserts, gain: 0.25).allSatisfy { abs($0 - 0.5) < 1e-6 },
                     "a steady fader holds its gain from block to block")

        let moved = block(inserts, gain: 1)
        let lefts = stride(from: 0, to: 16, by: 2).map { moved[$0] }
        suite.expect(lefts.first! > 0.5 && lefts.first! < 1 && abs(lefts.last! - 2) < 1e-5
                        && zip(lefts, lefts.dropFirst()).allSatisfy { $0 < $1 },
                     "a fader move slides across the block after the effects")
        suite.expect(moved[0] == moved[1], "both channels slide from the same gain")

        inserts.setStage(nil)
        suite.expect(inserts.load() == nil, "taking the effects out leaves no stage")
        let leaving = block(inserts, gain: 0.5)
        suite.expect(doubler.calls == 3, "a stage taken out is not run again")
        // The engine is back to rendering at 0.5; this side slides from the
        // 1 it last applied back to unity, so the two meet without a step.
        suite.expect(abs(leaving.last! - 0.5) < 1e-6 && leaving[0] > 0.4 && leaving[0] <= 0.56,
                     "removing the last effect hands the fader back without a jump")
        suite.expect(block(inserts, gain: 0.5).allSatisfy { $0 == 0.5 },
                     "and the block after it is untouched again")

        let bad = MixerInserts()
        bad.setStage(Doubler())
        suite.expect(block(bad, gain: .nan).allSatisfy { $0 == 0 }, "a gain that is not a number plays silence")

        // Saved chains.
        let component = AudioComponentDescription(componentType: kAudioUnitType_Effect,
                                                  componentSubType: kAudioUnitSubType_LowPassFilter,
                                                  componentManufacturer: kAudioUnitManufacturer_Apple,
                                                  componentFlags: 0, componentFlagsMask: 0)
        let record = MixerEffectRecord(component: component, name: "Low Pass", manufacturer: "Apple",
                                       hasCustomView: false, isBypassed: true,
                                       state: ["cutoff": 900.0, "data": Data([1, 2, 3])])
        let data = MixerEffectRecord.fileData(for: ["com.example.player": [record, record], "com.example.none": []])
        let read = MixerEffectRecord.chains(fromFileData: data)
        suite.expect(read.keys.sorted() == ["com.example.player"] && read["com.example.player"]?.count == 2,
                     "a chain is saved under its app, and an empty one is not saved at all")
        let restored = read["com.example.player"]?.first
        suite.expect(restored?.component.componentSubType == kAudioUnitSubType_LowPassFilter
                        && restored?.component.componentType == kAudioUnitType_Effect
                        && restored?.component.componentManufacturer == kAudioUnitManufacturer_Apple,
                     "a saved effect names the same Audio Unit when read back")
        suite.expect(restored?.name == "Low Pass" && restored?.manufacturer == "Apple"
                        && restored?.isBypassed == true && restored?.hasCustomView == false,
                     "its name, bypass and interface come back as saved")
        suite.expect(restored?.state?["cutoff"] as? Double == 900 && restored?.state?["data"] as? Data == Data([1, 2, 3]),
                     "the plugin's own state survives the file")

        var unsavable = record
        unsavable.state = ["bad": NSObject()]
        suite.expect(unsavable.propertyList["state"] == nil && unsavable.propertyList["name"] as? String == "Low Pass",
                     "a state that cannot be written is left out without losing the effect")
        suite.expect(MixerEffectRecord(propertyList: ["name": "No codes"]) == nil
                        && MixerEffectRecord(propertyList: "text") == nil,
                     "an entry that names no Audio Unit is not an effect")
        suite.expect(MixerEffectRecord.chains(fromFileData: nil).isEmpty
                        && MixerEffectRecord.chains(fromFileData: Data([0, 1, 2])).isEmpty,
                     "a missing or damaged file is an empty set of chains")
        let mixed = try? PropertyListSerialization.data(
            fromPropertyList: ["app": [record.propertyList, ["junk": true]], "other": "nonsense"],
            format: .binary, options: 0)
        suite.expect(MixerEffectRecord.chains(fromFileData: mixed)["app"]?.count == 1
                        && MixerEffectRecord.chains(fromFileData: mixed)["other"] == nil,
                     "damaged entries are skipped and the rest of the file is kept")

        // Chains are kept in the preferences, so a settings backup carries them.
        let stored = MixerEffectRecord.propertyList(for: ["com.example.player": [record], "com.example.none": []])
        suite.expect(stored?.keys.sorted() == ["com.example.player"]
                        && PropertyListSerialization.propertyList(stored as Any, isValidFor: .xml),
                     "a set of chains is a property list a backup file can hold")
        suite.expect(MixerEffectRecord.propertyList(for: ["com.example.none": []]) == nil
                        && MixerEffectRecord.propertyList(for: [:]) == nil,
                     "with no chains left there is nothing to store")
        let reread = MixerEffectRecord.chains(fromPropertyList: stored)
        suite.expect(reread["com.example.player"]?.first?.name == "Low Pass"
                        && reread["com.example.player"]?.first?.state?["cutoff"] as? Double == 900,
                     "chains read back from the preferences as they were stored")
        suite.expect(MixerEffectRecord.chains(fromPropertyList: nil).isEmpty
                        && MixerEffectRecord.chains(fromPropertyList: "text").isEmpty
                        && MixerEffectRecord.chains(fromPropertyList: ["app": "junk"]).isEmpty,
                     "preferences that hold no chains read as none")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.appEffectChains),
                     "effect chains are part of a settings backup")
    }
}
