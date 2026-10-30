import AppKit
import Combine
import SwiftUI

/// The pet's home corner: up to 3 knitted decorations on a little shelf in the bottom-right corner of the screen.
struct HomeView: View {
    let items: [Decor]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { d in Text(d.emoji).font(.system(size: 22)) }
        }
        .padding(.horizontal, 8)
        .padding(.top, 2)
        .padding(.bottom, 5)
        .background(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.62, green: 0.45, blue: 0.33)).frame(height: 5)
        }
    }
}

@MainActor
final class HomeController {
    private let panel: NSPanel
    private var cancellables = Set<AnyCancellable>()

    init(life: PetLife, prefs: Prefs) {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 120, height: 40),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        // Clicks go through to whatever is behind it.
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        life.$state.combineLatest(prefs.$showHome)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] s, show in
                MainActor.assumeIsolated { self?.update(s.home.compactMap(Decor.init(rawValue:)), show: show) }
            }
            .store(in: &cancellables)
    }

    private var shown: [Decor] = []

    private func update(_ items: [Decor], show: Bool) {
        guard show, !items.isEmpty else {
            panel.orderOut(nil)
            shown = []
            return
        }
        if items != shown || !panel.isVisible {
            shown = items
            let host = NSHostingView(rootView: HomeView(items: items))
            panel.contentView = host
            panel.setContentSize(host.fittingSize)
        }
        place()
        panel.orderFrontRegardless()
    }

    /// Bottom-right corner of the main screen, just above the Dock.
    func place() {
        let vf = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        panel.setFrameOrigin(NSPoint(x: (vf.maxX - panel.frame.width - 12).rounded(), y: vf.minY.rounded()))
    }
}
