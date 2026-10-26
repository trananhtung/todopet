import AppKit
import SwiftUI

/// The pet's diary: what it said, what it held back, and why.
struct LogView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all, reminders, quiet, pet

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: L("Tất cả", "All")
            case .reminders: L("Nhắc & quậy", "Reminders")
            case .quiet: L("Im lặng", "Held back")
            case .pet: L("Pet", "Pet")
            }
        }

        func includes(_ k: LogEntry.Kind) -> Bool {
            switch self {
            case .all: true
            case .reminders: [.bubble, .response, .antic].contains(k)
            case .quiet: [.hold, .flow, .meeting, .focus].contains(k)
            case .pet: [.mood, .life, .distraction].contains(k)
            }
        }
    }

    @ObservedObject var log: PetLog
    @ObservedObject var state: BoardState
    @State private var day = DayMath.key(Date())
    @State private var filter: Filter = .all
    @State private var copied = false

    private var entries: [LogEntry] { day == DayMath.key(Date()) ? log.today : log.load(day: day) }

    private func dayLabel(_ key: String) -> String {
        let today = DayMath.key(Date())
        switch DayMath.daysBetween(key, today) {
        case 0: return L("Hôm nay", "Today")
        case 1: return L("Hôm qua", "Yesterday")
        default: return key
        }
    }

    var body: some View {
        let all = entries
        let shown = all.filter { filter.includes($0.kind) }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button { state.showLog = false } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                Text(L("📜 Nhật ký pet", "📜 Pet diary")).font(.headline)
                Spacer()
                Picker("", selection: $day) {
                    ForEach(log.days().prefix(14), id: \.self) { Text(dayLabel($0)).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            Text(LogSummary(all).text)
                .font(.caption).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Picker("", selection: $filter) {
                ForEach(Filter.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 5) {
                    if shown.isEmpty {
                        Text(L("Chưa có gì trong nhật ký.", "Nothing in the diary yet."))
                            .font(.callout).foregroundColor(.secondary).padding(.vertical, 8)
                    }
                    ForEach(shown.sorted { $0.time > $1.time }) { row($0) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 300)
            HStack {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(PetLog.export(all, day: day), forType: .string)
                    copied = true
                } label: {
                    Label(copied ? L("Đã sao chép ✔︎", "Copied ✔︎") : L("Sao chép", "Copy"), systemImage: "doc.on.doc")
                }
                .help(L("Sao chép cả ngày để dán cho Claude khi muốn chỉnh pet", "Copy the whole day to paste into Claude when tuning the pet"))
                Spacer()
                if let folder = log.folder {
                    Button { NSWorkspace.shared.open(folder) } label: { Label(L("Mở thư mục", "Open folder"), systemImage: "folder") }
                }
            }
            .buttonStyle(.borderless)
            .font(.callout)
            Text(L("Chỉ lưu trên máy này, giữ 14 ngày. Dán cho Claude khi muốn chỉnh ngưỡng nhắc.",
                   "Stored on this Mac only, kept 14 days. Paste it into Claude when you want to tune the pet."))
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding(14)
        .onChange(of: day) { _, _ in copied = false }
    }

    private func row(_ e: LogEntry) -> some View {
        let quiet = [.hold, .flow, .meeting, .focus, .system, .response].contains(e.kind)
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(DayMath.timeString(e.time))
                .font(.caption.monospacedDigit()).foregroundColor(.secondary)
                .frame(width: 38, alignment: .leading)
            Text(e.kind.icon).font(.caption)
            Text(e.text)
                .font(.caption)
                .foregroundColor(quiet ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}
