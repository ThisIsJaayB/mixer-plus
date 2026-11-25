// SPDX-License-Identifier: GPL-3.0-or-later

import Combine
import CoreAudio
import Foundation

/// What the output's own volume control does to the level, 0 to 1: the
/// figure its fader prints in decibels, and what its meter is scaled by.
final class MixerOutputGain: ObservableObject {
    static let shared = MixerOutputGain()

    @Published private(set) var gain: Float = 1
    private var request = 0
    private var subscriptions: Set<AnyCancellable> = []

    private init() {
        guard AppVolumeMixer.isSupported else { return }
        let mixer = AppVolumeMixer.shared
        mixer.$systemOutputVolume.receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.refresh(volume: $0) }
            .store(in: &subscriptions)
        mixer.$currentOutputDeviceUID.receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh(volume: AppVolumeMixer.shared.systemOutputVolume) }
            .store(in: &subscriptions)
    }

    /// The fader's level the way a desk prints it.
    var readout: String {
        MixerMeterLevel.readout(gain > 0 ? 20 * log10(gain) : MixerMeterLevel.floorDB)
    }

    /// The slider's position gives an answer at once; the output's real
    /// level in decibels, read off the main thread, replaces it when it
    /// arrives. Reading it can wait on a device that is reconnecting.
    private func refresh(volume: Double?) {
        request += 1
        let request = request
        set(MixerMeterLevel.outputGain(decibels: nil, volume: volume))
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let decibels = Self.readOutputDecibels(volume: volume)
            DispatchQueue.main.async {
                guard let self, self.request == request, decibels != nil else { return }
                self.set(MixerMeterLevel.outputGain(decibels: decibels, volume: volume))
            }
        }
    }

    private func set(_ value: Float) {
        if gain != value { gain = value }
    }

    /// The default output's volume in decibels: what it reports, or what it
    /// says the slider's position comes to. Nil for an output with neither.
    private static func readOutputDecibels(volume: Double?) -> Float? {
        func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope,
                     _ element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
            AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        }
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var defaultOutput = address(kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal,
                                    kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultOutput, 0, nil,
                                         &size, &device) == noErr, device != 0 else { return nil }
        // The main control, or the loudest of the first two channels.
        var levels: [Float] = []
        for element in [kAudioObjectPropertyElementMain, 1, 2] as [AudioObjectPropertyElement] {
            var value = Float32(0)
            var valueSize = UInt32(MemoryLayout<Float32>.size)
            var decibels = address(kAudioDevicePropertyVolumeDecibels, kAudioDevicePropertyScopeOutput, element)
            if AudioObjectHasProperty(device, &decibels),
               AudioObjectGetPropertyData(device, &decibels, 0, nil, &valueSize, &value) == noErr {
                levels.append(value)
            } else if let volume {
                var convert = address(kAudioDevicePropertyVolumeScalarToDecibels, kAudioDevicePropertyScopeOutput,
                                      element)
                value = Float32(volume)
                if AudioObjectHasProperty(device, &convert),
                   AudioObjectGetPropertyData(device, &convert, 0, nil, &valueSize, &value) == noErr {
                    levels.append(value)
                }
            }
            if element == kAudioObjectPropertyElementMain, !levels.isEmpty { break }
        }
        return levels.max()
    }
}
