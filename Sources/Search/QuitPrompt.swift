import AppKit
import SwiftUI

// ⌘Q, asked about first: Search's own card rather than the system's alert,
// on by default and put away for good from the card itself.
//
// ⌘Q sits one key from ⌘W, and a slip of the finger closing every window is
// the one keystroke in a browser that loses the most. The card is quick to
// answer from the keyboard either way: Return quits, Escape stays, and ⌘Q
// pressed again — a second, deliberate press — quits too. "Quit, and don't
// ask again" turns it off; Settings › General turns it back on.
//
// Modal, and answered before the quit goes on, so the caller stays a plain
// yes or no (Links.shouldQuit).

@MainActor
enum QuitPrompt {
    enum Answer { case quit, quitForGood, stay }

    /// Asks, on the window in front's screen, and waits for the answer.
    static func ask() -> Answer {
        var answer = Answer.stay
        let panel = Card(contentRect: NSRect(x: 0, y: 0, width: 440, height: 220),
                         styleMask: [.borderless], backing: .buffered, defer: false)
        let finish: (Answer) -> Void = { picked in
            answer = picked
            NSApp.stopModal()
        }
        let host = NSHostingView(rootView: QuitCard(answer: finish))
        host.frame.size = host.fittingSize
        panel.setContentSize(host.fittingSize)
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .modalPanel
        panel.isReleasedWhenClosed = false
        panel.appearance = NSApp.effectiveAppearance
        place(panel)

        // The keys, while it is up: Return quits, Escape stays, ⌘Q again quits.
        let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.window === panel else { return event }
            let command = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
            switch event.keyCode {
            case 36, 76: finish(.quit)                                  // Return, Enter
            case 53: finish(.stay)                                      // Escape
            case 12 where command: finish(.quit)                        // ⌘Q
            default: return event
            }
            return nil
        }
        defer { if let keys { NSEvent.removeMonitor(keys) } }

        // The window behind it darkened while it is up, so the question is
        // the one thing lit.
        let dim = Dim(over: Links.window)
        defer { dim?.lift() }

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        NSApp.runModal(for: panel)
        panel.orderOut(nil)
        return answer
    }

    /// A shade over the whole browser window, title bar and all: laid in its
    /// frame view rather than a window of its own, so the window's own
    /// rounded corners clip it and it never squares them off. Fades in, and
    /// out again as the card goes.
    private final class Dim {
        private let shade = NSView()

        init?(over window: NSWindow?) {
            guard let frame = window?.contentView?.superview else { return nil }
            shade.wantsLayer = true
            shade.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
            shade.frame = frame.bounds
            shade.autoresizingMask = [.width, .height]
            shade.alphaValue = 0
            frame.addSubview(shade, positioned: .above, relativeTo: nil)
            if Motion.reduced {
                shade.alphaValue = 1
            } else {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.18
                    shade.animator().alphaValue = 1
                }
            }
        }

        func lift() {
            let shade = shade
            guard !Motion.reduced else { shade.removeFromSuperview(); return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.14
                shade.animator().alphaValue = 0
            }, completionHandler: { shade.removeFromSuperview() })
        }
    }

    /// Over the middle of the window in front, a little above centre, as a
    /// sheet would sit; on the main screen with no window.
    private static func place(_ panel: NSPanel) {
        let size = panel.frame.size
        let area = Links.window?.frame ?? NSScreen.main?.visibleFrame ?? .zero
        panel.setFrameOrigin(NSPoint(x: area.midX - size.width / 2,
                                     y: area.midY - size.height / 2 + area.height * 0.08))
    }

    /// A borderless panel still takes the keyboard.
    private final class Card: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
    }
}

private struct QuitCard: View {
    let answer: (QuitPrompt.Answer) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 60, height: 60)
                .padding(.bottom, 16)
            Text("Quit Search?")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.ink)
            // Only promised back when they will be: not with Settings set to
            // start fresh (Preferences.startsFresh).
            Text(Store.settings.bool(forKey: Preferences.freshKey)
                 ? "Your windows and tabs will close."
                 : "Your windows and tabs will close, and come back next time.")
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.muted)
                .padding(.top, 4)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Choice(title: "Quit, and don’t ask again") { answer(.quitForGood) }
                Spacer(minLength: 16)
                Choice(title: "Cancel", key: "esc") { answer(.stay) }
                Choice(title: "Quit", symbol: "return", filled: true) { answer(.quit) }
            }
            .padding(.top, 28)
        }
        .padding(24)
        .frame(width: 460, alignment: .leading)
.background(Palette.ground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
        .padding(1)
    }

    /// One of the three: a word, and the key that answers the same.
    private struct Choice: View {
        let title: String
        var key: String? = nil
        var symbol: String? = nil
        var filled = false
        let act: () -> Void
        @State private var hovering = false

        private var ink: Color { filled ? Palette.ground : Palette.ink }

        var body: some View {
            Button(action: act) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                    if key != nil || symbol != nil {
                        Group {
                            if let key {
                                Text(key.uppercased())
                                    .font(.system(size: 10, weight: .semibold))
                                    .tracking(0.4)
                            } else if let symbol {
                                Image(systemName: symbol)
                                    .font(.system(size: 10, weight: .semibold))
                            }
                        }
                        .padding(.horizontal, 6)
                        .frame(height: 18)
                        .background(ink.opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                }
                .foregroundStyle(ink)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(background, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    if !filled {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Palette.hairline, lineWidth: 1)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .fixedSize()
            .onHover { hovering = $0 }
        }

        private var background: Color {
            if filled { return hovering ? Palette.ink.opacity(0.85) : Palette.ink }
            return hovering ? Palette.hover : Palette.wash
        }
    }
}
