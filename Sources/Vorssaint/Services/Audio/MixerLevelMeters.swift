// SPDX-License-Identifier: GPL-3.0-or-later

import Accelerate
import AppKit
import AudioToolbox
import Combine
import CoreAudio
import CoreAudioTapCompat

/// Something on screen that shows a mixer level: a meter or a peak readout.
protocol MixerMeterDisplay: AnyObject {
    /// The row it shows: an app's id, or `MixerLevelMeters.mainOutputID`.
    var meterID: String { get }
    func show(left: MixerMeterLevel, right: MixerMeterLevel)
}

/// Tells the meters when a display can actually be seen. A row in a closed
/// panel, or one in a window behind others, then costs nothing.
final class MixerMeterVisibility {
    private weak var display: (NSView & MixerMeterDisplay)?
    private var observer: NSObjectProtocol?
    private var isLive = false

    init(_ display: NSView & MixerMeterDisplay) { self.display = display }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Call from the view's `viewDidMoveToWindow`.
    func windowChanged() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
        if let window = display?.window {
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] _ in self?.update() }
        }
        update()
    }

    private func update() {
        guard let display else { return }
        let live = display.window?.occlusionState.contains(.visible) == true
        guard live != isLive else { return }
        isLive = live
        if live {
            MixerLevelMeters.shared.attach(display)
        } else {
            MixerLevelMeters.shared.detach(display)
            display.show(left: MixerMeterLevel(), right: MixerMeterLevel())
        }
    }
}

/// The level meters of the mixer.
///
/// A meter exists only for an app that is playing and whose row is on screen:
/// each visible display registers here, and the last one to leave stops
/// everything. An app the mixer is already processing is measured where its
/// engine plays it, after effects, fader and pan. Any other is heard through
/// a listen-only tap, so metering
/// never changes what it plays. A few times a second the loudest sample of
/// each tap goes straight to its view's layer, without SwiftUI.
final class MixerLevelMeters {
    static let shared = MixerLevelMeters()

    /// How often the meters move while any is live.
    private static let interval: TimeInterval = 1.0 / 15

    /// The id of the meter on everything the Mac plays, as opposed to one app.
    static let mainOutputID = "bus:main"

    private var views = NSHashTable<AnyObject>.weakObjects()
    private var displays: [any MixerMeterDisplay] { views.allObjects.compactMap { $0 as? any MixerMeterDisplay } }
    private var readers: [String: AnyObject] = [:]
    /// The engines being measured directly, in place of a reader.
    private var probes: [String: MixerOutputProbe] = [:]
    private var levels: [String: (left: MixerMeterLevel, right: MixerMeterLevel)] = [:]
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

    func attach(_ view: any MixerMeterDisplay) {
        views.add(view)
        if subscriptions.isEmpty {
            let mixer = AppVolumeMixer.shared
            mixer.$apps.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.sync() }
                .store(in: &subscriptions)
            mixer.$currentOutputDeviceUID.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.sync() }
                .store(in: &subscriptions)
            mixer.$systemOutputMuted.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.sync() }
                .store(in: &subscriptions)
            // The output's meter sits after its fader, so it follows it.
            MixerOutputGain.shared.$gain.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.sync() }
                .store(in: &subscriptions)
        }
        sync()
    }

    func detach(_ view: any MixerMeterDisplay) {
        views.remove(view)
        sync()
    }

    /// The preference changed, or a row now shows another app.
    func sync() {
        let shown = Set(displays.map(\.meterID))
        guard Self.isEnabled, !shown.isEmpty, #available(macOS 14.4, *) else { return stopAll() }

        let mixer = AppVolumeMixer.shared
        let hostUID = mixer.currentOutputDeviceUID
        wanted = []
        for app in mixer.apps where shown.contains(app.id) {
            gains[app.id] = MixerRoutingSupport.gain(forVolume: app.volume)
            // A bypassed app is one whose audio must not be touched at all.
            guard app.isPlaying, !app.isBypassed, !app.audioObjects.isEmpty, let hostUID else { continue }
            wanted.insert(app.id)
            // An engine shows what is actually played. Its level already
            // carries the fader, so nothing is scaled afterwards.
            if let probe = mixer.outputProbe(for: app.id) {
                if probes[app.id] !== probe {
                    probes[app.id]?.isMetering = false
                    probe.isMetering = true
                    probes[app.id] = probe
                    (readers[app.id] as? MixerLevelReader)?.stop()
                    readers[app.id] = nil
                    levels[app.id] = levels[app.id] ?? (MixerMeterLevel(), MixerMeterLevel())
                }
                continue
            }
            if let stale = probes.removeValue(forKey: app.id) { stale.isMetering = false }
            if let reader = readers[app.id] as? MixerLevelReader,
               reader.objects == app.audioObjects, reader.hostUID == hostUID { continue }
            (readers[app.id] as? MixerLevelReader)?.stop()
            readers[app.id] = MixerLevelReader(objects: app.audioObjects, hostUID: hostUID)
            levels[app.id] = levels[app.id] ?? (MixerMeterLevel(), MixerMeterLevel())
        }
        // Everything the Mac plays, with the output's own volume applied, as
        // a desk's main meter sits after its fader. Silent while muted.
        let main = Self.mainOutputID
        if shown.contains(main), let hostUID {
            gains[main] = mixer.systemOutputMuted == true ? 0 : MixerOutputGain.shared.gain
            wanted.insert(main)
            if (readers[main] as? MixerLevelReader)?.hostUID != hostUID {
                (readers[main] as? MixerLevelReader)?.stop()
                readers[main] = MixerLevelReader(objects: [], hostUID: hostUID)
                levels[main] = levels[main] ?? (MixerMeterLevel(), MixerMeterLevel())
            }
        }
        // An app that stopped keeps its reader until its meter has fallen
        // back, so a pause between tracks does not rebuild the tap; one
        // whose row left the screen goes at once.
        for id in Set(readers.keys).union(probes.keys)
        where !wanted.contains(id) && (!shown.contains(id) || isAtRest(id)) {
            drop(id)
        }
        if readers.isEmpty && probes.isEmpty { stopTimer() } else { startTimer() }
    }

    private func isAtRest(_ id: String) -> Bool {
        guard let level = levels[id] else { return true }
        return level.left.isAtRest && level.right.isAtRest
    }

    private func drop(_ id: String) {
        if #available(macOS 14.4, *) { (readers[id] as? MixerLevelReader)?.stop() }
        readers[id] = nil
        probes.removeValue(forKey: id)?.isMetering = false
        levels[id] = nil
        gains[id] = nil
        show((MixerMeterLevel(), MixerMeterLevel()), for: id)
    }

    private func stopAll() {
        for id in Set(readers.keys).union(probes.keys) { drop(id) }
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
        let mixer = AppVolumeMixer.shared
        for id in Set(readers.keys).union(probes.keys) {
            guard var level = levels[id] else { continue }
            let before = level
            let peaks: (left: Float, right: Float)
            let gain: Float
            if let probe = probes[id] {
                peaks = probe.takePeaks()
                gain = 1
            } else if let reader = readers[id] as? MixerLevelReader {
                peaks = reader.takePeaks()
                gain = gains[id] ?? 1
            } else {
                continue
            }
            level.left.advance(peak: peaks.left * gain, elapsed: Float(Self.interval))
            level.right.advance(peak: peaks.right * gain, elapsed: Float(Self.interval))
            levels[id] = level
            if level.left != before.left || level.right != before.right { show(level, for: id) }
            if isAtRest(id), !wanted.contains(id) { finished = true }
            // An engine that came or went changes where this app is measured.
            if id != Self.mainOutputID, mixer.outputProbe(for: id) !== probes[id] { finished = true }
        }
        // The meter of an app that stopped has fallen back: its reader can go.
        if finished { sync() }
    }

    private func show(_ level: (left: MixerMeterLevel, right: MixerMeterLevel), for id: String) {
        for display in displays where display.meterID == id {
            display.show(left: level.left, right: level.right)
        }
    }
}

/// Hears one app through a listen-only tap and keeps the loudest sample of
/// each side. With no processes to hear, it listens to everything the Mac
/// plays instead.
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
    private let leftPeak = AtomicFloatBox(0)
    private let rightPeak = AtomicFloatBox(0)
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

    /// Each side's loudest sample since the last call, 0 (silence) to 1
    /// (full scale). A buffer landing at the same moment may be missed,
    /// which a meter refreshed many times a second cannot show.
    func takePeaks() -> (left: Float, right: Float) {
        let level = compensation.value
        let left = leftPeak.value, right = rightPeak.value
        if left != 0 { leftPeak.value = 0 }
        if right != 0 { rightPeak.value = 0 }
        return (left * level, right * level)
    }

    func stop() {
        Self.queue.async { [self] in
            stopped = true
            teardown()
        }
    }

    private func build() -> Bool {
        guard let uuid = createPrivateAudioTap(objects.isEmpty ? .stereoGlobalExcluding : .stereoMixdown,
                                               processes: objects as [NSNumber], deviceUID: nil,
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
        let leftPeak = self.leftPeak, rightPeak = self.rightPeak
        let channels = Int(format.mChannelsPerFrame)
        guard AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregateID, nil, { _, input, _, output, _ in
            // The device beneath the aggregate would otherwise play whatever
            // this memory last held.
            MixerRender.silence(UnsafeMutableAudioBufferListPointer(output))
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            guard let index = MixerRender.tapBufferIndex(in: buffers, tapChannels: channels),
                  let data = buffers[index].mData?.assumingMemoryBound(to: Float.self) else { return }
            // The buffer's own layout: the lone buffer the tap index falls
            // back to may not have the tap's two channels.
            let stride = max(1, Int(buffers[index].mNumberChannels))
            let frames = vDSP_Length(Int(buffers[index].mDataByteSize) / (MemoryLayout<Float>.size * stride))
            var left: Float = 0
            vDSP_maxmgv(data, vDSP_Stride(stride), &left, frames)
            var right = left
            if stride > 1 { vDSP_maxmgv(data + 1, vDSP_Stride(stride), &right, frames) }
            // Only this thread raises a peak, so a read then a write is enough.
            if left > leftPeak.value { leftPeak.value = left }
            if right > rightPeak.value { rightPeak.value = right }
        }) == noErr, let ioProc, AudioDeviceStart(aggregateID, ioProc) == noErr else { return false }

        // The mixdown of everything is not divided the way one app's is.
        if !objects.isEmpty {
            let compensation = self.compensation
            levelWatch = LevelCompensationWatch.started(objects: objects) { compensation.value = $0 }
        }
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
