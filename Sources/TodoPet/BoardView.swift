import AppKit
import SwiftUI

final class BoardState: ObservableObject {
    @Published var focusAddToken = UUID()
    /// When set, the board shows the "split this task" view.
    @Published var breakdown: TodoTask?
}

enum PriorityStyle {
    static func color(_ uiPriority: Int) -> Color {
        switch uiPriority {
        case 1: Color(red: 0.82, green: 0.27, blue: 0.23)
        case 2: Color(red: 0.92, green: 0.54, blue: 0.04)
        case 3: Color(red: 0.14, green: 0.44, blue: 0.88)
        default: Color.secondary
        }
    }
}

/// Little pet face used in the board header.
struct MiniPet: View {
    let mood: Mood
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20)) { tl in
            Canvas { ctx, size in
                PetArt.draw(&ctx, size: size, pose: PetPose(mood: mood, t: tl.date.timeIntervalSinceReferenceDate))
            }
        }
        .frame(width: 54, height: 54)
    }
}

/// The task board that opens when you click the pet.
struct BoardView: View {
    @ObservedObject var brain: Brain
    @ObservedObject var prefs: Prefs
    @ObservedObject var state: BoardState
    var close: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if brain.hasToken, let task = state.breakdown {
                BreakdownView(task: task, brain: brain, state: state)
            } else if brain.hasToken {
                content
            } else {
                TokenSetupView(brain: brain, prefs: prefs)
                    .padding(14)
            }
            Divider()
            footer
        }
        .frame(width: 370)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            MiniPet(mood: brain.mood)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(prefs.petName) \(brain.mood.label) \(brain.mood.emoji)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                HStack(spacing: 4) {
                    ForEach(0..<max(brain.target, brain.day.planned), id: \.self) { i in
                        Circle()
                            .fill(i < brain.day.completed.count ? Color.green : (i < brain.day.planned ? Color.primary.opacity(0.25) : Color.clear))
                            .overlay(Circle().stroke(Color.primary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: i < brain.day.planned ? [] : [2])))
                            .frame(width: 9, height: 9)
                    }
                    Text(L("Xong \(brain.day.completed.count)/\(max(brain.day.planned, brain.target)) hôm nay",
                           "\(brain.day.completed.count)/\(max(brain.day.planned, brain.target)) done today"))
                        .font(.caption).foregroundColor(.secondary)
                }
                if let reason = brain.reasons.first {
                    Text("\(reason.delta > 0 ? "▲" : "▼") \(reason.text)")
                        .font(.caption2)
                        .foregroundColor(reason.delta > 0 ? .green : .orange)
                        .help(brain.reasons.map { "\($0.delta > 0 ? "+" : "")\($0.delta)  \($0.text)" }.joined(separator: "\n"))
                }
            }
            Spacer()
            if let s = brain.stats, s.streak > 0 {
                VStack(spacing: 0) {
                    Text("🔥 \(s.streak)").font(.system(size: 15, weight: .bold, design: .rounded))
                    Text(L("ngày liên tiếp", "day streak")).font(.system(size: 9)).foregroundColor(.secondary)
                }
                .help(L("Chuỗi ngày đạt mục tiêu trên Todoist", "Your Todoist daily goal streak"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            if brain.isDemo {
                Label(L("Đang chạy chế độ demo — dữ liệu giả.", "Demo mode — sample data."), systemImage: "theatermasks")
                    .font(.caption).foregroundColor(.purple)
            }
            if brain.day.planned < brain.target {
                HStack(alignment: .top, spacing: 8) {
                    Text("📝")
                    Text(L("Hôm nay mới có \(brain.day.planned)/\(brain.target) việc. Thêm việc quan trọng nhất trước nhé!",
                           "Only \(brain.day.planned)/\(brain.target) tasks planned. Add the most important one first!"))
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
            }
            AddTaskRow(brain: brain, state: state)
            if let next = brain.day.next {
                FrogCard(task: next, brain: brain, prefs: prefs)
            }
            if prefs.useCalendar {
                CalendarCard(brain: brain, prefs: prefs)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if !brain.day.overdue.isEmpty {
                        sectionTitle(L("Quá hạn", "Overdue"), count: brain.day.overdue.count, color: .red) {
                            if brain.day.overdue.contains(where: { !$0.isRecurring }) {
                                Button(L("Dời hết vào hôm nay", "Move all to today")) { brain.pullOverdueToToday() }
                                    .buttonStyle(.link).font(.caption)
                            }
                        }
                        ForEach(brain.day.overdue) { TaskRow(task: $0, brain: brain, state: state, overdue: true) }
                    }
                    sectionTitle(L("Hôm nay", "Today"), count: brain.day.today.count, color: .primary) { EmptyView() }
                    if brain.day.today.isEmpty {
                        Text(L("Chưa có việc nào cho hôm nay.", "Nothing planned for today yet."))
                            .font(.callout).foregroundColor(.secondary).padding(.vertical, 4)
                    }
                    ForEach(brain.day.today) { TaskRow(task: $0, brain: brain, state: state, overdue: false) }
                    if !brain.day.completed.isEmpty {
                        DisclosureGroup {
                            ForEach(brain.day.completed) { t in
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                                    Text(t.title).strikethrough().foregroundColor(.secondary).lineLimit(1)
                                    Spacer()
                                }
                                .padding(.vertical, 2)
                            }
                        } label: {
                            Text(L("Đã xong hôm nay (\(brain.day.completed.count))", "Done today (\(brain.day.completed.count))"))
                                .font(.caption.bold()).foregroundColor(.green)
                        }
                        .padding(.top, 6)
                    }
                }
            }
            .frame(maxHeight: 220)
            if let e = brain.errorText {
                Text("⚠️ " + e).font(.caption).foregroundColor(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
    }

    private func sectionTitle<Trailing: View>(_ title: String, count: Int, color: Color, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text("\(title) · \(count)").font(.caption.bold()).foregroundColor(color)
            Spacer()
            trailing()
        }
        .padding(.top, 6)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let f = brain.focus {
                Button {
                    brain.stopFocus()
                } label: {
                    Label(f.isBreak ? L("Dừng nghỉ", "End break") : L("Dừng tập trung", "Stop focus"), systemImage: "stop.fill")
                }
            } else {
                Button {
                    brain.startFocus(nil)
                    close()
                } label: {
                    Label(L("Tập trung \(prefs.focusMinutes)'", "Focus \(prefs.focusMinutes)'"), systemImage: "timer")
                }
                .disabled(!brain.hasToken)
            }
            Spacer()
            if brain.loading {
                ProgressView().controlSize(.small)
            } else if let d = brain.lastSync {
                Text(DayMath.timeString(d)).font(.caption2).foregroundColor(.secondary)
                    .help(L("Lần đồng bộ cuối", "Last sync"))
            }
            Button { brain.refreshSoon() } label: { Image(systemName: "arrow.clockwise") }
                .help(L("Làm mới", "Refresh"))
            Button { openTodoist() } label: { Image(systemName: "checklist") }
                .help(L("Mở Todoist", "Open Todoist"))
            Button { brain.openSettings?() } label: { Image(systemName: "gearshape") }
                .help(L("Cài đặt", "Settings"))
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func openTodoist() {
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.todoist.mac.Todoist") {
            NSWorkspace.shared.openApplication(at: app, configuration: .init())
        } else if let url = URL(string: "https://app.todoist.com/app/today") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct FrogCard: View {
    let task: TodoTask
    @ObservedObject var brain: Brain
    @ObservedObject var prefs: Prefs

    var body: some View {
        HStack(spacing: 10) {
            Text("🐸").font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Làm ngay việc này", "Do this first")).font(.caption2.bold()).foregroundColor(.secondary)
                Text(task.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
            }
            Spacer()
            if brain.focus == nil {
                Button("▶︎ \(prefs.focusMinutes)'") { brain.startFocus(task) }
                    .buttonStyle(PillButtonStyle(primary: true))
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.green.opacity(0.10)))
    }
}

struct TaskRow: View {
    let task: TodoTask
    @ObservedObject var brain: Brain
    @ObservedObject var state: BoardState
    let overdue: Bool
    @State private var hover = false
    @State private var confirmDelete: Bool

    /// `confirming` starts the row in its delete-confirmation state (used for snapshots).
    init(task: TodoTask, brain: Brain, state: BoardState, overdue: Bool, confirming: Bool = false) {
        self.task = task
        self.brain = brain
        self.state = state
        self.overdue = overdue
        _confirmDelete = State(initialValue: confirming)
    }

    private var stuckDays: Int? { brain.stuck.first { $0.task.id == task.id }?.days }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            row
            if confirmDelete {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Lines.confirmDelete(task))
                        .font(.caption).foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button(L("Huỷ", "Cancel")) { confirmDelete = false }
                    Button(L("Xoá", "Delete")) {
                        confirmDelete = false
                        brain.delete(task)
                    }
                    .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
                .padding(.leading, 24)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(confirmDelete ? Color.red.opacity(0.07) : (hover ? Color.primary.opacity(0.05) : .clear)))
        .onHover { inside in
            hover = inside
            if !inside { confirmDelete = false }
        }
    }

    private var row: some View {
        HStack(alignment: .top, spacing: 8) {
            Button { brain.complete(task) } label: {
                Image(systemName: hover ? "checkmark.circle" : "circle")
                    .font(.system(size: 16))
                    .foregroundColor(PriorityStyle.color(task.uiPriority))
            }
            .buttonStyle(.plain)
            .help(L("Hoàn thành", "Complete"))
            VStack(alignment: .leading, spacing: 1) {
                Text(task.title).font(.system(size: 13)).lineLimit(2)
                HStack(spacing: 6) {
                    if let time = task.dueTime {
                        Label(DayMath.timeString(time), systemImage: "clock")
                    }
                    if overdue, let d = task.dueDay {
                        Label(DayMath.daysAgo(d), systemImage: "calendar").foregroundColor(.red)
                    }
                    if let n = stuckDays {
                        Text(L("⏳ dời \(n) ngày", "⏳ \(n) days")).foregroundColor(.orange)
                            .help(L("Việc này cứ bị dời mãi — thử chia nhỏ (✂️)", "This keeps getting postponed — try splitting it (✂️)"))
                    }
                    if task.isRecurring { Image(systemName: "repeat") }
                    ForEach(task.labels ?? [], id: \.self) { Text("@\($0)") }
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }
            Spacer(minLength: 4)
            if hover {
                Button { brain.startFocus(task) } label: { Image(systemName: "play.fill") }
                    .buttonStyle(.borderless).help(L("Tập trung vào việc này", "Focus on this"))
                Button { state.breakdown = task } label: { Image(systemName: "scissors") }
                    .buttonStyle(.borderless).help(L("Chia nhỏ thành các bước", "Split into small steps"))
                if !task.isRecurring {
                    Button { brain.reschedule(task, to: overdue ? "today" : "tomorrow") } label: {
                        Image(systemName: overdue ? "arrow.down.to.line" : "arrow.right.to.line")
                    }
                    .buttonStyle(.borderless)
                    .help(overdue ? L("Dời vào hôm nay", "Move to today") : L("Dời sang mai", "Move to tomorrow"))
                }
                Button { confirmDelete = true } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .foregroundColor(.red.opacity(0.8))
                    .help(L("Xoá việc", "Delete task"))
            }
        }
    }
}

struct AddTaskRow: View {
    @ObservedObject var brain: Brain
    @ObservedObject var state: BoardState
    @State private var text = ""
    @State private var due: DueChoice = .today
    @State private var priority = 1
    @State private var busy = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                TextField(due == .smart ? L("vd: Gọi khách 3pm p1 #Work", "e.g. Call client 3pm p1 #Work")
                                        : L("Thêm việc… (Enter để lưu)", "Add a task… (Enter to save)"), text: $text)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit(save)
                    .disabled(busy)
                Button(action: save) {
                    if busy { ProgressView().controlSize(.small) } else { Image(systemName: "plus.circle.fill").font(.title3) }
                }
                .buttonStyle(.borderless)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || busy)
            }
            HStack(spacing: 8) {
                Picker("", selection: $due) {
                    ForEach(DueChoice.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                if due != .smart {
                    Picker("", selection: $priority) {
                        Text("P1").tag(4)
                        Text("P2").tag(3)
                        Text("P3").tag(2)
                        Text("P4").tag(1)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                Spacer()
                Text("⌃⌥T").font(.caption2).foregroundColor(.secondary)
                    .help(L("Phím tắt mở bảng việc từ bất kỳ đâu", "Global shortcut to open this board"))
            }
            .controlSize(.small)
        }
        .onChange(of: state.focusAddToken) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focused = true }
        }
    }

    private func save() {
        let t = text
        guard !t.trimmingCharacters(in: .whitespaces).isEmpty, !busy else { return }
        busy = true
        Task {
            if await brain.add(t, due: due, priority: priority) { text = "" }
            busy = false
            focused = true
        }
    }
}

struct TokenSetupView: View {
    @ObservedObject var brain: Brain
    @ObservedObject var prefs: Prefs
    @State private var token = ""
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker(L("Ngôn ngữ", "Language"), selection: $prefs.lang) {
                ForEach(Lang.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(L("Kết nối Todoist", "Connect Todoist")).font(.headline)
            Text(L("Mở Todoist → Cài đặt → Tích hợp → Developer, sao chép “API token” rồi dán vào đây. Token được lưu an toàn trong Keychain của máy.",
                   "Open Todoist → Settings → Integrations → Developer, copy the “API token” and paste it here. It is stored safely in your macOS Keychain."))
                .font(.callout).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Link(L("Mở trang lấy token ↗", "Open the token page ↗"),
                 destination: URL(string: "https://app.todoist.com/app/settings/integrations/developer")!)
                .font(.callout)
            SecureField("API token", text: $token)
                .textFieldStyle(.roundedBorder)
                .onSubmit(connect)
            HStack {
                Button(action: connect) {
                    if busy { ProgressView().controlSize(.small) } else { Text(L("Lưu & kết nối", "Save & connect")) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(token.isEmpty || busy)
                Button(L("Xem thử (demo)", "Try demo")) { brain.useDemo() }
            }
            if let e = brain.errorText {
                Text("⚠️ " + e).font(.caption).foregroundColor(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func connect() {
        busy = true
        Task {
            if await brain.setToken(token) { token = "" }
            busy = false
        }
    }
}

/// Shows the board in a popover attached to the pet (or the menu bar icon).
@MainActor
final class BoardController: NSObject, NSPopoverDelegate {
    let popover = NSPopover()
    let state = BoardState()
    var onShownChanged: ((Bool) -> Void)?

    init(brain: Brain, prefs: Prefs) {
        super.init()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        var view = BoardView(brain: brain, prefs: prefs, state: state)
        view.close = { [weak self] in self?.popover.performClose(nil) }
        let host = NSHostingController(rootView: view)
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
    }

    var isShown: Bool { popover.isShown }

    func show(relativeTo view: NSView, focusAdd: Bool) {
        NSApp.activate(ignoringOtherApps: true)
        if !popover.isShown {
            popover.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
        }
        popover.contentViewController?.view.window?.makeKey()
        if focusAdd { state.focusAddToken = UUID() }
    }

    func toggle(relativeTo view: NSView) {
        if popover.isShown { popover.performClose(nil) } else { show(relativeTo: view, focusAdd: false) }
    }

    nonisolated func popoverDidShow(_ notification: Notification) {
        MainActor.assumeIsolated { onShownChanged?(true) }
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            state.breakdown = nil
            onShownChanged?(false)
        }
    }
}
