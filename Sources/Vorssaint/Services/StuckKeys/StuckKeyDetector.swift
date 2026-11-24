// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A modifier key the detector follows. Caps Lock is a toggle, and Fn is
/// held for long stretches on purpose, so neither is here.
enum StuckKeyModifier: String, CaseIterable, Codable {
    case command, shift, option, control
}

/// What looks stuck: a modifier, or an ordinary key by its key code.
enum StuckKeySubject: Hashable, Codable {
    case modifier(StuckKeyModifier)
    case key(UInt16)
}

/// Why a key looks stuck.
enum StuckKeyReason: String, Codable {
    /// The system believes the modifier is down while no keyboard reports
    /// it: a program pressed it and never let go.
    case heldBySoftware
    /// The keyboard side says "this modifier is down" but neither of its
    /// keys is. Nothing is holding it.
    case flagWithoutKey
    /// Held on a keyboard with no other key, click, scroll or pointer
    /// movement for the whole time.
    case heldAlone
    /// A modifier held on a keyboard for a very long stretch, whatever
    /// else was going on.
    case heldTooLong
    /// An ordinary key held far longer than anyone holds one.
    case keyHeld

    /// Whether a keyboard is physically reporting the key down. Software
    /// can let go of a key it holds; it cannot lift a jammed switch.
    var isHardware: Bool {
        switch self {
        case .heldBySoftware, .flagWithoutKey: return false
        case .heldAlone, .heldTooLong, .keyHeld: return true
        }
    }
}

struct StuckKeyFinding: Hashable {
    let subject: StuckKeySubject
    let reason: StuckKeyReason
    /// How long the condition had held when it was reported, in seconds.
    let duration: Double
}

/// One reading of the keyboard's state. Only whether keys are down, never
/// which keys were typed.
struct StuckKeySnapshot {
    var time: Double
    /// Modifiers the keyboards report as down.
    var hardwareFlags: Set<StuckKeyModifier> = []
    /// Modifiers the system believes are down, hardware and software together.
    var sessionFlags: Set<StuckKeyModifier> = []
    /// Modifiers with at least one of their two keys down on a keyboard.
    var hardwareKeys: Set<StuckKeyModifier> = []
    /// Ordinary keys down on a keyboard, when they were scanned this time.
    /// Nil leaves the last scan standing.
    var heldKeys: Set<UInt16>? = nil
    /// Seconds since the last key press, click, scroll or pointer movement.
    var secondsSinceOtherInput: Double = 0
    /// Sticky Keys latches modifiers in software on purpose.
    var stickyKeysOn = false
}

/// Decides, from a stream of snapshots, when a key looks stuck.
///
/// Pure rules: the caller supplies every reading and the clock. Each stuck
/// key is reported once for as long as it stays down; when it comes up it is
/// forgotten, and holding it again later can be reported again.
struct StuckKeyDetector {
    struct Thresholds: Equatable {
        /// A program holding a modifier no keyboard is pressing.
        var software: Double = 2
        /// A modifier held with no other input at all.
        var alone: Double = 10
        /// A modifier held, whatever else is happening.
        var tooLong: Double = 90
        /// An ordinary key held.
        var key: Double = 30

        /// What the settings offer, in seconds. Zero turns a rule off.
        static let aloneChoices = [5, 10, 20, 30]
        static let longHoldChoices = [0, 60, 90, 180, 300]
        static let keyChoices = [0, 15, 30, 60, 120]

        /// Thresholds from stored preferences. A value that is not offered
        /// falls back to the default, and zero means the rule never fires.
        init(aloneSeconds: Int, longHoldSeconds: Int, keySeconds: Int) {
            func pick(_ value: Int, from choices: [Int], default fallback: Double) -> Double {
                guard choices.contains(value) else { return fallback }
                return value == 0 ? .infinity : Double(value)
            }
            alone = pick(aloneSeconds, from: Self.aloneChoices, default: 10)
            tooLong = pick(longHoldSeconds, from: Self.longHoldChoices, default: 90)
            key = pick(keySeconds, from: Self.keyChoices, default: 30)
        }

        init(software: Double = 2, alone: Double = 10, tooLong: Double = 90, key: Double = 30) {
            self.software = software
            self.alone = alone
            self.tooLong = tooLong
            self.key = key
        }
    }

    var thresholds = Thresholds()

    private var softwareSince: [StuckKeyModifier: Double] = [:]
    private var flagOnlySince: [StuckKeyModifier: Double] = [:]
    private var hardwareSince: [StuckKeyModifier: Double] = [:]
    private var keySince: [UInt16: Double] = [:]
    private var reported: Set<Key> = []

    private struct Key: Hashable {
        let subject: StuckKeySubject
        let reason: StuckKeyReason
    }

    init(thresholds: Thresholds = Thresholds()) { self.thresholds = thresholds }

    /// Takes one reading and returns what has newly become stuck.
    mutating func observe(_ snapshot: StuckKeySnapshot) -> [StuckKeyFinding] {
        let now = snapshot.time
        var findings: [StuckKeyFinding] = []
        var reported = self.reported
        defer { self.reported = reported }

        func report(_ subject: StuckKeySubject, _ reason: StuckKeyReason, since: Double, after threshold: Double) {
            let key = Key(subject: subject, reason: reason)
            guard now - since >= threshold, !reported.contains(key) else { return }
            reported.insert(key)
            findings.append(StuckKeyFinding(subject: subject, reason: reason, duration: now - since))
        }

        for modifier in StuckKeyModifier.allCases {
            let subject = StuckKeySubject.modifier(modifier)
            let onHardware = snapshot.hardwareFlags.contains(modifier)
            let keyIsDown = snapshot.hardwareKeys.contains(modifier)

            // Down for the system, on no keyboard.
            Self.track(&softwareSince, modifier, now,
                       while: snapshot.sessionFlags.contains(modifier) && !onHardware && !keyIsDown
                           && !snapshot.stickyKeysOn,
                       clearing: Key(subject: subject, reason: .heldBySoftware), from: &reported)
            if let since = softwareSince[modifier] {
                report(subject, .heldBySoftware, since: since, after: thresholds.software)
            }

            // Reported down by the keyboard side, with neither key down.
            Self.track(&flagOnlySince, modifier, now, while: onHardware && !keyIsDown && !snapshot.stickyKeysOn,
                       clearing: Key(subject: subject, reason: .flagWithoutKey), from: &reported)
            if let since = flagOnlySince[modifier] {
                report(subject, .flagWithoutKey, since: since, after: thresholds.software)
            }

            // Held on a keyboard.
            let wasHeld = hardwareSince[modifier] != nil
            Self.track(&hardwareSince, modifier, now, while: onHardware && keyIsDown,
                       clearing: Key(subject: subject, reason: .heldAlone), from: &reported)
            if wasHeld, hardwareSince[modifier] == nil { reported.remove(Key(subject: subject, reason: .heldTooLong)) }
            if let since = hardwareSince[modifier] {
                // "Alone" needs the quiet to last the threshold too: a key
                // held through a busy minute and then a pause is not alone
                // until the pause itself is that long.
                if snapshot.secondsSinceOtherInput >= thresholds.alone {
                    report(subject, .heldAlone, since: since, after: thresholds.alone)
                }
                report(subject, .heldTooLong, since: since, after: thresholds.tooLong)
            }
        }

        if let held = snapshot.heldKeys {
            for code in keySince.keys where !held.contains(code) {
                keySince[code] = nil
                reported.remove(Key(subject: .key(code), reason: .keyHeld))
            }
            for code in held where keySince[code] == nil { keySince[code] = now }
        }
        for (code, since) in keySince {
            report(.key(code), .keyHeld, since: since, after: thresholds.key)
        }
        return findings.sorted { $0.duration > $1.duration }
    }

    /// Starts the clock for a condition when it begins, and forgets it, with
    /// what was reported for it, when it ends.
    private static func track(_ since: inout [StuckKeyModifier: Double], _ modifier: StuckKeyModifier,
                              _ now: Double, while condition: Bool,
                              clearing key: Key, from reported: inout Set<Key>) {
        if condition {
            if since[modifier] == nil { since[modifier] = now }
        } else if since[modifier] != nil {
            since[modifier] = nil
            reported.remove(key)
        }
    }

    /// Whether a subject is still in the stuck condition it was reported for.
    func isStillStuck(_ finding: StuckKeyFinding) -> Bool {
        switch (finding.subject, finding.reason) {
        case (.modifier(let modifier), .heldBySoftware): return softwareSince[modifier] != nil
        case (.modifier(let modifier), .flagWithoutKey): return flagOnlySince[modifier] != nil
        case (.modifier(let modifier), _): return hardwareSince[modifier] != nil
        case (.key(let code), _): return keySince[code] != nil
        }
    }
}

/// One stuck key, as kept in the log: enough to look for a pattern later,
/// and nothing about what was being typed.
struct StuckKeyIncident: Codable, Equatable {
    var date: Date
    var subject: StuckKeySubject
    var reason: StuckKeyReason
    var duration: Double
    /// The app in front when it was noticed.
    var frontmostApp: String?
    /// Whether the Release button cleared it. Nil if it was never pressed.
    var released: Bool?

    static let limit = 100

    /// The log with one more incident, the oldest dropped past the limit.
    static func appending(_ incident: StuckKeyIncident, to log: [StuckKeyIncident]) -> [StuckKeyIncident] {
        Array((log + [incident]).suffix(limit))
    }
}
