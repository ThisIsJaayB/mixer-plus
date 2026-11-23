// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import AVFoundation
import CoreAudioKit
import SwiftUI

/// Opens each effect's interface in its own window. A window stays open when
/// the menu bar panel closes, and is brought back if opened again.
final class MixerEffectWindows {
    private var windows: [UUID: NSWindow] = [:]
    private var closeObservers: [UUID: NSObjectProtocol] = [:]

    /// `onClose` runs after the window closes, so the plugin's settings can
    /// be saved as they were left.
    func open(_ slot: MixerEffectSlot, appName: String, onClose: @escaping () -> Void) {
        if let window = windows[slot.id] { return show(window) }
        guard let audioUnit = slot.unit?.auAudioUnit else { return }
        guard slot.record.hasCustomView else {
            return present(slot, appName: appName, viewController: nil, onClose: onClose)
        }
        // The Audio Unit answers on a thread of its choosing.
        audioUnit.requestViewController { [weak self] viewController in
            DispatchQueue.main.async {
                // A plugin without an interface still returns a view, an
                // empty 1×1 placeholder: the generic panel is used for it.
                let usable = viewController.flatMap { $0.preferredContentSize.width > 10 ? $0 : nil }
                self?.present(slot, appName: appName, viewController: usable, onClose: onClose)
            }
        }
    }

    func close(_ id: UUID) {
        if let observer = closeObservers.removeValue(forKey: id) {
            NotificationCenter.default.removeObserver(observer)
        }
        windows.removeValue(forKey: id)?.close()
    }

    private func present(_ slot: MixerEffectSlot, appName: String, viewController: NSViewController?,
                         onClose: @escaping () -> Void) {
        guard windows[slot.id] == nil, let audioUnit = slot.unit?.auAudioUnit else { return }
        let content = viewController ?? NSHostingController(
            rootView: MixerEffectParametersView(parameters: audioUnit.parameterTree?.allParameters ?? []))
        let window = NSWindow(contentViewController: content)
        window.title = "\(slot.name) — \(appName)"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        if let viewController, viewController.preferredContentSize != .zero {
            window.setContentSize(viewController.preferredContentSize)
        }
        window.center()
        windows[slot.id] = window
        closeObservers[slot.id] = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in onClose() }
        show(window)
    }

    private func show(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

/// Controls for each parameter of a plugin that brings no interface of its
/// own: a pop-up for named choices, a switch for on/off, a slider otherwise.
struct MixerEffectParametersView: View {
    let parameters: [AUParameter]
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        Group {
            if parameters.isEmpty {
                Text(MixerPlusStrings.localized(l10n.language).effectHasNoSettings)
                    .foregroundStyle(.secondary)
                    .padding(24)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(parameters, id: \.address) { MixerEffectParameterRow(parameter: $0) }
                    }
                    .padding(20)
                }
                .frame(maxHeight: 520)
            }
        }
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct MixerEffectParameterRow: View {
    let parameter: AUParameter
    @State private var value: AUValue

    init(parameter: AUParameter) {
        self.parameter = parameter
        _value = State(initialValue: parameter.value)
    }

    var body: some View {
        control
            .onChange(of: value) { parameter.value = value }
            .disabled(!parameter.flags.contains(.flag_IsWritable))
    }

    @ViewBuilder
    private var control: some View {
        if let choices = parameter.valueStrings, !choices.isEmpty {
            Picker(parameter.displayName, selection: Binding(
                get: { Int(value.rounded()) }, set: { value = AUValue($0) })) {
                ForEach(Array(choices.enumerated()), id: \.offset) { index, choice in
                    Text(choice).tag(Int(parameter.minValue) + index)
                }
            }
        } else if parameter.unit == .boolean {
            Toggle(parameter.displayName, isOn: Binding(get: { value >= 0.5 }, set: { value = $0 ? 1 : 0 }))
        } else {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(parameter.displayName)
                    Spacer()
                    Text(displayValue)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $value,
                       in: parameter.minValue...max(parameter.maxValue, parameter.minValue + .ulpOfOne))
                    .accessibilityLabel(parameter.displayName)
            }
        }
    }

    /// The plugin's own text for the value if it gives one (many of Apple's
    /// effects return an empty string), otherwise the number with decimals
    /// suited to the range.
    private var displayValue: String {
        var current = value
        var text = parameter.string(fromValue: &current)
        if text.isEmpty {
            let span = parameter.maxValue - parameter.minValue
            let decimals = span >= 100 ? 0 : span >= 10 ? 1 : abs(value) < 0.1 ? 3 : 2
            text = value.formatted(.number.precision(.fractionLength(decimals)))
        }
        return parameter.unitName.map { "\(text) \($0)" } ?? text
    }
}
