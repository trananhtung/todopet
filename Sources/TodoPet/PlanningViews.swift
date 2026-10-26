import AppKit
import SwiftUI

/// Today's meetings, free time and suggested time blocks.
struct CalendarCard: View {
    @ObservedObject var brain: Brain
    @ObservedObject var prefs: Prefs

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch brain.calendarAccess {
            case .notDetermined:
                HStack(alignment: .top) {
                    Text("📅")
                    Text(L("Cho pet xem Lịch để biết giờ họp và giờ trống.", "Let the pet read your Calendar to know meetings and free time."))
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(L("Cho phép", "Allow")) { brain.requestCalendarAccess() }
                }
            case .denied:
                HStack(alignment: .top) {
                    Text("📅")
                    Text(L("Pet chưa được đọc Lịch.", "The pet can't read your Calendar."))
                        .font(.callout)
                    Spacer()
                    Button(L("Mở cài đặt", "Open settings")) { CalendarWatcher.openPrivacySettings() }
                }
            case .granted:
                meetings
            }
            if !brain.suggestions.isEmpty {
                Text(L("Gợi ý khung giờ", "Suggested time blocks"))
                    .font(.caption.bold()).foregroundColor(.secondary).padding(.top, 2)
                ForEach(brain.suggestions) { s in
                    HStack(spacing: 8) {
                        Text("\(DayMath.timeString(s.start))–\(DayMath.timeString(s.end))")
                            .font(.caption.monospacedDigit()).foregroundColor(.secondary)
                        Text(s.task.title).font(.callout).lineLimit(1)
                        Spacer()
                        Button(L("Đặt giờ", "Set time")) { brain.schedule(s) }
                            .buttonStyle(.link).font(.caption)
                            .help(L("Đặt giờ này cho việc trong Todoist", "Give the task this time in Todoist"))
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.blue.opacity(0.08)))
    }

    @ViewBuilder private var meetings: some View {
        let now = Date()
        if let cur = CalendarMath.current(brain.events, at: now) {
            meetingRow(cur, label: L("Đang họp đến \(DayMath.timeString(cur.end))", "In a meeting until \(DayMath.timeString(cur.end))"))
        } else if let next = CalendarMath.next(brain.events, after: now) {
            meetingRow(next, label: L("Họp tiếp lúc \(DayMath.timeString(next.start))", "Next meeting at \(DayMath.timeString(next.start))"))
        } else {
            Text("📅 " + L("Không còn cuộc họp nào hôm nay", "No more meetings today")).font(.callout)
        }
        Text(summary(now)).font(.caption).foregroundColor(.secondary)
    }

    private func meetingRow(_ e: CalEvent, label: String) -> some View {
        HStack(spacing: 8) {
            Text("📅")
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.caption2.bold()).foregroundColor(.secondary)
                Text(e.title).font(.callout).lineLimit(1)
            }
            Spacer()
            if let url = e.joinURL {
                Button(L("Vào họp ↗", "Join ↗")) { NSWorkspace.shared.open(url) }
                    .buttonStyle(PillButtonStyle(primary: true))
            }
        }
    }

    private func summary(_ now: Date) -> String {
        let end = DayMath.at(hour: prefs.workEnd, on: now)
        let from = max(now, DayMath.at(hour: prefs.workStart, on: now))
        let free = CalendarMath.freeMinutes(brain.events, from: from, to: end)
        var s = L("Còn trống \(CalendarMath.hoursText(max(0, free))) đến \(DayMath.timeString(end))",
                  "\(CalendarMath.hoursText(max(0, free))) free until \(DayMath.timeString(end))")
        if brain.target < prefs.dailyTarget {
            s += L(" · nhiều họp nên mục tiêu hôm nay: \(brain.target) việc", " · busy day, so today's target: \(brain.target)")
        }
        return s
    }
}

/// Splits a task into small first steps (by hand, from a template, or with Claude) and adds them as sub-tasks.
struct BreakdownView: View {
    struct Step: Identifiable {
        let id = UUID()
        var text: String
    }

    let task: TodoTask
    @ObservedObject var brain: Brain
    @ObservedObject var state: BoardState
    @State private var steps: [Step]
    @State private var firstToday = true
    @State private var asking = false
    @State private var saving = false
    @State private var confirmDelete = false
    @State private var error: String?

    init(task: TodoTask, brain: Brain, state: BoardState, steps: [String] = ["", "", ""]) {
        self.task = task
        self.brain = brain
        self.state = state
        _steps = State(initialValue: steps.map { Step(text: $0) })
    }

    private var filled: [String] {
        steps.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private var placeholders: [String] {
        [L("vd: Mở file và đọc lại yêu cầu (10')", "e.g. Open the file and reread the brief (10')"),
         L("vd: Viết dàn ý 5 gạch đầu dòng", "e.g. Write a 5-bullet outline"),
         L("vd: Làm phần dễ nhất trong 25'", "e.g. Do the easiest part in 25'")]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { state.breakdown = nil } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                Text(L("Chia nhỏ việc ✂️", "Split a task ✂️")).font(.headline)
            }
            Text(task.title).font(.system(size: 14, weight: .semibold)).lineLimit(3)
            if let s = brain.stuck.first(where: { $0.task.id == task.id }) {
                Text("⏳ " + L("Đã nằm trong danh sách \(s.days) ngày", "On your list for \(s.days) days"))
                    .font(.caption).foregroundColor(.orange)
            }
            Text(L("Việc to hay mơ hồ thì khó bắt đầu. Mỗi bước nên xong trong 15–30 phút, bước 1 càng dễ càng tốt.",
                   "Big or vague tasks are hard to start. Each step should take 15–30 minutes; make step 1 as easy as possible."))
                .font(.callout).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button {
                    Task { await askClaude() }
                } label: {
                    if asking { ProgressView().controlSize(.small) } else { Label(L("Nhờ Claude gợi ý", "Ask Claude"), systemImage: "sparkles") }
                }
                .disabled(asking || !brain.hasClaudeKey)
                .help(L("Gửi tên và ghi chú của việc tới Claude API", "Sends the task's title and notes to the Claude API"))
                Button(L("Mẫu nhanh", "Quick template")) { fillTemplate() }
            }
            if !brain.hasClaudeKey {
                Text(L("Thêm API key Claude trong Cài đặt để nhận gợi ý tự động.", "Add a Claude API key in Settings for automatic suggestions."))
                    .font(.caption).foregroundColor(.secondary)
            }

            ForEach($steps) { $step in
                let i = steps.firstIndex { $0.id == step.id } ?? 0
                HStack(spacing: 6) {
                    Text("\(i + 1).").font(.callout.monospacedDigit()).foregroundColor(.secondary).frame(width: 18, alignment: .trailing)
                    TextField(i < placeholders.count ? placeholders[i] : L("Bước tiếp theo", "Next step"), text: $step.text)
                        .textFieldStyle(.roundedBorder)
                    if steps.count > 1 {
                        Button { steps.removeAll { $0.id == step.id } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                }
            }
            if steps.count < 6 {
                Button { steps.append(Step(text: "")) } label: { Label(L("Thêm bước", "Add a step"), systemImage: "plus") }
                    .buttonStyle(.borderless).font(.callout)
            }
            Toggle(L("Đưa bước 1 vào kế hoạch hôm nay", "Put step 1 on today's plan"), isOn: $firstToday)
                .font(.callout)
            if let error {
                Text("⚠️ " + error).font(.caption).foregroundColor(.red).fixedSize(horizontal: false, vertical: true)
            }
            if confirmDelete {
                HStack(alignment: .firstTextBaseline) {
                    Text(Lines.confirmDelete(task)).font(.caption).foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(L("Huỷ", "Cancel")) { confirmDelete = false }
                    Button(L("Xoá", "Delete")) {
                        brain.delete(task)
                        state.breakdown = nil
                    }
                    .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.07)))
            }
            HStack {
                Button(L("Bỏ khỏi kế hoạch", "Drop from plan")) {
                    brain.unplan(task)
                    state.breakdown = nil
                }
                .help(L("Bỏ hạn của việc (vẫn giữ trong Todoist)", "Removes the due date (the task stays in Todoist)"))
                Button { confirmDelete = true } label: { Image(systemName: "trash") }
                    .foregroundColor(.red)
                    .help(L("Xoá việc", "Delete task"))
                Spacer()
                Button {
                    save()
                } label: {
                    if saving { ProgressView().controlSize(.small) } else { Text(L("Thêm vào Todoist", "Add to Todoist")) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(filled.isEmpty || saving)
            }
        }
        .padding(14)
    }

    private func fillTemplate() {
        let title = TextClean.short(task.title, 40)
        steps = [
            Step(text: L("Chuẩn bị mọi thứ cần cho “\(title)” (10')", "Gather what you need for “\(title)” (10')")),
            Step(text: L("Làm bản nháp đầu tiên thật nhanh (25')", "Make a quick first draft (25')")),
            Step(text: L("Hoàn thiện và đánh dấu xong", "Polish it and mark it done")),
        ]
    }

    private func askClaude() async {
        asking = true
        error = nil
        do {
            steps = try await brain.suggestSteps(for: task).map { Step(text: $0) }
        } catch {
            self.error = error.localizedDescription
        }
        asking = false
    }

    private func save() {
        saving = true
        error = nil
        Task {
            if await brain.split(task, into: filled, firstToday: firstToday) {
                state.breakdown = nil
            } else {
                error = brain.errorText ?? L("Không thêm được vào Todoist.", "Couldn't add to Todoist.")
            }
            saving = false
        }
    }
}
