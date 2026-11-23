// SPDX-License-Identifier: GPL-3.0-or-later

import Accelerate
import AppKit
import AudioToolbox
import Combine
import CoreAudio
import CoreAudioTapCompat

/// The level meters behind the mixer's faders.
///
/// A meter exists only for an app that is playing and whose row is on screen:
/// each visible `MixerMeterView` registers here, and the last one to leave
/// stops everything. An app is heard through a listen-only tap, so metering
/// never changes what it plays. A few times a second the loudest sample of
/// each tap goes straight to its view's layer, without SwiftUI.
final class MixerLevelMeters {
    static let shared = MixerLevelMeters()

    /// How often the meters move while any is live.
    private static let interval: TimeInterval = 1.0 / 15

    private var views = NSHashTable<MixerMeterView>.weakObjects()
    private var readers: [String: AnyObject] = [:]
    private var levels: [String: MixerMeterLevel] = [:]
    /// The fader each metered app sits at, so the meter follows the slider.
    private var gains: [String: Float] = [:]
    /// The apps that should have a reader right now.
    private var wanted: Set<String> = []
    private var subscriptions: Set<AnyCancellable> = []
    private var timer: Timer?

    private init() {}

    static var isEnabled: Bool {
        AppVolumeMixer.isSupported && UserDefaults.standard.bool(forKey: DefaultsKey.mixerShowLevelMeters)
    }

    // MARK: - Views

    func attach(_ view: MixerMeterView) {
        views.add(view)
        if subscriptions.isEmpty {
            let mixer = AppVolumeMixer.shared
            mixer.$apps.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.sync() }
                .store(in: &subscriptions)
            mixer.$currentOutputDeviceUID.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.sync() }
                .store(in: &subscriptions)
        }
        sync()
    }

    func detach(_ view: MixerMeterView) {
        views.remove(view)
        sync()
    }

    /// The preference changed, or a row now shows another app.
    func sync() {
        let shown = Set(views.allObjects.map(\.appID))
        guard Self.isEnabled, !shown.isEmpty, #available(macOS 14.4, *) else { return stopAll() }

        let mixer = AppVolumeMixer.shared
        let hostUID = mixer.currentOutputDeviceUID
        wanted = []
        for app in mixer.apps where shown.contains(app.id) {
            gains[app.id] = MixerRoutingSupport.gain(forVolume: app.volume)
            // A bypassed app is one whose audio must not be touched at all.
            guard app.isPlaying, !app.isBypassed, !app.audioObjects.isEmpty, let hostUID else { continue }
            wanted.insert(app.id)
            if let reader = readers[app.id] as? MixerLevelReader,
               reader.objects == app.audioObjects, reader.hostUID == hostUID { continue }
            (readers[app.id] as? MixerLevelReader)?.stop()
            readers[app.id] = MixerLevelReader(objects: app.audioObjects, hostUID: hostUID)
            levels[app.id] = levels[app.id] ?? MixerMeterLevel()
        }
        // An app that stopped keeps its reader until its meter has fallen
        // back, so a pause between tracks does not rebuild the tap; one
        // whose row left the screen goes at once.
        for id in Array(readers.keys)
        where !wanted.contains(id) && (!shown.contains(id) || levels[id]?.isAtRest != false) {
            drop(id)
        }
        if readers.isEmpty { stopTimer() } else { startTimer() }
    }

    private func drop(_ id: String) {
        if #available(macOS 14.4, *) { (readers[id] as? MixerLevelReader)?.stop() }
        readers[id] = nil
        levels[id] = nil
        gains[id] = nil
        show(MixerMeterLevel(), for: id)
    }

    private func stopAll() {
        for id in Array(readers.keys) { drop(id) }
        wanted = []
        stopTimer()
        if views.count == 0 { subscriptions.removeAll() }
    }

    // MARK: - Refresh

    private func startTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = Self.interval / 4
        // Common modes, so the meters keep moving while a fader is dragged.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard #available(macOS 14.4, *) else { return }
        var finished = false
        for (id, reader) in readers {
            guard let reader = reader as? MixerLevelReader, var level = levels[id] else { continue }
            let before = level
            level.advance(peak: reader.takePeak() * (gains[id] ?? 1), elapsed: Float(Self.interval))
            levels[id] = level
            if level.level != before.level || level.isHot != before.isHot { show(level, for: id) }
            if level.isAtRest, !wanted.contains(id) { finished = true }
        }
        // The meter of an app that stopped has fallen back: its reader can go.
        if finished { sync() }
    }

    private func show(_ level: MixerMeterLevel, for id: String) {
        for view in views.allObjects where view.appID == id {
            view.show(level: level.level, isHot: level.isHot)
        }
    }
}

/// Hears one app through a listen-only tap and keeps its loudest sample.
///
/// The same shape as the island's level reader: a private tap on the app's
/// processes, read through a private aggregate device on the current output.
/// The tap is unmuted, so the app plays exactly as it did, and the audio
/// thread only measures: nothing is stored or copied.
///
/// Every Core Audio call runs on one background queue. Creating a tap or
/// starting a device can wait on a Bluetooth or USB device, and the panel
/// must never wait with it.
@available(macOS 14.4, *)
private final class MixerLevelReader {
    let objects: [AudioObjectID]
    let hostUID: String

    private static let queue = DispatchQueue(label: "com.vorssaint.utils.mixer.meters", qos: .utility)
    private let peak = AtomicFloatBox(0)
    /// What the stereo mixdown took from the app's level on a wide output.
    private let compensation = AtomicFloatBox(1)
    // Touched only on `queue`.
    private var tapID = AudioObjectID(0)
    private var aggregateID = AudioObjectID(0)
    private var ioProc: AudioDeviceIOProcID?
    private var levelWatch: LevelCompensationWatch?
    private var stopped = false

    init(objects: [AudioObjectID], hostUID: String) {
        self.objects = objects
        self.hostUID = hostUID
        Self.queue.async { [self] in
            if !stopped, !build() { teardown() }
        }
    }

    /// The loudest sample since the last call, 0 (silence) to 1 (full scale).
    /// A buffer landing at the same moment may be missed, which a meter
    /// refreshed many times a second cannot show.
    func takePeak() -> Float {
        let value = peak.value
        if value != 0 { peak.value = 0 }
        return value * compensation.value
    }

    func stop() {
        Self.queue.async { [self] in
            stopped = true
            teardown()
        }
    }

    private func build() -> Bool {
        guard let uuid = createPrivateAudioTap(.stereoMixdown, processes: objects as [NSNumber], deviceUID: nil,
                                               name: "Vorssaint Mixer Levels", muteBehavior: .unmuted, id: &tapID)
        else { return false }
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        // Only 32-bit float samples are measured; anything else gets no meter.
        guard AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format) == noErr,
              format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mBitsPerChannel == 32, format.mChannelsPerFrame > 0 else { return false }

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Vorssaint Mixer Levels",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceMainSubDeviceKey: hostUID,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: hostUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
            kAudioAggregateDeviceTapAutoStartKey: true,
        ]
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID) == noErr,
              aggregateID != 0 else {
            aggregateID = 0
            return false
        }
        // The audio thread touches only these captured values, never this object.
        let peak = self.peak
        let channels = Int(format.mChannelsPerFrame)
        guard AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregateID, nil, { _, input, _, output, _ in
            // The device beneath the aggregate would otherwise play whatever
            // this memory last held.
            MixerRender.silence(UnsafeMutableAudioBufferListPointer(output))
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            guard let index = MixerRender.tapBufferIndex(in: buffers, tapChannels: channels),
                  let data = buffers[index].mData?.assumingMemoryBound(to: Float.self) else { return }
            var loudest: Float = 0
            vDSP_maxmgv(data, 1, &loudest,
                        vDSP_Length(Int(buffers[index].mDataByteSize) / MemoryLayout<Float>.size))
            // Only this thread raises the peak, so a read then a write is enough.
            if loudest > peak.value { peak.value = loudest }
        }) == noErr, let ioProc, AudioDeviceStart(aggregateID, ioProc) == noErr else { return false }

        let compensation = self.compensation
        levelWatch = LevelCompensationWatch.started(objects: objects) { compensation.value = $0 }
        return true
    }

    private func teardown() {
        levelWatch?.stop()
        levelWatch = nil
        if aggregateID != 0 {
            if let ioProc {
                AudioDeviceStop(aggregateID, ioProc)
                AudioDeviceDestroyIOProcID(aggregateID, ioProc)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != 0 { AudioHardwareDestroyProcessTap(tapID) }
        aggregateID = 0
        ioProc = nil
        tapID = 0
    }
}
