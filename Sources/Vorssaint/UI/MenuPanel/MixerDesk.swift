// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import AVFoundation
import SwiftUI

/// The width the mixer desk would like the panel to be, reported upwards so
/// the panel can grow for it and shrink back for every other tab.
struct MixerDeskWidthKey: PreferenceKey {
    static let defaultValue = MixerDeskMetrics.minimumWidth
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct MixerDeskLayoutKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether the mixer may lay itself out as a desk of channel strips. Only
    /// the menu bar panel can widen for one; Settings and the island keep
    /// the list.
    var mixerDeskLayout: Bool {
        get { self[MixerDeskLayoutKey.self] }
        set { self[MixerDeskLayoutKey.self] = newValue }
    }
}

/// The mixer as a desk: the microphone on the left, one channel strip per app
/// in the middle, then system sounds and the main output on the right, where
/// a mixing desk keeps its buses. Each app strip runs from its output and
/// effects at the top, through pan and level, to its name at the bottom.
///
/// The panel keeps its usual width while the strips fit and grows a strip at
/// a time for more apps; past the widest it may be, the app strips scroll
/// sideways between the pinned ones.
struct MixerDesk: View {
    /// The app rows to show, already ordered and filtered by the caller.
    let apps: [MixerApp]
    @ObservedObject private var mixer = AppVolumeMixer.shared
    @ObservedObject private var input = AudioInputDeviceManager.shared
    @ObservedObject private var audioPriority = AudioPriorityService.shared
    @ObservedObject private var micMute = MicMuteService.shared
    @ObservedObject private var effects = MixerEffects.shared
    @ObservedObject private var catalog = MixerEffectCatalog.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.mixerAppArrangement) private var arrangementValue = ""
    @AppStorage(DefaultsKey.mixerShowLevelMeters) private var showLevelMeters = true
    @State private var draggingAppID: String?
    @State private var dropTarget: MixerAppDropTarget?
    @Environment(\.colorScheme) private var colorScheme

    private var strings: MixerPlusStrings { .localized(l10n.language) }
    private var arrangementStrings: MixerFeatureStrings { FeatureStrings.mixer(l10n.language) }
    private var arrangement: MixerAppArrangement { MixerAppArrangement(rawValue: arrangementValue) }
    private var showsMicrophone: Bool { !input.inputDevices.isEmpty }
    private static let unit = MixerDeskMetrics.stripWidth + MixerDeskMetrics.stripSpacing
    private static let muteTint = Color(red: 0.38, green: 0.72, blue: 1)

    var body: some View {
        let buses = showsMicrophone ? 3 : 2
        let width = MixerDeskMetrics.width(forStrips: apps.count + buses)
        let room = width - 8 - CGFloat(buses) * Self.unit
        HStack(alignment: .top, spacing: MixerDeskMetrics.stripSpacing) {
            if showsMicrophone { microphoneStrip }
            if !apps.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: MixerDeskMetrics.stripSpacing) {
                        ForEach(apps) { appStrip($0) }
                    }
                }
                .frame(width: min(CGFloat(apps.count) * Self.unit - MixerDeskMetrics.stripSpacing, room))
            }
            systemSoundsStrip
            mainOutputStrip
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(colorScheme == .dark ? Color.black.opacity(0.28) : Color.primary.opacity(0.05)))
        .frame(maxWidth: .infinity)
        .preference(key: MixerDeskWidthKey.self, value: width)
        .onAppear { catalog.load() }
    }

    // MARK: - App strips

    private func appStrip(_ app: MixerApp) -> some View {
        let icon = ResponsibleProcess.icon(for: app.ownerPid, pointSize: 28)
        let ids = apps.compactMap(\.persistenceID)
        return MixerStrip(name: app.name, color: MixerStripColor.color(for: app.ownerPid, icon: icon)) {
            if !app.isBypassed { outputMenu(for: app) }
        } slots: {
            if !app.isBypassed { effectSlots(for: app) }
        } knob: {
            if !app.isBypassed {
                MixerPanKnob(value: Binding(get: { app.pan }, set: { mixer.setPan($0, for: app) }),
                             strings: strings, appName: app.name, size: 24)
            }
        } readout: {
            if !app.isBypassed {
                HStack(spacing: 2) {
                    MixerReadoutBox { Text(faderReadout(app.volume)) }
                    MixerReadoutBox { if showLevelMeters { MixerPeakReadout(meterID: app.id) } }
                }
            }
        } fader: {
            if app.isBypassed {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .help(l10n.s.mixerBypassedCaption)
            } else {
                HStack(alignment: .center, spacing: 2) {
                    MixerVerticalFader(value: Binding(get: { app.volume }, set: { mixer.setVolume($0, for: app) }),
                                       maximum: AppVolumeMixer.maxVolume, showsScale: true,
                                       isBoosting: (app.volume * 100).rounded() > 100,
                                       accessibilityLabel: app.name)
                    meter(app.id)
                }
            }
        } keys: {
            if !app.isBypassed {
                MixerDeskKey(letter: "M", isOn: app.volume <= 0.001, tint: Self.muteTint,
                             help: "\(strings.mute): \(app.name)") { mixer.toggleMute(app) }
                MixerDeskKey(letter: "S", isOn: mixer.soloedIDs.contains(app.id), tint: .yellow,
                             help: "\(strings.solo): \(app.name)") { mixer.toggleSolo(app) }
            }
        } badge: {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 28, height: 28)
                .overlay(alignment: .topTrailing) {
                    if arrangement.isPinned(app.persistenceID) {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(.secondary)
                            .offset(x: 5, y: -3)
                    }
                }
        }
        .opacity(app.isSilencedBySolo ? 0.55 : 1)
        .onAppear { effects.load(app) }
        .contextMenu { appActions(app) }
        .modifier(MixerAppReorderModifier(
            id: app.persistenceID, icon: icon, draggingID: $draggingAppID, target: $dropTarget,
            dragChanged: { _ in },
            canMove: { source, target in
                ids.contains(source) && ids.contains(target)
                    && arrangement.isPinned(source) == arrangement.isPinned(target)
            },
            move: { source, target, after in
                updateArrangement { $0.move(source, to: target, after: after, visibleIDs: ids) }
            },
            sideways: true))
    }

    @ViewBuilder
    private func appActions(_ app: MixerApp) -> some View {
        if let id = app.persistenceID {
            Button {
                updateArrangement { $0.togglePin(id) }
            } label: {
                let pinned = arrangement.isPinned(id)
                Label(pinned ? arrangementStrings.unpin : arrangementStrings.pinFirst,
                      systemImage: pinned ? "pin.slash" : "pin")
            }
            if app.supportsVolumeOverride {
                let sharing = MixerScreenSharingStrings.localized(l10n.language)
                Toggle(sharing.allowVolumeControl, isOn: Binding(
                    get: { !app.isBypassed }, set: { mixer.setCallAppVolumeControl($0, for: app) }))
            }
            Divider()
            Button(l10n.s.mixerHideFromList) { mixer.hideFromList(app) }
        }
    }

    private func updateArrangement(_ change: (inout MixerAppArrangement) -> Void) {
        var updated = arrangement
        change(&updated)
        arrangementValue = updated.rawValue
    }

    /// The fader's level in dB, from the curve the engine plays it with.
    private func faderReadout(_ volume: Double) -> String {
        let gain = MixerRoutingSupport.gain(forVolume: volume)
        return MixerMeterLevel.readout(gain > 0 ? 20 * log10(gain) : MixerMeterLevel.floorDB)
    }

    @ViewBuilder
    private func meter(_ id: String) -> some View {
        if showLevelMeters {
            MixerStereoMeter(meterID: id)
                .frame(width: 10, height: MixerDeskMetrics.faderHeight - 8)
                .allowsHitTesting(false)
        } else {
            Color.clear.frame(width: 10)
        }
    }

    // MARK: - An app's output and effects

    private func outputMenu(for app: MixerApp) -> some View {
        let selected = app.selectedOutputDeviceUID
        let title = selected.flatMap { uid in mixer.outputDevices.first { $0.uid == uid }?.name }
            ?? (selected == nil ? l10n.s.mixerOutputDefault : l10n.s.mixerOutputUnavailable)
        return MixerStripMenu(title: title, help: l10n.s.mixerOutputTooltip) {
            choice(l10n.s.mixerOutputDefault, isOn: selected == nil) { mixer.setOutputDeviceUID(nil, for: app) }
            ForEach(mixer.outputDevices) { device in
                choice(device.isDefault ? "\(device.name) (\(l10n.s.mixerOutputCurrent))" : device.name,
                       isOn: selected == device.uid) { mixer.setOutputDeviceUID(device.uid, for: app) }
            }
            if mixer.outputDevices.contains(where: { MixerRoutingSupport.isAirPlaySentinel($0.uid) }) {
                Divider()
                Button(l10n.s.mixerAirPlayChooseSpeaker) {
                    mixer.setOutputDeviceUID(MixerRoutingSupport.airPlaySpeakerChoiceID, for: app)
                }
            }
        }
    }

    /// A menu item that shows a tick while it is the current choice.
    @ViewBuilder
    private func choice(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if isOn { Label(title, systemImage: "checkmark") } else { Text(title) }
        }
    }

    private func effectSlots(for app: MixerApp) -> some View {
        let chain = effects.chains[MixerEffects.key(for: app)] ?? []
        return ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 2) {
                ForEach(Array(chain.enumerated()), id: \.element.id) { index, slot in
                    MixerDeskEffectSlot(slot: slot, app: app, strings: strings,
                                        canMoveUp: index > 0, canMoveDown: index < chain.count - 1)
                }
                Menu {
                    if let manufacturers = catalog.manufacturers {
                        ForEach(manufacturers) { manufacturer in
                            Menu(manufacturer.name) {
                                ForEach(manufacturer.components, id: \.self) { component in
                                    Button(component.name) { effects.add(component, to: app) }
                                }
                            }
                        }
                    } else {
                        Text(strings.findingEffects)
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: MixerDeskMetrics.stripWidth - 10, height: 15)
                        .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.22), style: StrokeStyle(lineWidth: 0.8, dash: [2.5, 2])))
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(strings.addEffect)
                .accessibilityLabel("\(strings.addEffect): \(app.name)")
            }
        }
    }

    // MARK: - Bus strips

    private var microphoneStrip: some View {
        let current = MixerRoutingSupport.selectedInputDeviceUID(
            preferredUID: input.preferredInputDeviceUID, currentUID: input.currentInputDeviceUID,
            priorityIsActive: audioPriority.inputPriorityEnabled)
        let title = current.flatMap { uid in input.inputDevices.first { $0.uid == uid }?.name }
            ?? l10n.s.mixerOutputDefault
        return MixerStrip(name: l10n.s.mixerInputTitle, color: .orange) {
            MixerStripMenu(title: title, help: l10n.s.mixerInputTooltip) {
                if !audioPriority.inputPriorityEnabled {
                    choice(l10n.s.mixerOutputDefault, isOn: current == nil) {
                        input.setPreferredInputDeviceUID(nil)
                    }
                }
                ForEach(input.inputDevices) { device in
                    choice(device.name, isOn: current == device.uid) {
                        if audioPriority.inputPriorityEnabled {
                            input.setCurrentInputDeviceUID(device.uid)
                        } else {
                            input.setPreferredInputDeviceUID(device.uid)
                        }
                    }
                }
            }
        } slots: {
            EmptyView()
        } knob: {
            EmptyView()
        } readout: {
            if let volume = input.inputVolume {
                MixerReadoutBox { Text("\(MixerRoutingSupport.displayPercent(forVolume: volume))%") }
            }
        } fader: {
            // A microphone that reports no level has nothing to fade.
            if let volume = input.inputVolume {
                MixerVerticalFader(value: Binding(get: { volume }, set: { input.setInputVolume($0) }),
                                   maximum: 1, showsScale: false, isBoosting: false,
                                   accessibilityLabel: l10n.s.mixerInputTitle)
            }
        } keys: {
            MixerDeskKey(letter: "M", isOn: micMute.isMuted, tint: Self.muteTint,
                         help: "\(strings.mute): \(l10n.s.mixerInputTitle)") { micMute.toggle() }
        } badge: {
            MixerBusBadge(systemImage: micMute.isMuted ? "mic.slash.fill" : "mic.fill")
        }
    }

    private var systemSoundsStrip: some View {
        let devices = mixer.outputDevices.filter(\.canBeDefaultSystemOutput)
        let current = mixer.currentSystemSoundOutputDeviceUID
        let title = current.flatMap { uid in devices.first { $0.uid == uid }?.name } ?? l10n.s.mixerOutputUnavailable
        return MixerStrip(name: l10n.s.mixerSoundEffectsOutputTitle, color: .gray) {
            MixerStripMenu(title: title, help: l10n.s.mixerSoundEffectsOutputTooltip) {
                ForEach(devices) { device in
                    choice(device.name, isOn: current == device.uid) {
                        _ = mixer.setSystemSoundOutputDeviceUID(device.uid)
                    }
                }
            }
        } slots: {
            EmptyView()
        } knob: {
            EmptyView()
        } readout: {
            EmptyView()
        } fader: {
            EmptyView()
        } keys: {
            EmptyView()
        } badge: {
            MixerBusBadge(systemImage: "bell.fill")
        }
    }

    private var mainOutputStrip: some View {
        let devices = mixer.outputDevices.filter(\.canBeDefaultOutput)
        let current = mixer.currentOutputDeviceUID
        let title = current.flatMap { uid in devices.first { $0.uid == uid }?.name } ?? l10n.s.mixerOutputUnavailable
        let muted = mixer.systemOutputMuted == true
        return MixerStrip(name: l10n.s.mixerSystemOutputTitle, color: .purple) {
            MixerStripMenu(title: title, help: l10n.s.mixerSystemOutputTooltip) {
                ForEach(devices) { device in
                    choice(device.name, isOn: current == device.uid) {
                        _ = mixer.setUniversalOutputDeviceUID(device.uid)
                    }
                }
            }
        } slots: {
            EmptyView()
        } knob: {
            EmptyView()
        } readout: {
            HStack(spacing: 2) {
                if let volume = mixer.systemOutputVolume {
                    MixerReadoutBox { Text("\(MixerRoutingSupport.displayPercent(forVolume: volume))") }
                }
                MixerReadoutBox { if showLevelMeters { MixerPeakReadout(meterID: MixerLevelMeters.mainOutputID) } }
            }
        } fader: {
            HStack(alignment: .center, spacing: 2) {
                if let volume = mixer.systemOutputVolume {
                    MixerVerticalFader(value: Binding(get: { volume },
                                                      set: { mixer.requestOutputAdjustment(volume: $0) }),
                                       maximum: 1, showsScale: false, isBoosting: false,
                                       accessibilityLabel: l10n.s.mixerSystemOutputTitle)
                }
                meter(MixerLevelMeters.mainOutputID)
            }
        } keys: {
            if mixer.systemOutputMuted != nil {
                MixerDeskKey(letter: "M", isOn: muted, tint: Self.muteTint,
                             help: "\(strings.mute): \(l10n.s.mixerSystemOutputTitle)") {
                    mixer.requestOutputAdjustment(muted: !muted)
                }
            }
        } badge: {
            MixerBusBadge(systemImage: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
        }
    }
}

/// One channel of the desk. Every strip gives each part the same height,
/// whether it fills it or not, so faders and keys line up across the desk.
private struct MixerStrip<Top: View, Slots: View, Knob: View, Readout: View,
                          Fader: View, Keys: View, Badge: View>: View {
    let name: String
    let color: Color
    @ViewBuilder let top: Top
    @ViewBuilder let slots: Slots
    @ViewBuilder let knob: Knob
    @ViewBuilder let readout: Readout
    @ViewBuilder let fader: Fader
    @ViewBuilder let keys: Keys
    @ViewBuilder let badge: Badge
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // Each part sits in a stack of its own, so an empty one still takes
        // its height and the strips stay level with each other.
        VStack(spacing: 4) {
            ZStack { top }.frame(height: 16)
            ZStack(alignment: .top) { slots }.frame(height: 50, alignment: .top)
            ZStack { knob }.frame(height: 24)
            ZStack { readout }.frame(height: 13)
            ZStack { fader }.frame(height: MixerDeskMetrics.faderHeight)
            HStack(spacing: 2) { keys }.frame(height: 16)
            ZStack { badge }.frame(height: 28)
            VStack(spacing: 2) {
                Rectangle().fill(color).frame(height: 2.5)
                Text(name)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 2)
                    .frame(height: 13)
            }
        }
        .padding(.top, 5)
        .padding(.bottom, 4)
        .frame(width: MixerDeskMetrics.stripWidth)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.primary.opacity(colorScheme == .dark ? 0.07 : 0.05)))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
        .help(name)
    }
}

/// The dark pill at the top of a strip that names a device and opens its menu.
private struct MixerStripMenu<Items: View>: View {
    let title: String
    let help: String
    @ViewBuilder let items: Items
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Menu { items } label: {
            Text(title)
                .font(.system(size: 8.5, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 3)
                .frame(width: MixerDeskMetrics.stripWidth - 10, height: 16)
                .background(RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(colorScheme == .dark ? Color.black.opacity(0.45) : Color.primary.opacity(0.1)))
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("\(help): \(title)")
        .accessibilityLabel("\(help): \(title)")
    }
}

/// The small dark box a level is printed in.
private struct MixerReadoutBox<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        content
            .font(.system(size: 8, weight: .semibold).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(.white)
            .frame(width: 23, height: 13)
            .background(RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.black.opacity(colorScheme == .dark ? 0.6 : 0.72)))
    }
}

/// A bus has no app icon: a symbol in a tile stands in for one.
private struct MixerBusBadge: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 28)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.1)))
    }
}

/// One effect in a strip's insert slots: lit while it runs, grey while
/// bypassed or missing. A click opens its window.
private struct MixerDeskEffectSlot: View {
    @ObservedObject var slot: MixerEffectSlot
    let app: MixerApp
    let strings: MixerPlusStrings
    let canMoveUp: Bool
    let canMoveDown: Bool
    @ObservedObject private var l10n = L10n.shared

    private var effects: MixerEffects { .shared }
    private var isLit: Bool { slot.isAvailable && !slot.isBypassed }

    var body: some View {
        let arrangement = FeatureStrings.mixer(l10n.language)
        Button {
            effects.openWindow(for: slot, app: app)
        } label: {
            Text(slot.name)
                .font(.system(size: 8, weight: .bold))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(isLit ? Color.white : Color.secondary)
                .padding(.horizontal, 3)
                .frame(width: MixerDeskMetrics.stripWidth - 10, height: 15)
                .background(RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(isLit ? Color(red: 0.24, green: 0.47, blue: 0.82) : Color.primary.opacity(0.14)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(slot.isAvailable ? "\(strings.openEffect): \(slot.name)" : "\(slot.name) (\(strings.effectUnavailable))")
        .contextMenu {
            if slot.isAvailable {
                Button(slot.isBypassed ? strings.turnEffectOn : strings.bypassEffect) {
                    effects.setBypassed(!slot.isBypassed, slot, in: app)
                }
                Divider()
            }
            Button(arrangement.moveUp) { effects.move(slot, by: -1, in: app) }.disabled(!canMoveUp)
            Button(arrangement.moveDown) { effects.move(slot, by: 1, in: app) }.disabled(!canMoveDown)
            Divider()
            Button(strings.removeEffect) { effects.remove(slot, from: app) }
        }
    }
}
