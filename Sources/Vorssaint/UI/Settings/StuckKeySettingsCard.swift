// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// The Stuck Keys page of Settings, under Utilities beside the other
/// keyboard helpers.
struct StuckKeySettings: View {
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(StuckKeyStrings.localized(l10n.language).title).font(.title2.bold())
                StuckKeySettingsCard()
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(22)
        }
    }
}

/// The stuck-key watch's controls: its switch, how long each kind of hold
/// has to last before it counts, and the log of what it has caught.
struct StuckKeySettingsCard: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var watch = StuckKeyWatch.shared
    @AppStorage(DefaultsKey.stuckKeyWatchEnabled) private var enabled = true
    @AppStorage(DefaultsKey.stuckKeyAloneSeconds) private var aloneSeconds = 10
    @AppStorage(DefaultsKey.stuckKeyLongHoldSeconds) private var longHoldSeconds = 90
    @AppStorage(DefaultsKey.stuckKeyHeldSeconds) private var keySeconds = 30
    @AppStorage(DefaultsKey.stuckKeyAutoRelease) private var autoRelease = false

    private var strings: StuckKeyStrings { .localized(l10n.language) }
    private static let shownIncidents = 12

    var body: some View {
        SettingsCard {
            SettingsRow(symbol: "keyboard.badge.ellipsis", title: strings.enable, caption: strings.enableCaption) {
                Toggle(strings.enable, isOn: $enabled).labelsHidden().toggleStyle(.switch)
            }
            if enabled {
                Divider()
                picker(strings.aloneTitle, selection: $aloneSeconds, choices: StuckKeyDetector.Thresholds.aloneChoices)
                picker(strings.longTitle, selection: $longHoldSeconds,
                       choices: StuckKeyDetector.Thresholds.longHoldChoices)
                picker(strings.keyTitle, selection: $keySeconds, choices: StuckKeyDetector.Thresholds.keyChoices)
                SettingsRow(symbol: nil, title: strings.autoRelease, caption: strings.autoReleaseCaption) {
                    Toggle(strings.autoRelease, isOn: $autoRelease).labelsHidden().toggleStyle(.switch)
                }
                Divider()
                log
            }
        }
        .onChange(of: enabled) { watch.syncWithPreferences() }
        .onChange(of: aloneSeconds) { watch.syncWithPreferences() }
        .onChange(of: longHoldSeconds) { watch.syncWithPreferences() }
        .onChange(of: keySeconds) { watch.syncWithPreferences() }
    }

    private func picker(_ title: String, selection: Binding<Int>, choices: [Int]) -> some View {
        SettingsRow(symbol: nil, title: title) {
            Picker(title, selection: selection) {
                ForEach(choices, id: \.self) { seconds in
                    Text(seconds == 0 ? strings.off : MixerPlusStrings.duration(seconds, l10n.language)).tag(seconds)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }

    private var log: some View {
        let incidents = Array(watch.incidents.suffix(Self.shownIncidents).reversed())
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(strings.logTitle).font(.subheadline.weight(.semibold))
                Spacer()
                if !incidents.isEmpty {
                    Button(strings.clearLog) { watch.clearIncidents() }.controlSize(.small)
                }
            }
            if incidents.isEmpty {
                Text(strings.logEmpty).font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(Array(incidents.enumerated()), id: \.offset) { _, incident in
                    row(incident)
                }
            }
        }
    }

    private func row(_ incident: StuckKeyIncident) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(StuckKeyWatch.name(of: incident.subject, l10n.language))
                    .font(.callout.weight(.medium))
                if let released = incident.released {
                    Text(released ? strings.logReleased : strings.logStillDown)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill((released ? Color.green : Color.orange).opacity(0.18)))
                        .foregroundStyle(released ? Color.green : Color.orange)
                }
                Spacer()
                Text(incident.date.formatted(.dateTime.day().month(.abbreviated).hour().minute()
                    .locale(Locale(identifier: l10n.language.rawValue))))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text([StuckKeyWatch.explanation(of: incident.reason, duration: incident.duration, l10n.language),
                  incident.frontmostApp].compactMap { $0 }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
