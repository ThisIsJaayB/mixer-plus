// SPDX-License-Identifier: GPL-3.0-or-later

import Combine
import Foundation

/// Which mixer rows count as recently active, for the panel and the island.
///
/// Follows the mixer's published rows and wakes once per row that runs out of
/// time, so nothing polls: with every app silent and expired, this is idle.
final class MixerRecentApps: ObservableObject {
    static let shared = MixerRecentApps()

    /// Rows that are playing or stopped within the chosen time.
    @Published private(set) var recentIDs: Set<String> = []
    /// Lists every open app for now, without touching the saved preference.
    @Published var showAll = false

    private var activity = MixerRecentActivity()
    private var subscription: AnyCancellable?
    private var expiry: DispatchWorkItem?

    private var linger: Int {
        MixerRecentActivity.sanitizedLinger(
            UserDefaults.standard.integer(forKey: DefaultsKey.mixerInactiveAppLingerSeconds))
    }

    private init() {
        subscription = AppVolumeMixer.shared.$apps
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.observe($0) }
    }

    /// Whether a row belongs in the list under the user's "Hide inactive apps"
    /// choice. A row with a custom volume, output or pan always stays, so
    /// hiding idle rows can never conceal a setting the user may want to undo.
    func shows(_ app: MixerApp, hideInactiveApps: Bool) -> Bool {
        MixerRoutingSupport.shouldShowApp(isPlaying: app.isPlaying || recentIDs.contains(app.id) || app.pan != 0,
                                          volume: app.volume,
                                          selectedOutputDeviceUID: app.selectedOutputDeviceUID,
                                          hideInactiveApps: hideInactiveApps && !showAll)
    }

    /// The time to linger changed in the options: apply it to the rows on screen.
    func lingerChanged() { publish() }

    private func observe(_ apps: [MixerApp]) {
        var playing: Set<String> = []
        var present: Set<String> = []
        for app in apps {
            present.insert(app.id)
            if app.isPlaying { playing.insert(app.id) }
        }
        activity.observe(playing: playing, present: present, now: CFAbsoluteTimeGetCurrent())
        publish()
    }

    private func publish() {
        let now = CFAbsoluteTimeGetCurrent()
        let linger = linger
        let recent = activity.recent(now: now, linger: linger)
        if recent != recentIDs { recentIDs = recent }

        expiry?.cancel()
        expiry = nil
        guard let next = activity.nextExpiry(now: now, linger: linger) else { return }
        let work = DispatchWorkItem { [weak self] in self?.publish() }
        expiry = work
        // A hair past the deadline, so the row has expired when this runs.
        DispatchQueue.main.asyncAfter(deadline: .now() + (next - now) + 0.05, execute: work)
    }
}
