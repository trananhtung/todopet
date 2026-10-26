import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var prefs: Prefs
    @ObservedObject var brain: Brain
    @State private var token = ""
    @State private var busy = false
    @State private var message: String?
    @State private var claudeKey = ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private func hour(_ h: Int) -> String { String(format: "%02d:00", h) }

    var body: some View {
        Form {
            Section(L("Chung", "General")) {
                Picker(L("Ngôn ngữ", "Language"), selection: $prefs.lang) {
                    ForEach(Lang.allCases) { Text($0.label).tag($0) }
                }
                TextField(L("Tên pet", "Pet name"), text: $prefs.petName)
                HStack {
                    Text(L("Kích thước", "Size"))
                    Slider(value: $prefs.petScale, in: 0.7...1.6, step: 0.1)
                    Text(String(format: "%.0f%%", prefs.petScale * 100)).monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                Toggle(L("Âm thanh", "Sounds"), isOn: $prefs.soundOn)
                Toggle(L("Khi nổi cáu thì đuổi theo con trỏ chuột", "Chase the mouse cursor when grumpy"), isOn: $prefs.chaseWhenAngry)
                Toggle(L("Quậy khi bạn lười (càu nhàu, diễu hành với biển, đứng chắn màn hình)",
                         "Mischief when you slack (grumbling, sign parade, standing in the way)"), isOn: $prefs.antics)
                Toggle(L("Pet nói thành tiếng (giọng Linh của macOS)", "Pet speaks out loud (macOS voice)"), isOn: $prefs.voiceOn)
                if prefs.voiceOn {
                    Button(L("Nghe thử", "Test voice")) { Voice.shared.say(L("Ê! Làm việc đi chứ!", "Hey! Get to work!")) }
                }
                Toggle(L("Mở cùng macOS", "Open at login"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            message = error.localizedDescription
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }

            Section("Todoist") {
                if brain.hasToken && !brain.isDemo {
                    HStack {
                        Label(L("Đã kết nối", "Connected"), systemImage: "checkmark.seal.fill").foregroundColor(.green)
                        Spacer()
                        Button(L("Ngắt kết nối", "Disconnect"), role: .destructive) { brain.removeToken() }
                    }
                }
                SecureField(brain.hasToken && !brain.isDemo ? L("Token mới (tuỳ chọn)", "New token (optional)") : "API token", text: $token)
                HStack {
                    Button(L("Lưu token", "Save token")) {
                        busy = true
                        Task {
                            let ok = await brain.setToken(token)
                            message = ok ? L("Đã kết nối ✔︎", "Connected ✔︎") : (brain.errorText ?? L("Không kết nối được", "Could not connect"))
                            if ok { token = "" }
                            busy = false
                        }
                    }
                    .disabled(token.isEmpty || busy)
                    Link(L("Lấy token ↗", "Get token ↗"), destination: URL(string: "https://app.todoist.com/app/settings/integrations/developer")!)
                    if busy { ProgressView().controlSize(.small) }
                }
                TextField(L("Bộ lọc “việc của tôi hôm nay”", "“My day” filter"), text: $prefs.filterQuery)
                Text(L("Cú pháp bộ lọc Todoist, vd: (today | overdue) & #Công việc", "Todoist filter syntax, e.g. (today | overdue) & #Work"))
                    .font(.caption).foregroundColor(.secondary)
            }

            Section(L("Nhịp làm việc", "Work rhythm")) {
                Stepper(L("Số việc cần lên kế hoạch mỗi ngày: \(prefs.dailyTarget)", "Tasks to plan each day: \(prefs.dailyTarget)"),
                        value: $prefs.dailyTarget, in: 1...10)
                Stepper(L("Bắt đầu làm việc: \(hour(prefs.workStart))", "Work starts: \(hour(prefs.workStart))"),
                        value: $prefs.workStart, in: 0...(max(0, prefs.workEnd - 1)))
                Stepper(L("Kết thúc: \(hour(prefs.workEnd))", "Work ends: \(hour(prefs.workEnd))"),
                        value: $prefs.workEnd, in: (prefs.workStart + 1)...24)
                Stepper(L("Hạn lên kế hoạch: \(hour(prefs.planDeadline))", "Plan by: \(hour(prefs.planDeadline))"),
                        value: $prefs.planDeadline, in: prefs.workStart...max(prefs.workStart, prefs.workEnd))
                Toggle(L("Làm việc Thứ 7", "Work on Saturday"), isOn: $prefs.workSaturday)
                Toggle(L("Làm việc Chủ nhật", "Work on Sunday"), isOn: $prefs.workSunday)
                Stepper(L("Nhắc việc mỗi \(prefs.remindEvery) phút", "Nudge every \(prefs.remindEvery) min"),
                        value: $prefs.remindEvery, in: 15...180, step: 15)
                Stepper(L("Phiên tập trung: \(prefs.focusMinutes) phút", "Focus session: \(prefs.focusMinutes) min"),
                        value: $prefs.focusMinutes, in: 5...90, step: 5)
                Stepper(L("Nghỉ giữa phiên: \(prefs.breakMinutes) phút", "Break: \(prefs.breakMinutes) min"),
                        value: $prefs.breakMinutes, in: 1...30)
            }

            Section(L("Chống xao nhãng", "Distractions")) {
                TextField(L("Ứng dụng gây xao nhãng", "Distracting apps"), text: $prefs.distractionApps)
                Text(L("Tên app cách nhau bởi dấu phẩy. Mở app này hơn 2 phút trong giờ làm, pet sẽ cáu.",
                       "Comma-separated app names. Using one for 2+ minutes during work hours makes the pet grumpy."))
                    .font(.caption).foregroundColor(.secondary)
                Toggle(L("Theo dõi trang web trong trình duyệt", "Watch websites in the browser"), isOn: $prefs.watchBrowsers)
                TextField(L("Trang web gây xao nhãng", "Distracting websites"), text: $prefs.distractionSites)
                    .disabled(!prefs.watchBrowsers)
                Text(L("Tên miền cách nhau bởi dấu phẩy (gồm cả tên miền con), hoặc một phần địa chỉ như youtube.com/shorts. Hỗ trợ Safari, Chrome, Arc, Edge, Brave, Cốc Cốc… (không hỗ trợ Firefox). macOS sẽ hỏi quyền một lần cho mỗi trình duyệt; pet chỉ đọc địa chỉ tab đang mở, không lưu lại.",
                       "Comma-separated domains (subdomains included), or part of an address like youtube.com/shorts. Works with Safari, Chrome, Arc, Edge, Brave… (not Firefox). macOS asks once per browser; the pet only reads the active tab's address and never stores it."))
                    .font(.caption).foregroundColor(.secondary)
                if !brain.browserDenied.isEmpty {
                    HStack {
                        Text(L("Chưa cấp quyền: ", "No access: ") + brain.browserDenied.joined(separator: ", "))
                            .font(.caption).foregroundColor(.orange)
                        Spacer()
                        Button(L("Mở quyền Automation", "Open Automation settings")) {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        Button(L("Thử lại", "Retry")) { brain.retryBrowsers() }
                    }
                }
            }

            Section(L("Lịch", "Calendar")) {
                Toggle(L("Đọc Lịch của macOS (gồm tài khoản Google, Outlook đã thêm vào Lịch)", "Read the macOS Calendar (incl. Google/Outlook accounts added to it)"),
                       isOn: $prefs.useCalendar)
                    .onChange(of: prefs.useCalendar) { _, on in
                        if on, brain.calendarAccess == .notDetermined { brain.requestCalendarAccess() }
                    }
                if prefs.useCalendar {
                    HStack {
                        switch brain.calendarAccess {
                        case .granted: Label(L("Đã có quyền", "Access granted"), systemImage: "checkmark.seal.fill").foregroundColor(.green)
                        case .notDetermined:
                            Text(L("Chưa cấp quyền", "Not granted yet")).foregroundColor(.secondary)
                            Spacer()
                            Button(L("Cho phép", "Allow")) { brain.requestCalendarAccess() }
                        case .denied:
                            Text(L("Bị từ chối", "Denied")).foregroundColor(.orange)
                            Spacer()
                            Button(L("Mở cài đặt", "Open settings")) { CalendarWatcher.openPrivacySettings() }
                        }
                    }
                    Toggle(L("Ngày nhiều họp thì giảm số việc cần làm", "Lower the daily target on meeting-heavy days"), isOn: $prefs.adaptTarget)
                    Stepper(L("Nhắc trước giờ họp \(prefs.meetingLead) phút", "Remind \(prefs.meetingLead) min before meetings"),
                            value: $prefs.meetingLead, in: 1...30)
                    Text(L("Khi đang họp pet im lặng và không tính là bạn lười. Cứ 2 giờ trống ≈ 1 việc quan trọng.",
                           "During meetings the pet stays quiet and doesn't count it as slacking. About 1 important task per 2 free hours."))
                        .font(.caption).foregroundColor(.secondary)
                }
            }

            Section(L("Việc bị dời mãi", "Postponed tasks")) {
                Stepper(L("Coi là “bị dời mãi” sau \(prefs.stuckDays) ngày", "Flag a task after \(prefs.stuckDays) days on your list"),
                        value: $prefs.stuckDays, in: 2...10)
                if brain.hasClaudeKey {
                    HStack {
                        Label(L("Đã có API key Claude", "Claude API key saved"), systemImage: "sparkles").foregroundColor(.green)
                        Spacer()
                        Button(L("Xoá key", "Remove key"), role: .destructive) { brain.setClaudeKey(nil) }
                    }
                }
                SecureField(L("API key Claude (tuỳ chọn, để gợi ý cách chia nhỏ)", "Claude API key (optional, for split suggestions)"), text: $claudeKey)
                HStack {
                    Button(L("Lưu key", "Save key")) {
                        brain.setClaudeKey(claudeKey)
                        claudeKey = ""
                    }
                    .disabled(claudeKey.isEmpty)
                    Link(L("Lấy API key ↗", "Get an API key ↗"), destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                }
                TextField(L("Model Claude", "Claude model"), text: $prefs.claudeModel)
                Text(L("Key lưu trong Keychain. Khi bạn bấm “Nhờ Claude gợi ý”, tên và ghi chú của việc được gửi tới Claude API (tính phí theo lượt dùng, khoảng 1–2 xu Mỹ mỗi lần).",
                       "The key lives in your Keychain. When you press “Ask Claude”, the task's title and notes are sent to the Claude API (billed per use, roughly 1–2 US cents each time)."))
                    .font(.caption).foregroundColor(.secondary)
            }

            if let message {
                Text(message).font(.callout)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 640)
    }
}
