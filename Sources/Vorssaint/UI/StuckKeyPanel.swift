// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// The small notice that appears under the menu bar when a key looks stuck.
/// It never takes the keyboard: with a modifier stuck, a window that became
/// key would only make things worse.
final class StuckKeyPanelController {
    private var panel: OverlayPanel?
    private var hideWork: DispatchWorkItem?

    func show() {
        hideWork?.cancel()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        position(panel)
        panel.orderFrontRegardless()
    }

    func hide(after delay: TimeInterval = 0) {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.panel?.orderOut(nil) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func makePanel() -> OverlayPanel {
        let host = NSHostingController(rootView: StuckKeyNotice())
        host.sizingOptions = .preferredContentSize
        let panel = OverlayPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 90),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentViewController = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        return panel
    }

    /// Top centre of the screen the pointer is on, just under the menu bar.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        panel.layoutIfNeeded()
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 12))
    }
}

private struct StuckKeyNotice: View {
    @ObservedObject private var watch = StuckKeyWatch.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.colorScheme) private var colorScheme

    private var strings: StuckKeyStrings { .localized(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(watch.current, id: \.self) { finding in
                row(finding)
            }
            if let result = watch.lastRelease {
                Label(String(format: result.cleared ? strings.releasedFormat : strings.stillDownFormat,
                             StuckKeyWatch.name(of: result.finding.subject, l10n.language)),
                      systemImage: result.cleared ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(result.cleared ? Color.green : Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(width: 340, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 0.7))
    }

    private func row(_ finding: StuckKeyFinding) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "keyboard.badge.ellipsis")
                .font(.system(size: 18))
                .foregroundStyle(.orange)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(String(format: strings.looksStuckFormat, StuckKeyWatch.name(of: finding.subject, l10n.language)))
                    .font(.system(size: 12.5, weight: .semibold))
                Text(StuckKeyWatch.explanation(of: finding.reason, duration: finding.duration, l10n.language))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button(strings.release) { watch.release(finding) }
                        .keyboardShortcut(.none)
                    Button(strings.ignore) { watch.dismiss(finding) }
                }
                .controlSize(.small)
                .padding(.top, 3)
            }
            Spacer(minLength: 0)
        }
    }
}
