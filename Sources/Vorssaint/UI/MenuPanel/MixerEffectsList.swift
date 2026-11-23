// SPDX-License-Identifier: GPL-3.0-or-later

import AVFoundation
import SwiftUI

/// The effects under an app's row: each one with bypass, open and remove, and
/// a menu to add more. They run top to bottom, before the app's fader.
struct MixerEffectsList: View {
    let app: MixerApp
    @ObservedObject private var effects = MixerEffects.shared
    @ObservedObject private var catalog = MixerEffectCatalog.shared
    @ObservedObject private var l10n = L10n.shared

    private var strings: MixerPlusStrings { .localized(l10n.language) }
    private var arrangement: MixerFeatureStrings { FeatureStrings.mixer(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            let chain = effects.chains[MixerEffects.key(for: app)] ?? []
            ForEach(Array(chain.enumerated()), id: \.element.id) { index, slot in
                MixerEffectRow(slot: slot, app: app, strings: strings, arrangement: arrangement,
                               canMoveUp: index > 0, canMoveDown: index < chain.count - 1)
            }
            addMenu
        }
        .font(.system(size: 10.5))
        .onAppear {
            effects.load(app)
            catalog.load()
        }
    }

    private var addMenu: some View {
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
            Label(strings.addEffect, systemImage: "plus")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.secondary)
    }
}

private struct MixerEffectRow: View {
    @ObservedObject var slot: MixerEffectSlot
    let app: MixerApp
    let strings: MixerPlusStrings
    let arrangement: MixerFeatureStrings
    let canMoveUp: Bool
    let canMoveDown: Bool

    private var effects: MixerEffects { .shared }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                effects.setBypassed(!slot.isBypassed, slot, in: app)
            } label: {
                Image(systemName: "power")
                    .foregroundStyle(slot.isBypassed || !slot.isAvailable ? Color.secondary : Color.accentColor)
            }
            .disabled(!slot.isAvailable)
            .help(slot.isBypassed ? strings.turnEffectOn : strings.bypassEffect)
            .accessibilityLabel("\(slot.isBypassed ? strings.turnEffectOn : strings.bypassEffect): \(slot.name)")

            Text(slot.isAvailable ? slot.name : "\(slot.name) (\(strings.effectUnavailable))")
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(slot.isBypassed || !slot.isAvailable ? .secondary : .primary)
                .help(slot.manufacturer)
            Spacer(minLength: 4)

            if slot.isAvailable {
                Button {
                    effects.openWindow(for: slot, app: app)
                } label: {
                    Image(systemName: "macwindow")
                }
                .help("\(strings.openEffect): \(slot.name)")
                .accessibilityLabel("\(strings.openEffect): \(slot.name)")
            }
            Button {
                effects.remove(slot, from: app)
            } label: {
                Image(systemName: "xmark")
            }
            .help(strings.removeEffect)
            .accessibilityLabel("\(strings.removeEffect): \(slot.name)")
        }
        .buttonStyle(.borderless)
        .contextMenu {
            Button(arrangement.moveUp) { effects.move(slot, by: -1, in: app) }.disabled(!canMoveUp)
            Button(arrangement.moveDown) { effects.move(slot, by: 1, in: app) }.disabled(!canMoveDown)
        }
        .accessibilityAction(named: Text(arrangement.moveUp)) { effects.move(slot, by: -1, in: app) }
        .accessibilityAction(named: Text(arrangement.moveDown)) { effects.move(slot, by: 1, in: app) }
    }
}
