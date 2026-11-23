// SPDX-License-Identifier: GPL-3.0-or-later

import AVFoundation
import Combine
import Foundation

/// One effect in an app's chain. `unit` is nil for an effect that is saved
/// but could not be loaded; it keeps its place and its saved settings.
final class MixerEffectSlot: Identifiable, ObservableObject {
    let id = UUID()
    private(set) var record: MixerEffectRecord
    let unit: AVAudioUnit?
    @Published private(set) var isBypassed: Bool
    fileprivate var parameterObserver: AUParameterObserverToken?

    var name: String { record.name }
    var manufacturer: String { record.manufacturer }
    var isAvailable: Bool { unit != nil }

    init(record: MixerEffectRecord, unit: AVAudioUnit?) {
        self.record = record
        self.unit = unit
        isBypassed = record.isBypassed
        unit?.auAudioUnit.shouldBypassEffect = record.isBypassed
    }

    /// Bypass is the Audio Unit's own switch, so the audio path is not rebuilt.
    fileprivate func setBypassed(_ bypassed: Bool) {
        isBypassed = bypassed
        record.isBypassed = bypassed
        unit?.auAudioUnit.shouldBypassEffect = bypassed
    }

    /// The record as it should be saved now, with the plugin's current state.
    fileprivate func currentRecord() -> MixerEffectRecord {
        if let unit { record.state = unit.auAudioUnit.fullState }
        return record
    }
}

/// Installed Audio Unit effects, for the Add Effect menu. Scanning them takes
/// tens of milliseconds, so it happens off the main thread the first time an
/// effects list is opened, and never for someone who does not use effects.
/// Read once per launch; a plugin installed later appears after a restart.
final class MixerEffectCatalog: ObservableObject {
    struct Manufacturer: Identifiable {
        let name: String
        let components: [AVAudioUnitComponent]
        var id: String { name }
    }

    static let shared = MixerEffectCatalog()
    /// Nil until the first scan has finished.
    @Published private(set) var manufacturers: [Manufacturer]?
    private var isLoading = false

    func load() {
        guard manufacturers == nil, !isLoading else { return }
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let manager = AVAudioUnitComponentManager.shared()
            let components = [kAudioUnitType_Effect, kAudioUnitType_MusicEffect].flatMap { type in
                manager.components(matching: AudioComponentDescription(
                    componentType: type, componentSubType: 0, componentManufacturer: 0,
                    componentFlags: 0, componentFlagsMask: 0))
            }
            let found = Dictionary(grouping: components, by: \.manufacturerName)
                .map { Manufacturer(name: $0.key, components: $0.value.sorted { $0.name < $1.name }) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            DispatchQueue.main.async {
                self.manufacturers = found
                self.isLoading = false
            }
        }
    }
}

/// The Audio Unit effects on each app, and their place in the audio path.
///
/// A chain belongs to an app's settings key, so it is remembered between
/// launches like the app's volume. Effects load out of process, so a plugin
/// that crashes takes its own helper down and not the mixer.
///
/// Main thread only. The audio thread sees a chain as one `MixerEffectsStage`
/// handed to the engine's `MixerInserts`.
final class MixerEffects: ObservableObject {
    static let shared = MixerEffects()

    /// The loaded chains, by settings key. A key that is absent has not been
    /// loaded yet; what is saved for it is still counted by `count(for:)`.
    @Published private(set) var chains: [String: [MixerEffectSlot]] = [:]

    private var saved: [String: [MixerEffectRecord]]?
    private var loading: Set<String> = []
    /// Chains whose plugin settings changed and are waiting to be written.
    private var pendingSaves: [String: DispatchWorkItem] = [:]

    private struct Host {
        weak var inserts: MixerInserts?
        let sampleRate: Double
    }
    private var hosts: [String: Host] = [:]
    private var stages: [String: MixerEffectsStage] = [:]
    private var rebuilds: [String: DispatchWorkItem] = [:]
    let windows = MixerEffectWindows()

    private init() {
        // A backup restored while the app runs replaces what is saved. Chains
        // already loaded keep playing; the rest read the new ones.
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil,
                                               queue: .main) { [weak self] _ in self?.saved = nil }
    }

    // MARK: - Keys and counts

    /// Where an app's chain is kept. A row without a bundle id or name has
    /// nothing stable to save under: its chain lasts while the app runs.
    static func key(for app: MixerApp) -> String { app.persistenceID ?? "row:\(app.id)" }
    private static func isSessionKey(_ key: String) -> Bool { key.hasPrefix("row:") }

    func count(for app: MixerApp) -> Int { count(forKey: Self.key(for: app)) }

    private func count(forKey key: String) -> Int {
        chains[key]?.count ?? (Self.isSessionKey(key) ? 0 : savedChains()[key]?.count ?? 0)
    }

    /// Whether an app has effects and so needs an engine, loaded or not.
    func hasEffects(_ app: MixerApp) -> Bool { count(for: app) > 0 }

    // MARK: - Storage

    /// Chains live in the preferences, so a settings backup carries them
    /// like an app's volume. Builds before that kept them in this file.
    private static var legacyFileURL: URL? {
        PrivateFileStore.containerURL?.appendingPathComponent("MixerEffects.plist")
    }

    private func savedChains() -> [String: [MixerEffectRecord]] {
        if let saved { return saved }
        let defaults = UserDefaults.standard
        var loaded = MixerEffectRecord.chains(fromPropertyList: defaults.dictionary(forKey: DefaultsKey.appEffectChains))
        // Move a file from an earlier build across once, then let it go.
        if let url = Self.legacyFileURL, let data = try? Data(contentsOf: url) {
            if loaded.isEmpty {
                loaded = MixerEffectRecord.chains(fromFileData: data)
                saved = loaded
                store(loaded)
            }
            try? FileManager.default.removeItem(at: url)
        }
        saved = loaded
        return loaded
    }

    private func store(_ chains: [String: [MixerEffectRecord]]) {
        if let plist = MixerEffectRecord.propertyList(for: chains) {
            UserDefaults.standard.set(plist, forKey: DefaultsKey.appEffectChains)
        } else {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.appEffectChains)
        }
    }

    private func save(_ key: String) {
        pendingSaves.removeValue(forKey: key)?.cancel()
        guard !Self.isSessionKey(key), let chain = chains[key] else { return }
        var all = savedChains()
        all[key] = chain.isEmpty ? nil : chain.map { $0.currentRecord() }
        store(all)
        saved = all
    }

    /// A plugin's knobs move many times a second; the file is written once
    /// they have been still for two seconds.
    private func scheduleSave(_ key: String) {
        pendingSaves.removeValue(forKey: key)?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save(key) }
        pendingSaves[key] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    /// Writes whatever is still waiting, as the app quits.
    func saveAll() {
        for key in Array(pendingSaves.keys) { save(key) }
    }

    // MARK: - Loading

    /// Loads an app's saved chain, once. The effects list calls this when it
    /// opens, and an engine when it starts playing an app that has effects.
    func load(_ app: MixerApp) { load(key: Self.key(for: app)) }

    private func load(key: String) {
        guard chains[key] == nil, !loading.contains(key) else { return }
        let records = Self.isSessionKey(key) ? [] : savedChains()[key] ?? []
        guard !records.isEmpty else {
            chains[key] = []
            return
        }
        loading.insert(key)
        var slots = [MixerEffectSlot?](repeating: nil, count: records.count)
        let group = DispatchGroup()
        for (index, record) in records.enumerated() {
            group.enter()
            Self.instantiate(record) { unit in
                if let state = record.state { unit?.auAudioUnit.fullState = state }
                slots[index] = MixerEffectSlot(record: record, unit: unit)
                group.leave()
            }
        }
        group.notify(queue: .main) { [self] in
            loading.remove(key)
            // Anything added while these loaded goes after them.
            let restored = slots.compactMap { $0 }
            restored.forEach { watch($0, key: key) }
            chains[key] = restored + (chains[key] ?? [])
            chainChanged(key, save: false)
        }
    }

    /// Out of process, so a crashing plugin cannot take the app down. The
    /// completion always arrives on the main thread.
    private static func instantiate(_ record: MixerEffectRecord, completion: @escaping (AVAudioUnit?) -> Void) {
        AVAudioUnit.instantiate(with: record.component, options: .loadOutOfProcess) { unit, _ in
            DispatchQueue.main.async { completion(unit) }
        }
    }

    private func watch(_ slot: MixerEffectSlot, key: String) {
        guard let tree = slot.unit?.auAudioUnit.parameterTree else { return }
        // The plugin calls this from its own threads, often in bursts.
        slot.parameterObserver = tree.token(byAddingParameterObserver: { [weak self] _, _ in
            DispatchQueue.main.async { self?.scheduleSave(key) }
        })
    }

    private func unwatch(_ slot: MixerEffectSlot) {
        guard let token = slot.parameterObserver else { return }
        slot.unit?.auAudioUnit.parameterTree?.removeParameterObserver(token)
        slot.parameterObserver = nil
    }

    // MARK: - Editing

    func add(_ component: AVAudioUnitComponent, to app: MixerApp) {
        let key = Self.key(for: app)
        load(key: key)
        let record = MixerEffectRecord(component: component.audioComponentDescription, name: component.name,
                                       manufacturer: component.manufacturerName,
                                       hasCustomView: component.hasCustomView, isBypassed: false, state: nil)
        Self.instantiate(record) { [self] unit in
            guard let unit else { return }
            let slot = MixerEffectSlot(record: record, unit: unit)
            watch(slot, key: key)
            chains[key, default: []].append(slot)
            chainChanged(key)
        }
    }

    func remove(_ slot: MixerEffectSlot, from app: MixerApp) {
        let key = Self.key(for: app)
        windows.close(slot.id)
        unwatch(slot)
        chains[key]?.removeAll { $0.id == slot.id }
        chainChanged(key)
    }

    /// Moves an effect one place earlier (−1) or later (+1).
    func move(_ slot: MixerEffectSlot, by offset: Int, in app: MixerApp) {
        let key = Self.key(for: app)
        guard var chain = chains[key], let index = chain.firstIndex(where: { $0.id == slot.id }),
              chain.indices.contains(index + offset) else { return }
        chain.swapAt(index, index + offset)
        chains[key] = chain
        chainChanged(key)
    }

    func setBypassed(_ bypassed: Bool, _ slot: MixerEffectSlot, in app: MixerApp) {
        let key = Self.key(for: app)
        slot.setBypassed(bypassed)
        save(key)
        updatePath(key)
    }

    func openWindow(for slot: MixerEffectSlot, app: MixerApp) {
        let key = Self.key(for: app)
        windows.open(slot, appName: app.name) { [weak self] in self?.save(key) }
    }

    /// The chain's effects or their order changed: the engine's stage has to
    /// be built again, and the mixer has to know whether the app still needs
    /// an engine at all.
    private func chainChanged(_ key: String, save shouldSave: Bool = true) {
        if shouldSave { save(key) }
        rebuild(key)
        AppVolumeMixer.shared.effectsChanged()
    }

    // MARK: - Audio path

    /// An engine started playing this app. Its effects move to it.
    func engineInstalled(for app: MixerApp, inserts: MixerInserts?, sampleRate: Double) {
        let key = Self.key(for: app)
        guard let inserts, sampleRate > 0 else {
            hosts[key] = nil
            return
        }
        guard hosts[key]?.inserts !== inserts else { return }
        // The engine this one replaces must not go on rendering a stage that
        // is about to be torn down.
        hosts[key]?.inserts?.setStage(nil)
        hosts[key] = Host(inserts: inserts, sampleRate: sampleRate)
        guard count(forKey: key) > 0 else { return }
        if chains[key] == nil {
            load(key: key)
        } else {
            rebuild(key)
        }
    }

    /// Puts the current chain into the app's engine. An effect can belong to
    /// one AVAudioEngine only, so a running stage is first taken out of the
    /// audio path, given time to finish its last block, and torn down; the
    /// app plays without effects for that moment.
    private func rebuild(_ key: String) {
        rebuilds.removeValue(forKey: key)?.cancel()
        guard let old = stages[key] else { return install(key) }
        hosts[key]?.inserts?.setStage(nil)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            old.teardown()
            stages[key] = nil
            rebuilds[key] = nil
            install(key)
        }
        rebuilds[key] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func install(_ key: String) {
        guard let host = hosts[key], host.inserts != nil else { return }
        let units = (chains[key] ?? []).compactMap(\.unit)
        guard !units.isEmpty, let stage = MixerEffectsStage(units: units, sampleRate: host.sampleRate) else {
            host.inserts?.setStage(nil)
            return
        }
        stages[key] = stage
        updatePath(key)
    }

    /// The stage is in the path unless every effect is bypassed, or it is
    /// being rebuilt.
    private func updatePath(_ key: String) {
        guard rebuilds[key] == nil, let stage = stages[key] else { return }
        let active = (chains[key] ?? []).contains { $0.isAvailable && !$0.isBypassed }
        hosts[key]?.inserts?.setStage(active ? stage : nil)
    }
}
