import AppKit
import SwiftUI

/// Live motion values, read by the renderer every frame (deliberately not @Published).
final class PetMotion {
    var facing: CGFloat = -1
    var walking = false
    var walkPhase: Double = 0
    var lookX: CGFloat = 0
    var hovered = false
    var held = false
    /// You're typing or in the zone: small movements, no walking.
    var calm = false
    private var shownMood: Mood = .normal
    private var prevMood: Mood = .normal
    private var changedAt: Double = 0

    func pose(mood: Mood, t: Double) -> PetPose {
        if mood != shownMood {
            prevMood = shownMood
            shownMood = mood
            changedAt = t
        }
        var pose = PetPose(mood: mood, t: t, facing: facing, walking: walking, walkPhase: walkPhase, lookX: lookX,
                           hovered: hovered, held: held, prevMood: prevMood, blend: min(1, (t - changedAt) / 0.8))
        pose.calm = calm
        return pose
    }
}

struct PetView: View {
    @ObservedObject var brain: Brain
    @ObservedObject var life: PetLife
    let motion: PetMotion

    /// Calm moods animate slower to save battery; the pet runs all day.
    private var frameInterval: Double {
        switch brain.mood {
        case .sleeping: 1.0 / 10
        case .normal, .annoyed, .focus: 1.0 / 24
        case .happy, .angry, .celebrating: 1.0 / 30
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: frameInterval)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .top) {
                Canvas { ctx, size in
                    var pose = motion.pose(mood: brain.mood, t: t)
                    pose.decorate(life.state)
                    if let c = brain.celebration {
                        pose.celebration = c.kind
                        pose.golden = c.golden
                        let since = tl.date.timeIntervalSince(c.start)
                        if since < 1.6 {
                            pose.food = c.food
                            pose.foodT = since
                        }
                    }
                    PetArt.draw(&ctx, size: size, pose: pose)
                }
                if let f = brain.focus {
                    FocusChip(session: f, now: tl.date)
                } else if brain.flow {
                    Text("🎧")
                        .font(.system(size: 11))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.black.opacity(0.35)))
                        .help(L("Bạn đang vào guồng — mình giữ im lặng", "You're in the zone — I'll stay quiet"))
                }
            }
        }
    }
}

struct FocusChip: View {
    let session: FocusSession
    let now: Date

    var body: some View {
        let left = max(0, Int(session.end.timeIntervalSince(now)))
        Text("\(session.isBreak ? "☕" : "🍅") \(left / 60):\(String(format: "%02d", left % 60))")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .monospacedDigit()
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.black.opacity(0.7)))
            .foregroundColor(.white)
    }
}

/// Transparent view on top of the pet that turns mouse events into click / drag / hover.
final class PetHitView: NSView {
    var onClick: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?
    var onDragBegan: (() -> Void)?
    var onDragMoved: ((NSPoint) -> Void)?
    var onDragEnded: (() -> Void)?
    var onHover: ((Bool) -> Void)?

    private var downAt: NSPoint?
    private var startOrigin = NSPoint.zero
    private var dragging = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Only the pet's body is clickable; the transparent corners are not.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        let b = bounds
        let body = NSRect(x: b.width * 0.14, y: 0, width: b.width * 0.72, height: b.height * 0.72)
        return body.contains(p) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }

    override func mouseDown(with event: NSEvent) {
        downAt = NSEvent.mouseLocation
        startOrigin = window?.frame.origin ?? .zero
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = downAt else { return }
        let p = NSEvent.mouseLocation
        if !dragging, hypot(p.x - down.x, p.y - down.y) > 4 {
            dragging = true
            onDragBegan?()
        }
        if dragging { onDragMoved?(NSPoint(x: startOrigin.x + p.x - down.x, y: startOrigin.y + p.y - down.y)) }
    }

    override func mouseUp(with event: NSEvent) {
        if dragging { onDragEnded?() } else if downAt != nil { onClick?() }
        downAt = nil
        dragging = false
    }

    override func rightMouseDown(with event: NSEvent) { onRightClick?(event) }
}

/// Owns the pet window and makes the pet walk around the bottom of the screen.
@MainActor
final class PetController {
    let panel: NSPanel
    let hit = PetHitView()
    let motion = PetMotion()
    private let brain: Brain
    private let prefs: Prefs
    private var timer: Timer?
    private var last = CACurrentMediaTime()
    private var lastCalmCheck: Double = 0
    private var x: CGFloat = 0
    private var y: CGFloat = 0
    private var vy: CGFloat = 0

    private enum Behavior {
        case idle(until: Double), walk(toX: CGFloat), fall, held
        // Mischief (see `AnticKind`).
        case parade(toX: CGFloat), leap(from: NSPoint, to: NSPoint, start: Double), perch(until: Double)
    }

    /// Called when a parade or a perch on the screen is over.
    var onAnticEnded: (() -> Void)?

    var isInAntic: Bool {
        switch behavior {
        case .parade, .leap, .perch: true
        default: false
        }
    }

    /// Marches to the far side of the screen (the sign follows via `onMoved`).
    func startParade() {
        let vf = screen.visibleFrame
        behavior = .parade(toX: x + size / 2 > vf.midX ? vf.minX + 10 : vf.maxX - size - 10)
    }

    /// Leaps up into the middle of the screen and stays there a while.
    func startBlock() {
        let vf = screen.visibleFrame
        behavior = .leap(from: NSPoint(x: x, y: y), to: NSPoint(x: vf.midX - size / 2, y: vf.midY - size / 2),
                         start: CACurrentMediaTime())
    }

    func endAntic() {
        guard isInAntic else { return }
        vy = 0
        behavior = .fall
        onAnticEnded?()
    }
    private var behavior: Behavior = .fall

    /// True while a bubble or the board is open: the pet stands still.
    var paused = false
    var onMoved: ((NSRect) -> Void)?

    var size: CGFloat { CGFloat(124 * min(max(prefs.petScale, 0.6), 2.0)) }
    var frame: NSRect { panel.frame }
    var isVisible: Bool { panel.isVisible }

    init(brain: Brain, prefs: Prefs) {
        self.brain = brain
        self.prefs = prefs
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 124, height: 124),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.hidesOnDeactivate = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 124, height: 124))
        let host = NSHostingView(rootView: PetView(brain: brain, life: brain.life, motion: motion))
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        hit.frame = container.bounds
        hit.autoresizingMask = [.width, .height]
        container.addSubview(host)
        container.addSubview(hit)
        panel.contentView = container

        hit.onHover = { [weak self] inside in self?.motion.hovered = inside }
        hit.onDragBegan = { [weak self] in
            self?.behavior = .held
            self?.motion.held = true
            self?.motion.walking = false
        }
        hit.onDragMoved = { [weak self] origin in
            self?.x = origin.x
            self?.y = origin.y
        }
        hit.onDragEnded = { [weak self] in
            self?.motion.held = false
            self?.vy = 0
            self?.behavior = .fall
        }

        let vf = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        x = vf.maxX - size - 140
        y = vf.minY + 300
        applySize()
        panel.orderFrontRegardless()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func applySize() {
        panel.setFrame(NSRect(x: x, y: y, width: size, height: size), display: true)
    }

    func show() { panel.orderFrontRegardless() }
    func hide() { panel.orderOut(nil) }

    /// Brings the pet back to the bottom of the main screen.
    func comeHere() {
        let vf = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        x = vf.midX - size / 2
        y = vf.minY + 200
        vy = 0
        behavior = .fall
        show()
    }

    private var screen: NSScreen {
        let c = CGPoint(x: x + size / 2, y: y + size / 2)
        return NSScreen.screens.first { $0.frame.contains(c) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private var groundY: CGFloat { screen.visibleFrame.minY - size * 0.05 }

    private func speed(_ m: Mood) -> CGFloat {
        let base: CGFloat = switch m {
        case .happy: 58
        case .normal, .focus: 38
        case .annoyed: 22
        case .angry: 70
        case .sleeping, .celebrating: 0
        }
        return base * size / 124
    }

    private func step() {
        let now = CACurrentMediaTime()
        let dt = min(0.1, now - last)
        last = now
        let mood = brain.mood
        if now - lastCalmCheck > 0.5 {
            lastCalmCheck = now
            motion.calm = brain.calmMotion
        }
        if abs(panel.frame.width - size) > 0.5 { applySize() }

        switch behavior {
        case .held:
            break
        case .fall:
            motion.walking = false
            vy -= 2200 * CGFloat(dt)
            y += vy * CGFloat(dt)
            if y <= groundY {
                y = groundY
                vy = 0
                behavior = .idle(until: now + 0.8)
            }
        case .idle(let until):
            motion.walking = false
            if now >= until && !paused && !motion.hovered { chooseNext(now, mood) }
        case .walk(let tx):
            if paused || motion.hovered || motion.calm || speed(mood) == 0 {
                behavior = .idle(until: now + 0.6)
                motion.walking = false
                break
            }
            let dx = tx - x
            if abs(dx) < 2 {
                behavior = .idle(until: now + idleTime(mood))
                motion.walking = false
            } else {
                let dir: CGFloat = dx > 0 ? 1 : -1
                let v = speed(mood)
                x += dir * min(abs(dx), v * CGFloat(dt))
                motion.facing = dir
                motion.walking = true
                motion.walkPhase += dt * Double(v / (size / 124)) / 38 * 9
            }
        case .parade(let tx):
            // Mischief ignores pauses: the bubble just follows along.
            let dx = tx - x
            if abs(dx) < 2 {
                motion.walking = false
                behavior = .idle(until: now + 2)
                onAnticEnded?()
            } else {
                let dir: CGFloat = dx > 0 ? 1 : -1
                let v = 95 * size / 124
                x += dir * min(abs(dx), v * CGFloat(dt))
                motion.facing = dir
                motion.walking = true
                motion.walkPhase += dt * 20
            }
        case .leap(let from, let to, let start):
            motion.walking = false
            let k = CGFloat(min(1, (now - start) / 0.7))
            x = from.x + (to.x - from.x) * k
            y = from.y + (to.y - from.y) * k + sin(.pi * k) * 120
            if k >= 1 { behavior = .perch(until: now + 20) }
        case .perch(let until):
            motion.walking = false
            if now >= until { endAntic() }
        }

        let vf = screen.visibleFrame
        switch behavior {
        case .held, .fall, .leap, .perch: break
        default: y = groundY
        }
        if case .held = behavior {} else {
            x = min(max(x, vf.minX - size * 0.1), vf.maxX - size * 0.9)
        }
        if !motion.walking {
            let m = NSEvent.mouseLocation
            let target = max(-1, min(1, (m.x - (x + size / 2)) / 300))
            motion.lookX += (target - motion.lookX) * CGFloat(min(1, dt * 4))
        }
        let origin = NSPoint(x: x.rounded(), y: y.rounded())
        if panel.frame.origin != origin {
            panel.setFrameOrigin(origin)
            onMoved?(panel.frame)
        }
    }

    private func idleTime(_ m: Mood) -> Double {
        switch m {
        case .happy: .random(in: 1.5...3.5)
        case .normal: .random(in: 3...7)
        case .annoyed: .random(in: 5...9)
        case .angry: .random(in: 1.5...3)
        case .focus, .sleeping: 5
        case .celebrating: 1
        }
    }

    private func chooseNext(_ now: Double, _ mood: Mood) {
        // No wandering while you type: walking at the edge of the screen pulls your eyes away.
        if motion.calm {
            behavior = .idle(until: now + 2)
            return
        }
        let vf = screen.visibleFrame
        let minX = vf.minX + 10, maxX = vf.maxX - size - 10
        func clamp(_ v: CGFloat) -> CGFloat { min(max(v, minX), maxX) }
        switch mood {
        case .sleeping, .celebrating:
            behavior = .idle(until: now + idleTime(mood))
        case .focus:
            // Walk to a quiet corner and sit there.
            let corner = maxX - 20
            behavior = abs(x - corner) > 4 ? .walk(toX: corner) : .idle(until: now + 5)
        case .angry where prefs.chaseWhenAngry && Double.random(in: 0...1) < 0.65:
            // Grumpy pets march toward your cursor.
            behavior = .walk(toX: clamp(NSEvent.mouseLocation.x - size / 2))
        default:
            let chance: Double = switch mood {
            case .happy: 0.7
            case .annoyed: 0.3
            default: 0.55
            }
            if Double.random(in: 0...1) < chance {
                let dist = CGFloat.random(in: 80...320) * (Bool.random() ? 1 : -1)
                behavior = .walk(toX: clamp(x + dist))
            } else {
                behavior = .idle(until: now + idleTime(mood))
            }
        }
    }
}
