import SwiftUI

/// The work day as a thin strip: meetings, timed tasks and now, with the load against the time left.
struct DayStripView: View {
    @ObservedObject var brain: Brain
    @ObservedObject var prefs: Prefs

    var body: some View {
        let l = brain.load
        let lanes = max(1, (brain.strip.map(\.lane).max() ?? 0) + 1)
        let level = DayLoadRules.level(l)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text("\(prefs.workStart)h").font(.caption2.monospacedDigit()).foregroundColor(.secondary)
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.07))
                        Rectangle().fill(Color.primary.opacity(0.06))
                            .frame(width: geo.size.width * brain.stripNow)
                        ForEach(brain.strip) { seg in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(seg.kind == .meeting ? Color.purple.opacity(0.65) : Color.blue.opacity(0.6))
                                .frame(width: max(3, geo.size.width * (seg.end - seg.start)), height: 6)
                                .offset(x: geo.size.width * seg.start, y: 2 + CGFloat(seg.lane) * 8)
                                .help("\(seg.kind == .meeting ? "📅" : "⏰") \(seg.title)")
                        }
                        Rectangle().fill(Color.red).frame(width: 1.5, height: geo.size.height)
                            .offset(x: geo.size.width * brain.stripNow)
                    }
                }
                .frame(height: CGFloat(lanes) * 8 + 2)
                Text("\(prefs.workEnd)h").font(.caption2.monospacedDigit()).foregroundColor(.secondary)
            }
            if l.capacity > 0 {
                HStack(spacing: 4) {
                    Circle().fill(color(level)).frame(width: 6, height: 6)
                    Text(L("~\(DayLoadRules.text(l.taskMinutes + l.meetingMinutes)) việc & họp / còn \(DayLoadRules.text(l.capacity))",
                           "~\(DayLoadRules.text(l.taskMinutes + l.meetingMinutes)) of tasks & meetings / \(DayLoadRules.text(l.capacity)) left"))
                        .font(.caption2).foregroundColor(level == .ok ? .secondary : color(level))
                    if level == .over {
                        Button(L("Dời bớt", "Lighten")) { brain.openWrapUp?(true) }
                            .buttonStyle(.link).font(.caption2)
                    }
                }
                .help(L("Việc không có thời lượng trong Todoist được tính \(prefs.defaultEstimate) phút",
                        "Tasks without a Todoist duration count as \(prefs.defaultEstimate) minutes"))
            }
        }
    }

    private func color(_ l: LoadLevel) -> Color {
        switch l {
        case .ok: .green
        case .tight: .orange
        case .over: .red
        }
    }
}

/// 📌 Pin my place: keep your spot with a one-line next step; it comes back after a break, a meeting or a detour.
struct PinRow: View {
    @ObservedObject var brain: Brain
    @State private var editing = false
    @State private var note = ""
    @FocusState private var focused: Bool

    var body: some View {
        if let p = brain.pinned {
            HStack(spacing: 6) {
                Text("📌")
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.note ?? p.taskTitle ?? L("Chỗ đang làm", "Your place")).font(.caption.bold()).lineLimit(1)
                    if let w = ResumeRules.whereText(p) { Text(w).font(.caption2).foregroundColor(.secondary).lineLimit(1) }
                }
                Spacer(minLength: 4)
                if p.url != nil || p.bundle != nil {
                    Button(L("Mở lại ↗", "Reopen ↗")) { brain.reopen(p) }.buttonStyle(.link).font(.caption)
                }
                Button { brain.clearPin() } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }
                    .buttonStyle(.borderless).help(L("Bỏ ghim", "Unpin"))
            }
        } else if editing {
            HStack(spacing: 6) {
                Text("📌")
                TextField(L("Bước tiếp theo là gì? (tuỳ chọn)", "What's the next step? (optional)"), text: $note)
                    .textFieldStyle(.roundedBorder).font(.caption)
                    .focused($focused)
                    .onSubmit(pin)
                Button(L("Ghim", "Pin"), action: pin).font(.caption)
                Button { editing = false } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
            }
            .onAppear { focused = true }
        } else if brain.workContext != nil || brain.day.next != nil {
            Button {
                editing = true
            } label: {
                HStack(spacing: 4) {
                    Text("📌 " + L("Ghim chỗ đang làm", "Pin my place")).font(.caption)
                    if let w = brain.workContext.flatMap(ResumeRules.whereText) {
                        Text("· " + w).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                    }
                }
            }
            .buttonStyle(.borderless)
            .help(L("Giữ chỗ bạn đang làm (ứng dụng, trang, việc) kèm bước tiếp theo; pet nhắc lại khi bạn quay về",
                    "Keep your spot (app, page, task) with a next step; the pet brings it back when you return"))
        }
    }

    private func pin() {
        brain.pinPlace(note: note)
        note = ""
        editing = false
    }
}

/// The shutdown ritual: today's wins, what to do with what's left, tomorrow's frog and a note, then rest.
/// `lighten` shows only the moves, for an overbooked day.
struct WrapUpView: View {
    @ObservedObject var brain: Brain
    @ObservedObject var state: BoardState
    let lighten: Bool
    @State private var moves: [String: WrapMove] = [:]
    @State private var frogId: String?
    @State private var note = ""
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(lighten ? L("⚖️ Dời bớt việc hôm nay", "⚖️ Lighten today") : L("🌙 Đóng ngày", "🌙 Wrap up"))
                    .font(.headline)
                Spacer()
                Button { state.wrapUp = nil } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }
                    .buttonStyle(.borderless)
            }
            if lighten {
                Text(Lines.overbooked(brain.load)).font(.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                wins
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if !brain.day.open.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L("Việc còn dở", "Still open")).font(.caption.bold()).foregroundColor(.secondary)
                            ForEach(brain.day.open) { t in moveRow(t) }
                        }
                    }
                    if !lighten { tomorrow }
                }
            }
            .frame(maxHeight: 280)
            HStack {
                if lighten {
                    Spacer()
                    Button(L("Áp dụng", "Apply")) { finish(done: false) }
                        .buttonStyle(PillButtonStyle(primary: true))
                } else {
                    Button(L("Lưu kế hoạch", "Save plan")) { finish(done: false) }
                        .buttonStyle(PillButtonStyle(primary: false))
                    Spacer()
                    Button(L("🌙 Xong ngày hôm nay", "🌙 Done for today")) { finish(done: true) }
                        .buttonStyle(PillButtonStyle(primary: true))
                        .help(L("Pet đi ngủ và im lặng tới đầu giờ làm hôm sau (họp và việc có giờ vẫn nhắc)",
                                "The pet sleeps and stays quiet until your next workday (meetings and timed tasks still come through)"))
                }
            }
        }
        .padding(14)
        .onAppear(perform: load)
    }

    @ViewBuilder private var wins: some View {
        let done = brain.day.completed
        VStack(alignment: .leading, spacing: 3) {
            if done.isEmpty {
                Text(L("Hôm nay chưa xong việc nào, không sao cả. Chọn một việc nhỏ cho mai nhé 🌱",
                       "Nothing finished today, and that's okay. Pick one small thing for tomorrow 🌱"))
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(L("Hôm nay bạn đã xong \(done.count) việc 🎉", "You finished \(done.count) task(s) today 🎉")).font(.callout.bold())
                ForEach(done.prefix(5)) { t in
                    Label(t.title, systemImage: "checkmark.circle.fill").font(.caption).lineLimit(1)
                        .foregroundColor(.green)
                }
                if done.count > 5 { Text("+\(done.count - 5)").font(.caption2).foregroundColor(.secondary) }
            }
        }
    }

    private func moveRow(_ t: TodoTask) -> some View {
        HStack(spacing: 6) {
            Text(t.title).font(.caption).lineLimit(1)
            Spacer(minLength: 4)
            if t.isRecurring {
                Label(L("lặp lại", "repeats"), systemImage: "repeat").font(.caption2).foregroundColor(.secondary)
                    .help(L("Việc lặp lại giữ lịch của nó", "Repeating tasks keep their schedule"))
            } else {
                Picker("", selection: Binding(get: { moves[t.id] ?? .keep }, set: { moves[t.id] = $0 })) {
                    ForEach(WrapMove.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.mini)
                .frame(width: 150)
            }
        }
    }

    @ViewBuilder private var tomorrow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Con ếch cho ngày mai 🐸", "Tomorrow's frog 🐸")).font(.caption.bold()).foregroundColor(.secondary)
            Picker("", selection: $frogId) {
                Text(L("Để mai tính", "Decide tomorrow")).tag(String?.none)
                ForEach(brain.day.open) { Text(TextClean.short($0.title, 44)).tag(String?.some($0.id)) }
            }
            .labelsHidden()
            Text(L("Lời nhắn cho mai (bắt đầu từ đâu?)", "A note for tomorrow (where to start?)")).font(.caption.bold()).foregroundColor(.secondary)
            TextField(L("vd: mở file báo cáo, viết phần kết luận", "e.g. open the report, write the conclusion"), text: $note)
                .textFieldStyle(.roundedBorder).font(.caption)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        let key = DayMath.key(WrapRules.nextWorkday(after: Date(), isWorkday: brain.prefs.isWorkday))
        if let p = brain.plans.plan(for: key) {
            frogId = p.frogId
            note = p.note ?? ""
        } else {
            frogId = brain.day.next?.id
        }
        if lighten {
            // Suggest moving the lowest-priority tasks without a time until the day fits.
            var over = brain.load.overBy
            for t in DaySnapshot.ranked(brain.day.today).reversed() where over > 0 && t.dueTime == nil && !t.isRecurring {
                moves[t.id] = .tomorrow
                over -= DayLoadRules.estimate(t, defaultMinutes: brain.prefs.defaultEstimate)
            }
        }
    }

    private func finish(done: Bool) {
        if lighten {
            brain.applyMoves(moves)
        } else {
            brain.applyWrapUp(moves: moves, frogId: frogId, note: note, done: done)
        }
        state.wrapUp = nil
    }
}
