import AppKit
import AVFoundation
import SwiftUI

/// The pet's escalating mischief when you slack off.
enum AnticKind: Equatable {
    /// Level 1: sighs and grumbles in place.
    case grumble
    /// Level 2: marches across the screen dragging a sign with the task you're avoiding.
    case parade(String)
    /// Level 3: leaps up and stands in the middle of the screen until you get back to work.
    case block
}

struct AnticEvent: Equatable {
    let id = UUID()
    let kind: AnticKind
    let start: Date
}

/// Speaks short lines out loud with a macOS voice (Vietnamese uses "Linh" when it's installed).
@MainActor
final class Voice {
    static let shared = Voice()
    private let synth = AVSpeechSynthesizer()

    func say(_ text: String) {
        // Emoji would be read out by name; keep letters, digits and punctuation only.
        let scalars = text.unicodeScalars.filter { s in
            !(s.properties.isEmojiPresentation || (s.properties.isEmoji && s.value > 0x2000))
        }
        let clean = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        synth.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: clean)
        u.voice = AVSpeechSynthesisVoice(language: currentLang == .vi ? "vi-VN" : "en-US")
        synth.speak(u)
    }
}

final class SignModel: ObservableObject {
    @Published var text = ""
    /// The rope goes toward the pet.
    @Published var ropeOnRight = true
}

struct SignView: View {
    @ObservedObject var model: SignModel

    var body: some View {
        HStack(spacing: 0) {
            if !model.ropeOnRight { rope }
            Text("📌 " + model.text.uppercased())
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 240)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(LinearGradient(colors: [Color(red: 0.62, green: 0.40, blue: 0.22), Color(red: 0.45, green: 0.27, blue: 0.13)],
                                             startPoint: .top, endPoint: .bottom))
                        .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                )
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(red: 0.30, green: 0.17, blue: 0.08), lineWidth: 2))
            if model.ropeOnRight { rope }
        }
        .padding(6)
        .fixedSize()
    }

    private var rope: some View {
        Capsule().fill(Color(red: 0.55, green: 0.42, blue: 0.25)).frame(width: 22, height: 3)
    }
}

/// The sign the pet drags behind it during a parade.
@MainActor
final class SignController {
    private let panel: NSPanel
    private let model = SignModel()
    private let host: NSHostingView<SignView>

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 60),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        host = NSHostingView(rootView: SignView(model: model))
        panel.contentView = host
    }

    func show(_ text: String) {
        model.text = TextClean.short(text, 48)
        panel.setContentSize(host.fittingSize)
        panel.orderFrontRegardless()
    }

    func hide() { panel.orderOut(nil) }

    /// Keeps the sign behind the pet, on the side it's walking away from.
    func follow(_ petFrame: NSRect, facing: CGFloat) {
        guard panel.isVisible else { return }
        let ropeOnRight = facing > 0
        if model.ropeOnRight != ropeOnRight {
            model.ropeOnRight = ropeOnRight
            panel.setContentSize(host.fittingSize)
        }
        let w = panel.frame.width
        let x = ropeOnRight ? petFrame.minX - w + petFrame.width * 0.2 : petFrame.maxX - petFrame.width * 0.2
        panel.setFrameOrigin(NSPoint(x: x.rounded(), y: (petFrame.minY + petFrame.height * 0.18).rounded()))
    }
}
