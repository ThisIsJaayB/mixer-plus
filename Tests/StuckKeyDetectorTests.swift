// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A key is called stuck only when it has stayed down past its threshold in
/// one of a few recognisable ways, once per time it sticks, and never for
/// the ordinary ways people hold keys.
enum StuckKeyDetectorTests {
    private static func held(_ modifier: StuckKeyModifier, at time: Double, idle: Double = 0,
                             keys: Set<UInt16>? = nil) -> StuckKeySnapshot {
        StuckKeySnapshot(time: time, hardwareFlags: [modifier], sessionFlags: [modifier], hardwareKeys: [modifier],
                         heldKeys: keys, secondsSinceOtherInput: idle)
    }

    static func run(_ suite: TestSuite) {
        let command = StuckKeySubject.modifier(.command)

        // Nothing held.
        var quiet = StuckKeyDetector()
        suite.expect((0..<200).allSatisfy { quiet.observe(StuckKeySnapshot(time: Double($0), heldKeys: [])).isEmpty },
                     "an untouched keyboard is never reported")

        // Held by software: the system says down, no keyboard does.
        var software = StuckKeyDetector()
        func softwareHeld(_ time: Double, sticky: Bool = false) -> StuckKeySnapshot {
            StuckKeySnapshot(time: time, sessionFlags: [.command], stickyKeysOn: sticky)
        }
        suite.expect(software.observe(softwareHeld(0)).isEmpty && software.observe(softwareHeld(1)).isEmpty,
                     "a modifier a program holds for a moment is not stuck")
        let caught = software.observe(softwareHeld(2))
        suite.expect(caught.count == 1 && caught.first?.subject == command && caught.first?.reason == .heldBySoftware,
                     "a modifier down for the system but on no keyboard is held by software")
        suite.expect(caught.first?.reason.isHardware == false, "and software can be asked to let go of it")
        suite.expect(software.observe(softwareHeld(3)).isEmpty && software.observe(softwareHeld(60)).isEmpty,
                     "one stuck key is reported once, however long it stays")
        suite.expect(software.isStillStuck(caught[0]), "it counts as stuck while it stays down")
        _ = software.observe(StuckKeySnapshot(time: 61))
        suite.expect(!software.isStillStuck(caught[0]), "and no longer once it is released")
        _ = software.observe(softwareHeld(62))
        suite.expect(software.observe(softwareHeld(64)).first?.reason == .heldBySoftware,
                     "sticking again after a release is reported again")

        var sticky = StuckKeyDetector()
        suite.expect((0..<30).allSatisfy { sticky.observe(softwareHeld(Double($0), sticky: true)).isEmpty },
                     "Sticky Keys latching a modifier on purpose is not a stuck key")

        // A flag with no key behind it.
        var phantom = StuckKeyDetector()
        _ = phantom.observe(StuckKeySnapshot(time: 0, hardwareFlags: [.shift], sessionFlags: [.shift]))
        suite.expect(phantom.observe(StuckKeySnapshot(time: 2, hardwareFlags: [.shift], sessionFlags: [.shift]))
                        .first?.reason == .flagWithoutKey,
                     "a modifier reported down with neither of its keys down has nothing holding it")

        // Held alone.
        var alone = StuckKeyDetector()
        suite.expect((0..<10).allSatisfy { alone.observe(held(.command, at: Double($0), idle: Double($0))).isEmpty },
                     "a modifier held for a few seconds is ordinary")
        let lonely = alone.observe(held(.command, at: 10, idle: 10))
        suite.expect(lonely.first?.reason == .heldAlone && lonely.first?.subject == command
                        && lonely.first?.reason.isHardware == true,
                     "a modifier held ten seconds with no other input at all looks stuck, on the keyboard")

        var busy = StuckKeyDetector()
        suite.expect((0..<60).allSatisfy { busy.observe(held(.command, at: Double($0), idle: 0.3)).isEmpty },
                     "a modifier held while typing, clicking or moving the pointer is in use")
        suite.expect(busy.observe(held(.command, at: 60, idle: 5)).isEmpty
                        && busy.observe(held(.command, at: 65, idle: 10)).first?.reason == .heldAlone,
                     "it counts as alone only once the quiet itself has lasted the threshold")

        var marathon = StuckKeyDetector()
        suite.expect((0..<90).allSatisfy { marathon.observe(held(.option, at: Double($0), idle: 0.2)).isEmpty }
                        && marathon.observe(held(.option, at: 90, idle: 0.2)).first?.reason == .heldTooLong,
                     "a modifier held a minute and a half is reported even through activity")
        _ = marathon.observe(StuckKeySnapshot(time: 91))
        suite.expect((92..<120).allSatisfy { marathon.observe(held(.option, at: Double($0), idle: 0.2)).isEmpty },
                     "letting go starts the count again")

        // Two modifiers at once are told apart.
        var pair = StuckKeyDetector()
        var both: [StuckKeyFinding] = []
        for second in 0...10 {
            both += pair.observe(StuckKeySnapshot(time: Double(second), hardwareFlags: [.command, .shift],
                                                  sessionFlags: [.command, .shift], hardwareKeys: [.command, .shift],
                                                  secondsSinceOtherInput: Double(second)))
        }
        suite.expect(Set(both.map(\.subject)) == [command, .modifier(.shift)] && both.count == 2,
                     "each stuck modifier is reported by name")

        // An ordinary key.
        var key = StuckKeyDetector()
        suite.expect(key.observe(StuckKeySnapshot(time: 0, heldKeys: [13])).isEmpty
                        && key.observe(StuckKeySnapshot(time: 25, heldKeys: [13])).isEmpty,
                     "an ordinary key held for a while is ordinary")
        // A reading that did not scan the keys leaves the last scan standing.
        suite.expect(key.observe(StuckKeySnapshot(time: 28)).isEmpty, "a reading without a key scan changes nothing")
        let jammed = key.observe(StuckKeySnapshot(time: 30, heldKeys: [13]))
        suite.expect(jammed.first?.subject == .key(13) && jammed.first?.reason == .keyHeld,
                     "an ordinary key down for thirty seconds looks stuck")
        suite.expect(key.observe(StuckKeySnapshot(time: 35, heldKeys: [13])).isEmpty, "and is reported once")
        _ = key.observe(StuckKeySnapshot(time: 36, heldKeys: []))
        suite.expect(!key.isStillStuck(jammed[0]), "until it comes up")

        // Thresholds are the user's to set.
        var eager = StuckKeyDetector(thresholds: .init(software: 1, alone: 3, tooLong: 20, key: 5))
        _ = eager.observe(held(.control, at: 0, idle: 0))
        suite.expect(eager.observe(held(.control, at: 3, idle: 3)).first?.reason == .heldAlone,
                     "a shorter threshold reports sooner")

        // Thresholds from stored preferences.
        let stored = StuckKeyDetector.Thresholds(aloneSeconds: 20, longHoldSeconds: 0, keySeconds: 60)
        suite.expect(stored.alone == 20 && stored.tooLong == .infinity && stored.key == 60 && stored.software == 2,
                     "a stored choice is used, and zero turns its rule off")
        let damaged = StuckKeyDetector.Thresholds(aloneSeconds: -4, longHoldSeconds: 7, keySeconds: 999_999)
        suite.expect(damaged == StuckKeyDetector.Thresholds(),
                     "a stored value that is not offered falls back to the default")
        var never = StuckKeyDetector(thresholds: stored)
        suite.expect((0..<400).allSatisfy { never.observe(held(.option, at: Double($0), idle: 0.2)).isEmpty },
                     "a rule that is turned off never reports")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.stuckKeyAloneSeconds] as? Int == 10
                        && Defaults.registeredDefaults[DefaultsKey.stuckKeyHeldSeconds] as? Int == 30
                        && Defaults.registeredDefaults[DefaultsKey.stuckKeyLongHoldSeconds] as? Int == 90
                        && Defaults.registeredDefaults[DefaultsKey.stuckKeyWatchEnabled] as? Bool == true
                        && Defaults.registeredDefaults[DefaultsKey.stuckKeyAutoRelease] as? Bool == false,
                     "the watch is on with its usual thresholds until changed, and never releases unasked")
        suite.expect(!SettingsBackupSupport.exportKeys().contains(DefaultsKey.stuckKeyIncidents)
                        && SettingsBackupSupport.exportKeys().contains(DefaultsKey.stuckKeyAloneSeconds),
                     "the thresholds are backed up; the log of one Mac's incidents is not")

        // The log.
        let incident = StuckKeyIncident(date: Date(timeIntervalSince1970: 1_800_000_000), subject: command,
                                        reason: .heldBySoftware, duration: 2.5, frontmostApp: "Finder", released: true)
        let data = try? JSONEncoder().encode([incident])
        let decoded = data.flatMap { try? JSONDecoder().decode([StuckKeyIncident].self, from: $0) }
        suite.expect(decoded == [incident], "an incident survives being saved and read back")
        var log: [StuckKeyIncident] = []
        for index in 0..<(StuckKeyIncident.limit + 20) {
            var next = incident
            next.duration = Double(index)
            log = StuckKeyIncident.appending(next, to: log)
        }
        suite.expect(log.count == StuckKeyIncident.limit && log.first?.duration == 20
                        && log.last?.duration == Double(StuckKeyIncident.limit + 19),
                     "the log keeps the most recent incidents and drops the oldest")
    }
}
