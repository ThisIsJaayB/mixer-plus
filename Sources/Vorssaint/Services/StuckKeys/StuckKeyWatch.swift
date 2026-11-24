// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Combine
import CoreGraphics

/// Watches for keys that stay down when nobody is holding them.
///
/// It reads whether keys are down, about once a second, from the state the
/// system already keeps. It installs no event tap, so it cannot delay input,
/// and it never sees what is typed. When a key looks stuck it says so, offers
/// to release it, and writes the incident to a log so a pattern can be found.
final class StuckKeyWatch: ObservableObject {
    static let shared = StuckKeyWatch()

    /// What is stuck and being shown right now.
    @Published private(set) var current: [StuckKeyFinding] = []
    /// What happened when Release was last pressed, for the panel to show.
    @Published private(set) var lastRelease: (finding: StuckKeyFinding, cleared: Bool)?

    private var detector = StuckKeyDetector()
    private var timer: Timer?
    private var ticks = 0
    private let panel = StuckKeyPanelController()

    /// Modifiers are read every tick; ordinary keys, which take a query per
    /// key, every fifth.
    private static let interval: TimeInterval = 1
    private static let keyScanEvery = 5
    /// Key codes of the two keys behind each modifier, left then right.
    private static let modifierKeys: [(StuckKeyModifier, CGEventFlags, [CGKeyCode])] = [
        (.command, .maskCommand, [55, 54]), (.shift, .maskShift, [56, 60]),
        (.option, .maskAlternate, [58, 61]), (.control, .maskControl, [59, 62]),
    ]
    /// Not ordinary keys: the modifiers above, Caps Lock and Fn.
    private static let skippedKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    private init() {}

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: DefaultsKey.stuckKeyWatchEnabled) }

    /// Starts or stops watching to match the preferences, and takes up any
    /// change to the thresholds without losing track of keys already down.
    func syncWithPreferences() {
        let defaults = UserDefaults.standard
        detector.thresholds = StuckKeyDetector.Thresholds(
            aloneSeconds: defaults.integer(forKey: DefaultsKey.stuckKeyAloneSeconds),
            longHoldSeconds: defaults.integer(forKey: DefaultsKey.stuckKeyLongHoldSeconds),
            keySeconds: defaults.integer(forKey: DefaultsKey.stuckKeyHeldSeconds))
        if Self.isEnabled {
            guard timer == nil else { return }
            let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in self?.tick() }
            timer.tolerance = 0.3
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else {
            timer?.invalidate()
            timer = nil
            current = []
            panel.hide()
        }
    }

    // MARK: - Reading

    private func tick() {
        ticks += 1
        var snapshot = Self.readModifiers()
        if ticks % Self.keyScanEvery == 0 { snapshot.heldKeys = Self.readHeldKeys() }
        let found = detector.observe(snapshot)
        // Whatever was released, by the user or by the key coming up, goes.
        let remaining = current.filter(detector.isStillStuck)
        if remaining.count != current.count { current = remaining }
        guard !found.isEmpty else {
            if current.isEmpty { panel.hide() }
            return
        }
        for finding in found { log(finding, released: nil) }
        current.append(contentsOf: found)
        lastRelease = nil
        panel.show()
        // Only what a program left down: a key held on a keyboard may be meant.
        if UserDefaults.standard.bool(forKey: DefaultsKey.stuckKeyAutoRelease) {
            for finding in found where !finding.reason.isHardware { release(finding) }
        }
    }

    private static func modifiers(in flags: CGEventFlags) -> Set<StuckKeyModifier> {
        Set(modifierKeys.filter { flags.contains($0.1) }.map(\.0))
    }

    private static func readModifiers() -> StuckKeySnapshot {
        let state = CGEventSourceStateID.hidSystemState
        let keys = Set(modifierKeys.filter { entry in
            entry.2.contains { CGEventSource.keyState(state, key: $0) }
        }.map(\.0))
        // Anything a person does apart from holding the key itself.
        let idle = [CGEventType.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel,
                    .mouseMoved, .leftMouseDragged]
            .map { CGEventSource.secondsSinceLastEventType(state, eventType: $0) }
            .min() ?? 0
        return StuckKeySnapshot(time: CFAbsoluteTimeGetCurrent(),
                                hardwareFlags: modifiers(in: CGEventSource.flagsState(state)),
                                sessionFlags: modifiers(in: CGEventSource.flagsState(.combinedSessionState)),
                                hardwareKeys: keys,
                                secondsSinceOtherInput: idle,
                                stickyKeysOn: stickyKeysOn)
    }

    private static func readHeldKeys() -> Set<UInt16> {
        var held: Set<UInt16> = []
        for code in UInt16(0)..<128 where !skippedKeyCodes.contains(code) {
            if CGEventSource.keyState(.hidSystemState, key: code) { held.insert(code) }
        }
        return held
    }

    /// Sticky Keys holds modifiers down in software on purpose.
    private static var stickyKeysOn: Bool {
        UserDefaults(suiteName: "com.apple.universalaccess")?.bool(forKey: "stickyKey") ?? false
    }

    // MARK: - Releasing

    /// Sends the "key up" that never came. That clears a key a program left
    /// down; it cannot lift a switch that is physically closed, and the
    /// result says which it was.
    func release(_ finding: StuckKeyFinding) {
        let source = CGEventSource(stateID: .hidSystemState)
        let codes: [CGKeyCode]
        var clearing: CGEventFlags = []
        switch finding.subject {
        case .modifier(let modifier):
            guard let entry = Self.modifierKeys.first(where: { $0.0 == modifier }) else { return }
            codes = entry.2
            clearing = entry.1
        case .key(let code):
            codes = [code]
        }
        for code in codes {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else { continue }
            if !clearing.isEmpty {
                // A modifier's release travels as a change of flags.
                event.type = .flagsChanged
                event.flags = CGEventSource.flagsState(.combinedSessionState).subtracting(clearing)
            }
            event.post(tap: .cghidEventTap)
            event.post(tap: .cgSessionEventTap)
        }
        // Read it back once the events have landed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [self] in
            let cleared = !isDown(finding.subject)
            lastRelease = (finding, cleared)
            noteRelease(of: finding, cleared: cleared)
            if cleared {
                current.removeAll { $0 == finding }
                if current.isEmpty { panel.hide(after: 2.5) }
            }
        }
    }

    private func isDown(_ subject: StuckKeySubject) -> Bool {
        switch subject {
        case .modifier(let modifier):
            guard let entry = Self.modifierKeys.first(where: { $0.0 == modifier }) else { return false }
            return CGEventSource.flagsState(.combinedSessionState).contains(entry.1)
                || entry.2.contains { CGEventSource.keyState(.hidSystemState, key: $0) }
        case .key(let code):
            return CGEventSource.keyState(.hidSystemState, key: code)
        }
    }

    /// Stops showing a finding without doing anything to the key. It is not
    /// reported again until the key has come up and stuck once more.
    func dismiss(_ finding: StuckKeyFinding) {
        current.removeAll { $0 == finding }
        if current.isEmpty { panel.hide() }
    }

    // MARK: - Log

    private(set) var incidents: [StuckKeyIncident] {
        get {
            UserDefaults.standard.data(forKey: DefaultsKey.stuckKeyIncidents)
                .flatMap { try? JSONDecoder().decode([StuckKeyIncident].self, from: $0) } ?? []
        }
        set {
            objectWillChange.send()
            if newValue.isEmpty {
                UserDefaults.standard.removeObject(forKey: DefaultsKey.stuckKeyIncidents)
            } else {
                UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: DefaultsKey.stuckKeyIncidents)
            }
        }
    }

    func clearIncidents() { incidents = [] }

    private func log(_ finding: StuckKeyFinding, released: Bool?) {
        incidents = StuckKeyIncident.appending(
            StuckKeyIncident(date: Date(), subject: finding.subject, reason: finding.reason,
                             duration: finding.duration,
                             frontmostApp: NSWorkspace.shared.frontmostApplication?.localizedName,
                             released: released),
            to: incidents)
    }

    /// Records on the incident already logged for this finding whether the
    /// Release button cleared it.
    private func noteRelease(of finding: StuckKeyFinding, cleared: Bool) {
        var log = incidents
        guard let index = log.lastIndex(where: { $0.subject == finding.subject && $0.reason == finding.reason })
        else { return }
        log[index].released = cleared
        incidents = log
    }

    // MARK: - Names

    /// A modifier goes by the name printed on the key, which is the same in
    /// every language, with its symbol.
    static func name(of subject: StuckKeySubject, _ language: AppLanguage) -> String {
        switch subject {
        case .modifier(.command): return "Command ⌘"
        case .modifier(.shift): return "Shift ⇧"
        case .modifier(.option): return "Option ⌥"
        case .modifier(.control): return "Control ⌃"
        case .key(let code):
            return String(format: StuckKeyStrings.localized(language).keyFormat,
                          KeyboardDebounceKeyCatalog.label(for: Int64(code)))
        }
    }

    static func explanation(of reason: StuckKeyReason, duration: Double, _ language: AppLanguage) -> String {
        let strings = StuckKeyStrings.localized(language)
        let time = MixerPlusStrings.duration(max(1, Int(duration.rounded())), language)
        switch reason {
        case .heldBySoftware: return strings.reasonSoftware
        case .flagWithoutKey: return strings.reasonFlag
        case .heldAlone: return String(format: strings.reasonAloneFormat, time)
        case .heldTooLong: return String(format: strings.reasonLongFormat, time)
        case .keyHeld: return String(format: strings.reasonKeyFormat, time)
        }
    }
}
