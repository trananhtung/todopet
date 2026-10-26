import AppKit
import SwiftUI

/// NSHostingView that reacts to the first click even though the panel never becomes active.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class BubbleModel: ObservableObject {
    @Published var bubble: Bubble?
    @Published var tailX: CGFloat = 130
    @Published var mood: Mood = .normal
    var petName = "Mochi"
    var onAction: ((BubbleAction) -> Void)?
    var onClose: (() -> Void)?
}

struct BubbleShape: Shape {
    var tailX: CGFloat
    let tail: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - tail)
        var p = Path(roundedRect: body, cornerRadius: 16)
        let tx = min(max(tailX, body.minX + 22), body.maxX - 22)
        p.move(to: CGPoint(x: tx - 9, y: body.maxY - 0.5))
        p.addQuadCurve(to: CGPoint(x: tx + 2, y: rect.maxY), control: CGPoint(x: tx - 2, y: body.maxY + 4))
        p.addQuadCurve(to: CGPoint(x: tx + 9, y: body.maxY - 0.5), control: CGPoint(x: tx + 4, y: body.maxY + 2))
        p.closeSubpath()
        return p
    }
}

struct PillButtonStyle: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(primary ? Color.accentColor : Color.primary.opacity(0.08)))
            .foregroundColor(primary ? .white : .primary)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}

struct BubbleView: View {
    @ObservedObject var model: BubbleModel
    static let width: CGFloat = 270

    var body: some View {
        if let b = model.bubble {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(model.petName) \(model.mood.emoji)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button { model.onClose?() } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Text(b.text)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
                if !b.actions.isEmpty {
                    let rows = stride(from: 0, to: b.actions.count, by: 2).map { Array(b.actions[$0..<min($0 + 2, b.actions.count)]) }
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(rows.indices, id: \.self) { i in
                            HStack(spacing: 6) {
                                ForEach(rows[i]) { a in
                                    Button(a.title) { model.onAction?(a) }.buttonStyle(PillButtonStyle(primary: a.primary))
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 12 + 10)
            .frame(width: BubbleView.width, alignment: .leading)
            .background(
                BubbleShape(tailX: model.tailX)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
            )
            .overlay(BubbleShape(tailX: model.tailX).stroke(Color.primary.opacity(0.08), lineWidth: 1))
            .padding(10)
        }
    }
}

/// Speech bubble floating above the pet.
@MainActor
final class BubbleController {
    let panel: NSPanel
    let model = BubbleModel()
    private let host: FirstMouseHostingView<BubbleView>
    private var hideWork: DispatchWorkItem?
    private var petFrame = NSRect.zero
    private var hovering = false

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 290, height: 100),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        host = FirstMouseHostingView(rootView: BubbleView(model: model))
        panel.contentView = host
    }

    var isVisible: Bool { panel.isVisible }

    func show(_ b: Bubble, petFrame: NSRect, mood: Mood, name: String, onDone: @escaping () -> Void) {
        model.petName = name
        model.mood = mood
        model.bubble = b
        self.petFrame = petFrame
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        panel.setContentSize(size)
        place()
        // Fade in gently instead of popping up: abrupt onsets grab attention the most.
        let appearing = !panel.isVisible
        if appearing { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        if appearing {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.35
                panel.animator().alphaValue = 1
            }
        }

        hideWork?.cancel()
        let work = DispatchWorkItem(block: onDone)
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + b.seconds, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        hideWork = nil
        model.bubble = nil
        panel.orderOut(nil)
    }

    func follow(_ petFrame: NSRect) {
        self.petFrame = petFrame
        if panel.isVisible { place() }
    }

    private func place() {
        let size = panel.frame.size
        let screen = NSScreen.screens.first { $0.frame.intersects(petFrame) } ?? NSScreen.main ?? NSScreen.screens[0]
        let vf = screen.visibleFrame
        let petCenter = petFrame.midX
        var x = petCenter - size.width / 2
        x = min(max(x, vf.minX + 4), vf.maxX - size.width - 4)
        var y = petFrame.minY + petFrame.height * 0.62
        y = min(y, vf.maxY - size.height)
        panel.setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
        let tail = petCenter - x - 10
        if abs(model.tailX - tail) > 1 { model.tailX = tail }
    }
}
