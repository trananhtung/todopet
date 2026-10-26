import AppKit
import Carbon
import Combine
import SwiftUI

/// NSMenuItem that runs a closure.
final class ActionItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, key: String = "", modifiers: NSEvent.ModifierFlags = .command, _ handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        keyEquivalentModifierMask = modifiers
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func fire() { handler() }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let prefs = Prefs.shared
    private var brain: Brain!
    private var pet: PetController!
    private var bubbles: BubbleController!
    private let sign = SignController()
    private var board: BoardController!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var hotKey: HotKey?
    private var showPetWork: DispatchWorkItem?
    private var statusTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            DevTools.snapshot(to: args[i + 1])
            return
        }
        if args.contains("--selftest") { exit(DevTools.selfTest() ? 0 : 1) }

        installEditMenu()
        brain = Brain(prefs: prefs, demo: args.contains("--demo"))
        pet = PetController(brain: brain, prefs: prefs)
        bubbles = BubbleController()
        board = BoardController(brain: brain, prefs: prefs)

        brain.openBoard = { [weak self] focusAdd in self?.openBoard(focusAdd: focusAdd) }
        brain.openBreakdown = { [weak self] task in
            self?.board.state.breakdown = task
            self?.openBoard(focusAdd: false)
        }
        brain.openSettings = { [weak self] in self?.openSettings() }

        pet.hit.onClick = { [weak self] in self?.petClicked() }
        pet.hit.onRightClick = { [weak self] event in
            guard let self else { return }
            let menu = NSMenu()
            self.fill(menu)
            NSMenu.popUpContextMenu(menu, with: event, for: self.pet.hit)
        }
        pet.onMoved = { [weak self] frame in
            guard let self else { return }
            bubbles.follow(frame)
            sign.follow(frame, facing: pet.motion.facing)
        }
        pet.onAnticEnded = { [weak self] in
            self?.sign.hide()
            self?.brain.endAntic()
        }
        brain.$antic.receive(on: DispatchQueue.main).sink { [weak self] antic in
            MainActor.assumeIsolated { self?.perform(antic) }
        }.store(in: &cancellables)

        bubbles.model.onAction = { [weak self] action in
            self?.brain.noteResponse(.picked(action.title))
            self?.brain.bubble = nil
            action.run()
        }
        bubbles.model.onClose = { [weak self] in
            if self?.brain.bubble?.reminder == true { self?.brain.noteResponse(.closed) }
            self?.brain.bubble = nil
        }
        board.onShownChanged = { [weak self] _ in self?.updatePause() }

        brain.$bubble.receive(on: DispatchQueue.main).sink { [weak self] b in
            MainActor.assumeIsolated { self?.showBubble(b) }
        }.store(in: &cancellables)

        setupStatusItem()
        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(controlKey | optionKey), id: 1) { [weak self] in
            MainActor.assumeIsolated { self?.openBoard(focusAdd: true) }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pet.applySize() }
        }
        brain.start()
    }

    // MARK: - Bubble & board

    private func showBubble(_ b: Bubble?) {
        guard let b else {
            bubbles.hide()
            updatePause()
            return
        }
        if !pet.isVisible || (board.isShown && !b.urgent) {
            brain.bubble = nil
            return
        }
        let id = b.id
        bubbles.show(b, petFrame: pet.frame, mood: brain.mood, name: prefs.petName) { [weak self] in
            if self?.brain.bubble?.id == id {
                if self?.brain.bubble?.reminder == true { self?.brain.noteResponse(.ignored) }
                self?.brain.bubble = nil
            }
        }
        updatePause()
    }

    private func updatePause() {
        pet.paused = bubbles.isVisible || board.isShown
    }

    /// Plays the brain's mischief with the pet window (grumbling needs no movement).
    private func perform(_ antic: AnticEvent?) {
        guard pet.isVisible else { return }
        switch antic?.kind {
        case .parade(let text)?:
            sign.show(text)
            pet.startParade()
            sign.follow(pet.frame, facing: pet.motion.facing)
        case .block?:
            pet.startBlock()
        case .grumble?:
            break
        case nil:
            sign.hide()
            pet.endAntic()
        }
    }

    private func petClicked() {
        // Clicking the pet calls off any mischief.
        if pet.isInAntic { brain.endAntic() }
        if let b = brain.bubble, b.actions.isEmpty { brain.bubble = nil }
        if board.isShown {
            board.popover.performClose(nil)
        } else {
            openBoard(focusAdd: false)
        }
    }

    private func openBoard(focusAdd: Bool) {
        if brain.bubble != nil { brain.bubble = nil }
        if pet.isVisible {
            board.show(relativeTo: pet.hit, focusAdd: focusAdd)
        } else if let button = statusItem.button {
            board.show(relativeTo: button, focusAdd: focusAdd)
        }
        brain.refreshSoon()
    }

    private func openSettings() {
        board.popover.performClose(nil)
        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(prefs: prefs, brain: brain)))
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            settingsWindow = w
        }
        settingsWindow?.title = L("Cài đặt TodoPet", "TodoPet Settings")
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        Publishers.CombineLatest3(brain.$mood, brain.$day, brain.$focus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _ in MainActor.assumeIsolated { self?.updateStatusTitle() } }
            .store(in: &cancellables)
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                if self?.brain.focus != nil { self?.updateStatusTitle() }
            }
        }
        updateStatusTitle()
    }

    private func updateStatusTitle() {
        guard let button = statusItem?.button else { return }
        if let f = brain.focus {
            let left = max(0, Int(f.end.timeIntervalSinceNow))
            button.title = "\(f.isBreak ? "☕" : "🍅") \(left / 60):\(String(format: "%02d", left % 60))"
        } else if brain.hasToken {
            button.title = "\(brain.mood.emoji) \(brain.day.completed.count)/\(max(brain.target, brain.day.planned))"
        } else {
            button.title = "🐾"
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        fill(menu)
    }

    private func fill(_ menu: NSMenu) {
        let header = NSMenuItem(title: "\(prefs.petName) \(brain.mood.emoji) — \(brain.mood.label)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        menu.addItem(ActionItem(L("Mở bảng việc", "Open task board") + "   ⌃⌥T") { [weak self] in self?.openBoard(focusAdd: false) })
        if brain.hasToken {
            menu.addItem(ActionItem(L("Thêm việc…", "Add a task…")) { [weak self] in self?.openBoard(focusAdd: true) })
            if brain.focus != nil {
                menu.addItem(ActionItem(L("Dừng tập trung", "Stop focus")) { [weak self] in self?.brain.stopFocus() })
            } else {
                menu.addItem(ActionItem(L("Bắt đầu tập trung \(prefs.focusMinutes)'", "Start focus \(prefs.focusMinutes)'")) { [weak self] in
                    self?.brain.startFocus(nil)
                })
            }
        } else {
            menu.addItem(ActionItem(L("Kết nối Todoist…", "Connect Todoist…")) { [weak self] in self?.openBoard(focusAdd: false) })
        }
        menu.addItem(.separator())
        menu.addItem(ActionItem(L("Gọi \(prefs.petName) về đây", "Call \(prefs.petName) over")) { [weak self] in self?.pet.comeHere() })
        if pet.isVisible {
            menu.addItem(ActionItem(L("Ẩn pet 1 giờ", "Hide pet for 1 hour")) { [weak self] in self?.hidePet(for: 3600) })
        } else {
            menu.addItem(ActionItem(L("Hiện pet", "Show pet")) { [weak self] in self?.showPet() })
        }
        if let q = brain.quietUntil, q > Date() {
            menu.addItem(ActionItem(L("Bật lại nhắc nhở", "Resume reminders")) { [weak self] in self?.brain.quiet(minutes: nil) })
        } else {
            menu.addItem(ActionItem(L("Im lặng 1 giờ", "Quiet for 1 hour")) { [weak self] in self?.brain.quiet(minutes: 60) })
        }
        menu.addItem(ActionItem(L("Làm mới", "Refresh"), key: "r") { [weak self] in self?.brain.refreshSoon() })
        menu.addItem(ActionItem(L("Nhật ký pet…", "Pet diary…")) { [weak self] in
            self?.board.state.showLog = true
            self?.openBoard(focusAdd: false)
        })
        menu.addItem(.separator())
        menu.addItem(ActionItem(L("Cài đặt…", "Settings…"), key: ",") { [weak self] in self?.openSettings() })
        menu.addItem(ActionItem(L("Thoát TodoPet", "Quit TodoPet"), key: "q") { NSApp.terminate(nil) })
    }

    private func hidePet(for seconds: Double) {
        brain.bubble = nil
        board.popover.performClose(nil)
        pet.hide()
        showPetWork?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.showPet() } }
        showPetWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func showPet() {
        showPetWork?.cancel()
        pet.show()
    }

    /// Accessory apps have no visible menu bar, but ⌘C/⌘V/⌘A still need an Edit menu to work in text fields.
    private func installEditMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }
}
